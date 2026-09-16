#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# Show MMMC Node Scenarios
# Displays hardcoded setup/hold scenarios for each PNR node
# ═══════════════════════════════════════════════════════════════════════════════

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

# Suppress info messages from config loading
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

# Check if node scenarios are configured
if {![info exists mmmc]} {
    puts "ERROR: No node scenarios configured in MMMC config"
    exit 1
}

# Check for specific node request
if {$argc >= 1} {
    set requested_node [lindex $argv 0]
    
    if {![info exists mmmc($requested_node)]} {
        puts "ERROR: Node '$requested_node' not found in MMMC configuration"
        puts "Available nodes: [join [lsort [array names mmmc]] { }]"
        exit 1
    }
    
    # Show specific node details
    puts ""
    puts "═══════════════════════════════════════════════════════════════════════════════"
    puts "MMMC Scenarios for Node: $requested_node"
    puts "═══════════════════════════════════════════════════════════════════════════════"
    
    array set node_info $mmmc($requested_node)
    puts ""
    
    puts "Setup Scenarios ([llength $node_info(setup)]):"
    set counter 1
    foreach scenario $node_info(setup) {
        if {[info exists analysis_views($scenario)]} {
            array set view_info $analysis_views($scenario)
            puts [format "  %2d. %-30s - %s" $counter $scenario $view_info(description)]
        } else {
            puts [format "  %2d. %-30s - (Definition not found)" $counter $scenario]
        }
        incr counter
    }
    
    puts ""
    puts "Hold Scenarios ([llength $node_info(hold)]):"
    set counter 1
    foreach scenario $node_info(hold) {
        if {[info exists analysis_views($scenario)]} {
            array set view_info $analysis_views($scenario)
            puts [format "  %2d. %-30s - %s" $counter $scenario $view_info(description)]
        } else {
            puts [format "  %2d. %-30s - (Definition not found)" $counter $scenario]
        }
        incr counter
    }
    
    puts ""
    
} else {
    # Show summary of all nodes
    puts ""
    puts "═══════════════════════════════════════════════════════════════════════════════"
    puts "MMMC Node Scenario Summary"
    puts "═══════════════════════════════════════════════════════════════════════════════"
    puts ""
    
    foreach node [lsort [array names mmmc]] {
        array set node_info $mmmc($node)
        set setup_count [llength $node_info(setup)]
        set hold_count [llength $node_info(hold)]
        # Calculate unique scenarios manually
        set all_scenarios {}
        foreach scenario [concat $node_info(setup) $node_info(hold)] {
            if {$scenario ni $all_scenarios} {
                lappend all_scenarios $scenario
            }
        }
        set total_unique [llength $all_scenarios]
        
        puts [format "%-12s: %2d setup + %2d hold = %2d total scenarios" $node $setup_count $hold_count $total_unique]
    }
    
    puts "Usage: $argv0 <node_name>  - Show detailed scenarios for specific node"
    puts "Available nodes: [join [lsort [array names mmmc]] { }]"
    puts ""
}