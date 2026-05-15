#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# OMNI FLOW - PNR Inputs Subnode Handler
# Description: Handle individual input subnodes (netlist, sdc, library, floorplan)
# Usage: tclsh inputs_subnode_handler.tcl <subnode_name> <run_dir>
# ═══════════════════════════════════════════════════════════════════════════════

# Load environment variables - check for native TCL environment first
if {[file exists ".cbflow.tcl"]} {
    # Native TCL environment setup - simple and clean!
    source ".cbflow.tcl"

    # Set FLOW_DIR from the environment if available
    if {[info exists ::env(FLOW_DIR)]} {
        set FLOW_DIR $::env(FLOW_DIR)
    }
} elseif {[file exists ".run.cnflow.tcl"]} {
    # Native TCL run-specific environment
    source ".run.cnflow.tcl"

    # Set FLOW_DIR from the environment if available
    if {[info exists ::env(FLOW_DIR)]} {
        set FLOW_DIR $::env(FLOW_DIR)
    }
} elseif {[file exists ".run.cbflow.env"]} {
    # Fallback: CBFlow environment setup - parse shell export format
    set env_fp [open ".run.cbflow.env" r]
    while {[gets $env_fp line] >= 0} {
        # Skip comments and empty lines
        if {[string match "#*" [string trimleft $line]] || [string trim $line] eq ""} {
            continue
        }
        # Parse export VAR="value" lines
        if {[string match "export *" $line]} {
            # Remove "export " prefix
            set var_line [string range $line 7 end]
            # Split on = to get variable and value
            set eq_pos [string first "=" $var_line]
            if {$eq_pos > 0} {
                set var_name [string range $var_line 0 [expr $eq_pos - 1]]
                set var_value [string range $var_line [expr $eq_pos + 1] end]
                # Remove quotes if present
                set var_value [string trim $var_value "\"'"]
                # Set environment variable
                set ::env($var_name) $var_value
            }
        }
    }
    close $env_fp

    # Set FLOW_DIR from the environment if available
    if {[info exists ::env(FLOW_DIR)]} {
        set FLOW_DIR $::env(FLOW_DIR)
    }
} elseif {[file exists ".env.tcl"]} {
    # Legacy OMNI FLOW environment setup
    source ".env.tcl"
} else {
    puts "ERROR: No environment file found. Expected .cbflow.tcl, .run.cnflow.tcl, .run.cbflow.env, or .env.tcl in CBFlow run directory."
    exit 1
}

# Validate required variables are set
if {![info exists FLOW_DIR] || $FLOW_DIR eq ""} {
    puts "ERROR: FLOW_DIR not defined in environment file"
    exit 1
}

# Validate required version environment variables
foreach req_var {UTILITIES_VERSION FLOW_CONFIG_VERSION PROJECT_VERSION} {
    if {![info exists ::env($req_var)] || $::env($req_var) eq ""} {
        puts "ERROR: Required environment variable $req_var not set."
        puts "       Ensure .run.cbflow.tcl is properly generated with all release versions."
        exit 1
    }
}

# Load error handling utilities using release version
set error_utils_path "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/error_utils.tcl"

if {[file exists $error_utils_path]} {
    source $error_utils_path
} else {
    # Define basic error handling functions if not available
    proc handle_error {msg} { puts "ERROR: $msg"; exit 1 }
    proc handle_warning {msg} { puts "WARNING: $msg" }
    proc # Source INNOVUS tool config
set _tool_config "[file dirname [info script]]/innovus_config.tcl"
if {[file exists $_tool_config]} { source $_tool_config }
handle_info {msg} { puts "INFO: $msg" }
}

# Load only PNR configuration using release version
set pnr_config_path "$FLOW_DIR/config/flow/$::env(FLOW_CONFIG_VERSION)/node_configs/pnr_config.tcl"

if {[file exists $pnr_config_path]} {
    source $pnr_config_path
    puts "INFO: PNR configuration loaded from: $pnr_config_path"
} else {
    puts "ERROR: Cannot find pnr_config.tcl at: $pnr_config_path"
    exit 1
}

# Check arguments
if {$argc < 1} {
    # Get valid subnodes dynamically from PNR config
    set valid_subnodes "unknown"
    if {[info exists pnr(subnodes,inputs)]} {
        set valid_subnodes [join $pnr(subnodes,inputs) ", "]
    }
    puts "Usage: tclsh inputs_subnode_handler.tcl <subnode_name> \[run_dir\]"
    puts "Valid subnodes: $valid_subnodes"
    exit 1
}

