#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# OMNI FLOW - FP Inputs Subnode Handler
# Description: Handle individual input subnodes (netlist, sdc, upf)
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
foreach req_var {UTILITIES_VERSION FLOW_CONFIG_VERSION} {
    if {![info exists ::env($req_var)] || $::env($req_var) eq ""} {
        puts "ERROR: Required environment variable $req_var not set."
        puts "       Ensure .run.cbflow.tcl is properly generated with all release versions."
        exit 1
    }
}

# Load utilities using release version
set utils_path "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

if {[file exists $utils_path]} {
    source $utils_path
} else {
    puts "ERROR: Cannot find utils.tcl at: $utils_path"
    exit 1
}

# Load flow configuration using release version
set flow_config_path "$FLOW_DIR/config/flow/$::env(FLOW_CONFIG_VERSION)/flow_config.tcl"

if {[file exists $flow_config_path]} {
    source $flow_config_path
} else {
    puts "ERROR: Cannot find flow_config.tcl at: $flow_config_path"
    exit 1
}

# Check arguments
if {$argc < 1} {
    # Get valid subnodes dynamically from flow config
    set valid_subnodes "unknown"
    if {[info exists fp(subnodes,inputs)]} {
        set valid_subnodes [join $fp(subnodes,inputs) ", "]
    }
    puts "Usage: tclsh inputs_subnode_handler.tcl <subnode_name> \[run_dir\]"
    puts "Valid subnodes: $valid_subnodes"
    exit 1
}

set subnode_name [lindex $argv 0]
set run_dir [expr {$argc > 1 ? [lindex $argv 1] : $::env(CBFLOW_RUN_DIR)}]

# Validate subnode name against flow configuration
if {[info exists fp(subnodes,inputs)]} {
    set valid_subnodes $fp(subnodes,inputs)
    if {[lsearch -exact $valid_subnodes $subnode_name] == -1} {
        handle_error "Invalid subnode: $subnode_name. Valid subnodes: [join $valid_subnodes {, }]"
    }
    handle_info "Subnode validation passed: $subnode_name"
} else {
    handle_warning "Flow configuration for FP inputs subnodes not found, loading from config"
    # Load subnodes from centralized config
    set allowed_subnodes [::CBFlow::Config::get_subnodes "FP" "inputs"]
    if {$allowed_subnodes eq ""} {
        set allowed_subnodes {setup netlist sdc def upf library validate finish}
    }
    if {[lsearch -exact $allowed_subnodes $subnode_name] == -1} {
        handle_error "Unknown subnode: $subnode_name. Expected one of: [join $allowed_subnodes {, }]"
    }
}

# Load user configuration
if {[file exists "$run_dir/setup/user_config.tcl"]} {
    source "$run_dir/setup/user_config.tcl"
} elseif {[file exists "$run_dir/.config.tcl"]} {
    source "$run_dir/.config.tcl"
} else {
    handle_error "Cannot find configuration file in $run_dir"
}

# Create work directory for this subnode
set ::flow_type "FP"
set flow_type $::flow_type
file mkdir "$run_dir/work/$flow_type/inputs/$subnode_name"

# ═══════════════════════════════════════════════════════════════════════════════
# SUBNODE HANDLERS
# ═══════════════════════════════════════════════════════════════════════════════

proc handle_netlist_subnode {run_dir} {
    global fp project flow flow_type

    handle_info "Processing netlist subnode..."

    set target_dir "$run_dir/work/$flow_type/inputs/netlist"

    # Check if netlist is defined directly or via synthesis run
    set netlist_file ""
    if {[info exists fp(input,netlist)]} {
        set netlist_file $fp(input,netlist)
    } elseif {[info exists fp(input,synth_run)]} {
        # Resolve netlist from synthesis run
        set synth_run $fp(input,synth_run)
        set workspace_dir [file dirname $run_dir]
        set synth_run_dir "$workspace_dir/P0_run_SYNTH_$synth_run"
        set netlist_file "$synth_run_dir/results/synth/netlist/${flow(design_name)}.v"
        handle_info "Resolving netlist from synthesis run: $synth_run"
        handle_info "Expected netlist path: $netlist_file"
    } else {
        handle_error "Neither fp(input,netlist) nor fp(input,synth_run) is defined in configuration"
    }
    
    # Validate netlist file exists
    if {![file exists $netlist_file]} {
        handle_error "Netlist file not found: $netlist_file"
    }
    
    # Create symbolic link to netlist
    set target_netlist "$target_dir/[file tail $netlist_file]"
    
    # Remove existing link/file if it exists
    if {[file exists $target_netlist]} {
        file delete $target_netlist
    }
    
    # Create symbolic link
    if {[catch {file link -symbolic $target_netlist $netlist_file} err]} {
        handle_warning "Could not create symbolic link, copying file instead: $err"
        file copy $netlist_file $target_netlist
    }
    
    handle_info "Netlist linked: $target_netlist"
    
    # Create netlist info file
    set info_file "$target_dir/netlist_info.tcl"
    set netlist_fp [open $info_file "w"]
    puts $netlist_fp "# Netlist Information"
    puts $netlist_fp "set netlist_info(source_file) \"$netlist_file\""
    puts $netlist_fp "set netlist_info(target_file) \"$target_netlist\""
    puts $netlist_fp "set netlist_info(timestamp) \"[clock format [clock seconds]]\""
    puts $netlist_fp "set netlist_info(size) \"[file size $netlist_file]\""
    close $netlist_fp
    
    handle_info "Netlist subnode completed successfully"
}

