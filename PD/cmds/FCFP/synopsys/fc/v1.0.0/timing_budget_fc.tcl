#!/usr/bin/env tclsh
# CBFlow FCFP timing_budget - Synopsys Fusion Compiler
# FC-RM: timing_budget.tcl -- Abstract timing estimation,
#         budget creation, and distribution to sub-blocks
# Aligned with FC-RM Y-2026.03
set run_dir $::env(CBFLOW_RUN_DIR)
set env_file "$run_dir/.run.cbflow.tcl"
if {[file exists $env_file]} { source $env_file } else { puts stderr "ERROR: .run.cbflow.tcl not found"; exit 1 }
if {[info exists ::env(FLOW_DIR)]} { set FLOW_DIR $::env(FLOW_DIR) } else { puts stderr "ERROR: FLOW_DIR not set"; exit 1 }
if {![info exists ::env(UTILITIES_VERSION)] || $::env(UTILITIES_VERSION) eq ""} { puts stderr "ERROR: UTILITIES_VERSION not set"; exit 1 }
set utils_path "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} { source $utils_path } else { puts stderr "ERROR: Utils not found"; exit 1 }
namespace import ::CBFlow::Utilities::print_header
set config_file "$run_dir/work/FCFP/timing_budget/run/config.tcl"
if {[file exists $config_file]} { source $config_file }
global fcfp project tech flow
# Source FC tool config
set _tool_config "[file dirname [info script]]/fc_config.tcl"
if {[file exists $_tool_config]} { source $_tool_config }
handle_info "Starting FCFP timing_budget..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

# Source tech_config
if {[info exists ::env(TECH_NAME)] && $::env(TECH_NAME) ne "" &&
    [info exists ::env(TECH_VERSION)] && $::env(TECH_VERSION) ne ""} {
    set _tc "$::env(CONFIG_ROOT)/tech/$::env(TECH_NAME)/$::env(TECH_VERSION)/tech_config.tcl"
    if {[file exists $_tc]} { source -e $_tc }
}
# Source user_config for overrides
if {[file exists "$run_dir/setup/user_config.tcl"]} { source -e "$run_dir/setup/user_config.tcl" }

set WORK_DIR "$run_dir/work/FCFP/timing_budget1"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

# ==============================================================================
# flow_proc: load_design
# ==============================================================================
flow_proc load_design {
    handle_info "Loading design for timing_budget..."
    global fcfp flow

    set design_name [expr {[info exists fc(common,design_name)] ? $fc(common,design_name) : $flow(design_name)}]

    if {[info exists fc(common,open_lib)] && $fc(common,open_lib) ne ""} {
        open_lib $fc(common,open_lib)
    }

    set from_label [expr {[info exists fc(timing_budget,from_label)] ? $fc(timing_budget,from_label) : "top_compile"}]
    copy_block -from ${design_name}/${from_label} -to ${design_name}/timing_budget
    current_block ${design_name}/timing_budget
    link_block

    handle_info "Design loaded: $design_name"
}

# ==============================================================================
# flow_proc: estimate_timing
# FC-RM: create_abstract -estimate_timing, estimate_timing
# ==============================================================================
flow_proc estimate_timing {
    handle_info "Estimating timing for budget creation..."
    global fcfp

    # Create abstracts with timing estimation
    create_abstract -estimate_timing
    handle_info "Abstracts created with timing estimation"

    # Run timing estimation
    estimate_timing

    # Pre-budget timing reports
    set max_paths [expr {[info exists fc(analysis,max_paths)] ? $fc(analysis,max_paths) : 100}]
    redirect -file $::REPORTS_DIR/report_timing.pre_budget.rpt {
        report_timing -max_paths $max_paths -delay_type max
    }
    redirect -file $::REPORTS_DIR/report_qor.pre_budget.rpt { report_qor }

    handle_info "Timing estimation completed"
}

