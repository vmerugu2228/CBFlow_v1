#!/usr/bin/env bash
# mac_array P1 (re-floorplanned) -> size the ai_subsys die from mac_array's
# released abstract -> ai_subsys P1. Publishes replace existing P1 entries.
set -e
WA=$(cd "$(dirname "$0")" && pwd); cd "$WA"
export PUBLISH_OVERRIDE=1
./run_p1_dl3.sh mac_array > build_p1.out 2>&1
# lib tag OSS1 holds copies of the block views — refresh mac_array's
../bin/cbflow flow library-manager add --tech skywater_130nm --tag OSS1 --category block \
    --project opensky --path "$WA/../test_releases/P1/mac_array/PNR/PRO_EXIT" >> build_p1.log 2>&1
echo "[$(date +%T)] OSS1: mac_array views refreshed" >> build_p1.log
LEF=~/eda/lib_tags/skywater_130nm/OSS1/block/mac_array/lef/mac_array.lef
read W H < <(awk '/^ *SIZE/ {print $2, $4; exit}' "$LEF")
# mac_array on the core bottom edge, filling the core width; 500 um logic band above
DIE=$(python3 -c "import math; print(f'0 0 {10.12+math.ceil($W/0.46)*0.46+10.12:.2f} {10.88+$H+500+10.88:.2f}')")
sed -i '' "s/^set fp(oss,fp,die_area) .*/set fp(oss,fp,die_area)         {$DIE}   ;# mac_array ${W} x ${H}/" ai_subsys/uc_FP_openroad.tcl
echo "[$(date +%T)] ai_subsys die {$DIE} (mac_array $W x $H)" >> build_p1.log
./run_p1_dl2.sh ai_subsys > build_p1_dl2.out 2>&1
