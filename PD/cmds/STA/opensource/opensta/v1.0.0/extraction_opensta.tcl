#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow STA — extraction (opensource / openroad)
# OpenRCX parasitic extraction of the staged (routed) DEF for one RC corner
# (::RC_CORNER, set by the extraction subnode handler) -> ::SPEF_OUT.
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "STA"
set STAGE_NAME "extraction"
# Dynamic subnodes (per RC corner / per scenario) pass their node in the
# context script (::OSS_NODE); otherwise the launch wrapper's node.
set NODE_NAME [expr {[info exists ::OSS_NODE] ? $::OSS_NODE : ([info exists ::env(CBFLOW_NODE_NAME)] && $::env(CBFLOW_NODE_NAME) ne "" ? $::env(CBFLOW_NODE_NAME) : "extraction1")}]

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_utils.tcl"

set design_name [oss_get flow design_name]
set blocks      [hier_children $design_name]

if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

flow_proc extract {
    global design_name blocks
    set_thread_count [oss_get sta oss,threads]
    oss_read_lefs $blocks
    set _def [lindex [glob -nocomplain "$::DEF_DIR/${design_name}.def" "$::DEF_DIR/*.def"] 0]
    if {$_def eq ""} { error "no DEF staged in $::DEF_DIR (sta(input,def_file) / release_tag)" }
    read_def $_def
    define_process_corner -ext_model_index 0 X
    extract_parasitics -ext_model_file [oss_get tech rcx,$::RC_CORNER,openrcx]
    file mkdir [file dirname $::SPEF_OUT]
    write_spef $::SPEF_OUT
    handle_info "SPEF $::RC_CORNER -> $::SPEF_OUT"
}

flow_exec_all
exit
