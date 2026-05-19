#!/usr/bin/env tclsh
# CBFlow PNR EXPORT_DATA1 Subnode Handler - Synopsys FC
if {$argc < 1} { puts "ERROR: Missing subnode argument"; exit 1 }
set subnode_name [lindex $argv 0]
set run_dir [expr {$argc > 1 ? [lindex $argv 1] : [pwd]}]
set node_name [expr {$argc > 2 ? [lindex $argv 2] : ""}]
if {[file exists "$run_dir/.run.cbflow.tcl"]} { source "$run_dir/.run.cbflow.tcl" } else { puts "ERROR: .run.cbflow.tcl not found"; exit 1 }
source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/error_utils.tcl"
set flow_config "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/flow_config.tcl"
if {[file exists $flow_config]} { source $flow_config }
set node_config "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/node_configs/SYNTH_PNR_config.tcl"
if {[file exists $node_config]} { source $node_config }
if {[file exists "$run_dir/setup/user_config.tcl"]} { source "$run_dir/setup/user_config.tcl" }
# Source tool launch config (module load, tool shell, bsub, xterm)
set _launch_config "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/tool_launch_config.tcl"
if {[file exists $_launch_config]} { source $_launch_config }
set ::flow_type "SYNTH_PNR"
set stage_name "export_data"
if {$node_name eq ""} { set node_name $stage_name }
set _tool_ver [expr {[info exists ::env(FC_VERSION)] ? $::env(FC_VERSION) : {v1.0.0}}]
set cmd_file "$::env(FLOW_DIR)/cmds/SYNTH_PNR/synopsys/fc/$_tool_ver/export_data_fc.tcl"
set test_mode false
if {[info exists flow(test_mode)] && $flow(test_mode) eq "true"} { set test_mode true }
switch $subnode_name {
    "setup" {
        puts "INFO: $stage_name setup..."
        file mkdir "$run_dir/work/$::flow_type/$node_name/run"
        file mkdir "$run_dir/work/$::flow_type/$node_name/setup"
        # Generate setup.tcl and config.tcl
        if {[info exists ::env(GENERATION_VERSION)] && $::env(GENERATION_VERSION) ne ""} {
            set gen_script "$::env(FLOW_DIR)/utils/generation/$::env(GENERATION_VERSION)/generate_setup.tcl"
            if {[file exists $gen_script]} {
                puts "INFO: Generating setup files via generate_setup.tcl..."
                if {[catch {exec tclsh $gen_script $::flow_type $node_name ${node_name}_default $run_dir} gen_result]} {
                    puts "WARNING: generate_setup.tcl: $gen_result"
                } else {
                    puts "INFO: Setup files generated: $gen_result"
                }
            }
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
            set _tool_name [expr {[info exists synth_pnr(tool,name)] ? $synth_pnr(tool,name) : "fc"}]
            set _log_file "$_work_dir/${node_name}.log"
            set _module_cmd ""
            set _tool_shell "fc_shell"
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
            # Create dummy output files matching EXACTLY what real FC writes
            set _dn [expr {[info exists flow(design_name)] ? $flow(design_name) : "design"}]
            set _out "$run_dir/outputs"
            file mkdir $_out
            # Netlists (6 variants — matches write_verilog commands in export_data_fc.tcl)
            foreach {_suf _desc} {
                .v              "// Logic-only netlist (no PG)"
                .pt.v           "// PrimeTime netlist (with diodes/DCAP)"
                .fm.v           "// Formality netlist (with pg, no supply stmts)"
                .lvs.v          "// LVS netlist (with pg & physical cells)"
                .vc_lp.v        "// VC_LP netlist (no diodes, no supply stmts)"
                .dc.v           "// DC comparison netlist (no diodes)"
            } {
                set _f [open "$_out/${_dn}${_suf}" "w"]; puts $_f "$_desc\n// \[TEST MODE\]"; close $_f
            }
            # Physical data
            set _f [open "$_out/${_dn}.gds" "w"]; puts $_f "// GDS-II \[TEST MODE\]"; close $_f
            set _f [open "$_out/${_dn}.def" "w"]; puts $_f "// DEF \[TEST MODE\]"; close $_f
            set _f [open "$_out/${_dn}.lef" "w"]; puts $_f "// LEF \[TEST MODE\]"; close $_f
            # Per-scenario SDC files (matches write_sdc loop in export_data_fc.tcl)
            set _scenarios {func_ss_0p76v_rcmax_150c func_ff_0p84v_rcmin_m40c func_tt_0p80v_rctyp_25c}
            foreach _scn $_scenarios {
                set _f [open "$_out/${_dn}_${_scn}.sdc" "w"]; puts $_f "// SDC for $_scn \[TEST MODE\]"; close $_f
            }
            # UPF + supplemental variants (matches save_upf commands)
            set _f [open "$_out/${_dn}.upf" "w"]; puts $_f "// UPF \[TEST MODE\]"; close $_f
            set _f [open "$_out/${_dn}.supplemental.upf" "w"]; puts $_f "// Supplemental UPF \[TEST MODE\]"; close $_f
            # SPEF (matches write_parasitics output — produces .spef and .spef.gz)
            set _f [open "$_out/${_dn}.spef" "w"]; puts $_f "// SPEF \[TEST MODE\]"; close $_f
            # Scripts and maps
            foreach _suf {_wscript _wscript_for_pt _routing_constraints _floorplan .saif.ptpx.map .saif.fc.map} {
                set _f [open "$_out/${_dn}${_suf}" "w"]; puts $_f "// \[TEST MODE\]"; close $_f
            }
            puts "INFO: \[TEST MODE\] Created [llength {.v .pt.v .fm.v .lvs.v .vc_lp.v .dc.v .gds .def .lef .sdc .upf .spef}] dummy output files in $_out/"
            puts "INFO: $stage_name run completed \[TEST MODE\]"
        } else {
            if {![file exists $cmd_file]} { puts "ERROR: Command file not found: $cmd_file"; exit 1 }
            set _work_dir "$run_dir/work/$::flow_type/$node_name/run"
            set _tool_name [expr {[info exists synth_pnr(tool,name)] ? $synth_pnr(tool,name) : "fc"}]
            set _log_file "$_work_dir/${node_name}.log"
            set _module_cmd ""
            set _tool_shell "fc_shell"
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
        # Generate output manifest for downstream flows (STA, LEC, CLP, PV, EMIR)
        set _resolve_lib "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/resolve_inputs.tcl"
        if {[file exists $_resolve_lib]} {
            source $_resolve_lib
            generate_output_manifest $::flow_type $node_name $run_dir
        }
        # Run log + file validation
        set _val_script "$::env(SCRIPTS_ROOT)/validation/$::env(VALIDATION_VERSION)/validate_run.tcl"
        if {[file exists $_val_script]} {
            if {[catch {exec tclsh $_val_script $::flow_type $stage_name $run_dir $::env(FLOW_DIR)} _val_out]} {
                puts "WARNING: Validation issues: $_val_out"
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
    default { puts "ERROR: Unknown subnode: $subnode_name"; exit 1 }
}
