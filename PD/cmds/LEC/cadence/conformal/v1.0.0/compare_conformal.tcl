#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow LEC — Cadence Conformal — Compare Stage
# Setup, compare, and report equivalence results
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "LEC"
set STAGE_NAME "compare"
set NODE_NAME "compare1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# ── Read designs ──────────────────────────────────────────────────────────
flow_proc read_designs {
    handle_info "Reading golden and revised designs..."

    set _golden $::lec(input,netlist_golden)
    set _revised $::lec(input,netlist_revised)

    # Read golden
    read_library -golden -both $_golden
    read_design -golden $_golden -file verilog

    # Read revised
    read_design -revised $_revised -file verilog

    handle_info "Both designs loaded"
}

# ── Setup comparison ──────────────────────────────────────────────────────
flow_proc setup_comparison {
    handle_info "Configuring comparison settings..."

    set_system_mode setup

    # Flatten design for equivalence checking
    if {$::lec(compare,flatten_design) eq "true"} {
        set_flatten_model -seq_equiv -seq_constant
    }

    # Datapath verification
    if {$::lec(compare,datapath_verify) eq "true"} {
        set_datapath_option -auto
    }

    # Uniquify names if needed
    if {$::lec(compare,uniquify_names) eq "true"} {
        uniquify -golden -revised
    }

    # Read SVF guidance if available
    if {[info exists ::lec(input,svf_file)] && $::lec(input,svf_file) ne ""} {
        if {[file exists $::lec(input,svf_file)]} {
            read_svf $::lec(input,svf_file)
            handle_info "SVF guidance loaded: $::lec(input,svf_file)"
        }
    }

    handle_info "Comparison setup complete"
}

# ── Run comparison ────────────────────────────────────────────────────────
flow_proc run_comparison {
    handle_info "Running equivalence comparison..."

    set_system_mode lec

    # Map key points between golden and revised
    map_key_points

    # Add all comparison points
    add_compared_points -all

    # Run comparison
    compare

    handle_info "Comparison complete"
}

# ── Generate reports ──────────────────────────────────────────────────────
flow_proc generate_reports {
    handle_info "Generating comparison reports..."
    set rpt_dir $::REPORTS_DIR
    file mkdir $rpt_dir

    # Comparison summary
    redirect "$rpt_dir/comparison_summary.rpt" { report_compare_data }

    # Detailed status
    redirect "$rpt_dir/equivalence_analysis.rpt" { report_compare_data -all }

    # Status report
    redirect "$rpt_dir/status.rpt" { report_status }

    # Non-equivalent points (if any)
    redirect "$rpt_dir/failing_points.rpt" { report_compare_data -nonequivalent }

    # Unmapped points
    redirect "$rpt_dir/unmapped_points.rpt" { report_unmapped_points }

    # Check result
    set _status [report_compare_data -summary]
    if {[string match "*SUCCEEDED*" $_status] || [string match "*Equivalent*" $_status]} {
        handle_info "LEC Result: PASSED — designs are equivalent"
        set fh [open "$rpt_dir/PASSED" "w"]
        puts $fh "LEC PASSED — [clock format [clock seconds]]"
        close $fh
    } else {
        handle_error "LEC Result: FAILED — designs are NOT equivalent"
        set fh [open "$rpt_dir/FAILED" "w"]
        puts $fh "LEC FAILED — [clock format [clock seconds]]"
        close $fh
    }

    handle_info "Reports generated in $rpt_dir"
}

flow_exec_all
