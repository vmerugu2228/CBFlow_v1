#!/usr/bin/env tclsh
# CBflow DFT_INSERT_PASS1 insert — Mentor Tessent
# DFT insertion + database extract — writes the full Pass1 artifact set:
#   <block>.dft.v, dictionaries, dft_inserted_design/, insertion report.

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
source "$::env(CBFLOW_DFT_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/dft_tessent_common.tcl"

set FLOW_TYPE "DFT_INSERT_PASS1"
set STAGE_NAME "insert"
set NODE_NAME "${STAGE_NAME}1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# ---------------------------------------------------------------------------

flow_proc insert_set_mode {
    handle_info "Switching to insertion mode..."
    set_system_mode insertion
    handle_info "Tessent system mode: insertion"
}

flow_proc insert_insert_logic {
    handle_info "Inserting test logic..."
    insert_test_logic
    handle_info "Test logic inserted"
}

flow_proc insert_write_design {
    set block [dft_tessent_block_name]
    set did [dft_tessent_block_get $block design_id rtl1]
    set out_v   "$::OUTPUTS_DIR/${block}.dft.v"
    set out_dir "$::OUTPUTS_DIR/${block}_${did}.dft_inserted_design"
    set mod_rtl "$::OUTPUTS_DIR/modified_rtl_files/${block}.v"
    file mkdir [file dirname $mod_rtl]
    file mkdir $out_dir
    write_design -output_file $out_v -netlist_format verilog
    write_design_source_files -output_dir $out_dir
    file copy -force $out_v $mod_rtl
    handle_info "DFT-inserted RTL: $out_v"
    handle_info "Modified RTL copy: $mod_rtl"
    handle_info "Inserted design dir: $out_dir"
}

flow_proc insert_write_dictionaries {
    set block [dft_tessent_block_name]
    foreach {ext key} {
        design_source_dictionary design_source
        dft_info_dictionary      dft_info
        dft_summary_dictionary   dft_summary
    } {
        set f "$::OUTPUTS_DIR/${block}.${ext}"
        handle_info "Writing dictionary $key → $f"
        write_design_dictionary -type $key -output $f
    }
}

flow_proc insert_report {
    set block [dft_tessent_block_name]
    set rpt "$::REPORTS_DIR/insertion.rpt"
    handle_info "Writing insertion report → $rpt"
    report_dft_insertion -verbose > $rpt
}

flow_proc insert_import_script {
    if {![string is true -strict $::dft_insert_pass1(write_design_import_script)]} {
        if {$::dft_insert_pass1(write_design_import_script) ne "ON"} {
            handle_info "write_design_import_script OFF — skipping"
            return
        }
    }
    set block [dft_tessent_block_name]
    set script "$::OUTPUTS_DIR/${block}.import.tcl"
    write_design_import_script -output $script
    handle_info "Design import script: $script"
}

flow_proc insert_flow {
    handle_info "Executing DFT_INSERT_PASS1 insert flow..."
    flow_exec insert_set_mode
    flow_exec insert_insert_logic
    flow_exec insert_write_design
    flow_exec insert_write_dictionaries
    flow_exec insert_report
    flow_exec insert_import_script
    handle_info "DFT_INSERT_PASS1 insert completed"
}

if {[info exists argv0] && $argv0 eq [info script]} { flow_exec insert_flow } else { puts "DFT_INSERT_PASS1 insert procedures loaded" }
exit
