#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow ECO — eco (opensource / openroad)
# Timing ECO on a released routed database: the change file written by the
# timing-eco skill (eco(oss,mode) changes) or guided repair_timing (repair),
# then legalization and re-route. Every change is listed in
# reports/eco_changes.rpt; timing after on global-route parasitics in
# reports/eco_qor.tcl (signoff1 times the extracted result; the timing before
# is the STA run the ECO was derived from).
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "ECO"
set STAGE_NAME "eco"
set NODE_NAME [cbflow_node_name]

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_utils.tcl"

set design_name [oss_get flow design_name]
set blocks      [hier_children $design_name]

if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

# Vt flavour of a master: the first tech(vt_pattern,<vt>) glob it matches
proc eco_vt_of {master} {
    foreach _v [oss_get tech vt_variants_available] {
        if {[string match [oss_get tech vt_pattern,$_v] $master]} { return $_v }
    }
    return ""
}

proc eco_inst_names {} {
    set _n {}
    foreach _i [[ord::get_db_block] getInsts] { dict set _n [$_i getName] 1 }
    return $_n
}

# Buffer insertion through the STA network editor (OpenROAD insert_buffer
# crashes / leaves an inconsistent parasitics state on a routed database in
# this build): a new <buffer_cell> instance drives a new net carrying the
# given load pins of <net> (all its loads when none are given). Placed at
# the first load; detailed placement legalizes it.
proc eco_insert_buffer {buffer_cell net args} {
    set _blk [ord::get_db_block]
    if {[$_blk findNet $net] eq "NULL"} { error "eco_insert_buffer: no net $net" }
    set _m [[ord::get_db] findMaster $buffer_cell]
    if {$_m eq "NULL"} { error "eco_insert_buffer: no lib cell $buffer_cell" }
    set _in ""; set _out ""
    foreach _mt [$_m getMTerms] {
        if {[$_mt getSigType] ni {SIGNAL CLOCK}} continue
        if {[$_mt getIoType] eq "INPUT"} { set _in [$_mt getName] } elseif {[$_mt getIoType] eq "OUTPUT"} { set _out [$_mt getName] }
    }
    if {$_in eq "" || $_out eq ""} { error "eco_insert_buffer: $buffer_cell is not a buffer (one input, one output)" }
    set _loads $args
    if {![llength $_loads]} {
        foreach _p [get_pins -quiet -of_objects [get_nets $net]] {
            if {[get_property $_p direction] eq "input"} { lappend _loads [get_full_name $_p] }
        }
    }
    if {![llength $_loads]} { error "eco_insert_buffer: net $net has no load pins" }
    set _k 1
    while {[$_blk findInst eco_buf_$_k] ne "NULL" || [$_blk findNet eco_net_$_k] ne "NULL"} { incr _k }
    make_net eco_net_$_k
    make_instance eco_buf_$_k $buffer_cell
    foreach _l $_loads {
        disconnect_pin $net $_l
        connect_pin eco_net_$_k $_l
    }
    connect_pin $net eco_buf_$_k/$_in
    connect_pin eco_net_$_k eco_buf_$_k/$_out
    set _li [$_blk findInst [file dirname [lindex $_loads 0]]]
    if {$_li ne "NULL"} {
        set _b [$_blk findInst eco_buf_$_k]
        $_b setLocation {*}[$_li getLocation]; $_b setPlacementStatus PLACED
    }
    return eco_buf_$_k
}

