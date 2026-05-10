#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# OMNI FLOW - Setup and Config Expansion Script
# Description: Expands hierarchical setup files (flow_proc hooks) and config files (variables)
# Usage: generate_setup.tcl <flow_type> <node_type> <node_name> <run_dir>
# Generates: run_dir/work/<NODE>/<node_type>/run/setup.tcl
# Generates: run_dir/work/<NODE>/<node_type>/run/config.tcl
# ═══════════════════════════════════════════════════════════════════════════════

# Parse command line arguments
if {$argc != 4} {
    puts "ERROR: Invalid number of arguments"
    puts "Usage: tclsh generate_setup.tcl <flow_type> <node_type> <node_name> <run_dir>"
    puts "  flow_type: SYNTH, PNR"
    puts "  node_type: stage name (init_design, floorplan, placement, cts, route, post_route, signoff, synthesis)"
    puts "  node_name: unique identifier for this node instance"
    puts "  run_dir: run directory containing setup files"
    puts ""
    puts "This script expands hierarchical files into:"
    puts "  <run_dir>/work/<flow_type>/<node_type>/run/setup.tcl (flow_proc hooks)"
    puts "  <run_dir>/work/<flow_type>/<node_type>/run/config.tcl (configuration variables)"
    puts ""
    puts "Setup files contain flow_proc append/prepend hooks that align with command files"
    puts "Config files contain configuration variables for the flow"
    exit 1
}

set flow_type [lindex $argv 0]
set node_type [lindex $argv 1]
set node_name [lindex $argv 2]
set run_dir [lindex $argv 3]

# Validate flow_type
if {$flow_type ni {SYNTH PNR}} {
    puts "ERROR: Invalid flow_type '$flow_type'. Must be SYNTH or PNR"
    exit 1
}

# Define valid node types for each flow
set valid_synth_nodes {synthesis}
set valid_pnr_nodes {init_design inputs floorplan powerplan placement cts route post_route signoff}

if {$flow_type eq "SYNTH" && $node_type ni $valid_synth_nodes} {
    puts "ERROR: Invalid node_type '$node_type' for SYNTH flow"
    puts "Valid SYNTH nodes: [join $valid_synth_nodes {, }]"
    exit 1
}

if {$flow_type eq "PNR" && $node_type ni $valid_pnr_nodes} {
    puts "ERROR: Invalid node_type '$node_type' for PNR flow"
    puts "Valid PNR nodes: [join $valid_pnr_nodes {, }]"
    exit 1
}

# Get script directory and flow directory
set script_dir [file dirname [file normalize [info script]]]
set flow_dir [file dirname $script_dir]

# Source utilities
if {[file exists "$flow_dir/utils/utils.tcl"]} {
    source "$flow_dir/utils/utils.tcl"
}

# Define setup file paths in hierarchical order (SETUP ONLY, NO CONFIG)
proc get_hierarchical_setup_paths {flow_dir run_dir flow_type node_type node_name} {
    set setup_files {}
    
    # Setup files (lowest to highest priority) - flow_proc hooks only
    # 1. Global setup (lowest priority)
    lappend setup_files [list "global_setup" "$flow_dir/setup/setup.tcl"]
    
    # 2. Flow-level node type setup
    lappend setup_files [list "flow_node_type_setup" "$flow_dir/setup/$flow_type/${node_type}_setup.tcl"]
    
    # 3. Run-level global override (applies to all nodes in this run)
    lappend setup_files [list "run_global_override" "$run_dir/setup/override.tcl"]
    
    # 4. Run-level node type override
    lappend setup_files [list "run_node_type_override" "$run_dir/setup/override.${node_type}.tcl"]
    
    # 5. Run-level node name override (highest priority)
    lappend setup_files [list "run_node_name_override" "$run_dir/setup/override_${node_name}.tcl"]
    
    return $setup_files
}

# Define config file paths in hierarchical order (CONFIG VARIABLES ONLY)
proc get_hierarchical_config_paths {flow_dir run_dir flow_type node_type node_name} {
    set config_files {}
    
    # Config files (lowest to highest priority) - configuration variables only
    # 1. Flow-level node type config (lowest priority)
    lappend config_files [list "flow_node_type_config" "$flow_dir/config/$flow_type/${node_type}_config.tcl"]
    
    # 2. Run-level node type config
    lappend config_files [list "run_node_type_config" "$run_dir/config/${node_type}_config.tcl"]
    
    # 3. Run-level node name config (highest priority)
    lappend config_files [list "run_node_name_config" "$run_dir/config/${node_name}_config.tcl"]
    
    return $config_files
}

