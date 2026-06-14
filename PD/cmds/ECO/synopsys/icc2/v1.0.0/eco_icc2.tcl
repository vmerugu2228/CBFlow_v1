#!/usr/bin/env tclsh
# ===============================================================================
# CBFlow - ECO Implementation Command File
# Description: Apply functional and timing ECOs using IC Compiler II
# Tool: Synopsys IC Compiler II
# ===============================================================================

set run_dir $::env(CBFLOW_RUN_DIR)
set env_file "$run_dir/.run.cbflow.tcl"
if {[file exists $env_file]} { source $env_file } else { puts stderr "ERROR: .run.cbflow.tcl not found"; exit 1 }
if {[info exists ::env(FLOW_DIR)]} { set FLOW_DIR $::env(FLOW_DIR) } else { puts stderr "ERROR: FLOW_DIR not set"; exit 1 }
if {![info exists ::env(UTILITIES_VERSION)] || $::env(UTILITIES_VERSION) eq ""} { puts stderr "ERROR: UTILITIES_VERSION not set"; exit 1 }
set utils_path "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} { source $utils_path } else { puts stderr "ERROR: Utils not found"; exit 1 }
namespace import ::CBFlow::Utilities::print_header

set config_file "$run_dir/work/ECO/eco/run/config.tcl"
if {[file exists $config_file]} { source $config_file }
global eco project tech flow
handle_info "Starting ECO implementation with Synopsys IC Compiler II..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

# ── Directories ──────────────────────────────────────────────────────────────
set WORK_DIR "$run_dir/work/ECO/eco1"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

# Source tech_config
if {[info exists ::env(TECH_NAME)] && $::env(TECH_NAME) ne "" &&
    [info exists ::env(TECH_VERSION)] && $::env(TECH_VERSION) ne ""} {
    set _tc "$::env(CONFIG_ROOT)/tech/$::env(TECH_NAME)/$::env(TECH_VERSION)/tech_config.tcl"
    if {[file exists $_tc]} { source $_tc }
}
# Source user_config for overrides
if {[file exists "$run_dir/setup/user_config.tcl"]} { source "$run_dir/setup/user_config.tcl" }

# --------------------------------------------------------------------------
# Procedure: apply_functional_eco
#   Apply functional ECO changes from modified Verilog
# --------------------------------------------------------------------------
flow_proc apply_functional_eco {
    global eco project
    handle_info "Applying functional ECO changes..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    file mkdir "$::OUTPUTS_DIR" ; file mkdir "$::REPORTS_DIR"

    set ::eco_func_applied 0

    # Apply ECO from Verilog netlist changes
    if {[info exists eco(input,eco_verilog)]} {
        set eco_verilog $eco(input,eco_verilog)
        handle_info "Applying functional ECO from: $eco_verilog"
        eco_netlist -by_verilog_file $eco_verilog
        set ::eco_func_applied 1
        report_eco_changes -file "$::REPORTS_DIR/functional_eco_changes.rpt"
        handle_info "Functional ECO changes applied"
    }

    # Apply ECO from script
    if {[info exists eco(input,eco_script)]} {
        handle_info "Applying ECO script: $eco(input,eco_script)"
        source $eco(input,eco_script)
        set ::eco_func_applied 1
    }

    # Apply from change list
    if {[info exists eco(input,change_list)]} {
        handle_info "Processing change list: $eco(input,change_list)"
        eco_netlist -by_change_list $eco(input,change_list)
        set ::eco_func_applied 1
    }

    if {$::eco_func_applied == 0} {
        handle_info "No functional ECO changes to apply"
    }
}

# --------------------------------------------------------------------------
# Procedure: apply_timing_eco
#   Apply timing-driven ECO optimizations
# --------------------------------------------------------------------------
flow_proc apply_timing_eco {
    global eco
    handle_info "Applying timing ECO optimizations..."
    set run_dir $::env(CBFLOW_RUN_DIR)

    if {[info exists eco(timing_eco,enable)] && $eco(timing_eco,enable) eq "true"} {
        if {[info exists eco(timing_eco,setup_margin)]} {
            set_app_options -name opt.timing.setup_margin -value $eco(timing_eco,setup_margin)
        }
        if {[info exists eco(timing_eco,hold_margin)]} {
            set_app_options -name opt.timing.hold_margin -value $eco(timing_eco,hold_margin)
        }

        handle_info "Running timing ECO optimization..."
        eco_opt_timing

        report_timing -type eco -file "$::REPORTS_DIR/timing_eco.rpt"
        handle_info "Timing ECO applied"
    } else {
        handle_info "Timing ECO not requested (eco(timing_eco,enable) not set)"
    }
}

# --------------------------------------------------------------------------
# Procedure: place_eco_cells
#   Place newly added ECO cells in ICC2
# --------------------------------------------------------------------------
flow_proc place_eco_cells {
    global eco
    handle_info "Placing ECO cells..."
    set run_dir $::env(CBFLOW_RUN_DIR)

    # Place ECO cells with legalization
    place_eco_cells -eco_changed_cells -legalize
    legalize_placement

    report_placement -type eco -file "$::REPORTS_DIR/eco_placement.rpt"
    report_congestion -file "$::REPORTS_DIR/eco_congestion.rpt"

    handle_info "ECO cell placement completed"
}