# Change-file commands: one per line, '#' comments; only
# eco(oss,changes,allowed) commands; caps eco(oss,limit,*); replace_cell
# targets must exist, be a different master and not be dont_use.
proc eco_parse_changes {file} {
    set _allowed [oss_get eco oss,changes,allowed]
    set _dont [oss_pnr_dont_use]
    set _cmds {}
    set _cnt [dict create buffers 0 resizes 0 vt_swaps 0 removals 0]
    set _fh [open $file]; set _lines [split [read $_fh] \n]; close $_fh
    set _ln 0
    foreach _l $_lines {
        incr _ln
        set _l [string trim $_l]
        if {$_l eq "" || [string index $_l 0] eq "#"} continue
        if {![info complete $_l]} { error "change file line $_ln: incomplete command: $_l" }
        set _c [lindex $_l 0]
        if {$_c ni $_allowed} { error "change file line $_ln: '$_c' is not an allowed ECO command (eco(oss,changes,allowed): $_allowed)" }
        switch $_c {
            replace_cell {
                if {[llength $_l] != 3} { error "change file line $_ln: replace_cell <instance> <lib_cell>" }
                lassign $_l - _inst _new
                set _i [[ord::get_db_block] findInst $_inst]
                if {$_i eq "NULL"} { error "change file line $_ln: no instance $_inst" }
                set _old [[$_i getMaster] getName]
                if {$_old eq $_new} { error "change file line $_ln: $_inst is already $_new" }
                if {[[ord::get_db] findMaster $_new] eq "NULL"} { error "change file line $_ln: no lib cell $_new" }
                foreach _p $_dont { if {[string match $_p $_new]} { error "change file line $_ln: $_new is dont_use ($_p)" } }
                if {[eco_vt_of $_old] ne [eco_vt_of $_new]} { dict incr _cnt vt_swaps } else { dict incr _cnt resizes }
            }
            eco_insert_buffer {
                if {[llength $_l] < 3} { error "change file line $_ln: eco_insert_buffer <buffer_cell> <net> \[load pins...\]" }
                dict incr _cnt buffers
            }
            remove_buffers { dict incr _cnt removals [expr {[llength $_l] - 1}] }
        }
        lappend _cmds [list $_ln $_l]
    }
    foreach {_k _lim} {buffers buffers resizes resizes vt_swaps vt_swaps removals removals} {
        set _max [oss_get eco oss,limit,$_lim]
        if {[dict get $_cnt $_k] > $_max} {
            error "change file: [dict get $_cnt $_k] $_k exceeds eco(oss,limit,$_lim) $_max"
        }
    }
    return [list $_cmds $_cnt]
}

# Load: the released routed database, timing views, SDC, routing layers.
# No parasitics estimate before the edits (incremental parasitics updates
# fail on a routed database — EST-0104); the pre-ECO timing is the STA run's.
flow_proc load_design {
    global design_name blocks
    set_thread_count [oss_get eco oss,threads]
    oss_read_corners $::NODE_NAME $blocks
    set _odb "$::run_dir/work/ECO/odb1/odb/${design_name}.odb"
    if {![file exists $_odb]} { error "released database not staged: $_odb (eco(input,release_tag))" }
    handle_info "ECO source database: $_odb"
    read_db $_odb
    read_sdc [oss_sdc_file]
    set_propagated_clock [all_clocks]
    oss_set_wire_rc
    lassign [oss_signal_layers $design_name $blocks] _min _max
    set _layers [oss_ms metal_layers]
    set _cmin [oss_ms clock_routing_layer_min]
    set _cmax [oss_ms clock_routing_layer_max]
    if {[lsearch -exact $_layers $_cmax] > [lsearch -exact $_layers $_max]} { set _cmax $_max }
    if {[lsearch -exact $_layers $_cmin] > [lsearch -exact $_layers $_cmax]} { set _cmin $_cmax }
    set_routing_layers -signal ${_min}-${_max} -clock ${_cmin}-${_cmax}
}