proc read_file_content {file_path label} {
    if {[file exists $file_path]} {
        set fp [open $file_path r]
        set content [read $fp]
        close $fp
        return [list true $content]
    } else {
        return [list false ""]
    }
}

proc get_flow_procedures {cmd_file_path} {
    set procedures {}
    
    if {![file exists $cmd_file_path]} {
        puts "WARNING: Command file not found: $cmd_file_path"
        return $procedures
    }
    
    # Read the command file and extract flow_proc definitions
    set fp [open $cmd_file_path r]
    set content [read $fp]
    close $fp
    
    # Look for flow_proc definitions
    set lines [split $content "\n"]
    foreach line $lines {
        set line [string trim $line]
        if {[regexp {^flow_proc\s+(\w+)} $line -> proc_name]} {
            lappend procedures $proc_name
        }
    }
    
    return $procedures
}

proc expand_setup_files_only {flow_dir run_dir flow_type node_type node_name} {
    set result ""
    
    # Add header
    append result "#!/usr/bin/env tclsh\n"
    append result "# ═══════════════════════════════════════════════════════════════════════════════\n"
    append result "# OMNI FLOW - Setup Hooks for $flow_type $node_type ($node_name)\n"
    append result "# Generated: [clock format [clock seconds]]\n"
    append result "# Description: flow_proc hooks only (NO configuration variables)\n"
    append result "# ═══════════════════════════════════════════════════════════════════════════════\n\n"
    
    # Add basic logging functions
    append result "# Basic logging functions\n"
    append result "proc handle_info \{msg\} \{ puts \"\\\[INFO\\\] \$msg\" \}\n"
    append result "proc handle_error \{msg\} \{ puts \"\\\[ERROR\\\] \$msg\"; exit 1 \}\n"
    append result "proc handle_warning \{msg\} \{ puts \"\\\[WARNING\\\] \$msg\" \}\n\n"
    
    # Add environment setup (minimal - no config loading)
    append result "# Environment setup\n"
    append result "set FLOW_DIR \"$flow_dir\"\n"
    append result "set ROOT_DIR \"[file dirname $flow_dir]\"\n"
    append result "set RUN_DIR \"$run_dir\"\n"
    append result "set ::env(FLOW_DIR) \$FLOW_DIR\n"
    append result "set ::env(ROOT_DIR) \$ROOT_DIR\n\n"
    
    # Load utilities
    append result "# Load flow utilities\n"
    append result "if \\\{\\[file exists \\\"\\\$FLOW_DIR/utils/utils.tcl\\\"\\\]\\} \\\{\n"
    append result "    source \\\"\\\$FLOW_DIR/utils/utils.tcl\\\"\n"
    append result "\\} else \\\{\n"
    append result "    handle_error \\\"Cannot find flow utilities at \\\$FLOW_DIR/utils/utils.tcl\\\"\n"
    append result "\\}\n\n"
    
    # Declare global arrays (minimal)
    if {$flow_type eq "SYNTH"} {
        append result "# Declare global arrays\n"
        append result "global synth project tech flow\n\n"
    } else {
        append result "# Declare global arrays\n"
        append result "global pnr project tech flow\n\n"
    }
    
    # Add node information
    append result "# Node information\n"
    append result "set ::flow::current_node \"$node_name\"\n"
    append result "set ::flow::current_stage \"$node_type\"\n"
    append result "set ::flow::current_flow \"$flow_type\"\n"
    append result "set ::flow::current_run_dir \"$run_dir\"\n\n"
    
    append result "handle_info \"Setup hooks for $flow_type $node_type ($node_name)\"\n\n"
    
    # Get hierarchical setup file paths (SETUP ONLY)
    set setup_files [get_hierarchical_setup_paths $flow_dir $run_dir $flow_type $node_type $node_name]
    
    # Expand ONLY setup files (flow_proc hooks)
    append result "# ═══════════════════════════════════════════════════════════════════════════════\n"
    append result "# HIERARCHICAL SETUP EXPANSION (flow_proc hooks ONLY)\n"
    append result "# Priority Order: global -> flow/setup -> override.tcl -> override.node_type.tcl -> override_node_name.tcl (highest)\n"
    append result "# ═══════════════════════════════════════════════════════════════════════════════\n\n"
    
    foreach setup_entry $setup_files {
        lassign $setup_entry label file_path
        lassign [read_file_content $file_path $label] exists content
        
        if {$exists} {
            append result "# ───────────────────────────────────────────────────────────────────────────────\n"
            append result "# $label: $file_path\n"
            append result "# ───────────────────────────────────────────────────────────────────────────────\n"
            append result "$content\n\n"
        } else {
            append result "# $label: $file_path (NOT FOUND - SKIPPED)\n\n"
        }
    }
    
    # Add completion message
    append result "# ═══════════════════════════════════════════════════════════════════════════════\n"
    append result "# SETUP HOOKS COMPLETE\n"
    append result "# ═══════════════════════════════════════════════════════════════════════════════\n\n"
    
    append result "handle_info \"Setup hooks expansion complete for $flow_type $node_type ($node_name)\"\n"
    append result "handle_info \"All flow_proc hooks have been applied in priority order\"\n"
    append result "handle_info \"Setup priority: global -> flow -> override.tcl -> override.node_type.tcl -> override_node_name.tcl (highest)\"\n\n"
    
    # Add command file loading
    append result "# Load command file with all flow_proc hooks applied\n"
    append result "if \\\{\\[file exists \\\"\\\$FLOW_DIR/cmds/$flow_type/${node_type}.tcl\\\"\\\]\\} \\\{\n"
    append result "    handle_info \\\"Loading command file: $flow_type/${node_type}.tcl with all hooks applied\\\"\n"
    append result "    source \\\"\\\$FLOW_DIR/cmds/$flow_type/${node_type}.tcl\\\"\n"
    append result "    handle_info \\\"Command file loaded successfully\\\"\n"
    append result "\\} else \\\{\n"
    append result "    handle_error \\\"Command file not found: \\\$FLOW_DIR/cmds/$flow_type/${node_type}.tcl\\\"\n"
    append result "\\}\n\n"
    
    return $result
}

