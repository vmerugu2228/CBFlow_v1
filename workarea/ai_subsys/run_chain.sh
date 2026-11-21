#!/bin/bash
# ai_subsys DL2 chain: SYNTH -> PNR (xterm mode), each consuming the previous release tag
set -e
cd "$(dirname "$0")"
C=../../bin/cbflow
$C workspace create --config uc_SYNTH_yosys.tcl
(cd P0_run_SYNTH_oss_r1 && ../../../bin/cbflow run all) > synth_all.log 2>&1
grep -q "result=PASS" synth_all.log || { echo "SYNTH FAILED"; exit 1; }
$C workspace create --config uc_PNR_openroad.tcl
(cd P0_run_PNR_oss_r1 && ../../../bin/cbflow run all) > pnr_all.log 2>&1
grep -q "result=PASS" pnr_all.log || { echo "PNR FAILED"; exit 1; }
echo "CHAIN PASS"
