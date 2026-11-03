#!/usr/bin/env tclsh
# CBflow DFT_INSERT_PASS1 bscan_cfg — Mentor Tessent
# Boundary-scan configuration (only when block has a padring).

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
source "$::env(CBFLOW_DFT_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/dft_tessent_common.tcl"

set FLOW_TYPE "DFT_INSERT_PASS1"
set STAGE_NAME "bscan_cfg"
set NODE_NAME "${STAGE_NAME}1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# ---------------------------------------------------------------------------

flow_proc bscan_cfg_apply {
    set block [dft_tessent_block_name]
    set enabled $::dft_insert_pass1(bscan,enabled)
    # "auto" → emit only when block has a padring flag set
    if {$enabled eq "auto"} {
        set has_padring [dft_tessent_block_get $block has_padring false]
        if {![string is true -strict $has_padring]} {
            handle_info "BSCAN skipped for block '$block' (has_padring=$has_padring)"
            return
        }
    } elseif {![string is true -strict $enabled]} {
        handle_info "BSCAN explicitly disabled for block '$block'"
        return
    }

    handle_info "Applying BSCAN configuration (cell=$::dft_insert_pass1(bscan,cell_template))..."
    add_boundary_scan_cell -default -cell_template $::dft_insert_pass1(bscan,cell_template)

    if {[string is true -strict $::dft_insert_pass1(bscan,bypass_register)]} {
        add_bypass_register
    }
    handle_info "BSCAN configured for block '$block'"
}

flow_proc bscan_cfg_summary {
    set rpt "$::REPORTS_DIR/bscan_cfg.rpt"
    set fh [open $rpt "w"]
    puts $fh "BSCAN configuration — [dft_tessent_block_name]"
    puts $fh "Enabled: $::dft_insert_pass1(bscan,enabled)"
    puts $fh "Cell template: $::dft_insert_pass1(bscan,cell_template)"
    puts $fh "Bypass register: $::dft_insert_pass1(bscan,bypass_register)"
    close $fh
}

flow_proc bscan_cfg_flow {
    handle_info "Executing DFT_INSERT_PASS1 bscan_cfg flow..."
    flow_exec bscan_cfg_apply
    flow_exec bscan_cfg_summary
    handle_info "DFT_INSERT_PASS1 bscan_cfg completed"
}

if {[info exists argv0] && $argv0 eq [info script]} { flow_exec bscan_cfg_flow } else { puts "DFT_INSERT_PASS1 bscan_cfg procedures loaded" }
exit
