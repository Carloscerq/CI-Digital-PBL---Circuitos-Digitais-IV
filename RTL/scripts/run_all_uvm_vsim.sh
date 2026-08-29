#!/usr/bin/env bash
# ============================================================================
#  run_all_uvm_vsim.sh  --  run every UVM bench under Questa and summarise.
#
#    ./run_all_uvm_vsim.sh                    # all benches
#    ./run_all_uvm_vsim.sh mac spi gcd        # just these
#    ./run_all_uvm_vsim.sh -- +UVM_VERBOSITY=UVM_HIGH   # all, extra vsim args
#
#  Everything after a lone -- is forwarded to vsim for every bench.
#  Exits non-zero if any bench failed, so it drops straight into CI.
# ============================================================================
set -uo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
runner=$script_dir/uvm_vsim.sh

benches=()
extra=()
opts=()
seen_sep=0
for arg in "$@"; do
    if [ "$arg" = "--" ]; then seen_sep=1; continue; fi
    if   [ "$seen_sep" -eq 1 ];        then extra+=("$arg")
    elif [ "$arg" = "--compile-only" ]; then opts+=("$arg")
    else benches+=("$arg")
    fi
done

if [ ${#benches[@]} -eq 0 ]; then
    mapfile -t benches < <("$runner" --list)
fi

results=()
failed=0
blocked=0

for b in "${benches[@]}"; do
    echo
    echo "############################################################"
    echo "#  $b"
    echo "############################################################"
    "$runner" "${opts[@]+"${opts[@]}"}" "$b" "${extra[@]+"${extra[@]}"}"
    case $? in
        0) results+=("PASS     $b") ;;
        3) results+=("BLOCKED  $b"); blocked=$((blocked + 1)) ;;   # no licence
        *) results+=("FAIL     $b"); failed=$((failed + 1)) ;;
    esac
done

echo
echo "============================================================"
echo "  UVM regression summary (Questa)"
echo "============================================================"
printf '  %s\n' "${results[@]}"
echo "------------------------------------------------------------"
echo "  ${#benches[@]} bench(es), $failed failed, $blocked blocked"
[ "$blocked" -gt 0 ] && echo "  BLOCKED = compiled, but no Questa simulation licence."
echo "  logs: $(cd -- "$script_dir/.." && pwd)/sim_vsim/<bench>.log"
echo "============================================================"

[ "$failed" -eq 0 ] && [ "$blocked" -eq 0 ]
