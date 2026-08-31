#!/usr/bin/env bash
# ============================================================================
#  uvm_verilator.sh  --  run one UVM testbench under Verilator (open source).
#
#  Third runner for the same benches: run_uvm.sh drives Cadence Xcelium,
#  uvm_vsim.sh drives Questa/ModelSim, this one drives Verilator. Same .files
#  lists, same top modules, same default tests, so a bench behaves identically
#  under all three -- and this one needs no licence.
#
#    ./uvm_verilator.sh --list                          # every bench id
#    ./uvm_verilator.sh mac                             # default test
#    ./uvm_verilator.sh mac +UVM_VERBOSITY=UVM_HIGH     # per-item logging
#    ./uvm_verilator.sh mac +UVM_TESTNAME=mac_protocol_test
#    ./uvm_verilator.sh mac --trace                     # FST waves for gtkwave
#    ./uvm_verilator.sh mac --build-only                # verilate + compile only
#
#  Anything after the bench id is forwarded to the simulation binary, so
#  +plusargs all work. A later +UVM_TESTNAME wins over the default.
#
#  Exit status is 0 only if the build succeeded AND the run reported zero
#  UVM_ERROR / UVM_FATAL -- UVM calls $finish on a failing test and Verilator
#  exits 0 for that, so the UVM report summary is parsed instead.
#
#  Requirements:
#    verilator >= 5.038  (5.050 is what this was developed against; UVM 1.2
#                         needs class support, --timing and --vpi)
#    UVM 1.2 sources     (auto-detected, see "UVM sources" below)
#    a C++20 compiler    (g++ -fcoroutines, for --timing)
#  Optional: ccache (verilator uses it if present -- rebuilds drop from ~2min
#  to seconds), z3 (constraint solving; verilator falls back to its own).
# ============================================================================
set -uo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
rtl_root=$(cd -- "$script_dir/.." && pwd)
repo_root=$(cd -- "$rtl_root/.." && pwd)
dpi_shim=$script_dir/verilator/uvm_dpi_verilator.cc

# ----------------------------------------------------------------------------
#  Bench table:
#    id | filelist (rtl_root-relative) | top module | default test | extra C/C++
# ----------------------------------------------------------------------------
#  Kept in sync with uvm_vsim.sh and each bench's own run_uvm.sh. The .files
#  lists are themselves inconsistent about what they are relative to (some to
#  their own directory, some to RTL/), so resolve_source() below tries both.
#
#  The 5th field is for C/C++ sources a bench needs but that its .files list
#  cannot carry (the lists are read by tools that only take SystemVerilog).
#  mlp's scoreboard checks the DUT against a bit-exact C++ reference model over
#  DPI-C, which run_uvm.sh passes to xrun on the command line for the same
#  reason. Paths are rtl_root-relative; each one's directory is added to the
#  C++ include path, so mlp_ref.cpp finds its mlp_weights.h.
BENCHES=(
  "mac|mac/uvm/mac_uvm_wide.files|mac_uvm_top|mac_wide_random_test"
  "mlp|mlp_model/uvm/mlp_uvm.files|mlp_uvm_top|mlp_directed_random_test|mlp_model/mlp_ref.cpp"
  "spi|spi/uvm/spi_uvm.files|spi_uvm_top|spi_directed_test"
  "gcd|gcd/uvm/gcd/gcd_uvm.files|gcd_uvm_top|gcd_full_random_test"
  "euclidian_gcd|gcd/uvm/euclidian_gcd/euclidian_gcd_uvm.files|euclidian_gcd_uvm_top|euclidian_gcd_random_test"
  "filtro_lms|LMS/uvm/filtro_lms_uvm.files|filtro_lms_uvm_top|filtro_lms_regression_test"
  "perceptron|perceptron/uvm/perceptron_uvm_wide.files|perceptron_uvm_top|perceptron_wide_random_test"
  "spectrogram|spectrogram/uvm/spectrogram_generator_uvm.files|spectrogram_generator_uvm_top|spectrogram_generator_directed_random_test"
  "cnn_mac_q8_16|cnn/uvm/mac_q8_16/mac_q8_16_uvm.files|mac_q8_16_uvm_top|mac_q8_16_default_test"
  "cnn_line_buffer|cnn/uvm/line_buffer_3x3/line_buffer_3x3_uvm.files|line_buffer_3x3_uvm_top|line_buffer_3x3_directed_random_test"
  "cnn_maxpool|cnn/uvm/maxpool_2x2/maxpool_2x2_uvm.files|maxpool_2x2_uvm_top|maxpool_2x2_directed_random_test"
  "cnn_conv2d|cnn/uvm/conv2d_fsm/conv2d_fsm_uvm.files|conv2d_fsm_uvm_top|conv2d_fsm_directed_random_test"
  "cnn_dense|cnn/uvm/dense_layer_fsm/dense_layer_fsm_uvm.files|dense_layer_fsm_uvm_top|dense_layer_fsm_directed_random_test"
  "cnn_top|cnn/uvm/cnn_top/cnn_top_uvm.files|cnn_top_uvm_top|cnn_top_directed_random_test"
  "fft|FFT/model_sim_four_modes/uvm/preprocess_lms_fft_uvm.files|preprocess_lms_fft_uvm_top|preprocess_lms_fft_directed_test"
)

