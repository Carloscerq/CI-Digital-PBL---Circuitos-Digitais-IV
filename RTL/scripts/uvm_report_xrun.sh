#!/usr/bin/env bash
# ============================================================================
#  uvm_report_xrun.sh  --  run every UVM bench under Xcelium and write ONE
#                          Markdown report.
#
#  Xcelium counterpart of uvm_report.sh (which drives Questa/vsim). It does
#  NOT reimplement the xrun command line: it calls each bench's own
#  run_uvm.sh -- the scripts that already encode the right working directory
#  (several DUTs $readmemh their ROMs with CWD-relative paths), filelist,
#  top module and default test -- then collects every bench's verdict,
#  UVM_ERROR / UVM_FATAL / UVM_WARNING counts, wall-clock time and log path
#  into a single file.
#
#    ./uvm_report_xrun.sh                        # all benches -> sim_xrun/uvm_report.md
#    ./uvm_report_xrun.sh mac spi gcd            # just these
#    ./uvm_report_xrun.sh --out /tmp/uvm.md      # choose the report path
#    ./uvm_report_xrun.sh --elaborate           # build every bench, no simulation
#    ./uvm_report_xrun.sh -- +UVM_VERBOSITY=UVM_HIGH   # all, extra xrun args
#
#  Everything after a lone -- is forwarded to xrun (via run_uvm.sh) for every
#  bench. Each bench compiles into its own library under sim_xrun/, so runs
#  do not contaminate each other and a re-run is incremental.
#
#  Exit status is 0 only if every bench passed: a FAIL or a BLOCKED (built
#  OK, but no Xcelium licence) makes it non-zero, so it drops into CI.
# ============================================================================
set -uo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
rtl_root=$(cd -- "$script_dir/.." && pwd)

# ----------------------------------------------------------------------------
#  Bench table:  id | run_uvm.sh (relative to rtl_root) | default test
# ----------------------------------------------------------------------------
#  Same bench ids as uvm_vsim.sh / uvm_verilator.sh. The default test is only
#  for display -- run_uvm.sh already passes it -- so a compile failure still
#  shows which test was meant to run.
BENCHES=(
  "mac|mac/uvm/run_uvm.sh|mac_wide_random_test"
  "mlp|mlp_model/uvm/run_uvm.sh|mlp_directed_random_test"
  "spi|spi/uvm/run_uvm.sh|spi_directed_test"
  "gcd|gcd/uvm/gcd/run_uvm.sh|gcd_full_random_test"
  "euclidian_gcd|gcd/uvm/euclidian_gcd/run_uvm.sh|euclidian_gcd_random_test"
  "filtro_lms|LMS/uvm/run_uvm.sh|filtro_lms_regression_test"
  "perceptron|perceptron/uvm/run_uvm.sh|perceptron_wide_random_test"
  "spectrogram|spectrogram/uvm/run_uvm.sh|spectrogram_generator_directed_random_test"
  "cnn_mac_q8_16|cnn/uvm/mac_q8_16/run_uvm.sh|mac_q8_16_default_test"
  "cnn_line_buffer|cnn/uvm/line_buffer_3x3/run_uvm.sh|line_buffer_3x3_directed_random_test"
  "cnn_maxpool|cnn/uvm/maxpool_2x2/run_uvm.sh|maxpool_2x2_directed_random_test"
  "cnn_conv2d|cnn/uvm/conv2d_fsm/run_uvm.sh|conv2d_fsm_directed_random_test"
  "cnn_dense|cnn/uvm/dense_layer_fsm/run_uvm.sh|dense_layer_fsm_directed_random_test"
  "cnn_top|cnn/uvm/smma_cnn_top/run_uvm.sh|smma_cnn_top_directed_random_test"
  "fft|FFT/model_sim_four_modes/uvm/run_uvm.sh|preprocess_lms_fft_directed_test"
)
list_benches() { printf '%s\n' "${BENCHES[@]}" | cut -d'|' -f1; }

# ----------------------------------------------------------------------------
#  Arguments
# ----------------------------------------------------------------------------
benches=()
extra=()
elaborate=0
report=$rtl_root/sim_xrun/uvm_report.md
seen_sep=0
while [ $# -gt 0 ]; do
    arg=$1; shift
    if [ "$seen_sep" -eq 1 ]; then extra+=("$arg"); continue; fi
    case "$arg" in
        --)                     seen_sep=1 ;;
        --list)                 list_benches; exit 0 ;;
        --out)                  report=${1:?--out needs a path}; shift ;;
        --out=*)                report=${arg#--out=} ;;
        --elaborate|--compile-only) elaborate=1 ;;
        -h|--help)              sed -n '2,26p' "${BASH_SOURCE[0]}" | sed 's|^# \?||'; exit 0 ;;
        -*)                     echo "uvm_report_xrun.sh: unknown option '$arg'" >&2; exit 2 ;;
        *)                      benches+=("$arg") ;;
    esac
