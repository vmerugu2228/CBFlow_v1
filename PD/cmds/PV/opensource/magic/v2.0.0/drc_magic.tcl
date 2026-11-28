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

# KLayout: run the deck -> reports/drc_klayout.lyrdb
proc pv_drc_klayout {gds} {
    global design_name
    set _rdb "$::REPORTS_DIR/drc_klayout.lyrdb"
    set _rd [list -rd input=$gds -rd top_cell=$design_name -rd report=$_rdb \
                  -rd thr=[oss_get pv oss,drc,klayout_threads]]
    foreach {_k _v} [oss_get pv oss,drc,klayout_options] { lappend _rd -rd $_k=$_v }
    oss_exec_tool klayout [oss_get tech klayout,drc] "$::REPORTS_DIR/drc_klayout.log" $_rd
}

# KLayout: report database (lyrdb) -> error count + per-rule counts (why)
proc pv_drc_klayout_count {why} {
    set _rdb "$::REPORTS_DIR/drc_klayout.lyrdb"
    if {![file exists $_rdb]} { error "KLayout DRC wrote no report database (see $::REPORTS_DIR/drc_klayout.log)" }
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

# Magic: drc style check; per-rule counts written by Magic itself (why)
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
    oss_exec_tool magic $_script "$::REPORTS_DIR/drc_magic.log"
}

# Magic: total error count from the log
proc pv_drc_magic_count {} {
    set _log "$::REPORTS_DIR/drc_magic.log"
    set _fh [open $_log]; set _txt [read $_fh]; close $_fh
    if {![regexp {Total DRC errors found: (\d+)} $_txt -> _n]} { error "Magic DRC produced no result (see $_log)" }
    return $_n
}

# Load: the staged GDS, the DRC engine and its deck
flow_proc load_design {
    global design_name
    set ::drc_gds "$::GDS_DIR/${design_name}.gds"
    if {![file exists $::drc_gds]} { error "GDS not staged: $::drc_gds (pv(input,gds))" }
    # pv(oss,pv,mode) hier: DRC the top-level layout — child block cells emptied
    set _kids [hier_children $design_name]
    if {[pv_mode] eq "hier" && [llength $_kids] > 0} {
        set _out "$::WORK_DIR/${design_name}_hier.gds"
        set _py "$::WORK_DIR/hier_gds.py"
        set _fh [open $_py w]
        puts $_fh "import pya"
        puts $_fh "ly = pya.Layout(); ly.read('$::drc_gds')"
        foreach _b $_kids {
            puts $_fh "c = ly.cell('$_b')"
            puts $_fh "if c is None: raise SystemExit('child block cell $_b not in $::drc_gds')"
            puts $_fh "c.prune_subcells(); c.clear_shapes()"
        }
        puts $_fh "ly.write('$_out')"
        close $_fh
        oss_exec_tool klayout $_py "$::REPORTS_DIR/hier_gds.log"
        set ::drc_gds $_out
        handle_info "hier DRC: child blocks emptied ([join $_kids {, }]) -> $_out"
    }
    set ::drc_eng [oss_get pv oss,drc,engine]
    set ::drc_why "$::REPORTS_DIR/drc_${::drc_eng}_why.rpt"
}

# Run the DRC engine on the GDS
flow_proc drc {
    switch -- $::drc_eng {
        klayout { pv_drc_klayout $::drc_gds;           set ::drc_deck [oss_get tech klayout,drc] }
        magic   { pv_drc_magic $::drc_gds $::drc_why;  set ::drc_deck [oss_get pv oss,drc,style] }
        default { error "pv(oss,drc,engine) '$::drc_eng' — expected klayout or magic" }
    }
}

# Reports: error count + per-rule counts (reports/drc_<engine>_why.rpt)
flow_proc report {
    if {![is_true $::flow(test_mode)]} {
        switch -- $::drc_eng {
            klayout { set ::drc_errors [pv_drc_klayout_count $::drc_why] }
            magic   { set ::drc_errors [pv_drc_magic_count] }
        }
    }
}

# Save the DRC result -> outputs/drc.rpt
flow_proc save_design {
    global design_name
    if {![is_true $::flow(test_mode)]} {
        file mkdir [file dirname [oss_stage_out drc.rpt]]
        set _fh [open [oss_stage_out drc.rpt] w]
        puts $_fh "design $design_name\ngds $::drc_gds\nengine $::drc_eng\ndeck $::drc_deck\ndrc_errors $::drc_errors"
        close $_fh
    }
}

# DRC gate (pv(oss,drc,max_errors)) — last, so drc.rpt exists when it fails
flow_proc check_drc {
    if {![is_true $::flow(test_mode)]} {
        set _n $::drc_errors
        handle_info "DRC ($::drc_eng): $_n error(s)"
        if {$_n > [oss_get pv oss,drc,max_errors]} {
            set _msg "DRC: $_n error(s) (max [oss_get pv oss,drc,max_errors]) — see $::drc_why"
            if {[is_true [oss_get pv oss,fail_on_violations]]} { error $_msg }
            handle_warning "$_msg — reported, flow continues (pv(oss,fail_on_violations) false)"
        }
    }
}

flow_exec_all
exit