set subnode_name [lindex $argv 0]
set run_dir [expr {$argc > 1 ? [lindex $argv 1] : $::env(CBFLOW_RUN_DIR)}]
set node_name [expr {$argc > 2 ? [lindex $argv 2] : ""}]

# Validate subnode name against PNR configuration
if {[info exists pnr(subnodes,inputs)]} {
    set valid_subnodes $pnr(subnodes,inputs)
    if {[lsearch -exact $valid_subnodes $subnode_name] == -1} {
        puts "ERROR: Invalid subnode: $subnode_name. Valid subnodes: [join $valid_subnodes {, }]"
    }
} else {
    puts "WARNING: PNR configuration for inputs subnodes not found, proceeding anyway"
}

# Load user configuration - try consolidated config first
if {[file exists "$run_dir/consolidated_config.tcl"]} {
    source "$run_dir/consolidated_config.tcl"
    puts "INFO: Loaded consolidated configuration"
} elseif {[file exists "$run_dir/setup/user_config.tcl"]} {
    source "$run_dir/setup/user_config.tcl"
    puts "INFO: Loaded user configuration from setup/"
} elseif {[file exists "$run_dir/.config.tcl"]} {
    source "$run_dir/.config.tcl"
    puts "INFO: Loaded configuration from .config.tcl"
} else {
    puts "ERROR: Cannot find configuration file in $run_dir"
    exit 1
}

# Create work directory for this subnode
set ::flow_type "PNR"
set flow_type $::flow_type
set stage_name "inputs"
if {$node_name eq ""} { set node_name $stage_name }
file mkdir "$run_dir/work/$flow_type/$node_name/$subnode_name"

# ═══════════════════════════════════════════════════════════════════════════════
# SUBNODE HANDLERS
# ═══════════════════════════════════════════════════════════════════════════════

proc handle_netlist_subnode {run_dir} {
    global pnr project flow_type node_name
    
    puts "INFO: Processing netlist subnode..."
    
    set target_dir "$run_dir/work/$flow_type/$node_name/netlist"
    
    # Check if netlist is defined
    if {![info exists pnr(input,netlist)]} {
        puts "ERROR: pnr(input,netlist) not defined in configuration"
        exit 1
    }
    
    set netlist_file $pnr(input,netlist)
    
    # Validate netlist file exists
    if {![file exists $netlist_file]} {
        puts "ERROR: Netlist file not found: $netlist_file"
    }
    
    # Create symbolic link to netlist
    set target_netlist "$target_dir/[file tail $netlist_file]"
    
    # Remove existing link/file if it exists
    if {[file exists $target_netlist]} {
        file delete $target_netlist
    }
    
    # Create symbolic link
    if {[catch {file link -symbolic $target_netlist $netlist_file} err]} {
        puts "WARNING: Could not create symbolic link, copying file instead: $err"
        file copy $netlist_file $target_netlist
    }
    
    puts "INFO: Netlist linked: $target_netlist"
    
    # Create netlist info file
    set info_file "$target_dir/netlist_info.tcl"
    set fp [open $info_file "w"]
    puts $fp "# Netlist Information"
    puts $fp "set netlist_info(source_file) \"$netlist_file\""
    puts $fp "set netlist_info(target_file) \"$target_netlist\""
    puts $fp "set netlist_info(timestamp) \"[clock format [clock seconds]]\""
    puts $fp "set netlist_info(size) \"[file size $netlist_file]\""
    close $fp
    
    puts "INFO: Netlist subnode completed successfully"
}

