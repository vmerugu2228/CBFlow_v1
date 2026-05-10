#!/usr/bin/env tclsh
# ===============================================================================
# CBFlow - EMIR Thermal Analysis Command File
# Description: Thermal simulation and hotspot identification
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

set config_file "$run_dir/work/EMIR/thermal_analysis/run/config.tcl"
if {[file exists $config_file]} { source $config_file }

# Source tech_config
if {[info exists ::env(TECH_NAME)] && $::env(TECH_NAME) ne "" && [info exists ::env(TECH_VERSION)]} {
    set _tc "$::env(CONFIG_ROOT)/tech/$::env(TECH_NAME)/$::env(TECH_VERSION)/tech_config.tcl"
    if {[file exists $_tc]} { source -e $_tc }
}

# Source user_config for overrides
if {[file exists "$run_dir/setup/user_config.tcl"]} { source -e "$run_dir/setup/user_config.tcl" }
global emir project tech flow
handle_info "Starting EMIR thermal_analysis with Synopsys RedHawk..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

set WORK_DIR "$run_dir/work/EMIR/thermal_analysis"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

# --------------------------------------------------------------------------
# Procedure: configure_thermal
#   Set up thermal simulation parameters
# --------------------------------------------------------------------------
flow_proc configure_thermal {
    global emir project tech
    handle_info "Configuring thermal analysis..."

    # Ambient temperature
    if {[info exists emir(thermal,ambient_temp)]} {
        set ::thermal_ambient $emir(thermal,ambient_temp)
    } else {
        set ::thermal_ambient 25.0
    }

    # Thermal threshold for hotspot detection
    if {[info exists emir(thermal,threshold)]} {
        set ::thermal_threshold $emir(thermal,threshold)
    } else {
        set ::thermal_threshold 105.0
    }

    # Package thermal resistance
    if {[info exists emir(thermal,theta_ja)]} {
        set ::thermal_theta_ja $emir(thermal,theta_ja)
        set_thermal_option -theta_ja $emir(thermal,theta_ja)
    }

    # Thermal conductivity of substrate
    if {[info exists emir(thermal,substrate_k)]} {
        set_thermal_option -substrate_conductivity $emir(thermal,substrate_k)
    }

    # Boundary conditions
    if {[info exists emir(thermal,boundary)]} {
        set_thermal_option -boundary_condition $emir(thermal,boundary)
    }

    # Grid resolution
    if {[info exists emir(thermal,grid_resolution)]} {
        set_thermal_option -grid_resolution $emir(thermal,grid_resolution)
    }

    handle_info "Thermal configuration:"
    handle_info "  Ambient temperature: ${::thermal_ambient}C"
    handle_info "  Hotspot threshold:   ${::thermal_threshold}C"
    if {[info exists ::thermal_theta_ja]} { handle_info "  Theta-JA:            ${::thermal_theta_ja} C/W" }
}

# --------------------------------------------------------------------------
# Procedure: run_thermal_sim
#   Execute thermal simulation
# --------------------------------------------------------------------------
flow_proc run_thermal_sim {
    handle_info "Running thermal simulation with RedHawk..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    file mkdir "$::REPORTS_DIR/thermal"

    set thermal_start [clock seconds]

    # Set ambient temperature
    set_temperature $::thermal_ambient

    # Perform thermal analysis
    perform_thermal_analysis -ambient $::thermal_ambient

    # Generate thermal map
    report_thermal -type temperature_map \
        -file "$::REPORTS_DIR/thermal/thermal_map.rpt"

    # Generate per-layer thermal report
    report_thermal -type per_layer \
        -file "$::REPORTS_DIR/thermal/per_layer_thermal.rpt"

    # Generate thermal gradient report
    report_thermal -type gradient \
        -file "$::REPORTS_DIR/thermal/thermal_gradient.rpt"

    # Generate power density to thermal correlation
    report_thermal -type power_correlation \
        -file "$::REPORTS_DIR/thermal/power_thermal_correlation.rpt"

    set thermal_end [clock seconds]
    set ::thermal_runtime [expr {$thermal_end - $thermal_start}]
    handle_info "Thermal simulation runtime: ${::thermal_runtime} seconds"
}

