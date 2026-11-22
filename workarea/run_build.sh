#!/bin/bash
# opensky build, bottom-up and in parallel (sizing from each block's uc files):
#   gcd ─────────┐                         DL3, in parallel
#   mac_array ───┼─┐
#   ctrl_subsys ◄┘ │  starts when gcd is in the block library      DL2, in parallel
#   ai_subsys ◄────┘  starts when mac_array is in the block library
#   opensky_chip ◄── starts when both DL2s are in the block library  DL1
# Per block: SYNTH -> FP -> PNR, publish FP_EXIT + PRO_EXIT, block library add
# (PNR/PRO_EXIT), then signoff (STA / PV / LEC in parallel, each releasing
# <FLOW>/PRO_EXIT and attaching to the PRO_EXIT entry in SmartGrid).
# Releases: <release,path>/P0/<block>/<FLOW>/<tag>.
cd "$(dirname "$0")"
WA=$PWD
C=$WA/../bin/cbflow
export RUN=oss_b1
LOG=$WA/build.log
REL=$WA/../test_releases/P0

say() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }

# mk_uc <block> <src uc> <dst uc> [sed expr]...  — run name + extra edits
mk_uc() {
    local b=$1 src=$2 dst=$3; shift 3
    local args=(-e "s/^set flow(run_name) .*/set flow(run_name)             \"$RUN\"/")
    for e in "$@"; do args+=(-e "$e"); done
    sed "${args[@]}" "$WA/$b/$src" > "$WA/$b/$dst"
}

# run_flow <block> <FLOW> <uc>  — non-zero on failure
run_flow() {
    local b=$1 f=$2 uc=$3 rd="P0_run_${2}_${1}_${RUN}"
    local fl; fl=$(echo "$f" | tr 'A-Z' 'a-z')
    say "$b $f: start"
    (cd "$WA/$b" && rm -rf "$rd" && $C workspace create --config "$uc") > "$WA/$b/${fl}_b1_create.log" 2>&1
    (cd "$WA/$b/$rd" && $C run all) > "$WA/$b/${fl}_b1.log" 2>&1
    if grep -q "result=PASS" "$WA/$b/${fl}_b1.log"; then
        say "$b $f: PASS"
    else
        say "$b $f: FAILED — see $b/${fl}_b1.log"; return 1
    fi
}

publish() {   # one publish at a time
    local b=$1 rd=$2 lock="$WA/.publish.lock"
    while ! mkdir "$lock" 2>/dev/null; do sleep 2; done
    (cd "$WA/$b" && $C run release --from-run "$rd" --publish 2>&1) \
        | grep -E "Published:|Not published|ERROR" | sed "s|^|$b $rd: |" | tee -a "$LOG"
    rmdir "$lock"
}

no_tag='/^set project(release,tag)/d'

# block <name> — SYNTH -> FP -> PNR -> publish -> library -> signoff (background)
block() {
    local b=$1
    run_flow "$b" SYNTH uc_SYNTH_yosys.tcl || return 1
    mk_uc "$b" uc_FP_openroad.tcl uc_FP_openroad_b1.tcl "$no_tag"
    [ -n "$FP_APPEND" ] && echo "$FP_APPEND" >> "$WA/$b/uc_FP_openroad_b1.tcl"
    run_flow "$b" FP uc_FP_openroad_b1.tcl || return 1
    publish "$b" "P0_run_FP_${b}_${RUN}"
    mk_uc "$b" uc_PNR_openroad.tcl uc_PNR_openroad_b1.tcl "$no_tag" \
        's|^set pnr(input,def_file_release_tag) .*|set pnr(input,def_file_release_tag) "FP_EXIT"|'
    run_flow "$b" PNR uc_PNR_openroad_b1.tcl || return 1
    publish "$b" "P0_run_PNR_${b}_${RUN}"
    local tag; tag=$(awk '/^milestone/ {print $2}' "$WA/$b/P0_run_PNR_${b}_${RUN}"/work/PNR/release_data1/outputs/release.manifest)
    [ -n "$tag" ] || { say "$b: no PNR exit tag in release.manifest"; return 1; }
    say "$b: library-manager add PNR/$tag"
    $C flow library-manager add --tech skywater_130nm --tag OSS0 --category block \
        --project opensky --path "$REL/$b/PNR/$tag" >> "$LOG" 2>&1 || return 1
    echo "$tag" > "$WA/.$b.done"
    "$WA/run_signoff.sh" "$b" "$tag" &
}

wait_for() { while [ ! -f "$WA/.$1.done" ]; do [ -f "$WA/.$1.failed" ] && return 1; sleep 30; done; }
run_block() {
    [ -f "$WA/.$1.done" ] && { say "$1: already built (resume)"; return 0; }
    block "$@" || { touch "$WA/.$1.failed"; say "$1: chain stopped"; return 1; }
}
lef_size() { awk '/^ *SIZE/ {print $2, $4; exit}' "$REL/$1/PNR/$(cat "$WA/.$1.done")/lef/$1.lef"; }

# RESUME=1 keeps finished blocks (.<block>.done) and retries the failed ones
if [ "$RESUME" = 1 ]; then
    rm -f "$WA"/.*.failed
else
    : > "$LOG"; rm -f "$WA"/.*.done "$WA"/.*.failed
fi
rmdir "$WA/.publish.lock" 2>/dev/null
for b in gcd mac_array ctrl_subsys ai_subsys opensky_chip; do
    sed -i '' "s/^set flow(run_name) .*/set flow(run_name)             \"$RUN\"/" "$WA/$b/uc_SYNTH_yosys.tcl"
done
say "start: parallel bottom-up build ($RUN)${RESUME:+ — resume}"

run_block gcd &
run_block mac_array &
( wait_for gcd && run_block ctrl_subsys ) &
( wait_for mac_array && run_block ai_subsys ) &
(
    wait_for ctrl_subsys && wait_for ai_subsys || exit 1
    # DL2 children sit on the rail pitch: explicit die + placement from their
    # abstracts — ai_subsys at (40, 54.4), ctrl_subsys right of it, 80 um channels
    read AW AH <<< "$(lef_size ai_subsys)"
    read CW CH <<< "$(lef_size ctrl_subsys)"
    CX=$(awk -v w="$AW" 'BEGIN { printf "%.2f", int((40 + w + 80) / 0.46 + 1) * 0.46 }')
    DW=$(awk -v x="$CX" -v w="$CW" 'BEGIN { printf "%d", x + w + 80 }')
    DH=$(awk -v a="$AH" -v c="$CH" 'BEGIN { m = (a > c ? a : c); printf "%d", 54.4 + m + 80 }')
    say "opensky_chip: ai ${AW}x${AH}, ctrl ${CW}x${CH} -> die ${DW}x${DH}, ctrl at x=$CX"
    FP_APPEND="set fp(oss,fp,die_area)         {0 0 $DW $DH}
set fp(oss,macro,placement)     {u_ai_subsys 40 54.4 R0 u_ctrl_subsys $CX 54.4 R0}" run_block opensky_chip
) &
wait
if [ -f "$WA/.opensky_chip.done" ]; then say "BUILD PASS"; else say "BUILD DONE WITH FAILURES"; fi