list_benches() { printf '%s\n' "${BENCHES[@]}" | cut -d'|' -f1; }

die() { echo "uvm_verilator.sh: $*" >&2; exit 2; }

# ----------------------------------------------------------------------------
#  Arguments
# ----------------------------------------------------------------------------
trace=0
build_only=0
rebuild=0
bench=""
sim_extra=()

while [ $# -gt 0 ]; do
    case "$1" in
        --list)                     list_benches; exit 0 ;;
        --trace|--waves)            trace=1; shift ;;
        --build-only|--compile-only) build_only=1; shift ;;
        --rebuild)                  rebuild=1; shift ;;
        -h|--help)                  sed -n '2,32p' "${BASH_SOURCE[0]}" | sed 's|^# \?||'; exit 0 ;;
        *)                          if [ -z "$bench" ]; then bench=$1; else sim_extra+=("$1"); fi; shift ;;
    esac
done

[ -n "$bench" ] || { echo "usage: $(basename "$0") <bench> [+plusargs...]" >&2
                     echo "benches:" >&2; list_benches | sed 's/^/  /' >&2; exit 2; }

entry=""
for e in "${BENCHES[@]}"; do
    [ "${e%%|*}" = "$bench" ] && { entry=$e; break; }
done
[ -n "$entry" ] || { echo "uvm_verilator.sh: unknown bench '$bench'" >&2
                     echo "benches:" >&2; list_benches | sed 's/^/  /' >&2; exit 2; }

IFS='|' read -r _id files_rel top default_test extra_c <<< "$entry"

# ----------------------------------------------------------------------------
#  Verilator
# ----------------------------------------------------------------------------
VERILATOR=${VERILATOR:-verilator}
command -v "$VERILATOR" >/dev/null \
    || die "'$VERILATOR' not on PATH. Install Verilator >= 5.038 (UVM needs
    class support, --timing and --vpi), or set VERILATOR=/path/to/verilator."

vl_version=$("$VERILATOR" --version 2>/dev/null | awk '{print $2}')
vl_major=${vl_version%%.*}
if [ -n "${vl_major:-}" ] && [ "$vl_major" -lt 5 ] 2>/dev/null; then
    die "Verilator $vl_version is too old for UVM -- 5.038 or newer is needed."
fi

