#!/usr/bin/env tclsh
# CBFlow FCFP top_compile - Synopsys Fusion Compiler

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "FCFP"
set STAGE_NAME "top_compile"
set NODE_NAME "${STAGE_NAME}1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# ==============================================================================
# flow_proc: load_design
# ==============================================================================
flow_proc load_design {
    handle_info "Loading design for top_compile..."
    global fcfp flow

    set design_name [expr {[info exists fcfp(common,design_name)] ? $fcfp(common,design_name) : $flow(design_name)}]

    if {[info exists fcfp(common,open_lib)] && $fcfp(common,open_lib) ne ""} {
        open_lib $fcfp(common,open_lib)
    }

    set from_label [expr {[info exists fcfp(top_compile,from_label)] ? $fcfp(top_compile,from_label) : "place_pins"}]
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

    if {[info exists fcfp(top_compile,qor_metric)] && $fcfp(top_compile,qor_metric) ne ""} {
        lappend qor_cmd -metric $fcfp(top_compile,qor_metric)
    } elseif {[info exists fcfp(compile,qor_metric)] && $fcfp(compile,qor_metric) ne ""} {
        lappend qor_cmd -metric $fcfp(compile,qor_metric)
    } else {
        lappend qor_cmd -metric timing
    }

    # Active scenarios for top compile
    if {[info exists fcfp(top_compile,active_scenarios)] && $fcfp(top_compile,active_scenarios) ne ""} {
        set_scenario_status -active false [get_scenarios -filter active]
        set_scenario_status -active true $fcfp(top_compile,active_scenarios)
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

    set from_stage [expr {[info exists fcfp(top_compile,from_stage)] ? $fcfp(top_compile,from_stage) : "logic_opto"}]
    set to_stage [expr {[info exists fcfp(top_compile,to_stage)] ? $fcfp(top_compile,to_stage) : "logic_opto"}]

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

    set design_name [expr {[info exists fcfp(common,design_name)] ? $fcfp(common,design_name) : $flow(design_name)}]

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

    handle_info "Top_compile reports generated in: $::REPORTS_DIR"
}

# ==============================================================================
# ==============================================================================

flow_exec_all

# Exit tool after stage completion
exit
