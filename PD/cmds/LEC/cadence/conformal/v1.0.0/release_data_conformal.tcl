#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow LEC — Cadence Conformal — Release Data Stage
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "LEC"
set STAGE_NAME "release_data"
set NODE_NAME "release_data1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

flow_proc prepare_release {
    handle_info "Preparing LEC release data..."
    set rpt_dir "$run_dir/work/$::FLOW_TYPE/compare1/reports"
    set rel_dir "$::OUTPUTS_DIR"
    file mkdir $rel_dir

    foreach rpt {comparison_summary.rpt equivalence_analysis.rpt failing_points.rpt status.rpt} {
        set src "$rpt_dir/$rpt"
        if {[file exists $src]} {
            file copy -force $src "$rel_dir/$rpt"
        }
    }

    # Copy PASS/FAIL marker
    foreach marker {PASSED FAILED} {
        set src "$rpt_dir/$marker"
        if {[file exists $src]} { file copy -force $src "$rel_dir/$marker" }
    }

    handle_info "Release data prepared in $rel_dir"
}

flow_proc validate_release {
    handle_info "Validating release data..."
    set rel_dir "$::OUTPUTS_DIR"

    if {![file exists "$rel_dir/comparison_summary.rpt"]} {
        error "Missing mandatory file: comparison_summary.rpt"
    }

    handle_info "Release validation passed"
}

flow_exec_all
