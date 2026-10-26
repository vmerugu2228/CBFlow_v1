#!/usr/bin/env tclsh
# EMIR Thermal Analysis - Cadence Voltus
# Note: Voltus integrates thermal into power analysis -- there is no standalone
# thermal solver. Thermal analysis = temperature-dependent power + IR analysis.

# -- Bootstrap -----------------------------------------------------------------
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "EMIR"
set STAGE_NAME "thermal_analysis"
set NODE_NAME "thermal_analysis1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

handle_info "Starting EMIR thermal_analysis stage with Voltus..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

set WORK_DIR "$run_dir/work/EMIR/thermal_analysis1"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                     SETUP THERMAL                                          │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc setup_thermal {
    global emir
    handle_info "Configuring thermal-aware analysis settings..."

    file mkdir "$::REPORTS_DIR/thermal"
    file mkdir "$::OUTPUTS_DIR/emir/thermal"

    # Set ambient temperature
    if {[info exists emir(thermal,ambient_temperature)] && $emir(thermal,ambient_temperature) ne ""} {
        handle_info "  set_db thermal_ambient_temperature $emir(thermal,ambient_temperature)"
        set_db thermal_ambient_temperature $emir(thermal,ambient_temperature)
    } elseif {[info exists emir(voltus,ambient_temp)] && $emir(voltus,ambient_temp) ne ""} {
        handle_info "  set_db thermal_ambient_temperature $emir(voltus,ambient_temp)"
        set_db thermal_ambient_temperature $emir(voltus,ambient_temp)
    }

    # Set operating temperature for power analysis
    if {[info exists emir(voltus,junction_temp)] && $emir(voltus,junction_temp) ne ""} {
        handle_info "  set_db power_temperature $emir(voltus,junction_temp)"
        set_db power_temperature $emir(voltus,junction_temp)
    } elseif {[info exists emir(thermal,max_temperature)] && $emir(thermal,max_temperature) ne ""} {
        handle_info "  set_db power_temperature $emir(thermal,max_temperature)"
        set_db power_temperature $emir(thermal,max_temperature)
    }

    # Read thermal model if available
    if {[info exists emir(thermal,thermal_model_file)] && $emir(thermal,thermal_model_file) ne ""} {
        if {[file exists $emir(thermal,thermal_model_file)]} {
            handle_info "  read_thermal_model $emir(thermal,thermal_model_file)"
            read_thermal_model $emir(thermal,thermal_model_file)
        } else {
            handle_warning "Thermal model file not found: $emir(thermal,thermal_model_file)"
        }
    }

    # Read temperature map if available (for non-uniform temperature distribution)
    if {[info exists emir(thermal,temperature_map_file)] && $emir(thermal,temperature_map_file) ne ""} {
        if {[file exists $emir(thermal,temperature_map_file)]} {
            handle_info "  set_thermal_map -file $emir(thermal,temperature_map_file)"
            set_thermal_map -file $emir(thermal,temperature_map_file)
        } else {
            handle_warning "Temperature map file not found: $emir(thermal,temperature_map_file)"
        }
    }

    handle_info "Thermal configuration completed"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                     RUN THERMAL-AWARE ANALYSIS                             │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc run_thermal_aware_analysis {
    global emir flow
    handle_info "Running thermal-aware power and IR analysis..."

    set vdd_net [expr {[info exists emir(power,vdd_net)] && $emir(power,vdd_net) ne "" ? $emir(power,vdd_net) : "VDD"}]
    set vss_net [expr {[info exists emir(power,vss_net)] && $emir(power,vss_net) ne "" ? $emir(power,vss_net) : "VSS"}]

    # Thermal-aware power analysis: includes temperature-dependent leakage
    handle_info "  set_power_analysis_mode -method static -thermal_aware true"
    if {[info exists emir(power,analysis_view)] && $emir(power,analysis_view) ne ""} {
        set_power_analysis_mode -method static \
            -analysis_view $emir(power,analysis_view) \
            -thermal_aware true
    } else {
        set_power_analysis_mode -method static \
            -thermal_aware true
    }

    # Power report at operating temperature
    set thermal_power_rpt "$::REPORTS_DIR/thermal/thermal_power.rpt"
    handle_info "  report_power -hierarchy all > $thermal_power_rpt"
    report_power -hierarchy all > $thermal_power_rpt

    # Temperature-dependent leakage report
    set leak_rpt "$::REPORTS_DIR/thermal/thermal_leakage.rpt"
    handle_info "  report_power -leakage > $leak_rpt"
    report_power -leakage > $leak_rpt

    # IR drop at operating temperature
    handle_info "  set_pg_analysis_mode -power_grid_analysis static -voltage_from_pg_pin true"
    set_pg_analysis_mode -power_grid_analysis static \
        -voltage_from_pg_pin true

    handle_info "  analyze_power_grid -net $vdd_net -temperature_dependent true"
    analyze_power_grid -net $vdd_net -temperature_dependent true

    # IR drop report at temperature
    set thermal_ir_rpt "$::REPORTS_DIR/thermal/thermal_ir_drop.rpt"
    handle_info "  report_power_rail -net $vdd_net -type ir_drop -temperature_dependent"
    report_power_rail -net $vdd_net -type ir_drop \
        -temperature_dependent > $thermal_ir_rpt

    # Standard IR drop at temperature for comparison
    set ir_rpt "$::REPORTS_DIR/thermal/ir_drop_at_temp.rpt"
    report_power_rail -net $vdd_net -type ir_drop \
        -output_file $ir_rpt

    handle_info "Thermal-aware analysis completed"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                     GENERATE THERMAL REPORT                                │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc generate_thermal_report {
    global emir flow
    handle_info "Generating thermal analysis reports..."

    # Voltus thermal report
    set thermal_rpt "$::REPORTS_DIR/thermal/thermal_results.rpt"
    handle_info "  report_thermal -output_file $thermal_rpt"
    report_thermal -output_file $thermal_rpt

    # Power density report (proxy for thermal hotspots)
    set density_rpt "$::REPORTS_DIR/thermal/power_density.rpt"
    handle_info "  report_power -density > $density_rpt"
    report_power -density > $density_rpt

    # Summary report
    set summary_file "$::REPORTS_DIR/thermal/thermal_analysis_summary.rpt"
    set fp [open $summary_file w]
    puts $fp "================================================================"
    puts $fp "CBFlow EMIR Thermal Analysis Summary - Voltus"
    puts $fp "================================================================"
    puts $fp "Generated: [expr {[catch {clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}} _ts] ? "epoch [clock seconds]" : $_ts}]"
    puts $fp "Tool: Cadence Voltus"
    puts $fp "Design: $flow(design_name)"
    puts $fp ""
    puts $fp "Configuration:"
    if {[info exists emir(thermal,ambient_temperature)] && $emir(thermal,ambient_temperature) ne ""} {
        puts $fp "  Ambient temperature:    $emir(thermal,ambient_temperature)C"
    }
    if {[info exists emir(voltus,junction_temp)] && $emir(voltus,junction_temp) ne ""} {
        puts $fp "  Junction temperature:   $emir(voltus,junction_temp)C"
    }
    if {[info exists emir(thermal,max_temperature)] && $emir(thermal,max_temperature) ne ""} {
        puts $fp "  Max temperature limit:  $emir(thermal,max_temperature)C"
    }
    puts $fp ""
    puts $fp "Note: Voltus integrates thermal into power analysis."
    puts $fp "      Temperature-dependent leakage and IR drop are computed"
    puts $fp "      using the configured junction/ambient temperatures."
    puts $fp "      Power density serves as proxy for thermal hotspot detection."
    puts $fp ""
    puts $fp "Reports Generated:"
    puts $fp "  Thermal power:      thermal/thermal_power.rpt"
    puts $fp "  Thermal leakage:    thermal/thermal_leakage.rpt"
    puts $fp "  Thermal IR drop:    thermal/thermal_ir_drop.rpt"
    puts $fp "  IR at temperature:  thermal/ir_drop_at_temp.rpt"
    puts $fp "  Thermal results:    thermal/thermal_results.rpt"
    puts $fp "  Power density:      thermal/power_density.rpt"
    close $fp

    handle_info "  Summary: $summary_file"
    handle_info "Thermal analysis reporting completed"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                           EXECUTION CONTROL                                │
# └─────────────────────────────────────────────────────────────────────────────┘

handle_info "================================================================"
handle_info " CBFlow EMIR thermal_analysis with Voltus"
handle_info "================================================================"

flow_proc thermal_analysis_flow {
    handle_info "Executing EMIR thermal_analysis flow..."
    flow_exec setup_thermal
    flow_exec run_thermal_aware_analysis
    flow_exec generate_thermal_report
    handle_info "EMIR thermal_analysis completed successfully"
}

if {[info exists argv0] && $argv0 eq [info script]} { flow_exec thermal_analysis_flow } else { puts " EMIR thermal_analysis procedures loaded" }

# Exit tool after stage completion
exit
