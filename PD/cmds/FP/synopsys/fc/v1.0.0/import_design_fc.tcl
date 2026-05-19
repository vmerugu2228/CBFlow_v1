#!/usr/bin/env tclsh
# CBFlow FP import_design - Synopsys Fusion Compiler
# FC-RM: compile_dp.tcl -- Load design, set QoR strategy, run compile_dp
# Aligned with FC-RM Y-2026.03
set run_dir $::env(CBFLOW_RUN_DIR)
set env_file "$run_dir/.run.cbflow.tcl"
if {[file exists $env_file]} { source $env_file } else { puts stderr "ERROR: .run.cbflow.tcl not found"; exit 1 }
if {[info exists ::env(FLOW_DIR)]} { set FLOW_DIR $::env(FLOW_DIR) } else { puts stderr "ERROR: FLOW_DIR not set"; exit 1 }
if {![info exists ::env(UTILITIES_VERSION)] || $::env(UTILITIES_VERSION) eq ""} { puts stderr "ERROR: UTILITIES_VERSION not set"; exit 1 }
set utils_path "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} { source $utils_path } else { puts stderr "ERROR: Utils not found"; exit 1 }
namespace import ::CBFlow::Utilities::print_header
set config_file "$run_dir/work/$::env(CBFLOW_FLOW_TYPE)/$::env(CBFLOW_NODE_NAME)/run/config.tcl"
if {[file exists $config_file]} { source $config_file }
global fp project tech flow
# Source FC tool config
set _tool_config "[file dirname [info script]]/fc_config.tcl"
if {[file exists $_tool_config]} { source $_tool_config }
handle_info "Starting FP import_design..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

# Source tech_config
if {[info exists ::env(TECH_NAME)] && $::env(TECH_NAME) ne "" &&
    [info exists ::env(TECH_VERSION)] && $::env(TECH_VERSION) ne ""} {
    set _tc "$::env(CONFIG_ROOT)/tech/$::env(TECH_NAME)/$::env(TECH_VERSION)/tech_config.tcl"
    if {[file exists $_tc]} { source -e $_tc }
}

set WORK_DIR "$run_dir/work/FP/import_design1"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

# ==============================================================================
# flow_proc: load_design
# FC-RM: open_lib, copy_block to create working copy
# ==============================================================================
flow_proc load_design {
    handle_info "Loading design from library..."
    global fp flow

    set design_name [expr {[info exists fc(common,design_name)] ? $fc(common,design_name) : $flow(design_name)}]
    set lib_name [expr {[info exists fc(common,design_lib_name)] ? $fc(common,design_lib_name) : "${design_name}.nlib"}]

    # Open the design library
    handle_info "Opening library: $lib_name"
    open_lib $lib_name

    # Copy block to create a working copy for compile_dp
    handle_info "Creating working copy: ${design_name}/import_design"
    copy_block -from ${design_name}/init_design -to ${design_name}/import_design
    current_block ${design_name}/import_design
    link_block

    # Report design statistics
    set cell_count [sizeof_collection [get_cells -hierarchical]]
    set port_count [sizeof_collection [get_ports *]]
    handle_info "Design loaded: $cell_count cells, $port_count ports"

    handle_info "Design loaded for import_design stage"
}

# ==============================================================================
# flow_proc: set_qor_strategy
# FC-RM: set_qor_strategy -stage compile_initial -reduced_effort
# ==============================================================================
flow_proc set_qor_strategy {
    handle_info "Setting QoR strategy for compile_dp..."
    global fp

    # Set QoR strategy for DP stage -- reduced effort for early exploration
    set metric [expr {[info exists fc(compile,qor_metric)] ? $fc(compile,qor_metric) : "timing"}]

    set_qor_strategy -stage compile_initial -reduced_effort -metric $metric

    # Apply user-specified app options for compile_dp
    if {[info exists fc(compile_dp,app_options)] && $fc(compile_dp,app_options) ne ""} {
        foreach {opt val} $fc(compile_dp,app_options) {
            handle_info "Setting app option: $opt = $val"
            set_app_options -name $opt -value $val
        }
    }

    handle_info "QoR strategy set: stage=compile_initial, reduced_effort, metric=$metric"
}

