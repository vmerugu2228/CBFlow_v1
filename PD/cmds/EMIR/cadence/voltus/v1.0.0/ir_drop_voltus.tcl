#!/usr/bin/env tclsh
# EMIR IR Drop Analysis - Cadence Voltus

# -- Bootstrap -----------------------------------------------------------------
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "EMIR"
set STAGE_NAME "ir_drop"
set NODE_NAME "ir_drop1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

handle_info "Starting EMIR ir_drop stage with Voltus..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

set WORK_DIR "$run_dir/work/EMIR/ir_drop1"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                     SETUP IR ANALYSIS                                      │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc setup_ir_analysis {
    global emir
    handle_info "Configuring IR drop analysis settings..."

    file mkdir "$::REPORTS_DIR/ir_drop"
    file mkdir "$::OUTPUTS_DIR/emir/ir_drop"

    # Static PG analysis mode with voltage-from-pg-pin
    handle_info "  set_pg_analysis_mode -power_grid_analysis static"
    set_pg_analysis_mode -power_grid_analysis static

    handle_info "  set_pg_analysis_mode -voltage_from_pg_pin true"
    set_pg_analysis_mode -voltage_from_pg_pin true

    # Enable EM analysis alongside IR drop (unless explicitly skipped)
    if {![info exists emir(em,skip)] || $emir(em,skip) ne "true"} {
        handle_info "  set_pg_analysis_mode -enable_em_analysis true"
        set_pg_analysis_mode -power_grid_analysis static \
            -enable_em_analysis true
    }

    # Set EM temperature if configured
    if {[info exists emir(voltus,junction_temp)] && $emir(voltus,junction_temp) ne ""} {
        handle_info "  set_db em_temperature $emir(voltus,junction_temp)"
        set_db em_temperature $emir(voltus,junction_temp)
    }

    # Set EM target lifetime if configured
    if {[info exists emir(em,target_lifetime)] && $emir(em,target_lifetime) ne ""} {
        handle_info "  set_db em_target_lifetime $emir(em,target_lifetime)"
        set_db em_target_lifetime $emir(em,target_lifetime)
    }

    handle_info "IR drop configuration completed"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                     RUN STATIC IR                                          │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc run_static_ir {
    global emir
    handle_info "Running static IR drop analysis..."

    # Get power/ground net names
    set vdd_net [expr {[info exists emir(power,vdd_net)] && $emir(power,vdd_net) ne "" ? $emir(power,vdd_net) : "VDD"}]
    set vss_net [expr {[info exists emir(power,vss_net)] && $emir(power,vss_net) ne "" ? $emir(power,vss_net) : "VSS"}]

    # Run static power grid analysis on VDD
    handle_info "  analyze_power_grid -net $vdd_net"
    analyze_power_grid -net $vdd_net

    # Run static power grid analysis on VSS
    handle_info "  analyze_power_grid -net $vss_net"
    analyze_power_grid -net $vss_net

    # Report IR drop for VDD
    set vdd_ir_rpt "$::REPORTS_DIR/ir_drop/ir_drop_vdd.rpt"
    handle_info "  report_power_rail -net $vdd_net -type ir_drop"
    report_power_rail -net $vdd_net -type ir_drop \
        -output_file $vdd_ir_rpt

    # Report IR drop for VSS
    set vss_ir_rpt "$::REPORTS_DIR/ir_drop/ir_drop_vss.rpt"
    handle_info "  report_power_rail -net $vss_net -type ir_drop"
    report_power_rail -net $vss_net -type ir_drop \
        -output_file $vss_ir_rpt

    # Worst-case IR drop instances
    set worst_rpt "$::REPORTS_DIR/ir_drop/worst_ir_instances.rpt"
    set max_inst 100
    if {[info exists emir(ir_drop,max_violations)] && $emir(ir_drop,max_violations) ne ""} {
        set max_inst $emir(ir_drop,max_violations)
    }
    handle_info "  report_power_rail -net $vdd_net -type ir_drop -worst_instances $max_inst"
    report_power_rail -net $vdd_net -type ir_drop \
        -worst_instances $max_inst \
        -output_file $worst_rpt

    # IR drop with threshold filtering
    if {[info exists emir(ir_drop,threshold)] && $emir(ir_drop,threshold) ne ""} {
        set thresh_rpt "$::REPORTS_DIR/ir_drop/ir_drop_threshold.rpt"
        handle_info "  report_power_rail -net $vdd_net -type ir_drop -threshold $emir(ir_drop,threshold)"
        report_power_rail -net $vdd_net -type ir_drop \
            -threshold $emir(ir_drop,threshold) \
            -output_file $thresh_rpt
    }

    # Per-instance IR drop report
    set inst_rpt "$::REPORTS_DIR/ir_drop/ir_drop_by_instance.rpt"
    handle_info "  report_power_rail -net $vdd_net -type ir_drop -inst_report"
    report_power_rail -net $vdd_net -type ir_drop \
        -inst_report \
        -output_file $inst_rpt

    # Voltage report
    set voltage_rpt "$::REPORTS_DIR/ir_drop/voltage_vdd.rpt"
    handle_info "  report_power_rail -net $vdd_net -type voltage"
    report_power_rail -net $vdd_net -type voltage \
        -output_file $voltage_rpt

    # Current density report
    set jdensity_rpt "$::REPORTS_DIR/ir_drop/current_density_vdd.rpt"
    handle_info "  report_power_rail -net $vdd_net -type current_density"
    report_power_rail -net $vdd_net -type current_density \
        -output_file $jdensity_rpt

    handle_info "Static IR drop analysis completed"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                     RUN DYNAMIC IR                                         │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc run_dynamic_ir {
    global emir
    handle_info "Checking dynamic IR drop configuration..."

    # Only run if explicitly enabled
    if {![info exists emir(ir_drop,run_dynamic)] || $emir(ir_drop,run_dynamic) ne "true"} {
        handle_info "  Dynamic IR analysis not enabled -- skipping"
        return
    }

    set vdd_net [expr {[info exists emir(power,vdd_net)] && $emir(power,vdd_net) ne "" ? $emir(power,vdd_net) : "VDD"}]

    # Need activity file for dynamic analysis
    if {[info exists emir(input,power_activity_file)] && $emir(input,power_activity_file) ne "" && [file exists $emir(input,power_activity_file)]} {
        set ext [string tolower [file extension $emir(input,power_activity_file)]]
        set fmt "VCD"
        if {$ext eq ".fsdb"} { set fmt "FSDB" }

        # Read activity with optional scope and time window
        set read_cmd "read_activity_file -format $fmt"
        if {[info exists emir(power,activity_scope)] && $emir(power,activity_scope) ne ""} {
            append read_cmd " -scope $emir(power,activity_scope)"
        }
        if {[info exists emir(power,activity_start_time)] && $emir(power,activity_start_time) ne ""} {
            append read_cmd " -start_time $emir(power,activity_start_time)"
        }
        if {[info exists emir(power,activity_end_time)] && $emir(power,activity_end_time) ne ""} {
            append read_cmd " -end_time $emir(power,activity_end_time)"
        }
        append read_cmd " $emir(input,power_activity_file)"
        handle_info "  $read_cmd"
        eval $read_cmd
    } else {
        handle_warning "Dynamic IR requires VCD/FSDB activity file -- skipping"
        return
    }

    # Switch to dynamic power analysis mode
    handle_info "  set_power_analysis_mode -method dynamic"
    set_power_analysis_mode -method dynamic
    if {[info exists emir(power,analysis_view)] && $emir(power,analysis_view) ne ""} {
        set_power_analysis_mode -method dynamic -analysis_view $emir(power,analysis_view)
    }

    # Configure dynamic simulation parameters
    if {[info exists emir(ir_drop,dynamic_resolution)] && $emir(ir_drop,dynamic_resolution) ne ""} {
        handle_info "  set_dynamic_power_simulation -resolution $emir(ir_drop,dynamic_resolution)"
        set_dynamic_power_simulation -resolution $emir(ir_drop,dynamic_resolution)
    }

    # Switch PG analysis to dynamic mode
    handle_info "  set_pg_analysis_mode -power_grid_analysis dynamic"
    set_pg_analysis_mode -power_grid_analysis dynamic

    # Run dynamic analysis
    handle_info "  analyze_power_grid -net $vdd_net"
    analyze_power_grid -net $vdd_net

    # Report dynamic IR drop
    set dyn_rpt "$::REPORTS_DIR/ir_drop/dynamic_ir_drop_vdd.rpt"
    handle_info "  report_power_rail -net $vdd_net -type ir_drop -time_based"
    report_power_rail -net $vdd_net -type ir_drop \
        -time_based > $dyn_rpt

    # Peak dynamic IR
    set peak_rpt "$::REPORTS_DIR/ir_drop/dynamic_ir_peak_vdd.rpt"
    handle_info "  report_power_rail -net $vdd_net -type ir_drop -peak"
    report_power_rail -net $vdd_net -type ir_drop \
        -peak > $peak_rpt

    handle_info "Dynamic IR drop analysis completed"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                     RUN EM ANALYSIS                                        │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc run_em_analysis {
    global emir
    handle_info "Running electromigration analysis..."

    # Skip if EM disabled
    if {[info exists emir(em,skip)] && $emir(em,skip) eq "true"} {
        handle_info "  EM analysis skipped by config"
        return
    }

    file mkdir "$::REPORTS_DIR/em"

    # EM violations summary
    set em_rpt "$::REPORTS_DIR/em/em_violations.rpt"
    handle_info "  report_em_violation -output_file $em_rpt"
    report_em_violation -output_file $em_rpt

    # Detailed EM violations
    set em_detail_rpt "$::REPORTS_DIR/em/em_detail.rpt"
    handle_info "  report_em_violation -detail -output_file $em_detail_rpt"
    report_em_violation -detail -output_file $em_detail_rpt

    # EM violations on power nets
    set em_power_rpt "$::REPORTS_DIR/em/em_power_nets.rpt"
    handle_info "  report_em_violation -net_type power -output_file $em_power_rpt"
    report_em_violation -net_type power -output_file $em_power_rpt

    # EM violations on signal nets
    set em_signal_rpt "$::REPORTS_DIR/em/em_signal_nets.rpt"
    handle_info "  report_em_violation -net_type signal -output_file $em_signal_rpt"
    report_em_violation -net_type signal -output_file $em_signal_rpt

    # EM with threshold filtering
    if {[info exists emir(em,threshold)] && $emir(em,threshold) ne ""} {
        set em_thresh_rpt "$::REPORTS_DIR/em/em_threshold.rpt"
        handle_info "  report_em_violation -threshold $emir(em,threshold) -output_file $em_thresh_rpt"
        report_em_violation -threshold $emir(em,threshold) \
            -output_file $em_thresh_rpt
    }

    # EM summary
    set em_summary_rpt "$::REPORTS_DIR/em/em_summary.rpt"
    handle_info "  report_em_violation -summary -output_file $em_summary_rpt"
    report_em_violation -summary -output_file $em_summary_rpt

    handle_info "EM analysis completed"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                     CHECK THRESHOLDS                                       │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc check_thresholds {
    global emir
    handle_info "Checking IR drop and EM thresholds..."

    set vdd_net [expr {[info exists emir(power,vdd_net)] && $emir(power,vdd_net) ne "" ? $emir(power,vdd_net) : "VDD"}]
    set vss_net [expr {[info exists emir(power,vss_net)] && $emir(power,vss_net) ne "" ? $emir(power,vss_net) : "VSS"}]

    # Power grid integrity check
    set pg_rpt "$::REPORTS_DIR/ir_drop/pg_integrity.rpt"
    handle_info "  check_power_grid -net {$vdd_net $vss_net} -output_file $pg_rpt"
    check_power_grid -net [list $vdd_net $vss_net] -output_file $pg_rpt

    # PG summary
    set pg_summary "$::REPORTS_DIR/ir_drop/pg_summary.rpt"
    handle_info "  report_pg_summary > $pg_summary"
    report_pg_summary > $pg_summary

    handle_info "Threshold check completed"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                     GENERATE MAPS                                          │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc generate_maps {
    global emir
    handle_info "Generating power grid visualization maps..."

    set vdd_net [expr {[info exists emir(power,vdd_net)] && $emir(power,vdd_net) ne "" ? $emir(power,vdd_net) : "VDD"}]

    file mkdir "$::OUTPUTS_DIR/emir/ir_drop/maps"

    # IR drop map
    handle_info "  generate_pg_map -net $vdd_net -type ir_drop"
    generate_pg_map -net $vdd_net -type ir_drop

    # Current density map
    handle_info "  generate_pg_map -net $vdd_net -type current_density"
    generate_pg_map -net $vdd_net -type current_density

    # EM violation map (if EM enabled)
    if {![info exists emir(em,skip)] || $emir(em,skip) ne "true"} {
        handle_info "  generate_pg_map -net $vdd_net -type em_violation"
        generate_pg_map -net $vdd_net -type em_violation
    }

    # Voltage distribution map
    handle_info "  generate_pg_map -net $vdd_net -type voltage"
    generate_pg_map -net $vdd_net -type voltage

    handle_info "Maps generated"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                     GENERATE REPORT                                        │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc generate_report {
    global emir flow
    handle_info "Generating IR drop analysis summary..."

    set summary_file "$::REPORTS_DIR/ir_drop/ir_drop_summary.rpt"
    file mkdir [file dirname $summary_file]
    set fp [open $summary_file w]
    puts $fp "================================================================"
    puts $fp "CBFlow EMIR IR Drop Analysis Summary - Voltus"
    puts $fp "================================================================"
    puts $fp "Generated: [expr {[catch {clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}} _ts] ? "epoch [clock seconds]" : $_ts}]"
    puts $fp "Tool: Cadence Voltus"
    puts $fp "Design: $flow(design_name)"
    puts $fp ""
    puts $fp "Configuration:"
    if {[info exists emir(ir_drop,threshold)] && $emir(ir_drop,threshold) ne ""} {
        puts $fp "  IR drop threshold:  $emir(ir_drop,threshold)V"
    }
    if {[info exists emir(em,threshold)] && $emir(em,threshold) ne ""} {
        puts $fp "  EM threshold:       $emir(em,threshold)"
    }
    if {[info exists emir(power,vdd_net)] && $emir(power,vdd_net) ne ""} {
        puts $fp "  VDD net:            $emir(power,vdd_net)"
    }
    if {[info exists emir(power,vss_net)] && $emir(power,vss_net) ne ""} {
        puts $fp "  VSS net:            $emir(power,vss_net)"
    }
    puts $fp ""
    puts $fp "Static IR Reports:"
    puts $fp "  VDD IR drop:        ir_drop/ir_drop_vdd.rpt"
    puts $fp "  VSS IR drop:        ir_drop/ir_drop_vss.rpt"
    puts $fp "  Worst instances:    ir_drop/worst_ir_instances.rpt"
    puts $fp "  By instance:        ir_drop/ir_drop_by_instance.rpt"
    puts $fp "  Voltage:            ir_drop/voltage_vdd.rpt"
    puts $fp "  Current density:    ir_drop/current_density_vdd.rpt"
    puts $fp "  PG integrity:       ir_drop/pg_integrity.rpt"
    if {[info exists emir(ir_drop,run_dynamic)] && $emir(ir_drop,run_dynamic) eq "true"} {
        puts $fp ""
        puts $fp "Dynamic IR Reports:"
        puts $fp "  Time-based IR:      ir_drop/dynamic_ir_drop_vdd.rpt"
        puts $fp "  Peak IR:            ir_drop/dynamic_ir_peak_vdd.rpt"
    }
    if {![info exists emir(em,skip)] || $emir(em,skip) ne "true"} {
        puts $fp ""
        puts $fp "EM Reports:"
        puts $fp "  Violations:         em/em_violations.rpt"
        puts $fp "  Detail:             em/em_detail.rpt"
        puts $fp "  Power nets:         em/em_power_nets.rpt"
        puts $fp "  Signal nets:        em/em_signal_nets.rpt"
        puts $fp "  Summary:            em/em_summary.rpt"
    }
    close $fp

    handle_info "  Summary: $summary_file"
    handle_info "IR drop reporting completed"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                           EXECUTION CONTROL                                │
# └─────────────────────────────────────────────────────────────────────────────┘

handle_info "================================================================"
handle_info " CBFlow EMIR ir_drop with Voltus"
handle_info "================================================================"

flow_proc ir_drop_flow {
    handle_info "Executing EMIR ir_drop flow..."
    flow_exec setup_ir_analysis
    flow_exec run_static_ir
    flow_exec run_dynamic_ir
    flow_exec run_em_analysis
    flow_exec check_thresholds
    flow_exec generate_maps
    flow_exec generate_report
    handle_info "EMIR ir_drop completed successfully"
}

if {[info exists argv0] && $argv0 eq [info script]} { flow_exec ir_drop_flow } else { puts " EMIR ir_drop procedures loaded" }

# Exit tool after stage completion
exit
