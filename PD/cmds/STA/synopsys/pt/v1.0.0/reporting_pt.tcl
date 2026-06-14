#!/usr/bin/env tclsh
# CBFlow STA reporting - Synopsys PrimeTime

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "STA"
set STAGE_NAME "reporting"
set NODE_NAME "${STAGE_NAME}1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

flow_proc setup_reporting_dirs {
    handle_info "Setting up reporting directories..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    foreach dir {"work/STA/reporting/run" "reports/sta" "logs/reporting"} {
        file mkdir "$run_dir/$dir"
    }
    puts " Reporting directories created"
}

flow_proc aggregate_results {
    handle_info "Aggregating MMMC timing results..."
    global mmmc_active_scenarios analysis_views
    set run_dir $::env(CBFLOW_RUN_DIR)

    set summary_data {}
    set overall_worst_setup_wns 0.0
    set overall_worst_setup_scenario ""
    set overall_worst_hold_wns 0.0
    set overall_worst_hold_scenario ""

    if {![info exists mmmc_active_scenarios] || [llength $mmmc_active_scenarios] == 0} {
        handle_info "No MMMC scenarios active — nothing to aggregate"
        return
    }
    foreach scenario $mmmc_active_scenarios {
        array set view_info $analysis_views($scenario)

        # Parse setup report
        set setup_wns "N/A"
        set setup_tns "N/A"
        set setup_rpt "$::REPORTS_DIR/setup_timing_${scenario}.rpt"
        if {[file exists $setup_rpt]} {
            set fp [open $setup_rpt r]
            set content [read $fp]
            close $fp
            if {[regexp {slack\s+\(VIOLATED\)\s+([-\d.]+)} $content -> slack_val]} {
                set setup_wns $slack_val
            } elseif {[regexp {slack\s+\(MET\)\s+([-\d.]+)} $content -> slack_val]} {
                set setup_wns $slack_val
            }
            set setup_tns 0.0
        }

        # Parse hold report
        set hold_wns "N/A"
        set hold_tns "N/A"
        set hold_rpt "$::REPORTS_DIR/hold_timing_${scenario}.rpt"
        if {[file exists $hold_rpt]} {
            set fp [open $hold_rpt r]
            set content [read $fp]
            close $fp
            if {[regexp {slack\s+\(VIOLATED\)\s+([-\d.]+)} $content -> slack_val]} {
                set hold_wns $slack_val
            } elseif {[regexp {slack\s+\(MET\)\s+([-\d.]+)} $content -> slack_val]} {
                set hold_wns $slack_val
            }
            set hold_tns 0.0
        }

        lappend summary_data [list $scenario $view_info(corner) $view_info(mode) \
            $view_info(voltage) $view_info(temperature) $setup_wns $setup_tns $hold_wns $hold_tns]

        # Track overall worst
        if {$setup_wns ne "N/A" && $setup_wns < $overall_worst_setup_wns} {
            set overall_worst_setup_wns $setup_wns
            set overall_worst_setup_scenario $scenario
        }
        if {$hold_wns ne "N/A" && $hold_wns < $overall_worst_hold_wns} {
            set overall_worst_hold_wns $hold_wns
            set overall_worst_hold_scenario $scenario
        }

        array unset view_info
    }

    # Generate cross-corner summary
    set summary_file "$::REPORTS_DIR/mmmc_timing_summary.rpt"
    set fh [open $summary_file "w"]
    puts $fh "# ═══════════════════════════════════════════════════════════════════════════════"
    puts $fh "# CBFlow MMMC Timing Summary - PrimeTime (Cross-Corner)"
    puts $fh "# Generated: [expr {[catch {clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}} _ts] ? "epoch [clock seconds]" : $_ts}]"
    puts $fh "# Scenario Set: $::mmmc_active_scenario_set"
    puts $fh "# Total Scenarios: [llength $mmmc_active_scenarios]"
    puts $fh "# ═══════════════════════════════════════════════════════════════════════════════"
    puts $fh ""
    puts $fh [format "%-40s %-6s %-10s %-6s %-6s | %-10s %-10s | %-10s %-10s" \
        "Scenario" "Crnr" "Mode" "Volt" "Temp" "SetupWNS" "SetupTNS" "HoldWNS" "HoldTNS"]
    puts $fh [string repeat "-" 130]

    foreach entry $summary_data {
        lassign $entry sc corner mode voltage temp s_wns s_tns h_wns h_tns
        puts $fh [format "%-40s %-6s %-10s %-6s %-6s | %-10s %-10s | %-10s %-10s" \
            $sc $corner $mode $voltage $temp $s_wns $s_tns $h_wns $h_tns]
    }

    puts $fh [string repeat "-" 130]
    puts $fh ""
    puts $fh "═══ Overall Worst ═══"
    if {$overall_worst_setup_scenario ne ""} {
        puts $fh "  Setup WNS: ${overall_worst_setup_wns}ns ($overall_worst_setup_scenario)"
    } else {
        puts $fh "  Setup WNS: N/A (no setup violations or no reports)"
    }
    if {$overall_worst_hold_scenario ne ""} {
        puts $fh "  Hold  WNS: ${overall_worst_hold_wns}ns ($overall_worst_hold_scenario)"
    } else {
        puts $fh "  Hold  WNS: N/A (no hold violations or no reports)"
    }
    puts $fh ""
    puts $fh "# End of MMMC Timing Summary"
    close $fh

    handle_info "Cross-corner summary written: $summary_file"
    puts " MMMC reporting completed"
}

flow_proc reporting_flow {
    handle_info "Executing STA reporting flow..."
    flow_exec setup_reporting_dirs
    flow_exec aggregate_results
    handle_info "STA reporting completed successfully"
}
if {[info exists argv0] && $argv0 eq [info script]} { flow_exec reporting_flow } else { puts " STA reporting procedures loaded" }
exit