# ==============================================================================
# flow_proc: run_compile_dp
# FC-RM: compile_fusion -to logic_opto (design planning compile)
# ==============================================================================
flow_proc run_compile_dp {
    handle_info "Running compile_dp (compile_fusion -to logic_opto)..."
    global fp

    # FC-RM: compile_fusion with logic_opto target for DP
    set compile_cmd "compile_fusion -to logic_opto"

    # Add user-specified compile options
    if {[info exists fc(compile_dp,options)] && $fc(compile_dp,options) ne ""} {
        append compile_cmd " $fc(compile_dp,options)"
    }

    handle_info "Executing: $compile_cmd"
    eval $compile_cmd

    # Report compile results
    set cell_count [sizeof_collection [get_cells -hierarchical]]
    handle_info "Compile_dp completed: $cell_count cells after logic optimization"

    handle_info "compile_dp completed successfully"
}

# ==============================================================================
# flow_proc: save_design
# FC-RM: save_lib, save_block
# ==============================================================================
flow_proc save_design {
    handle_info "Saving import_design block..."
    global fp flow

    set run_dir $::env(CBFLOW_RUN_DIR)
    set design_name [expr {[info exists fc(common,design_name)] ? $fc(common,design_name) : $flow(design_name)}]
    set lib_name [expr {[info exists fc(common,design_lib_name)] ? $fc(common,design_lib_name) : "${design_name}.nlib"}]

    # Save library and block
    save_lib -all
    save_block
    save_block -as ${lib_name}:${design_name}/import_design_done

    handle_info "Import design block saved: ${design_name}/import_design_done"
}

# ==============================================================================
# flow_proc: generate_reports
# FC-RM: report_qor, report_timing, report_utilization
# ==============================================================================
flow_proc generate_reports {
    handle_info "Generating import_design reports..."
    global fp

    file mkdir "$::REPORTS_DIR"

    set max_paths [expr {[info exists fc(analysis,max_paths)] ? $fc(analysis,max_paths) : 100}]

    # Core reports
    redirect -file $::REPORTS_DIR/report_qor.rpt { report_qor }
    redirect -file $::REPORTS_DIR/report_timing.rpt {
        report_timing -max_paths $max_paths -delay_type max
    }
    redirect -file $::REPORTS_DIR/report_timing.min.rpt {
        report_timing -max_paths $max_paths -delay_type min
    }
    redirect -file $::REPORTS_DIR/report_utilization.rpt { report_utilization }
    redirect -file $::REPORTS_DIR/report_design.rpt { report_design -physical }

    # Check design
    redirect -file $::REPORTS_DIR/check_design.rpt {
        check_design -checks all
    }

    # Message summary
    redirect -file $::REPORTS_DIR/report_msg_summary.rpt { report_msg -summary }

    handle_info "Import design reports generated in: $::REPORTS_DIR"
}

# ==============================================================================
# Source setup.tcl and overrides before flow_exec_all
# ==============================================================================
set _setup_file "$run_dir/work/$::env(CBFLOW_FLOW_TYPE)/$::env(CBFLOW_NODE_NAME)/run/setup.tcl"
if {[file exists $_setup_file]} { handle_info "Sourcing setup hooks: $_setup_file"; source -e $_setup_file }
set _override_file "$run_dir/setup/override_setup.tcl"
if {[file exists $_override_file]} { handle_info "Sourcing user override: $_override_file"; source -e $_override_file }
set _stage_override "$run_dir/setup/override_setup.import_design.tcl"
if {[file exists $_stage_override]} { handle_info "Sourcing stage override: $_stage_override"; source -e $_stage_override }

flow_exec_all

# Exit tool after stage completion
exit
