#!/usr/bin/env tclsh
# ===============================================================================
# CBFlow - EMIR IR Drop Command File
# Description: IR drop analysis and hotspot identification
# Tool: Synopsys RedHawk
# ===============================================================================

set run_dir $::env(CBFLOW_RUN_DIR)
set env_file "$run_dir/.run.cbflow.tcl"
if {[file exists $env_file]} { source $env_file } else { puts stderr "ERROR: .run.cbflow.tcl not found"; exit 1 }
if {[info exists ::env(FLOW_DIR)]} { set FLOW_DIR $::env(FLOW_DIR) } else { puts stderr "ERROR: FLOW_DIR not set"; exit 1 }
if {![info exists ::env(UTILITIES_VERSION)] || $::env(UTILITIES_VERSION) eq ""} { puts stderr "ERROR: UTILITIES_VERSION not set"; exit 1 }
set utils_path "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} { source $utils_path } else { puts stderr "ERROR: Utils not found"; exit 1 }
namespace import ::CBFlow::Utilities::print_header

set config_file "$run_dir/work/EMIR/ir_drop/run/config.tcl"
if {[file exists $config_file]} { source $config_file }

# Source tech_config
if {[info exists ::env(TECH_NAME)] && $::env(TECH_NAME) ne "" && [info exists ::env(TECH_VERSION)]} {
    set _tc "$::env(CONFIG_ROOT)/tech/$::env(TECH_NAME)/$::env(TECH_VERSION)/tech_config.tcl"
    if {[file exists $_tc]} { source -e $_tc }
}

# Source user_config for overrides
if {[file exists "$run_dir/setup/user_config.tcl"]} { source -e "$run_dir/setup/user_config.tcl" }
global emir project tech flow
handle_info "Starting EMIR ir_drop with Synopsys RedHawk..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

set WORK_DIR "$run_dir/work/EMIR/ir_drop"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

# --------------------------------------------------------------------------
# Procedure: configure_ir
#   Configure IR drop analysis parameters and thresholds
# --------------------------------------------------------------------------
flow_proc configure_ir {
    global emir project tech
    handle_info "Configuring IR drop analysis..."

    # Set IR drop thresholds
    if {[info exists emir(ir,vdd_threshold)]} {
        set ::ir_vdd_threshold $emir(ir,vdd_threshold)
    } else {
        set ::ir_vdd_threshold 0.05
    }

    if {[info exists emir(ir,vss_threshold)]} {
        set ::ir_vss_threshold $emir(ir,vss_threshold)
    } else {
        set ::ir_vss_threshold 0.02
    }

    # Set supply voltage
    if {[info exists emir(power,vdd_voltage)]} {
        set ::ir_supply_voltage $emir(power,vdd_voltage)
    } else {
        set ::ir_supply_voltage 0.9
    }

    # EM threshold
    if {[info exists emir(ir,em_threshold)]} {
        set ::em_threshold $emir(ir,em_threshold)
    } else {
        set ::em_threshold 1.0
    }

    # Analysis mode
    if {[info exists emir(ir,mode)]} {
        set ::ir_mode $emir(ir,mode)
    } else {
        set ::ir_mode "both"
    }

    handle_info "IR drop configuration:"
    handle_info "  Supply voltage:  ${::ir_supply_voltage}V"
    handle_info "  VDD threshold:   ${::ir_vdd_threshold}V ([format %.1f [expr {$::ir_vdd_threshold / $::ir_supply_voltage * 100}]]%)"
    handle_info "  VSS threshold:   ${::ir_vss_threshold}V"
    handle_info "  EM threshold:    ${::em_threshold} mA/um"
    handle_info "  Analysis mode:   $::ir_mode"
}

# --------------------------------------------------------------------------
# Procedure: run_ir_drop
#   Execute IR drop analysis (static and dynamic)
# --------------------------------------------------------------------------
flow_proc run_ir_drop {
    handle_info "Running IR drop analysis with RedHawk..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    file mkdir "$::REPORTS_DIR/ir_drop"

    set ir_start [clock seconds]

    # Static IR drop analysis
    if {$::ir_mode eq "static" || $::ir_mode eq "both"} {
        handle_info "Running static IR drop analysis..."
        perform_ir_analysis -static
        report_ir_drop -type static -threshold $::ir_vdd_threshold \
            -file "$::REPORTS_DIR/ir_drop/static_ir_drop.rpt"
        report_ir_drop -type static -per_instance \
            -file "$::REPORTS_DIR/ir_drop/static_ir_per_instance.rpt"

        # Generate static IR drop map
        generate_ir_map -type static -file "$::REPORTS_DIR/ir_drop/static_ir_map.rpt"
    }

    # Dynamic IR drop analysis
    if {$::ir_mode eq "dynamic" || $::ir_mode eq "both"} {
        handle_info "Running dynamic IR drop analysis..."
        perform_ir_analysis -dynamic
        report_ir_drop -type dynamic -threshold $::ir_vdd_threshold \
            -file "$::REPORTS_DIR/ir_drop/dynamic_ir_drop.rpt"
        report_ir_drop -type dynamic -per_instance \
            -file "$::REPORTS_DIR/ir_drop/dynamic_ir_per_instance.rpt"

        # Generate dynamic IR drop map
        generate_ir_map -type dynamic -file "$::REPORTS_DIR/ir_drop/dynamic_ir_map.rpt"
    }

    # Electromigration analysis
    handle_info "Running electromigration analysis..."
    perform_em_analysis
    report_em -threshold $::em_threshold -file "$::REPORTS_DIR/ir_drop/em_violations.rpt"

    set ir_end [clock seconds]
    set ::ir_runtime [expr {$ir_end - $ir_start}]
    handle_info "IR drop analysis runtime: ${::ir_runtime} seconds"
}

