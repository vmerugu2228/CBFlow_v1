#!/usr/bin/env tclsh
# EMIR Power Analysis - Cadence Voltus

# -- Bootstrap -----------------------------------------------------------------
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "EMIR"
set STAGE_NAME "power_analysis"
set NODE_NAME "power_analysis1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

handle_info "Starting EMIR power_analysis stage with Voltus..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

set WORK_DIR "$run_dir/work/EMIR/power_analysis1"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                     SETUP POWER ANALYSIS                                   │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc setup_power_analysis {
    global emir flow
    handle_info "Configuring power analysis mode..."

    file mkdir "$::REPORTS_DIR/power"
    file mkdir "$::OUTPUTS_DIR/emir/power"

    # Determine analysis method from config: static | dynamic | dynamic_vectorless
    set method "static"
    if {[info exists emir(power,analysis_mode)] && $emir(power,analysis_mode) ne ""} {
        set method $emir(power,analysis_mode)
    }

    # Determine analysis view if configured
    set view_opt ""
    if {[info exists emir(power,analysis_view)] && $emir(power,analysis_view) ne ""} {
        set view_opt "-analysis_view $emir(power,analysis_view)"
    }

    handle_info "  Power analysis method: $method"
    if {$view_opt ne ""} {
        handle_info "  set_power_analysis_mode -method $method $view_opt"
        set_power_analysis_mode -method $method {*}[list -analysis_view $emir(power,analysis_view)]
    } else {
        handle_info "  set_power_analysis_mode -method $method"
        set_power_analysis_mode -method $method
    }

    # Set switching activity for vectorless/static analysis
    if {$method eq "static" || $method eq "vectorless"} {
        # Check for activity file (SAIF/VCD)
        if {[info exists emir(input,power_activity_file)] && $emir(input,power_activity_file) ne ""} {
            if {[file exists $emir(input,power_activity_file)]} {
                # Detect format from extension
                set ext [string tolower [file extension $emir(input,power_activity_file)]]
                set fmt "SAIF"
                if {$ext eq ".vcd"} { set fmt "VCD" }
                if {$ext eq ".fsdb"} { set fmt "FSDB" }
                if {$ext eq ".tcf"} { set fmt "TCF" }

                set scope_opt ""
                if {[info exists emir(power,activity_scope)] && $emir(power,activity_scope) ne ""} {
                    set scope_opt "-scope $emir(power,activity_scope)"
                }

                handle_info "  read_activity_file -format $fmt $scope_opt $emir(input,power_activity_file)"
                if {$scope_opt ne ""} {
                    read_activity_file -format $fmt -scope $emir(power,activity_scope) $emir(input,power_activity_file)
                } else {
                    read_activity_file -format $fmt $emir(input,power_activity_file)
                }
            } else {
                handle_warning "Activity file not found: $emir(input,power_activity_file)"
            }
        } else {
            # Use default switching activity from config
            set input_activity "0.2"
            set period "2.0"
            if {[info exists emir(power,default_toggle_rate)] && $emir(power,default_toggle_rate) ne ""} {
                set input_activity $emir(power,default_toggle_rate)
            }
            if {[info exists emir(power,default_static_probability)] && $emir(power,default_static_probability) ne ""} {
                set period $emir(power,default_static_probability)
            }

            handle_info "  set_default_switching_activity -input_activity $input_activity -period $period"
            set_default_switching_activity -input_activity $input_activity -period $period
        }
    }

    # Dynamic analysis: read VCD and configure simulation
    if {$method eq "dynamic"} {
        if {[info exists emir(input,power_activity_file)] && $emir(input,power_activity_file) ne "" && [file exists $emir(input,power_activity_file)]} {
            set ext [string tolower [file extension $emir(input,power_activity_file)]]
            set fmt "VCD"
            if {$ext eq ".fsdb"} { set fmt "FSDB" }

            set scope_opt ""
            if {[info exists emir(power,activity_scope)] && $emir(power,activity_scope) ne ""} {
                set scope_opt "-scope $emir(power,activity_scope)"
            }

            handle_info "  read_activity_file -format $fmt $scope_opt $emir(input,power_activity_file)"
            if {$scope_opt ne ""} {
                read_activity_file -format $fmt -scope $emir(power,activity_scope) $emir(input,power_activity_file)
            } else {
                read_activity_file -format $fmt $emir(input,power_activity_file)
            }
        } else {
            handle_warning "Dynamic analysis requires VCD/FSDB -- falling back to dynamic_vectorless"
            set_power_analysis_mode -method dynamic_vectorless
        }
    }

    handle_info "Power analysis setup completed"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                     RUN POWER ANALYSIS                                     │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc run_power_analysis {
    global emir flow
    handle_info "Running power analysis..."

    # Total power summary
    set power_rpt "$::REPORTS_DIR/power/power_summary.rpt"
    handle_info "  report_power > $power_rpt"
    report_power > $power_rpt

    # Hierarchical power breakdown
    set hier_rpt "$::REPORTS_DIR/power/power_hierarchy.rpt"
    handle_info "  report_power -hierarchy all > $hier_rpt"
    report_power -hierarchy all > $hier_rpt

    # Leakage power
    set leak_rpt "$::REPORTS_DIR/power/power_leakage.rpt"
    handle_info "  report_power -leakage > $leak_rpt"
    report_power -leakage > $leak_rpt

    # Internal (short-circuit) power
    set int_rpt "$::REPORTS_DIR/power/power_internal.rpt"
    handle_info "  report_power -internal > $int_rpt"
    report_power -internal > $int_rpt

    # Switching (dynamic) power
    set sw_rpt "$::REPORTS_DIR/power/power_switching.rpt"
    handle_info "  report_power -switching > $sw_rpt"
    report_power -switching > $sw_rpt

    # Per-instance power for detailed analysis
    set inst_rpt "$::REPORTS_DIR/power/power_per_instance.rpt"
    handle_info "  report_power -per_instance > $inst_rpt"
    report_power -per_instance > $inst_rpt

    handle_info "Power analysis completed"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                     SETUP PG ANALYSIS                                      │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc setup_pg_analysis {
    global emir
    handle_info "Configuring power grid analysis mode..."

    # Static PG analysis as baseline for power-driven IR
    handle_info "  set_pg_analysis_mode -power_grid_analysis static -voltage_from_pg_pin true"
    set_pg_analysis_mode -power_grid_analysis static \
        -voltage_from_pg_pin true

    handle_info "PG analysis mode configured"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                     RUN PG ANALYSIS                                        │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc run_pg_analysis {
    global emir
    handle_info "Running power grid analysis for power data..."

    # Get power/ground net names
    set vdd_net [expr {[info exists emir(power,vdd_net)] && $emir(power,vdd_net) ne "" ? $emir(power,vdd_net) : "VDD"}]
    set vss_net [expr {[info exists emir(power,vss_net)] && $emir(power,vss_net) ne "" ? $emir(power,vss_net) : "VSS"}]

    # Analyze power grids
    handle_info "  analyze_power_grid -net $vdd_net"
    analyze_power_grid -net $vdd_net
    handle_info "  analyze_power_grid -net $vss_net"
    analyze_power_grid -net $vss_net

    # Power grid integrity check
    set pg_check_rpt "$::REPORTS_DIR/power/pg_check.rpt"
    handle_info "  check_power_grid -net {$vdd_net $vss_net} -output_file $pg_check_rpt"
    check_power_grid -net [list $vdd_net $vss_net] -output_file $pg_check_rpt

    handle_info "PG analysis completed"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                     GENERATE REPORTS                                       │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc generate_reports {
    global emir flow
    handle_info "Generating power analysis reports..."

    set vdd_net [expr {[info exists emir(power,vdd_net)] && $emir(power,vdd_net) ne "" ? $emir(power,vdd_net) : "VDD"}]

    # IR drop from power analysis (quick check)
    set ir_rpt "$::REPORTS_DIR/power/ir_drop_quick.rpt"
    handle_info "  report_power_rail -net $vdd_net -type ir_drop > $ir_rpt"
    report_power_rail -net $vdd_net -type ir_drop > $ir_rpt

    # Final power report
    set final_rpt "$::REPORTS_DIR/power/power_final.rpt"
    handle_info "  report_power -detail > $final_rpt"
    report_power -detail > $final_rpt

    # Summary file
    set summary_file "$::REPORTS_DIR/power/power_analysis_summary.rpt"
    set fp [open $summary_file w]
    puts $fp "================================================================"
    puts $fp "CBFlow EMIR Power Analysis Summary - Voltus"
    puts $fp "================================================================"
    puts $fp "Generated: [expr {[catch {clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}} _ts] ? "epoch [clock seconds]" : $_ts}]"
    puts $fp "Tool: Cadence Voltus"
    puts $fp "Design: $flow(design_name)"
    puts $fp ""
    puts $fp "Configuration:"
    if {[info exists emir(power,analysis_mode)]}    { puts $fp "  Analysis mode:    $emir(power,analysis_mode)" }
    if {[info exists emir(power,supply_voltage)]}   { puts $fp "  Supply voltage:   $emir(power,supply_voltage)V" }
    if {[info exists emir(power,analysis_view)]}    { puts $fp "  Analysis view:    $emir(power,analysis_view)" }
    puts $fp ""
    puts $fp "Reports Generated:"
    puts $fp "  Power summary:     power/power_summary.rpt"
    puts $fp "  Hierarchy:         power/power_hierarchy.rpt"
    puts $fp "  Leakage:           power/power_leakage.rpt"
    puts $fp "  Internal:          power/power_internal.rpt"
    puts $fp "  Switching:         power/power_switching.rpt"
    puts $fp "  Per-instance:      power/power_per_instance.rpt"
    puts $fp "  PG check:          power/pg_check.rpt"
    puts $fp "  IR drop (quick):   power/ir_drop_quick.rpt"
    puts $fp "  Final:             power/power_final.rpt"
    close $fp

    handle_info "  Summary: $summary_file"
    handle_info "Power reporting completed"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                           EXECUTION CONTROL                                │
# └─────────────────────────────────────────────────────────────────────────────┘

handle_info "================================================================"
handle_info " CBFlow EMIR power_analysis with Voltus"
handle_info "================================================================"

flow_proc power_analysis_flow {
    handle_info "Executing EMIR power_analysis flow..."
    flow_exec setup_power_analysis
    flow_exec run_power_analysis
    flow_exec setup_pg_analysis
    flow_exec run_pg_analysis
    flow_exec generate_reports
    handle_info "EMIR power_analysis completed successfully"
}

if {[info exists argv0] && $argv0 eq [info script]} { flow_exec power_analysis_flow } else { puts " EMIR power_analysis procedures loaded" }

# Exit tool after stage completion
exit