# ==============================================================================
# flow_proc: create_budgets
# FC-RM: budget_timing
# ==============================================================================
flow_proc create_budgets {
    handle_info "Creating timing budgets..."
    global fcfp

    set budget_cmd "budget_timing"

    # Budget mode: default, aggressive, or conservative
    if {[info exists fc(timing_budget,mode)] && $fc(timing_budget,mode) ne ""} {
        lappend budget_cmd -mode $fc(timing_budget,mode)
    }

    # Scenarios for budgeting
    if {[info exists fc(timing_budget,active_scenarios)] && $fc(timing_budget,active_scenarios) ne ""} {
        set_scenario_status -active false [get_scenarios -filter active]
        set_scenario_status -active true $fc(timing_budget,active_scenarios)
    }

    # Source user budget constraints before budget_timing
    if {[info exists fc(timing_budget,constraint_script)] && [file exists $fc(timing_budget,constraint_script)]} {
        source -e $fc(timing_budget,constraint_script)
    }

    handle_info "Running: $budget_cmd"
    eval $budget_cmd

    handle_info "Timing budgets created"
}

# ==============================================================================
# flow_proc: distribute_budgets
# FC-RM: Write budgeted SDC for each sub-block
# ==============================================================================
flow_proc distribute_budgets {
    handle_info "Distributing budgets to sub-blocks..."
    global fcfp

    set run_dir $::env(CBFLOW_RUN_DIR)
    set budget_dir "$run_dir/results/fcfp/timing_budgets"
    file mkdir $budget_dir

    if {[info exists fc(common,sub_blocks)] && [llength $fc(common,sub_blocks)] > 0} {
        foreach block $fc(common,sub_blocks) {
            file mkdir "$budget_dir/$block"
            catch {
                write_sdc -block $block "$budget_dir/$block/${block}_budgeted.sdc"
                handle_info "Budgeted SDC written: $block"
            }
        }
    }

    # Write top-level budgeted SDC
    catch {
        write_sdc "$budget_dir/top_budgeted.sdc"
        handle_info "Top-level budgeted SDC written"
    }

    handle_info "Budget distribution completed"
}

# ==============================================================================
# flow_proc: save_design
# ==============================================================================
flow_proc save_design {
    handle_info "Saving timing_budget block..."
    global fcfp flow

    set design_name [expr {[info exists fc(common,design_name)] ? $fc(common,design_name) : $flow(design_name)}]

    save_lib -all
    save_block
    save_block -as ${design_name}/timing_budget
    handle_info "Block saved: ${design_name}/timing_budget"
}

# ==============================================================================
# flow_proc: generate_reports
# ==============================================================================
flow_proc generate_reports {
    handle_info "Generating timing_budget reports..."
    global fcfp

    set max_paths [expr {[info exists fc(analysis,max_paths)] ? $fc(analysis,max_paths) : 100}]

    redirect -file $::REPORTS_DIR/report_qor.rpt { report_qor }
    redirect -file $::REPORTS_DIR/report_timing.rpt {
        report_timing -max_paths $max_paths -delay_type max
    }
    redirect -file $::REPORTS_DIR/report_timing.min.rpt {
        report_timing -max_paths $max_paths -delay_type min
    }
    redirect -file $::REPORTS_DIR/report_constraint.rpt {
        report_constraint -all_violators
    }
    redirect -file $::REPORTS_DIR/report_design.rpt { report_design -physical }
    redirect -file $::REPORTS_DIR/report_msg_summary.rpt { report_msg -summary }

    handle_info "Timing_budget reports generated in: $::REPORTS_DIR"
}

# ==============================================================================
# Source setup.tcl and overrides before flow_exec_all
# ==============================================================================
set _setup_file "$run_dir/work/FCFP/timing_budget/run/setup.tcl"
if {[file exists $_setup_file]} { handle_info "Sourcing setup hooks: $_setup_file"; source $_setup_file }
set _override_file "$run_dir/setup/override_setup.tcl"
if {[file exists $_override_file]} { handle_info "Sourcing user override: $_override_file"; source $_override_file }
set _stage_override "$run_dir/setup/override_setup.timing_budget.tcl"
if {[file exists $_stage_override]} { handle_info "Sourcing stage override: $_stage_override"; source $_stage_override }

flow_exec_all

# Exit tool after stage completion
exit
