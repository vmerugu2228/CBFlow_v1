#!/usr/bin/env tclsh
# CBFlow FP import_design - Synopsys Fusion Compiler
# FC-RM: compile_dp.tcl -- Load design, set QoR strategy, run compile_dp
# Aligned with FC-RM Y-2026.03

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "FP"
set STAGE_NAME "import_design"
set NODE_NAME "import_design1"

# ── Config (full cascade: project → tech → flow → node → mmmc → tool → user) ─
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"

# ── Directories ──────────────────────────────────────────────────────────────
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# ==============================================================================
# flow_proc: load_design
# FC-RM: open_lib, copy_block to create working copy
# ==============================================================================
flow_proc load_design {
    handle_info "Loading design from library..."
    global fp flow

    set design_name [expr {[info exists fp(common,design_name)] ? $fp(common,design_name) : $flow(design_name)}]
    set lib_name [expr {[info exists fp(common,design_lib_name)] ? $fp(common,design_lib_name) : "${design_name}.nlib"}]

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
    set metric [expr {[info exists fp(compile,qor_metric)] ? $fp(compile,qor_metric) : "timing"}]

    set_qor_strategy -stage compile_initial -reduced_effort -metric $metric

    # Apply user-specified app options for compile_dp
    if {[info exists fp(compile_dp,app_options)] && $fp(compile_dp,app_options) ne ""} {
        foreach {opt val} $fp(compile_dp,app_options) {
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
    if {[info exists fp(compile_dp,options)] && $fp(compile_dp,options) ne ""} {
        append compile_cmd " $fp(compile_dp,options)"
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
    set design_name [expr {[info exists fp(common,design_name)] ? $fp(common,design_name) : $flow(design_name)}]
    set lib_name [expr {[info exists fp(common,design_lib_name)] ? $fp(common,design_lib_name) : "${design_name}.nlib"}]

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

    set max_paths [expr {[info exists fp(analysis,max_paths)] ? $fp(analysis,max_paths) : 100}]

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
