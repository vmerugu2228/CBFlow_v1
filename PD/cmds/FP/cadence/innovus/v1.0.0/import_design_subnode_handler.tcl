#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow - FP import_design Subnode Handler
# Description: Handle individual import_design subnodes (setup, run, validate, finish)
# Usage: tclsh import_design_subnode_handler.tcl <subnode_name> <run_dir>
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
} elseif {[file exists ".run.cbflow.tcl"]} {
    # Native TCL run-specific environment (alternative naming)
    source ".run.cbflow.tcl"

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
    # Legacy environment setup
    source ".env.tcl"
} else {
    puts "ERROR: No environment file found. Expected .cbflow.tcl, .run.cnflow.tcl, .run.cbflow.tcl, .run.cbflow.env, or .env.tcl in CBFlow run directory."
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
    if {[info exists fp(subnodes,import_design)]} {
        set valid_subnodes [join $fp(subnodes,import_design) ", "]
    }

    puts "ERROR: Missing subnode argument"
    puts "Usage: $argv0 <subnode_name> \[run_dir\]"
    puts "Valid subnodes for import_design: $valid_subnodes"
    exit 1
}

set subnode_name [lindex $argv 0]
set run_dir [expr {$argc >= 2 ? [lindex $argv 1] : $::env(CBFLOW_RUN_DIR)}]

# Validate subnode name
if {[info exists fp(subnodes,import_design)]} {
    set valid_subnodes $fp(subnodes,import_design)
    if {[lsearch $valid_subnodes $subnode_name] == -1} {
        handle_error "Invalid subnode '$subnode_name' for import_design. Valid options: [join $valid_subnodes {, }]"
        exit 1
    }
} else {
    handle_warning "Cannot validate subnode name - fp(subnodes,import_design) not found in config"
}

# Load user configuration (needed for test_mode)
if {[file exists "$run_dir/setup/user_config.tcl"]} {
    source "$run_dir/setup/user_config.tcl"
}

# Source tool launch config (module load, tool shell, bsub, xterm)
set _launch_config "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/tool_launch_config.tcl"
if {[file exists $_launch_config]} { source $_launch_config }

set ::flow_type "FP"

# ═══════════════════════════════════════════════════════════════════════════════
# IMPORT_DESIGN SUBNODE HANDLERS
# ═══════════════════════════════════════════════════════════════════════════════

proc log_subnode_status {subnode_name status run_dir} {
    # Log subnode status to .run.status file
    set timestamp [clock format [clock seconds] -format "%Y%m%d_%H%M%S"]
    set status_file "$run_dir/.run.status"

    if {[catch {open $status_file "a"} status_fp]} {
        handle_warning "Could not open status file for writing: $status_file"
        return
    }

    puts $status_fp "$timestamp import_design:$subnode_name $status"
    close $status_fp

handle_info "Status logged: import_design:$subnode_name $status"
}

