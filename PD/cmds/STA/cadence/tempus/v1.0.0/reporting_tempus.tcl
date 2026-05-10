#!/usr/bin/env tclsh
# CBFlow STA reporting - Cadence Tempus | MMMC cross-corner timing summary
set run_dir $::env(CBFLOW_RUN_DIR)
set env_file "$run_dir/.run.cbflow.tcl"
if {[file exists $env_file]} { source $env_file } else { puts stderr "ERROR: .run.cbflow.tcl not found"; exit 1 }
if {[info exists ::env(FLOW_DIR)]} { set FLOW_DIR $::env(FLOW_DIR) } else { puts stderr "ERROR: FLOW_DIR not set"; exit 1 }
if {![info exists ::env(UTILITIES_VERSION)] || $::env(UTILITIES_VERSION) eq ""} { puts stderr "ERROR: UTILITIES_VERSION not set"; exit 1 }
set utils_path "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} { source $utils_path } else { puts stderr "ERROR: Utils not found"; exit 1 }
namespace import ::CBFlow::Utilities::print_header
set config_file "$run_dir/work/STA/reporting/run/config.tcl"
if {[file exists $config_file]} { source $config_file }

# Source tech_config
if {[info exists ::env(TECH_NAME)] && $::env(TECH_NAME) ne "" && [info exists ::env(TECH_VERSION)]} {
    set _tc "$::env(CONFIG_ROOT)/tech/$::env(TECH_NAME)/$::env(TECH_VERSION)/tech_config.tcl"
    if {[file exists $_tc]} { source -e $_tc }
}

# Source user_config for overrides
if {[file exists "$run_dir/setup/user_config.tcl"]} { source -e "$run_dir/setup/user_config.tcl" }
global sta project tech flow
handle_info "Starting STA reporting with Cadence Tempus..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

set WORK_DIR "$run_dir/work/STA/reporting"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

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
    puts $fh "# CBFlow MMMC Timing Summary - Tempus (Cross-Corner)"
    puts $fh "# Generated: [clock format [clock seconds]]"
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

# Exit tool after stage completion
exit