# ----------------------------------------------------------------------------
#  UVM sources
# ----------------------------------------------------------------------------
#  Verilator ships no UVM of its own, so point it at a UVM 1.2 source tree.
#  UVM_SRC wins; otherwise reuse Questa's copy (uvm_vsim.sh already depends on
#  it) or Accellera's usual install layouts. It must be 1.2: the Xcelium
#  scripts use -uvmhome CDNS-1.2, so the benches expect 1.2, not 1.1d.
if [ -z "${UVM_SRC:-}" ]; then
    questa_home=${QUESTA_HOME:-}
    if [ -z "$questa_home" ]; then
        vsim_bin=$(command -v vsim || true)
        [ -n "$vsim_bin" ] && questa_home=$(cd -- "$(dirname -- "$(readlink -f "$vsim_bin")")/.." && pwd)
    fi
    for cand in ${questa_home:+"$questa_home/verilog_src/uvm-1.2/src"} \
                "$HOME/questasim/verilog_src/uvm-1.2/src" \
                ${UVM_HOME:+"$UVM_HOME/src"} \
                /usr/share/uvm-1.2/src /opt/uvm-1.2/src; do
        [ -f "$cand/uvm_pkg.sv" ] && { UVM_SRC=$cand; break; }
    done
fi
[ -n "${UVM_SRC:-}" ] && [ -f "$UVM_SRC/uvm_pkg.sv" ] \
    || die "no UVM 1.2 sources found. Set UVM_SRC=/path/to/uvm-1.2/src
    (a directory containing uvm_pkg.sv and dpi/). Questa's copy lives at
    \$QUESTA_HOME/verilog_src/uvm-1.2/src."
[ -f "$UVM_SRC/dpi/uvm_dpi.h" ] || die "UVM_SRC='$UVM_SRC' has no dpi/ directory"
[ -f "$dpi_shim" ] || die "missing DPI shim: $dpi_shim"

# ----------------------------------------------------------------------------
#  Filelist -> absolute source paths
# ----------------------------------------------------------------------------
filelist=$rtl_root/$files_rel
[ -f "$filelist" ] || die "filelist not found: $filelist"
filelist_dir=$(dirname -- "$filelist")

sources=()
incdirs=()
add_incdir() {
    local d=$1 i
    for i in "${incdirs[@]:-}"; do [ "$i" = "$d" ] && return 0; done
    incdirs+=("$d")
}

# The .files lists disagree about what their entries are relative to: most to
# the filelist's own directory, the cnn conv2d/dense/smma lists to RTL/, the
# FFT list to RTL/FFT/, and mac_uvm_wide.files to the repo root ("RTL/mac/..").
# Rather than special-case each, try every ancestor of the filelist from
# nearest outwards and take the first that exists.
resolve_source() {
    local line=$1 base=$filelist_dir cand
    while :; do
        cand=$base/$line
        if [ -f "$cand" ]; then
            echo "$(cd -- "$(dirname -- "$cand")" && pwd)/$(basename -- "$line")"
            return 0
        fi
        [ "$base" = "$repo_root" ] && return 1     # never climb past the repo
        base=$(dirname -- "$base")
    done
}

