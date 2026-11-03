#!/usr/bin/env tclsh
# CBflow DFT_INSERT_PASS1 init — Mentor Tessent
#
# Context setup + Database setup + PDK & Design setup + Compile & Elab
# (per owner spreadsheet Pass1 "Setup" row).

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
source "$::env(CBFLOW_DFT_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/dft_tessent_common.tcl"

set FLOW_TYPE "DFT_INSERT_PASS1"
set STAGE_NAME "init"
set NODE_NAME "${STAGE_NAME}1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# ---------------------------------------------------------------------------

flow_proc init_tessent_shell {
    handle_info "Tessent shell init..."
    set_context $::dft_insert_pass1(tool,context)
    set_design_level [dft_tessent_block_get [dft_tessent_block_name] design_type RTL]
    set_system_mode setup
    handle_info "Tessent context: $::dft_insert_pass1(tool,context)"
}

flow_proc read_libraries {
    set block [dft_tessent_block_name]
    handle_info "Reading libraries for block '$block'..."
    # tcelllib (standard-cell) first
    if {[info exists ::dft_insert_pass1(input,tcelllib)] && $::dft_insert_pass1(input,tcelllib) ne ""} {
        read_cell_library $::dft_insert_pass1(input,tcelllib)
        handle_info "tcelllib: $::dft_insert_pass1(input,tcelllib)"
    }
    # Then memory libs from MasterConfig
    set masis    [dft_tessent_project_get mbist_libs,masis    {}]
    set compiler [dft_tessent_project_get mbist_libs,compiler {}]
    foreach f $masis    { read_cell_library $f ; handle_info "masis: $f" }
    foreach f $compiler { read_verilog      $f ; handle_info "compiler: $f" }
}

flow_proc read_rtl {
    set block [dft_tessent_block_name]
    handle_info "Reading RTL for block '$block'..."
    set rtl_cmd [dft_tessent_resolve_rtl_filelist $block]
    if {$rtl_cmd eq ""} {
        # Fallback to the direct dft_insert_pass1(input,rtl) field
        if {[info exists ::dft_insert_pass1(input,rtl)] && $::dft_insert_pass1(input,rtl) ne ""} {
            read_verilog $::dft_insert_pass1(input,rtl)
        } else {
            handle_error "No RTL filelist configured — set project(dft,rtl_files,$block) or dft_insert_pass1(input,rtl)"
        }
    } else {
        eval $rtl_cmd
    }
    set_current_design $block
}

flow_proc apply_bbox_models {
    set block [dft_tessent_block_name]
    set errs [dft_tessent_check_bbox_models $block]
    if {[llength $errs] > 0} {
        foreach e $errs { handle_error $e }
    }
    set insts [dft_tessent_block_get $block bbox_models,instances {}]
    set mods  [dft_tessent_block_get $block bbox_models,modules   {}]
    if {[llength $insts] == 0 && [llength $mods] == 0} {
        handle_info "No blackbox models declared for '$block'"
        return
    }
    handle_info "Applying blackbox models: ${insts} + modules {${mods}}"
    foreach inst $insts { add_black_box -instances $inst }
    foreach mod  $mods  { add_black_box -modules   $mod }
}

flow_proc init_summary {
    set rpt "$::REPORTS_DIR/init.rpt"
    set fh [open $rpt "w"]
    puts $fh "DFT_INSERT_PASS1 init — [clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}]"
    puts $fh "Block:    [dft_tessent_block_name]"
    puts $fh "Tool:     Tessent  Status: OK"
    puts $fh "Context:  $::dft_insert_pass1(tool,context)"
    close $fh
    handle_info "Init summary: $rpt"
}

flow_proc init_flow {
    handle_info "Executing DFT_INSERT_PASS1 init flow..."
    flow_exec init_tessent_shell
    flow_exec read_libraries
    flow_exec read_rtl
    flow_exec apply_bbox_models
    flow_exec init_summary
    handle_info "DFT_INSERT_PASS1 init completed"
}

if {[info exists argv0] && $argv0 eq [info script]} { flow_exec init_flow } else { puts "DFT_INSERT_PASS1 init procedures loaded" }
exit
