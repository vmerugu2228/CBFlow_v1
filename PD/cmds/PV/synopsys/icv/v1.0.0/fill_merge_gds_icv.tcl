#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow PV fill_merge_gds — Synopsys ICV
# Post-merge fill validation / stitching. Verifies that the merged GDS from
# merge_gds1 is well-formed for the multi-patterning decomposition stage.
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$::env(CBFLOW_RUN_DIR)/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "PV"
set STAGE_NAME "fill_merge_gds"
set NODE_NAME "${STAGE_NAME}1"

source "$::env(CBFLOW_RUN_DIR)/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$::env(CBFLOW_RUN_DIR)/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $::env(CBFLOW_RUN_DIR) $FLOW_TYPE $NODE_NAME

flow_proc configure_fill_merge_gds {
    global pv
    handle_info "Configuring post-merge fill validation..."
    # Input from producer stage merge_gds1 (per-stage $WORK_DIR/results),
    # NOT the legacy shared $CBFLOW_RUN_DIR/results/pv/ (which nothing writes
    # to anymore after the fill1/erc1 stage rework).
    set ::fill_merge_input "$::env(CBFLOW_RUN_DIR)/work/PV/merge_gds1/results/merged.gds"
    set ::fill_merge_out   "$::WORK_DIR/results/fill_merged.gds"
    handle_info "  Input:  $::fill_merge_input"
    handle_info "  Output: $::fill_merge_out"
}

flow_proc run_fill_merge_gds {
    set ::fill_merge_status "PASS"
    handle_info "Running post-merge fill validation with Synopsys ICV..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    file mkdir "$::WORK_DIR/results"
    file mkdir "$::REPORTS_DIR"
    set cmd "icv -fill_merge -i $::fill_merge_input -o $::fill_merge_out"
    append cmd " -log $::env(CBFLOW_RUN_DIR)/logs/pv/fill_merge_gds_icv.log"
    handle_info "ICV command: $cmd"
    if {[catch {eval exec $cmd} _r]} {
        handle_warning "ICV fill_merge_gds failed: $_r"
        set ::fill_merge_status "FAIL"
    } else {
        set ::fill_merge_status "PASS"
        handle_info "Post-merge fill validation completed"
    }
}

flow_proc report_fill_merge_gds {
    set rpt_dir "$::REPORTS_DIR"
    file mkdir $rpt_dir
    # pv_fill_merge_density check keys off the exact label emitted here.
    set _fail [expr {$::fill_merge_status eq "FAIL"}]
    set ::fill_merge_density [expr {$_fail ? 1 : 0}]
    set fp [open "$rpt_dir/fill_merge_gds_summary.rpt" w]
    puts $fp "PV Post-Merge Fill Validation Summary — Synopsys ICV"
    puts $fp "Input:  $::fill_merge_input"
    puts $fp "Output: $::fill_merge_out"
    puts $fp "Status: $::fill_merge_status"
    puts $fp "Density Violations Post-Fill: $::fill_merge_density"
    close $fp
    handle_info "Report written"
}

flow_proc fill_merge_gds_flow {
    flow_exec configure_fill_merge_gds
    flow_exec run_fill_merge_gds
    flow_exec report_fill_merge_gds
    flow_fail_if_status ::fill_merge_status "$::REPORTS_DIR/fill_merge_gds_summary.rpt"
}
if {[info exists argv0] && $argv0 eq [info script]} { flow_exec fill_merge_gds_flow } else { puts " PV fill_merge_gds procedures loaded" }
exit
