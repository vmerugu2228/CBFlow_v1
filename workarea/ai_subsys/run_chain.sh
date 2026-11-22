#!/bin/bash
# ai_subsys DL2 chain: SYNTH -> FP -> PNR (xterm mode), each consuming the previous release tag
set -e
cd "$(dirname "$0")"
C=../../bin/cbflow
$C workspace create --config uc_SYNTH_yosys.tcl
(cd P0_run_SYNTH_ai_subsys_oss_r1 && ../../../bin/cbflow run all) > synth_all.log 2>&1
grep -q "result=PASS" synth_all.log || { echo "SYNTH FAILED"; exit 1; }
$C workspace create --config uc_FP_openroad.tcl
(cd P0_run_FP_ai_subsys_oss_r1 && ../../../bin/cbflow run all) > fp_all.log 2>&1
grep -q "result=PASS" fp_all.log || { echo "FP FAILED"; exit 1; }
$C workspace create --config uc_PNR_openroad.tcl
(cd P0_run_PNR_ai_subsys_oss_r1 && ../../../bin/cbflow run all) > pnr_all.log 2>&1
grep -q "result=PASS" pnr_all.log || { echo "PNR FAILED"; exit 1; }
echo "CHAIN PASS"
