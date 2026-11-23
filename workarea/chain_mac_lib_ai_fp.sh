#!/usr/bin/env bash
# mac_array P1 PV (alone: DRC then LVS, KLayout 1 thread) -> publish ->
# lib tag OSS1 refresh (block views; GDS / CDL from the PV release) ->
# ai_subsys die from the released mac_array abstract -> ai_subsys P1 SYNTH + FP.
set -e
WA=$(cd "$(dirname "$0")" && pwd); cd "$WA"
C=$WA/../bin/cbflow
LOG=$WA/build_p1.log
say() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }

PV=mac_array/P1_run_PV_mac_array_p1_b1
if ! grep -q "max_parallel_jobs" $PV/setup/user_config.tcl; then
    printf '\n# Memory: DRC and LVS one at a time; KLayout single-threaded\nset flow(max_parallel_jobs) 1\nset pv(oss,drc,klayout_threads) 1\n' >> $PV/setup/user_config.tcl
fi
say "mac_array PV: start (alone)"
(cd $PV && $C run all > ../pv_serial.log 2>&1) && say "mac_array PV: PASS" || { say "mac_array PV: RUN FAILED — see mac_array/pv_serial.log"; exit 1; }
(cd mac_array && $C run release --from-run P1_run_PV_mac_array_p1_b1 --publish --override 2>&1) | grep -E "Published:|Not published|ERROR" | sed 's|^|mac_array PV: |' | tee -a "$LOG"

say "OSS1: library-manager add mac_array (PNR/PRO_EXIT + PV/PRO_EXIT)"
$C flow library-manager add --tech skywater_130nm --tag OSS1 --category block \
    --project opensky --path "$WA/../test_releases/P1/mac_array/PNR/PRO_EXIT" >> "$LOG" 2>&1 \
    || { say "OSS1: library-manager add FAILED"; exit 1; }
say "OSS1: mac_array views refreshed"

LEF=~/eda/lib_tags/skywater_130nm/OSS1/block/mac_array/lef/mac_array.lef
read W H < <(awk '/^ *SIZE/ {print $2, $4; exit}' "$LEF")
DIE=$(python3 -c "import math; print(f'0 0 {10.12+math.ceil($W/0.46)*0.46+20+10.12:.2f} {10.88+$H+500+10.88:.2f}')")
sed -i '' "s/^set fp(oss,fp,die_area) .*/set fp(oss,fp,die_area)         {$DIE}   ;# mac_array ${W} x ${H}/" ai_subsys/uc_FP_openroad.tcl
say "ai_subsys die {$DIE} (mac_array $W x $H)"

UNTIL=FP PUBLISH_OVERRIDE=1 ./run_p1_dl2.sh ai_subsys > build_p1_dl2.out 2>&1
