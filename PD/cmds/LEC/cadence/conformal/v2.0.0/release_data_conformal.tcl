#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow LEC — Cadence Conformal — Release Data Stage
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "LEC"
set STAGE_NAME "release_data"
set NODE_NAME [cbflow_node_name]

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME



# Source release utilities for ::CBFlow::Release namespace
set _ru "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/release_utils.tcl"
if {[file exists $_ru]} { source $_ru }

# Report contracts come from release_config.tcl (release_deliverables(LEC,*)).
if {![array exists ::release_deliverables]} {
    set _rc "$::env(CONFIG_ROOT)/flow/[cbflow_version FLOW_CONFIG_VERSION]/release_config.tcl"
    if {![file exists $_rc]} { handle_error "release_config.tcl not found: $_rc" }
    source $_rc
}

flow_proc prepare_release {
    set run_dir $::env(CBFLOW_RUN_DIR)
    handle_info "Preparing LEC release data..."
    # Reports of the compare node upstream of this release node.
    set rpt_dir "[cbflow_node_dir [cbflow_chain_node compare]]/reports"
    set rel_dir "$::OUTPUTS_DIR"
    file mkdir $rel_dir

    foreach rpt [cbflow_require release_deliverables LEC,compare_reports] {
        set src "$rpt_dir/$rpt"
        if {[file exists $src]} {
            file copy -force $src "$rel_dir/$rpt"
        }
    }

    # Copy PASS/FAIL marker
    foreach marker [cbflow_require release_deliverables LEC,status_markers] {
        set src "$rpt_dir/$marker"
        if {[file exists $src]} { file copy -force $src "$rel_dir/$marker" }
    }

    handle_info "Release data prepared in $rel_dir"
}

flow_proc validate_release {
    handle_info "Validating release data..."
    set rel_dir "$::OUTPUTS_DIR"

    foreach f [cbflow_require release_deliverables LEC,mandatory] {
        if {![file exists "$rel_dir/$f"]} {
            error "Missing mandatory file: $f"
        }
    }

    handle_info "Release validation passed"
}

flow_exec_all
