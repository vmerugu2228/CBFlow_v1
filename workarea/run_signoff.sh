#!/bin/bash
# Signoff for a block whose PNR is released: STA (OpenSTA), PV (Magic/Netgen)
# and LEC (Yosys) in parallel, each consuming the PNR exit release and
# releasing <FLOW>_<exit> (e.g. STA_PRO_EXIT). CLP has no open-source tool.
#   usage: run_signoff.sh <block> [pnr_exit_tag]   (default PRO_EXIT)
cd "$(dirname "$0")"
WA=$PWD
C=$WA/../bin/cbflow
B=$1; EXIT=${2:-PRO_EXIT}; RUN=oss_u10
LOG=$WA/signoff.log
[ -d "$WA/$B" ] || { echo "no block $B"; exit 1; }

say() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }

# mk <FLOW> <template uc in gcd/> — per-block uc: design, run name, tags
mk() {
    local f=$1 src=$2 dst="$WA/$B/uc_${1}_signoff.tcl"
    sed -e "s/^set flow(design_name) .*/set flow(design_name)          \"$B\"/" \
        -e "s/^set flow(run_name) .*/set flow(run_name)             \"$RUN\"/" \
        -e "s/^set sta(input,release_tag) *\"[^\"]*\"/set sta(input,release_tag)     \"$EXIT\"/" \
        -e "s/^set pv(input,release_tag) *\"[^\"]*\"/set pv(input,release_tag)      \"$EXIT\"/" \
        -e "s/^set lec(input,netlist_golden_release_tag) .*/set lec(input,netlist_golden_release_tag)  \"P0_SYNTH_v1\"/" \
        -e "s/^set lec(input,netlist_revised_release_tag) .*/set lec(input,netlist_revised_release_tag) \"$EXIT\"/" \
        -e "s/^set project(release,tag) .*/set project(release,tag)       \"${f}_${EXIT}\"/" \
        "$WA/gcd/$src" > "$dst"
    echo "$dst"
}

run() {
    local f=$1 uc=$2 rd="P0_run_${1}_${B}_${RUN}"
    local fl; fl=$(echo "$f" | tr 'A-Z' 'a-z')
    say "$B $f: start (input $EXIT)"
    (cd "$WA/$B" && rm -rf "$rd" && $C workspace create --config "$uc") > "$WA/$B/${fl}_signoff_create.log" 2>&1
    (cd "$WA/$B/$rd" && $C run all) > "$WA/$B/${fl}_signoff.log" 2>&1
    if grep -q "result=PASS" "$WA/$B/${fl}_signoff.log"; then
        say "$B $f: PASS -> release ${f}_${EXIT}"
    else
        say "$B $f: FAILED — see $B/${fl}_signoff.log"
    fi
}

run STA "$(mk STA uc_STA_opensta.tcl)" &
run PV  "$(mk PV  uc_PV_magic.tcl)" &
run LEC "$(mk LEC uc_LEC_yosys.tcl)" &
wait
say "$B signoff done"