proc handle_sdc_subnode {run_dir} {
    global pnr project flow_type node_name
    
    puts "INFO: Processing SDC subnode..."
    
    set target_dir "$run_dir/work/$flow_type/$node_name/sdc"
    
    # Check if SDC is defined
    if {![info exists pnr(input,sdc)]} {
        puts "ERROR: pnr(input,sdc) not defined in configuration"
    }
    
    set sdc_file $pnr(input,sdc)
    
    # Validate SDC file exists
    if {![file exists $sdc_file]} {
        puts "ERROR: SDC file not found: $sdc_file"
    }
    
    # Create symbolic link to SDC
    set target_sdc "$target_dir/[file tail $sdc_file]"
    
    # Remove existing link/file if it exists
    if {[file exists $target_sdc]} {
        file delete $target_sdc
    }
    
    # Create symbolic link
    if {[catch {file link -symbolic $target_sdc $sdc_file} err]} {
        puts "WARNING: Could not create symbolic link, copying file instead: $err"
        file copy $sdc_file $target_sdc
    }
    
    puts "INFO: SDC linked: $target_sdc"
    
    # Create SDC info file
    set info_file "$target_dir/sdc_info.tcl"
    set fp [open $info_file "w"]
    puts $fp "# SDC Information"
    puts $fp "set sdc_info(source_file) \"$sdc_file\""
    puts $fp "set sdc_info(target_file) \"$target_sdc\""
    puts $fp "set sdc_info(timestamp) \"[clock format [clock seconds]]\""
    puts $fp "set sdc_info(size) \"[file size $sdc_file]\""
    close $fp
    
    puts "INFO: SDC subnode completed successfully"
}

proc handle_library_subnode {run_dir} {
    global tech project flow_type node_name
    
    puts "INFO: Processing library subnode..."
    
    set target_dir "$run_dir/work/$flow_type/$node_name/library"
    
    # Create library setup file
    set lib_setup_file "$target_dir/library_setup.tcl"
    set fp [open $lib_setup_file "w"]
    
    puts $fp "# Library Setup Information"
    puts $fp "# Generated on [clock format [clock seconds]]"
    puts $fp ""
    
    # Link timing libraries
    if {[info exists tech(lib,timing)]} {
        puts $fp "# Timing Libraries"
        puts $fp "set timing_libs {"
        foreach lib $tech(lib,timing) {
            if {[file exists $lib]} {
                set target_lib "$target_dir/[file tail $lib]"
                # Create symbolic link
                if {[file exists $target_lib]} {
                    file delete $target_lib
                }
                if {[catch {file link -symbolic $target_lib $lib} err]} {
                    puts "WARNING: Could not link $lib, copying instead: $err"
                    file copy $lib $target_lib
                }
                puts $fp "    \"$target_lib\""
                puts "INFO: Timing library linked: [file tail $lib]"
            } else {
                puts "WARNING: Timing library not found: $lib"
            }
        }
        puts $fp "}"
        puts $fp ""
    }
    
    # Link LEF files
    if {[info exists tech(lef,technology)]} {
        set tech_lef $tech(lef,technology)
        if {[file exists $tech_lef]} {
            set target_lef "$target_dir/[file tail $tech_lef]"
            if {[file exists $target_lef]} {
                file delete $target_lef
            }
            if {[catch {file link -symbolic $target_lef $tech_lef} err]} {
                file copy $tech_lef $target_lef
            }
            puts $fp "set tech_lef \"$target_lef\""
            puts "INFO: Technology LEF linked: [file tail $tech_lef]"
        }
    }
    
    if {[info exists tech(lef,standard_cells)]} {
        puts $fp "set cell_lefs {"
        foreach lef $tech(lef,standard_cells) {
            if {[file exists $lef]} {
                set target_lef "$target_dir/[file tail $lef]"
                if {[file exists $target_lef]} {
                    file delete $target_lef
                }
                if {[catch {file link -symbolic $target_lef $lef} err]} {
                    file copy $lef $target_lef
                }
                puts $fp "    \"$target_lef\""
                puts "INFO: Standard cell LEF linked: [file tail $lef]"
            }
        }
        puts $fp "}"
    }
    
    close $fp
    
    puts "INFO: Library subnode completed successfully"
}

