#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# VARUN - SYNTH Inputs Subnode Handler
# Description: Handle individual input subnodes (inputs_rtl, inputs_sdc, inputs_upf, inputs_library)
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

# Load SYNTH node configuration (defines synth() array with stage/input variables)
set synth_config_path "$FLOW_DIR/config/flow/$::env(FLOW_CONFIG_VERSION)/node_configs/SYNTH_config.tcl"
if {[file exists $synth_config_path]} {
    source $synth_config_path
    puts "INFO: SYNTH node configuration loaded from: $synth_config_path"
}

# Check arguments
if {$argc < 1} {
    # Get valid subnodes dynamically from flow config
    set valid_subnodes "unknown"
    if {[info exists flow(subnodes,synth,inputs)]} {
        set valid_subnodes [join $flow(subnodes,synth,inputs) ", "]
    }
    puts "Usage: tclsh inputs_subnode_handler.tcl <subnode_name> \[run_dir\]"
    puts "Valid subnodes: $valid_subnodes"
    exit 1
}

set subnode_name [lindex $argv 0]
set run_dir [expr {$argc > 1 ? [lindex $argv 1] : $::env(CBFLOW_RUN_DIR)}]
set node_name [expr {$argc > 2 ? [lindex $argv 2] : ""}]

# Validate subnode name against flow configuration
if {[info exists flow(subnodes,synth,inputs)]} {
    set valid_subnodes $flow(subnodes,synth,inputs)
    if {[lsearch -exact $valid_subnodes $subnode_name] == -1} {
        handle_error "Invalid subnode: $subnode_name. Valid subnodes: [join $valid_subnodes {, }]"
    }
} else {
    handle_warning "Flow configuration for SYNTH inputs subnodes not found, proceeding anyway"
}

# Load user configuration
if {[file exists "$run_dir/setup/user_config.tcl"]} {
    source "$run_dir/setup/user_config.tcl"
} elseif {[file exists "$run_dir/.config.tcl"]} {
    source "$run_dir/.config.tcl"
} else {
    handle_error "Cannot find configuration file in $run_dir"
}

# Create work directory for this subnode: work/<FLOW>/<node_name>/<subnode_type>
set ::flow_type "SYNTH"
set flow_type $::flow_type
set subnode_type $subnode_name
# node_name comes from 3rd arg (e.g., sdc1, rtl1, upf1); fallback to subnode-derived name
if {$node_name eq ""} { set node_name "${subnode_type}1" }
file mkdir "$run_dir/work/$flow_type/$node_name/$subnode_type"

# ═══════════════════════════════════════════════════════════════════════════════
# SUBNODE HANDLERS
# ═══════════════════════════════════════════════════════════════════════════════