# Apply: fillers out (room for new / larger cells), the change file or
# guided repair, every change listed in eco_changes.rpt
flow_proc apply_changes {
    global design_name
    remove_fillers
    set _before [eco_inst_names]
    set _masters {}
    foreach _i [[ord::get_db_block] getInsts] { dict set _masters [$_i getName] [[$_i getMaster] getName] }
    set _mode [oss_get eco oss,mode]
    set _rpt {}
    lappend _rpt "# ECO changes — $design_name ($_mode mode)"
    switch $_mode {
        changes {
            set _cf [expr {[info exists ::eco(input,change_file)] ? $::eco(input,change_file) : ""}]
            if {$_cf eq "" || ![file exists $_cf]} { error "eco(input,change_file) not set or missing: '$_cf'" }
            file copy -force $_cf "$::REPORTS_DIR/eco_change_file.tcl"
            lassign [eco_parse_changes $_cf] _cmds _cnt
            handle_info "change file: [llength $_cmds] command(s) — $_cnt"
            lappend _rpt "# change file: $_cf"
            foreach _e $_cmds {
                lassign $_e _ln _cmd
                if {[catch {uplevel #0 $_cmd} _err]} { error "change file line $_ln failed: $_cmd — $_err" }
                lappend _rpt "applied : $_cmd"
            }
        }
        repair {
            set _args {}
            if {[is_true [oss_get eco oss,repair,setup]]} { lappend _args -setup -setup_margin [oss_get eco oss,repair,setup_margin] }
            if {[is_true [oss_get eco oss,repair,hold]]}  { lappend _args -hold -hold_margin [oss_get eco oss,repair,hold_margin] }
            if {![llength $_args]} { error "repair mode: eco(oss,repair,setup) and eco(oss,repair,hold) are both false" }
            lappend _args -max_buffer_percent [oss_get eco oss,repair,max_buffer_percent] \
                          -max_utilization [oss_get eco oss,repair,max_utilization]
            set _seq [oss_get eco oss,repair,sequence]
            if {$_seq ne ""} { lappend _args -sequence $_seq }
            foreach _s [oss_get eco oss,repair,skip] { lappend _args -skip_$_s }
            handle_info "repair_timing $_args"
            lappend _rpt "# repair_timing $_args"
            estimate_parasitics -placement
            repair_timing {*}$_args
        }
        default { error "eco(oss,mode) must be changes or repair, got '$_mode'" }
    }
    # Change list: resized / swapped instances, added and removed instances
    set _after [eco_inst_names]
    set _n [dict create resized 0 added 0 removed 0]
    foreach _i [[ord::get_db_block] getInsts] {
        set _nm [$_i getName]; set _m [[$_i getMaster] getName]
        if {![dict exists $_before $_nm]} {
            lappend _rpt "added   : $_nm $_m"; dict incr _n added
            # unplaced new instance: start at its first connected neighbour
            if {[$_i getPlacementStatus] in {NONE UNPLACED}} {
                foreach _it [$_i getITerms] {
                    set _net [$_it getNet]; if {$_net eq "NULL"} continue
                    foreach _o [$_net getITerms] {
                        set _oi [$_o getInst]
                        if {$_oi ne $_i && [$_oi getPlacementStatus] ni {NONE UNPLACED}} {
                            $_i setLocation {*}[$_oi getLocation]; $_i setPlacementStatus PLACED; break
                        }
                    }
                    if {[$_i getPlacementStatus] eq "PLACED"} break
                }
            }
        } elseif {[dict get $_masters $_nm] ne $_m} {
            lappend _rpt "resized : $_nm [dict get $_masters $_nm] -> $_m"; dict incr _n resized
        }
    }
    dict for {_nm -} $_before { if {![dict exists $_after $_nm]} { lappend _rpt "removed : $_nm [dict get $_masters $_nm]"; dict incr _n removed } }
    lappend _rpt "Summary : resized [dict get $_n resized], added [dict get $_n added], removed [dict get $_n removed]"
    set _fh [open "$::REPORTS_DIR/eco_changes.rpt" w]; puts $_fh [join $_rpt \n]; close $_fh
    handle_info "ECO: resized [dict get $_n resized], added [dict get $_n added], removed [dict get $_n removed]"
    if {[dict get $_n resized] + [dict get $_n added] + [dict get $_n removed] == 0} {
        handle_warning "the ECO changed nothing"
    }
}

# Legalize the changed cells (bounded displacement), then re-route: the
# signal / clock wiring of the source database is removed first — a database
# saved after OpenRCX extraction carries re-encoded wires the detailed router
# rejects (DRT-1010 non-orthogonal wire) — then global + detailed route.
# Power / ground (special) wiring is kept.
flow_proc legalize_route {
    detailed_placement -max_displacement [oss_get eco oss,place,max_displacement]
    oss_report "$::REPORTS_DIR/eco_check_placement.rpt" check_placement -verbose
    set _n 0
    foreach _net [[ord::get_db_block] getNets] {
        if {[$_net isSpecial] || [$_net getSigType] in {POWER GROUND}} continue
        set _w [$_net getWire]
        if {$_w ne "NULL"} { odb::dbWire_destroy $_w; incr _n }
    }
    handle_info "re-route: removed the wiring of $_n signal / clock nets"
    oss_report "$::REPORTS_DIR/eco_grt.rpt" global_route -allow_congestion
    estimate_parasitics -global_routing
    detailed_route -output_drc "$::REPORTS_DIR/eco_route_drc.rpt" -verbose 1
}

# Reports: post-ECO QoR / timing on global-route parasitics (signoff1 times
# the extracted layout)
flow_proc report {
    oss_write_qor eco
}

flow_proc save_design {
    global_connect
    write_db [oss_stage_out eco.odb]
}

# DRC gate — last, so the database and reports exist when it fails
flow_proc check_drc {
    set _n 0
    if {[file exists "$::REPORTS_DIR/eco_route_drc.rpt"]} {
        set _fh [open "$::REPORTS_DIR/eco_route_drc.rpt"]
        foreach _l [split [read $_fh] "\n"] { if {[string match "violation type:*" $_l]} { incr _n } }
        close $_fh
    }
    handle_info "Post-ECO detailed-route DRC violations: $_n"
    set _max [oss_get eco oss,route,max_drc]
    if {$_n > $_max} {
        set _msg "ECO re-route left $_n DRC violations (max $_max) — see $::REPORTS_DIR/eco_route_drc.rpt"
        if {[is_true [oss_get eco oss,fail_on_violations]]} { error $_msg }
        handle_warning "$_msg — reported, flow continues"
    }
}

flow_exec_all
exit
