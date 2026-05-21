#!/usr/bin/env tclsh
# CBFlow FCFP init_compile - Synopsys Fusion Compiler

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "FCFP"
set STAGE_NAME "init_compile"
set NODE_NAME "${STAGE_NAME}1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# ==============================================================================
flow_proc load_design {
    handle_info "Loading design for init_compile..."
    global fcfp flow

    set design_name [expr {[info exists fcfp(common,design_name)] ? $fcfp(common,design_name) : $flow(design_name)}]

    if {[info exists fcfp(common,open_lib)] && $fcfp(common,open_lib) ne ""} {
        open_lib $fcfp(common,open_lib)
    }

    set from_label [expr {[info exists fcfp(init_compile,from_label)] ? $fcfp(init_compile,from_label) : "commit_blocks"}]
    copy_block -from ${design_name}/${from_label} -to ${design_name}/init_compile
    current_block ${design_name}/init_compile
    link_block

    handle_info "Design loaded: $design_name"
}

# ==============================================================================
# flow_proc: set_qor_strategy
# FC-RM: set_qor_strategy -stage compile_initial -reduced_effort
# ==============================================================================
flow_proc set_qor_strategy {
    handle_info "Setting QoR strategy for compile_initial..."
    global fcfp

    set qor_cmd "set_qor_strategy -stage compile_initial"

    if {[info exists fcfp(compile,qor_metric)] && $fcfp(compile,qor_metric) ne ""} {
        lappend qor_cmd -metric $fcfp(compile,qor_metric)
    } else {
        lappend qor_cmd -metric timing
    }

    # Reduced effort for DP flow (recommended per FC-RM)
    if {![info exists fcfp(compile,reduced_effort)] || $fcfp(compile,reduced_effort)} {
        lappend qor_cmd -reduced_effort
    }

    if {[info exists fcfp(compile,active_scenarios)] && $fcfp(compile,active_scenarios) ne ""} {
        set_scenario_status -active false [get_scenarios -filter active]
        set_scenario_status -active true $fcfp(compile,active_scenarios)
    }

    handle_info "Running: $qor_cmd"
    eval $qor_cmd

    # Handle hybrid library type
    set rm_lib_type [get_attribute -quiet [current_design] rm_lib_type]
    if {$rm_lib_type ne "" && [regexp {h$} $rm_lib_type]} {
        handle_info "Hybrid library detected -- setting congestion_driven_max_util to 0.85"
        set_app_options -name place.coarse.congestion_driven_max_util -value 0.85
        eval $qor_cmd
    }

    handle_info "Init compile QoR strategy set"
}

# ==============================================================================
# flow_proc: run_compile
# FC-RM: compile_fusion -to logic_opto (early compile for area estimation)
# ==============================================================================
flow_proc run_compile {
    handle_info "Running init_compile (compile_fusion -to logic_opto)..."
    global fcfp

    set compile_to [expr {[info exists fcfp(compile,early_stage)] ? $fcfp(compile,early_stage) : "logic_opto"}]

    handle_info "compile_fusion -to $compile_to"
    compile_fusion -to $compile_to

    change_names -rules verilog -hierarchy -skip_physical_only_cells
    connect_pg_net

    handle_info "Init compile ($compile_to) completed"
}

# ==============================================================================
# flow_proc: save_design
# ==============================================================================
flow_proc save_design {
    handle_info "Saving init_compile block..."
    global fcfp flow

    set design_name [expr {[info exists fcfp(common,design_name)] ? $fcfp(common,design_name) : $flow(design_name)}]

    save_lib -all
    save_block
    save_block -as ${design_name}/init_compile
    handle_info "Block saved: ${design_name}/init_compile"
}

# ==============================================================================
# flow_proc: generate_reports
# ==============================================================================
flow_proc generate_reports {
    handle_info "Generating init_compile reports..."
    global fcfp

    set max_paths [expr {[info exists fcfp(analysis,max_paths)] ? $fcfp(analysis,max_paths) : 100}]

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

    handle_info "Init_compile reports generated in: $::REPORTS_DIR"
}

# ==============================================================================
# ==============================================================================

flow_exec_all

# Exit tool after stage completion
exit
