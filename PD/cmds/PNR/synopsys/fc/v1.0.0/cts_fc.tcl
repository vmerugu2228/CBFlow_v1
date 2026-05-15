#!/usr/bin/env tclsh
# CBFlow PNR cts1 - Synopsys Fusion Compiler | PNR cts1
set run_dir $::env(CBFLOW_RUN_DIR)
set env_file "$run_dir/.run.cbflow.tcl"
if {[file exists $env_file]} { source $env_file } else { puts stderr "ERROR: .run.cbflow.tcl not found"; exit 1 }
if {[info exists ::env(FLOW_DIR)]} { set FLOW_DIR $::env(FLOW_DIR) } else { puts stderr "ERROR: FLOW_DIR not set"; exit 1 }
if {![info exists ::env(UTILITIES_VERSION)] || $::env(UTILITIES_VERSION) eq ""} { puts stderr "ERROR: UTILITIES_VERSION not set"; exit 1 }
set utils_path "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} { source $utils_path } else { puts stderr "ERROR: Utils not found"; exit 1 }
namespace import ::CBFlow::Utilities::print_header
set config_file "$run_dir/work/PNR/cts1/run/config.tcl"
if {[file exists $config_file]} { source $config_file }
global pnr project tech flow
# Source FC tool config
set _tool_config "[file dirname [info script]]/fc_config.tcl"
if {[file exists $_tool_config]} { source $_tool_config }
handle_info "Starting PNR cts1 with Synopsys Fusion Compiler..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

# -- Directories ---------------------------------------------------------------
set WORK_DIR "$run_dir/work/PNR/cts1"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

# Source tech_config
if {[info exists ::env(TECH_NAME)] && $::env(TECH_NAME) ne "" &&
    [info exists ::env(TECH_VERSION)] && $::env(TECH_VERSION) ne ""} {
    set _tc "$::env(CONFIG_ROOT)/tech/$::env(TECH_NAME)/$::env(TECH_VERSION)/tech_config.tcl"
    if {[file exists $_tc]} { source -e $_tc }
}
# Source user_config for overrides
if {[file exists "$run_dir/setup/user_config.tcl"]} { source -e "$run_dir/setup/user_config.tcl" }

# Source MMMC configuration
set mmmc_config_file "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/mmmc_config.tcl"
if {[file exists $mmmc_config_file]} { source -e $mmmc_config_file }

# ==============================================================================
# flow_proc: configure_cts
# Description: Configure CTS options, NDR rules, and clock constraints
# ==============================================================================
flow_proc configure_cts {
    handle_info "Configuring CTS options..."
    global pnr tech

    # Set QoR strategy for CTS stage
    if {[info exists fc(compile,qor_version)] && $fc(compile,qor_version) ne ""} {
        set_app_options -name flow.set_qor_strategy.version -value $fc(compile,qor_version)
    }
    set set_qor_strategy_cmd "set_qor_strategy -stage cts"
    if {[info exists fc(compile,qor_metric)] && $fc(compile,qor_metric) ne ""} {
        lappend set_qor_strategy_cmd -metric $fc(compile,qor_metric)
    }
    if {[info exists fc(compile,qor_mode)] && $fc(compile,qor_mode) ne ""} {
        lappend set_qor_strategy_cmd -mode $fc(compile,qor_mode)
    }
    if {[info exists fc(compile,reduced_effort)] && $fc(compile,reduced_effort)} {
        lappend set_qor_strategy_cmd -reduced_effort
    }
    handle_info "Running: $set_qor_strategy_cmd"
    eval $set_qor_strategy_cmd

    # Set instance name prefixes
    set_app_options -name cts.common.user_instance_name_prefix -value clock_opt_cts_
    set_app_options -name opt.common.user_instance_name_prefix -value clock_opt_cts_opt_

    # Set active scenarios for CTS step
    if {[info exists fc(cts,active_scenarios)] && $fc(cts,active_scenarios) ne ""} {
        set_scenario_status -active false [get_scenarios -filter active]
        set_scenario_status -active true $fc(cts,active_scenarios)
    }

    # Lib cell purpose for CTS
    if {[info exists fc(cts,ref_cells)] && $fc(cts,ref_cells) ne ""} {
        set_lib_cell_purpose -include cts $fc(cts,ref_cells)
        handle_info "CTS reference cells: $fc(cts,ref_cells)"
    }
    if {[info exists fc(cts,exclude_cells)] && $fc(cts,exclude_cells) ne ""} {
        set_lib_cell_purpose -exclude cts $fc(cts,exclude_cells)
    }

    # Configure NDR (non-default routing) rules for clock nets and mark trees
    if {[info exists fc(cts,ndr_rule)] && $fc(cts,ndr_rule) ne ""} {
        handle_info "Applying clock NDR rule: $fc(cts,ndr_rule)"
        mark_clock_trees -routing_rules
    }

    # Antenna rules
    if {[info exists tech(antenna_rule_file)] && [file exists $tech(antenna_rule_file)]} {
        handle_info "Reading antenna rules: $tech(antenna_rule_file)"
        source -e $tech(antenna_rule_file)
    }

    # CTS primary corner override
    if {[info exists fc(cts,primary_corner)] && $fc(cts,primary_corner) ne ""} {
        handle_info "Setting cts.compile.primary_corner to $fc(cts,primary_corner)"
        set_app_options -name cts.compile.primary_corner -value $fc(cts,primary_corner)
    }

    handle_info "CTS configuration completed"
}