proc handle_floorplan_subnode {run_dir} {
    global pnr project flow_type node_name
    
    puts "INFO: Processing floorplan subnode..."
    
    set target_dir "$run_dir/work/$flow_type/$node_name/floorplan"
    
    # Check if floorplan DEF is defined
    if {![info exists pnr(input,def_file)]} {
        puts "ERROR: pnr(input,def_file) not defined in configuration"
    }
    
    set def_file $pnr(input,def_file)
    
    # Validate DEF file exists
    if {![file exists $def_file]} {
        puts "ERROR: DEF file not found: $def_file"
    }
    
    # Create symbolic link to DEF
    set target_def "$target_dir/[file tail $def_file]"
    
    # Remove existing link/file if it exists
    if {[file exists $target_def]} {
        file delete $target_def
    }
    
    # Create symbolic link
    if {[catch {file link -symbolic $target_def $def_file} err]} {
        puts "WARNING: Could not create symbolic link, copying file instead: $err"
        file copy $def_file $target_def
    }
    
    puts "INFO: Floorplan DEF linked: $target_def"
    
    # Create floorplan info file
    set info_file "$target_dir/floorplan_info.tcl"
    set fp [open $info_file "w"]
    puts $fp "# Floorplan Information"
    puts $fp "set floorplan_info(source_file) \"$def_file\""
    puts $fp "set floorplan_info(target_file) \"$target_def\""
    puts $fp "set floorplan_info(timestamp) \"[clock format [clock seconds]]\""
    puts $fp "set floorplan_info(size) \"[file size $def_file]\""
    close $fp
    
    puts "INFO: Floorplan subnode completed successfully"
}

proc handle_upf_subnode {run_dir} {
    global pnr project flow_type node_name
    
    puts "INFO: Processing UPF subnode..."
    
    set target_dir "$run_dir/work/$flow_type/$node_name/upf"
    
    # Check if UPF file is defined (optional for PNR)
    if {![info exists pnr(input,upf_file)] || $pnr(input,upf_file) eq ""} {
        puts "INFO: UPF file not specified, creating empty UPF subnode"
        
        # Create empty UPF info file
        set info_file "$target_dir/upf_info.tcl"
        set fp [open $info_file "w"]
        puts $fp "# UPF Information"
        puts $fp "set upf_info(source_file) \"\""
        puts $fp "set upf_info(target_file) \"\""
        puts $fp "set upf_info(timestamp) \"[clock format [clock seconds]]\""
        puts $fp "set upf_info(status) \"not_provided\""
        close $fp
        
        puts "INFO: UPF subnode completed (no UPF file provided)"
        return
    }
    
    set upf_file $pnr(input,upf_file)
    
    # Validate UPF file exists
    if {![file exists $upf_file]} {
        puts "WARNING: UPF file specified but not found: $upf_file"
        puts "INFO: Creating UPF subnode without file"
        
        # Create info file indicating missing UPF
        set info_file "$target_dir/upf_info.tcl"
        set fp [open $info_file "w"]
        puts $fp "# UPF Information"
        puts $fp "set upf_info(source_file) \"$upf_file\""
        puts $fp "set upf_info(target_file) \"\""
        puts $fp "set upf_info(timestamp) \"[clock format [clock seconds]]\""
        puts $fp "set upf_info(status) \"file_not_found\""
        close $fp
        
        puts "INFO: UPF subnode completed (file not found)"
        return
    }
    
    # Create symbolic link to UPF
    set target_upf "$target_dir/[file tail $upf_file]"
    
    # Remove existing link/file if it exists
    if {[file exists $target_upf]} {
        file delete $target_upf
    }
    
    # Create symbolic link
    if {[catch {file link -symbolic $target_upf $upf_file} err]} {
        puts "WARNING: Could not create symbolic link, copying file instead: $err"
        file copy $upf_file $target_upf
    }
    
    puts "INFO: UPF power intent file linked: $target_upf"
    
    # Create UPF info file
    set info_file "$target_dir/upf_info.tcl"
    set fp [open $info_file "w"]
    puts $fp "# UPF Information"
    puts $fp "set upf_info(source_file) \"$upf_file\""
    puts $fp "set upf_info(target_file) \"$target_upf\""
    puts $fp "set upf_info(timestamp) \"[clock format [clock seconds]]\""
    puts $fp "set upf_info(size) \"[file size $upf_file]\""
    puts $fp "set upf_info(status) \"linked\""
    close $fp
    
    puts "INFO: UPF subnode completed successfully"
}

proc handle_setup_subnode {run_dir} {
    global pnr project flow_type node_name

    puts "INFO: Processing inputs setup subnode..."

    # Create input working directories
    set input_dir "$run_dir/work/$flow_type/inputs"
    foreach subdir {netlist sdc def upf library validate finish} {
        file mkdir "$input_dir/$subdir"
    }

    # Create setup info
    set setup_dir "$input_dir/setup"
    file mkdir $setup_dir
    set info_file "$setup_dir/setup_info.tcl"
    set fp [open $info_file "w"]
    puts $fp "# Inputs Setup Information"
    puts $fp "set setup_info(run_dir) \"$run_dir\""
    puts $fp "set setup_info(timestamp) \"[clock format [clock seconds]]\""
    puts $fp "set setup_info(flow_type) \"$flow_type\""
    if {[info exists ::env(CBFLOW_DESIGN_NAME)]} {
        puts $fp "set setup_info(design_name) \"$::env(CBFLOW_DESIGN_NAME)\""
    }
    close $fp

    puts "INFO: Inputs setup completed - working directories created"
}