# --------------------------------------------------------------------------
# Procedure: identify_hotspots
#   Identify worst-case IR drop and EM hotspot locations
# --------------------------------------------------------------------------
flow_proc identify_hotspots {
    global emir
    handle_info "Identifying IR drop and EM hotspots..."
    set run_dir $::env(CBFLOW_RUN_DIR)

    # Find worst IR drop instances
    report_ir_drop -type worst -count 50 \
        -file "$::REPORTS_DIR/ir_drop/worst_ir_instances.rpt"

    # Find worst EM violations
    report_em -type worst -count 50 \
        -file "$::REPORTS_DIR/ir_drop/worst_em_segments.rpt"

    # Check against thresholds
    set ::ir_vdd_max "N/A"
    set ::ir_vdd_violations 0
    set ::em_violations 0

    set worst_rpt "$::REPORTS_DIR/ir_drop/worst_ir_instances.rpt"
    if {[file exists $worst_rpt]} {
        set fp [open $worst_rpt r]; set content [read $fp]; close $fp
        if {[regexp {Worst VDD IR Drop:\s*([0-9.]+)} $content -> val]} {
            set ::ir_vdd_max $val
        }
        if {[regexp {VDD violations.*?:\s*(\d+)} $content -> cnt]} {
            set ::ir_vdd_violations $cnt
        }
    }

    set em_rpt "$::REPORTS_DIR/ir_drop/worst_em_segments.rpt"
    if {[file exists $em_rpt]} {
        set fp [open $em_rpt r]; set content [read $fp]; close $fp
        if {[regexp {EM violations:\s*(\d+)} $content -> cnt]} {
            set ::em_violations $cnt
        }
    }

    handle_info "Hotspot analysis:"
    handle_info "  Worst VDD IR drop: $::ir_vdd_max V"
    handle_info "  IR violations:     $::ir_vdd_violations"
    handle_info "  EM violations:     $::em_violations"
}

# --------------------------------------------------------------------------
# Procedure: generate_ir_report
#   Generate comprehensive IR drop analysis report
# --------------------------------------------------------------------------
flow_proc generate_ir_report {
    global emir project tech
    handle_info "Generating IR drop report..."
    set run_dir $::env(CBFLOW_RUN_DIR)

    set rpt "$::OUTPUTS_DIR/emir/ir_drop.rpt"
    file mkdir [file dirname $rpt]
    set fp [open $rpt w]
    puts $fp "==============================================================================="
    puts $fp "CBFlow EMIR - IR Drop Analysis Results (Synopsys RedHawk)"
    puts $fp "==============================================================================="
    puts $fp "Generated: [clock format [clock seconds]]"
    if {[info exists project(top_module)]} { puts $fp "Design:          $project(top_module)" }
    if {[info exists tech(node)]}          { puts $fp "Technology:      $tech(node)" }
    puts $fp "Tool:            Synopsys RedHawk"
    puts $fp "Supply Voltage:  ${::ir_supply_voltage}V"
    puts $fp "VDD Threshold:   ${::ir_vdd_threshold}V"
    puts $fp "EM Threshold:    ${::em_threshold} mA/um"
    if {[info exists ::ir_runtime]} { puts $fp "Runtime:         ${::ir_runtime} seconds" }
    puts $fp ""
    puts $fp "Results Summary:"
    puts $fp "-----------------------------------------------------------------------"
    puts $fp "  Worst VDD IR Drop:  $::ir_vdd_max V"
    puts $fp "  IR Drop Violations: $::ir_vdd_violations"
    puts $fp "  EM Violations:      $::em_violations"
    puts $fp ""
    puts $fp "Detailed Reports:"
    puts $fp "  reports/emir/ir_drop/static_ir_drop.rpt"
    puts $fp "  reports/emir/ir_drop/dynamic_ir_drop.rpt"
    puts $fp "  reports/emir/ir_drop/em_violations.rpt"
    puts $fp "  reports/emir/ir_drop/worst_ir_instances.rpt"
    close $fp

    handle_info "IR drop report: $rpt"
}

# --------------------------------------------------------------------------
# Top-level flow execution
# --------------------------------------------------------------------------
flow_exec_all configure_ir run_ir_drop identify_hotspots generate_ir_report

# Exit tool after stage completion
exit