done

command -v xrun >/dev/null || { echo "uvm_report_xrun.sh: xrun not on PATH" >&2; exit 2; }

if [ ${#benches[@]} -eq 0 ]; then
    mapfile -t benches < <(list_benches)
fi

build_dir=$rtl_root/sim_xrun
mkdir -p "$build_dir" || { echo "uvm_report_xrun.sh: cannot create $build_dir" >&2; exit 2; }
mkdir -p "$(dirname -- "$report")" || { echo "uvm_report_xrun.sh: cannot create report dir" >&2; exit 2; }

# ----------------------------------------------------------------------------
#  Log parsing  (xrun exits 0 even on a failing test, so read the summary)
# ----------------------------------------------------------------------------
count_of() {  # <log> <label>  -> integer, or "" if the summary never printed
    grep -oE "^[[:space:]]*$2[[:space:]]*:[[:space:]]*[0-9]+" "$1" 2>/dev/null | tail -1 | grep -oE '[0-9]+$'
}
testname_of() {  # <log>
    grep -oE "Running test [A-Za-z0-9_]+" "$1" 2>/dev/null | tail -1 | awk '{print $3}'
}
fmt_hms() { printf '%d:%02d:%02d' $(( $1 / 3600 )) $(( ($1 % 3600) / 60 )) $(( $1 % 60 )); }

# ----------------------------------------------------------------------------
#  Run
# ----------------------------------------------------------------------------
rows=()
console=()
total_pass=0 total_fail=0 total_blocked=0
started=$(date +%s)

for b in "${benches[@]}"; do
    entry=""
    for e in "${BENCHES[@]}"; do [ "${e%%|*}" = "$b" ] && { entry=$e; break; }; done
    if [ -z "$entry" ]; then
        echo "uvm_report_xrun.sh: unknown bench '$b' (see --list)" >&2
        rows+=("| \`$b\` | – | ❌ FAIL | – | – | – | 0:00:00 | unknown bench id | – |")
        console+=("$(printf '  %-9s %-16s %s' FAIL "$b" 'unknown bench id')")
        total_fail=$((total_fail + 1))
        continue
    fi
    IFS='|' read -r _id run_rel def_test <<< "$entry"
    runscript=$rtl_root/$run_rel

    echo
    echo "############################################################"
    echo "#  $b"
    echo "############################################################"

    log=$build_dir/$b.log
    lib=$build_dir/xcelium_$b.d

    if [ ! -x "$runscript" ]; then
        echo "  missing runner: $runscript" | tee "$log"
        rows+=("| \`$b\` | ${def_test:-–} | ❌ FAIL | – | – | – | 0:00:00 | missing $run_rel | – |")
        console+=("$(printf '  %-9s %-16s %s' FAIL "$b" "missing $run_rel")")
        total_fail=$((total_fail + 1))
        continue
    fi

    # run_uvm.sh appends "$@" to its xrun line, so these land on xrun:
    #   -xmlibdirname  keeps each bench's compiled library separate (and lets a
    #                  re-run be incremental); absolute so the per-bench cd is
    #                  irrelevant.
    #   -elaborate     build only, no simulation, when --elaborate was given.
    run_args=(-xmlibdirname "$lib")
    [ "$elaborate" -eq 1 ] && run_args+=(-elaborate)
    run_args+=("${extra[@]+"${extra[@]}"}")

    # Run each run_uvm.sh from its own directory: four of them (mlp, spi,
    # perceptron, spectrogram) have no cd and use a bare -f <name>.files, so
    # they only work when CWD is that script's dir. The others cd themselves,
    # via an absolute $0, so starting there is harmless for them too.
    t0=$SECONDS
    ( cd -- "$(dirname -- "$runscript")" && exec "$runscript" "${run_args[@]}" ) 2>&1 | tee "$log"
    rc=${PIPESTATUS[0]}
    dt=$(( SECONDS - t0 ))

    err=$(count_of "$log" UVM_ERROR)
    fat=$(count_of "$log" UVM_FATAL)
    warn=$(count_of "$log" UVM_WARNING)
    tn=$(testname_of "$log"); tn=${tn:-$def_test}

    lic_hit=0
    grep -qiE '\*[EF],LIC|license (check|checkout|queu)|unable to (obtain|check ?out).*licen' "$log" && lic_hit=1
    build_err=0
    grep -qE '^[a-z_]*: \*[EF],' "$log" && build_err=1

    if [ "$elaborate" -eq 1 ]; then
        if [ "$rc" -eq 0 ] && [ "$build_err" -eq 0 ]; then
            verdict="PASS"; detail="elaborated (no simulation)"; total_pass=$((total_pass + 1))
        elif [ "$lic_hit" -eq 1 ]; then
            verdict="BLOCKED"; detail="no Xcelium licence"; total_blocked=$((total_blocked + 1))
        else
            verdict="FAIL"; detail="elaboration failed"; total_fail=$((total_fail + 1))
        fi
    elif [ -n "$err" ] && [ -n "$fat" ]; then
        if [ "$err" -ne 0 ] || [ "$fat" -ne 0 ]; then
            verdict="FAIL"; detail="UVM_ERROR=$err UVM_FATAL=$fat"; total_fail=$((total_fail + 1))
        else
            verdict="PASS"; detail="UVM_ERROR=0 UVM_FATAL=0"; total_pass=$((total_pass + 1))
        fi
    elif [ "$lic_hit" -eq 1 ]; then
        verdict="BLOCKED"; detail="built OK; no Xcelium simulation licence"; total_blocked=$((total_blocked + 1))
    elif [ "$build_err" -eq 1 ]; then
        verdict="FAIL"; detail="compile/elaboration failed"; total_fail=$((total_fail + 1))
    else
        verdict="FAIL"; detail="run did not finish (no UVM report summary)"; total_fail=$((total_fail + 1))
    fi

    icon="✅"; [ "$verdict" = "FAIL" ] && icon="❌"; [ "$verdict" = "BLOCKED" ] && icon="⚠️"
    log_rel=$(realpath --relative-to="$(dirname -- "$report")" "$log" 2>/dev/null || echo "$log")

    rows+=("| \`$b\` | ${tn:-–} | $icon $verdict | ${err:-–} | ${fat:-–} | ${warn:-–} | $(fmt_hms "$dt") | $detail | [log]($log_rel) |")
    console+=("$(printf '  %-9s %-16s %s' "$verdict" "$b" "$detail")")
done

wall=$(( $(date +%s) - started ))
overall="PASS"
[ "$total_blocked" -gt 0 ] && overall="BLOCKED"
[ "$total_fail" -gt 0 ] && overall="FAIL"

# ----------------------------------------------------------------------------
#  Report
# ----------------------------------------------------------------------------
git_rev=$(git -C "$rtl_root" rev-parse --short HEAD 2>/dev/null || echo "n/a")
git_branch=$(git -C "$rtl_root" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "n/a")
xrun_ver=$(xrun -version 2>/dev/null | head -1 | sed 's/^TOOL:[[:space:]]*//; s/[[:space:]]\{1,\}/ /g')
xrun_ver=${xrun_ver:-unknown}

{
    echo "# UVM regression report (Xcelium / xrun)"
    echo
    echo "| | |"
    echo "|---|---|"
    echo "| Date | $(date '+%Y-%m-%d %H:%M:%S %Z') |"
    echo "| Host | $(hostname) |"
    echo "| Git | \`$git_branch\` @ \`$git_rev\` |"
    echo "| Simulator | $xrun_ver |"
    [ -n "${extra[*]:-}" ] && echo "| Extra xrun args | \`${extra[*]}\` |"
    [ "$elaborate" -eq 1 ] && echo "| Mode | \`-elaborate\` (build only) |"
    echo "| Benches | ${#benches[@]} |"
    echo "| Result | **$overall** — $total_pass passed, $total_fail failed, $total_blocked blocked |"
    echo "| Wall time | $(fmt_hms "$wall") |"
    echo
    echo "| Bench | Test | Verdict | ERR | FATAL | WARN | Time | Detail | Log |"
    echo "|---|---|---|---:|---:|---:|---:|---|---|"
    printf '%s\n' "${rows[@]}"
    echo
    echo "> BLOCKED = the bench built cleanly but xrun could not check out an"
    echo "> Xcelium simulation licence. Point \`CDS_LIC_FILE\` / \`LM_LICENSE_FILE\` at a"
    echo "> working server and re-run, or use \`--elaborate\` to exercise the build alone."
    echo
    echo "_Generated by \`RTL/scripts/uvm_report_xrun.sh\`. Per-bench build libraries:"
    echo "\`RTL/sim_xrun/xcelium_<bench>.d/\`._"
} > "$report"

# ----------------------------------------------------------------------------
#  Console tail
# ----------------------------------------------------------------------------
echo
echo "============================================================"
echo "  UVM regression summary (Xcelium)"
echo "============================================================"
printf '%s\n' "${console[@]}"
echo "------------------------------------------------------------"
echo "  ${#benches[@]} bench(es): $total_pass passed, $total_fail failed, $total_blocked blocked"
echo "  report: $report"
echo "  logs:   $build_dir/<bench>.log"
echo "============================================================"

[ "$total_fail" -eq 0 ] && [ "$total_blocked" -eq 0 ]
