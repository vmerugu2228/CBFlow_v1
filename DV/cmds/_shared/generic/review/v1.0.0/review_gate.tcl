#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow DV — Generic Review-Gate Command File
# ═══════════════════════════════════════════════════════════════════════════════
#
# Shared across every DV review flow (SPEC_RAMP, PLANNING, TB_SETUP, M1-M4_EXEC,
# ECO_EXEC, DV_SIGNOFF) and every review stage within them. The pattern:
#
#   1. (optional) look up <flow>(review,<stage>,artifact) in user_config for a
#      path to the review doc / scoreboard log / regression report
#   2. verify the artifact exists under inputs/ or work/<stage>/outputs/
#   3. stamp outputs/review_signoff.txt with timestamp + reviewer identity
#   4. flow_exec_all runs setup → run → validate → finish subnodes
#
# No EDA tool invocation. These stages are human-driven milestone gates.
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

# FLOW_TYPE / STAGE_NAME / NODE_NAME are set by the subnode handler before
# it dispatches here (via setup_dirs). If run standalone (debug), fall back
# to env vars populated by the engine.
if {![info exists ::FLOW_TYPE]} {
    set ::FLOW_TYPE [expr {[info exists ::env(CBFLOW_FLOW_TYPE)] ? $::env(CBFLOW_FLOW_TYPE) : ""}]
}
if {![info exists ::STAGE_NAME]} {
    set ::STAGE_NAME [expr {[info exists ::env(CBFLOW_STAGE_NAME)] ? $::env(CBFLOW_STAGE_NAME) : ""}]
}
if {![info exists ::NODE_NAME]} {
    set ::NODE_NAME [expr {[info exists ::env(CBFLOW_NODE_NAME)] ? $::env(CBFLOW_NODE_NAME) : ""}]
}

source "$run_dir/work/$::FLOW_TYPE/$::NODE_NAME/run/config.tcl"
source "$run_dir/work/$::FLOW_TYPE/$::NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $::FLOW_TYPE $::NODE_NAME

# ── Validate attached artifact (if declared) ────────────────────────────────
flow_proc validate_artifact {
    global ::FLOW_TYPE ::STAGE_NAME
    set flow_lower [string tolower $::FLOW_TYPE]
    set art_key "review,$::STAGE_NAME,artifact"
    # Attempt both the typed array lookup and a direct var read — different
    # flows may expose the artifact through their flow array OR via a plain
    # <flow>_artifact(…) variable set in user_config.tcl.
    set art_path ""
    if {[info exists ::${flow_lower}($art_key)]} {
        set art_path [set ::${flow_lower}($art_key)]
    }
    if {$art_path eq ""} {
        handle_info "No artifact declared for $::STAGE_NAME ($flow_lower($art_key) unset) — review is advisory only."
        return
    }
    # Artifact paths resolved relative to run_dir if not absolute.
    if {![string match "/*" $art_path]} {
        set art_path "$::env(CBFLOW_RUN_DIR)/$art_path"
    }
    if {![file exists $art_path]} {
        handle_warning "Declared review artifact missing: $art_path"
        handle_warning "  Set $flow_lower($art_key) in user_config.tcl to the real review doc."
        return
    }
    set _sz [file size $art_path]
    handle_info "Artifact validated: $art_path ([expr {$_sz}] bytes)"
}

# ── Stamp review signoff ────────────────────────────────────────────────────
flow_proc stamp_signoff {
    global ::FLOW_TYPE ::STAGE_NAME
    set signoff "$::OUTPUTS_DIR/review_signoff.txt"
    file mkdir [file dirname $signoff]
    set fh [open $signoff "w"]
    set ts [clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}]
    set reviewer [expr {[info exists ::env(USER)] ? $::env(USER) : "unknown"}]
    puts $fh "stage:     $::STAGE_NAME"
    puts $fh "flow:      $::FLOW_TYPE"
    puts $fh "reviewer:  $reviewer"
    puts $fh "timestamp: $ts"
    puts $fh "status:    REVIEWED"
    close $fh
    handle_info "Review signoff stamped: $signoff"
}

flow_exec_all
