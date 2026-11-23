#!/usr/bin/env bash
# gcd P2: PRO_EXIT (export rewired onto pro1) -> publish -> STA on the
# PRO_EXIT release tag; then a full run releases BTO (order gate passes).
cd "$(dirname "$0")/gcd"
C=/Users/vmerugu/projects/CBflow_clone/bin/cbflow
LOG=../test_exit_order.log; : > $LOG
say() { echo "[$(date +%H:%M:%S)] $*" | tee -a $LOG; }
mk() { local t=$1 rd="P2_run_PNR_gcd_$1"
    if [ -d $rd ]; then P=$(cat $rd/.race_db_pointer 2>/dev/null); [ -n "$P" ] && rm -f "$P" "$P-wal" "$P-shm"; rm -rf $rd; fi
    sed -e "s/^set flow(run_name) .*/set flow(run_name)             \"$t\"/" uc_PNR_openroad_P2.tcl > uc_PNR_$t.tcl
    $C workspace create --config uc_PNR_$t.tcl > ${t}_create.log 2>&1 && echo $rd; }
say "=== PRO_EXIT via set-dep export_data1 -> pro1"
rd=$(mk p2pro) || { say "create FAILED"; exit 1; }
(cd $rd && $C run set-dep --node export_data1 --deps pro1 > /dev/null 2>&1 && $C run stage --name release_data1 > ../p2pro_release.log 2>&1) && say "  release_data1 PASS" || say "  release_data1 FAILED"
say "  $(grep -h 'exit order' $rd/work/PNR/release_data1/run/*.log | head -1 | sed 's/.*INFO\] //')"
say "  manifest: $(tr '\n' ' ' < $rd/work/PNR/release_data1/outputs/release.manifest)"
$C run release --from-run $rd --publish 2>&1 | grep -E "Published|ERROR" | sed 's/^/  /' | tee -a $LOG
say "=== STA on the PRO_EXIT release"
(cd .. && FLOWS=STA PHASE=P2 RUN=p2_b1 LIB_TAG=OSS2 PUBLISH=1 ./run_signoff.sh gcd PRO_EXIT > /dev/null 2>&1)
say "  $(grep -h 'signoff inputs bound' P2_run_STA_gcd_p2_b1/work/STA/*/run/*.log 2>/dev/null | head -1 | sed 's/^INFO: //')"
say "  $(grep 'gcd STA' ../signoff.log | tail -1)"
say "  inputs: $(grep -h 'input,' P2_run_STA_gcd_p2_b1/setup/resolved_inputs.tcl 2>/dev/null | awk '{print $2"="$3}' | tr '\n' ' ')"
say "=== BTO full run (gate: PRO_EXIT now released)"
rd=$(mk p2bto) || { say "create FAILED"; exit 1; }
(cd $rd && $C run all > ../p2bto_all.log 2>&1) && say "  run all PASS" || say "  run all FAILED"
say "  $(grep -h 'exit order' $rd/work/PNR/release_data1/run/*.log | head -1 | sed 's/.*INFO\] //')"
say "  manifest: $(tr '\n' ' ' < $rd/work/PNR/release_data1/outputs/release.manifest 2>/dev/null)"
say "=== done"