# --------------------------------------------------------------------------
# Procedure: identify_hotspots
#   Identify thermal hotspots exceeding threshold
# --------------------------------------------------------------------------
flow_proc identify_hotspots {
    global emir
    handle_info "Identifying thermal hotspots..."
    set run_dir $::env(CBFLOW_RUN_DIR)

    # Report hotspots above threshold
    report_thermal -type hotspot -threshold $::thermal_threshold \
        -file "$::REPORTS_DIR/thermal/hotspots.rpt"

    # Get worst-case temperatures
    report_thermal -type worst -count 50 \
        -file "$::REPORTS_DIR/thermal/worst_thermal.rpt"

    # Parse results
    set ::thermal_max_temp "N/A"
    set ::thermal_avg_temp "N/A"
    set ::thermal_hotspot_count 0

    set hotspot_rpt "$::REPORTS_DIR/thermal/hotspots.rpt"
    if {[file exists $hotspot_rpt]} {
        set fp [open $hotspot_rpt r]; set content [read $fp]; close $fp
        if {[regexp {Maximum Temperature:\s*([0-9.]+)} $content -> val]} { set ::thermal_max_temp $val }
        if {[regexp {Average Temperature:\s*([0-9.]+)} $content -> val]} { set ::thermal_avg_temp $val }
        if {[regexp {Hotspot Count:\s*(\d+)} $content -> cnt]}           { set ::thermal_hotspot_count $cnt }
    }

    set worst_rpt "$::REPORTS_DIR/thermal/worst_thermal.rpt"
    if {[file exists $worst_rpt]} {
        set fp [open $worst_rpt r]; set content [read $fp]; close $fp
        if {$::thermal_max_temp eq "N/A" && [regexp {Worst.*?:\s*([0-9.]+)} $content -> val]} {
            set ::thermal_max_temp $val
        }
    }

    handle_info "Thermal analysis results:"
    handle_info "  Maximum temperature: ${::thermal_max_temp}C"
    handle_info "  Average temperature: ${::thermal_avg_temp}C"
    handle_info "  Hotspot count:       $::thermal_hotspot_count"

    if {$::thermal_max_temp ne "N/A" && $::thermal_max_temp > $::thermal_threshold} {
        handle_warning "Maximum temperature (${::thermal_max_temp}C) exceeds threshold (${::thermal_threshold}C)"
    }
}

# --------------------------------------------------------------------------
# Procedure: generate_thermal_report
#   Generate comprehensive thermal analysis report
# --------------------------------------------------------------------------
flow_proc generate_thermal_report {
    global emir project tech
    handle_info "Generating thermal analysis report..."
    set run_dir $::env(CBFLOW_RUN_DIR)

    set rpt "$::OUTPUTS_DIR/emir/thermal_analysis.rpt"
    file mkdir [file dirname $rpt]
    set fp [open $rpt w]
    puts $fp "==============================================================================="
    puts $fp "CBFlow EMIR - Thermal Analysis Results (Synopsys RedHawk)"
    puts $fp "==============================================================================="
    puts $fp "Generated: [clock format [clock seconds]]"
    if {[info exists project(top_module)]} { puts $fp "Design:     $project(top_module)" }
    if {[info exists tech(node)]}          { puts $fp "Technology: $tech(node)" }
    puts $fp "Tool:       Synopsys RedHawk"
    puts $fp ""
    puts $fp "Analysis Parameters:"
    puts $fp "  Ambient Temperature: ${::thermal_ambient}C"
    puts $fp "  Hotspot Threshold:   ${::thermal_threshold}C"
    if {[info exists ::thermal_theta_ja]} { puts $fp "  Theta-JA:            ${::thermal_theta_ja} C/W" }
    if {[info exists ::thermal_runtime]}  { puts $fp "  Runtime:             ${::thermal_runtime} seconds" }
    puts $fp ""
    puts $fp "Results Summary:"
    puts $fp "-----------------------------------------------------------------------"
    puts $fp "  Maximum Temperature: ${::thermal_max_temp}C"
    puts $fp "  Average Temperature: ${::thermal_avg_temp}C"
    puts $fp "  Hotspot Count:       $::thermal_hotspot_count"
    puts $fp ""
    puts $fp "Detailed Reports:"
    puts $fp "  reports/emir/thermal/thermal_map.rpt"
    puts $fp "  reports/emir/thermal/hotspots.rpt"
    puts $fp "  reports/emir/thermal/thermal_gradient.rpt"
    puts $fp "  reports/emir/thermal/power_thermal_correlation.rpt"
    close $fp

    handle_info "Thermal analysis report: $rpt"
}

# --------------------------------------------------------------------------
# Top-level flow execution
# --------------------------------------------------------------------------
flow_exec_all configure_thermal run_thermal_sim identify_hotspots generate_thermal_report

# Exit tool after stage completion
exit