proc handle_sdc_subnode {run_dir} {
    global fp project flow flow_type

    handle_info "Processing SDC subnode..."

    set target_dir "$run_dir/work/$flow_type/inputs/sdc"

    # Check if SDC is defined directly or via release tag
    set sdc_file ""
    if {[info exists fp(input,sdc)]} {
        set sdc_file $fp(input,sdc)
    } elseif {[info exists fp(input,sdc_func_file)]} {
        set sdc_file $fp(input,sdc_func_file)
        handle_info "Using functional SDC file: $sdc_file"
    } elseif {[info exists fp(input,sdc_release_tag)]} {
        # Load release configuration
        set config_root [file dirname [file dirname [file dirname [file dirname $run_dir]]]]
        source "$config_root/core/config/flow/$::env(PROJECT_VERSION)/release_config.tcl"

        # Resolve SDC from release tag
        set sdc_tag $fp(input,sdc_release_tag)
        set sdc_mode [expr {[info exists fp(sdc_mode)] ? $fp(sdc_mode) : "func"}]
        set sdc_file [get_release_file_path "constraints" $sdc_tag $flow(design_name) $sdc_mode]
        handle_info "Resolving SDC from release tag: $sdc_tag (mode: $sdc_mode)"
        handle_info "Expected SDC path: $sdc_file"
    } else {
        handle_error "No SDC input method specified (sdc_func_file, sdc_release_tag, or sdc_release_dir)"
    }
    
    # Validate SDC file exists
    if {![file exists $sdc_file]} {
        handle_error "SDC file not found: $sdc_file"
    }
    
    # Create symbolic link to SDC
    set target_sdc "$target_dir/[file tail $sdc_file]"
    
    # Remove existing link/file if it exists
    if {[file exists $target_sdc]} {
        file delete $target_sdc
    }
    
    # Create symbolic link
    if {[catch {file link -symbolic $target_sdc $sdc_file} err]} {
        handle_warning "Could not create symbolic link, copying file instead: $err"
        file copy $sdc_file $target_sdc
    }
    
    handle_info "SDC linked: $target_sdc"
    
    # Create SDC info file
    set info_file "$target_dir/sdc_info.tcl"
    set sdc_fp [open $info_file "w"]
    puts $sdc_fp "# SDC Information"
    puts $sdc_fp "set sdc_info(source_file) \"$sdc_file\""
    puts $sdc_fp "set sdc_info(target_file) \"$target_sdc\""
    puts $sdc_fp "set sdc_info(timestamp) \"[clock format [clock seconds]]\""
    puts $sdc_fp "set sdc_info(size) \"[file size $sdc_file]\""
    close $sdc_fp
    
    handle_info "SDC subnode completed successfully"
}

proc handle_upf_subnode {run_dir} {
    global fp project flow flow_type

    handle_info "Processing UPF subnode..."

    set target_dir "$run_dir/work/$flow_type/inputs/upf"

    # Check if UPF file is defined (optional for FP)
    set upf_file ""
    if {[info exists fp(input,upf_file)] && $fp(input,upf_file) ne ""} {
        set upf_file $fp(input,upf_file)
    } elseif {[info exists fp(input,upf_release_tag)]} {
        # Load release configuration
        set config_root [file dirname [file dirname [file dirname [file dirname $run_dir]]]]
        source "$config_root/core/config/flow/$::env(PROJECT_VERSION)/release_config.tcl"

        # Resolve UPF from release tag
        set upf_tag $fp(input,upf_release_tag)
        set upf_file [get_release_file_path "power" $upf_tag $flow(design_name)]
        handle_info "Resolving UPF from release tag: $upf_tag"
        handle_info "Expected UPF path: $upf_file"
    } else {
        handle_info "UPF file not specified, creating empty UPF subnode"

        # Create empty UPF info file
        set info_file "$target_dir/upf_info.tcl"
        set upf_fp [open $info_file "w"]
        puts $upf_fp "# UPF Information"
        puts $upf_fp "set upf_info(source_file) \"\""
        puts $upf_fp "set upf_info(target_file) \"\""
        puts $upf_fp "set upf_info(timestamp) \"[clock format [clock seconds]]\""
        puts $upf_fp "set upf_info(status) \"not_provided\""
        close $upf_fp

        handle_info "UPF subnode completed (no UPF file provided)"
        return
    }

    # Validate UPF file exists
    if {![file exists $upf_file]} {
        handle_warning "UPF file specified but not found: $upf_file"
        handle_info "Creating UPF subnode without file"

        # Create info file indicating missing UPF
        set info_file "$target_dir/upf_info.tcl"
        set upf_fp [open $info_file "w"]
        puts $upf_fp "# UPF Information"
        puts $upf_fp "set upf_info(source_file) \"$upf_file\""
        puts $upf_fp "set upf_info(target_file) \"\""
        puts $upf_fp "set upf_info(timestamp) \"[clock format [clock seconds]]\""
        puts $upf_fp "set upf_info(status) \"file_not_found\""
        close $upf_fp

        handle_info "UPF subnode completed (file not found)"
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
        handle_warning "Could not create symbolic link, copying file instead: $err"
        file copy $upf_file $target_upf
    }

    handle_info "UPF power intent file linked: $target_upf"

    # Create UPF info file
    set info_file "$target_dir/upf_info.tcl"
    set upf_fp [open $info_file "w"]
    puts $upf_fp "# UPF Information"
    puts $upf_fp "set upf_info(source_file) \"$upf_file\""
    puts $upf_fp "set upf_info(target_file) \"$target_upf\""
    puts $upf_fp "set upf_info(timestamp) \"[clock format [clock seconds]]\""
    puts $upf_fp "set upf_info(size) \"[file size $upf_file]\""
    puts $upf_fp "set upf_info(status) \"linked\""
    close $upf_fp

    handle_info "UPF subnode completed successfully"
}

