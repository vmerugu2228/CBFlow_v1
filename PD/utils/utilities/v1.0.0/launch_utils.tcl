#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow — Launch Wrapper Utilities
# Generates tool launch scripts and handles LSF/xterm/local execution.
# Extracted from 102 duplicate copies across subnode handlers.
# ═══════════════════════════════════════════════════════════════════════════════

# ── Tool launch flags per vendor ─────────────────────────────────────────────
# Why: Cadence and Synopsys use different CLI flags. This is the single
# source of truth — handlers never hardcode tool flags.
proc _get_tool_flags {tool_name} {
    switch -glob $tool_name {
        "genus"       { return [list "-f" "-log"] }
        "innovus"     { return [list "-files" "-log"] }
        "tempus"      { return [list "-files" "-log"] }
        "voltus"      { return [list "-files" "-log"] }
        "conformal"   { return [list "-dofile" "-logfile"] }
        "conformal_lp" { return [list "-dofile" "-logfile"] }
        "lec"         { return [list "-dofile" "-logfile"] }
        "calibre"     { return [list "REDIRECT" "|& tee"] }
        "fc*"         { return [list "-f" "-output_log_file"] }
        "pt*"         { return [list "-f" "-output_log_file"] }
        "fm*"         { return [list "-f" "-output_log_file"] }
        default       { return [list "-f" "-log"] }
    }
}

# ── Generate launch wrapper script ──────────────────────────────────────────
# Creates a .csh wrapper that invokes the EDA tool with correct flags.
# Returns the wrapper path.
proc generate_launch_wrapper {work_dir stage_name cmd_file tool_name {log_file ""}} {
    global lsf

    if {$log_file eq ""} {
        set log_file "$work_dir/[file rootname [file tail $cmd_file]].log"
    }

    # Resolve tool shell and module load
    set tool_shell $tool_name
    set module_cmd ""
    set wrapper_shell "/bin/csh -f"
    catch { if {[info exists lsf(tool_shell,$tool_name)]} { set tool_shell $lsf(tool_shell,$tool_name) } }
    catch { if {[info exists lsf(module,$tool_name)]} { set module_cmd $lsf(module,$tool_name) } }
    catch { if {[info exists lsf(tool_wrapper_shell)]} { set wrapper_shell $lsf(tool_wrapper_shell) } }

    # Get correct flags for this tool
    set flags [_get_tool_flags $tool_name]
    set script_flag [lindex $flags 0]
    set log_flag [lindex $flags 1]

    # Build launch command
    if {$script_flag eq "REDIRECT"} {
        # Calibre: uses shell redirect for logging
        set launch_line "$tool_shell $cmd_file $log_flag $log_file"
    } else {
        set launch_line "$tool_shell $script_flag $cmd_file $log_flag $log_file"
    }

    # Write wrapper
    set wrapper_path "$work_dir/launch_${stage_name}.csh"
    set wf [open $wrapper_path "w"]
    puts $wf "#!$wrapper_shell"
    puts $wf "# CBflow tool launch wrapper — $stage_name"
    puts $wf "# Generated: [clock format [clock seconds]]"
    if {$module_cmd ne ""} { puts $wf "$module_cmd" }
    puts $wf "$launch_line"
    close $wf
    catch { file attributes $wrapper_path -permissions rwxr-xr-x }

    return $wrapper_path
}

# ── Determine launch mode ────────────────────────────────────────────────────
# Returns: list of {use_lsf use_xterm}
proc determine_launch_mode {} {
    set use_lsf false
    set use_xterm false

    if {[info exists ::env(CBFLOW_BSUB_CMD)] && $::env(CBFLOW_BSUB_CMD) ne ""} {
        set use_lsf true
    } elseif {[info exists ::flow(use_lsf)] && $::flow(use_lsf) eq "true"} {
        set use_lsf true
    } elseif {[info exists ::env(CBFLOW_USE_LSF)] && $::env(CBFLOW_USE_LSF) eq "1"} {
        set use_lsf true
    }

    if {[info exists ::flow(use_xterm)] && $::flow(use_xterm) eq "true"} {
        set use_xterm true
    } elseif {[info exists ::env(CBFLOW_USE_XTERM)] && $::env(CBFLOW_USE_XTERM) eq "1"} {
        set use_xterm true
    }

    return [list $use_lsf $use_xterm]
}

