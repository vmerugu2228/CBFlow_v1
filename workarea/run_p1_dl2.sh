#!/bin/bash
# opensky P1 for DL2 blocks (children from library tag $LIB_TAG), in parallel:
#   SYNTH (P1_SYNTH_v1) -> FP (FP_EXIT) -> PV on FP (background) -> PNR
#   (PRO_EXIT) -> publish FP_EXIT + PRO_EXIT -> signoff (STA / PV / LEC).
# project(phase) "P1" + project(lib_config_tag) "$LIB_TAG" per run.
#   usage: run_p1_dl2.sh <block>...      (e.g. ctrl_subsys)
cd "$(dirname "$0")"
WA=$PWD
C=$WA/../bin/cbflow
export PHASE=P1 RUN=p1_b1 LIB_TAG=OSS1
LOG=$WA/build_p1_dl2.log
SYN_TAG="${PHASE}_SYNTH_v1"

say() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }

# mk_uc <block> <src uc> <dst uc> [sed expr]...  — run name, phase, tags
mk_uc() {
    local b=$1 src=$2 dst=$3; shift 3
    local args=(-e "s/^set flow(run_name) .*/set flow(run_name)             \"$RUN\"/"
                -e '/^set project(phase)/d' -e '/^set project(release,phase)/d' \
                -e '/^set project(lib_config_tag)/d')
    for e in "$@"; do args+=(-e "$e"); done
    sed "${args[@]}" "$WA/$b/$src" > "$WA/$b/$dst"
    echo "set project(phase)             \"$PHASE\"" >> "$WA/$b/$dst"
    echo "set project(release,phase)     \"$PHASE\"" >> "$WA/$b/$dst"
    echo "set project(lib_config_tag)    \"$LIB_TAG\"" >> "$WA/$b/$dst"
}

run_flow() {    # run_flow <block> <FLOW> <uc>  — non-zero on failure
    local b=$1 f=$2 uc=$3 rd="${PHASE}_run_${2}_${1}_${RUN}"
    local fl; fl=$(echo "$f" | tr 'A-Z' 'a-z')
    say "$b $f: start"
    (cd "$WA/$b" && rm -rf "$rd" && $C workspace create --config "$uc") > "$WA/$b/${fl}_${PHASE}_create.log" 2>&1
    (cd "$WA/$b/$rd" && $C run all) > "$WA/$b/${fl}_${PHASE}.log" 2>&1
    if grep -q "result=PASS" "$WA/$b/${fl}_${PHASE}.log"; then
        say "$b $f: PASS"
    else
        say "$b $f: FAILED — see $b/${fl}_${PHASE}.log"; return 1
    fi
}

publish() {   # one publish at a time (lock shared with the P0 build)
    local b=$1 rd=$2 lock="$WA/.publish.lock"
    while ! mkdir "$lock" 2>/dev/null; do sleep 2; done
    (cd "$WA/$b" && $C run release --from-run "$rd" --publish 2>&1) \
        | grep -E "Published:|Not published|ERROR" | sed "s|^|$b $rd: |" | tee -a "$LOG"
    rmdir "$lock"
}

block() {
    local b=$1
    mk_uc "$b" uc_SYNTH_yosys.tcl "uc_SYNTH_yosys_${PHASE}.tcl" \
        "s/^set project(release,tag) .*/set project(release,tag)       \"$SYN_TAG\"/"
    run_flow "$b" SYNTH "uc_SYNTH_yosys_${PHASE}.tcl" || return 1
    mk_uc "$b" uc_FP_openroad.tcl "uc_FP_openroad_${PHASE}.tcl" '/^set project(release,tag)/d' \
        "s/^set fp(input,release_tag) .*/set fp(input,release_tag)      \"$SYN_TAG\"/"
    run_flow "$b" FP "uc_FP_openroad_${PHASE}.tcl" || return 1
    publish "$b" "${PHASE}_run_FP_${b}_${RUN}"
    "$WA/run_signoff.sh" "$b" FP_EXIT &          # PV on the floorplan release
    mk_uc "$b" uc_PNR_openroad.tcl "uc_PNR_openroad_${PHASE}.tcl" '/^set project(release,tag)/d' \
        "s/^set pnr(input,release_tag) .*/set pnr(input,release_tag)     \"$SYN_TAG\"/" \
        's|^set pnr(input,def_file_release_tag) .*|set pnr(input,def_file_release_tag) "FP_EXIT"|'
    run_flow "$b" PNR "uc_PNR_openroad_${PHASE}.tcl" || return 1
    publish "$b" "${PHASE}_run_PNR_${b}_${RUN}"
    "$WA/run_signoff.sh" "$b" PRO_EXIT
}

: > "$LOG"
[ $# -gt 0 ] || { echo "usage: $0 <block>..."; exit 1; }
say "start: $PHASE DL2 blocks $* ($RUN, lib tag $LIB_TAG)"
for b in "$@"; do ( block "$b" || say "$b: chain stopped" ) & done
wait
say "$PHASE DL2 done"
