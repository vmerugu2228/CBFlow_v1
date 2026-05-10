#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# Show MMMC Scenarios
# Displays available scenarios for specified type
# ═══════════════════════════════════════════════════════════════════════════════

if {$argc < 1} {
    puts stderr "Usage: $argv0 <scenario_type>"
    puts stderr "  scenario_type: setup, hold, power, signoff, all"
    exit 1
}

set scenario_type [lindex $argv 0]

# Use environment variable for FLOW_DIR instead of calculating
if {[info exists ::env(FLOW_DIR)]} {
    set FLOW_DIR $::env(FLOW_DIR)
} else {
    # Fallback calculation with warning
    set script_dir [file dirname [file normalize [info script]]]
    set FLOW_DIR [file dirname $script_dir]
    puts "WARNING: FLOW_DIR not found in environment, using calculated path: $FLOW_DIR"
}

# Source MMMC configuration
set mmmc_config_file "$FLOW_DIR/config/mmmc_config.tcl"
if {![file exists $mmmc_config_file]} {
    puts "ERROR: MMMC config file not found: $mmmc_config_file"
    exit 1
}

# Suppress info messages from config loading by redirecting puts
rename puts puts_original
proc puts {args} {
    if {[llength $args] == 1 && [string match "INFO:*" [lindex $args 0]]} {
        return
    }
    return [uplevel 1 puts_original $args]
}
source $mmmc_config_file
rename puts ""
rename puts_original puts

# Check if the requested scenario type exists
if {![info exists mmmc_scenario_sets($scenario_type)]} {
    puts "ERROR: Invalid scenario type '$scenario_type'"
    puts "Available types: [join [array names mmmc_scenario_sets] { }]"
    exit 1
}

# Get scenario information
array set set_info $mmmc_scenario_sets($scenario_type)
set scenarios $set_info(scenarios)
set description $set_info(description)

# Display scenario information
puts ""
puts "Description: $description"
puts "Scenario Count: [llength $scenarios] scenarios"
puts ""

set counter 1
foreach scenario $scenarios {
    if {[info exists analysis_views($scenario)]} {
        array set view_info $analysis_views($scenario)
        puts [format "%2d. %-30s - %s" $counter $scenario $view_info(description)]
    } else {
        puts [format "%2d. %-30s - (Definition not found)" $counter $scenario]
    }
    incr counter
}

puts ""
puts "Note: These scenarios can be enabled in PNR command files using:"
puts "      set mmmc_scenarios_enabled {[join $scenarios { }]}"
puts ""