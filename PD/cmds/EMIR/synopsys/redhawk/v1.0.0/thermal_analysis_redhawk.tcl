#!/usr/bin/env tclsh
# CBFlow EMIR thermal analysis - Synopsys RedHawk

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "EMIR"
set STAGE_NAME "thermal_analysis"
set NODE_NAME "${STAGE_NAME}1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

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
    puts $fp "Generated: [expr {[catch {clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}} _ts] ? "epoch [clock seconds]" : $_ts}]"
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
