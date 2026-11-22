#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow STA — release_data (opensource / tclsh)
# Publish the STA reports: <release,path>/<phase>/<design>/<tag>/reports/sta/.
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "STA"
set STAGE_NAME "release_data"
# Dynamic subnodes (per RC corner / per scenario) pass their node in the
# context script (::OSS_NODE); otherwise the launch wrapper's node.
set NODE_NAME [expr {[info exists ::OSS_NODE] ? $::OSS_NODE : [cbflow_node_name]}]

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_utils.tcl"

set design_name [oss_get flow design_name]
set blocks      [hier_children $design_name]

if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/release_utils.tcl"

flow_proc publish {
    global design_name
    set _dir [::CBFlow::Release::init $::FLOW_TYPE $design_name $::DIRS(run) [oss_get project release,phase]]
    set _m "[cbflow_node_dir [oss_chain_node merge_reports]]/outputs"
    ::CBFlow::Release::copy_file "$_m/sta_summary.rpt" reports/sta sta_summary.rpt
    set _tnode [oss_chain_node timing]
    foreach _sd [glob -nocomplain -type d "[cbflow_node_dir $_tnode]/*/reports"] {
        set _scen [file tail [file dirname $_sd]]
        ::CBFlow::Release::copy_glob "$_sd/*.rpt" reports/sta/$_scen
    }
    # Signoff metrics + verdict for SmartGrid (attached to the exit it checked)
    set _L [list "# category: timing"]
    set _fh [open "$_m/sta_summary.rpt"]; set _t [read $_fh]; close $_fh
    foreach _ln [split $_t \n] {
        if {[llength $_ln] == 5 && [string is double -strict [lindex $_ln 1]]} {
            lassign $_ln _sc _sw _st _hw _ht
            lappend _L "$_sc setup WNS : $_sw" "$_sc setup TNS : $_st" "$_sc hold WNS : $_hw" "$_sc hold TNS : $_ht"
        }
    }
    if {[is_true [oss_get sta oss,report_power]]} {
        ::CBFlow::Release::copy_file "$_m/sta_power.rpt" reports/sta sta_power.rpt
        lappend _L "# category: power"
        set _fh [open "$_m/sta_power.rpt"]; set _pt [read $_fh]; close $_fh
        set _worst ""; set _wsc ""
        foreach _ln [lrange [split $_pt \n] 1 end] {
            if {[llength $_ln] != 5} continue
            lassign $_ln _sc _t _i _w _l
            lappend _L "Total power mW $_sc : $_t" "Internal power mW $_sc : $_i" \
                       "Switching power mW $_sc : $_w" "Leakage power mW $_sc : $_l"
            if {$_worst eq "" || $_t > $_worst} { set _worst $_t; set _wsc $_sc }
        }
        lappend _L "Total power mW : $_worst" "Worst power view : $_wsc"
        lappend _L "# category: timing"
    }
    source "$_m/sta_summary.tcl"
    set _ok [expr {$sta_summary(wns_setup) >= [oss_get sta signoff,min_setup_wns]
                   && $sta_summary(wns_hold) >= [oss_get sta signoff,min_hold_wns]}]
    lappend _L "Scenarios : $sta_summary(scenarios)" "Worst setup WNS : $sta_summary(wns_setup)" \
               "Worst hold WNS : $sta_summary(wns_hold)" \
               "# category: signoff" "Status : [expr {$_ok ? "PASS" : "FAIL"}]"
    set _fh [open "$_dir/metrics.rpt" w]; puts $_fh [join $_L \n]; close $_fh
    ::CBFlow::Release::generate_manifest
    ::CBFlow::Release::stamp_complete
    set _fh [open [oss_stage_out release.manifest] w]
    puts $_fh "release_dir $_dir"
    puts $_fh "attach_to [oss_get sta input,release_tag]"
    close $_fh
    handle_info "STA reports released -> $_dir/reports/sta"
}

flow_exec_all
exit
