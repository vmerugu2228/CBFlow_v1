#!/usr/bin/env tclsh
# CBflow DFT_INSERT_PASS1 vgen — Mentor Tessent
# Pattern generation — MemoryBist_P1 + ParallelRetentionTest + ICLNetwork files.

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
source "$::env(CBFLOW_DFT_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/dft_tessent_common.tcl"

set FLOW_TYPE "DFT_INSERT_PASS1"
set STAGE_NAME "vgen"
set NODE_NAME "${STAGE_NAME}1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# ---------------------------------------------------------------------------

flow_proc vgen_mbist_patterns {
    if {![string is true -strict $::dft_insert_pass1(vgen,memory_test)]} {
        handle_info "vgen,memory_test disabled — skipping"
        return
    }
    handle_info "Generating MBIST patterns (MemoryBist_P1)..."
    create_patterns -memory_test -pattern_name MemoryBist_P1
    foreach ext {v pdl} {
        set f "$::OUTPUTS_DIR/MemoryBist_P1.${ext}"
        write_patterns -pattern_name MemoryBist_P1 -format $ext -output $f
        handle_info "Pattern $ext: $f"
    }
}

flow_proc vgen_retention_patterns {
    if {![string is true -strict $::dft_insert_pass1(vgen,retention_test)]} {
        handle_info "vgen,retention_test disabled — skipping"
        return
    }
    handle_info "Generating parallel retention patterns..."
    create_patterns -memory_test -retention -parallel \
                    -pattern_name MemoryBist_ParallelRetentionTest_P1
    foreach ext {v pdl} {
        set f "$::OUTPUTS_DIR/MemoryBist_ParallelRetentionTest_P1.${ext}"
        write_patterns -pattern_name MemoryBist_ParallelRetentionTest_P1 -format $ext -output $f
        handle_info "Retention pattern $ext: $f"
    }
}

flow_proc vgen_icl_network {
    handle_info "Writing ICL network..."
    foreach ext {v pdl} {
        set f "$::OUTPUTS_DIR/ICLNetwork.${ext}"
        extract_icl -network -format $ext -output $f
        handle_info "ICLNetwork $ext: $f"
    }
}

flow_proc vgen_metrics {
    # Pattern count — one of the key DFT metrics
    set count 0
    foreach pat [glob -nocomplain "$::OUTPUTS_DIR/*.v"] {
        if {[string match "*Pattern*" [file tail $pat]] ||
            [string match "*Bist*" [file tail $pat]]} {
            incr count
        }
    }
    emit_metric pattern_count $count
    handle_info "Pattern files: $count"
}

flow_proc vgen_flow {
    handle_info "Executing DFT_INSERT_PASS1 vgen flow..."
    flow_exec vgen_mbist_patterns
    flow_exec vgen_retention_patterns
    flow_exec vgen_icl_network
    flow_exec vgen_metrics
    handle_info "DFT_INSERT_PASS1 vgen completed"
}

if {[info exists argv0] && $argv0 eq [info script]} { flow_exec vgen_flow } else { puts "DFT_INSERT_PASS1 vgen procedures loaded" }
exit