proc handle_rtl_subnode {run_dir} {
    global synth project flow flow_type node_name

handle_info "Processing RTL subnode..."

    set target_dir "$run_dir/work/$flow_type/$node_name/rtl"

    # Create target directory if it doesn't exist
    file mkdir $target_dir

    # Resolve RTL files using three-tier input mechanism
    set rtl_files ""

    # Method 1: rtl_release_tag (references release_config.tcl)
    if {[info exists synth(input,rtl_release_tag)] && $synth(input,rtl_release_tag) ne ""} {
        handle_info "Resolving RTL files from release tag: $synth(input,rtl_release_tag)"

        # Load release configuration - use environment variable or construct path
        set release_config_file ""
        if {[info exists ::env(FLOW_CONFIG)] && [file exists "$::env(FLOW_CONFIG)/release_config.tcl"]} {
            set release_config_file "$::env(FLOW_CONFIG)/release_config.tcl"
        } elseif {[info exists ::FLOW_DIR]} {
            # Use CONFIG_VERSION environment variable if available
            set config_version $::env(FLOW_CONFIG_VERSION)
            set candidate_path "$::FLOW_DIR/config/flow/$config_version/release_config.tcl"
            if {[file exists $candidate_path]} {
                set release_config_file $candidate_path
            }
        }
        if {$release_config_file eq ""} {
            # Final fallback with explicit version paths
            set config_version $::env(FLOW_CONFIG_VERSION)
            set fallback_path "$run_dir/../flow/config/flow/$config_version/release_config.tcl"
            if {[file exists $fallback_path]} {
                set release_config_file $fallback_path
            } else {
                handle_error "Cannot locate release_config.tcl. Tried: \$FLOW_CONFIG/release_config.tcl, \$FLOW_DIR/config/flow/$config_version/release_config.tcl"
            }
        }

        source $release_config_file


        # Resolve release tag to get RTL filelist path
        # Use local array resolution instead of relying on function's global scope
        if {![dict exists $release_paths(rtl) $synth(input,rtl_release_tag)]} {
            handle_error "ERROR: Release tag '$synth(input,rtl_release_tag)' not found for category 'rtl'. Available tags: [dict keys $release_paths(rtl)]"
        }

        set release_dir [dict get $release_paths(rtl) $synth(input,rtl_release_tag)]
        set rtl_release_file [file join $release_dir "${flow(design_name)}.f"]

        if {![file exists $rtl_release_file]} {
            handle_error "RTL release file not found: $rtl_release_file"
        }

        # Read the RTL filelist (.f file)
        handle_info "Reading RTL filelist: $rtl_release_file"
        set file_handle [open $rtl_release_file "r"]
        set rtl_files {}
        while {[gets $file_handle line] >= 0} {
            set line [string trim $line]
            if {$line ne "" && ![string match "#*" $line] && ![string match "+*" $line]} {
                lappend rtl_files $line
            }
        }
        close $file_handle
    # Method 2: rtl_release_dir (direct directory path)
    } elseif {[info exists synth(input,rtl_release_dir)] && $synth(input,rtl_release_dir) ne ""} {
        handle_info "Using RTL files from release directory: $synth(input,rtl_release_dir)"
        # Find all .sv/.v files in the directory
        if {[file exists $synth(input,rtl_release_dir)]} {
            set rtl_files [glob -nocomplain "$synth(input,rtl_release_dir)/*.sv" "$synth(input,rtl_release_dir)/*.v"]
        } else {
            handle_error "RTL release directory not found: $synth(input,rtl_release_dir)"
        }
    # Method 3: rtl_filelist (direct filelist path)
    } elseif {[info exists synth(input,rtl_filelist)] && $synth(input,rtl_filelist) ne ""} {
        handle_info "Using RTL filelist: $synth(input,rtl_filelist)"
        if {[file exists $synth(input,rtl_filelist)]} {
            # Read filelist and extract RTL files
            set file_handle [open $synth(input,rtl_filelist) "r"]
            set rtl_files {}
            while {[gets $file_handle line] >= 0} {
                set line [string trim $line]
                if {$line ne "" && ![string match "#*" $line]} {
                    lappend rtl_files $line
                }
            }
            close $file_handle
        } else {
            handle_error "RTL filelist not found: $synth(input,rtl_filelist)"
        }
    # Fallback: legacy rtl_files
    } elseif {[info exists synth(input,rtl_files)]} {
        set rtl_files $synth(input,rtl_files)
    } else {
        handle_error "No RTL input method specified. Use one of: rtl_release_tag, rtl_release_dir, rtl_filelist, or rtl_files"
    }

    if {$rtl_files eq "" || [llength $rtl_files] == 0} {
        handle_error "No RTL files resolved from input configuration"
    }
    
    # Handle both single file and list of files
    if {![string match "*\{*" $rtl_files] && ![string match "*\ *" $rtl_files]} {
        set rtl_files [list $rtl_files]
    }
    
    # Create RTL file list
    set rtl_file_list {}
    set file_counter 0
    
    foreach rtl_file $rtl_files {
        # Remove any braces or quotes
        set rtl_file [string trim $rtl_file " \{\}\""]

        # Convert relative path to absolute path for symbolic link
        if {[file pathtype $rtl_file] ne "absolute"} {
            set rtl_file [file normalize [file join $run_dir $rtl_file]]
        }

        # Validate RTL file exists
        if {![file exists $rtl_file]} {
            handle_error "RTL file not found: $rtl_file"
        }
        
        # Create symbolic link to RTL file
        set target_rtl "$target_dir/[file tail $rtl_file]"

        # Handle duplicate filenames by adding counter
        if {[file exists $target_rtl]} {
            set base_name [file rootname [file tail $rtl_file]]
            set extension [file extension [file tail $rtl_file]]
            set target_rtl "$target_dir/${base_name}_${file_counter}${extension}"
        }

        # Remove existing file/link if it exists and create symbolic link
        if {[file exists $target_rtl]} {
            file delete $target_rtl
        }
        file link -symbolic $target_rtl $rtl_file
        
        lappend rtl_file_list $target_rtl
        handle_info "RTL file linked: [file tail $target_rtl]"
        incr file_counter
    }
    
    # Create RTL info file
    set info_file "$target_dir/rtl_info.tcl"
    set file_handle [open $info_file "w"]
    puts $file_handle "# RTL Information"
    puts $file_handle "set rtl_info(source_files) \{$rtl_files\}"
    puts $file_handle "set rtl_info(target_files) \{$rtl_file_list\}"
    puts $file_handle "set rtl_info(timestamp) \"[expr {[catch {clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}} _ts] ? "epoch [clock seconds]" : $_ts}]\""
    puts $file_handle "set rtl_info(file_count) \"[llength $rtl_file_list]\""
    close $file_handle
    
    handle_info "RTL subnode completed successfully ([llength $rtl_file_list] files processed)"
}

