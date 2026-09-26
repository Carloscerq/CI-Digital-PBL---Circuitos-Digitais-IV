#!/usr/bin/env bash
# ============================================================================
#  run_tb_wrapper.sh -- build and run tb_top_system_de0cv
#
#  Same file list and CWD rules as run_tb_top_system.sh (see FILELIST_NOTE and
#  CWD_NOTE there): the RTL comes out of RTL/quartus/quartus.qsf so the two
#  cannot disagree, and the run happens from RTL/sim_verilator because the
#  design's $readmemh paths are relative to RTL/quartus/.
# ============================================================================
set -uo pipefail
die() { echo "ERROR: $*" >&2; exit 1; }

tb_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
rtl_root=$(cd -- "$tb_dir/../.." && pwd)
qsf=$rtl_root/quartus/quartus.qsf
tb_src=$tb_dir/tb_top_system_de0cv.sv
top=tb_top_system_de0cv

mapfile -t rel_files < <(
    grep -E '^set_global_assignment -name (SYSTEMVERILOG_FILE|VERILOG_FILE) ' "$qsf" \
    | sed -E 's/^set_global_assignment -name [A-Z_]+ //' | tr -d '\r')
[ "${#rel_files[@]}" -gt 0 ] || die "no HDL files found in $qsf"

files=()
for rel in "${rel_files[@]}"; do
    abs=$(cd -- "$rtl_root/quartus" && readlink -f -- "$rel" 2>/dev/null)
    [ -n "$abs" ] && [ -f "$abs" ] || die "listed in qsf but missing: $rel"
    files+=("$abs")
done

pkgs=() rest=()
for f in "${files[@]}"; do
    case "$(basename "$f")" in
        system_types_pkg.sv|mlp_weights.sv) pkgs+=("$f") ;;
        *)                                  rest+=("$f") ;;
    esac
done
files=("${pkgs[@]}" "${rest[@]}")

build_dir=$rtl_root/sim_verilator
obj_dir=$build_dir/obj_${top}
mkdir -p "$build_dir" && cd "$build_dir" || die "cannot enter $build_dir"
[ "${1:-}" = "--rebuild" ] && rm -rf "$obj_dir"

echo "[run] verilating ${#files[@]} RTL files..."
verilator --binary -j 0 --timing --top-module "$top" \
    --Mdir "$obj_dir" -o "V$top" -CFLAGS -O2 -DRTL_SIM -Wno-fatal \
    -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-UNOPTFLAT -Wno-DECLFILENAME \
    -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM -Wno-VARHIDDEN -Wno-CASEINCOMPLETE \
    -Wno-SYNCASYNCNET -Wno-MULTIDRIVEN \
    "${files[@]}" "$tb_src" || die "verilator build failed"

echo "[run] running   (cwd $PWD)"
"$obj_dir/V$top"
echo "[run] exit $?"