proc expand_config_files_only {flow_dir run_dir flow_type node_type node_name} {
    set result ""
    
    # Add header
    append result "#!/usr/bin/env tclsh\n"
    append result "# ═══════════════════════════════════════════════════════════════════════════════\n"
    append result "# OMNI FLOW - Config Variables for $flow_type $node_type ($node_name)\n"
    append result "# Generated: [clock format [clock seconds]]\n"
    append result "# Description: Configuration variables only (NO flow_proc hooks)\n"
    append result "# ═══════════════════════════════════════════════════════════════════════════════\n\n"
    
    # Add basic logging functions
    append result "# Basic logging functions\n"
    append result "proc handle_info \\{msg\\} \\{ puts \\\"\\\\\\[INFO\\\\\\] \\$msg\\\" \\}\n"
    append result "proc handle_error \\{msg\\} \\{ puts \\\"\\\\\\[ERROR\\\\\\] \\$msg\\\"; exit 1 \\}\n"
    append result "proc handle_warning \\{msg\\} \\{ puts \\\"\\\\\\[WARNING\\\\\\] \\$msg\\\" \\}\n\n"
    
    # Add environment setup
    append result "# Environment setup\n"
    append result "set FLOW_DIR \\\"$flow_dir\\\"\n"
    append result "set ROOT_DIR \\\"[file dirname $flow_dir]\\\"\n"
    append result "set RUN_DIR \\\"$run_dir\\\"\n"
    append result "set ::env(FLOW_DIR) \\$FLOW_DIR\n"
    append result "set ::env(ROOT_DIR) \\$ROOT_DIR\n\n"
    
    # Declare global arrays
    if {$flow_type eq "SYNTH"} {
        append result "# Declare global arrays\n"
        append result "global synth project tech flow\n\n"
    } else {
        append result "# Declare global arrays\n"
        append result "global pnr project tech flow\n\n"
    }
    
    # Add node information
    append result "# Node information\n"
    append result "set ::flow::current_node \\\"$node_name\\\"\n"
    append result "set ::flow::current_stage \\\"$node_type\\\"\n"
    append result "set ::flow::current_flow \\\"$flow_type\\\"\n"
    append result "set ::flow::current_run_dir \\\"$run_dir\\\"\n\n"
    
    append result "handle_info \\\"Config variables for $flow_type $node_type ($node_name)\\\"\n\n"
    
    # Get hierarchical config file paths
    set config_files [get_hierarchical_config_paths $flow_dir $run_dir $flow_type $node_type $node_name]
    
    # Expand config files
    append result "# ═══════════════════════════════════════════════════════════════════════════════\n"
    append result "# HIERARCHICAL CONFIG EXPANSION (configuration variables ONLY)\n"
    append result "# Priority Order: flow/config -> run_dir/config/node_type -> run_dir/config/node_name (highest)\n"
    append result "# ═══════════════════════════════════════════════════════════════════════════════\n\n"
    
    foreach config_entry $config_files {
        lassign $config_entry label file_path
        lassign [read_file_content $file_path $label] exists content
        
        if {$exists} {
            append result "# ───────────────────────────────────────────────────────────────────────────────\n"
            append result "# $label: $file_path\n"
            append result "# ───────────────────────────────────────────────────────────────────────────────\n"
            append result "$content\n\n"
        } else {
            append result "# $label: $file_path (NOT FOUND - SKIPPED)\n\n"
        }
    }
    
    # Add completion message
    append result "# ═══════════════════════════════════════════════════════════════════════════════\n"
    append result "# CONFIG VARIABLES COMPLETE\n"
    append result "# ═══════════════════════════════════════════════════════════════════════════════\n\n"
    
    append result "handle_info \\\"Config variables expansion complete for $flow_type $node_type ($node_name)\\\"\n"
    append result "handle_info \\\"All configuration variables have been loaded in priority order\\\"\n"
    append result "handle_info \\\"Config priority: flow -> run_node_type -> run_node_name (highest)\\\"\n\n"
    
    return $result
}