# ==============================================================================
# flow_proc: build_clock_trees
# Description: Build clock trees via clock_opt build_clock phase
# ==============================================================================
flow_proc build_clock_trees {
    handle_info "Building clock trees..."
    global pnr

    # Check and apply relaxed clock transition for better CTS convergence
    handle_info "Running check_clock_transition -threshold 0.15 -apply_max_transition"
    check_clock_transition -threshold 0.15 -apply_max_transition

    # Build clock tree
    handle_info "Running clock_opt -from build_clock -to build_clock"
    clock_opt -from build_clock -to build_clock

    # Save intermediate state
    if {[info exists fc(output,block_labeling)] && $fc(output,block_labeling)} {
        save_block -as $fc(common,design_name)/clock_opt_cts_build_clock
    }

    # Restore original clock transition constraint
    restore_clock_transition

    handle_info "Clock tree build completed"
}

# ==============================================================================
# flow_proc: route_clock_nets
# Description: Route clock nets via clock_opt route_clock phase
# ==============================================================================
flow_proc route_clock_nets {
    handle_info "Routing clock nets..."

    handle_info "Running clock_opt -from route_clock -to route_clock"
    clock_opt -from route_clock -to route_clock

    # Redundant via insertion on clock nets if enabled
    if {[info exists ::pnr(cts,redundant_via)] && $::pnr(cts,redundant_via)} {
        handle_info "Running add_redundant_vias for CTS"
        add_redundant_vias
    }

    # Enable AOCV analysis after CTS if configured
    if {[info exists ::pnr(cts,enable_aocv)] && $::pnr(cts,enable_aocv)} {
        set_app_options -name time.aocvm_enable_analysis -value true
        handle_info "AOCV analysis enabled"
    }

    # Create shields if enabled
    if {[info exists ::pnr(cts,enable_shields)] && $::pnr(cts,enable_shields)} {
        handle_info "Creating clock shields..."
        set create_shields_cmd "create_shields"
        if {[info exists ::pnr(cts,shields_ground_net)] && $::pnr(cts,shields_ground_net) ne ""} {
            lappend create_shields_cmd -with_ground $::pnr(cts,shields_ground_net)
        }
        eval $create_shields_cmd
    }

    handle_info "Clock net routing completed"
}

# ==============================================================================
# flow_proc: propagate_clocks
# Description: Propagate clocks to inactive scenarios and connect PG nets
# ==============================================================================
flow_proc propagate_clocks {
    handle_info "Propagating clocks and connecting PG nets..."

    # Connect PG nets
    connect_pg_net

    # Run check_routes to save updated routing DRC to the block
    redirect -file $::REPORTS_DIR/check_routes.rpt {
        check_routes -open_net false
    }

    handle_info "Clock propagation and PG connection completed"
}