proc handle_setup_subnode {run_dir} {
    global fp project flow_type
    handle_info "Processing import_design setup subnode..."

    # Log start status
    log_subnode_status "setup" "STARTED" $run_dir

    # Determine flow parameters
    set flow_type "FP"

    # Create working directory for consolidated files
    set target_dir "$run_dir/work/$flow_type/import_design/run"
    file mkdir $target_dir
    file mkdir "$run_dir/work/$flow_type/import_design/setup"
    set node_type "import_design"
    set node_name "import_design"

    # Check test mode
    global flow
    if {[file exists "$run_dir/setup/user_config.tcl"]} {
        source "$run_dir/setup/user_config.tcl"
    }
    set test_mode false
    if {[info exists flow(test_mode)] && $flow(test_mode) eq "true"} {
        set test_mode true
    }

    if {$test_mode} {
        handle_info "\[TEST MODE\] Skipping config generation, creating placeholder files"
        set cfp [open "$target_dir/config.tcl" "w"]
        puts $cfp "# Test mode placeholder config"
        close $cfp
        set sfp [open "$target_dir/setup.tcl" "w"]
        puts $sfp "# Test mode placeholder setup"
        close $sfp
        set result "Test mode - config generation skipped"
    } else {
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

        if {[catch {exec tclsh $generate_script $flow_type $node_type $node_name $run_dir} result]} {
            handle_error "Failed to generate setup files: $result"
            return
        }
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

    # Create import_design setup info file for tracking
    set setup_info_file "$target_dir/import_design_setup_info.tcl"
    set info_fp [open $setup_info_file "w"]
    puts $info_fp "# import_design Setup Information"
    puts $info_fp "# Generated: [clock format [clock seconds]]"
    puts $info_fp ""
    puts $info_fp "array set import_design_setup {"
    puts $info_fp "    timestamp \"[clock format [clock seconds]]\""
    puts $info_fp "    flow_type \"$flow_type\""
    puts $info_fp "    node_type \"$node_type\""
    puts $info_fp "    node_name \"$node_name\""
    puts $info_fp "    run_dir \"$run_dir\""
    puts $info_fp "    config_file \"$config_file\""
    puts $info_fp "    setup_file \"$setup_file\""
    puts $info_fp "    config_exists \"[file exists $config_file]\""
    puts $info_fp "    setup_exists \"[file exists $setup_file]\""
    puts $info_fp "}"
    close $info_fp

    handle_info "✓ import_design setup completed - configuration files ready for import_design execution"

    # Log completion status
    log_subnode_status "setup" "COMPLETE" $run_dir
}

proc handle_run_subnode {run_dir} {
    handle_info "Processing import_design run subnode..."
    set flow_type "FP"
    set stage_name "import_design"
    set node_name "import_design"

    # Check test mode
    set test_mode false
    if {[info exists ::flow(test_mode)] && $::flow(test_mode) eq "true"} {
        set test_mode true
    }

    # Log start status
    log_subnode_status "run" "STARTED" $run_dir

    # Create working directory
    set target_dir "$run_dir/work/$flow_type/import_design/run"
    file mkdir $target_dir

    set cmd_file "$::env(FLOW_DIR)/cmds/FP/cadence/innovus/[expr {[info exists ::env(INNOVUS_VERSION)] ? $::env(INNOVUS_VERSION) : "v1.0.0"}]/import_design_innovus.tcl"

    if {$test_mode} {
        handle_info "\[TEST MODE\] Bypassing EDA tool invocation"
        handle_info "Command file: $cmd_file"
        if {[file exists $cmd_file]} {
            handle_info "╔══════════════════════════════════════════════════╗"
            handle_info "║  Command File: [file tail $cmd_file]"
            handle_info "╚══════════════════════════════════════════════════╝"
            set _f [open $cmd_file r]; set _lines [split [read $_f] "\n"]; close $_f
            set _lc 0
            foreach _line $_lines { incr _lc; if {$_lc <= 20} { handle_info "  $_line" } }
            if {$_lc > 20} { handle_info "  ... ([expr {$_lc - 20}] more lines)" }
            handle_info "══════════════════════════════════════════════════"
        } else { handle_info "WARNING: Command file not found: $cmd_file" }
        # Generate wrapper script even in test mode (for review)
        set _work_dir "$run_dir/work/$flow_type/$node_name/run"
        file mkdir $_work_dir
        set _tool_name [expr {[info exists ::fp(tool,name)] ? $::fp(tool,name) : "innovus"}]
        set _log_file "$_work_dir/${node_name}.log"
        set _module_cmd ""
        set _tool_shell "innovus"
        catch {
            if {[info exists ::lsf(module,$_tool_name)]} { set _module_cmd $::lsf(module,$_tool_name) }
            if {[info exists ::lsf(tool_shell,$_tool_name)]} { set _tool_shell $::lsf(tool_shell,$_tool_name) }
        }
        set _wrapper "$_work_dir/launch_${stage_name}.csh"
        set _wf [open $_wrapper "w"]
        puts $_wf "#!/bin/csh -f"
        puts $_wf "# CBFlow tool launch wrapper — $flow_type $stage_name"
        puts $_wf "# Generated: [clock format [clock seconds]]"
        if {$_module_cmd ne ""} { puts $_wf "$_module_cmd" }
        puts $_wf "$_tool_shell -f $cmd_file -output_log_file $_log_file"
        close $_wf
        catch { file attributes $_wrapper -permissions rwxr-xr-x }
        handle_info "Wrapper script: $_wrapper"
        # Show planned launch mode in test mode
        set _use_lsf false
        set _use_xterm false
        if {[info exists ::env(CBFLOW_BSUB_CMD)] && $::env(CBFLOW_BSUB_CMD) ne ""} {
            set _use_lsf true
        } elseif {[info exists flow(use_lsf)] && $flow(use_lsf) eq "true"} {
            set _use_lsf true
        } elseif {[info exists ::env(CBFLOW_USE_LSF)] && $::env(CBFLOW_USE_LSF) eq "1"} {
            set _use_lsf true
        }
        if {[info exists flow(use_xterm)] && $flow(use_xterm) eq "true"} {
            set _use_xterm true
        } elseif {[info exists ::env(CBFLOW_USE_XTERM)] && $::env(CBFLOW_USE_XTERM) eq "1"} {
            set _use_xterm true
        }
        if {$_use_lsf} {
            handle_info "\[TEST MODE\] Launch mode: LSF ([expr {$_use_xterm ? "interactive xterm" : "batch"}])"
        } elseif {$_use_xterm} {
            handle_info "\[TEST MODE\] Launch mode: xterm (local)"
        } else {
            handle_info "\[TEST MODE\] Launch mode: local execution"
        }
        handle_info "import_design run completed \[TEST MODE\]"
        log_subnode_status "run" "COMPLETE" $run_dir
        return
    }

    if {![file exists $cmd_file]} { handle_error "Command file not found: $cmd_file"; return }
    set _work_dir "$run_dir/work/$flow_type/$node_name/run"
    set _tool_name [expr {[info exists ::fp(tool,name)] ? $::fp(tool,name) : "innovus"}]
    set _log_file "$_work_dir/${node_name}.log"
    set _module_cmd ""
    set _tool_shell "innovus"
    set _wrapper_shell "/bin/csh -f"
    catch {
        if {[info exists ::lsf(module,$_tool_name)]} { set _module_cmd $::lsf(module,$_tool_name) }
        if {[info exists ::lsf(tool_shell,$_tool_name)]} { set _tool_shell $::lsf(tool_shell,$_tool_name) }
        if {[info exists ::lsf(tool_wrapper_shell)]} { set _wrapper_shell $::lsf(tool_wrapper_shell) }
    }
    set _wrapper "$_work_dir/launch_${stage_name}.csh"
    set _wf [open $_wrapper "w"]
    puts $_wf "#!$_wrapper_shell"
    puts $_wf "# CBFlow tool launch wrapper — $flow_type $stage_name"
    puts $_wf "# Generated: [clock format [clock seconds]]"
    if {$_module_cmd ne ""} { puts $_wf "$_module_cmd" }
    puts $_wf "$_tool_shell -f $cmd_file -output_log_file $_log_file"
    close $_wf
    catch { file attributes $_wrapper -permissions rwxr-xr-x }
    handle_info "Wrapper: $_wrapper"

    # Determine launch mode: LSF > XTERM > LOCAL
    set _use_lsf false
    set _use_xterm false
    if {[info exists ::env(CBFLOW_BSUB_CMD)] && $::env(CBFLOW_BSUB_CMD) ne ""} {
        set _use_lsf true
    } elseif {[info exists flow(use_lsf)] && $flow(use_lsf) eq "true"} {
        set _use_lsf true
    } elseif {[info exists ::env(CBFLOW_USE_LSF)] && $::env(CBFLOW_USE_LSF) eq "1"} {
        set _use_lsf true
    }
    if {[info exists flow(use_xterm)] && $flow(use_xterm) eq "true"} {
        set _use_xterm true
    } elseif {[info exists ::env(CBFLOW_USE_XTERM)] && $::env(CBFLOW_USE_XTERM) eq "1"} {
        set _use_xterm true
    }

    set _xterm "xterm"
    set _geom "200x50"
    catch { set _xterm $::lsf(xterm,command) }
    catch { set _geom $::lsf(xterm,geometry) }

    if {$_use_lsf} {
        if {[info exists ::env(CBFLOW_BSUB_CMD)] && $::env(CBFLOW_BSUB_CMD) ne ""} {
            set bsub_cmd $::env(CBFLOW_BSUB_CMD)
        } else {
            set _qtype "M"
            catch { set _qtype $::lsf(flow_mapping,$flow_type,$stage_name) }
            set _mem "16GB"; set _cpu "8"; set _time "4:00"
            catch { set _mem $::lsf(queue_types,$_qtype,memory) }
            catch { set _cpu $::lsf(queue_types,$_qtype,cpu) }
            catch { set _time $::lsf(queue_types,$_qtype,runtime_limit) }
            set _bsub "bsub"
            set _queue_name "normal"
            set _project ""
            set _affinity ""
            catch { set _bsub $::lsf(bsub,command) }
            catch { set _queue_name $::lsf(bsub,queue) }
            catch { set _project $::lsf(bsub,project) }
            catch { set _affinity $::lsf(bsub,affinity) }
            set bsub_cmd "$_bsub"
            if {$_project ne ""} { append bsub_cmd " -P $_project" }
            append bsub_cmd " -J cbflow_${flow_type}_${stage_name}"
            if {$_use_xterm} { append bsub_cmd " -Is" }
            append bsub_cmd " -q $_queue_name -n $_cpu -W $_time"
            append bsub_cmd " -R \"rusage\[mem=$_mem\]"
            if {$_affinity ne ""} { append bsub_cmd " $_affinity" }
            append bsub_cmd "\""
            append bsub_cmd " -o $_work_dir/lsf_${node_name}_%J.log"
            append bsub_cmd " -e $_work_dir/lsf_${node_name}_%J.err"
        }
        if {$_use_xterm} {
            handle_info "Submitting via LSF (xterm): $bsub_cmd $_xterm -e $_wrapper"
            if {[catch {exec {*}$bsub_cmd $_xterm -geometry $_geom -title "CBFlow $flow_type $stage_name" -e $_wrapper} result]} {
                handle_error "LSF submit failed: $result"; return
            }
        } else {
            handle_info "Submitting via LSF (batch): $bsub_cmd $_wrapper"
            if {[catch {exec {*}$bsub_cmd $_wrapper} result]} { handle_error "LSF submit failed: $result"; return }
        }
        puts $result
    } elseif {$_use_xterm} {
        handle_info "Launching in xterm: $_xterm -geometry $_geom -e $_wrapper"
        exec $_xterm -geometry $_geom -title "CBFlow $flow_type $stage_name" -e $_wrapper &
    } else {
        handle_info "Executing locally: $_wrapper"
        if {[catch {exec $_wrapper} result]} { handle_error "$stage_name failed: $result"; return }
        puts $result
    }
    handle_info "import_design run completed"

    # Log completion status
    log_subnode_status "run" "COMPLETE" $run_dir
}

proc handle_validate_subnode {run_dir} {
    handle_info "Processing import_design validate subnode..."
    set flow_type "FP"
    global flow
    if {[info exists flow(test_mode)] && $flow(test_mode) eq "true"} {
        handle_info "\[TEST MODE\] Validation skipped"
        log_subnode_status "validate" "COMPLETE" $run_dir
        return
    }

    # Log start status
    log_subnode_status "validate" "STARTED" $run_dir

    # Create working directory
    set target_dir "$run_dir/work/$flow_type/import_design/validate"
    file mkdir $target_dir

    set validation_passed true
    set validation_errors {}
    set validation_warnings {}

    # Check that run subnode completed successfully
    set run_dir_check "$run_dir/work/$flow_type/import_design/run"
    if {![file exists $run_dir_check]} {
        lappend validation_errors "import_design run directory not found: $run_dir_check"
        set validation_passed false
    }

    # Verify design import artifacts exist
    set db_dir "$run_dir/work/$flow_type/import_design/run"
    foreach check_file [list "config.tcl" "setup.tcl"] {
        if {[file exists "$db_dir/$check_file"]} {
            handle_info "Validated: $check_file exists"
        } else {
            lappend validation_warnings "Expected file not found: $db_dir/$check_file"
        }
    }

    # Check for import errors in log
    set log_pattern "$run_dir/work/$flow_type/import_design/run/*.log"
    set log_files [glob -nocomplain $log_pattern]
    foreach log_file $log_files {
        set fd [open $log_file "r"]
        set log_content [read $fd]
        close $fd
        if {[regexp -nocase {ERROR|FATAL} $log_content]} {
            lappend validation_warnings "Errors found in log: [file tail $log_file]"
        }
    }

    # Report validation results
    if {$validation_passed} {
        handle_info "✓ import_design validation passed"
    } else {
        handle_error "✗ import_design validation failed"
        foreach error $validation_errors {
            handle_error "  - $error"
        }
    }

    foreach warning $validation_warnings {
        handle_warning "  - $warning"
    }

    # Create validation report
    set validation_report "$target_dir/import_design_validation.rpt"
    set rpt_fp [open $validation_report "w"]
    puts $rpt_fp "# import_design Validation Report"
    puts $rpt_fp "# Generated: [clock format [clock seconds]]"
    puts $rpt_fp ""
    puts $rpt_fp "Validation Status: [expr {$validation_passed ? "PASSED" : "FAILED"}]"
    puts $rpt_fp "Errors: [llength $validation_errors]"
    puts $rpt_fp "Warnings: [llength $validation_warnings]"
    puts $rpt_fp ""
    if {[llength $validation_errors] > 0} {
        puts $rpt_fp "ERRORS:"
        foreach error $validation_errors {
            puts $rpt_fp "  - $error"
        }
        puts $rpt_fp ""
    }
    if {[llength $validation_warnings] > 0} {
        puts $rpt_fp "WARNINGS:"
        foreach warning $validation_warnings {
            puts $rpt_fp "  - $warning"
        }
        puts $rpt_fp ""
    }
    close $rpt_fp

    handle_info "✓ Validation report created: $validation_report"

    # Log completion status
    if {$validation_passed} {
        log_subnode_status "validate" "COMPLETE" $run_dir
    } else {
        log_subnode_status "validate" "FAILED" $run_dir
    }
}

proc handle_finish_subnode {run_dir} {
    handle_info "Processing import_design finish subnode..."
    set flow_type "FP"

    # Log start status
    log_subnode_status "finish" "STARTED" $run_dir

    # Create working directory
    set target_dir "$run_dir/work/$flow_type/import_design/finish"
    file mkdir $target_dir

    # Create finish timestamp
    set finish_file "$target_dir/import_design_finish.timestamp"
    set finish_fp [open $finish_file "w"]
    puts $finish_fp "# import_design Finish Timestamp"
    puts $finish_fp "# Generated: [clock format [clock seconds]]"
    puts $finish_fp ""
    puts $finish_fp "import_design_finish_time: [clock seconds]"
    puts $finish_fp "import_design_finish_date: [clock format [clock seconds]]"
    close $finish_fp

    handle_info "✓ import_design finish completed - stage ready for next step"

    # Log completion status
    log_subnode_status "finish" "COMPLETE" $run_dir
}

# ═══════════════════════════════════════════════════════════════════════════════
# MAIN EXECUTION
# ═══════════════════════════════════════════════════════════════════════════════

handle_info "Starting import_design subnode handler for '$subnode_name' in $run_dir"

# Dispatch to appropriate subnode handler
switch $subnode_name {
    "setup" {
        handle_setup_subnode $run_dir
    }
    "run" {
        handle_run_subnode $run_dir
    }
    "validate" {
        handle_validate_subnode $run_dir
    }
    "finish" {
        handle_finish_subnode $run_dir
    }
    default {
        handle_error "Unknown subnode: $subnode_name"
        exit 1
    }
}

handle_info "import_design subnode '$subnode_name' completed successfully"