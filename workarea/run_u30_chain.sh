#!/bin/bash
# opensky bottom-up rebuild at 30% core utilization (FP_openroad_config
# oss,fp,core_utilization 30; no per-block die_area override).
#   gcd -> ctrl_subsys -> mac_array -> ai_subsys -> opensky_chip
# Each block: [SYNTH] -> FP -> PNR, release, then library-manager add
# (OSS0 block library) so the parent reads the new abstract.
set -e
cd "$(dirname "$0")"
WA=$PWD
C=$WA/../bin/cbflow
RUN=oss_u30
LOG=$WA/u30_chain.log
REL=$WA/../test_releases/P0

say() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }

# mk_uc <block> <src uc> <dst uc> <sed expr>...
mk_uc() {
    local b=$1 src=$2 dst=$3; shift 3
    local args=(-e "s/^set flow(run_name) .*/set flow(run_name)             \"$RUN\"/"
                -e '/^set fp(oss,fp,die_area)/d')
    for e in "$@"; do args+=(-e "$e"); done
    sed "${args[@]}" "$WA/$b/$src" > "$WA/$b/$dst"
}

# run_flow <block> <FLOW> <uc>
run_flow() {
    local b=$1 f=$2 uc=$3 rd="P0_run_${2}_${1}_${RUN}"
    local fl; fl=$(echo "$f" | tr 'A-Z' 'a-z')
    say "$b $f: create ($uc)"
    (cd "$WA/$b" && rm -rf "$rd" && $C workspace create --config "$uc") >> "$LOG" 2>&1
    say "$b $f: run all ($rd)"
    (cd "$WA/$b/$rd" && $C run all) > "$WA/$b/${fl}_u30.log" 2>&1 || true
    if grep -q "result=PASS" "$WA/$b/${fl}_u30.log"; then
        say "$b $f: PASS"
    else
        say "$b $f: FAILED — see $b/${fl}_u30.log"; exit 1
    fi
}

lib_add() {
    say "$1: library-manager add $2"
    $C flow library-manager add --tech skywater_130nm --tag OSS0 --category block \
        --project opensky --path "$REL/$1/$2" >> "$LOG" 2>&1
}

rel_tag() { sed -e 's/^/s|^set project(release,tag) .*|set project(release,tag)       "/' -e 's/$/"|/' <<< "$1"; }

# fp_pnr <block> <FP tag> <PNR tag> [FP sed expr]
fp_pnr() {
    local b=$1 fpt=$2 pnrt=$3; shift 3
    mk_uc "$b" uc_FP_openroad.tcl uc_FP_openroad_u30.tcl "$(rel_tag "$fpt")" "$@"
    run_flow "$b" FP uc_FP_openroad_u30.tcl
    mk_uc "$b" uc_PNR_openroad.tcl uc_PNR_openroad_u30.tcl "$(rel_tag "$pnrt")" \
        "s|^set pnr(input,def_file_release_tag) .*|set pnr(input,def_file_release_tag) \"$fpt\"|"
    run_flow "$b" PNR uc_PNR_openroad_u30.tcl
    grep -h "Design area" "$WA/$b/P0_run_FP_${b}_${RUN}"/work/FP/*/reports/design_area.rpt 2>/dev/null \
        | head -1 | sed "s/^/[$b FP] /" | tee -a "$LOG"
}

lef_size() { awk '/^ *SIZE/ {print $2, $4; exit}' "$REL/$1/$2/lef/$1.lef"; }

: > "$LOG"
say "chain start (core_utilization 30)"

fp_pnr gcd P0_FP_v2 P0_PNR_v3
lib_add gcd P0_PNR_v3

fp_pnr ctrl_subsys P0_FP_v1 P0_PNR_v2 \
    's|^set fp(oss,macro,placement) .*|set fp(oss,macro,placement)     {u_gcd 40 40 R0}|'
lib_add ctrl_subsys P0_PNR_v2

fp_pnr mac_array P0_FP_v1 P0_PNR_v2
lib_add mac_array P0_PNR_v2

fp_pnr ai_subsys P0_FP_v1 P0_PNR_v1 \
    's|^set fp(oss,macro,placement) .*|set fp(oss,macro,placement)     {u_mac_array 40 40 R0}|'
lib_add ai_subsys P0_PNR_v1

# Chip: ctrl_subsys sits right of ai_subsys with an 80um channel
read AIW AIH <<< "$(lef_size ai_subsys P0_PNR_v1)"
CX=$(awk -v w="$AIW" 'BEGIN { printf "%.2f", int((40 + w + 80) / 0.46 + 1) * 0.46 }')
say "opensky_chip: ai_subsys ${AIW}x${AIH} -> u_ctrl_subsys at x=$CX"
mk_uc opensky_chip uc_SYNTH_yosys.tcl uc_SYNTH_yosys_u30.tcl "$(rel_tag P0_SYNTH_v1)"
run_flow opensky_chip SYNTH uc_SYNTH_yosys_u30.tcl
fp_pnr opensky_chip P0_FP_v1 P0_PNR_v1 \
    "s|^set fp(oss,macro,placement) .*|set fp(oss,macro,placement)     {u_ai_subsys 40 54.4 R0 u_ctrl_subsys $CX 54.4 R0}|"

say "CHAIN PASS"
