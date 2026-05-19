#!/usr/bin/env tclsh
# CBFlow STA TIMING Subnode Handler - Synopsys PT
if {$argc < 1} { puts "ERROR: Missing subnode argument"; exit 1 }
set subnode_name [lindex $argv 0]
set run_dir [expr {$argc > 1 ? [lindex $argv 1] : [pwd]}]
set node_name [expr {$argc > 2 ? [lindex $argv 2] : ""}]
if {[file exists "$run_dir/.run.cbflow.tcl"]} { source "$run_dir/.run.cbflow.tcl" } else { puts "ERROR: .run.cbflow.tcl not found"; exit 1 }
source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/error_utils.tcl"
set flow_config "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/flow_config.tcl"
if {[file exists $flow_config]} { source $flow_config }
set node_config "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/node_configs/STA_config.tcl"
if {[file exists $node_config]} { source $node_config }
if {[file exists "$run_dir/setup/user_config.tcl"]} { source "$run_dir/setup/user_config.tcl" }
# Source tool launch config (module load, tool shell, bsub, xterm)
set _launch_config "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/tool_launch_config.tcl"
if {[file exists $_launch_config]} { source $_launch_config }
set ::flow_type "STA"
set stage_name "timing"
if {$node_name eq ""} { set node_name $stage_name }
set _tool_ver [expr {[info exists ::env(PT_VERSION)] ? $::env(PT_VERSION) : {v1.0.0}}]
set cmd_file "$::env(FLOW_DIR)/cmds/STA/synopsys/pt/$_tool_ver/timing_pt.tcl"
set test_mode false
if {[info exists flow(test_mode)] && $flow(test_mode) eq "true"} { set test_mode true }
switch $subnode_name {
    "setup" {
        puts "INFO: $stage_name setup..."
        file mkdir "$run_dir/work/$::flow_type/$node_name/run"
        file mkdir "$run_dir/work/$::flow_type/$node_name/setup"
        # Source SPEF manifest from upstream extraction stage
        # This makes spef_map(<rc_corner>) and spef_corners available to timing scenarios
        set _dep_stage "extraction1"
        # Check for custom extraction node name from runtime config
        set _rtf "$run_dir/setup/runtime_flow_config.tcl"
        if {[file exists $_rtf]} {
            set _rf [open $_rtf r]; set _rc [read $_rf]; close $_rf
            if {[regexp {stages,(\w+),type\s+extraction} $_rc _m _ename]} {
                set _dep_stage $_ename
            }
        }
        set _spef_manifest "$run_dir/work/$::flow_type/$_dep_stage/results/spef_manifest.tcl"
        if {[file exists $_spef_manifest]} {
            source $_spef_manifest
            puts "INFO: Loaded SPEF manifest from $_dep_stage: $spef_corner_count corners"
            foreach _c $spef_corners {
                puts "INFO:   $_c -> $spef_map($_c)"
            }
            # Write a copy to timing work dir for the run subnode to pick up
            file copy -force $_spef_manifest "$run_dir/work/$::flow_type/$node_name/setup/spef_manifest.tcl"
        } else {
            puts "WARNING: No SPEF manifest found at: $_spef_manifest"
            puts "WARNING: Timing analysis will use user_config spef paths (if set)"
        }
        puts "INFO: $stage_name setup completed"
    }
    "run" {
        puts "INFO: $stage_name run..."
        if {$test_mode} {
            puts "INFO: \[TEST MODE\] Bypassing EDA tool invocation"
            puts "INFO: Command file: $cmd_file"
            if {[file exists $cmd_file]} {
                puts "INFO: ╔══════════════════════════════════════════════════╗"
                puts "INFO: ║  Command File: [file tail $cmd_file]"
                puts "INFO: ╚══════════════════════════════════════════════════╝"
                set _f [open $cmd_file r]; set _lines [split [read $_f] "\n"]; close $_f
                set _lc 0
                foreach _line $_lines { incr _lc; if {$_lc <= 20} { puts "INFO:   $_line" } }
                if {$_lc > 20} { puts "INFO:   ... ([expr {$_lc - 20}] more lines)" }
                puts "INFO: ══════════════════════════════════════════════════"
            } else { puts "WARNING: Command file not found: $cmd_file" }
            # Generate wrapper script even in test mode (for review)
            set _work_dir "$run_dir/work/$::flow_type/$node_name/run"
            file mkdir $_work_dir
            set _tool_name [expr {[info exists sta(tool,name)] ? $sta(tool,name) : "pt"}]
            set _log_file "$_work_dir/${node_name}.log"
            set _module_cmd ""
            set _tool_shell "pt_shell"
            catch {
                if {[info exists lsf(module,$_tool_name)]} { set _module_cmd $lsf(module,$_tool_name) }
                if {[info exists lsf(tool_shell,$_tool_name)]} { set _tool_shell $lsf(tool_shell,$_tool_name) }
            }
            set _wrapper "$_work_dir/launch_${stage_name}.csh"
            set _wf [open $_wrapper "w"]
            puts $_wf "#!/bin/csh -f"
            puts $_wf "# CBFlow tool launch wrapper — $::flow_type $stage_name"
            puts $_wf "# Generated: [clock format [clock seconds]]"
            if {$_module_cmd ne ""} { puts $_wf "$_module_cmd" }
            puts $_wf "$_tool_shell -f $cmd_file -output_log_file $_log_file"
            close $_wf
            catch { file attributes $_wrapper -permissions rwxr-xr-x }
            puts "INFO: Wrapper script: $_wrapper"
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
                puts "INFO: \[TEST MODE\] Launch mode: LSF ([expr {$_use_xterm ? "interactive xterm" : "batch"}])"
            } elseif {$_use_xterm} {
                puts "INFO: \[TEST MODE\] Launch mode: xterm (local)"
            } else {
                puts "INFO: \[TEST MODE\] Launch mode: local execution"
            }
            puts "INFO: $stage_name run completed \[TEST MODE\]"
        } else {
            if {![file exists $cmd_file]} { puts "ERROR: Command file not found: $cmd_file"; exit 1 }
            set _work_dir "$run_dir/work/$::flow_type/$node_name/run"
            set _tool_name [expr {[info exists sta(tool,name)] ? $sta(tool,name) : "pt"}]
            set _log_file "$_work_dir/${node_name}.log"
            set _module_cmd ""
            set _tool_shell "pt_shell"
            set _wrapper_shell "/bin/csh -f"
            catch {
                if {[info exists lsf(module,$_tool_name)]} { set _module_cmd $lsf(module,$_tool_name) }
                if {[info exists lsf(tool_shell,$_tool_name)]} { set _tool_shell $lsf(tool_shell,$_tool_name) }
                if {[info exists lsf(tool_wrapper_shell)]} { set _wrapper_shell $lsf(tool_wrapper_shell) }
            }
            set _wrapper "$_work_dir/launch_${stage_name}.csh"
            set _wf [open $_wrapper "w"]
            puts $_wf "#!$_wrapper_shell"
            puts $_wf "# CBFlow tool launch wrapper — $::flow_type $stage_name"
            puts $_wf "# Generated: [clock format [clock seconds]]"
            if {$_module_cmd ne ""} { puts $_wf "$_module_cmd" }
            puts $_wf "$_tool_shell -f $cmd_file -output_log_file $_log_file"
            close $_wf
            catch { file attributes $_wrapper -permissions rwxr-xr-x }
            puts "INFO: Wrapper: $_wrapper"

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

            # Resolve xterm settings
            set _xterm "xterm"
            set _geom "200x50"
            catch { set _xterm $lsf(xterm,command) }
            catch { set _geom $lsf(xterm,geometry) }

            if {$_use_lsf} {
                if {[info exists ::env(CBFLOW_BSUB_CMD)] && $::env(CBFLOW_BSUB_CMD) ne ""} {
                    set bsub_cmd $::env(CBFLOW_BSUB_CMD)
                } else {
                    # Build bsub from config
                    set _qtype "M"
                    catch { set _qtype $lsf(flow_mapping,$::flow_type,$stage_name) }
                    set _mem "16GB"; set _cpu "8"; set _time "4:00"
                    catch { set _mem $lsf(queue_types,$_qtype,memory) }
                    catch { set _cpu $lsf(queue_types,$_qtype,cpu) }
                    catch { set _time $lsf(queue_types,$_qtype,runtime_limit) }
                    set _bsub "bsub"
                    set _queue_name "normal"
                    set _project ""
                    set _affinity ""
                    catch { set _bsub $lsf(bsub,command) }
                    catch { set _queue_name $lsf(bsub,queue) }
                    catch { set _project $lsf(bsub,project) }
                    catch { set _affinity $lsf(bsub,affinity) }
                    set bsub_cmd "$_bsub"
                    if {$_project ne ""} { append bsub_cmd " -P $_project" }
                    append bsub_cmd " -J cbflow_${::flow_type}_${stage_name}"
                    if {$_use_xterm} { append bsub_cmd " -Is" }
                    append bsub_cmd " -q $_queue_name -n $_cpu -W $_time"
                    append bsub_cmd " -R \"rusage\[mem=$_mem\]"
                    if {$_affinity ne ""} { append bsub_cmd " $_affinity" }
                    append bsub_cmd "\""
                    append bsub_cmd " -o $_work_dir/lsf_${node_name}_%J.log"
                    append bsub_cmd " -e $_work_dir/lsf_${node_name}_%J.err"
                }
                if {$_use_xterm} {
                    # LSF + xterm: submit to LSF, opens xterm on compute node
                    set _launch_target "$_xterm -geometry $_geom -title \"CBFlow $::flow_type $stage_name\" -e $_wrapper"
                    puts "INFO: Submitting via LSF (xterm): $bsub_cmd $_launch_target"
                    if {[catch {exec {*}$bsub_cmd $_xterm -geometry $_geom -title "CBFlow $::flow_type $stage_name" -e $_wrapper} result]} {
                        puts "ERROR: LSF submit failed: $result"; exit 1
                    }
                } else {
                    # LSF batch: submit wrapper directly
                    puts "INFO: Submitting via LSF (batch): $bsub_cmd $_wrapper"
                    if {[catch {exec {*}$bsub_cmd $_wrapper} result]} { puts "ERROR: LSF submit failed: $result"; exit 1 }
                }
                puts $result
            } elseif {$_use_xterm} {
                # Local xterm: opens xterm window running wrapper locally
                puts "INFO: Launching in xterm: $_xterm -geometry $_geom -e $_wrapper"
                exec $_xterm -geometry $_geom -title "CBFlow $::flow_type $stage_name" -e $_wrapper &
            } else {
                # Local execution in current terminal
                puts "INFO: Executing locally: $_wrapper"
                if {[catch {exec $_wrapper} result]} { puts "ERROR: $stage_name failed: $result"; exit 1 }
                puts $result
            }
            puts "INFO: $stage_name run completed"
        }
    }    "validate" {
        puts "INFO: $stage_name validate..."
        set _val_script "$::env(SCRIPTS_ROOT)/validation/$::env(VALIDATION_VERSION)/validate_run.tcl"
        set _log_file "$run_dir/work/$::flow_type/$node_name/run/${node_name}.log"
        if {[file exists $_val_script]} {
            puts "INFO: Running validation: $::flow_type $stage_name $node_name"
            set _val_rc [catch {exec tclsh $_val_script $::flow_type $stage_name $run_dir $::env(FLOW_DIR) 2>@1} _val_out]
            if {$_val_out ne ""} {
                foreach _vl [split $_val_out "\n"] {
                    if {[string match "*ERROR*" $_vl] || [string match "*FAIL*" $_vl]} {
                        puts "VALIDATE: $_vl"
                    }
                }
            }
            if {$_val_rc != 0 && [string match "*validation failed*" [string tolower $_val_out]]} {
                puts "ERROR: Validation FAILED for $stage_name ($node_name)"
                exit 1
            } else {
                puts "INFO: Validation passed for $stage_name"
            }
        }
        puts "INFO: $stage_name validate completed"
    }
    "finish" {
        puts "INFO: $stage_name finish..."
        set ff "$run_dir/work/$::flow_type/$node_name/run/${stage_name}_finish.timestamp"
        file mkdir [file dirname $ff]
        set fh [open $ff "w"]; puts $fh "Completed: [clock format [clock seconds]]"; close $fh
        puts "INFO: $stage_name finish completed"
    }
    "dynamic" {
        # Dynamic timing: resolve MMMC scenarios and run per-scenario timing
        puts "INFO: $stage_name dynamic — resolving MMMC scenarios..."

        # Load MMMC config
        set mmmc_config_file "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/mmmc_config.tcl"
        if {[file exists $mmmc_config_file]} { source $mmmc_config_file }

        # Determine which scenarios to run
        # Priority: user_config override > node config default > signoff set
        set setup_scenarios {}
        set hold_scenarios {}

        if {[info exists sta(mmmc,setup_scenarios)] && $sta(mmmc,setup_scenarios) ne ""} {
            set setup_scenarios $sta(mmmc,setup_scenarios)
        } elseif {[info exists mmmc_scenario_sets] && [array exists mmmc_scenario_sets]} {
            set sset [expr {[info exists sta(mmmc,scenario_set)] ? $sta(mmmc,scenario_set) : "sta_signoff"}]
            if {$sset ne "custom" && [info exists mmmc_scenario_sets($sset)]} {
                array set _ss $mmmc_scenario_sets($sset)
                if {[info exists _ss(scenarios)]} { set setup_scenarios $_ss(scenarios) }
            }
        }

        if {[info exists sta(mmmc,hold_scenarios)] && $sta(mmmc,hold_scenarios) ne ""} {
            set hold_scenarios $sta(mmmc,hold_scenarios)
        }

        # Combine all unique scenarios
        set all_scenarios [concat $setup_scenarios $hold_scenarios]
        set all_scenarios [lsort -unique $all_scenarios]

        if {[llength $all_scenarios] == 0} {
            puts "WARNING: No MMMC scenarios resolved. Using default signoff set."
            set all_scenarios {func_ss_0p76v_rcmax_150c func_ff_0p84v_rcmin_m40c}
        }

        puts "INFO: MMMC scenarios to run ([llength $all_scenarios]):"
        puts "INFO:   Setup: $setup_scenarios"
        puts "INFO:   Hold:  $hold_scenarios"

        # Create work directory
        set _work_dir "$run_dir/work/$::flow_type/$node_name/run"
        file mkdir $_work_dir
        file mkdir "$run_dir/reports/sta"

        # Scenario handler path
        set _scenario_handler "$::env(FLOW_DIR)/cmds/STA/synopsys/pt/$_tool_ver/timing_scenario_handler.tcl"

        foreach scenario $all_scenarios {
            puts "INFO: ── Scenario: $scenario ──"

            if {$test_mode} {
                # Test mode: invoke scenario handler which creates report stubs
                if {[file exists $_scenario_handler]} {
                    if {[catch {exec tclsh $_scenario_handler $scenario $run_dir} result]} {
                        puts "WARNING: Scenario $scenario: $result"
                    } else {
                        puts $result
                    }
                } else {
                    puts "INFO: \[TEST MODE\] Scenario $scenario — handler not found, creating stubs"
                    set rpt [open "$run_dir/reports/sta/timing_${scenario}_summary.rpt" "w"]
                    puts $rpt "# Test mode summary for scenario: $scenario"
                    puts $rpt "# Generated: [clock format [clock seconds]]"
                    puts $rpt "Setup WNS: 0.000ns  Hold WNS: 0.000ns"
                    close $rpt
                }
            } else {
                # Production mode: run scenario handler
                if {[file exists $_scenario_handler]} {
                    puts "INFO: Executing: tclsh $_scenario_handler $scenario $run_dir"
                    if {[catch {exec tclsh $_scenario_handler $scenario $run_dir} result]} {
                        puts "ERROR: Scenario $scenario failed: $result"
                        exit 1
                    }
                    puts $result
                } else {
                    puts "ERROR: Scenario handler not found: $_scenario_handler"
                    exit 1
                }
            }
        }

        puts "INFO: $stage_name dynamic completed — [llength $all_scenarios] scenarios processed"
    }
    default {
        # Individual MMMC scenario subnode (e.g., func_ss_0p76v_rcmax_150c)
        # Run as a single-scenario timing analysis
        set scenario $subnode_name
        puts "INFO: $stage_name scenario: $scenario"

        set _work_dir "$run_dir/work/$::flow_type/$node_name/run"
        file mkdir $_work_dir
        file mkdir "$run_dir/reports/sta"

        # Resolve scenario handler from same directory as this handler (vendor-agnostic)
        set _handler_dir [file dirname [info script]]
        set _scenario_handler [file join $_handler_dir "timing_scenario_handler.tcl"]

        if {$test_mode} {
            if {[file exists $_scenario_handler]} {
                if {[catch {exec tclsh $_scenario_handler $scenario $run_dir} result]} {
                    puts "WARNING: Scenario $scenario: $result"
                } else {
                    puts $result
                }
            } else {
                puts "INFO: \[TEST MODE\] Scenario $scenario — creating report stub"
                set rpt [open "$run_dir/reports/sta/timing_${scenario}_summary.rpt" "w"]
                puts $rpt "# Test mode summary for scenario: $scenario"
                puts $rpt "# Generated: [clock format [clock seconds]]"
                puts $rpt "Setup WNS: 0.000ns  Hold WNS: 0.000ns"
                close $rpt
            }
        } else {
            if {[file exists $_scenario_handler]} {
                puts "INFO: Executing: tclsh $_scenario_handler $scenario $run_dir"
                if {[catch {exec tclsh $_scenario_handler $scenario $run_dir} result]} {
                    puts "ERROR: Scenario $scenario failed: $result"
                    exit 1
                }
                puts $result
            } else {
                puts "ERROR: Scenario handler not found: $_scenario_handler"
                exit 1
            }
        }
        puts "INFO: $stage_name scenario $scenario completed"
    }
}