proc handle_setup_subnode {run_dir} {
    global fp project flow_type

    handle_info "Processing setup subnode - generating consolidated config.tcl and setup.tcl..."

    # Create working directory for consolidated files
    set target_dir "$run_dir/work/$flow_type/inputs/run"
    file mkdir $target_dir

    # Determine flow parameters
    set flow_type "FP"
    set node_type "inputs"
    set node_name "inputs"

    # Validate GENERATION_VERSION is set
    if {![info exists ::env(GENERATION_VERSION)] || $::env(GENERATION_VERSION) eq ""} {
        handle_error "GENERATION_VERSION not set. Ensure .run.cbflow.tcl is properly generated."
        return
    }
    set generate_script "$::env(FLOW_DIR)/utils/generation/$::env(GENERATION_VERSION)/generate_setup.tcl"

    if {![file exists $generate_script]} {
        handle_error "Generate setup script not found: $generate_script"
        return
    }

    handle_info "Calling generate_setup.tcl to create consolidated configuration files..."
    handle_info "Command: tclsh $generate_script $flow_type $node_type $node_name $run_dir"

    # Execute generate_setup.tcl to create consolidated config.tcl and setup.tcl
    if {[catch {exec tclsh $generate_script $flow_type $node_type $node_name $run_dir} result]} {
        handle_error "Failed to generate setup files: $result"
        return
    }

    handle_info "Generate setup result: $result"

    # Verify that the files were created
    set config_file "$target_dir/config.tcl"
    set setup_file "$target_dir/setup.tcl"

    if {[file exists $config_file]} {
        handle_info "✓ Consolidated config.tcl created: $config_file"
    } else {
        handle_warning "✗ config.tcl not found: $config_file"
    }

    if {[file exists $setup_file]} {
        handle_info "✓ Consolidated setup.tcl created: $setup_file"
    } else {
        handle_warning "✗ setup.tcl not found: $setup_file"
    }

    # Create legacy setup info file for backward compatibility
    set legacy_target_dir "$run_dir/work/$flow_type/inputs/setup"
    file mkdir $legacy_target_dir
    set info_file "$legacy_target_dir/setup_info.tcl"
    set setup_fp [open $info_file "w"]
    puts $setup_fp "# Setup Information - Legacy Compatibility"
    puts $setup_fp "set setup_info(timestamp) \"[clock format [clock seconds]]\""
    puts $setup_fp "set setup_info(flow_type) \"FP\""
    puts $setup_fp "set setup_info(config_file) \"$config_file\""
    puts $setup_fp "set setup_info(setup_file) \"$setup_file\""
    puts $setup_fp "set setup_info(status) \"consolidated\""
    close $setup_fp

    handle_info "Setup subnode completed successfully - consolidated configuration files generated"
}

proc handle_def_subnode {run_dir} {
    global fp project flow_type

    handle_info "Processing DEF subnode..."

    set target_dir "$run_dir/work/$flow_type/inputs/def"

    # Check if DEF file is defined (optional for FP)
    if {![info exists fp(input,def_file)] || $fp(input,def_file) eq ""} {
        handle_info "DEF file not specified, creating empty DEF subnode"

        # Create empty DEF info file
        set info_file "$target_dir/def_info.tcl"
        set def_fp [open $info_file "w"]
        puts $def_fp "# DEF Information"
        puts $def_fp "set def_info(source_file) \"\""
        puts $def_fp "set def_info(target_file) \"\""
        puts $def_fp "set def_info(timestamp) \"[clock format [clock seconds]]\""
        puts $def_fp "set def_info(status) \"not_provided\""
        close $def_fp

        handle_info "DEF subnode completed (no DEF file provided)"
        return
    }

    set def_file $fp(input,def_file)

    # Validate DEF file exists
    if {![file exists $def_file]} {
        handle_warning "DEF file specified but not found: $def_file"
        handle_info "Creating DEF subnode without file"

        # Create info file indicating missing DEF
        set info_file "$target_dir/def_info.tcl"
        set def_fp [open $info_file "w"]
        puts $def_fp "# DEF Information"
        puts $def_fp "set def_info(source_file) \"$def_file\""
        puts $def_fp "set def_info(target_file) \"\""
        puts $def_fp "set def_info(timestamp) \"[clock format [clock seconds]]\""
        puts $def_fp "set def_info(status) \"file_not_found\""
        close $def_fp

        handle_info "DEF subnode completed (file not found)"
        return
    }

    # Create symbolic link to DEF
    set target_def "$target_dir/[file tail $def_file]"

    # Remove existing link/file if it exists
    if {[file exists $target_def]} {
        file delete $target_def
    }

    # Create symbolic link
    if {[catch {file link -symbolic $target_def $def_file} err]} {
        handle_warning "Could not create symbolic link, copying file instead: $err"
        file copy $def_file $target_def
    }

    handle_info "DEF file linked: $target_def"

    # Create DEF info file
    set info_file "$target_dir/def_info.tcl"
    set def_fp [open $info_file "w"]
    puts $def_fp "# DEF Information"
    puts $def_fp "set def_info(source_file) \"$def_file\""
    puts $def_fp "set def_info(target_file) \"$target_def\""
    puts $def_fp "set def_info(timestamp) \"[clock format [clock seconds]]\""
    puts $def_fp "set def_info(size) \"[file size $def_file]\""
    puts $def_fp "set def_info(status) \"linked\""
    close $def_fp

    handle_info "DEF subnode completed successfully"
}

