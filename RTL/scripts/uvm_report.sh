#!/usr/bin/env bash
# ============================================================================
#  uvm_report.sh  --  run every UVM bench under Questa and write ONE report.
#
#  Thin wrapper around uvm_vsim.sh: it runs the same benches the same way,
#  but instead of a scroll-past console summary it collects each bench's
#  verdict, UVM_ERROR / UVM_FATAL / UVM_WARNING counts, wall-clock time and
#  log path into a single Markdown file.
#
#    ./uvm_report.sh                         # all benches -> sim_vsim/uvm_report.md
#    ./uvm_report.sh mac spi gcd             # just these
#    ./uvm_report.sh --out /tmp/uvm.md       # choose the report path
#    ./uvm_report.sh --compile-only          # compile every bench, no simulation
#    ./uvm_report.sh -- +UVM_VERBOSITY=UVM_HIGH   # all, extra vsim args
#
#  Everything after a lone -- is forwarded to vsim for every bench.
#  Exit status is 0 only if every bench passed (mirrors run_all_uvm_vsim.sh):
#  a FAIL or a BLOCKED (compiled, but no simulation licence) makes it non-zero,
#  so it drops straight into CI.
# ============================================================================
set -uo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
rtl_root=$(cd -- "$script_dir/.." && pwd)
runner=$script_dir/uvm_vsim.sh

[ -x "$runner" ] || { echo "uvm_report.sh: missing $runner" >&2; exit 2; }

# ----------------------------------------------------------------------------
#  Arguments
# ----------------------------------------------------------------------------
benches=()
extra=()
opts=()
report=$rtl_root/sim_vsim/uvm_report.md
seen_sep=0
while [ $# -gt 0 ]; do
    arg=$1; shift
    if [ "$seen_sep" -eq 1 ]; then extra+=("$arg"); continue; fi
    case "$arg" in
        --)             seen_sep=1 ;;
        --out)          report=${1:?--out needs a path}; shift ;;
        --out=*)        report=${arg#--out=} ;;
        --compile-only) opts+=("$arg") ;;
        -h|--help)      sed -n '2,22p' "${BASH_SOURCE[0]}" | sed 's|^# \?||'; exit 0 ;;
        -*)             echo "uvm_report.sh: unknown option '$arg'" >&2; exit 2 ;;
        *)              benches+=("$arg") ;;
    esac
done

