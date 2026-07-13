#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow PV decomp — Synopsys ICV
# Mask decomposition (multi-patterning colorization).
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$::env(CBFLOW_RUN_DIR)/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "PV"
set STAGE_NAME "decomp"
set NODE_NAME "${STAGE_NAME}1"

source "$::env(CBFLOW_RUN_DIR)/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$::env(CBFLOW_RUN_DIR)/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $::env(CBFLOW_RUN_DIR) $FLOW_TYPE $NODE_NAME

flow_proc configure_decomp {
    global pv tech
    handle_info "Configuring mask decomposition..."
    # Input from producer stage fill_merge_gds1 (per-stage $WORK_DIR/results).
    set ::decomp_input "$::env(CBFLOW_RUN_DIR)/work/PV/fill_merge_gds1/results/fill_merged.gds"
    set ::decomp_out "$::WORK_DIR/results/decomp.gds"
    set ::decomp_colors [expr {[info exists pv(decomp,colors)] ? $pv(decomp,colors) : 2}]
    handle_info "  Input:  $::decomp_input"
    handle_info "  Output: $::decomp_out"
    handle_info "  Colors: $::decomp_colors"
}

flow_proc run_decomp {
    set ::decomp_status "PASS"
    handle_info "Running mask decomposition with Synopsys ICV..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    file mkdir "$::WORK_DIR/results"
    file mkdir "$::REPORTS_DIR"
    set cmd "icv -decomp -i $::decomp_input -o $::decomp_out -colors $::decomp_colors"
    append cmd " -log $::env(CBFLOW_RUN_DIR)/logs/pv/decomp_icv.log"
    handle_info "ICV command: $cmd"
    if {[catch {eval exec $cmd} _r]} {
        handle_warning "ICV decomp failed: $_r"
        set ::decomp_status "FAIL"
    } else {
        set ::decomp_status "PASS"
        handle_info "Mask decomposition completed"
    }
}

flow_proc report_decomp {
    set rpt_dir "$::REPORTS_DIR"
    file mkdir $rpt_dir
    set fp [open "$rpt_dir/decomp_summary.rpt" w]
    puts $fp "PV Mask Decomposition Summary — Synopsys ICV"
    puts $fp "Input:  $::decomp_input"
    puts $fp "Output: $::decomp_out"
    puts $fp "Colors: $::decomp_colors"
    puts $fp "Status: $::decomp_status"
    close $fp
    handle_info "Report written"
}

flow_proc decomp_flow {
    flow_exec configure_decomp
    flow_exec run_decomp
    flow_exec report_decomp
    if {[info exists ::decomp_status] && $::decomp_status eq "FAIL"} {
        handle_error "decomp failed — see $::REPORTS_DIR/decomp_summary.rpt"
    }
}
if {[info exists argv0] && $argv0 eq [info script]} { flow_exec decomp_flow } else { puts " PV decomp procedures loaded" }
exit