# ── Submit/execute job ────────────────────────────────────────────────────────
# Handles LSF batch, LSF interactive (xterm), xterm local, and local execution.
proc submit_job {wrapper flow_type stage_name node_name work_dir} {
    global lsf

    lassign [determine_launch_mode] use_lsf use_xterm

    # Resolve xterm settings only if needed
    set xterm_cmd "xterm"
    set xterm_geom "200x50"
    if {$use_xterm || $use_lsf} {
        if {[info exists lsf(xterm,command)]} {
            set xterm_cmd $lsf(xterm,command)
        }
        if {[info exists lsf(xterm,geometry)]} {
            set xterm_geom $lsf(xterm,geometry)
        }
    }

    if {$use_lsf} {
        # Build bsub command
        if {[info exists ::env(CBFLOW_BSUB_CMD)] && $::env(CBFLOW_BSUB_CMD) ne ""} {
            set bsub_cmd $::env(CBFLOW_BSUB_CMD)
        } else {
            # Resolve queue type with block-level override chain.
            # Priority (highest first):
            #   1. lsf(block,<design>,<stage>,queue)
            #   2. lsf(block,<design>,queue)
            #   3. lsf(flow_mapping,<FLOW>,<stage>)
            #   4. lsf(default_queue_type)
            set design ""
            if {[info exists ::flow(design_name)]} { set design $::flow(design_name) }
            set qtype ""
            if {$design ne "" && [info exists lsf(block,$design,$stage_name,queue)]} {
                set qtype $lsf(block,$design,$stage_name,queue)
            } elseif {$design ne "" && [info exists lsf(block,$design,queue)]} {
                set qtype $lsf(block,$design,queue)
            } elseif {[info exists lsf(flow_mapping,$flow_type,$stage_name)]} {
                set qtype $lsf(flow_mapping,$flow_type,$stage_name)
            } elseif {[info exists lsf(default_queue_type)]} {
                set qtype $lsf(default_queue_type)
            } else {
                puts "ERROR: no queue resolved for $flow_type/$stage_name (design=$design); set lsf(flow_mapping,...) or lsf(default_queue_type)"
                exit 1
            }
            # Resource limits — queue defaults from lsf_config, overridable per
            # block+stage.
            if {![info exists lsf(queue_types,$qtype,memory)]} {
                puts "ERROR: lsf(queue_types,$qtype,memory) not set in lsf_config.tcl"; exit 1
            }
            set mem $lsf(queue_types,$qtype,memory)
            set cpu $lsf(queue_types,$qtype,cpu)
            set runtime $lsf(queue_types,$qtype,runtime_limit)
            if {$design ne ""} {
                if {[info exists lsf(block,$design,$stage_name,memory)]} {
                    set mem $lsf(block,$design,$stage_name,memory)
                }
                if {[info exists lsf(block,$design,$stage_name,cpu)]} {
                    set cpu $lsf(block,$design,$stage_name,cpu)
                }
                if {[info exists lsf(block,$design,$stage_name,runtime)]} {
                    set runtime $lsf(block,$design,$stage_name,runtime)
                }
            }
            # bsub command settings — from config
            if {![info exists lsf(bsub,command)]} {
                puts "ERROR: lsf(bsub,command) not set in lsf_config.tcl"; exit 1
            }
            set bsub $lsf(bsub,command)
            set queue [expr {[info exists lsf(bsub,queue)] ? $lsf(bsub,queue) : "normal"}]
            set project [expr {[info exists lsf(bsub,project)] ? $lsf(bsub,project) : ""}]
            set affinity [expr {[info exists lsf(bsub,affinity)] ? $lsf(bsub,affinity) : ""}]
            # Build bsub cmd as a Tcl LIST, not a whitespace-joined string.
            # The prior form appended `-R \"rusage\[mem=$mem\]\"` into a
            # string and used `exec {*}$bsub_cmd` — {*} splits on
            # whitespace but does NOT interpret shell quoting, so bsub
            # received the literal `"rusage[mem=100]"` (with embedded
            # double-quotes as characters), rejecting the resource spec.
            # A proper Tcl list preserves whitespace within each element.
            set bsub_cmd [list $bsub]
            if {$project ne ""} { lappend bsub_cmd -P $project }
            lappend bsub_cmd -J cbflow_${flow_type}_${stage_name}
            if {$use_xterm} { lappend bsub_cmd -Is }
            lappend bsub_cmd -q $queue -n $cpu -W $runtime
            if {$design ne "" && [info exists lsf(block,$design,$stage_name,host)]} {
                lappend bsub_cmd -m $lsf(block,$design,$stage_name,host)
            }
            set extra_resource ""
            if {$design ne "" && [info exists lsf(block,$design,$stage_name,resource)]} {
                set extra_resource $lsf(block,$design,$stage_name,resource)
            }
            # Build the -R argument as ONE list element. Extra clauses
            # are appended with spaces INTO the same argument so bsub
            # sees a single -R value.
            set _R "rusage\[mem=$mem\]"
            if {$affinity ne ""}       { append _R " $affinity" }
            if {$extra_resource ne ""} { append _R " $extra_resource" }
            lappend bsub_cmd -R $_R
            lappend bsub_cmd -o "$work_dir/lsf_${node_name}_%J.log"
            lappend bsub_cmd -e "$work_dir/lsf_${node_name}_%J.err"
        }
        if {$use_xterm} {
            puts "INFO: Submitting via LSF (xterm): $bsub_cmd $xterm_cmd ..."
            if {[catch {exec {*}$bsub_cmd $xterm_cmd -geometry $xterm_geom -title "CBflow $flow_type $stage_name" -e $wrapper} result]} {
                puts "ERROR: LSF submit failed: $result"; exit 1
            }
        } else {
            puts "INFO: Submitting via LSF (batch): $bsub_cmd $wrapper"
            if {[catch {exec {*}$bsub_cmd $wrapper} result]} {
                puts "ERROR: LSF submit failed: $result"; exit 1
            }
        }
        puts $result
    } elseif {$use_xterm} {
        puts "INFO: Launching in xterm: $xterm_cmd -geometry $xterm_geom -e $wrapper"
        exec $xterm_cmd -geometry $xterm_geom -title "CBflow $flow_type $stage_name" -e $wrapper &
    } else {
        puts "INFO: Executing locally: $wrapper"
        if {[catch {exec $wrapper} result]} {
            puts "ERROR: $stage_name failed: $result"; exit 1
        }
        puts $result
    }
}

