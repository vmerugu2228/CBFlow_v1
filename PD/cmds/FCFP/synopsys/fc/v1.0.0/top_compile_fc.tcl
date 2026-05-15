#!/usr/bin/env tclsh
# CBFlow FCFP top_compile - Synopsys Fusion Compiler
# FC-RM: top_compile.tcl -- Top-level compile_fusion optimization
#         with abstracts for sub-blocks
# Aligned with FC-RM Y-2026.03
set run_dir $::env(CBFLOW_RUN_DIR)
set env_file "$run_dir/.run.cbflow.tcl"
if {[file exists $env_file]} { source $env_file } else { puts stderr "ERROR: .run.cbflow.tcl not found"; exit 1 }
if {[info exists ::env(FLOW_DIR)]} { set FLOW_DIR $::env(FLOW_DIR) } else { puts stderr "ERROR: FLOW_DIR not set"; exit 1 }
if {![info exists ::env(UTILITIES_VERSION)] || $::env(UTILITIES_VERSION) eq ""} { puts stderr "ERROR: UTILITIES_VERSION not set"; exit 1 }
set utils_path "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} { source $utils_path } else { puts stderr "ERROR: Utils not found"; exit 1 }
namespace import ::CBFlow::Utilities::print_header
set config_file "$run_dir/work/FCFP/top_compile/run/config.tcl"
if {[file exists $config_file]} { source $config_file }
global fcfp project tech flow
# Source FC tool config
set _tool_config "[file dirname [info script]]/fc_config.tcl"
if {[file exists $_tool_config]} { source $_tool_config }
handle_info "Starting FCFP top_compile..."
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

set WORK_DIR "$run_dir/work/FCFP/top_compile1"
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
    handle_info "Loading design for top_compile..."
    global fcfp flow

    set design_name [expr {[info exists fc(common,design_name)] ? $fc(common,design_name) : $flow(design_name)}]

    if {[info exists fc(common,open_lib)] && $fc(common,open_lib) ne ""} {
        open_lib $fc(common,open_lib)
    }

    set from_label [expr {[info exists fc(top_compile,from_label)] ? $fc(top_compile,from_label) : "place_pins"}]
    copy_block -from ${design_name}/${from_label} -to ${design_name}/top_compile
    current_block ${design_name}/top_compile
    link_block

    handle_info "Design loaded: $design_name"
}

# ==============================================================================
# flow_proc: set_qor_strategy
# FC-RM: set_qor_strategy for top-level compile
# ==============================================================================
flow_proc set_qor_strategy {
    handle_info "Setting QoR strategy for top_compile..."
    global fcfp

    set qor_cmd "set_qor_strategy -stage compile_initial"

    if {[info exists fc(top_compile,qor_metric)] && $fc(top_compile,qor_metric) ne ""} {
        lappend qor_cmd -metric $fc(top_compile,qor_metric)
    } elseif {[info exists fc(compile,qor_metric)] && $fc(compile,qor_metric) ne ""} {
        lappend qor_cmd -metric $fc(compile,qor_metric)
    } else {
        lappend qor_cmd -metric timing
    }

    # Active scenarios for top compile
    if {[info exists fc(top_compile,active_scenarios)] && $fc(top_compile,active_scenarios) ne ""} {
        set_scenario_status -active false [get_scenarios -filter active]
        set_scenario_status -active true $fc(top_compile,active_scenarios)
    }

    handle_info "Running: $qor_cmd"
    eval $qor_cmd

    handle_info "Top compile QoR strategy set"
}

# ==============================================================================
# flow_proc: run_compile
# FC-RM: compile_fusion -from logic_opto -to logic_opto (top-level optimization)
# ==============================================================================
flow_proc run_compile {
    handle_info "Running top_compile (compile_fusion top-level)..."
    global fcfp

    set from_stage [expr {[info exists fc(top_compile,from_stage)] ? $fc(top_compile,from_stage) : "logic_opto"}]
    set to_stage [expr {[info exists fc(top_compile,to_stage)] ? $fc(top_compile,to_stage) : "logic_opto"}]

    handle_info "compile_fusion -from $from_stage -to $to_stage"
    compile_fusion -from $from_stage -to $to_stage

    # Change names for downstream compatibility
    change_names -rules verilog -hierarchy -skip_physical_only_cells

    # Reconnect PG
    connect_pg_net

    handle_info "Top compile completed"
}

# ==============================================================================
# flow_proc: save_design
# ==============================================================================
flow_proc save_design {
    handle_info "Saving top_compile block..."
    global fcfp flow

    set design_name [expr {[info exists fc(common,design_name)] ? $fc(common,design_name) : $flow(design_name)}]

    save_lib -all
    save_block
    save_block -as ${design_name}/top_compile
    handle_info "Block saved: ${design_name}/top_compile"
}

# ==============================================================================
# flow_proc: generate_reports
# ==============================================================================
flow_proc generate_reports {
    handle_info "Generating top_compile reports..."
    global fcfp

    set max_paths [expr {[info exists fc(analysis,max_paths)] ? $fc(analysis,max_paths) : 100}]

    redirect -file $::REPORTS_DIR/report_qor.rpt { report_qor }
    redirect -file $::REPORTS_DIR/report_timing.rpt {
        report_timing -max_paths $max_paths -delay_type max
    }
    redirect -file $::REPORTS_DIR/report_timing.min.rpt {
        report_timing -max_paths $max_paths -delay_type min
    }
    redirect -file $::REPORTS_DIR/report_utilization.rpt { report_utilization }
    redirect -file $::REPORTS_DIR/report_design.rpt { report_design -physical }
    redirect -file $::REPORTS_DIR/report_msg_summary.rpt { report_msg -summary }

    handle_info "Top_compile reports generated in: $::REPORTS_DIR"
}

# ==============================================================================
# Source setup.tcl and overrides before flow_exec_all
# ==============================================================================
set _setup_file "$run_dir/work/FCFP/top_compile/run/setup.tcl"
if {[file exists $_setup_file]} { handle_info "Sourcing setup hooks: $_setup_file"; source $_setup_file }
set _override_file "$run_dir/setup/override_setup.tcl"
if {[file exists $_override_file]} { handle_info "Sourcing user override: $_override_file"; source $_override_file }
set _stage_override "$run_dir/setup/override_setup.top_compile.tcl"
if {[file exists $_stage_override]} { handle_info "Sourcing stage override: $_stage_override"; source $_stage_override }

flow_exec_all

# Exit tool after stage completion
exit
