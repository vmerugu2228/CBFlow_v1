#!/usr/bin/env bash
# Verify the three ways to release an intermediate PNR stage on gcd P2:
#   A bypass the stages after it   B set-dep export_data1 -> it
#   C add export_data2 / release_data2 under it
# SRC=place1 (PLACE_EXIT, default) or SRC=cts_opt1 (CTS_EXIT)
SRC=${SRC:-place1}
case $SRC in
    place1)   BYP=cts1,cts_opt1,route1,pro1,signoff1 ;;
    cts_opt1) BYP=route1,pro1,signoff1 ;;
    *) echo "SRC must be place1 or cts_opt1"; exit 1 ;;
esac
TAG=$(echo $SRC | tr -d 0-9 | tr '_' 'x')
cd "$(dirname "$0")/gcd"
C=/Users/vmerugu/projects/CBflow_clone/bin/cbflow
LOG=../test_release_${SRC}.log
: > $LOG
say() { echo "[$(date +%H:%M:%S)] $*" | tee -a $LOG; }
mk() {   # mk <run tag> -> run dir
    local t=$1 rd="P2_run_PNR_gcd_$1"
    if [ -d $rd ]; then P=$(cat $rd/.race_db_pointer 2>/dev/null); [ -n "$P" ] && rm -f "$P" "$P-wal" "$P-shm"; rm -rf $rd; fi
    sed -e "s/^set flow(run_name) .*/set flow(run_name)             \"$t\"/" uc_PNR_openroad_P2.tcl > uc_PNR_$t.tcl
    $C workspace create --config uc_PNR_$t.tcl > ${t}_create.log 2>&1 || { say "$t: create FAILED"; return 1; }
    echo $rd
}
check() {  # check <run dir> <release node>
    local rd=$1 rn=$2 m=$1/work/PNR/$2/outputs/release.manifest
    [ -f $m ] || { say "  $rd $rn: NO manifest"; return 1; }
    say "  manifest: $(tr '\n' ' ' < $m)"
    local R=$(awk '/^release_dir/{print $2}' $m)
    say "  release files: $(cd $R && find . -type f | grep -v reports/ | sort | tr '\n' ' ')"
    say "  report dirs: $(ls $R/reports 2>/dev/null | tr '\n' ' ')"
    say "  export.source: $(tr '\n' ' ' < $rd/work/PNR/$(grep -o 'export_data[0-9]*' <<< "$(cat $rd/work/PNR/$rn/run/*.log 2>/dev/null | grep -o 'export_data[0-9]*' | head -1)")/outputs/export.source 2>/dev/null)"
}

say "=== A ($SRC): bypass $BYP"
rd=$(mk ${TAG}A) || exit 1
(cd $rd && $C run stage --name $SRC > ../${TAG}A_src.log 2>&1) && say "  $SRC PASS" || { say "  $SRC FAILED"; exit 1; }
(cd $rd && $C run bypass --stages $BYP > ../${TAG}A_bypass.log 2>&1); say "  markers: $(ls $rd/work/PNR/*/BYPASSED 2>/dev/null | xargs -n1 dirname | xargs -n1 basename | tr '\n' ' ')"
(cd $rd && $C run stage --name release_data1 > ../${TAG}A_release.log 2>&1) && say "  release_data1 PASS" || say "  release_data1 FAILED (see gcd/${TAG}A_release.log)"
check $rd release_data1
(cd . && $C run release --from-run $rd --publish --override 2>&1 | grep -E "Published|ERROR|Not published" | sed 's/^/  /' | tee -a $LOG)

say "=== B ($SRC): set-dep export_data1 -> $SRC"
rd=$(mk ${TAG}B) || exit 1
(cd $rd && $C run set-dep --node export_data1 --deps $SRC 2>&1 | grep -E "dependencies|ERROR|Circular" | sed 's/^/  /' | tee -a $LOG)
(cd $rd && $C run stage --name release_data1 > ../${TAG}B_release.log 2>&1) && say "  release_data1 PASS" || say "  release_data1 FAILED (see gcd/${TAG}B_release.log)"
say "  ran: $(cd $rd && $C run status 2>&1 | grep -E '\[DONE' | awk '{print $3}' | tr '\n' ' ')"
check $rd release_data1
(cd . && $C run release --from-run $rd --publish --override 2>&1 | grep -E "Published|ERROR|Not published" | sed 's/^/  /' | tee -a $LOG)

say "=== C ($SRC): add export_data2 / release_data2 under $SRC"
rd=$(mk ${TAG}C) || exit 1
(cd $rd && $C run add-node --node export_data2 --type export_data --dep $SRC > ../${TAG}C_add.log 2>&1 && $C run add-node --node release_data2 --type release_data --dep export_data2 >> ../${TAG}C_add.log 2>&1) && say "  nodes added" || say "  add-node FAILED (see gcd/${TAG}C_add.log)"
(cd $rd && $C run stage --name release_data2 > ../${TAG}C_release.log 2>&1) && say "  release_data2 PASS" || say "  release_data2 FAILED (see gcd/${TAG}C_release.log)"
say "  ran: $(cd $rd && $C run status 2>&1 | grep -E '\[DONE' | awk '{print $3}' | tr '\n' ' ')"
check $rd release_data2
(cd . && $C run release --from-run $rd --node release_data2 --publish --override 2>&1 | grep -E "Published|ERROR|Not published" | sed 's/^/  /' | tee -a $LOG)
say "=== done"