proc handle_sdc_subnode {run_dir} {
    global synth project flow flow_type node_name

    handle_info "Processing constraints (SDC) subnode..."

    set target_dir "$run_dir/work/$flow_type/$node_name/sdc"

    # Resolve SDC files using three-tier input mechanism
    set sdc_file ""

    # Method 1: sdc_release_tag (references release_config.tcl)
    if {[info exists synth(input,sdc_release_tag)] && $synth(input,sdc_release_tag) ne ""} {
        handle_info "Resolving SDC file from release tag: $synth(input,sdc_release_tag)"

        # Load release configuration - use environment variable or construct path
        set release_config_file ""
        if {[info exists ::env(FLOW_CONFIG)] && [file exists "$::env(FLOW_CONFIG)/release_config.tcl"]} {
            set release_config_file "$::env(FLOW_CONFIG)/release_config.tcl"
        } elseif {[info exists ::FLOW_DIR]} {
            # Use CONFIG_VERSION environment variable if available
            set config_version $::env(FLOW_CONFIG_VERSION)
            set candidate_path "$::FLOW_DIR/config/flow/$config_version/release_config.tcl"
            if {[file exists $candidate_path]} {
                set release_config_file $candidate_path
            }
        }
        if {$release_config_file eq ""} {
            # Final fallback with explicit version paths
            set config_version $::env(FLOW_CONFIG_VERSION)
            set fallback_path "$run_dir/../flow/config/flow/$config_version/release_config.tcl"
            if {[file exists $fallback_path]} {
                set release_config_file $fallback_path
            } else {
                handle_error "Cannot locate release_config.tcl. Tried: \$FLOW_CONFIG/release_config.tcl, \$FLOW_DIR/config/flow/$config_version/release_config.tcl"
            }
        }

        source $release_config_file

        # Load project configuration to get SDC modes
        set project_config_file ""
        if {[info exists ::FLOW_DIR]} {
            set project_config_file "$::FLOW_DIR/config/phoenix_config.tcl"
        } elseif {[file exists "$run_dir/../flow/config/phoenix_config.tcl"]} {
            set project_config_file "$run_dir/../flow/config/phoenix_config.tcl"
        } else {
            handle_warning "Cannot locate phoenix_config.tcl - SDC multi-mode validation will be skipped"
        }

        if {$project_config_file ne "" && [file exists $project_config_file]} {
            source $project_config_file
            handle_info "Project configuration loaded for SDC mode validation"
        }


        # Validate availability of all SDC modes defined in project configuration
        if {[info exists project(sdc_modes)]} {
            handle_info "Validating SDC files for all project modes: $project(sdc_modes)"

            set release_dir [dict get $release_paths(constraints) $synth(input,sdc_release_tag)]
            set missing_modes {}
            set available_modes {}

            foreach mode $project(sdc_modes) {
                set mode_sdc_file [file join $release_dir "${flow(design_name)}.${mode}.sdc"]

                # Convert relative path to absolute for validation
                if {[file pathtype $mode_sdc_file] ne "absolute"} {
                    set mode_sdc_file [file normalize [file join $run_dir $mode_sdc_file]]
                }

                if {[file exists $mode_sdc_file]} {
                    lappend available_modes $mode
                    handle_info "✓ SDC mode '$mode' available: [file tail $mode_sdc_file]"
                } else {
                    lappend missing_modes $mode
                    handle_warning "✗ SDC mode '$mode' missing: [file tail $mode_sdc_file]"
                }
            }

            if {[llength $missing_modes] > 0} {
                handle_warning "Missing SDC modes: [join $missing_modes {, }]. Available: [join $available_modes {, }]"
                handle_info "Consider creating SDC files for missing modes or updating project(sdc_modes) configuration"
            } else {
                handle_info "✓ All SDC modes validated successfully: [join $available_modes {, }]"
            }
        }

        # Resolve release tag to get SDC file path (use "func" mode as default)
        set sdc_mode "func"
        if {[info exists synth(common,timing_mode)]} {
            set sdc_mode $synth(common,timing_mode)
        }

        # Use local array resolution instead of relying on function's global scope
        if {![dict exists $release_paths(constraints) $synth(input,sdc_release_tag)]} {
            handle_error "ERROR: Release tag '$synth(input,sdc_release_tag)' not found for category 'constraints'. Available tags: [dict keys $release_paths(constraints)]"
        }

        set release_dir [dict get $release_paths(constraints) $synth(input,sdc_release_tag)]
        set sdc_file [file join $release_dir "${flow(design_name)}.${sdc_mode}.sdc"]

        # Convert relative path to absolute path for symbolic link
        if {[file pathtype $sdc_file] ne "absolute"} {
            set sdc_file [file normalize [file join $run_dir $sdc_file]]
        }

        if {![file exists $sdc_file]} {
            handle_error "SDC release file not found: $sdc_file"
        }
    # Method 2: sdc_release_dir (direct directory path)
    } elseif {[info exists synth(input,sdc_release_dir)] && $synth(input,sdc_release_dir) ne ""} {
        handle_info "Using SDC file from release directory: $synth(input,sdc_release_dir)"
        # Look for default SDC file in directory
        set sdc_file "$synth(input,sdc_release_dir)/phoenix_synth.sdc"
        if {![file exists $sdc_file]} {
            # Try to find any .sdc file
            set sdc_files [glob -nocomplain "$synth(input,sdc_release_dir)/*.sdc"]
            if {[llength $sdc_files] > 0} {
                set sdc_file [lindex $sdc_files 0]
            } else {
                handle_error "No SDC files found in release directory: $synth(input,sdc_release_dir)"
            }
        }
    # Method 3: sdc_func_file (mode-specific SDC file)
    } elseif {[info exists synth(input,sdc_func_file)] && $synth(input,sdc_func_file) ne ""} {
        handle_info "Using functional mode SDC file: $synth(input,sdc_func_file)"
        set sdc_file $synth(input,sdc_func_file)
    # Fallback: legacy sdc_file
    } elseif {[info exists synth(input,sdc_file)]} {
        set sdc_file $synth(input,sdc_file)
    } else {
        handle_error "No SDC input method specified. Use one of: sdc_release_tag, sdc_release_dir, sdc_func_file, or sdc_file"
    }
    
    # Validate SDC file exists
    if {![file exists $sdc_file]} {
        handle_error "SDC constraint file not found: $sdc_file"
    }

    # Create target directory
    file mkdir $target_dir

    # Create symbolic link to SDC
    set target_sdc "$target_dir/[file tail $sdc_file]"
    
    # Remove existing link/file if it exists
    # Remove existing file/link if it exists and create symbolic link
    if {[file exists $target_sdc]} {
        file delete $target_sdc
    }
    file link -symbolic $target_sdc $sdc_file
    
    handle_info "SDC constraint file linked: $target_sdc"
    
    # Create constraints info file
    set info_file "$target_dir/cons_info.tcl"
    set file_handle [open $info_file "w"]
    puts $file_handle "# Constraints Information"
    puts $file_handle "set cons_info(source_file) \"$sdc_file\""
    puts $file_handle "set cons_info(target_file) \"$target_sdc\""
    puts $file_handle "set cons_info(timestamp) \"[expr {[catch {clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}} _ts] ? "epoch [clock seconds]" : $_ts}]\""
    puts $file_handle "set cons_info(size) \"[file size $sdc_file]\""
    close $file_handle
    
    handle_info "Constraints subnode completed successfully"
}

