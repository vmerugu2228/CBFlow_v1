#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow FP — probe (opensource / openroad)
# Early congestion / track estimate of the floorplan (fp(oss,probe,enable)):
# a quick global placement + global route on the powerplan database — nothing
# is saved; the floorplan release is unaffected. reports/probe.rpt: per-layer
# routing resource / demand / usage / overflow, total overflow, wirelength,
# placement overflow. Off the export chain (deps powerplan1); used by the
# floorplan skill to compare candidate sizes.
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "FP"
set STAGE_NAME "probe"
set NODE_NAME [cbflow_node_name]

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_utils.tcl"

set design_name [oss_get flow design_name]
set blocks      [hier_children $design_name]
set ::probe_on  [is_true [oss_get fp oss,probe,enable]]

if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

flow_proc load_design {
    global blocks
    if {!$::probe_on} return
    set_thread_count [oss_get fp oss,threads]
    oss_read_corners [oss_chain_node init_design] $blocks
    read_db [oss_prev_odb [oss_chain_node powerplan]]
    read_sdc [oss_sdc_file]
    oss_set_wire_rc
}

# Quick placement + global route (routing layers as PNR uses them)
flow_proc probe {
    global design_name blocks
    if {!$::probe_on} return
    set ::probe_t0 [clock seconds]
    oss_report "$::REPORTS_DIR/probe_gpl.rpt" global_placement -density [oss_get fp oss,probe,density] -skip_io
    lassign [oss_signal_layers $design_name $blocks] _min _max
    set_routing_layers -signal ${_min}-${_max}
    oss_report "$::REPORTS_DIR/probe_grt.rpt" global_route -allow_congestion -verbose \
        -congestion_report_file "$::REPORTS_DIR/probe_congestion.rpt"
}

# probe.rpt: the GRT usage table per layer + totals, placement overflow
flow_proc report {
    global design_name
    set L [list "# FP probe — $design_name (quick global placement + global route; nothing saved)"]
    if {!$::probe_on} {
        lappend L "Probe : disabled (fp(oss,probe,enable) false)"
    } else {
        set _fh [open "$::REPORTS_DIR/probe_grt.rpt"]; set _g [read $_fh]; close $_fh
        set _fh [open "$::REPORTS_DIR/probe_gpl.rpt"]; set _p [read $_fh]; close $_fh
        set _dbu [[ord::get_db_tech] getDbUnitsPerMicron]
        set _core [[ord::get_db_block] getCoreArea]
        lappend L "Probe : enabled"
        lappend L [format "Core um : %.2f x %.2f" [expr {[$_core dx] / double($_dbu)}] [expr {[$_core dy] / double($_dbu)}]]
        lappend L "Placement density target : [oss_get fp oss,probe,density]"
        # final global-placement overflow (last "overflow:" value printed)
        set _ov [regexp -all -inline {overflow:\s*([0-9.]+)} $_p]
        if {[llength $_ov]} { lappend L "Placement overflow : [lindex $_ov end]" }
        # GRT table rows: Layer  Resource  Demand  Usage(%)  Max H / Max V / Total Overflow
        set _tot ""
        foreach _ln [split $_g \n] {
            if {[regexp {^\s*(\S+)\s+(\d+)\s+(\d+)\s+([0-9.]+)%\s+(\d+)\s*/\s*(\d+)\s*/\s*(\d+)} $_ln -> _l _res _dem _use _oh _ov2 _ot]} {
                if {$_l eq "Total"} { set _tot [list $_res $_dem $_use $_ot]; continue }
                lappend L [format "Layer %-6s : resource %8d demand %8d usage %6.2f %% overflow %d (H %d / V %d)" $_l $_res $_dem $_use $_ot $_oh $_ov2]
            }
        }
        if {$_tot ne ""} {
            lassign $_tot _res _dem _use _ot
            lappend L [format "Total routing usage : %.2f %%" $_use]
            lappend L "Total overflow : $_ot"
        } else {
            lappend L "# GRT usage table not found in probe_grt.rpt"
        }
        if {[regexp {Total wirelength:\s*([0-9.]+)\s*um} $_g -> _wl] || [regexp {[Ww]irelength[^0-9]*([0-9.]+)\s*um} $_g -> _wl]} {
            lappend L "Estimated wirelength um : $_wl"
        }
        lappend L "Probe runtime s : [expr {[clock seconds] - $::probe_t0}]"
    }
    set _fh [open "$::REPORTS_DIR/probe.rpt" w]; puts $_fh [join $L \n]; close $_fh
    file copy -force "$::REPORTS_DIR/probe.rpt" [oss_stage_out probe.rpt]
    handle_info [join [lrange $L 1 end] "; "]
}

flow_exec_all
exit