proc handle_library_subnode {run_dir} {
    global fp project flow_type

    handle_info "Processing library subnode..."

    set target_dir "$run_dir/work/$flow_type/inputs/library"

    # Create library info file
    set info_file "$target_dir/library_info.tcl"
    set lib_fp [open $info_file "w"]
    puts $lib_fp "# Library Information"
    puts $lib_fp "set library_info(timestamp) \"[clock format [clock seconds]]\""
    puts $lib_fp "set library_info(status) \"processed\""
    close $lib_fp

    handle_info "Library subnode completed successfully"
}

proc handle_validate_subnode {run_dir} {
    global fp project flow_type

    handle_info "══════════════════════════════════════════════════════════════════════════════"
    handle_info "                          INPUTS VALIDATION SUBNODE"
    handle_info "══════════════════════════════════════════════════════════════════════════════"

    set target_dir "$run_dir/work/$flow_type/inputs/validate"
    set validation_passed true
    set validation_errors {}
    set validation_warnings {}

    # ═══════════════════════════════════════════════════════════════════════════════
    # PHASE 1: Directory Structure Validation
    # ═══════════════════════════════════════════════════════════════════════════════

    handle_info "Phase 1: Validating directory structure..."

    set required_dirs [list \
        "work/$flow_type/inputs/netlist" \
        "work/$flow_type/inputs/sdc" \
        "work/$flow_type/inputs/def" \
        "work/$flow_type/inputs/upf" \
        "work/$flow_type/inputs/library" \
    ]

    foreach dir $required_dirs {
        set full_dir "$run_dir/$dir"
        if {![file exists $full_dir]} {
            lappend validation_errors "Missing required directory: $dir"
            set validation_passed false
            handle_error "✗ Missing directory: $dir"
        } else {
            handle_info "✓ Directory found: $dir"
        }
    }

    # ═══════════════════════════════════════════════════════════════════════════════
    # PHASE 2: Netlist Validation - Focus on Run Directory Links
    # ═══════════════════════════════════════════════════════════════════════════════

    handle_info "Phase 2: Validating netlist inputs..."

    if {[info exists fp(input,netlist)]} {
        set netlist_file $fp(input,netlist)
        set netlist_link "$run_dir/work/$flow_type/inputs/netlist/[file tail $netlist_file]"

        # PRIMARY CHECK: Verify the linked file exists in run directory (what flow actually uses)
        if {[file exists $netlist_link]} {
            handle_info "✓ Netlist properly linked in run directory: $netlist_link"

            # SECONDARY CHECK: Verify the link is valid (points to existing source)
            if {[file exists $netlist_file]} {
                handle_info "✓ Source netlist file accessible: $netlist_file"
            } else {
                lappend validation_warnings "Linked netlist exists but source file is missing: $netlist_file"
                handle_warning "⚠ Source netlist file missing (link may be broken)"
            }
        } else {
            # CRITICAL ERROR: Missing linked file that flow depends on
            lappend validation_errors "Netlist not properly linked in run directory: $netlist_link"
            set validation_passed false
            puts "\[ERROR\] ✗ Netlist missing from run directory (required for flow)"

            # Additional context: Check if source exists to help with diagnosis
            if {[file exists $netlist_file]} {
                handle_info "  → Source exists: $netlist_file (run inputs setup to create link)"
            } else {
                puts "\[ERROR\] ✗ Source also missing: $netlist_file"
            }
        }
    } else {
        lappend validation_errors "No netlist file specified in configuration"
        set validation_passed false
        puts "\[ERROR\] ✗ No netlist file specified in fp(input,netlist)"
    }

    # ═══════════════════════════════════════════════════════════════════════════════
    # PHASE 3: SDC Validation - Focus on Run Directory Links
    # ═══════════════════════════════════════════════════════════════════════════════

    handle_info "Phase 3: Validating SDC inputs..."

    set sdc_found false

    # Check for SDC functional file
    if {[info exists fp(input,sdc_func_file)]} {
        set sdc_file $fp(input,sdc_func_file)
        set sdc_link "$run_dir/work/$flow_type/inputs/sdc/[file tail $sdc_file]"

        # PRIMARY CHECK: Verify the linked file exists in run directory
        if {[file exists $sdc_link]} {
            handle_info "✓ SDC functional file properly linked in run directory: $sdc_link"
            set sdc_found true

            # SECONDARY CHECK: Verify source file accessibility
            if {[file exists $sdc_file]} {
                handle_info "✓ Source SDC file accessible: $sdc_file"
            } else {
                lappend validation_warnings "Linked SDC exists but source file missing: $sdc_file"
                handle_warning "⚠ Source SDC file missing (link may be broken)"
            }
        } else {
            # CRITICAL ERROR: Missing linked SDC file
            lappend validation_errors "SDC functional file not properly linked in run directory: $sdc_link"
            set validation_passed false
            puts "\[ERROR\] ✗ SDC file missing from run directory (required for flow)"

            # Additional context
            if {[file exists $sdc_file]} {
                handle_info "  → Source exists: $sdc_file (run inputs setup to create link)"
            } else {
                puts "\[ERROR\] ✗ Source also missing: $sdc_file"
            }
        }
    }

    # Check for SDC release tag or directory (these don't need linking validation)
    if {[info exists fp(input,sdc_release_tag)] || [info exists fp(input,sdc_release_dir)]} {
        if {[info exists fp(input,sdc_release_tag)]} {
            handle_info "✓ SDC release tag specified: $fp(input,sdc_release_tag)"
            set sdc_found true
        }
        if {[info exists fp(input,sdc_release_dir)]} {
            set sdc_dir $fp(input,sdc_release_dir)
            if {[file exists $sdc_dir]} {
                handle_info "✓ SDC release directory found: $sdc_dir"
                set sdc_found true
            } else {
                lappend validation_errors "SDC release directory not found: $sdc_dir"
                puts "\[ERROR\] ✗ SDC release directory not found: $sdc_dir"
            }
        }
    }

    if {!$sdc_found} {
        lappend validation_errors "No SDC input method specified (sdc_func_file, sdc_release_tag, or sdc_release_dir)"
        set validation_passed false
        puts "\[ERROR\] ✗ No SDC input method specified"
    }

    # ═══════════════════════════════════════════════════════════════════════════════
    # PHASE 4: DEF Validation - Focus on Run Directory Links
    # ═══════════════════════════════════════════════════════════════════════════════

    handle_info "Phase 4: Validating DEF inputs..."

    if {[info exists fp(input,def_file)]} {
        set def_file $fp(input,def_file)
        set def_link "$run_dir/work/$flow_type/inputs/def/[file tail $def_file]"

        # PRIMARY CHECK: Verify the linked file exists in run directory (optional input)
        if {[file exists $def_link]} {
            handle_info "✓ DEF file properly linked in run directory: $def_link"

            # SECONDARY CHECK: Verify source file accessibility
            if {[file exists $def_file]} {
                handle_info "✓ Source DEF file accessible: $def_file"
            } else {
                lappend validation_warnings "Linked DEF exists but source file missing: $def_file"
                handle_warning "⚠ Source DEF file missing (link may be broken)"
            }
        } else {
            # DEF is optional - warn but don't fail validation
            lappend validation_warnings "DEF file not linked in run directory: $def_link"
            handle_warning "⚠ DEF file not linked in run directory (may be created during floorplan)"

            # Additional context
            if {[file exists $def_file]} {
                handle_info "  → Source exists: $def_file (run inputs setup to create link)"
            } else {
                handle_info "  → Source not found: $def_file (may be generated during flow)"
            }
        }
    } else {
        handle_info "ℹ No DEF file specified (may be created during floorplan)"
    }

    # ═══════════════════════════════════════════════════════════════════════════════
    # PHASE 5: UPF Validation - Focus on Run Directory Links
    # ═══════════════════════════════════════════════════════════════════════════════

    handle_info "Phase 5: Validating UPF inputs..."

    set upf_found false

    if {[info exists fp(input,upf_file)]} {
        set upf_file $fp(input,upf_file)
        set upf_link "$run_dir/work/$flow_type/inputs/upf/[file tail $upf_file]"

        # PRIMARY CHECK: Verify the linked file exists in run directory (optional input)
        if {[file exists $upf_link]} {
            handle_info "✓ UPF file properly linked in run directory: $upf_link"
            set upf_found true

            # SECONDARY CHECK: Verify source file accessibility
            if {[file exists $upf_file]} {
                handle_info "✓ Source UPF file accessible: $upf_file"
            } else {
                lappend validation_warnings "Linked UPF exists but source file missing: $upf_file"
                handle_warning "⚠ Source UPF file missing (link may be broken)"
            }
        } else {
            # UPF is optional - warn but don't fail validation
            lappend validation_warnings "UPF file not linked in run directory: $upf_link"
            handle_warning "⚠ UPF file not linked in run directory (optional for power intent)"

            # Additional context
            if {[file exists $upf_file]} {
                handle_info "  → Source exists: $upf_file (run inputs setup to create link)"
            } else {
                handle_info "  → Source not found: $upf_file (power analysis may be skipped)"
            }
        }
    }

    if {[info exists fp(input,upf_release_tag)] || [info exists fp(input,upf_release_dir)]} {
        if {[info exists fp(input,upf_release_tag)]} {
            handle_info "✓ UPF release tag specified: $fp(input,upf_release_tag)"
            set upf_found true
        }
        if {[info exists fp(input,upf_release_dir)]} {
            set upf_dir $fp(input,upf_release_dir)
            if {[file exists $upf_dir]} {
                handle_info "✓ UPF release directory found: $upf_dir"
                set upf_found true
            } else {
                lappend validation_warnings "UPF release directory not found: $upf_dir"
                handle_warning "⚠ UPF release directory not found: $upf_dir"
            }
        }
    }

    if {!$upf_found} {
        handle_info "ℹ No UPF input specified (power intent may be optional)"
    }

    # ═══════════════════════════════════════════════════════════════════════════════
    # PHASE 6: Library Validation
    # ═══════════════════════════════════════════════════════════════════════════════

    handle_info "Phase 6: Validating library inputs..."

    # Check for library info file created by library subnode
    set lib_info_file "$run_dir/work/$flow_type/inputs/library/library_info.tcl"
    if {[file exists $lib_info_file]} {
        handle_info "✓ Library processing completed (library_info.tcl found)"
    } else {
        lappend validation_warnings "Library subnode may not have completed successfully"
        handle_warning "⚠ Library info file not found: $lib_info_file"
    }

    # ═══════════════════════════════════════════════════════════════════════════════
    # PHASE 7: Validation Summary and Report Generation
    # ═══════════════════════════════════════════════════════════════════════════════

    handle_info "Phase 7: Generating validation report..."

    # Create comprehensive validation report (TCL format)
    set report_file "$target_dir/validation_report.tcl"
    set val_fp [open $report_file "w"]

    puts $val_fp "# ═══════════════════════════════════════════════════════════════════════════════"
    puts $val_fp "# CBFlow FP Inputs Validation Report (TCL Format)"
    puts $val_fp "# Generated: [clock format [clock seconds]]"
    puts $val_fp "# Run Directory: $run_dir"
    puts $val_fp "# ═══════════════════════════════════════════════════════════════════════════════"
    puts $val_fp ""

    puts $val_fp "set validation_report(timestamp) \"[clock format [clock seconds]]\""
    puts $val_fp "set validation_report(run_dir) \"$run_dir\""
    puts $val_fp "set validation_report(status) \"[expr {$validation_passed ? "PASSED" : "FAILED"}]\""
    puts $val_fp "set validation_report(total_errors) [llength $validation_errors]"
    puts $val_fp "set validation_report(total_warnings) [llength $validation_warnings]"
    puts $val_fp ""

    if {[llength $validation_errors] > 0} {
        puts $val_fp "# Validation Errors:"
        puts $val_fp "set validation_report(errors) {"
        foreach error $validation_errors {
            puts $val_fp "    \"$error\""
        }
        puts $val_fp "}"
        puts $val_fp ""
    } else {
        puts $val_fp "set validation_report(errors) {}"
        puts $val_fp ""
    }

    if {[llength $validation_warnings] > 0} {
        puts $val_fp "# Validation Warnings:"
        puts $val_fp "set validation_report(warnings) {"
        foreach warning $validation_warnings {
            puts $val_fp "    \"$warning\""
        }
        puts $val_fp "}"
        puts $val_fp ""
    } else {
        puts $val_fp "set validation_report(warnings) {}"
        puts $val_fp ""
    }

    # Add input file summary
    puts $val_fp "# Input Files Summary:"
    puts $val_fp "set validation_report(input_files) {"
    if {[info exists fp(input,netlist)]} {
        puts $val_fp "    netlist \"$fp(input,netlist)\""
    }
    if {[info exists fp(input,sdc_func_file)]} {
        puts $val_fp "    sdc_func \"$fp(input,sdc_func_file)\""
    }
    if {[info exists fp(input,def_file)]} {
        puts $val_fp "    def \"$fp(input,def_file)\""
    }
    if {[info exists fp(input,upf_file)]} {
        puts $val_fp "    upf \"$fp(input,upf_file)\""
    }
    puts $val_fp "}"

    close $val_fp

    # Create comprehensive human-readable validation report with clean ASCII formatting
    set readable_report_file "$target_dir/validation_report.txt"
    set readable_fp [open $readable_report_file "w"]

    puts $readable_fp "================================================================================"
    puts $readable_fp "                    CBFlow FP INPUTS VALIDATION REPORT"
    puts $readable_fp "================================================================================"
    puts $readable_fp ""
    puts $readable_fp "Generated     : [clock format [clock seconds]]"
    puts $readable_fp "Run Directory : $run_dir"
    puts $readable_fp "Flow Type     : FP (Floorplan)"
    puts $readable_fp ""

    # Overall Status Section
    puts $readable_fp "-- VALIDATION SUMMARY --"
    if {$validation_passed} {
        puts $readable_fp "Status        : PASSED"
    } else {
        puts $readable_fp "Status        : FAILED"
    }
    puts $readable_fp "Total Errors  : [llength $validation_errors]"
    puts $readable_fp "Total Warnings: [llength $validation_warnings]"
    puts $readable_fp ""

    # Phase-by-Phase Details
    puts $readable_fp "-- VALIDATION PHASES --"
    puts $readable_fp ""
    puts $readable_fp "Phase 1: Directory Structure Validation"
    set dirs_checked [list \
        "work/$flow_type/inputs/netlist" \
        "work/$flow_type/inputs/sdc" \
        "work/$flow_type/inputs/def" \
        "work/$flow_type/inputs/upf" \
        "work/$flow_type/inputs/library" \
    ]
    foreach dir $dirs_checked {
        set full_dir "$run_dir/$dir"
        if {[file exists $full_dir]} {
            puts $readable_fp "  \[OK\] Directory found: $dir"
        } else {
            puts $readable_fp "  \[ERR\] Directory missing: $dir"
        }
    }
    puts $readable_fp ""

    puts $readable_fp "Phase 2: Netlist Input Validation"
    if {[info exists fp(input,netlist)]} {
        set netlist_link "$run_dir/work/$flow_type/inputs/netlist/[file tail $fp(input,netlist)]"
        if {[file exists $netlist_link]} {
            puts $readable_fp "  \[OK\] Netlist file: [file tail $fp(input,netlist)]"
            puts $readable_fp "       Linked in: $netlist_link"
            puts $readable_fp "       Source   : $fp(input,netlist)"
        } else {
            puts $readable_fp "  \[ERR\] Netlist not linked in run directory: $netlist_link"
            if {[file exists $fp(input,netlist)]} {
                puts $readable_fp "       Source exists: $fp(input,netlist) (run inputs setup)"
            } else {
                puts $readable_fp "       Source missing: $fp(input,netlist)"
            }
        }
    } else {
        puts $readable_fp "  \[ERR\] No netlist file specified in configuration"
    }
    puts $readable_fp ""

    puts $readable_fp "Phase 3: SDC Input Validation"
    if {[info exists fp(input,sdc_func_file)]} {
        if {[file exists $fp(input,sdc_func_file)]} {
            puts $readable_fp "  \[OK\] SDC functional file: [file tail $fp(input,sdc_func_file)]"
            puts $readable_fp "       Location: $fp(input,sdc_func_file)"
        } else {
            puts $readable_fp "  \[ERR\] SDC functional file not found: $fp(input,sdc_func_file)"
        }
    }
    if {[info exists fp(input,sdc_release_tag)]} {
        puts $readable_fp "  \[INFO\] SDC release tag: $fp(input,sdc_release_tag)"
    }
    if {[info exists fp(input,sdc_release_dir)]} {
        if {[file exists $fp(input,sdc_release_dir)]} {
            puts $readable_fp "  \[OK\] SDC release directory: $fp(input,sdc_release_dir)"
        } else {
            puts $readable_fp "  \[ERR\] SDC release directory not found: $fp(input,sdc_release_dir)"
        }
    }
    puts $readable_fp ""

    puts $readable_fp "Phase 4: DEF Input Validation (Optional)"
    if {[info exists fp(input,def_file)]} {
        if {[file exists $fp(input,def_file)]} {
            puts $readable_fp "  \[OK\] DEF file: [file tail $fp(input,def_file)]"
            puts $readable_fp "       Location: $fp(input,def_file)"
        } else {
            puts $readable_fp "  \[WARN\] DEF file not found: $fp(input,def_file)"
        }
    } else {
        puts $readable_fp "  \[INFO\] No DEF file specified (may be created during floorplan)"
    }
    puts $readable_fp ""

    puts $readable_fp "Phase 5: UPF Input Validation (Optional)"
    if {[info exists fp(input,upf_file)]} {
        if {[file exists $fp(input,upf_file)]} {
            puts $readable_fp "  \[OK\] UPF file: [file tail $fp(input,upf_file)]"
            puts $readable_fp "       Location: $fp(input,upf_file)"
        } else {
            puts $readable_fp "  \[WARN\] UPF file not found: $fp(input,upf_file)"
        }
    }
    if {[info exists fp(input,upf_release_tag)]} {
        puts $readable_fp "  \[INFO\] UPF release tag: $fp(input,upf_release_tag)"
    }
    if {[info exists fp(input,upf_release_dir)]} {
        if {[file exists $fp(input,upf_release_dir)]} {
            puts $readable_fp "  \[OK\] UPF release directory: $fp(input,upf_release_dir)"
        } else {
            puts $readable_fp "  \[WARN\] UPF release directory not found: $fp(input,upf_release_dir)"
        }
    }
    if {![info exists fp(input,upf_file)] && ![info exists fp(input,upf_release_tag)] && ![info exists fp(input,upf_release_dir)]} {
        puts $readable_fp "  \[INFO\] No UPF input specified (power intent may be optional)"
    }
    puts $readable_fp ""

    puts $readable_fp "Phase 6: Library Input Validation"
    set lib_info_file "$run_dir/work/$flow_type/inputs/library/library_info.tcl"
    if {[file exists $lib_info_file]} {
        puts $readable_fp "  \[OK\] Library processing completed (library_info.tcl found)"
    } else {
        puts $readable_fp "  \[WARN\] Library subnode may not have completed successfully"
    }
    puts $readable_fp ""

    # Detailed Errors and Warnings
    if {[llength $validation_errors] > 0} {
        puts $readable_fp "-- CRITICAL ERRORS --"
        set error_count 1
        foreach error $validation_errors {
            puts $readable_fp "$error_count. $error"
            incr error_count
        }
        puts $readable_fp ""
    }

    if {[llength $validation_warnings] > 0} {
        puts $readable_fp "-- WARNINGS --"
        set warning_count 1
        foreach warning $validation_warnings {
            puts $readable_fp "$warning_count. $warning"
            incr warning_count
        }
        puts $readable_fp ""
    }

    # Input Files Summary
    puts $readable_fp "-- INPUT FILES SUMMARY --"
    if {[info exists fp(input,netlist)]} {
        puts $readable_fp "Netlist  : $fp(input,netlist)"
    }
    if {[info exists fp(input,sdc_func_file)]} {
        puts $readable_fp "SDC Func : $fp(input,sdc_func_file)"
    }
    if {[info exists fp(input,def_file)]} {
        puts $readable_fp "DEF File : $fp(input,def_file)"
    }
    if {[info exists fp(input,upf_file)]} {
        puts $readable_fp "UPF File : $fp(input,upf_file)"
    }
    puts $readable_fp ""

    # Recommendations
    puts $readable_fp "-- RECOMMENDATIONS --"
    if {$validation_passed} {
        puts $readable_fp "\[OK\] All critical validations passed. Flow can proceed to import_design stage."
        if {[llength $validation_warnings] > 0} {
            puts $readable_fp "\[WARN\] Please review warnings above. While not critical, they may affect flow quality."
        }
    } else {
        puts $readable_fp "\[ERR\] Critical errors found. Please fix all errors before proceeding with the flow."
        puts $readable_fp "      - Ensure all required input files exist and are accessible"
        puts $readable_fp "      - Check file paths in user configuration"
        puts $readable_fp "      - Verify directory permissions"
    }
    puts $readable_fp ""
    puts $readable_fp "================================================================================"

    close $readable_fp

    # ═══════════════════════════════════════════════════════════════════════════════
    # Final Status Report
    # ═══════════════════════════════════════════════════════════════════════════════

    handle_info "══════════════════════════════════════════════════════════════════════════════"
    if {$validation_passed} {
        handle_info "                        ✓ VALIDATION PASSED"
        handle_info "All critical inputs validated successfully!"
        if {[llength $validation_warnings] > 0} {
            handle_info "Note: [llength $validation_warnings] warning(s) found - see validation report"
        }
    } else {
        puts "                        ✗ VALIDATION FAILED"
        puts "[llength $validation_errors] critical error(s) found!"
        puts "Please fix the errors before proceeding with the flow."
    }
    handle_info "══════════════════════════════════════════════════════════════════════════════"
    handle_info "Validation reports saved to:"
    handle_info "  - validation_report.tcl (TCL format)"
    handle_info "  - validation_report.txt (Human readable)"

    # ═══════════════════════════════════════════════════════════════════════════════
    # Launch XTerm Report Viewer with Color-Coded Background
    # ═══════════════════════════════════════════════════════════════════════════════

    handle_info "Launching validation report viewer..."

    # Determine background color based on validation status
    set bg_color ""
    if {!$validation_passed} {
        # Dark red for errors
        set bg_color "#ffcccc"
        set title_status "FAILED"
    } elseif {[llength $validation_warnings] > 0} {
        # Dark yellow for warnings
        set bg_color "#ffffcc"
        set title_status "PASSED (Warnings)"
    } else {
        # Actual green for success
        set bg_color "#ccffcc"
        set title_status "PASSED"
    }

    # Launch XTerm with color-coded background to display the report
    if {[auto_execok xterm] ne ""} {
        handle_info "Opening validation report in XTerm with status-based background color..."
        handle_info "Background color: $bg_color ([expr {!$validation_passed ? "Error" : [llength $validation_warnings] > 0 ? "Warning" : "Success"}])"

        # Create a simple viewer script that displays the report with pagination
        set viewer_script "$target_dir/report_viewer.tcl"
        set viewer_fp [open $viewer_script "w"]

        puts $viewer_fp "#!/usr/bin/env tclsh"
        puts $viewer_fp "# CBFlow Validation Report Viewer"
        puts $viewer_fp ""
        puts $viewer_fp "set report_file \"$readable_report_file\""
        puts $viewer_fp "set status \"$title_status\""
        puts $viewer_fp ""
        puts $viewer_fp "if {\[file exists \$report_file\]} {"
        puts $viewer_fp "    puts \"\\n\""
        puts $viewer_fp "    puts \"=================================================================================\""
        puts $viewer_fp "    puts \"                   CBFlow FP INPUTS VALIDATION REPORT VIEWER\""
        puts $viewer_fp "    puts \"                             Status: \$status\""
        puts $viewer_fp "    puts \"=================================================================================\""
        puts $viewer_fp "    puts \"\\n\""
        puts $viewer_fp "    "
        puts $viewer_fp "    set fp \[open \$report_file r\]"
        puts $viewer_fp "    set content \[read \$fp\]"
        puts $viewer_fp "    close \$fp"
        puts $viewer_fp "    "
        puts $viewer_fp "    puts \$content"
        puts $viewer_fp "    "
        puts $viewer_fp "    puts \"\\n\""
        puts $viewer_fp "    puts \"=================================================================================\""
        puts $viewer_fp "    puts \"Report Location: $readable_report_file\""
        puts $viewer_fp "    puts \"TCL Data File  : $report_file\""
        puts $viewer_fp "    puts \"=================================================================================\""
        puts $viewer_fp "    puts \"\\n\""
        puts $viewer_fp "    puts \"Press Enter to close this report viewer...\""
        puts $viewer_fp "    flush stdout"
        puts $viewer_fp "    gets stdin"
        puts $viewer_fp "} else {"
        puts $viewer_fp "    puts \"ERROR: Report file not found: \$report_file\""
        puts $viewer_fp "    puts \"Press Enter to close...\""
        puts $viewer_fp "    gets stdin"
        puts $viewer_fp "}"

        close $viewer_fp

        # Make the viewer script executable
        file attributes $viewer_script -permissions 0755

        # Launch XTerm with the report viewer using default geometry and font
        exec xterm -title "CBFlow Validation Report - $title_status" \
                  -bg $bg_color \
                  -fg black \
                  -e tclsh $viewer_script &

        handle_info "✓ Validation report opened in XTerm with color-coded background"
        handle_info "  Background indicates status: Green=Success, Yellow=Warning, Red=Error"
    } else {
        handle_warning "XTerm not available - report saved to files only"
        handle_info "View reports manually:"
        handle_info "  cat $readable_report_file"
        handle_info "  source $report_file"
    }

    if {!$validation_passed} {
        handle_info "Inputs validation completed with errors - see report for details"
        # Don't exit here - let the validation complete and show the report
    }

    handle_info "Inputs validation subnode completed successfully"
}

proc handle_finish_subnode {run_dir} {
    global fp project flow_type

    handle_info "Processing finish subnode..."

    set target_dir "$run_dir/work/$flow_type/inputs/finish"

    # Create finish info file
    set info_file "$target_dir/finish_info.tcl"
    set fin_fp [open $info_file "w"]
    puts $fin_fp "# Finish Information"
    puts $fin_fp "set finish_info(timestamp) \"[clock format [clock seconds]]\""
    puts $fin_fp "set finish_info(status) \"completed\""
    close $fin_fp

    handle_info "Finish subnode completed successfully"
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
        # Get valid subnodes dynamically from flow config for error message
        set valid_list "unknown"
        if {[info exists fp(subnodes,inputs)]} {
            set valid_list [join $fp(subnodes,inputs) {, }]
        }
        handle_error "Unknown subnode: $subnode_name. Valid subnodes: $valid_list"
    }
}

# Add pause for XTerm display - keep window open so user can see the process
puts ""
puts "═══════════════════════════════════════════════════════════════════════════════"
puts "Subnode $subnode_name processing completed successfully!"
puts "═══════════════════════════════════════════════════════════════════════════════"
puts ""
puts "Window will close automatically in 3 seconds..."
flush stdout
after 3000