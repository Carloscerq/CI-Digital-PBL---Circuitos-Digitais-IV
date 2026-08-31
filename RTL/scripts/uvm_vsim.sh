#!/usr/bin/env bash
# ============================================================================
#  uvm_vsim.sh  --  run one UVM testbench under Questa/ModelSim (vlog + vsim).
#
#  The per-bench run_uvm.sh scripts drive Cadence Xcelium (xrun). This is the
#  Questa equivalent: same .files lists, same top modules, same default tests,
#  so a bench behaves identically under either simulator.
#
#    ./uvm_vsim.sh --list                          # every bench id
#    ./uvm_vsim.sh mac                             # default test
#    ./uvm_vsim.sh mac +UVM_VERBOSITY=UVM_HIGH     # per-item logging
#    ./uvm_vsim.sh mac +UVM_TESTNAME=mac_protocol_test
#    ./uvm_vsim.sh mac --gui                       # interactive, waves kept
#
#  Anything after the bench id is forwarded to vsim, so +plusargs, -do, -g
#  overrides etc. all work. A later +UVM_TESTNAME wins over the default.
#
#  Exit status is 0 only if compilation succeeded AND the run reported zero
#  UVM_ERROR / UVM_FATAL -- vsim itself exits 0 even on a failing test, so the
#  UVM report summary is parsed instead.
# ============================================================================
set -uo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
rtl_root=$(cd -- "$script_dir/.." && pwd)

# ----------------------------------------------------------------------------
#  Bench table:  id | filelist (relative to rtl_root) | top module | default test
# ----------------------------------------------------------------------------
#  Kept in sync with each bench's own run_uvm.sh. Note the .files lists are
#  themselves inconsistent about what they are relative to (some to their own
#  directory, some to RTL/), so resolve_filelist() below tries both.
BENCHES=(
  "mac|mac/uvm/mac_uvm_wide.files|mac_uvm_top|mac_wide_random_test"
  "mlp|mlp_model/uvm/mlp_uvm.files|mlp_uvm_top|mlp_directed_random_test"
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

die() { echo "uvm_vsim.sh: $*" >&2; exit 2; }

# ----------------------------------------------------------------------------
#  Arguments
# ----------------------------------------------------------------------------
gui=0
compile_only=0
bench=""
vsim_extra=()

while [ $# -gt 0 ]; do
    case "$1" in
        --list)         list_benches; exit 0 ;;
        --gui)          gui=1; shift ;;
        --compile-only) compile_only=1; shift ;;
        -h|--help)      sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's|^# \?||'; exit 0 ;;
        *)              if [ -z "$bench" ]; then bench=$1; else vsim_extra+=("$1"); fi; shift ;;
    esac
done

[ -n "$bench" ] || { echo "usage: $(basename "$0") <bench> [vsim args...]" >&2
                     echo "benches:" >&2; list_benches | sed 's/^/  /' >&2; exit 2; }

entry=""
for e in "${BENCHES[@]}"; do
    [ "${e%%|*}" = "$bench" ] && { entry=$e; break; }
done
[ -n "$entry" ] || { echo "uvm_vsim.sh: unknown bench '$bench'" >&2
                     echo "benches:" >&2; list_benches | sed 's/^/  /' >&2; exit 2; }

IFS='|' read -r _id files_rel top default_test <<< "$entry"

# ----------------------------------------------------------------------------
#  Questa install
# ----------------------------------------------------------------------------
#  QUESTA_HOME may be preset; otherwise derive it from whichever vsim is on
#  PATH. MODEL_TECH is the platform directory (linux_x86_64, linux_aarch64,
#  ...) and also names the matching prebuilt uvm_dpi shared object.
if [ -z "${QUESTA_HOME:-}" ]; then
    vsim_bin=$(command -v vsim || true)
    [ -n "$vsim_bin" ] || die "vsim not on PATH and QUESTA_HOME is not set.
    Add Questa to PATH, e.g.  export PATH=/home/carlos/questasim/linux_x86_64:\$PATH"
    QUESTA_HOME=$(cd -- "$(dirname -- "$(readlink -f "$vsim_bin")")/.." && pwd)
fi
[ -d "$QUESTA_HOME" ] || die "QUESTA_HOME='$QUESTA_HOME' is not a directory"

platform=$(basename "$(dirname -- "$(readlink -f "$(command -v vsim)")")" 2>/dev/null || echo linux_x86_64)

UVM_LIB=${UVM_LIB:-$QUESTA_HOME/uvm-1.2}
UVM_SRC=${UVM_SRC:-$QUESTA_HOME/verilog_src/uvm-1.2/src}
UVM_DPI=$UVM_LIB/$platform/uvm_dpi

[ -d "$UVM_LIB" ] || die "no precompiled UVM 1.2 library at '$UVM_LIB'
    (override with UVM_LIB=/path/to/uvm-1.2). The Xcelium scripts use
    -uvmhome CDNS-1.2, so the benches expect UVM 1.2, not Questa's default 1.1d."
[ -d "$UVM_SRC" ] || die "no UVM 1.2 sources at '$UVM_SRC' (needed for uvm_macros.svh)"

