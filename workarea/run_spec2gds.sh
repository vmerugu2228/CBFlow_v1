#!/bin/bash
# =============================================================================
# run_spec2gds.sh <block> <phase> — spec-to-GDS sign-off chain of a block
#
# Runs project(signoff_chain,<phase>) (global project config) stage by stage:
# every "<step> <tag>" pair of a stage runs in parallel through cbflow
# (workspace create from workarea/<block>/uc_<step>[_<tool>]_<phase>.tcl, or a
# retrace of the existing run, then `cbflow run all`); a step passes when the
# run passes and its release <phase>/<block>/<FLOW>/<tag>/RELEASE_COMPLETE is
# newer than the step's start. The chain stops after a stage with a failure.
# project(signoff_chain,bypass) bypasses unsupported stages of a step's run.
#
#   FROM=<step>   start at the stage holding <step> (earlier stages skipped)
#   UNTIL=<step>  stop after the stage holding <step>
#   DRY=1         print the plan (steps, user configs, run dirs) only
#   PROJECT=<p>   project (default opensky)
# Log: workarea/<block>/spec2gds_<phase>.log; summary table at the end.
# =============================================================================
set -u
B=${1:?usage: run_spec2gds.sh <block> <phase>}
PHASE=${2:?usage: run_spec2gds.sh <block> <phase>}
cd "$(dirname "$0")"
WA=$PWD
ROOT=$(cd .. && pwd)
C=$ROOT/bin/cbflow
PROJECT=${PROJECT:-opensky}
LOG=$WA/$B/spec2gds_${PHASE}.log
RES=$(mktemp -d "${TMPDIR:-/tmp}/spec2gds.XXXXXX")

say() {    # a dry run prints the plan without writing the log
    if [ -n "${DRY:-}" ]; then echo "[$(date +%H:%M:%S)] $*"; else echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; fi
}
die() { echo "run_spec2gds: ERROR: $*" >&2; exit 1; }

# ── project config: chain, bypass list, release area ────────────────────────
read_cfg() {
    tclsh <<EOF
foreach f [list "$ROOT/global/config/project/$PROJECT/v1.0.0/${PROJECT}_config.tcl" \
                "$ROOT/PD/config/project/$PROJECT/v1.0.0/${PROJECT}_pd_config.tcl"] {
    if {[file exists \$f]} { if {[catch {source \$f} e]} { puts stderr "\$f: \$e"; exit 1 } }
}
switch -- {$1} {
    chain   { if {![info exists project(signoff_chain,$PHASE)]} { puts stderr "project(signoff_chain,$PHASE) is not set"; exit 1 }
              foreach st \$project(signoff_chain,$PHASE) { puts \$st } }
    bypass  { if {[info exists project(signoff_chain,bypass)]} { foreach {s n} \$project(signoff_chain,bypass) { puts "\$s [join \$n ,]" } } }
    release { if {![info exists project(release,path)]} { puts stderr "project(release,path) is not set"; exit 1 }; puts \$project(release,path) }
}
EOF
}
CHAIN=$(read_cfg chain) || die "cannot read the chain"
BYPASS=$(read_cfg bypass) || die "cannot read the bypass list"
REL=$(read_cfg release) || die "cannot read project(release,path)"
[ -d "$WA/$B" ] || die "no workarea $WA/$B"

