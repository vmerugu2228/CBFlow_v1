#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow - EMIR Thermal Analysis Command File (Voltus)
# Description: Thermal simulation, hotspot detection, and thermal reporting
# Tool: Cadence Voltus
# ═══════════════════════════════════════════════════════════════════════════════

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
global emir project tech flow

# Source tech_config
if {[info exists ::env(TECH_NAME)] && $::env(TECH_NAME) ne "" && [info exists ::env(TECH_VERSION)]} {
    set _tc "$::env(CONFIG_ROOT)/tech/$::env(TECH_NAME)/$::env(TECH_VERSION)/tech_config.tcl"
    if {[file exists $_tc]} { source -e $_tc }
}
# Source user_config for overrides
if {[file exists "$run_dir/setup/user_config.tcl"]} { source -e "$run_dir/setup/user_config.tcl" }

handle_info "Starting EMIR thermal_analysis stage with Voltus..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

set WORK_DIR "$run_dir/work/EMIR/thermal_analysis"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                     CONFIGURE THERMAL                                      │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc configure_thermal {
    global emir project tech flow
    handle_info "Configuring thermal analysis settings..."

    file mkdir "$::REPORTS_DIR/thermal"
    file mkdir "$::OUTPUTS_DIR/emir/thermal"

    # Set ambient temperature
    if {[info exists emir(thermal,ambient_temperature)]} {
        puts "Ambient temperature: $emir(thermal,ambient_temperature)C"
        set_thermal_analysis_mode -ambient_temperature $emir(thermal,ambient_temperature)
    } else {
        puts "Ambient temperature: 25C (default)"
        set_thermal_analysis_mode -ambient_temperature 25
    }

    # Set thermal conductivity model
    if {[info exists emir(thermal,conductivity_model)]} {
        set_thermal_analysis_mode -conductivity_model $emir(thermal,conductivity_model)
        puts "Conductivity model: $emir(thermal,conductivity_model)"
    }

    # Set thermal mesh resolution
    if {[info exists emir(thermal,mesh_resolution)]} {
        set_thermal_analysis_mode -mesh_resolution $emir(thermal,mesh_resolution)
        puts "Mesh resolution: $emir(thermal,mesh_resolution)"
    }

    # Set package thermal resistance (junction to ambient)
    if {[info exists emir(thermal,theta_ja)]} {
        set_thermal_analysis_mode -theta_ja $emir(thermal,theta_ja)
        puts "Theta-JA: $emir(thermal,theta_ja) C/W"
    }

    # Set thermal analysis type (steady-state or transient)
    if {[info exists emir(thermal,analysis_type)]} {
        set_thermal_analysis_mode -type $emir(thermal,analysis_type)
        puts "Analysis type: $emir(thermal,analysis_type)"
    } else {
        set_thermal_analysis_mode -type steady_state
        puts "Analysis type: steady_state (default)"
    }

    # Configure heat sink parameters if available
    if {[info exists emir(thermal,heat_sink_enabled)] && $emir(thermal,heat_sink_enabled) eq "true"} {
        if {[info exists emir(thermal,heat_sink_coefficient)]} {
            set_thermal_analysis_mode -heat_sink_coefficient $emir(thermal,heat_sink_coefficient)
            puts "Heat sink coefficient: $emir(thermal,heat_sink_coefficient)"
        }
    }

    puts " Thermal analysis configuration completed"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                     RUN THERMAL ANALYSIS                                   │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc run_thermal {
    global emir project tech flow
    handle_info "Running thermal simulation..."

    # Run Voltus thermal analysis
    puts "Executing thermal analysis..."
    analyze_thermal

    # Generate thermal map
    set thermal_map "$::OUTPUTS_DIR/emir/thermal/thermal_map.rptdb"
    report_thermal -map \
        -out_file $thermal_map
    handle_info "  Thermal map: $thermal_map"

    # Generate temperature distribution report
    set temp_dist_rpt "$::REPORTS_DIR/thermal/temperature_distribution.rpt"
    report_thermal \
        -out_file $temp_dist_rpt
    handle_info "  Temperature distribution: $temp_dist_rpt"

    # Per-layer thermal report
    if {[info exists emir(thermal,per_layer_report)] && $emir(thermal,per_layer_report) eq "true"} {
        set layer_rpt "$::REPORTS_DIR/thermal/thermal_per_layer.rpt"
        report_thermal -per_layer \
            -out_file $layer_rpt
        handle_info "  Per-layer thermal: $layer_rpt"
    }

    # Generate thermal profile for power-thermal iteration
    if {[info exists emir(thermal,power_thermal_loop)] && $emir(thermal,power_thermal_loop) eq "true"} {
        set thermal_profile "$::OUTPUTS_DIR/emir/thermal/thermal_profile.dat"
        write_thermal_profile $thermal_profile
        handle_info "  Thermal profile for iteration: $thermal_profile"
    }

    puts " Thermal simulation completed"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                     IDENTIFY HOTSPOTS                                      │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc identify_hotspots {
    global emir project tech flow
    handle_info "Identifying thermal hotspots..."

    set hotspot_rpt "$::REPORTS_DIR/thermal/thermal_hotspots.rpt"

    # Set hotspot threshold from config
    if {[info exists emir(thermal,hotspot_threshold)]} {
        report_thermal_hotspot \
            -temperature_threshold $emir(thermal,hotspot_threshold) \
            -out_file $hotspot_rpt
        puts "Hotspot threshold: $emir(thermal,hotspot_threshold)C"
    } else {
        report_thermal_hotspot \
            -out_file $hotspot_rpt
    }
    handle_info "  Hotspot report: $hotspot_rpt"

    # Report worst-case thermal instances
    if {[info exists emir(thermal,max_hotspots)]} {
        set max_hotspots $emir(thermal,max_hotspots)
    } else {
        set max_hotspots 50
    }

    set worst_rpt "$::REPORTS_DIR/thermal/worst_thermal_instances.rpt"
    report_thermal -worst_case $max_hotspots \
        -out_file $worst_rpt
    handle_info "  Worst thermal instances ($max_hotspots): $worst_rpt"

    # Report thermal gradient violations
    if {[info exists emir(thermal,gradient_threshold)]} {
        set gradient_rpt "$::REPORTS_DIR/thermal/thermal_gradient.rpt"
        report_thermal -gradient_threshold $emir(thermal,gradient_threshold) \
            -out_file $gradient_rpt
        handle_info "  Gradient violations: $gradient_rpt"
    }

    puts " Hotspot identification completed"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                     GENERATE REPORT                                        │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc generate_report {
    global emir project tech flow
    handle_info "Generating thermal analysis summary..."

    set summary_file "$::REPORTS_DIR/thermal/thermal_analysis_summary.rpt"
    file mkdir [file dirname $summary_file]
    set fp [open $summary_file w]
    puts $fp "═══════════════════════════════════════════════════════════════"
    puts $fp "CBFlow EMIR Thermal Analysis Summary - Voltus"
    puts $fp "═══════════════════════════════════════════════════════════════"
    puts $fp "Generated: [clock format [clock seconds]]"
    puts $fp "Tool: Cadence Voltus"
    if {[info exists project(top_module)]} { puts $fp "Design: $project(top_module)" }
    if {[info exists project(name)]} { puts $fp "Project: $project(name)" }
    puts $fp ""
    puts $fp "Configuration:"
    if {[info exists emir(thermal,ambient_temperature)]} {
        puts $fp "  Ambient temperature: $emir(thermal,ambient_temperature)C"
    }
    if {[info exists emir(thermal,theta_ja)]} {
        puts $fp "  Theta-JA: $emir(thermal,theta_ja) C/W"
    }
    if {[info exists emir(thermal,analysis_type)]} {
        puts $fp "  Analysis type: $emir(thermal,analysis_type)"
    }
    if {[info exists emir(thermal,hotspot_threshold)]} {
        puts $fp "  Hotspot threshold: $emir(thermal,hotspot_threshold)C"
    }
    puts $fp ""
    puts $fp "Reports Generated:"
    puts $fp "  Temperature distribution: reports/emir/thermal/temperature_distribution.rpt"
    puts $fp "  Thermal hotspots:         reports/emir/thermal/thermal_hotspots.rpt"
    puts $fp "  Worst instances:          reports/emir/thermal/worst_thermal_instances.rpt"
    puts $fp "  Thermal map:              results/emir/thermal/thermal_map.rptdb"
    close $fp

    handle_info "  Summary: $summary_file"
    puts " Thermal analysis reporting completed"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                           EXECUTION CONTROL                                │
# └─────────────────────────────────────────────────────────────────────────────┘

handle_info "═══════════════════════════════════════════════════════════════"
handle_info " CBFlow EMIR thermal_analysis with Voltus"
handle_info "═══════════════════════════════════════════════════════════════"

flow_proc thermal_analysis_flow {
    handle_info "Executing EMIR thermal_analysis flow..."
    flow_exec configure_thermal
    flow_exec run_thermal
    flow_exec identify_hotspots
    flow_exec generate_report
    handle_info "EMIR thermal_analysis completed successfully"
}

if {[info exists argv0] && $argv0 eq [info script]} { flow_exec thermal_analysis_flow } else { puts " EMIR thermal_analysis procedures loaded" }

# Exit tool after stage completion
exit
