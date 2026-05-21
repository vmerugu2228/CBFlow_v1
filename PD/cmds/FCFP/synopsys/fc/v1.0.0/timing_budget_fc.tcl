#!/usr/bin/env tclsh
# CBFlow FCFP timing_budget - Synopsys Fusion Compiler

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "FCFP"
set STAGE_NAME "timing_budget"
set NODE_NAME "${STAGE_NAME}1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# ==============================================================================
# flow_proc: load_design
# ==============================================================================
flow_proc load_design {
    handle_info "Loading design for timing_budget..."
    global fcfp flow

    set design_name [expr {[info exists fcfp(common,design_name)] ? $fcfp(common,design_name) : $flow(design_name)}]

    if {[info exists fcfp(common,open_lib)] && $fcfp(common,open_lib) ne ""} {
        open_lib $fcfp(common,open_lib)
    }

    set from_label [expr {[info exists fcfp(timing_budget,from_label)] ? $fcfp(timing_budget,from_label) : "top_compile"}]
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
    set max_paths [expr {[info exists fcfp(analysis,max_paths)] ? $fcfp(analysis,max_paths) : 100}]
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
    if {[info exists fcfp(timing_budget,mode)] && $fcfp(timing_budget,mode) ne ""} {
        lappend budget_cmd -mode $fcfp(timing_budget,mode)
    }

    # Scenarios for budgeting
    if {[info exists fcfp(timing_budget,active_scenarios)] && $fcfp(timing_budget,active_scenarios) ne ""} {
        set_scenario_status -active false [get_scenarios -filter active]
        set_scenario_status -active true $fcfp(timing_budget,active_scenarios)
    }

    # Source user budget constraints before budget_timing
    if {[info exists fcfp(timing_budget,constraint_script)] && [file exists $fcfp(timing_budget,constraint_script)]} {
        source -e $fcfp(timing_budget,constraint_script)
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

    if {[info exists fcfp(common,sub_blocks)] && [llength $fcfp(common,sub_blocks)] > 0} {
        foreach block $fcfp(common,sub_blocks) {
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

    set design_name [expr {[info exists fcfp(common,design_name)] ? $fcfp(common,design_name) : $flow(design_name)}]

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

    set max_paths [expr {[info exists fcfp(analysis,max_paths)] ? $fcfp(analysis,max_paths) : 100}]

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
# ==============================================================================

flow_exec_all

# Exit tool after stage completion
exit