# ── Run subnode (full handler) ────────────────────────────────────────────────
# Complete run subnode handler: test mode display + real execution.
proc handler_run {run_dir flow_type node_name stage_name cmd_file test_mode {tool_name ""}} {
    set work_dir "$run_dir/work/$flow_type/$node_name/run"
    file mkdir $work_dir
    set log_file "$work_dir/${node_name}.log"

    # Resolve tool name — no hardcoded fallback
    if {$tool_name eq ""} {
        set fl [string tolower $flow_type]
        if {[info exists ::${fl}(tool,name)]} {
            set tool_name [set ::${fl}(tool,name)]
        } else {
            puts "ERROR: tool,name not set for flow $flow_type — set ${fl}(tool,name) in user_config or node_config"
            exit 1
        }
    }

    # Generate launch wrapper
    set wrapper [generate_launch_wrapper $work_dir $stage_name $cmd_file $tool_name $log_file]

    if {$test_mode} {
        puts "INFO: \[TEST MODE\] Running flow_procs with variable substitution"
        puts "INFO: Command file: [file tail $cmd_file]"

        # Execute the generated command file through tclsh
        # flow_exec in utils.tcl detects test_mode and intercepts EDA commands
        set _gen_file "$work_dir/${node_name}.${tool_name}.tcl"
        if {[file exists $_gen_file]} {
            puts "INFO: Executing: $_gen_file"
            if {[catch {exec tclsh $_gen_file 2>@1} _output]} {
                # Catch exits (test_mode intercepts exit but tclsh may still return non-zero)
                puts "$_output"
            } else {
                puts "$_output"
            }
        } elseif {[file exists $cmd_file]} {
            puts "INFO: Executing: $cmd_file"
            if {[catch {exec tclsh $cmd_file 2>@1} _output]} {
                puts "$_output"
            } else {
                puts "$_output"
            }
        } else {
            puts "WARNING: Command file not found: $cmd_file"
        }
        # Generate dummy output files for release testing
        set _design [expr {[info exists ::flow(design_name)] ? $::flow(design_name) : "design"}]
        set _outputs_dir "$run_dir/work/$flow_type/$node_name/outputs"
        set _reports_dir "$run_dir/work/$flow_type/$node_name/reports"
        file mkdir $_outputs_dir
        file mkdir $_reports_dir

        # Stage-specific dummy outputs
        set _ts "[clock format [clock seconds]]"
        switch -glob -- $stage_name {
            "init_design" {
                file mkdir "$_outputs_dir/init_design.enc.dat"
                set _f [open "$_outputs_dir/init_design.enc.dat/init_design.globals" w]
                puts $_f "# Test mode init_design checkpoint - $_ts"; close $_f
            }
            "synthesis" {
                set _f [open "$_outputs_dir/${_design}.v" w]
                puts $_f "// Synthesized netlist - $_ts\nmodule ${_design} (); endmodule"; close $_f
                set _f [open "$_outputs_dir/${_design}.sdc" w]
                puts $_f "# SDC constraints - $_ts"; close $_f
                set _f [open "$_reports_dir/qor.rpt" w]
                puts $_f "QoR Report - $_ts\nWNS: 0.000ns TNS: 0.000ns"; close $_f
            }
            "place" - "placement" {
                file mkdir "$_outputs_dir/place.enc.dat"
                set _f [open "$_outputs_dir/place.enc.dat/place.globals" w]
                puts $_f "# Test mode place checkpoint - $_ts"; close $_f
                set _f [open "$_reports_dir/qor.rpt" w]
                puts $_f "QoR Report - $_ts\nWNS: 0.000ns TNS: 0.000ns"; close $_f
            }
            "floorplan" {
                file mkdir "$_outputs_dir/floorplan.enc.dat"
                set _f [open "$_outputs_dir/floorplan.enc.dat/floorplan.globals" w]
                puts $_f "# Test mode floorplan checkpoint - $_ts"; close $_f
                set _f [open "$_outputs_dir/${_design}.def" w]
                puts $_f "VERSION 5.8 ;\nDESIGN ${_design} ;\nEND DESIGN"; close $_f
            }
            "powerplan" {
                file mkdir "$_outputs_dir/powerplan.enc.dat"
                set _f [open "$_outputs_dir/powerplan.enc.dat/powerplan.globals" w]
                puts $_f "# Test mode powerplan checkpoint - $_ts"; close $_f
            }
            "cts" - "cts_opt" {
                file mkdir "$_outputs_dir/${stage_name}.enc.dat"
                set _f [open "$_outputs_dir/${stage_name}.enc.dat/${stage_name}.globals" w]
                puts $_f "# Test mode $stage_name checkpoint - $_ts"; close $_f
                set _f [open "$_reports_dir/clock_timing.rpt" w]
                puts $_f "Clock Timing - $_ts\nSkew: 0.050ns Latency: 0.200ns"; close $_f
            }
            "route" {
                file mkdir "$_outputs_dir/route.enc.dat"
                set _f [open "$_outputs_dir/route.enc.dat/route.globals" w]
                puts $_f "# Test mode route checkpoint - $_ts"; close $_f
            }
            "pro" {
                file mkdir "$_outputs_dir/pro.enc.dat"
                set _f [open "$_outputs_dir/pro.enc.dat/pro.globals" w]
                puts $_f "# Test mode pro checkpoint - $_ts"; close $_f
            }
            "signoff" {
                file mkdir "$_outputs_dir/signoff.enc.dat"
                set _f [open "$_outputs_dir/signoff.enc.dat/signoff.globals" w]
                puts $_f "# Test mode signoff checkpoint - $_ts"; close $_f
                set _f [open "$_outputs_dir/${_design}.v" w]
                puts $_f "// Signoff netlist - $_ts\nmodule ${_design} (); endmodule"; close $_f
                set _f [open "$_outputs_dir/${_design}.def" w]
                puts $_f "VERSION 5.8 ;\nDESIGN ${_design} ;\nEND DESIGN"; close $_f
                set _f [open "$_outputs_dir/${_design}.gds" w]
                puts $_f "HEADER 600\nLIBNAME ${_design}\nENDLIB"; close $_f
                set _f [open "$_outputs_dir/${_design}.spef" w]
                puts $_f "*SPEF \"IEEE 1481-1998\"\n*DESIGN \"${_design}\""; close $_f
                set _f [open "$_reports_dir/timing_signoff.rpt" w]
                puts $_f "Signoff Timing - $_ts\nSetup WNS: 0.000ns Hold WNS: 0.000ns"; close $_f
            }
            "export_data" {
                # Copy key outputs from previous stage to export
                set _f [open "$_outputs_dir/${_design}.v" w]
                puts $_f "// Export netlist - $_ts\nmodule ${_design} (); endmodule"; close $_f
                set _f [open "$_outputs_dir/${_design}.def" w]
                puts $_f "VERSION 5.8 ;\nDESIGN ${_design} ;\nEND DESIGN"; close $_f
                set _f [open "$_outputs_dir/${_design}.sdc" w]
                puts $_f "# Export SDC - $_ts"; close $_f
                # Write output_manifest.tcl
                set _mf [open "$_outputs_dir/output_manifest.tcl" w]
                puts $_mf "array set manifest {"
                puts $_mf "    flow     \"$flow_type\""
                puts $_mf "    design   \"$_design\""
                puts $_mf "    netlist  \"$_outputs_dir/${_design}.v\""
                puts $_mf "    def      \"$_outputs_dir/${_design}.def\""
                puts $_mf "    sdc      \"$_outputs_dir/${_design}.sdc\""
                puts $_mf "}"
                close $_mf
            }
            "compare" {
                set _f [open "$_reports_dir/lec_compare.rpt" w]
                puts $_f "LEC Compare - $_ts\nStatus: PASS Equivalent: YES"; close $_f
                set _f [open "$_outputs_dir/PASSED" w]
                puts $_f "LEC PASSED - $_ts"; close $_f
            }
            "clp" {
                set _f [open "$_reports_dir/clp_check.rpt" w]
                puts $_f "CLP Check - $_ts\nStatus: PASS Violations: 0"; close $_f
                set _f [open "$_outputs_dir/clp_status.rpt" w]
                puts $_f "CLP PASS - $_ts"; close $_f
            }
            "drc" - "lvs" - "fill" - "erc" - "perc" - "perc_ldl" - "xor" - "merge_data" {
                set _f [open "$_reports_dir/${stage_name}.rpt" w]
                puts $_f "${stage_name} Report - $_ts\nStatus: PASS"; close $_f
                set _f [open "$_outputs_dir/${stage_name}_summary.txt" w]
                puts $_f "${stage_name} Summary - $_ts\nViolations: 0\nStatus: PASS"; close $_f
            }
            "nettran" {
                # Netlist translation (v2lvs Verilog→SPICE for LVS)
                set _f [open "$_outputs_dir/${_design}.cdl" w]
                puts $_f "* Test mode CDL netlist - $_ts\n.SUBCKT ${_design}\n.ENDS ${_design}"; close $_f
                set _f [open "$_reports_dir/nettran_summary.rpt" w]
                puts $_f "Netlist Translation - $_ts\nStatus: PASS"; close $_f
            }
            "merge_gds" - "fill_merge_gds" - "decomp_merge_gds" {
                # GDS-emitting layout-manipulation stages
                set _f [open "$_outputs_dir/${_design}_${stage_name}.gds" w]
                puts $_f "HEADER 600\nLIBNAME ${_design}\nENDLIB\n# Test mode $stage_name - $_ts"; close $_f
                set _f [open "$_reports_dir/${stage_name}_summary.rpt" w]
                puts $_f "${stage_name} Summary - $_ts\nStatus: PASS"; close $_f
            }
            "decomp" {
                # Mask decomposition (multi-patterning colorization)
                set _f [open "$_outputs_dir/${_design}_colored.gds" w]
                puts $_f "HEADER 600\nLIBNAME ${_design}\nENDLIB\n# Test mode decomp - $_ts"; close $_f
                set _f [open "$_reports_dir/decomp_summary.rpt" w]
                puts $_f "Mask Decomposition - $_ts\nStatus: PASS\nColors: 2"; close $_f
            }
            "merge_reports" {
                set _f [open "$_reports_dir/${stage_name}.rpt" w]
                puts $_f "${stage_name} Report - $_ts\nStatus: PASS"; close $_f
                set _f [open "$_outputs_dir/merge_reports_summary.txt" w]
                puts $_f "MMMC Cross-Corner Merge Reports Summary - $_ts"; close $_f
            }
            "release_data" {
                # Release package contains a manifest, release notes, and a
                # completion stamp. Mirrors what the real ::CBFlow::Release
                # procs would produce.
                set _f [open "$_outputs_dir/release_manifest.txt" w]
                puts $_f "# CBflow Release Manifest"
                puts $_f "# Flow:    $flow_type"
                puts $_f "# Design:  $_design"
                puts $_f "# Date:    $_ts"
                puts $_f "# Status:  COMPLETE (test_mode)"
                close $_f
                set _f [open "$_outputs_dir/release_notes.md" w]
                puts $_f "# Release Notes ($_design, $flow_type)\n\nTest-mode release."; close $_f
                set _f [open "$_outputs_dir/RELEASE_COMPLETE" w]
                puts $_f "Release completed: $_ts"; close $_f
                set _f [open "$_reports_dir/release_validation.rpt" w]
                puts $_f "Release Validation - $_ts\nStatus: PASS (test_mode)"; close $_f
            }
            "extraction" {
                set _f [open "$_outputs_dir/${_design}.spef" w]
                puts $_f "*SPEF \"IEEE 1481-1998\"\n*DESIGN \"${_design}\""; close $_f
                set _f [open "$_reports_dir/extraction.rpt" w]
                puts $_f "Extraction Report - $_ts\nStatus: PASS"; close $_f
            }
            "timing" {
                set _f [open "$_outputs_dir/${_design}_timing.rpt" w]
                puts $_f "Timing Report - $_ts\nSetup: 0.000ns Hold: 0.000ns"; close $_f
                set _f [open "$_reports_dir/timing_summary.rpt" w]
                puts $_f "Timing Summary - $_ts\nStatus: PASS"; close $_f
            }
            "power_spec" {
                set _f [open "$_outputs_dir/${_design}.upf" w]
                puts $_f "# UPF - $_ts\nset_design_top ${_design}"; close $_f
            }

            # ── DFT discipline (Tessent / TestMAX / VCS / Questa) ────────────
            "init_dft" - "init_scan" - "init_atpg" - "init_sim" {
                set _f [open "$_reports_dir/${stage_name}.rpt" w]
                puts $_f "${stage_name} init - $_ts\nStatus: OK"; close $_f
            }
            "insert_mbist" {
                set _f [open "$_outputs_dir/${_design}.mbist.v" w]
                puts $_f "// MBIST insertion - $_ts\nmodule ${_design}_mbist (); endmodule"; close $_f
                set _f [open "$_reports_dir/mbist_insertion.rpt" w]
                puts $_f "MBIST Report - $_ts\nMemories instrumented: 4\nStatus: PASS"; close $_f
            }
            "insert_occ" {
                set _f [open "$_outputs_dir/${_design}.occ.v" w]
                puts $_f "// OCC insertion - $_ts\nmodule ${_design}_occ (); endmodule"; close $_f
                set _f [open "$_reports_dir/occ_insertion.rpt" w]
                puts $_f "OCC Report - $_ts\nClocks instrumented: 4\nStatus: PASS"; close $_f
            }
            "insert_edt" {
                set _f [open "$_outputs_dir/${_design}.edt.v" w]
                puts $_f "// EDT/SSN insertion - $_ts\nmodule ${_design}_edt (); endmodule"; close $_f
                set _f [open "$_reports_dir/edt_insertion.rpt" w]
                puts $_f "EDT Report - $_ts\nCompression ratio: 100x\nStatus: PASS"; close $_f
            }
            "dft_verify" {
                set _f [open "$_reports_dir/dft_verify.rpt" w]
                puts $_f "DFT Verify - $_ts\nStatus: PASS\nViolations: 0"; close $_f
            }
            "dft_inserted_export" {
                set _f [open "$_outputs_dir/${_design}.dft.v" w]
                puts $_f "// DFT-inserted RTL - $_ts\nmodule ${_design} (); endmodule"; close $_f
            }
            "scan_stitch" {
                set _f [open "$_outputs_dir/${_design}.scan.v" w]
                puts $_f "// Scan-stitched netlist - $_ts\nmodule ${_design} (); endmodule"; close $_f
                set _f [open "$_outputs_dir/scan.scandef" w]
                puts $_f "VERSION 5.8 ;\nDESIGN ${_design} ;\nSCANCHAINS 16 ;\nEND DESIGN"; close $_f
                set _f [open "$_reports_dir/scan_chains.rpt" w]
                puts $_f "Scan Chains - $_ts\nChains: 16  AvgLength: 256\nStatus: PASS"; close $_f
            }
            "scan_check" {
                set _f [open "$_reports_dir/scan_drc.rpt" w]
                puts $_f "Scan DRC - $_ts\nStatus: PASS\nViolations: 0"; close $_f
            }
            "scan_export" {
                set _f [open "$_outputs_dir/${_design}.scan_export.v" w]
                puts $_f "// Scan export - $_ts\nmodule ${_design} (); endmodule"; close $_f
            }
            "pattern_gen" {
                set _f [open "$_outputs_dir/${_design}.patterns.stil" w]
                puts $_f "STIL 1.0 ;\nHeader { Title \"${_design} ATPG patterns - $_ts\"; }"
                close $_f
                set _f [open "$_reports_dir/pattern_gen.rpt" w]
                puts $_f "Pattern Gen - $_ts\nPatterns: 1024\nStatus: PASS"; close $_f
            }
            "fault_sim" {
                set _f [open "$_reports_dir/fault_coverage.rpt" w]
                puts $_f "Fault Simulation - $_ts\nFault coverage: 99.2%\nTest coverage: 99.5%"
                close $_f
            }
            "coverage_report" - "coverage" {
                set _f [open "$_reports_dir/${stage_name}.rpt" w]
                puts $_f "${stage_name} - $_ts\nCoverage: 99.5%\nStatus: PASS"; close $_f
                set _f [open "$_outputs_dir/${stage_name}_summary.txt" w]
                puts $_f "Coverage: 99.5%"; close $_f
            }
            "export_patterns" {
                set _f [open "$_outputs_dir/${_design}.patterns.stil" w]
                puts $_f "STIL 1.0 ;\nHeader { Title \"${_design} ATPG patterns - $_ts\"; }"
                close $_f
            }
            "compile" {
                set _f [open "$_reports_dir/compile.log" w]
                puts $_f "Compile - $_ts\nStatus: PASS"; close $_f
            }
            "run_sim" {
                set _f [open "$_outputs_dir/sim.log" w]
                puts $_f "Simulation - $_ts\nStatus: PASS\nErrors: 0"; close $_f
                set _f [open "$_outputs_dir/coverage.ucdb" w]
                puts $_f "# Coverage DB stub - $_ts"; close $_f
            }
            "testbench" - "patterns" {
                set _f [open "$_outputs_dir/${stage_name}.sv" w]
                puts $_f "// ${stage_name} - $_ts"; close $_f
            }
            "power_analysis" - "ir_drop" - "thermal_analysis" - "em_analysis" {
                set _f [open "$_reports_dir/${stage_name}.rpt" w]
                puts $_f "${stage_name} - $_ts\nStatus: PASS\nViolations: 0"; close $_f
                set _f [open "$_outputs_dir/${stage_name}_summary.txt" w]
                puts $_f "${stage_name} Summary - $_ts\nMax IR drop: 12.3 mV\nStatus: PASS"; close $_f
            }
            "merge_timing" - "power_opt" - "post_merge" {
                set _f [open "$_reports_dir/${stage_name}.rpt" w]
                puts $_f "${stage_name} - $_ts\nStatus: PASS"; close $_f
                set _f [open "$_outputs_dir/${stage_name}_summary.txt" w]
                puts $_f "${stage_name} Summary - $_ts\nLeakage reduction: 12%\nStatus: PASS"; close $_f
            }
            "eco" - "export_db" {
                set _f [open "$_reports_dir/${stage_name}.rpt" w]
                puts $_f "${stage_name} - $_ts\nStatus: PASS\nFixes applied: 7"; close $_f
                set _f [open "$_outputs_dir/${stage_name}_summary.txt" w]
                puts $_f "${stage_name} Summary - $_ts\nNet changes: 23\nStatus: PASS"; close $_f
            }
            "init_compile" - "shaping" - "placement" - "create_power" - "place_pins" - "top_compile" - "timing_budget" - "commit_blocks" - "create_floorplan" - "fc_floorplan" - "fc_powerplan" - "fc_post_floorplan" {
                set _f [open "$_reports_dir/${stage_name}.rpt" w]
                puts $_f "${stage_name} - $_ts\nStatus: PASS"; close $_f
                set _f [open "$_outputs_dir/${stage_name}.enc" w]
                puts $_f "FCFP ${stage_name} checkpoint stub - $_ts"; close $_f
            }
        }

        set _out_count [llength [glob -nocomplain "$_outputs_dir/*"]]
        set _rpt_count [llength [glob -nocomplain "$_reports_dir/*"]]
        if {$_out_count > 0 || $_rpt_count > 0} {
            puts "INFO: \[TEST MODE\] Created dummy files: $_out_count outputs, $_rpt_count reports"
        }

        puts "INFO: $stage_name run completed \[TEST MODE\]"
    } else {
        if {![file exists $cmd_file]} {
            puts "ERROR: Command file not found: $cmd_file"
            exit 1
        }
        puts "INFO: Wrapper: $wrapper"
        submit_job $wrapper $flow_type $stage_name $node_name $work_dir
        puts "INFO: $stage_name run completed"
    }
}