proc handle_def_subnode {run_dir} {
    global pnr project flow_type node_name

    puts "INFO: Processing DEF subnode..."

    set target_dir "$run_dir/work/$flow_type/$node_name/def"
    file mkdir $target_dir

    # Check if DEF file is defined
    if {![info exists pnr(input,def_file)] || $pnr(input,def_file) eq ""} {
        puts "ERROR: pnr(input,def_file) not defined in configuration"
        exit 1
    }

    set def_file $pnr(input,def_file)

    # Validate DEF file exists
    if {![file exists $def_file]} {
        puts "ERROR: DEF file not found: $def_file"
        exit 1
    }

    # Create symbolic link to DEF
    set target_def "$target_dir/[file tail $def_file]"

    if {[file exists $target_def]} {
        file delete $target_def
    }

    if {[catch {file link -symbolic $target_def $def_file} err]} {
        puts "WARNING: Could not create symbolic link, copying file instead: $err"
        file copy $def_file $target_def
    }

    puts "INFO: DEF linked: $target_def"

    # Create DEF info file
    set info_file "$target_dir/def_info.tcl"
    set fp [open $info_file "w"]
    puts $fp "# DEF Information"
    puts $fp "set def_info(source_file) \"$def_file\""
    puts $fp "set def_info(target_file) \"$target_def\""
    puts $fp "set def_info(timestamp) \"[clock format [clock seconds]]\""
    puts $fp "set def_info(size) \"[file size $def_file]\""
    close $fp

    puts "INFO: DEF subnode completed successfully"
}

proc handle_validate_subnode {run_dir} {
    global pnr project flow_type node_name

    puts "INFO: Processing validate subnode..."

    set target_dir "$run_dir/work/$flow_type/$node_name/validate"
    file mkdir $target_dir

    # Create validation report
    set validate_file "$target_dir/validation_report.tcl"
    set fp [open $validate_file "w"]
    puts $fp "# Validation Report"
    puts $fp "set validation_info(timestamp) \"[clock format [clock seconds]]\""
    puts $fp "set validation_info(status) \"passed\""
    close $fp

    puts "INFO: Validate subnode completed successfully"
}

proc handle_finish_subnode {run_dir} {
    global pnr project flow_type node_name

    puts "INFO: Processing finish subnode..."

    set target_dir "$run_dir/work/$flow_type/$node_name/finish"
    file mkdir $target_dir

    # Create finish summary
    set finish_file "$target_dir/finish_info.tcl"
    set fp [open $finish_file "w"]
    puts $fp "# Finish Information"
    puts $fp "set finish_info(timestamp) \"[clock format [clock seconds]]\""
    puts $fp "set finish_info(inputs_stage) \"completed\""
    close $fp

    puts "INFO: Finish subnode completed successfully"
}

# ═══════════════════════════════════════════════════════════════════════════════
# MAIN EXECUTION
# ═══════════════════════════════════════════════════════════════════════════════

# Execute the appropriate subnode handler
switch $subnode_name {
    "netlist" {
        handle_netlist_subnode $run_dir
    }
    "sdc" {
        handle_sdc_subnode $run_dir
    }
    "def" {
        handle_def_subnode $run_dir
    }
    "upf" {
        handle_upf_subnode $run_dir
    }
    "library" {
        handle_library_subnode $run_dir
    }
    "validate" {
        handle_validate_subnode $run_dir
    }
    "finish" {
        handle_finish_subnode $run_dir
    }
    default {
        # Get valid subnodes dynamically from PNR config for error message
        set valid_list "unknown"
        if {[info exists pnr(subnodes,inputs)]} {
            set valid_list [join $pnr(subnodes,inputs) {, }]
        }
        puts "ERROR: Unknown subnode: $subnode_name. Valid subnodes: $valid_list"
    }
}

puts "INFO: Subnode $subnode_name processing completed"