if [ ${#benches[@]} -eq 0 ]; then
    mapfile -t benches < <("$runner" --list)
fi
[ ${#benches[@]} -gt 0 ] || { echo "uvm_report.sh: no benches" >&2; exit 2; }

mkdir -p "$(dirname -- "$report")" || { echo "uvm_report.sh: cannot create report dir" >&2; exit 2; }

# ----------------------------------------------------------------------------
#  Per-bench log parsing  (same rules uvm_vsim.sh uses for its own verdict)
# ----------------------------------------------------------------------------
log_dir=$rtl_root/sim_vsim

# Questa prefixes console lines with "# " in batch mode; tolerate it.
count_of() {  # <log> <label>  -> integer, or "" if the summary never printed
    grep -oE "^(# )?$2 *: *[0-9]+" "$1" 2>/dev/null | tail -1 | grep -oE '[0-9]+$'
}
testname_of() {  # <log>
    grep -oE "Running test [A-Za-z0-9_]+" "$1" 2>/dev/null | tail -1 | awk '{print $3}'
}

fmt_hms() { printf '%d:%02d:%02d' $(( $1 / 3600 )) $(( ($1 % 3600) / 60 )) $(( $1 % 60 )); }

# ----------------------------------------------------------------------------
#  Run
# ----------------------------------------------------------------------------
rows=()          # markdown table rows
console=()       # short lines echoed at the end
total_pass=0 total_fail=0 total_blocked=0
started=$(date +%s)

for b in "${benches[@]}"; do
    echo
    echo "############################################################"
    echo "#  $b"
    echo "############################################################"

    t0=$SECONDS
    "$runner" "${opts[@]+"${opts[@]}"}" "$b" "${extra[@]+"${extra[@]}"}"
    rc=$?
    dt=$(( SECONDS - t0 ))

    log=$log_dir/$b.log
    log_rel=$(realpath --relative-to="$(dirname -- "$report")" "$log" 2>/dev/null || echo "$log")

    err=""; fat=""; warn=""; tn=""
    if [ -f "$log" ]; then
        err=$(count_of "$log" UVM_ERROR)
        fat=$(count_of "$log" UVM_FATAL)
        warn=$(count_of "$log" UVM_WARNING)
        tn=$(testname_of "$log")
    fi

    case $rc in
        0)  verdict="PASS";    total_pass=$((total_pass + 1)) ;;
        3)  verdict="BLOCKED"; total_blocked=$((total_blocked + 1)) ;;
        *)  verdict="FAIL";    total_fail=$((total_fail + 1)) ;;
    esac

    # Human-readable reason for the non-PASS cases.
    detail=""
    if [ "$verdict" = "BLOCKED" ]; then
        detail="compiled OK; no Questa simulation licence"
    elif [ "$verdict" = "FAIL" ]; then
        if [ ! -f "$log" ]; then
            detail="runner error before any log was written"
        elif grep -qE '^(# )?\*\* Error' "$log"; then
            detail="compile failed"
        elif [ -z "$err" ] || [ -z "$fat" ]; then
            detail="run did not finish (no UVM report summary)"
        else
            detail="UVM_ERROR=$err UVM_FATAL=$fat"
        fi
    elif [ -n "${opts[*]:-}" ]; then
        detail="compile-only"
    fi

    icon="✅"; [ "$verdict" = "FAIL" ] && icon="❌"; [ "$verdict" = "BLOCKED" ] && icon="⚠️"

    rows+=("| \`$b\` | ${tn:-–} | $(printf "$icon") $verdict | ${err:-–} | ${fat:-–} | ${warn:-–} | $(fmt_hms "$dt") | ${detail:-–} | [log]($log_rel) |")
    console+=("$(printf '  %-8s %-16s %s' "$verdict" "$b" "${detail:-ok}")")
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
vsim_ver=$(vsim -version 2>/dev/null | head -1 || echo "vsim not on PATH")

{
    echo "# UVM regression report (Questa / vsim)"
    echo
    echo "| | |"
    echo "|---|---|"
    echo "| Date | $(date '+%Y-%m-%d %H:%M:%S %Z') |"
    echo "| Host | $(hostname) |"
    echo "| Git | \`$git_branch\` @ \`$git_rev\` |"
    echo "| Simulator | $vsim_ver |"
    [ -n "${extra[*]:-}" ] && echo "| Extra vsim args | \`${extra[*]}\` |"
    [ -n "${opts[*]:-}" ]  && echo "| Mode | \`${opts[*]}\` |"
    echo "| Benches | ${#benches[@]} |"
    echo "| Result | **$overall** — $total_pass passed, $total_fail failed, $total_blocked blocked |"
    echo "| Wall time | $(fmt_hms "$wall") |"
    echo
    echo "| Bench | Test | Verdict | ERR | FATAL | WARN | Time | Detail | Log |"
    echo "|---|---|---|---:|---:|---:|---:|---|---|"
    printf '%s\n' "${rows[@]}"
    echo
    echo "> BLOCKED = the bench compiled cleanly but vsim could not check out a"
    echo "> simulation licence. Point \`LM_LICENSE_FILE\` / \`MGLS_LICENSE_FILE\` at a"
    echo "> working server and re-run, or use \`--compile-only\` to exercise the"
    echo "> compile step alone."
    echo
    echo "_Generated by \`RTL/scripts/uvm_report.sh\`._"
} > "$report"

# ----------------------------------------------------------------------------
#  Console tail
# ----------------------------------------------------------------------------
echo
echo "============================================================"
echo "  UVM regression summary (Questa)"
echo "============================================================"
printf '%s\n' "${console[@]}"
echo "------------------------------------------------------------"
echo "  ${#benches[@]} bench(es): $total_pass passed, $total_fail failed, $total_blocked blocked"
echo "  report: $report"
echo "  logs:   $log_dir/<bench>.log"
echo "============================================================"

[ "$total_fail" -eq 0 ] && [ "$total_blocked" -eq 0 ]
