#!/bin/bash
# mac_array P1: PNR re-run from place1 with overrides/pnr_P1.tcl (fanout limit,
# 4/6/8 scenarios), publish PRO_EXIT, then signoff (STA / PV / LEC).
cd "$(dirname "$0")"; WA=$PWD; C=$WA/../bin/cbflow; LOG=$WA/build_p1.log
export PHASE=P1 RUN=p1_b1 LIB_TAG=OSS1
say() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }
R=mac_array/P1_run_PNR_mac_array_p1_b1
say "mac_array PNR: re-run from place1 (overrides/pnr_P1.tcl)"
(cd "$WA/$R" && $C run retrace --from place1 && $C run all) > "$WA/mac_array/pnr_P1_rerun.log" 2>&1
grep -q "result=PASS" "$WA/mac_array/pnr_P1_rerun.log" || { say "mac_array PNR: FAILED — see mac_array/pnr_P1_rerun.log"; exit 1; }
say "mac_array PNR: PASS"
lock="$WA/.publish.lock"; while ! mkdir "$lock" 2>/dev/null; do sleep 2; done
(cd "$WA/mac_array" && $C run release --from-run P1_run_PNR_mac_array_p1_b1 --publish --override 2>&1) | grep -E "Published:|Not published|ERROR" | sed "s|^|mac_array: |" | tee -a "$LOG"
rmdir "$lock"
"$WA/run_signoff.sh" mac_array PRO_EXIT