# --------------------------------------------------------------------------
# Procedure: route_eco_nets
#   Route nets affected by ECO changes in ICC2
# --------------------------------------------------------------------------
flow_proc route_eco_nets {
    global eco
    handle_info "Routing ECO nets..."
    set run_dir $::env(CBFLOW_RUN_DIR)

    # Route ECO-affected nets
    route_eco -reroute
    route_detail -incremental

    # Fix DRC violations from ECO routing
    route_opt -eco

    report_route -type eco -file "$::REPORTS_DIR/eco_routing.rpt"
    check_routes -file "$::REPORTS_DIR/eco_drc_check.rpt"

    handle_info "ECO net routing completed"
}

# --------------------------------------------------------------------------
# Procedure: validate_eco
#   Validate ECO implementation (connectivity, timing, DRC)
# --------------------------------------------------------------------------
flow_proc validate_eco {
    global eco project
    handle_info "Validating ECO implementation..."
    set run_dir $::env(CBFLOW_RUN_DIR)

    set ::eco_errors {}

    # Check connectivity
    handle_info "Checking connectivity..."
    if {[catch {check_connectivity} conn_result]} {
        lappend ::eco_errors "Connectivity check failed: $conn_result"
    }

    # Check timing
    handle_info "Running timing analysis..."
    report_timing -max_paths [expr {[info exists eco(analysis,max_paths)] ? $eco(analysis,max_paths) : 100}] -file "$::REPORTS_DIR/eco_timing_final.rpt"
    report_qor -file "$::REPORTS_DIR/eco_qor.rpt"

    # Parse timing
    set ::eco_setup_wns "N/A"
    set ::eco_hold_wns "N/A"
    set timing_rpt "$::REPORTS_DIR/eco_timing_final.rpt"
    if {[file exists $timing_rpt]} {
        set fp [open $timing_rpt r]; set content [read $fp]; close $fp
        if {[regexp {Setup WNS:\s*([0-9.-]+)} $content -> val]} { set ::eco_setup_wns $val }
        if {[regexp {Hold WNS:\s*([0-9.-]+)} $content -> val]}  { set ::eco_hold_wns $val }
    }

    # Check DRC
    handle_info "Running DRC..."
    report_design -physical -file "$::REPORTS_DIR/eco_physical.rpt"

    if {[llength $::eco_errors] > 0} {
        foreach err $::eco_errors { handle_error "ECO validation: $err" }
    } else {
        handle_info "ECO validation passed"
    }
}

# --------------------------------------------------------------------------
# Procedure: generate_eco_report
#   Generate comprehensive ECO report
# --------------------------------------------------------------------------
flow_proc generate_eco_report {
    global eco project tech
    handle_info "Generating ECO report..."
    set run_dir $::env(CBFLOW_RUN_DIR)

    set rpt "$::OUTPUTS_DIR/eco_results.rpt"
    file mkdir [file dirname $rpt]
    set fp [open $rpt w]
    puts $fp "==============================================================================="
    puts $fp "CBFlow ECO - Implementation Results (Synopsys ICC2)"
    puts $fp "==============================================================================="
    puts $fp "Generated: [expr {[catch {clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}} _ts] ? "epoch [clock seconds]" : $_ts}]"
    if {[info exists project(top_module)]} { puts $fp "Design: $project(top_module)" }
    if {[info exists tech(node)]}          { puts $fp "Technology: $tech(node)" }
    puts $fp "Tool: Synopsys IC Compiler II"
    puts $fp ""
    puts $fp "ECO Summary:"
    puts $fp "-----------------------------------------------------------------------"
    puts $fp "  Functional ECO Applied: [expr {[info exists ::eco_func_applied] && $::eco_func_applied ? \"YES\" : \"NO\"}]"
    if {[info exists ::eco_setup_wns]} { puts $fp "  Setup WNS: $::eco_setup_wns" }
    if {[info exists ::eco_hold_wns]}  { puts $fp "  Hold WNS:  $::eco_hold_wns" }
    puts $fp "  Validation Errors: [expr {[info exists ::eco_errors] ? [llength $::eco_errors] : 0}]"
    puts $fp ""
    puts $fp "Detailed Reports:"
    puts $fp "  reports/eco/functional_eco_changes.rpt"
    puts $fp "  reports/eco/eco_timing_final.rpt"
    puts $fp "  reports/eco/eco_qor.rpt"
    puts $fp "  reports/eco/eco_routing.rpt"
    close $fp

    handle_info "ECO report: $rpt"
}

# --------------------------------------------------------------------------
# Top-level flow execution
# --------------------------------------------------------------------------
flow_exec_all apply_functional_eco apply_timing_eco place_eco_cells route_eco_nets validate_eco generate_eco_report

# Exit tool after stage completion
exit
