#!/bin/bash
# opensky fresh build, bottom-up, in parallel (sizing from each block's uc files):
#   gcd ─────────┐                         (DL3, parallel)
#   mac_array ───┼─┐
#   ctrl_subsys ◄┘ │  starts when gcd is released      (DL2, parallel)
#   ai_subsys ◄────┘  starts when mac_array is released
#   opensky_chip ◄── starts when both DL2s are released (DL1)
# Each block: SYNTH -> FP -> PNR; FP/PNR release under the exit name (default
# tag), then library-manager add (OSS0) so the parent reads the abstract.
cd "$(dirname "$0")"
WA=$PWD
C=$WA/../bin/cbflow
RUN=oss_u10
LOG=$WA/u10_parallel.log
REL=$WA/../test_releases/P0

say() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }

# mk_uc <block> <src uc> <dst uc> [sed expr]...  — run name + extra edits;
# utilization / die size / density come from the block's uc files
mk_uc() {
    local b=$1 src=$2 dst=$3; shift 3
    local args=(-e "s/^set flow(run_name) .*/set flow(run_name)             \"$RUN\"/")
    for e in "$@"; do args+=(-e "$e"); done
    sed "${args[@]}" "$WA/$b/$src" > "$WA/$b/$dst"
}

# run_flow <block> <FLOW> <uc>  — returns non-zero on failure
run_flow() {
    local b=$1 f=$2 uc=$3 rd="P0_run_${2}_${1}_${RUN}"
    local fl; fl=$(echo "$f" | tr 'A-Z' 'a-z')
    say "$b $f: start"
    (cd "$WA/$b" && rm -rf "$rd" && $C workspace create --config "$uc") >> "$WA/$b/${fl}_u10_create.log" 2>&1
    (cd "$WA/$b/$rd" && $C run all) > "$WA/$b/${fl}_u10.log" 2>&1
    if grep -q "result=PASS" "$WA/$b/${fl}_u10.log"; then
        say "$b $f: PASS"
    else
        say "$b $f: FAILED — see $b/${fl}_u10.log"; return 1
    fi
}

lib_add() {
    say "$1: library-manager add $2"
    $C flow library-manager add --tech skywater_130nm --tag OSS0 --category block \
        --project opensky --path "$REL/$1/$2" >> "$LOG" 2>&1
}

no_tag='/^set project(release,tag)/d'

# block <name> [FP sed expr]  — SYNTH -> FP -> PNR -> lib add; touches .<name>.done
block() {
    local b=$1; shift
    rm -f "$WA/.$b.done"
    run_flow "$b" SYNTH uc_SYNTH_yosys.tcl || return 1
    mk_uc "$b" uc_FP_openroad.tcl uc_FP_openroad_u10.tcl "$no_tag" "$@"
    [ -n "$FP_APPEND" ] && echo "$FP_APPEND" >> "$WA/$b/uc_FP_openroad_u10.tcl"
    run_flow "$b" FP uc_FP_openroad_u10.tcl || return 1
    grep -h "Design area\|Floorplan:" "$WA/$b/P0_run_FP_${b}_${RUN}"/work/FP/*/run/*.log 2>/dev/null \
        | grep -v "^\s*$" | head -2 | sed "s/^/[$b FP] /" | tee -a "$LOG"
    mk_uc "$b" uc_PNR_openroad.tcl uc_PNR_openroad_u10.tcl "$no_tag" \
        's|^set pnr(input,def_file_release_tag) .*|set pnr(input,def_file_release_tag) "FP_EXIT"|'
    run_flow "$b" PNR uc_PNR_openroad_u10.tcl || return 1
    local tag; tag=$(awk '/^milestone/ {print $2}' "$WA/$b/P0_run_PNR_${b}_${RUN}"/work/PNR/release_data1/outputs/release.manifest 2>/dev/null)
    [ -n "$tag" ] || { say "$b: no PNR release tag in release.manifest"; return 1; }
    lib_add "$b" "$tag" || return 1
    echo "$tag" > "$WA/.$b.done"
}

wait_for() { while [ ! -f "$WA/.$1.done" ]; do [ -f "$WA/.$1.failed" ] && return 1; sleep 30; done; }
run_block() { block "$@" || { touch "$WA/.$1.failed"; say "$1: chain stopped"; return 1; }; }

# lef_size <block> — SIZE of the abstract from the block's PNR release
lef_size() { awk '/^ *SIZE/ {print $2, $4; exit}' "$REL/$1/$(cat "$WA/.$1.done")/lef/$1.lef"; }

: > "$LOG"; rm -f "$WA"/.*.done "$WA"/.*.failed
# synth uc files: run name only (SYNTH keeps its explicit tag — not an exit)
for b in gcd mac_array ctrl_subsys ai_subsys opensky_chip; do
    sed -i '' "s/^set flow(run_name) .*/set flow(run_name)             \"$RUN\"/" "$WA/$b/uc_SYNTH_yosys.tcl"
done
say "start: parallel bottom-up (sizing from uc files)"

run_block gcd &
run_block mac_array &
( wait_for gcd && run_block ctrl_subsys ) &
( wait_for mac_array && run_block ai_subsys ) &
(
    wait_for ctrl_subsys && wait_for ai_subsys || exit 1
    read AW AH <<< "$(lef_size ai_subsys)"
    read CW CH <<< "$(lef_size ctrl_subsys)"
    # ai_subsys at (40, 54.4); ctrl_subsys right of it with an 80um channel
    CX=$(awk -v w="$AW" 'BEGIN { printf "%.2f", int((40 + w + 80) / 0.46 + 1) * 0.46 }')
    DW=$(awk -v x="$CX" -v w="$CW" 'BEGIN { printf "%d", x + w + 80 }')
    DH=$(awk -v a="$AH" -v c="$CH" 'BEGIN { m = (a > c ? a : c); printf "%d", 54.4 + m + 80 }')
    say "opensky_chip: ai ${AW}x${AH}, ctrl ${CW}x${CH} -> die ${DW}x${DH}, ctrl at x=$CX"
    FP_APPEND="set fp(oss,fp,die_area)         {0 0 $DW $DH}" run_block opensky_chip \
        "s|^set fp(oss,macro,placement) .*|set fp(oss,macro,placement)     {u_ai_subsys 40 54.4 R0 u_ctrl_subsys $CX 54.4 R0}|"
) &
wait
if [ -f "$WA/.opensky_chip.done" ]; then say "ALL PASS"; else say "DONE WITH FAILURES"; fi
