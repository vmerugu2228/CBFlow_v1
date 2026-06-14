#!/usr/bin/env tclsh
# STA timing_setup - Cadence Tempus

# -- Bootstrap -----------------------------------------------------------------
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "STA"
set STAGE_NAME "timing_setup"
set NODE_NAME "timing_setup1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# Source active scenarios
set scenarios_file "$run_dir/work/STA/mmmc_setup/run/active_scenarios.tcl"
if {[file exists $scenarios_file]} {
    source $scenarios_file
} else {
    puts stderr "ERROR: Active scenarios file not found: $scenarios_file"
    puts stderr "ERROR: Run mmmc_setup stage first"
    exit 1
}

# Source MMMC configuration for analysis_views
set mmmc_config_file "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/mmmc_config.tcl"
if {[file exists $mmmc_config_file]} { source $mmmc_config_file }

flow_proc setup_timing_dirs {
    handle_info "Setting up setup timing directories..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    foreach dir {"work/STA/timing_setup/run" "reports/sta" "results/sta" "logs/timing_setup"} {
        file mkdir "$run_dir/$dir"
    }
    puts " Setup timing directories created"
}

flow_proc run_setup_timing {
    handle_info "Running MMMC-aware setup timing analysis with Tempus..."
    global mmmc_active_scenarios analysis_views
    set run_dir $::env(CBFLOW_RUN_DIR)
    file mkdir "$::REPORTS_DIR"

    set summary_data {}
    set worst_wns 0.0
    set worst_scenario ""

    foreach scenario $mmmc_active_scenarios {
        handle_info "Analyzing setup timing for scenario: $scenario"

        # Get scenario view information
        array set view_info $analysis_views($scenario)

        # Set active analysis view for this scenario in Tempus
        set_analysis_view -setup [list $scenario] -hold [list $scenario]
        update_timing -full

        # Run setup timing analysis (Tempus uses -late for setup)
        set rpt_file "$::REPORTS_DIR/setup_timing_${scenario}.rpt"
        report_timing -late -max_paths 100 -path_type full_clock \
            -net -cap -significant_digits 4 > $rpt_file
        handle_info "  Setup report written: $rpt_file"

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

    # Generate MMMC setup summary report
    set summary_file "$::REPORTS_DIR/mmmc_setup_summary.rpt"
    set fh [open $summary_file "w"]
    puts $fh "# ═══════════════════════════════════════════════════════════════════════════════"
    puts $fh "# CBFlow MMMC Setup Timing Summary - Tempus"
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
        puts $fh "Worst Setup WNS: ${worst_wns}ns ($worst_scenario)"
    } else {
        puts $fh "Worst Setup WNS: N/A (no violations)"
    }
    puts $fh ""
    puts $fh "# End of MMMC Setup Timing Summary"
    close $fh
    handle_info "Setup summary written: $summary_file"
    puts " MMMC setup timing analysis completed"
}

flow_proc timing_setup_flow {
    handle_info "Executing STA setup timing flow..."
    flow_exec setup_timing_dirs
    flow_exec run_setup_timing
    handle_info "STA setup timing completed successfully"
}
if {[info exists argv0] && $argv0 eq [info script]} { flow_exec timing_setup_flow } else { puts " STA setup timing procedures loaded" }

# Exit tool after stage completion
exit
