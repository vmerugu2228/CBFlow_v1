#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow - EMIR Power Analysis Command File (Voltus)
# Description: Static and dynamic power analysis with power maps and reporting
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

set config_file "$run_dir/work/EMIR/power_analysis/run/config.tcl"
if {[file exists $config_file]} { source $config_file }
global emir project tech flow

# Source tech_config
if {[info exists ::env(TECH_NAME)] && $::env(TECH_NAME) ne "" && [info exists ::env(TECH_VERSION)]} {
    set _tc "$::env(CONFIG_ROOT)/tech/$::env(TECH_NAME)/$::env(TECH_VERSION)/tech_config.tcl"
    if {[file exists $_tc]} { source -e $_tc }
}
# Source user_config for overrides
if {[file exists "$run_dir/setup/user_config.tcl"]} { source -e "$run_dir/setup/user_config.tcl" }

handle_info "Starting EMIR power_analysis stage with Voltus..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

set WORK_DIR "$run_dir/work/EMIR/power_analysis"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                     CONFIGURE ANALYSIS                                     │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc configure_analysis {
    global emir project tech flow
    handle_info "Configuring power analysis settings..."

    file mkdir "$::OUTPUTS_DIR/emir/power"
    file mkdir "$::REPORTS_DIR/power"

    # Set power analysis mode
    if {[info exists emir(power,analysis_mode)]} {
        puts "Power analysis mode: $emir(power,analysis_mode)"
        set_power_analysis_mode -method $emir(power,analysis_mode)
    } else {
        puts "Power analysis mode: averaged (default)"
        set_power_analysis_mode -method averaged
    }

    # Configure power domain
    if {[info exists emir(power,supply_voltage)]} {
        puts "Supply voltage: $emir(power,supply_voltage)V"
    }

    # Set clock period for dynamic analysis
    if {[info exists project(clock,period)]} {
        puts "Clock period: $project(clock,period) ns"
        set_power_analysis_mode -clock_period $project(clock,period)
    }

    # Set switching activity defaults
    if {[info exists emir(power,default_toggle_rate)]} {
        set_default_switching_activity -toggle_rate $emir(power,default_toggle_rate)
        puts "Default toggle rate: $emir(power,default_toggle_rate)"
    }
    if {[info exists emir(power,default_static_probability)]} {
        set_default_switching_activity -static_probability $emir(power,default_static_probability)
        puts "Default static probability: $emir(power,default_static_probability)"
    }

    # Set analysis precision
    if {[info exists emir(power,precision)]} {
        set_power_analysis_mode -accuracy $emir(power,precision)
        puts "Analysis precision: $emir(power,precision)"
    }

    puts " Power analysis configuration completed"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                     RUN STATIC POWER                                       │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc run_static_power {
    global emir project tech flow
    handle_info "Running static (leakage) power analysis..."

    set rpt_file "$::REPORTS_DIR/power/static_power.rpt"

    # Run static power analysis
    report_power -static \
        -out_file $rpt_file

    # Generate hierarchical static power breakdown
    set hier_rpt "$::REPORTS_DIR/power/static_power_hierarchy.rpt"
    report_power -static -hierarchy \
        -out_file $hier_rpt

    # Report per-domain static power if multi-voltage
    if {[info exists emir(power,multi_voltage)] && $emir(power,multi_voltage) eq "true"} {
        set domain_rpt "$::REPORTS_DIR/power/static_power_domains.rpt"
        report_power -static -power_domain \
            -out_file $domain_rpt
        handle_info "  Per-domain static power: $domain_rpt"
    }

    handle_info "  Static power report: $rpt_file"
    handle_info "  Hierarchical report: $hier_rpt"
    puts " Static power analysis completed"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                     RUN DYNAMIC POWER                                      │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc run_dynamic_power {
    global emir project tech flow
    handle_info "Running dynamic (switching + internal) power analysis..."

    set rpt_file "$::REPORTS_DIR/power/dynamic_power.rpt"

    # Run dynamic power analysis
    report_power -dynamic \
        -out_file $rpt_file

    # Generate hierarchical dynamic power breakdown
    set hier_rpt "$::REPORTS_DIR/power/dynamic_power_hierarchy.rpt"
    report_power -dynamic -hierarchy \
        -out_file $hier_rpt

    # Detailed switching power breakdown
    set switching_rpt "$::REPORTS_DIR/power/switching_power.rpt"
    report_power -switching \
        -out_file $switching_rpt

    # Internal power breakdown
    set internal_rpt "$::REPORTS_DIR/power/internal_power.rpt"
    report_power -internal \
        -out_file $internal_rpt

    handle_info "  Dynamic power report: $rpt_file"
    handle_info "  Switching power report: $switching_rpt"
    handle_info "  Internal power report: $internal_rpt"
    puts " Dynamic power analysis completed"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                     GENERATE POWER MAPS                                    │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc generate_power_maps {
    global emir project tech flow
    handle_info "Generating power density maps..."

    file mkdir "$::OUTPUTS_DIR/emir/power/maps"

    # Generate power density map
    if {[info exists emir(power,map_resolution)]} {
        set resolution $emir(power,map_resolution)
    } else {
        set resolution 10
    }

    report_power_density \
        -resolution $resolution \
        -out_file "$::OUTPUTS_DIR/emir/power/maps/power_density.map"

    # Generate per-layer power map if configured
    if {[info exists emir(power,per_layer_map)] && $emir(power,per_layer_map) eq "true"} {
        report_power_density -per_layer \
            -resolution $resolution \
            -out_file "$::OUTPUTS_DIR/emir/power/maps/power_density_per_layer.map"
    }

    handle_info "  Power density map resolution: $resolution"
    puts " Power maps generated"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                     GENERATE REPORT                                        │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc generate_report {
    global emir project tech flow
    handle_info "Generating power analysis summary report..."

    set summary_file "$::REPORTS_DIR/power/power_analysis_summary.rpt"
    file mkdir [file dirname $summary_file]
    set fp [open $summary_file w]
    puts $fp "═══════════════════════════════════════════════════════════════"
    puts $fp "CBFlow EMIR Power Analysis Summary - Voltus"
    puts $fp "═══════════════════════════════════════════════════════════════"
    puts $fp "Generated: [clock format [clock seconds]]"
    puts $fp "Tool: Cadence Voltus"
    if {[info exists project(top_module)]} { puts $fp "Design: $project(top_module)" }
    if {[info exists project(name)]} { puts $fp "Project: $project(name)" }
    puts $fp ""
    puts $fp "Configuration:"
    if {[info exists emir(power,analysis_mode)]} { puts $fp "  Analysis mode: $emir(power,analysis_mode)" }
    if {[info exists emir(power,supply_voltage)]} { puts $fp "  Supply voltage: $emir(power,supply_voltage)V" }
    if {[info exists project(clock,period)]} { puts $fp "  Clock period: $project(clock,period) ns" }
    puts $fp ""
    puts $fp "Reports Generated:"
    puts $fp "  Static power:    reports/emir/power/static_power.rpt"
    puts $fp "  Dynamic power:   reports/emir/power/dynamic_power.rpt"
    puts $fp "  Switching power: reports/emir/power/switching_power.rpt"
    puts $fp "  Internal power:  reports/emir/power/internal_power.rpt"
    puts $fp "  Power density:   results/emir/power/maps/power_density.map"
    close $fp

    handle_info "  Summary: $summary_file"
    puts " Power analysis reporting completed"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                           EXECUTION CONTROL                                │
# └─────────────────────────────────────────────────────────────────────────────┘

handle_info "═══════════════════════════════════════════════════════════════"
handle_info " CBFlow EMIR power_analysis with Voltus"
handle_info "═══════════════════════════════════════════════════════════════"

flow_proc power_analysis_flow {
    handle_info "Executing EMIR power_analysis flow..."
    flow_exec configure_analysis
    flow_exec run_static_power
    flow_exec run_dynamic_power
    flow_exec generate_power_maps
    flow_exec generate_report
    handle_info "EMIR power_analysis completed successfully"
}

if {[info exists argv0] && $argv0 eq [info script]} { flow_exec power_analysis_flow } else { puts " EMIR power_analysis procedures loaded" }

# Exit tool after stage completion
exit
