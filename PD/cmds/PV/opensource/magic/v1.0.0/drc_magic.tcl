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

# DRC engine: pv(oss,drc,engine) — klayout (sky130 manufacturing deck
# tech(klayout,drc), deep/hierarchical: scales to large flat layouts) or
# magic (drc style pv(oss,drc,style)). Both write outputs/drc.rpt
# ("drc_errors N") and reports/drc_<engine>_why.rpt (count per rule).
flow_proc drc {
    global design_name
    set _gds "$::GDS_DIR/${design_name}.gds"
    if {![file exists $_gds]} { error "GDS not staged: $_gds (pv(input,gds))" }
    set _eng [oss_get pv oss,drc,engine]
    set _why "$::REPORTS_DIR/drc_${_eng}_why.rpt"
    switch -- $_eng {
        klayout { set _n [pv_drc_klayout $_gds $_why]; set _deck [oss_get tech klayout,drc] }
        magic   { set _n [pv_drc_magic $_gds $_why];   set _deck [oss_get pv oss,drc,style] }
        default { error "pv(oss,drc,engine) '$_eng' — expected klayout or magic" }
    }
    if {[is_true $::flow(test_mode)]} return
    file mkdir [file dirname [oss_stage_out drc.rpt]]
    set _fh [open [oss_stage_out drc.rpt] w]
    puts $_fh "design $design_name\ngds $_gds\nengine $_eng\ndeck $_deck\ndrc_errors $_n"
    close $_fh
    handle_info "DRC ($_eng): $_n error(s)"
    if {$_n > [oss_get pv oss,drc,max_errors]} {
        set _msg "DRC: $_n error(s) (max [oss_get pv oss,drc,max_errors]) — see $_why"
        if {[is_true [oss_get pv oss,fail_on_violations]]} { error $_msg }
        handle_warning "$_msg — reported, flow continues (pv(oss,fail_on_violations) false)"
    }
}

# KLayout: report database (lyrdb) -> error count + per-rule counts
proc pv_drc_klayout {gds why} {
    global design_name
    set _rdb "$::REPORTS_DIR/drc_klayout.lyrdb"
    set _rd [list -rd input=$gds -rd top_cell=$design_name -rd report=$_rdb \
                  -rd thr=[oss_get pv oss,drc,klayout_threads]]
    foreach {_k _v} [oss_get pv oss,drc,klayout_options] { lappend _rd -rd $_k=$_v }
    set _log "$::REPORTS_DIR/drc_klayout.log"
    oss_exec_tool klayout [oss_get tech klayout,drc] $_log $_rd
    if {[is_true $::flow(test_mode)]} { return 0 }
    if {![file exists $_rdb]} { error "KLayout DRC wrote no report database (see $_log)" }
    set _fh [open $_rdb]; set _x [read $_fh]; close $_fh
    set _n 0
    array set _cnt {}
    # one <item> per violation, each naming its rule in <category>
    if {![regexp {<items>(.*)</items>} $_x -> _items]} { set _items "" }
    foreach {_ _cat} [regexp -all -inline {<category>'?([^<']+)'?</category>} $_items] {
        incr _n; incr _cnt($_cat)
    }
    set _fh [open $why w]
    foreach _c [lsort [array names _cnt]] { puts $_fh "$_cnt($_c) $_c" }
    close $_fh
    return $_n
}

# Magic: drc style check -> total + per-rule counts
proc pv_drc_magic {gds why} {
    global design_name
    set _script "$::WORK_DIR/drc_magic.tcl"
    set _fh [open $_script w]
    puts $_fh "gds read $gds"
    puts $_fh "load $design_name"
    puts $_fh "select top cell"
    puts $_fh "drc euclidean on"
    puts $_fh "drc style [oss_get pv oss,drc,style]"
    puts $_fh "drc check"
    puts $_fh "drc catchup"
    puts $_fh "drc count total"
    puts $_fh "set _fh \[open $why w\]"
    puts $_fh "foreach {_why _boxes} \[drc listall why\] { puts \$_fh \"\[llength \$_boxes\] \$_why\" }"
    puts $_fh "close \$_fh"
    puts $_fh "quit -noprompt"
    close $_fh
    set _log "$::REPORTS_DIR/drc_magic.log"
    oss_exec_tool magic $_script $_log
    if {[is_true $::flow(test_mode)]} { return 0 }
    set _fh [open $_log]; set _txt [read $_fh]; close $_fh
    if {![regexp {Total DRC errors found: (\d+)} $_txt -> _n]} { error "Magic DRC produced no result (see $_log)" }
    return $_n
}

flow_exec_all
exit
