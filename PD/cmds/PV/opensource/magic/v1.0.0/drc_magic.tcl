#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow PV — drc (opensource / magic)
# Full-chip DRC with Magic (sky130 drc(full) deck) on the staged GDS.
# Fails when the error count exceeds pv(oss,drc,max_errors).
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "PV"
set STAGE_NAME "drc"
set NODE_NAME [cbflow_node_name]

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_utils.tcl"

set design_name [oss_get flow design_name]

if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

flow_proc magic_drc {
    global design_name pv
    set _gds "$::GDS_DIR/${design_name}.gds"
    if {![file exists $_gds]} { error "GDS not staged: $_gds (pv(input,gds))" }
    set _script "$::WORK_DIR/drc_magic.tcl"
    set _fh [open $_script w]
    puts $_fh "gds read $_gds"
    puts $_fh "load $design_name"
    puts $_fh "select top cell"
    puts $_fh "drc euclidean on"
    puts $_fh "drc style [oss_get pv oss,drc,style]"
    puts $_fh "drc check"
    puts $_fh "drc catchup"
    puts $_fh "drc count total"
    puts $_fh "set _fh \[open $::REPORTS_DIR/drc_magic_why.rpt w\]"
    puts $_fh "foreach {_why _boxes} \[drc listall why\] { puts \$_fh \"\[llength \$_boxes\] \$_why\" }"
    puts $_fh "close \$_fh"
    puts $_fh "quit -noprompt"
    close $_fh
    set _log "$::REPORTS_DIR/drc_magic.log"
    oss_exec_tool magic $_script $_log
    if {![is_true $::flow(test_mode)]} {
        set _fh [open $_log]; set _txt [read $_fh]; close $_fh
        if {![regexp {Total DRC errors found: (\d+)} $_txt -> _n]} { error "Magic DRC produced no result (see $_log)" }
        file mkdir [file dirname [oss_stage_out drc.rpt]]
        set _fh [open [oss_stage_out drc.rpt] w]
        puts $_fh "design $design_name\ngds $_gds\ndeck [oss_get pv oss,drc,style]\ndrc_errors $_n"
        close $_fh
        handle_info "Magic DRC: $_n error(s)"
        if {$_n > [oss_get pv oss,drc,max_errors]} {
            set _msg "DRC: $_n error(s) (max [oss_get pv oss,drc,max_errors]) — see $::REPORTS_DIR/drc_magic_why.rpt"
            if {[is_true [oss_get pv oss,fail_on_violations]]} { error $_msg }
            handle_warning "$_msg — reported, flow continues (pv(oss,fail_on_violations) false)"
        }
    }
}

flow_exec_all
exit
