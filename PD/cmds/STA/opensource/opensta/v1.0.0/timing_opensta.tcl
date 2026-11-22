#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow STA — timing (opensource / sta)
# OpenSTA timing for one MMMC scenario (::SCENARIO / ::LIB_SET / ::RC_CORNER /
# ::SDC_FILE / ::SPEF_FILE from the timing subnode handler): netlist + libs
# (+ child timing models) + SDC + SPEF, setup/hold/DRV reports and QoR.
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "STA"
set STAGE_NAME "timing"
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

flow_proc load {
    global design_name blocks
    foreach _l [oss_lib_set_files $::LIB_SET] { read_liberty $_l }
    foreach _b $blocks { read_liberty [hier_block_lib [hier_block_views $_b] $_b $::LIB_SET] }
    set _nl [lindex [glob -nocomplain "$::NETLIST_DIR/${design_name}.pt.v" "$::NETLIST_DIR/${design_name}.v"] 0]
    if {$_nl eq ""} { error "netlist not staged in $::NETLIST_DIR (expected ${design_name}.pt.v or ${design_name}.v)" }
    read_verilog $_nl
    link_design $design_name
    read_sdc $::SDC_FILE
    set_propagated_clock [all_clocks]
    if {$::SPEF_FILE ne "" && [file exists $::SPEF_FILE]} {
        read_spef $::SPEF_FILE
    } elseif {[is_true [oss_get sta oss,allow_no_spef]]} {
        handle_warning "no SPEF for $::RC_CORNER — timing with wire-load estimates only (sta(oss,allow_no_spef) true)"
    } else {
        error "no SPEF for $::RC_CORNER ($::SPEF_FILE) — set sta(oss,allow_no_spef) true to time without parasitics"
    }
}

flow_proc report {
    file mkdir $::SCEN_REPORTS
    set _n [oss_get sta oss,report,group_path_count]
    report_checks -path_delay max -group_path_count $_n -format full_clock_expanded > "$::SCEN_REPORTS/setup.rpt"
    report_checks -path_delay min -group_path_count $_n -format full_clock_expanded > "$::SCEN_REPORTS/hold.rpt"
    report_check_types -max_slew -max_capacitance -max_fanout -violators > "$::SCEN_REPORTS/drv.rpt"
    set _fh [open "$::SCEN_REPORTS/[oss_get sta oss,scenario_qor_file]" w]
    puts $_fh "set qor(scenario) \"$::SCENARIO\""
    puts $_fh "set qor(wns_setup) [sta::worst_slack -max]"
    puts $_fh "set qor(wns_hold) [sta::worst_slack -min]"
    puts $_fh "set qor(tns_setup) [sta::total_negative_slack -max]"
    puts $_fh "set qor(tns_hold) [sta::total_negative_slack -min]"
    puts $_fh "set qor(max_tran_violations) [sta::max_slew_violation_count]"
    puts $_fh "set qor(max_cap_violations) [sta::max_capacitance_violation_count]"
    puts $_fh "set qor(max_fanout_violations) [sta::max_fanout_violation_count]"
    # Power (sta(oss,report_power)): report_power on this scenario's corner;
    # the Total row (internal switching leakage total, W) goes into the QoR.
    if {[is_true [oss_get sta oss,report_power]]} {
        report_power > "$::SCEN_REPORTS/power.rpt"
        set _pfh [open "$::SCEN_REPORTS/power.rpt"]; set _pt [read $_pfh]; close $_pfh
        if {![regexp -line {^Total\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)} $_pt -> _int _sw _lk _tot]} {
            error "no Total row in $::SCEN_REPORTS/power.rpt"
        }
        puts $_fh "set qor(power_internal) $_int\nset qor(power_switching) $_sw\nset qor(power_leakage) $_lk\nset qor(power_total) $_tot"
    }
    close $_fh
    puts "QOR $::SCENARIO: wns_setup=[sta::worst_slack -max] wns_hold=[sta::worst_slack -min]"
}

flow_exec_all
exit
