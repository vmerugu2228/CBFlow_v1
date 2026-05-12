#!/usr/bin/env tclsh
# CBFlow STA TIMING SCENARIO Handler - Cadence Tempus
# Per-scenario timing handler: takes a SCENARIO NAME (not a subnode name)
# and runs both setup + hold analysis for that specific MMMC scenario.

if {$argc < 1} { puts "ERROR: Missing scenario_name argument"; exit 1 }
set scenario_name [lindex $argv 0]
set run_dir [expr {$argc > 1 ? [lindex $argv 1] : [pwd]}]

# Source run environment
if {[file exists "$run_dir/.run.cbflow.tcl"]} {
    source "$run_dir/.run.cbflow.tcl"
} else {
    puts "ERROR: .run.cbflow.tcl not found in $run_dir"
    exit 1
}

# Source utilities
source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/error_utils.tcl"

# Source flow config
set flow_config "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/flow_config.tcl"
if {[file exists $flow_config]} { source $flow_config }

# Source node config (STA_config.tcl)
set node_config "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/node_configs/STA_config.tcl"
if {[file exists $node_config]} { source $node_config }

# Source tech_config
if {[info exists ::env(TECH_NAME)] && $::env(TECH_NAME) ne "" && [info exists ::env(TECH_VERSION)]} {
    set _tc "$::env(CONFIG_ROOT)/tech/$::env(TECH_NAME)/$::env(TECH_VERSION)/tech_config.tcl"
    if {[file exists $_tc]} { source -e $_tc }
}
# Source user_config for overrides
if {[file exists "$run_dir/setup/user_config.tcl"]} { source -e "$run_dir/setup/user_config.tcl" }

set ::flow_type "STA"
set stage_name "timing_scenario"

# Determine tool version
set _tool_ver [expr {[info exists ::env(TEMPUS_VERSION)] ? $::env(TEMPUS_VERSION) : {v1.0.0}}]
set cmd_file "$::env(FLOW_DIR)/cmds/STA/cadence/tempus/$_tool_ver/timing_scenario_tempus.tcl"

# Determine test mode
set test_mode false
if {[info exists flow(test_mode)] && $flow(test_mode) eq "true"} { set test_mode true }

puts "INFO: $stage_name for scenario: $scenario_name"

if {$test_mode} {
    puts "INFO: \[TEST MODE\] Bypassing EDA tool invocation"
    puts "INFO: Running timing for scenario: $scenario_name"
    puts "INFO: Command file: $cmd_file"
    if {[file exists $cmd_file]} {
        puts "INFO: +-------------------------------------------------+"
        puts "INFO: |  Command File: [file tail $cmd_file]"
        puts "INFO: |  Scenario:     $scenario_name"
        puts "INFO: |  Tool:         Cadence Tempus"
        puts "INFO: +-------------------------------------------------+"
        set _f [open $cmd_file r]; set _lines [split [read $_f] "\n"]; close $_f
        set _lc 0
        foreach _line $_lines { incr _lc; if {$_lc <= 20} { puts "INFO:   $_line" } }
        if {$_lc > 20} { puts "INFO:   ... ([expr {$_lc - 20}] more lines)" }
        puts "INFO: =================================================="
    } else {
        puts "WARNING: Command file not found: $cmd_file"
    }
    # Create scenario-specific report stubs in test mode
    file mkdir "$run_dir/reports/sta"
    set rpt_stub [open "$run_dir/reports/sta/timing_${scenario_name}_summary.rpt" "w"]
    puts $rpt_stub "# Test mode summary for scenario: $scenario_name"
    puts $rpt_stub "# Generated: [clock format [clock seconds]]"
    puts $rpt_stub "# Tool: Cadence Tempus"
    puts $rpt_stub "Setup WNS: 0.000ns  Hold WNS: 0.000ns"
    close $rpt_stub
    puts "INFO: $stage_name for scenario $scenario_name completed \[TEST MODE\]"
} else {
    if {[file exists $cmd_file]} {
        if {[catch {exec tclsh $cmd_file $scenario_name} result]} {
            puts "ERROR: $stage_name failed for scenario $scenario_name: $result"
            exit 1
        }
        puts $result
    } else {
        puts "ERROR: Command file not found: $cmd_file"
        exit 1
    }
    puts "INFO: $stage_name for scenario $scenario_name completed"
}
