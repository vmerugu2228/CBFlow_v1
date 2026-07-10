#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow PV perc_ldl — Synopsys ICV
# PERC-LDL: latch-up / leakage-driven variant of PERC. Runs in parallel with
# the standard perc1 stage.
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "PV"
set STAGE_NAME "perc_ldl"
set NODE_NAME "${STAGE_NAME}1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

flow_proc configure_perc_ldl {
    global pv tech
    handle_info "Configuring PERC-LDL run..."
    set ::perc_ldl_gds "$run_dir/results/pv/signoff_layout.gds"
    if {[info exists pv(input,rule_deck_perc_ldl)] && $pv(input,rule_deck_perc_ldl) ne ""} {
        set ::perc_ldl_rules $pv(input,rule_deck_perc_ldl)
    } elseif {[info exists tech(rules,perc_ldl)]} {
        set ::perc_ldl_rules $tech(rules,perc_ldl)
    } else {
        handle_info "No PERC-LDL rule deck specified — falling back to standard PERC deck"
        set ::perc_ldl_rules [expr {[info exists pv(input,rule_deck_perc)] ? $pv(input,rule_deck_perc) : ""}]
    }
    set ::perc_ldl_out_dir "$run_dir/results/pv/perc_ldl"
    handle_info "PERC-LDL configuration:"
    handle_info "  GDS input:  $::perc_ldl_gds"
    handle_info "  Rule deck:  $::perc_ldl_rules"
    handle_info "  Output dir: $::perc_ldl_out_dir"
}

flow_proc run_perc_ldl {
    handle_info "Running PERC-LDL with Synopsys ICV..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    file mkdir "$::perc_ldl_out_dir"
    file mkdir "$::REPORTS_DIR"
    set cmd "icv -perc_ldl -i $::perc_ldl_gds -c $::perc_ldl_rules -f $::perc_ldl_out_dir"
    append cmd " -log $run_dir/logs/pv/perc_ldl_icv.log"
    handle_info "ICV command: $cmd"
    if {[catch {eval exec $cmd} _r]} {
        handle_error "ICV perc_ldl failed: $_r"
        set ::perc_ldl_status "FAIL"
    } else {
        set ::perc_ldl_status "PASS"
        handle_info "PERC-LDL completed"
    }
}

flow_proc report_perc_ldl {
    set rpt_dir "$::REPORTS_DIR"
    file mkdir $rpt_dir
    # Also ensure the mandatory_outputs path exists
    file mkdir "$run_dir/results/pv/perc_ldl"
    set fp [open "$rpt_dir/perc_ldl_summary.rpt" w]
    puts $fp "PV PERC-LDL Summary — Synopsys ICV"
    puts $fp "GDS input:  $::perc_ldl_gds"
    puts $fp "Rule deck:  $::perc_ldl_rules"
    puts $fp "Status:     $::perc_ldl_status"
    close $fp
    # Signoff artifact expected by mandatory_outputs
    set mp [open "$run_dir/results/pv/perc_ldl/perc_ldl.rpt" w]
    puts $mp "PERC-LDL sign-off report — $::perc_ldl_status"
    close $mp
    handle_info "Report written"
}

flow_proc perc_ldl_flow {
    flow_exec configure_perc_ldl
    flow_exec run_perc_ldl
    flow_exec report_perc_ldl
}
if {[info exists argv0] && $argv0 eq [info script]} { flow_exec perc_ldl_flow } else { puts " PV perc_ldl procedures loaded" }
exit
