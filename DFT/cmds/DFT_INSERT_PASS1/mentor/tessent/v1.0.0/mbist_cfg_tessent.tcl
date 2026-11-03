#!/usr/bin/env tclsh
# CBflow DFT_INSERT_PASS1 mbist_cfg — Mentor Tessent
# MBIST configuration: memory grouping, bbox models, constraints, static-ports.

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
source "$::env(CBFLOW_DFT_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/dft_tessent_common.tcl"

set FLOW_TYPE "DFT_INSERT_PASS1"
set STAGE_NAME "mbist_cfg"
set NODE_NAME "${STAGE_NAME}1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# ---------------------------------------------------------------------------

flow_proc mbist_cfg_check_enable {
    set block [dft_tessent_block_name]
    set enabled [dft_tessent_block_get $block include_memory_test OFF]
    if {$enabled ne "ON"} {
        handle_info "MBIST explicitly OFF for block '$block' — skipping config"
        set ::_mbist_skip 1
        return
    }
    set ::_mbist_skip 0
    handle_info "MBIST ON for block '$block'"
}

flow_proc mbist_cfg_memory_modules {
    if {$::_mbist_skip} { return }
    set block [dft_tessent_block_name]
    set mods [dft_tessent_block_get $block bbox_models,modules {}]
    foreach mod $mods {
        define_memory_module $mod
        handle_info "define_memory_module $mod"
    }
}

flow_proc mbist_cfg_grouping {
    if {$::_mbist_skip} { return }
    set block [dft_tessent_block_name]
    set gf [dft_tessent_block_get $block mbist_grouping_file ""]
    if {$gf eq ""} {
        handle_info "No memory grouping file for block '$block' — using defaults"
        return
    }
    source $gf
    handle_info "Memory grouping file sourced: $gf"
}

flow_proc mbist_cfg_constraints {
    if {$::_mbist_skip} { return }
    set constraints [dft_tessent_project_get mbist_common_constraints {}]
    foreach pair $constraints {
        set pin [lindex $pair 0]
        set val [lindex $pair 1]
        if {$pin eq "" || $val eq ""} { continue }
        set_memory_test_config -port $pin -value $val
        handle_info "set_memory_test_config -port $pin -value $val"
    }
}

flow_proc mbist_cfg_controller {
    if {$::_mbist_skip} { return }
    set ctype $::dft_insert_pass1(mbist,controller_type)
    set wrap  $::dft_insert_pass1(mbist,wrap_memories)
    set clkd  $::dft_insert_pass1(mbist,bist_clock_domain)
    set modes $::dft_insert_pass1(mbist,test_modes)
    set bap   $::dft_insert_pass1(mbist,bap_enabled)
    set count $::dft_insert_pass1(mbist,controller_count)

    set_mbist_controller_type $ctype
    if {[string is true -strict $wrap]} { enable_memory_wrapping }
    set_mbist_clock_domain $clkd
    foreach m $modes { add_test_mode $m }
    if {[string is true -strict $bap]} { enable_mbist_bap }
    if {$count ne "auto"} { set_mbist_controller_count $count }

    handle_info "MBIST controller: type=$ctype wrap=$wrap clk=$clkd modes=$modes bap=$bap count=$count"
}

flow_proc mbist_cfg_summary {
    set rpt "$::REPORTS_DIR/mbist_cfg.rpt"
    set block [dft_tessent_block_name]
    set fh [open $rpt "w"]
    puts $fh "MBIST configuration — $block"
    puts $fh "Skipped: $::_mbist_skip"
    puts $fh "Controller type: $::dft_insert_pass1(mbist,controller_type)"
    puts $fh "Clock domain:    $::dft_insert_pass1(mbist,bist_clock_domain)"
    puts $fh "Test modes:      $::dft_insert_pass1(mbist,test_modes)"
    set mods [dft_tessent_block_get $block bbox_models,modules {}]
    puts $fh "Memory modules:  $mods"
    close $fh
    handle_info "MBIST cfg report: $rpt"
}

flow_proc mbist_cfg_flow {
    handle_info "Executing DFT_INSERT_PASS1 mbist_cfg flow..."
    set ::_mbist_skip 0
    flow_exec mbist_cfg_check_enable
    flow_exec mbist_cfg_memory_modules
    flow_exec mbist_cfg_grouping
    flow_exec mbist_cfg_constraints
    flow_exec mbist_cfg_controller
    flow_exec mbist_cfg_summary
    handle_info "DFT_INSERT_PASS1 mbist_cfg completed"
}

if {[info exists argv0] && $argv0 eq [info script]} { flow_exec mbist_cfg_flow } else { puts "DFT_INSERT_PASS1 mbist_cfg procedures loaded" }
exit