# Main execution
puts "Expanding setup hooks and config variables for $flow_type $node_type ($node_name)..."
puts "Run directory: $run_dir"
puts "Generating both setup.tcl (flow_proc hooks) and config.tcl (configuration variables)"

# Validate run directory
if {![file exists $run_dir]} {
    puts "ERROR: Run directory does not exist: $run_dir"
    exit 1
}

# Create output directory structure
set output_dir "$run_dir/work/$flow_type/$node_type/run"
file mkdir $output_dir

# Generate expanded content (SETUP HOOKS ONLY)
set expanded_setup_content [expand_setup_files_only $flow_dir $run_dir $flow_type $node_type $node_name]

# Generate expanded content (CONFIG VARIABLES ONLY)
set expanded_config_content [expand_config_files_only $flow_dir $run_dir $flow_type $node_type $node_name]

# Write setup.tcl
set setup_output_file "$output_dir/setup.tcl"
set fp [open $setup_output_file w]
puts $fp $expanded_setup_content
close $fp

# Write config.tcl
set config_output_file "$output_dir/config.tcl"
set fp [open $config_output_file w]
puts $fp $expanded_config_content
close $fp

puts "Setup hooks file generated: $setup_output_file"
puts "Config variables file generated: $config_output_file"
puts ""
puts "Hierarchical Setup Loading Order (flow_proc hooks only):"
puts "1. flow/setup/setup.tcl (global - applies to all nodes)"
puts "2. flow/setup/$flow_type/${node_type}_setup.tcl"
puts "3. $run_dir/setup/override.tcl (applies to all nodes in this run)"
puts "4. $run_dir/setup/override.${node_type}.tcl"
puts "5. $run_dir/setup/override_${node_name}.tcl (highest priority)"
puts ""
puts "Hierarchical Config Loading Order (configuration variables only):"
puts "1. flow/config/$flow_type/${node_type}_config.tcl"
puts "2. $run_dir/config/${node_type}_config.tcl"
puts "3. $run_dir/config/${node_name}_config.tcl (highest priority)"
puts ""
puts "Files generated:"
puts "- setup.tcl: Contains ONLY flow_proc append/prepend hooks"
puts "- config.tcl: Contains ONLY configuration variables"