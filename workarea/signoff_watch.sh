#!/bin/bash
# Start run_signoff.sh for each block whose PNR passes in the u10 build.
cd "$(dirname "$0")"
DONE=.signoff_started; touch $DONE
while true; do
    grep -E "^\[[0-9:]+\] [a-z_]+ PNR: PASS" u10_parallel.log | awk '{print $2}' | while read -r b; do
        grep -qx "$b" $DONE && continue
        echo "$b" >> $DONE
        sleep 60   # let the auto-publish of the PNR release go first
        ./run_signoff.sh "$b" &
    done
    grep -q "ALL PASS\|DONE WITH FAILURES" u10_parallel.log && { wait; exit 0; }
    sleep 30
done
