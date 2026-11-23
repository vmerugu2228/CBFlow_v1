#!/bin/bash
# Signoff for a block whose PNR is released: STA (OpenSTA), PV (Magic/Netgen)
# and LEC (Yosys) in parallel, each consuming the PNR exit release and
# releasing under the exit name: <phase>/<block>/<FLOW>/<exit> (tag from
# <flow>(release,exit_from)). CLP has no open-source tool.
#   usage: run_signoff.sh <block> [exit_tag]   (default PRO_EXIT)
# exit_tag FP_EXIT: PV only on the FP release (floorplan GDS — no signal
# routing, so the verdict is DRC only: pv(signoff,lvs_required) false).
cd "$(dirname "$0")"
WA=$PWD
C=$WA/../bin/cbflow
B=$1; EXIT=${2:-PRO_EXIT}; RUN=${RUN:-oss_b1}; PHASE=${PHASE:-P0}
LOG=$WA/signoff.log
[ -d "$WA/$B" ] || { echo "no block $B"; exit 1; }

say() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }
PUBLISH=${PUBLISH:-1}

# One publish at a time (each refreshes the whole exit entry)
flock_publish() {
    local lock="$WA/.publish.lock"
    while ! mkdir "$lock" 2>/dev/null; do sleep 2; done
    $C run release --from-run "$1" --publish 2>&1 | grep -E "Published:|Not published|ERROR" | sed "s|^|$B $1: |" | tee -a "$LOG"
    rmdir "$lock"
}

# mk <FLOW> <template uc in gcd/> — per-block uc: design, run name, tags
mk() {
    local f=$1 src=$2 dst="$WA/$B/uc_${1}_signoff_${PHASE}_${EXIT}.tcl"
    sed -e "s/^set flow(design_name) .*/set flow(design_name)          \"$B\"/" \
        -e "s/^set flow(run_name) .*/set flow(run_name)             \"$RUN\"/" \
        -e "s/^set sta(input,release_tag) *\"[^\"]*\"/set sta(input,release_tag)     \"$EXIT\"/" \
        -e "s/^set pv(input,release_tag) *\"[^\"]*\"/set pv(input,release_tag)      \"$EXIT\"/" \
        -e "s/^set lec(input,netlist_golden_release_tag) .*/set lec(input,netlist_golden_release_tag)  \"${PHASE}_SYNTH_v1\"/" \
        -e "s/^set lec(input,netlist_revised_release_tag) .*/set lec(input,netlist_revised_release_tag) \"$EXIT\"/" \
        -e '/^set project(release,tag)/d' \
        "$WA/gcd/$src" > "$dst"
    if [ "$EXIT" = FP_EXIT ]; then
        sed -i '' "s/^set flow(run_name) .*/set flow(run_name)             \"${RUN}_fp\"/" "$dst"
        echo "set pv(signoff,lvs_required)   false" >> "$dst"
    fi
    echo "set project(phase)             \"$PHASE\"" >> "$dst"
    echo "set project(release,phase)     \"$PHASE\"" >> "$dst"
    # children (block library) from LIB_TAG when given; else project(lib_config_tag)
    [ -n "$LIB_TAG" ] && echo "set project(lib_config_tag)    \"$LIB_TAG\"" >> "$dst"
    # PV_MODE=flat|hier: pv(oss,pv,mode); a hier run releases to <exit>_HIER so
    # the flat release (<exit>, read by library-manager) is not overwritten
    if [ "$f" = PV ] && [ -n "$PV_MODE" ]; then
        echo "set pv(oss,pv,mode)            $PV_MODE" >> "$dst"
        [ "$PV_MODE" = hier ] && echo "set project(release,tag)       \"${EXIT}_HIER\"" >> "$dst"
    fi
    # MAX_PARALLEL=<n>: cap concurrent jobs (scenarios) in the run — memory
    [ -n "$MAX_PARALLEL" ] && echo "set flow(max_parallel_jobs)    $MAX_PARALLEL" >> "$dst"
    echo "$dst"
}

run() {
    local f=$1 uc=$2 rd="${PHASE}_run_${1}_${B}_${RUN}$([ "$EXIT" = FP_EXIT ] && echo _fp)"
    local fl; fl=$(echo "$f" | tr 'A-Z' 'a-z')$([ "$EXIT" = FP_EXIT ] && echo _fp)
    say "$B $f: start ($PHASE, input $EXIT)"
    (cd "$WA/$B" && rm -rf "$rd" && $C workspace create --config "$uc") > "$WA/$B/${fl}_signoff_create.log" 2>&1
    (cd "$WA/$B/$rd" && $C run all) > "$WA/$B/${fl}_signoff.log" 2>&1
    if ! grep -q "result=PASS" "$WA/$B/${fl}_signoff.log"; then
        say "$B $f: RUN FAILED — see $B/${fl}_signoff.log"; return
    fi
    # Verdict = the release's metrics.rpt Status (thresholds in the tool overlay)
    local rel; rel=$(awk '/^release_dir/{print $2}' "$WA/$B/$rd"/work/$f/release_data1/outputs/release.manifest)
    local st; st=$(awk -F' : ' '/^Status :/{print $2}' "$rel/metrics.rpt" 2>/dev/null)
    say "$B $f: run done, verdict ${st:-UNKNOWN} -> release ${rel#*/$PHASE/}"
    # attach to the exit entry in SmartGrid (refreshes it with every flow's release)
    if [ -n "$PUBLISH" ]; then
        (cd "$WA/$B" && flock_publish "$rd")
    fi
}

# FLOWS="STA PV LEC" (default) or any subset, e.g. FLOWS=STA
FLOWS=${FLOWS:-STA PV LEC}
if [ "$EXIT" = FP_EXIT ]; then
    run PV "$(mk PV uc_PV_magic.tcl)" &
else
    case " $FLOWS " in *" STA "*) run STA "$(mk STA uc_STA_opensta.tcl)" & ;; esac
    case " $FLOWS " in *" PV "*)  run PV  "$(mk PV  uc_PV_magic.tcl)" & ;; esac
    case " $FLOWS " in *" LEC "*) run LEC "$(mk LEC uc_LEC_yosys.tcl)" & ;; esac
fi
wait
say "$B signoff done"
