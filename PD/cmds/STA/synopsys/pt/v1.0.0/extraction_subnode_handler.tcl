#!/usr/bin/env tclsh
# CBFlow STA EXTRACTION Subnode Handler - Synopsys PT
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
# Source MMMC config for rc_corners array and tech config for parasitic file paths
set _mmmc_config "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/mmmc_config.tcl"
if {[file exists $_mmmc_config]} { source $_mmmc_config }
if {[info exists ::env(TECH_NAME)] && $::env(TECH_NAME) ne "" && [info exists ::env(TECH_VERSION)]} {
    set _tc "$::env(CONFIG_ROOT)/tech/$::env(TECH_NAME)/$::env(TECH_VERSION)/tech_config.tcl"
    if {[file exists $_tc]} { source $_tc }
}
# Source tool launch config (module load, tool shell, bsub, xterm)
set _launch_config "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/tool_launch_config.tcl"
if {[file exists $_launch_config]} { source $_launch_config }
set ::flow_type "STA"
set stage_name "extraction"
if {$node_name eq ""} { set node_name $stage_name }
set _tool_ver [expr {[info exists ::env(PT_VERSION)] ? $::env(PT_VERSION) : {v1.0.0}}]
set cmd_file "$::env(FLOW_DIR)/cmds/STA/synopsys/pt/$_tool_ver/extraction_pt.tcl"
set test_mode false
if {[info exists flow(test_mode)] && $flow(test_mode) eq "true"} { set test_mode true }
switch $subnode_name {
    "setup" {
        puts "INFO: $stage_name setup..."
        file mkdir "$run_dir/work/$::flow_type/$node_name/run"
        file mkdir "$run_dir/work/$::flow_type/$node_name/setup"
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
    }
    "validate" {
        puts "INFO: $stage_name validate..."
        # Generate SPEF manifest: list all per-corner SPEF files for downstream timing stage
        set _ext_dir "$run_dir/work/$::flow_type/$node_name"
        set _manifest "$_ext_dir/results/spef_manifest.tcl"
        file mkdir [file dirname $_manifest]
        set _mf [open $_manifest "w"]
        puts $_mf "# SPEF Manifest — generated by extraction validate"
        puts $_mf "# Maps RC corners to their extracted SPEF files"
        puts $_mf "# Generated: [clock format [clock seconds]]"
        puts $_mf ""
        set _corner_count 0
        set _corner_list {}
        foreach _d [lsort [glob -nocomplain -tails -directory $_ext_dir rc_*]] {
            set _spef_files [glob -nocomplain "$_ext_dir/$_d/results/*.spef"]
            if {[llength $_spef_files] > 0} {
                set _spef_path [lindex $_spef_files 0]
                puts $_mf "set spef_map($_d) \"$_spef_path\""
                lappend _corner_list $_d
                incr _corner_count
            }
        }
        puts $_mf ""
        puts $_mf "set spef_corners {[join $_corner_list " "]}"
        puts $_mf "set spef_corner_count $_corner_count"
        close $_mf
        puts "INFO: SPEF manifest: $_manifest ($_corner_count corners)"
        foreach _c $_corner_list { puts "INFO:   $_c -> [set spef_map($_c) ""]" }
        if {$test_mode && $_corner_count == 0} { puts "INFO: \[TEST MODE\] No SPEF files found (expected in test mode)" }
        puts "INFO: $stage_name validate completed"
    }
    "finish" {
        puts "INFO: $stage_name finish..."
        set ff "$run_dir/work/$::flow_type/$node_name/run/${stage_name}_finish.timestamp"
        file mkdir [file dirname $ff]
        set fh [open $ff "w"]; puts $fh "Completed: [clock format [clock seconds]]"; close $fh
        puts "INFO: $stage_name finish completed"
    }
    default {
        # Dynamic RC corner subnode (e.g., rc_max, rc_typ, rc_min, rc_max_cworst)
        if {[string match "rc_*" $subnode_name]} {
            puts "INFO: extraction $subnode_name ($node_name)..."
            set _corner_dir "$run_dir/work/$::flow_type/$node_name/$subnode_name"
            file mkdir "$_corner_dir/run"
            file mkdir "$_corner_dir/results"

            # Resolve RC parasitic file from tech_config
            # Keys: tech(rcx,<rc_corner>,nxtgrd), tech(rcx,<rc_corner>,tluplus), tech(rcx,<rc_corner>,qrc)
            # Priority: nxtgrd (StarRC) → tluplus (Synopsys) → qrc (Cadence)
            set _rc_file ""
            set _rc_file_type ""
            set _rc_corner $subnode_name  ;# e.g., rc_max, rc_typ, rc_min, rc_max_cworst

            # Try nxtgrd first (StarRC native format)
            if {[info exists tech(rcx,${_rc_corner},nxtgrd)] && $tech(rcx,${_rc_corner},nxtgrd) ne ""} {
                set _rc_file $tech(rcx,${_rc_corner},nxtgrd)
                set _rc_file_type "nxtgrd"
            }
            # Try tluplus (Synopsys format)
            if {$_rc_file eq "" && [info exists tech(rcx,${_rc_corner},tluplus)] && $tech(rcx,${_rc_corner},tluplus) ne ""} {
                set _rc_file $tech(rcx,${_rc_corner},tluplus)
                set _rc_file_type "tluplus"
            }
            # Try qrc (Cadence format)
            if {$_rc_file eq "" && [info exists tech(rcx,${_rc_corner},qrc)] && $tech(rcx,${_rc_corner},qrc) ne ""} {
                set _rc_file $tech(rcx,${_rc_corner},qrc)
                set _rc_file_type "qrc"
            }

            # Also resolve mapping file and LEF for StarRC
            set _mapping_file ""
            if {[info exists tech(tluplus_map)]} { set _mapping_file $tech(tluplus_map) }
            set _lef_file ""
            if {[info exists tech(lef_tech)]} { set _lef_file $tech(lef_tech) }
            set _def_file ""
            if {[info exists sta(input,def_file)]} { set _def_file $sta(input,def_file) }

            if {$test_mode} {
                puts "INFO: \[TEST MODE\] Extraction for RC corner: $subnode_name"
                puts "INFO:   RC file:     $_rc_file ($_rc_file_type)"
                puts "INFO:   Mapping:     $_mapping_file"
                puts "INFO:   LEF:         $_lef_file"
                puts "INFO:   DEF:         $_def_file"
                puts "INFO:   Corner dir:  $_corner_dir"
                # Create mock SPEF output for downstream stages
                set _spef "$_corner_dir/results/${node_name}_${subnode_name}.spef"
                set fh [open $_spef "w"]
                puts $fh "// SPEF for $subnode_name extraction"
                puts $fh "// Corner: $subnode_name  Node: $node_name"
                puts $fh "// RC file: $_rc_file ($_rc_file_type)"
                puts $fh "// Generated: [clock format [clock seconds]]"
                close $fh
                puts "INFO: Mock SPEF: $_spef"
                puts "INFO: extraction $subnode_name completed \[TEST MODE\]"
            } else {
                if {![file exists $cmd_file]} { puts "ERROR: Command file not found: $cmd_file"; exit 1 }
                set _work_dir "$_corner_dir/run"
                set _tool_name [expr {[info exists sta(tool,name)] ? $sta(tool,name) : "pt"}]
                set _log_file "$_work_dir/${node_name}_${subnode_name}.log"
                set _tool_shell "pt_shell"
                catch { if {[info exists lsf(tool_shell,$_tool_name)]} { set _tool_shell $lsf(tool_shell,$_tool_name) } }
                # Set corner-specific env vars for the cmd file
                set ::env(CBFLOW_RC_CORNER) $subnode_name
                set ::env(CBFLOW_RC_FILE) $_rc_file
                set ::env(CBFLOW_RC_FILE_TYPE) $_rc_file_type
                set ::env(CBFLOW_EXTRACTION_DIR) $_corner_dir
                set ::env(CBFLOW_MAPPING_FILE) $_mapping_file
                set ::env(CBFLOW_LEF_FILE) $_lef_file
                set ::env(CBFLOW_DEF_FILE) $_def_file

                # Determine extraction mode: StarRC standalone or PT internal
                set _ext_mode "starrc"
                if {[info exists sta(extraction,mode)]} { set _ext_mode $sta(extraction,mode) }

                if {$_ext_mode eq "starrc"} {
                    # Generate StarRC command file and invoke StarXtract
                    set _star_cmd "$_work_dir/star_cmd_${subnode_name}"
                    set _spef_out "$_corner_dir/results/${node_name}_${subnode_name}.spef"
                    set _starrc_bin "StarXtract"
                    if {[info exists sta(extraction,starrc_binary)]} { set _starrc_bin $sta(extraction,starrc_binary) }
                    set _coupling "RCCC"
                    if {[info exists sta(extraction,coupling)]} { set _coupling $sta(extraction,coupling) }

                    # Write star_cmd file
                    set _fh [open $_star_cmd "w"]
                    puts $_fh "STAR_DIRECTORY: $_work_dir/star_work"
                    puts $_fh "BLOCK: $::flow(design_name)"
                    if {$_rc_file_type eq "nxtgrd"} {
                        puts $_fh "TCAD_GRD_FILE: $_rc_file"
                    } elseif {$_rc_file_type eq "tluplus"} {
                        puts $_fh "TCAD_GRD_FILE: $_rc_file"
                    }
                    if {$_mapping_file ne ""} { puts $_fh "MAPPING_FILE: $_mapping_file" }
                    if {$_def_file ne ""}     { puts $_fh "TOP_DEF_FILE: $_def_file" }
                    if {$_lef_file ne ""}     { puts $_fh "LEF_FILE: $_lef_file" }
                    puts $_fh "NETLIST_FILE: $_spef_out"
                    puts $_fh "EXTRACTION: $_coupling"
                    puts $_fh "COUPLE_TO_GROUND: NO"
                    puts $_fh "STAR_SPEF_FORMAT: YES"
                    puts $_fh "OPERATING_TEMPERATURE: [lindex [array get rc_corners $subnode_name] 1]"
                    close $_fh

                    puts "INFO: Generated StarRC cmd: $_star_cmd"
                    puts "INFO: Invoking: $_starrc_bin $_star_cmd"
                    file mkdir "$_work_dir/star_work"
                    if {[catch {exec $_starrc_bin $_star_cmd >& "$_work_dir/${node_name}_${subnode_name}.log"} result]} {
                        puts "ERROR: StarRC extraction $subnode_name failed: $result"; exit 1
                    }
                } else {
                    # PT internal extraction
                    puts "INFO: Executing PT extraction for $subnode_name (rc_file=$_rc_file)"
                    if {[catch {exec $_tool_shell -f $cmd_file -output_log_file $_log_file} result]} {
                        puts "ERROR: extraction $subnode_name failed: $result"; exit 1
                    }
                }
                puts "INFO: extraction $subnode_name completed"
            }
        } else {
            puts "ERROR: Unknown subnode: $subnode_name"; exit 1
        }
    }
}