# ==============================================================================
# flow_proc: save_design_block
# Description: Save the design block after CTS
# ==============================================================================
flow_proc save_design_block {
    handle_info "Saving design block..."
    global pnr

    if {[info exists fc(output,block_labeling)] && $fc(output,block_labeling)} {
        save_block -as $fc(common,design_name)/cts
        handle_info "Block saved as $fc(common,design_name)/cts"
    } else {
        save_block
        handle_info "Block saved"
    }
}

# ==============================================================================
# flow_proc: generate_reports
# Description: Generate comprehensive CTS reports
# ==============================================================================
flow_proc generate_reports {
    handle_info "Generating CTS reports..."
    global pnr

    set run_dir $::env(CBFLOW_RUN_DIR)
    set max_paths [expr {[info exists fc(analysis,max_paths)] ? $fc(analysis,max_paths) : 100}]

    # FC-RM: Timing reports
    redirect -file $::REPORTS_DIR/report_timing.max.rpt {
        report_timing -max_paths $max_paths -delay_type max -nosplit
    }
    redirect -file $::REPORTS_DIR/report_timing.min.rpt {
        report_timing -max_paths $max_paths -delay_type min -nosplit
    }

    # FC-RM: QoR reports
    redirect -file $::REPORTS_DIR/report_qor.rpt { report_qor -nosplit }
    redirect -file $::REPORTS_DIR/report_qor_summary.rpt { report_qor -summary -nosplit }

    # FC-RM: Clock-specific reports
    redirect -file $::REPORTS_DIR/report_clock_qor.rpt { report_clock_qor }
    redirect -file $::REPORTS_DIR/report_clock_timing.setup.rpt {
        report_clock_timing -type summary -scenarios [all_scenarios]
    }
    redirect -file $::REPORTS_DIR/report_clock_timing.skew.rpt {
        report_clock_timing -type skew -scenarios [all_scenarios]
    }

    # FC-RM: Design and congestion
    redirect -file $::REPORTS_DIR/report_design.rpt { report_design -summary }
    redirect -file $::REPORTS_DIR/report_utilization.rpt { report_utilization }

    # FC-RM: Power
    redirect -file $::REPORTS_DIR/report_power.rpt { report_power }

    # FC-RM: Threshold voltage group
    redirect -file $::REPORTS_DIR/report_threshold_voltage_group.rpt { report_threshold_voltage_group }

    # FC-RM: Congestion after CTS
    redirect -file $::REPORTS_DIR/report_congestion.rpt { report_congestion }

    # FC-RM: App options end state
    redirect -file $::REPORTS_DIR/report_app_options.end.rpt { report_app_options -non_default * }

    # FC-RM: write_qor_data
    catch {
        write_qor_data -report_list "performance host_machine report_app_options" \
            -label clock_opt_cts -output $run_dir/qor_data
    }

    # FC-RM: report_msg summary
    redirect -file $::REPORTS_DIR/report_msg_summary.rpt { report_msg -summary }

    handle_info "CTS reports generated in: $::REPORTS_DIR"
}

# ==============================================================================
# Source setup.tcl (flow_proc hooks: prepend, append, replace)
# Must be sourced AFTER flow_proc definitions but BEFORE flow_exec_all
# ==============================================================================
set _setup_file "$run_dir/work/PNR/cts1/run/setup.tcl"
if {[file exists $_setup_file]} {
    handle_info "Sourcing setup hooks: $_setup_file"
    source -e $_setup_file
}
set _override_file "$run_dir/setup/override_setup.tcl"
if {[file exists $_override_file]} {
    handle_info "Sourcing user override: $_override_file"
    source -e $_override_file
}
set _stage_override "$run_dir/setup/override_setup.cts.tcl"
if {[file exists $_stage_override]} {
    handle_info "Sourcing stage override: $_stage_override"
    source -e $_stage_override
}

# ==============================================================================
# Execute all flow_procs in sequence
# ==============================================================================
flow_exec_all

# Exit tool after stage completion
exit
