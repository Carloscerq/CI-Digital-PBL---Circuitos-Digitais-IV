#!/usr/bin/env bash
# ============================================================================
#  run_tb_uart_loopback.sh -- build and run tb_uart_loopback
#
#    ./run_tb_uart_loopback.sh                   # seconds, fast baud divisor
#    ./run_tb_uart_loopback.sh --baud 115200     # the divisor the board uses
#    ./run_tb_uart_loopback.sh --vsim            # Questa instead of Verilator
#    ./run_tb_uart_loopback.sh --trace           # FST/WLF waves
#
#  >>> FILELIST_NOTE <<<
#  Unlike run_tb_top_system.sh this list is written out rather than parsed from
#  the qsf: the loopback has its own Quartus project (RTL/quartus_uart_loopback)
#  and is only six files, so there is nothing for the two to drift apart about.
#  elastic_fifo.sv is borrowed from top_system/rtl -- same FIFO, same semantics.
# ============================================================================
set -uo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }

tb_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
rtl_root=$(cd -- "$tb_dir/../.." && pwd)
tb_src=$tb_dir/tb_uart_loopback.sv
top=tb_uart_loopback

files=(
    "$rtl_root/uart/rtl/baudrate.sv"
    "$rtl_root/uart/rtl/transmitter.sv"
    "$rtl_root/uart/rtl/receiver.sv"
    "$rtl_root/uart/rtl/uart.sv"
    "$rtl_root/top_system/rtl/elastic_fifo.sv"
    "$rtl_root/uart/rtl/uart_loopback_top.sv"
)

for f in "${files[@]}" "$tb_src"; do
    [ -f "$f" ] || die "missing source: $f"
done

# ---------------------------------------------------------------- arguments
sim=verilator
trace=0
baud=""
rebuild=0

while [ $# -gt 0 ]; do
    case "$1" in
        --vsim)      sim=vsim ;;
        --verilator) sim=verilator ;;
        --trace)     trace=1 ;;
        --rebuild)   rebuild=1 ;;
        --baud)      shift; baud="${1:-}" ;;
        -h|--help)   sed -n '2,14p' "$0"; exit 0 ;;
        *)           die "unknown argument: $1" ;;
    esac
    shift
done

build_dir=$rtl_root/sim_verilator
obj_dir=$build_dir/obj_${top}
mkdir -p "$build_dir" || die "cannot create $build_dir"
[ "$rebuild" -eq 1 ] && rm -rf "$obj_dir"
cd "$build_dir" || die "cannot enter $build_dir"

if [ "$sim" = verilator ]; then
    command -v verilator >/dev/null || die "verilator not found in PATH"

    vflags=(
        --binary -j 0 --timing
        --top-module "$top"
        --Mdir "$obj_dir" -o "V$top"
        -CFLAGS -O2
        -Wno-fatal
        -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-UNOPTFLAT
        -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM
        -Wno-VARHIDDEN -Wno-CASEINCOMPLETE -Wno-SYNCASYNCNET
    )
    [ "$trace" -eq 1 ] && vflags+=(--trace-fst --trace-structs)
    [ -n "$baud" ] && vflags+=("-GBAUD_RATE=$baud")

    echo "[run] verilating..."
    verilator "${vflags[@]}" "${files[@]}" "$tb_src" || die "verilator build failed"

    echo "[run] running   (cwd $PWD)"
    "$obj_dir/V$top"
    rc=$?
else
    command -v vsim >/dev/null || die "vsim not found in PATH"
    lib=$build_dir/work_${top}
    rm -rf "$lib"
    vlib "$lib" >/dev/null || die "vlib failed"
    vmap work "$lib" >/dev/null || die "vmap failed"

    echo "[run] compiling..."
    vlog -sv -quiet -timescale 1ns/1ps -work "$lib" "${files[@]}" "$tb_src" \
        || die "vlog failed"

    vgflags=(-voptargs=+acc)
    [ -n "$baud" ] && vgflags+=("-gBAUD_RATE=$baud")

    do_cmd="run -all; quit -f"
    if [ "$trace" -eq 1 ]; then
        vgflags+=(-wlf "$build_dir/${top}.wlf")
        do_cmd="log -r /*; $do_cmd"
    fi

    echo "[run] running   (cwd $PWD)"
    vsim -c -quiet -work "$lib" "${vgflags[@]}" "$top" -do "$do_cmd"
    rc=$?
fi

echo "[run] exit $rc"
exit $rc