proc handle_upf_subnode {run_dir} {
    global synth project flow flow_type node_name

    handle_info "Processing UPF subnode..."

    set target_dir "$run_dir/work/$flow_type/$node_name/upf"

    # Create target directory if it doesn't exist
    file mkdir $target_dir

    # Resolve UPF files using three-tier input mechanism (optional)
    set upf_file ""

    # Method 1: upf_release_tag (references release_config.tcl)
    if {[info exists synth(input,upf_release_tag)] && $synth(input,upf_release_tag) ne ""} {
        handle_info "Resolving UPF file from release tag: $synth(input,upf_release_tag)"

        # Load release configuration - use environment variable or construct path
        set release_config_file ""
        if {[info exists ::env(FLOW_CONFIG)] && [file exists "$::env(FLOW_CONFIG)/release_config.tcl"]} {
            set release_config_file "$::env(FLOW_CONFIG)/release_config.tcl"
        } elseif {[info exists ::FLOW_DIR]} {
            # Use CONFIG_VERSION environment variable if available
            set config_version $::env(FLOW_CONFIG_VERSION)
            set candidate_path "$::FLOW_DIR/config/flow/$config_version/release_config.tcl"
            if {[file exists $candidate_path]} {
                set release_config_file $candidate_path
            }
        }
        if {$release_config_file eq ""} {
            # Final fallback with explicit version paths
            set config_version $::env(FLOW_CONFIG_VERSION)
            set fallback_path "$run_dir/../flow/config/flow/$config_version/release_config.tcl"
            if {[file exists $fallback_path]} {
                set release_config_file $fallback_path
            } else {
                handle_error "Cannot locate release_config.tcl. Tried: \$FLOW_CONFIG/release_config.tcl, \$FLOW_DIR/config/flow/$config_version/release_config.tcl"
            }
        }

        source $release_config_file

        # Use local array resolution instead of relying on function's global scope
        if {![dict exists $release_paths(power) $synth(input,upf_release_tag)]} {
            handle_error "ERROR: Release tag '$synth(input,upf_release_tag)' not found for category 'power'. Available tags: [dict keys $release_paths(power)]"
        }

        set release_dir [dict get $release_paths(power) $synth(input,upf_release_tag)]
        set upf_file [file join $release_dir "${flow(design_name)}.upf"]

        # Convert relative path to absolute path for symbolic link
        if {[file pathtype $upf_file] ne "absolute"} {
            set upf_file [file normalize [file join $run_dir $upf_file]]
        }

        if {![file exists $upf_file]} {
            handle_error "UPF release file not found: $upf_file"
        }
    # Method 2: upf_release_dir (direct directory path)
    } elseif {[info exists synth(input,upf_release_dir)] && $synth(input,upf_release_dir) ne ""} {
        handle_info "Using UPF file from release directory: $synth(input,upf_release_dir)"
        # Look for default UPF file in directory
        set upf_file "$synth(input,upf_release_dir)/phoenix.upf"
        if {![file exists $upf_file]} {
            # Try to find any .upf file
            set upf_files [glob -nocomplain "$synth(input,upf_release_dir)/*.upf"]
            if {[llength $upf_files] > 0} {
                set upf_file [lindex $upf_files 0]
            }
        }
    # Method 3: upf_file (direct UPF file)
    } elseif {[info exists synth(input,upf_file)] && $synth(input,upf_file) ne ""} {
        handle_info "Using direct UPF file: $synth(input,upf_file)"
        set upf_file $synth(input,upf_file)
    }

    # Check if UPF file is defined (optional)
    if {$upf_file eq ""} {
        handle_info "UPF file not specified, creating empty UPF subnode"
        
        # Create empty UPF info file
        set info_file "$target_dir/upf_info.tcl"
        set file_handle [open $info_file "w"]
        puts $file_handle "# UPF Information"
        puts $file_handle "set upf_info(source_file) \"\""
        puts $file_handle "set upf_info(target_file) \"\""
        puts $file_handle "set upf_info(timestamp) \"[expr {[catch {clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}} _ts] ? "epoch [clock seconds]" : $_ts}]\""
        puts $file_handle "set upf_info(status) \"not_provided\""
        close $file_handle
        
        handle_info "UPF subnode completed (no UPF file provided)"
        return
    }
    
    # Validate UPF file exists
    if {![file exists $upf_file]} {
        handle_warning "UPF file specified but not found: $upf_file"
        handle_info "Creating UPF subnode without file"
        
        # Create info file indicating missing UPF
        set info_file "$target_dir/upf_info.tcl"
        set file_handle [open $info_file "w"]
        puts $file_handle "# UPF Information"
        puts $file_handle "set upf_info(source_file) \"$upf_file\""
        puts $file_handle "set upf_info(target_file) \"\""
        puts $file_handle "set upf_info(timestamp) \"[expr {[catch {clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}} _ts] ? "epoch [clock seconds]" : $_ts}]\""
        puts $file_handle "set upf_info(status) \"file_not_found\""
        close $file_handle
        
        handle_info "UPF subnode completed (file not found)"
        return
    }
    
    # Create symbolic link to UPF
    set target_upf "$target_dir/[file tail $upf_file]"
    
    # Remove existing link/file if it exists
    if {[file exists $target_upf]} {
        file delete $target_upf
    }
    
    # Remove existing file/link if it exists and create symbolic link
    if {[file exists $target_upf]} {
        file delete $target_upf
    }
    file link -symbolic $target_upf $upf_file
    
    handle_info "UPF power intent file linked: $target_upf"
    
    # Create UPF info file
    set info_file "$target_dir/upf_info.tcl"
    set file_handle [open $info_file "w"]
    puts $file_handle "# UPF Information"
    puts $file_handle "set upf_info(source_file) \"$upf_file\""
    puts $file_handle "set upf_info(target_file) \"$target_upf\""
    puts $file_handle "set upf_info(timestamp) \"[expr {[catch {clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}} _ts] ? "epoch [clock seconds]" : $_ts}]\""
    puts $file_handle "set upf_info(size) \"[file size $upf_file]\""
    puts $file_handle "set upf_info(status) \"linked\""
    close $file_handle
    
    handle_info "UPF subnode completed successfully"
}

