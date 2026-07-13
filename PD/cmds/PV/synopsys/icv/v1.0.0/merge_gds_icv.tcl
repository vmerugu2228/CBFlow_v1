#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow PV merge_gds — Synopsys ICV
# Merge fill GDS with base layout.
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$::env(CBFLOW_RUN_DIR)/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "PV"
set STAGE_NAME "merge_gds"
set NODE_NAME "${STAGE_NAME}1"

source "$::env(CBFLOW_RUN_DIR)/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$::env(CBFLOW_RUN_DIR)/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $::env(CBFLOW_RUN_DIR) $FLOW_TYPE $NODE_NAME

flow_proc configure_merge_gds {
    global pv
    handle_info "Configuring GDS merge..."
    if {[info exists pv(input,gds)] && $pv(input,gds) ne ""} {
        set ::merge_gds_input $pv(input,gds)
    } else {
        handle_error "No input GDS — set pv(input,gds)"
        return
    }
    set ::merge_gds_out "$::WORK_DIR/results/merged.gds"
    handle_info "GDS merge configuration:"
    handle_info "  Input:  $::merge_gds_input"
    handle_info "  Output: $::merge_gds_out"
}

flow_proc run_merge_gds {
    set ::merge_gds_status "PASS"
    handle_info "Running GDS merge with Synopsys ICV..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    file mkdir "$::WORK_DIR/results"
    file mkdir "$::REPORTS_DIR"
    set cmd "icv -merge -i $::merge_gds_input -o $::merge_gds_out"
    append cmd " -log $::env(CBFLOW_RUN_DIR)/logs/pv/merge_gds_icv.log"
    handle_info "ICV command: $cmd"
    if {[catch {eval exec $cmd} _r]} {
        handle_warning "ICV merge_gds failed: $_r"
        set ::merge_gds_status "FAIL"
    } else {
        set ::merge_gds_status "PASS"
        handle_info "GDS merge completed"
    }
}

flow_proc report_merge_gds {
    set rpt_dir "$::REPORTS_DIR"
    file mkdir $rpt_dir
    set fp [open "$rpt_dir/merge_gds_summary.rpt" w]
    puts $fp "PV GDS Merge Summary — Synopsys ICV"
    puts $fp "Input:  $::merge_gds_input"
    puts $fp "Output: $::merge_gds_out"
    puts $fp "Status: $::merge_gds_status"
    close $fp
    handle_info "GDS merge report written"
}

flow_proc merge_gds_flow {
    flow_exec configure_merge_gds
    flow_exec run_merge_gds
    flow_exec report_merge_gds
    if {[info exists ::merge_gds_status] && $::merge_gds_status eq "FAIL"} {
        handle_error "merge_gds failed — see $::REPORTS_DIR/merge_gds_summary.rpt"
    }
}
if {[info exists argv0] && $argv0 eq [info script]} { flow_exec merge_gds_flow } else { puts " PV merge_gds procedures loaded" }
exit
