#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow PV decomp_merge_gds — Synopsys ICV
# Merge decomposed color layers back into a single GDS that downstream signoff
# checks (drc/lvs/perc/erc/xor) consume.
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$::env(CBFLOW_RUN_DIR)/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "PV"
set STAGE_NAME "decomp_merge_gds"
set NODE_NAME "${STAGE_NAME}1"

source "$::env(CBFLOW_RUN_DIR)/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$::env(CBFLOW_RUN_DIR)/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $::env(CBFLOW_RUN_DIR) $FLOW_TYPE $NODE_NAME

flow_proc configure_decomp_merge_gds {
    handle_info "Configuring decomposed GDS merge..."
    set ::dm_fill_input "$::env(CBFLOW_RUN_DIR)/results/pv/fill_merged.gds"
    set ::dm_decomp_input "$::env(CBFLOW_RUN_DIR)/results/pv/decomp.gds"
    set ::dm_out "$::WORK_DIR/results/signoff_layout.gds"
    handle_info "  Fill-merged input: $::dm_fill_input"
    handle_info "  Decomp input:      $::dm_decomp_input"
    handle_info "  Output:            $::dm_out"
}

flow_proc run_decomp_merge_gds {
    set ::dm_status "PASS"
    handle_info "Running decomposed GDS merge with Synopsys ICV..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    file mkdir "$::WORK_DIR/results"
    file mkdir "$::REPORTS_DIR"
    set cmd "icv -decomp_merge -fill $::dm_fill_input -decomp $::dm_decomp_input -o $::dm_out"
    append cmd " -log $::env(CBFLOW_RUN_DIR)/logs/pv/decomp_merge_gds_icv.log"
    handle_info "ICV command: $cmd"
    if {[catch {eval exec $cmd} _r]} {
        handle_warning "ICV decomp_merge_gds failed: $_r"
        set ::dm_status "FAIL"
    } else {
        set ::dm_status "PASS"
        handle_info "Decomposed GDS merge completed"
    }
}

flow_proc report_decomp_merge_gds {
    set rpt_dir "$::REPORTS_DIR"
    file mkdir $rpt_dir
    set fp [open "$rpt_dir/decomp_merge_gds_summary.rpt" w]
    puts $fp "PV Decomposed GDS Merge Summary — Synopsys ICV"
    puts $fp "Fill input:   $::dm_fill_input"
    puts $fp "Decomp input: $::dm_decomp_input"
    puts $fp "Output:       $::dm_out"
    puts $fp "Status:       $::dm_status"
    close $fp
    handle_info "Report written"
}

flow_proc decomp_merge_gds_flow {
    flow_exec configure_decomp_merge_gds
    flow_exec run_decomp_merge_gds
    flow_exec report_decomp_merge_gds
}
if {[info exists argv0] && $argv0 eq [info script]} { flow_exec decomp_merge_gds_flow } else { puts " PV decomp_merge_gds procedures loaded" }
exit
