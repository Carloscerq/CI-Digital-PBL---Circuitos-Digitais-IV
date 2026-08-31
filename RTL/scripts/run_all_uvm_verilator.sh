#!/usr/bin/env bash
# ============================================================================
#  run_all_uvm_verilator.sh  --  run every UVM bench under Verilator, summarise.
#
#    ./run_all_uvm_verilator.sh                   # all benches
#    ./run_all_uvm_verilator.sh mac spi gcd       # just these
#    ./run_all_uvm_verilator.sh --build-only      # verilate + compile only
#    ./run_all_uvm_verilator.sh -- +UVM_VERBOSITY=UVM_HIGH   # all, extra plusargs
#
#  Everything after a lone -- is forwarded to the sim binary for every bench.
#  Exits non-zero if any bench failed, so it drops straight into CI -- and
#  unlike the Questa flow it needs no licence.
#
#  The first build of each bench compiles all of UVM (~2 min); install ccache
#  and later runs take seconds.
# ============================================================================
set -uo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
runner=$script_dir/uvm_verilator.sh

benches=()
extra=()
opts=()
seen_sep=0
for arg in "$@"; do
    if [ "$arg" = "--" ]; then seen_sep=1; continue; fi
    if   [ "$seen_sep" -eq 1 ];         then extra+=("$arg")
    elif [ "$arg" = "--build-only" ] || [ "$arg" = "--compile-only" ] \
      || [ "$arg" = "--rebuild" ] || [ "$arg" = "--trace" ]; then opts+=("$arg")
    else benches+=("$arg")
    fi
done

if [ ${#benches[@]} -eq 0 ]; then
    mapfile -t benches < <("$runner" --list)
fi

results=()
failed=0

for b in "${benches[@]}"; do
    echo
    echo "############################################################"
    echo "#  $b"
    echo "############################################################"
    "$runner" "${opts[@]+"${opts[@]}"}" "$b" "${extra[@]+"${extra[@]}"}"
    if [ $? -eq 0 ]; then results+=("PASS     $b")
    else                 results+=("FAIL     $b"); failed=$((failed + 1))
    fi
done

echo
echo "============================================================"
echo "  UVM regression summary (Verilator)"
echo "============================================================"
printf '  %s\n' "${results[@]}"
echo "------------------------------------------------------------"
echo "  ${#benches[@]} bench(es), $failed failed"
echo "  logs: $(cd -- "$script_dir/.." && pwd)/sim_verilator/<bench>.log"
echo "============================================================"

[ "$failed" -eq 0 ]