while IFS= read -r line || [ -n "$line" ]; do
    line=${line%%#*}                       # strip comments
    line=$(echo "$line" | tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    [ -n "$line" ] || continue
    src=$(resolve_source "$line") \
        || die "source listed in $(basename "$filelist") not found: $line"
    sources+=("$src")
    add_incdir "$(dirname -- "$src")"
done < "$filelist"

[ ${#sources[@]} -gt 0 ] || die "filelist $(basename "$filelist") is empty"

# ----------------------------------------------------------------------------
#  Extra C/C++ sources (DPI reference models)
# ----------------------------------------------------------------------------
csources=()
cincdirs=()
for c in ${extra_c:-}; do
    [ -f "$rtl_root/$c" ] || die "extra C/C++ source not found: $rtl_root/$c"
    csources+=("$rtl_root/$c")
    cdir=$(cd -- "$(dirname -- "$rtl_root/$c")" && pwd)
    case " ${cincdirs[*]:-} " in *" $cdir "*) ;; *) cincdirs+=("$cdir") ;; esac
done

# ----------------------------------------------------------------------------
#  Build area
# ----------------------------------------------------------------------------
#  IMPORTANT: the simulation binary has to RUN from a directory exactly one
#  level below RTL/, because the DUTs load their ROM images with paths like
#  "../mem/cnn/dense_weights.mem" and "../mem/mlp/mlp_weights.mem" (chosen for
#  the Quartus project dir, RTL/quartus/). Running from anywhere else makes
#  $readmemh silently load nothing -- note dense_layer_fsm.sv prints
#  "successfully loaded" unconditionally, so a wrong cwd looks like a pass with
#  all-zero results. Hence RTL/sim_verilator as the cwd, with per-bench obj
#  directories inside it (mirrors RTL/sim_vsim for Questa).
build_dir=$rtl_root/sim_verilator
obj_dir=$build_dir/obj_$bench
log=$build_dir/$bench.log
exe=$obj_dir/V$top

mkdir -p "$build_dir" || die "cannot create $build_dir"
cd "$build_dir"      || die "cannot enter $build_dir"
[ "$rebuild" -eq 1 ] && rm -rf "$obj_dir"

# ----------------------------------------------------------------------------
#  Trace hook
# ----------------------------------------------------------------------------
#  None of the benches call $dumpfile/$dumpvars, so --trace binds a one-shot
#  dumper into the top module instead of touching the testbench sources.
trace_args=()
if [ "$trace" -eq 1 ]; then
    trace_sv=$obj_dir/${bench}_vlt_trace.sv
    mkdir -p "$obj_dir"
    cat > "$trace_sv" <<EOF
// Generated by uvm_verilator.sh --trace; not part of the bench sources.
module ${bench}_vlt_trace;
    initial begin
        \$dumpfile("$build_dir/$bench.fst");
        \$dumpvars;
    end
endmodule

bind $top ${bench}_vlt_trace ${bench}_vlt_trace_i();
EOF
    sources+=("$trace_sv")
    trace_args=(--trace-fst --trace-structs --trace-max-array 4096 --trace-max-width 4096)
fi

# ----------------------------------------------------------------------------
#  Verilate + compile
# ----------------------------------------------------------------------------
#  --timing        the benches use #delays and clocking-style waits
#  --vpi           uvm_svcmd_dpi.c reads +plusargs through vpi_get_vlog_info()
#  +define+UVM_HDL_NO_DPI  see scripts/verilator/uvm_dpi_verilator.cc
#  --assert        keep immediate/concurrent assertions live, as vsim does
#  -Wno-fatal      UVM 1.2 and the RTL both trip lint warnings that Questa and
#                  Xcelium only warn about; they stay visible in the log
#
#  VERILATOR_CXX_OPT defaults to -O0. This is not a micro-optimisation:
#  Verilator expands a `rand` unpacked array element by element, so
#  line_buffer_3x3_seq_item's `rand logic [23:0] pixels [32][32][4]` (4096 rand
#  elements, one frame per item) becomes a single enormous function. At -Os g++
#  ran >15 min at 8 GB of RSS on that one file, and maxpool_2x2_seq_item
#  reached 19 GB before being killed. At -O0 both are quick and small. The cost
#  is simulation speed, irrelevant here -- these benches finish in seconds.
#  Set VERILATOR_CXX_OPT=-Os to get it back.
#
#  It has to go through -MAKEFLAGS, not -CFLAGS: the generated rule ends
#  ... $(CXXFLAGS) $(CPPFLAGS) $(OPT_FAST) -c, so a -CFLAGS -O0 lands earlier
#  on the line than OPT_FAST's -Os and loses (last -O wins in gcc). OPT_FAST
#  and OPT_GLOBAL are plain `=` assignments in verilated.mk, so overriding them
#  on make's command line wins instead.
jobs=${VERILATOR_JOBS:-$( (nproc 2>/dev/null) || echo 4 )}
cxx_opt=${VERILATOR_CXX_OPT:--O0}

vl_args=(--binary -j "$jobs" --timing --vpi -sv --timescale 1ns/1ps --assert
         -Wno-fatal -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND -Wno-UNSIGNED -Wno-CMPCONST
         -Wno-UNOPTFLAT -Wno-CASEINCOMPLETE -Wno-MULTIDRIVEN -Wno-BLKANDNBLK
         --Mdir "$obj_dir" -o "V$top" --top-module "$top"
         "+define+UVM_HDL_NO_DPI" "+incdir+$UVM_SRC")
for d in "${incdirs[@]}"; do vl_args+=("+incdir+$d"); done
vl_args+=("${trace_args[@]+"${trace_args[@]}"}")
vl_args+=("$UVM_SRC/uvm_pkg.sv" "${sources[@]}")
vl_args+=(-MAKEFLAGS "OPT_FAST=$cxx_opt" -MAKEFLAGS "OPT_GLOBAL=$cxx_opt")
vl_args+=(-CFLAGS "-I$UVM_SRC/dpi")
for d in "${cincdirs[@]:-}"; do [ -n "$d" ] && vl_args+=(-CFLAGS "-I$d"); done
vl_args+=("$dpi_shim" "${csources[@]+"${csources[@]}"}")

echo "=== $bench : verilator (${#sources[@]} files + UVM 1.2) ==="
echo "    first build takes a couple of minutes (UVM is big); ccache makes the rest quick"
if ! "$VERILATOR" "${vl_args[@]}" > "$log" 2>&1; then
    echo "=== $bench : BUILD FAILED (see $log) ==="
    grep -E '^%Error' "$log" | head -20
    exit 1
fi
[ -x "$exe" ] || { echo "=== $bench : BUILD FAILED -- no $exe (see $log) ==="; exit 1; }

if [ "$build_only" -eq 1 ]; then
    echo "=== $bench : BUILD OK (--build-only, not simulated) ==="
    exit 0
fi

# ----------------------------------------------------------------------------
#  Simulate
# ----------------------------------------------------------------------------
#  cwd is $build_dir (one below RTL/) -- see the note above about $readmemh.
echo "=== $bench : run $top (+UVM_TESTNAME=$default_test) ==="
"$exe" "+UVM_TESTNAME=$default_test" "${sim_extra[@]+"${sim_extra[@]}"}" 2>&1 | tee -a "$log"

[ "$trace" -eq 1 ] && echo "    waves: $build_dir/$bench.fst  (gtkwave $build_dir/$bench.fst)"

# ----------------------------------------------------------------------------
#  Verdict
# ----------------------------------------------------------------------------
#  UVM ends a failing test with $finish, which Verilator reports as exit 0, so
#  read the UVM report summary instead.
count_of() { grep -oE "^$1 *: *[0-9]+" "$log" | tail -1 | grep -oE '[0-9]+$'; }

uvm_err=$(count_of UVM_ERROR)
uvm_fat=$(count_of UVM_FATAL)

if grep -qE '^%Error' "$log"; then
    echo "=== $bench : RUNTIME ERROR (see $log) ==="
    grep -E '^%Error' "$log" | head -10
    exit 1
fi
if [ -z "$uvm_err" ] || [ -z "$uvm_fat" ]; then
    echo "=== $bench : NO UVM REPORT SUMMARY -- the run did not finish (see $log) ==="
    exit 1
fi
if [ "$uvm_err" -ne 0 ] || [ "$uvm_fat" -ne 0 ]; then
    echo "=== $bench : FAIL (UVM_ERROR=$uvm_err UVM_FATAL=$uvm_fat, see $log) ==="
    exit 1
fi

echo "=== $bench : PASS (UVM_ERROR=0 UVM_FATAL=0) ==="
exit 0