# ----------------------------------------------------------------------------
#  Filelist -> absolute source paths
# ----------------------------------------------------------------------------
resolve_filelist() {
    # A .files path is relative either to RTL/ or to its own directory.
    local p=$1
    if [ -f "$rtl_root/$p" ]; then echo "$rtl_root/$p"; return 0; fi
    return 1
}

filelist=$(resolve_filelist "$files_rel") || die "filelist not found: $rtl_root/$files_rel"
filelist_dir=$(dirname -- "$filelist")

sources=()
incdirs=()
add_incdir() {
    local d=$1 i
    for i in "${incdirs[@]:-}"; do [ "$i" = "$d" ] && return 0; done
    incdirs+=("$d")
}

# The .files lists disagree about what their entries are relative to: most to
# the filelist's own directory, the cnn conv2d/dense/smma lists to RTL/, and
# the FFT list to RTL/FFT/. Rather than special-case each, try every ancestor
# of the filelist from nearest outwards and take the first that exists.
resolve_source() {
    local line=$1 base=$filelist_dir cand
    while :; do
        cand=$base/$line
        if [ -f "$cand" ]; then
            echo "$(cd -- "$(dirname -- "$cand")" && pwd)/$(basename -- "$line")"
            return 0
        fi
        [ "$base" = "$rtl_root" ] && return 1
        base=$(dirname -- "$base")
        case $base in "$rtl_root"*) ;; *) return 1 ;; esac   # never climb past RTL/
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
#  Build area
# ----------------------------------------------------------------------------
#  IMPORTANT: the simulator's working directory has to sit exactly one level
#  below RTL/, because the DUTs load their ROM images with paths like
#  "../mem/cnn/dense_weights.mem" and "../mem/mlp/mlp_weights.mem" (chosen for
#  the Quartus project dir, RTL/quartus/). Running from anywhere else makes
#  $readmemh silently load nothing -- note dense_layer_fsm.sv prints
#  "successfully loaded" unconditionally, so a wrong cwd looks like a pass with
#  all-zero results. Hence one shared build dir, RTL/sim_vsim, with a separate
#  work library per bench inside it rather than a subdirectory per bench.
build_dir=$rtl_root/sim_vsim
work_lib=work_$bench
log=$build_dir/$bench.log

mkdir -p "$build_dir" || die "cannot create $build_dir"
cd "$build_dir"      || die "cannot enter $build_dir"

rm -rf "$work_lib"
vlib "$work_lib" > /dev/null || die "vlib $work_lib failed"

# ----------------------------------------------------------------------------
#  Compile
# ----------------------------------------------------------------------------
vlog_args=(-sv -timescale 1ns/1ps -work "$work_lib" -L "$UVM_LIB" "+incdir+$UVM_SRC")
for d in "${incdirs[@]}"; do vlog_args+=("+incdir+$d"); done

echo "=== $bench : vlog (${#sources[@]} files) ==="
if ! vlog "${vlog_args[@]}" "${sources[@]}" 2>&1 | tee "$log"; then
    echo "=== $bench : COMPILE FAILED (see $log) ==="
    exit 1
fi
if grep -qE '^\*\* Error' "$log"; then
    echo "=== $bench : COMPILE FAILED (see $log) ==="
    exit 1
fi

if [ "$compile_only" -eq 1 ]; then
    echo "=== $bench : COMPILE OK (--compile-only, not simulated) ==="
    exit 0
fi

# ----------------------------------------------------------------------------
#  Simulate
# ----------------------------------------------------------------------------
#  -voptargs=+acc is the Questa counterpart of xrun's -access +rwc: it keeps
#  the design visible to the UVM factory/config_db and to waveform probing.
vsim_args=(-work "$work_lib" -L "$UVM_LIB" -sv_lib "$UVM_DPI"
           -voptargs=+acc -onfinish exit
           "+UVM_TESTNAME=$default_test")

if [ "$gui" -eq 1 ]; then
    vsim_args+=(-gui -do "run -all")
else
    vsim_args+=(-c -do "run -all; quit -f")
fi

echo "=== $bench : vsim $top (+UVM_TESTNAME=$default_test) ==="
vsim "${vsim_args[@]}" "${vsim_extra[@]+"${vsim_extra[@]}"}" "$work_lib.$top" 2>&1 | tee -a "$log"

[ "$gui" -eq 1 ] && exit 0

# ----------------------------------------------------------------------------
#  Verdict
# ----------------------------------------------------------------------------
#  vsim exits 0 even when the test failed, so read the UVM report summary.
#  Questa prefixes console lines with "# ", hence the optional prefix below.
count_of() { grep -oE "^(# )?$1 *: *[0-9]+" "$log" | tail -1 | grep -oE '[0-9]+$'; }

uvm_err=$(count_of UVM_ERROR)
uvm_fat=$(count_of UVM_FATAL)

# A missing licence is an environment problem, not a failing test -- call it
# out by name rather than reporting it as a broken bench.
if grep -qE 'Failure to obtain a Verilog simulation license|License Issue' "$log"; then
    echo "=== $bench : BLOCKED -- no Questa simulation licence ==="
    echo "    vlog compiled the bench cleanly; vsim could not check out"
    echo "    'qhsimvl' or 'msimhdlsim'. Point LM_LICENSE_FILE / MGLS_LICENSE_FILE"
    echo "    at a working licence server, then re-run. Use --compile-only to"
    echo "    exercise just the compile step in the meantime."
    exit 3
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
