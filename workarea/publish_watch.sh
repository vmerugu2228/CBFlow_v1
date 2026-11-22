#!/bin/bash
# Publish each FP / PNR release of the u10 build to SmartGrid as it passes
# (cbflow run release --from-run --publish; exit order is enforced there).
cd "$(dirname "$0")"
LOG=u10_parallel.log; DONE=.published_runs; touch $DONE
while true; do
    grep -E "^\[[0-9:]+\] [a-z_]+ (FP|PNR): PASS" $LOG | while read -r _ b f _; do
        rd="P0_run_${f%:}_${b}_oss_u10"
        grep -qx "$b/$rd" $DONE && continue
        (cd $b && ../../bin/cbflow run release --from-run $rd --publish 2>&1 | grep -E "Published:|Not published|ERROR" | sed "s|^|$b ${f%:}: |")
        echo "$b/$rd" >> $DONE
    done
    grep -q "ALL PASS\|DONE WITH FAILURES" $LOG && exit 0
    sleep 30
done
