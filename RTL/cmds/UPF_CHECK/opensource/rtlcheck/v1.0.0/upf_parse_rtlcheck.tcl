#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow UPF_CHECK — upf_parse (opensource / container tclsh)
# UPF parse: every command complete (Tcl syntax), commands counted; the UPF
# copied as upf.upf for the check.
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "UPF_CHECK"
set STAGE_NAME "upf_parse"
set NODE_NAME [cbflow_node_name]

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_utils.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_flow_utils.tcl"

set design_name [oss_get flow design_name]
source "$::env(CBFLOW_RTL_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/oss_rtl_utils.tcl"

if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

flow_proc parse {
    set _upf [oss_input upf]
    set _fh [open $_upf]; set _t [read $_fh]; close $_fh
    set _n 0; set _bad {}; set _cmd ""; set _ln 0
    foreach _l [split $_t \n] {
        incr _ln
        append _cmd $_l "\n"
        if {![info complete $_cmd]} continue
        if {[string trim $_cmd] ne "" && ![string match "#*" [string trim $_cmd]]} { incr _n }
        set _cmd ""
    }
    if {[string trim $_cmd] ne ""} { lappend _bad "incomplete command at end of file" }
    file copy -force $_upf [oss_stage_out upf.upf]
    oss_write_file "$::REPORTS_DIR/upf_parse.rpt" "UPF parse — [file tail $_upf]\n  Commands : $_n\n  Errors   : [llength $_bad]\n[join [lmap b $_bad {set b "  ERROR: $b"}] \n]\n"
    oss_write_file [oss_stage_out upf_parse.status] "[expr {[llength $_bad] ? "FAIL" : "PASS"}]\n"
    if {[llength $_bad]} { error "UPF parse failed: [join $_bad {; }]" }
    handle_info "UPF: $_n commands"
}

oss_exec_all
exit
