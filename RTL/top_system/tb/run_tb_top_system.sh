#!/usr/bin/env bash
# ============================================================================
#  run_tb_top_system.sh -- build and run tb_top_system under Verilator or Questa
#
#    ./run_tb_top_system.sh uart                       # ~seconds: framing only
#    ./run_tb_top_system.sh stream                     # ~minutes: full chain
#    ./run_tb_top_system.sh stream +SCENARIO=0Nm_BPFO_10
#    ./run_tb_top_system.sh stream +CNN_TARGET=2 +STRICT_CLASS
#    ./run_tb_top_system.sh uart --baud 115200         # production divisor
#    ./run_tb_top_system.sh stream --vsim              # Questa instead
#    ./run_tb_top_system.sh stream --trace             # FST waves
#
#  Anything starting with '+' is forwarded to the simulation as a plusarg.
#
#  >>> FILELIST_NOTE <<<
#  The RTL list is parsed out of RTL/quartus/quartus.qsf rather than kept here,
#  so a file added to the Quartus project is automatically in the simulation
#  and the two can never disagree about what the design is.
#
#  >>> RTL_SIM_NOTE <<<
#  dual_port_ram.v instantiates an Altera altsyncram megafunction for Quartus
#  and a behavioural array for simulation, selected by `ifdef RTL_SIM. Without
#  the define, elaboration fails with "Module 'altsyncram' is not defined"
#  because the vendor library is not loaded. The FFT project's own scripts
#  (run_*_modelsim.do, run_*_xcelium.sh) pass +define+RTL_SIM for the same
#  reason, so this one does too.
#
#  The other two RTL_SIM guards -- in the preprocess_* pipeline files -- only
#  pick different DEFAULT coefficient paths, and top_system.sv overrides those
#  parameters explicitly, so the define cannot change which coefficients load.
#
#  >>> CWD_NOTE <<<
#  The design's $readmemh paths are relative ("../mem/cnn/...",
#  "../FFT/.../coefficients/..."), resolved by Quartus from RTL/quartus/. The
#  simulation therefore has to run from a sibling of that directory; this
#  script uses RTL/sim_verilator/, which is what RTL/scripts/uvm_verilator.sh
#  already does.
# ============================================================================
set -uo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }

tb_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
rtl_root=$(cd -- "$tb_dir/../.." && pwd)
qsf=$rtl_root/quartus/quartus.qsf
tb_src=$tb_dir/tb_top_system.sv
top=tb_top_system

[ -f "$qsf" ]    || die "cannot find $qsf"
[ -f "$tb_src" ] || die "cannot find $tb_src"

# ---------------------------------------------------------------- arguments
mode=stream
sim=verilator
trace=0
baud=""
rebuild=0
plusargs=()

case "${1:-}" in
    uart|stream) mode=$1; shift ;;
esac

while [ $# -gt 0 ]; do
    case "$1" in
        --vsim)      sim=vsim ;;
        --verilator) sim=verilator ;;
        --trace)     trace=1 ;;
        --rebuild)   rebuild=1 ;;
        --baud)      shift; baud="${1:-}" ;;
        +*)          plusargs+=("$1") ;;
        -h|--help)   sed -n '2,25p' "$0"; exit 0 ;;
        *)           die "unknown argument: $1" ;;
    esac
    shift
done
plusargs+=("+MODE=$mode")

# ---------------------------------------------------------- RTL file list
# Pull every HDL entry out of the qsf, in project order, and resolve each one
# relative to RTL/quartus/ the way Quartus does.
mapfile -t rel_files < <(
    grep -E '^set_global_assignment -name (SYSTEMVERILOG_FILE|VERILOG_FILE) ' "$qsf" \
    | sed -E 's/^set_global_assignment -name [A-Z_]+ //' \
    | tr -d '\r'
)
[ "${#rel_files[@]}" -gt 0 ] || die "no HDL files found in $qsf"

files=()
for rel in "${rel_files[@]}"; do
    abs=$(cd -- "$rtl_root/quartus" && readlink -f -- "$rel" 2>/dev/null)
    [ -n "$abs" ] && [ -f "$abs" ] || die "listed in qsf but missing: $rel"
    files+=("$abs")
done

# Packages must be visible before anything that imports them.
pkgs=() rest=()
for f in "${files[@]}"; do
    case "$(basename "$f")" in
        system_types_pkg.sv|mlp_weights.sv) pkgs+=("$f") ;;
        *)                                  rest+=("$f") ;;
    esac
done
files=("${pkgs[@]}" "${rest[@]}")
echo "[run] ${#files[@]} RTL files from $(basename "$qsf")"

# ------------------------------------------------------------------- build
build_dir=$rtl_root/sim_verilator          # see CWD_NOTE
obj_dir=$build_dir/obj_${top}
mkdir -p "$build_dir" || die "cannot create $build_dir"
[ "$rebuild" -eq 1 ] && rm -rf "$obj_dir"

gflags=()
[ -n "$baud" ] && gflags+=("-GBAUD_RATE=$baud")

cd "$build_dir" || die "cannot enter $build_dir"

if [ "$sim" = verilator ]; then
    command -v verilator >/dev/null || die "verilator not found in PATH"

    vflags=(
        --binary -j 0 --timing
        --top-module "$top"
        --Mdir "$obj_dir" -o "V$top"
        -CFLAGS -O2
        -DRTL_SIM
        -Wno-fatal
        -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-UNOPTFLAT
        -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM
        -Wno-VARHIDDEN -Wno-CASEINCOMPLETE -Wno-SYNCASYNCNET
    )
    [ "$trace" -eq 1 ] && vflags+=(--trace-fst --trace-structs)

    echo "[run] verilating..."
    verilator "${vflags[@]}" "${gflags[@]}" "${files[@]}" "$tb_src" \
        || die "verilator build failed"

    echo "[run] running: ${plusargs[*]}   (cwd $PWD)"
    "$obj_dir/V$top" "${plusargs[@]}"
    rc=$?
else
    command -v vsim >/dev/null || die "vsim not found in PATH"
    lib=$build_dir/work_${top}
    rm -rf "$lib"
    vlib "$lib" >/dev/null || die "vlib failed"
    vmap work "$lib" >/dev/null || die "vmap failed"

    echo "[run] compiling..."
    vlog -sv -quiet +define+RTL_SIM -timescale 1ns/1ps \
         -work "$lib" "${files[@]}" "$tb_src" || die "vlog failed"

    vgflags=()
    [ -n "$baud" ] && vgflags+=("-gBAUD_RATE=$baud")
    # +acc keeps the internal signals the monitors probe through cross-module
    # references; vopt is free to optimise them away otherwise.
    vgflags+=(-voptargs=+acc)

    do_cmd="run -all; quit -f"
    if [ "$trace" -eq 1 ]; then
        vgflags+=(-wlf "$build_dir/${top}.wlf")
        do_cmd="log -r /*; $do_cmd"
    fi

    echo "[run] running: ${plusargs[*]}   (cwd $PWD)"
    vsim -c -quiet -work "$lib" "${vgflags[@]}" "$top" \
         "${plusargs[@]}" -do "$do_cmd"
    rc=$?
fi

echo "[run] exit $rc"
exit $rc