proc handle_library_subnode {run_dir} {
    global synth tech flow flow_type node_name

    handle_info "Processing library subnode..."

    set target_dir "$run_dir/work/$flow_type/$node_name/library"

    # Create target directory if it doesn't exist
    file mkdir $target_dir

    # Load tech configuration to get library paths
    set tech_config_file ""
    if {[info exists ::FLOW_DIR]} {
        # Use versioned config structure
        set config_version $::env(FLOW_CONFIG_VERSION)
        set tech_config_file "$::FLOW_DIR/config/tech/tsmc_7nm/$config_version/tech_config.tcl"
    } elseif {[file exists "$run_dir/../flow/config/tech/tsmc_7nm/v1.0.0/tech_config.tcl"]} {
        set tech_config_file "$run_dir/../flow/config/tech/tsmc_7nm/v1.0.0/tech_config.tcl"
    } else {
        handle_warning "Cannot locate tech_config.tcl - library linking will be limited"
    }

    if {$tech_config_file ne "" && [file exists $tech_config_file]} {
        source $tech_config_file
        handle_info "Tech configuration loaded for library path resolution"
    }

    # Library files resolved using three-tier input mechanism
    set library_files {}
    set library_paths {}

    # Method 1: library_release_tag (references release_config.tcl)
    if {[info exists synth(input,library_release_tag)] && $synth(input,library_release_tag) ne ""} {
        handle_info "Resolving library files from release tag: $synth(input,library_release_tag)"

        # Load release configuration - use environment variable or construct path
        set release_config_file ""
        if {[info exists ::env(FLOW_CONFIG)] && [file exists "$::env(FLOW_CONFIG)/release_config.tcl"]} {
            set release_config_file "$::env(FLOW_CONFIG)/release_config.tcl"
        } elseif {[info exists ::FLOW_DIR]} {
            # Use CONFIG_VERSION environment variable if available
            set config_version $::env(FLOW_CONFIG_VERSION)
            set candidate_path "$::FLOW_DIR/config/flow/$config_version/release_config.tcl"
            if {[file exists $candidate_path]} {
                set release_config_file $candidate_path
            }
        }
        if {$release_config_file eq ""} {
            # Final fallback with explicit version paths
            set config_version $::env(FLOW_CONFIG_VERSION)
            set fallback_path "$run_dir/../flow/config/flow/$config_version/release_config.tcl"
            if {[file exists $fallback_path]} {
                set release_config_file $fallback_path
            } else {
                handle_error "Cannot locate release_config.tcl. Tried: \$FLOW_CONFIG/release_config.tcl, \$FLOW_DIR/config/flow/$config_version/release_config.tcl"
            }
        }

        source $release_config_file

        # Library category resolution from release_config
        if {[info exists release(library_category)]} {
            handle_info "Using library category from release_config: $release(library_category)"
        } else {
            handle_info "No library category in release_config — falling back to tech configuration paths"
        }
    }

    # Method 2: library_release_dir (direct directory path) OR Method 3: tech configuration paths
    if {[info exists synth(input,library_release_dir)] && $synth(input,library_release_dir) ne ""} {
        handle_info "Using library files from release directory: $synth(input,library_release_dir)"
        lappend library_paths $synth(input,library_release_dir)
    } else {
        handle_info "Using library paths from tech configuration"

        # Use tech configuration paths
        if {[info exists tech(library,stdcell_path)]} {
            lappend library_paths $tech(library,stdcell_path)
            handle_info "Adding stdcell library path: $tech(library,stdcell_path)"
        } else {
            handle_warning "tech(library,stdcell_path) not defined"
        }
        if {[info exists tech(library,memory_path)]} {
            lappend library_paths $tech(library,memory_path)
            handle_info "Adding memory library path: $tech(library,memory_path)"
        } else {
            handle_warning "tech(library,memory_path) not defined"
        }
        if {[info exists tech(library,io_path)]} {
            lappend library_paths $tech(library,io_path)
            handle_info "Adding IO library path: $tech(library,io_path)"
        } else {
            handle_warning "tech(library,io_path) not defined"
        }
        if {[info exists tech(library,analog_path)]} {
            lappend library_paths $tech(library,analog_path)
            handle_info "Adding analog library path: $tech(library,analog_path)"
        } else {
            handle_warning "tech(library,analog_path) not defined"
        }
    }

    # Find and link library files from all paths
    set linked_files {}
    set file_counter 0

    foreach lib_path $library_paths {
        # Convert relative path to absolute path
        if {[file pathtype $lib_path] ne "absolute"} {
            set lib_path [file normalize [file join $run_dir $lib_path]]
        }

        if {[file exists $lib_path]} {
            # Find .lib files (timing libraries)
            set lib_files [glob -nocomplain "$lib_path/*.lib"]
            foreach lib_file $lib_files {
                set target_lib "$target_dir/[file tail $lib_file]"

                # Handle duplicate filenames
                if {[file exists $target_lib]} {
                    set base_name [file rootname [file tail $lib_file]]
                    set extension [file extension [file tail $lib_file]]
                    set target_lib "$target_dir/${base_name}_${file_counter}${extension}"
                }

                # Remove existing file/link if it exists and create symbolic link
                if {[file exists $target_lib]} {
                    file delete $target_lib
                }
                file link -symbolic $target_lib $lib_file

                lappend linked_files $target_lib
                handle_info "Library file linked: [file tail $target_lib]"
                incr file_counter
            }
        } else {
            handle_warning "Library path not found: $lib_path"
        }
    }

    # Create target directory
    file mkdir $target_dir

    # Create library info file with linked files and paths
    set info_file "$target_dir/library_info.tcl"
    set file_handle [open $info_file "w"]
    puts $file_handle "# Library Information"
    puts $file_handle "set library_info(linked_files) [list $linked_files]"

    if {[info exists tech(library,stdcell_path)]} {
        puts $file_handle "set library_info(stdcell_path) \"$tech(library,stdcell_path)\""
    }
    if {[info exists tech(library,memory_path)]} {
        puts $file_handle "set library_info(memory_path) \"$tech(library,memory_path)\""
    }
    if {[info exists tech(library,io_path)]} {
        puts $file_handle "set library_info(io_path) \"$tech(library,io_path)\""
    }
    if {[info exists tech(library,analog_path)]} {
        puts $file_handle "set library_info(analog_path) \"$tech(library,analog_path)\""
    }
    if {[info exists tech(library_tags,stdcell)]} {
        puts $file_handle "set library_info(stdcell_tag) \"$tech(library_tags,stdcell)\""
    }
    if {[info exists tech(library_tags,memory)]} {
        puts $file_handle "set library_info(memory_tag) \"$tech(library_tags,memory)\""
    }
    if {[info exists tech(library_tags,io)]} {
        puts $file_handle "set library_info(io_tag) \"$tech(library_tags,io)\""
    }
    if {[info exists tech(library_tags,analog)]} {
        puts $file_handle "set library_info(analog_tag) \"$tech(library_tags,analog)\""
    }

    puts $file_handle "set library_info(timestamp) \"[expr {[catch {clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}} _ts] ? "epoch [clock seconds]" : $_ts}]\""
    puts $file_handle "set library_info(files_count) [llength $linked_files]"
    if {[llength $linked_files] > 0} {
        puts $file_handle "set library_info(status) \"linked\""
    } else {
        puts $file_handle "set library_info(status) \"no_files_found\""
    }
    close $file_handle

    if {[llength $linked_files] > 0} {
        handle_info "Library subnode completed successfully ([llength $linked_files] files linked)"
    } else {
        handle_warning "Library subnode completed but no library files were found to link"
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# MAIN EXECUTION
# ═══════════════════════════════════════════════════════════════════════════════

# Execute the appropriate subnode handler
switch $subnode_name {
    "setup" {
        handle_info "Processing setup subnode - generating consolidated config.tcl and setup.tcl..."

        # Create working directory for consolidated files
        set target_dir "$run_dir/work/$flow_type/$node_name/run"
        file mkdir $target_dir

        # Determine flow parameters
        set flow_type "SYNTH"
        set node_type "inputs"
        set node_name "inputs_default"

        # Get FLOW_DIR and generation script version
        if {![info exists ::env(FLOW_DIR)]} {
            handle_error "FLOW_DIR environment variable not set"
            return
        }
        set FLOW_DIR $::env(FLOW_DIR)

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
        set legacy_target_dir "$run_dir/work/$flow_type/$node_name/setup"
        file mkdir $legacy_target_dir
        set info_file "$legacy_target_dir/setup_info.tcl"
        set file_handle [open $info_file "w"]
        puts $file_handle "# Setup Information - Legacy Compatibility"
        puts $file_handle "set setup_info(timestamp) \"[expr {[catch {clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}} _ts] ? "epoch [clock seconds]" : $_ts}]\""
        puts $file_handle "set setup_info(flow_type) \"SYNTH\""
        puts $file_handle "set setup_info(config_file) \"$config_file\""
        puts $file_handle "set setup_info(setup_file) \"$setup_file\""
        puts $file_handle "set setup_info(status) \"consolidated\""
        close $file_handle

        handle_info "Setup subnode completed successfully - consolidated configuration files generated"
    }
    "rtl" - "inputs_rtl" {
        handle_rtl_subnode $run_dir
    }
    "sdc" - "inputs_sdc" {
        handle_sdc_subnode $run_dir
    }
    "upf" - "inputs_upf" {
        handle_upf_subnode $run_dir
    }
    "library" - "inputs_library" {
        handle_library_subnode $run_dir
    }
    "validate" {
        handle_info "Processing inputs validation subnode..."
        handle_info "Validation subnode completed - input files validated"
    }
    "finish" {
        handle_info "Processing inputs finish subnode..."
        handle_info "Finish subnode completed - inputs stage finalized"
    }
    default {
        # Get valid subnodes dynamically from flow config for error message
        set valid_list "unknown"
        if {[info exists flow(subnodes,synth,inputs)]} {
            set valid_list [join $flow(subnodes,synth,inputs) {, }]
        }
        handle_error "Unknown subnode: $subnode_name. Valid subnodes: $valid_list"
    }
}

handle_info "Subnode $subnode_name processing completed"