uc_for() {    # uc_for <step> — the step's user config
    local s=$1 f
    f="$WA/$B/uc_${s}_${PHASE}.tcl"
    [ -f "$f" ] && { echo "$f"; return; }
    f=$(ls "$WA/$B"/uc_${s}_*_${PHASE}.tcl 2>/dev/null | grep -E "/uc_${s}_[A-Za-z0-9]+_${PHASE}\.tcl$")
    [ "$(echo "$f" | grep -c .)" = 1 ] || return 1
    echo "$f"
}
uc_val() {    # uc_val <uc> <key> — value of "set <key> ..." in a user config
    tclsh <<EOF
array set flow {}; array set project {}
foreach l [split [read [open "$1"]] \n] { if {[regexp {^\s*set\s+(flow|project)\(} \$l]} { catch {eval \$l} } }
puts [set {$2}]
EOF
}
run_dir_for() {   # run_dir_for <uc>
    echo "$WA/$B/${PHASE}_run_$(uc_val "$1" 'flow(type)')_${B}_$(uc_val "$1" 'flow(run_name)')"
}

step() {    # step <step> <tag> — one chain step; writes $RES/<step>
    local s=$1 tag=$2 uc rd flow t0 rc=1 msg byp
    uc=$(uc_for "$s") || { echo "FAIL|$s|-|$tag|no user config uc_${s}[_<tool>]_${PHASE}.tcl|-|0" > "$RES/$s"; return; }
    flow=$(uc_val "$uc" 'flow(type)'); rd=$(run_dir_for "$uc")
    t0=$(date +%s)
    if [ -d "$rd" ]; then
        local first
        first=$(cd "$rd" && $C run status 2>&1 \
                | sed -nE 's/^\[INFO\][[:space:]]+\[[A-Z ]+\][[:space:]]+([^[:space:]]+).*/\1/p' | head -1)
        [ -n "$first" ] || { echo "FAIL|$s|$flow|$tag|cannot read the first stage of $rd|$rd|0" > "$RES/$s"; return; }
        (cd "$rd" && $C run retrace --from "$first" > "$rd/spec2gds_retrace.log" 2>&1)
    else
        (cd "$WA/$B" && $C workspace create --config "$(basename "$uc")" > "$WA/$B/spec2gds_${s}_create.log" 2>&1)
        [ -d "$rd" ] || { echo "FAIL|$s|$flow|$tag|workspace create failed (spec2gds_${s}_create.log)|$rd|0" > "$RES/$s"; return; }
    fi
    byp=$(echo "$BYPASS" | awk -v s="$s" '$1 == s {print $2}')
    [ -n "$byp" ] && (cd "$rd" && $C run bypass --stages "$byp" > "$rd/spec2gds_bypass.log" 2>&1)
    (cd "$rd" && $C run all > "$rd/spec2gds_run.log" 2>&1)
    local mark="$REL/$PHASE/$B/$flow/$tag/RELEASE_COMPLETE"
    if ! grep -q "result=PASS" "$rd/spec2gds_run.log"; then
        msg="run FAILED: $(grep -m1 'FAILED:' "$rd/spec2gds_run.log" | sed 's/^ *//')"
    elif [ ! -f "$mark" ]; then
        msg="no release $flow/$tag"
    elif [ "$(stat -f %m "$mark" 2>/dev/null || stat -c %Y "$mark")" -lt "$t0" ]; then
        msg="release $flow/$tag not refreshed by this run"
    else
        rc=0; msg="released $flow/$tag"
    fi
    echo "$([ $rc = 0 ] && echo PASS || echo FAIL)|$s|$flow|$tag|$msg|$rd|$(( $(date +%s) - t0 ))" > "$RES/$s"
}

# ── plan ─────────────────────────────────────────────────────────────────────
mkdir -p "$(dirname "$LOG")"
say "spec-to-GDS chain — $B $PHASE (project $PROJECT, $(echo "$CHAIN" | grep -c .) stages, release $REL)"
started=$([ -z "${FROM:-}" ] && echo 1 || echo 0)
n=0; fail=0
while IFS= read -r stage; do
    [ -z "$stage" ] && continue
    n=$((n + 1))
    set -- $stage
    names=""; while [ $# -ge 2 ]; do names="$names $1"; shift 2; done
    if [ "$started" = 0 ]; then
        case " $names " in *" ${FROM} "*) started=1 ;; *) say "stage $n:$names — skipped (FROM=$FROM)"; continue ;; esac
    fi
    if [ -n "${DRY:-}" ]; then
        set -- $stage
        while [ $# -ge 2 ]; do
            uc=$(uc_for "$1") && rd=$(run_dir_for "$uc") || { uc="MISSING"; rd="-"; }
            say "stage $n: $1 -> $2   $(basename "$uc")   $(basename "$rd")"
            shift 2
        done
    else
        say "stage $n:$names — start"
        set -- $stage
        while [ $# -ge 2 ]; do step "$1" "$2" & shift 2; done
        wait
        set -- $stage
        while [ $# -ge 2 ]; do
            IFS='|' read -r st s flow tag msg rd secs < "$RES/$1"
            say "  $st  $s ($flow -> $tag) ${secs}s — $msg"
            [ "$st" = PASS ] || fail=1
            shift 2
        done
    fi
    case " $names " in *" ${UNTIL:-} "*) [ -n "${UNTIL:-}" ] && { say "UNTIL=$UNTIL reached"; break; } ;; esac
    if [ "$fail" = 1 ]; then say "stage $n failed — chain stopped"; break; fi
done <<< "$CHAIN"

# ── summary ──────────────────────────────────────────────────────────────────
if [ -z "${DRY:-}" ]; then
    say "summary:"
    for f in "$RES"/*; do
        [ -f "$f" ] || continue
        IFS='|' read -r st s flow tag msg rd secs < "$f"
        printf '  %-4s %-16s %-14s %-18s %6ss  %s\n' "$st" "$s" "$flow" "$tag" "$secs" "$(basename "$rd")" | tee -a "$LOG"
    done
fi
rm -rf "$RES"
exit $fail
