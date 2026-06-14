#!/usr/bin/env tclsh
# CBFlow STA timing_hold - Synopsys PrimeTime

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "STA"
set STAGE_NAME "timing_hold"
set NODE_NAME "${STAGE_NAME}1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

flow_proc setup_hold_dirs {
    handle_info "Setting up hold timing directories..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    foreach dir {"work/STA/timing_hold/run" "reports/sta" "results/sta" "logs/timing_hold"} {
        file mkdir "$run_dir/$dir"
    }
    puts " Hold timing directories created"
}

flow_proc run_hold_timing {
    handle_info "Running MMMC-aware hold timing analysis..."
    global mmmc_active_scenarios analysis_views
    set run_dir $::env(CBFLOW_RUN_DIR)
    file mkdir "$::REPORTS_DIR"

    set summary_data {}
    set worst_wns 0.0
    set worst_scenario ""

    foreach scenario $mmmc_active_scenarios {
        handle_info "Analyzing hold timing for scenario: $scenario"

        # Get scenario view information
        array set view_info $analysis_views($scenario)

        # Set operating conditions for this scenario
        set_operating_conditions -analysis_type on_chip_variation
        update_timing -full

        # Run hold timing analysis (min delay = hold)
        set rpt_file "$::REPORTS_DIR/hold_timing_${scenario}.rpt"
        report_timing -delay_type min -max_paths 100 -input_pins -nets -transition_time \
            -capacitance -significant_digits 4 > $rpt_file
        handle_info "  Hold report written: $rpt_file"

        # Collect WNS/TNS for summary
        set wns 0.0
        set tns 0.0
        if {[file exists $rpt_file]} {
            set fp [open $rpt_file r]
            set content [read $fp]
            close $fp
            if {[regexp {slack\s+\(VIOLATED\)\s+([-\d.]+)} $content -> slack_val]} {
                set wns $slack_val
            } elseif {[regexp {slack\s+\(MET\)\s+([-\d.]+)} $content -> slack_val]} {
                set wns $slack_val
            }
        }

        lappend summary_data [list $scenario $view_info(corner) $view_info(mode) $view_info(voltage) $view_info(temperature) $wns $tns]

        if {$wns < $worst_wns} {
            set worst_wns $wns
            set worst_scenario $scenario
        }

        array unset view_info
    }

    # Generate MMMC hold summary report
    set summary_file "$::REPORTS_DIR/mmmc_hold_summary.rpt"
    set fh [open $summary_file "w"]
    puts $fh "# ═══════════════════════════════════════════════════════════════════════════════"
    puts $fh "# CBFlow MMMC Hold Timing Summary - PrimeTime"
    puts $fh "# Generated: [expr {[catch {clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}} _ts] ? "epoch [clock seconds]" : $_ts}]"
    puts $fh "# Scenario Set: $::mmmc_active_scenario_set"
    puts $fh "# ═══════════════════════════════════════════════════════════════════════════════"
    puts $fh ""
    puts $fh [format "%-45s %-8s %-12s %-8s %-8s %-12s %-12s" \
        "Scenario" "Corner" "Mode" "Voltage" "Temp" "WNS(ns)" "TNS(ns)"]
    puts $fh [string repeat "-" 110]
    foreach entry $summary_data {
        lassign $entry sc corner mode voltage temp wns tns
        puts $fh [format "%-45s %-8s %-12s %-8s %-8s %-12s %-12s" \
            $sc $corner $mode $voltage $temp $wns $tns]
    }
    puts $fh [string repeat "-" 110]
    puts $fh ""
    if {$worst_scenario ne ""} {
        puts $fh "Worst Hold WNS: ${worst_wns}ns ($worst_scenario)"
    } else {
        puts $fh "Worst Hold WNS: N/A (no violations)"
    }
    puts $fh ""
    puts $fh "# End of MMMC Hold Timing Summary"
    close $fh
    handle_info "Hold summary written: $summary_file"
    puts " MMMC hold timing analysis completed"
}

flow_proc timing_hold_flow {
    handle_info "Executing STA hold timing flow..."
    flow_exec setup_hold_dirs
    flow_exec run_hold_timing
    handle_info "STA hold timing completed successfully"
}
if {[info exists argv0] && $argv0 eq [info script]} { flow_exec timing_hold_flow } else { puts " STA hold timing procedures loaded" }
exit
