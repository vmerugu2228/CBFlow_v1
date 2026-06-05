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
            # Queue type — from config, no hardcoded fallback
            if {![info exists lsf(flow_mapping,$flow_type,$stage_name)]} {
                if {![info exists lsf(default_queue_type)]} {
                    puts "ERROR: lsf(default_queue_type) not set in lsf_config.tcl and no flow_mapping for $flow_type/$stage_name"
                    exit 1
                }
                set qtype $lsf(default_queue_type)
            } else {
                set qtype $lsf(flow_mapping,$flow_type,$stage_name)
            }
            # Resource limits — must come from lsf_config queue_types
            if {![info exists lsf(queue_types,$qtype,memory)]} {
                puts "ERROR: lsf(queue_types,$qtype,memory) not set in lsf_config.tcl"; exit 1
            }
            set mem $lsf(queue_types,$qtype,memory)
            set cpu $lsf(queue_types,$qtype,cpu)
            set runtime $lsf(queue_types,$qtype,runtime_limit)
            # bsub command settings — from config
            if {![info exists lsf(bsub,command)]} {
                puts "ERROR: lsf(bsub,command) not set in lsf_config.tcl"; exit 1
            }
            set bsub $lsf(bsub,command)
            set queue [expr {[info exists lsf(bsub,queue)] ? $lsf(bsub,queue) : "normal"}]
            set project [expr {[info exists lsf(bsub,project)] ? $lsf(bsub,project) : ""}]
            set affinity [expr {[info exists lsf(bsub,affinity)] ? $lsf(bsub,affinity) : ""}]
            set bsub_cmd "$bsub"
            if {$project ne ""} { append bsub_cmd " -P $project" }
            append bsub_cmd " -J cbflow_${flow_type}_${stage_name}"
            if {$use_xterm} { append bsub_cmd " -Is" }
            append bsub_cmd " -q $queue -n $cpu -W $runtime"
            append bsub_cmd " -R \"rusage\[mem=$mem\]"
            if {$affinity ne ""} { append bsub_cmd " $affinity" }
            append bsub_cmd "\""
            append bsub_cmd " -o $work_dir/lsf_${node_name}_%J.log"
            append bsub_cmd " -e $work_dir/lsf_${node_name}_%J.err"
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
        } else {
            puts "WARNING: Command file not found: $cmd_file"
        }
        puts "INFO: Wrapper script: $wrapper"
        lassign [determine_launch_mode] _lsf _xterm
        if {$_lsf} {
            puts "INFO: \[TEST MODE\] Launch mode: LSF ([expr {$_xterm ? "interactive xterm" : "batch"}])"
        } elseif {$_xterm} {
            puts "INFO: \[TEST MODE\] Launch mode: xterm (local)"
        } else {
            puts "INFO: \[TEST MODE\] Launch mode: local execution"
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
            }
            "clp" {
                set _f [open "$_reports_dir/clp_check.rpt" w]
                puts $_f "CLP Check - $_ts\nStatus: PASS Violations: 0"; close $_f
            }
            "drc" {
                set _f [open "$_reports_dir/drc.rpt" w]
                puts $_f "DRC Report - $_ts\nViolations: 0"; close $_f
            }
            "lvs" {
                set _f [open "$_reports_dir/lvs.rpt" w]
                puts $_f "LVS Report - $_ts\nStatus: CLEAN"; close $_f
            }
            "fill" {
                set _f [open "$_reports_dir/metal_fill.rpt" w]
                puts $_f "Metal Fill - $_ts\nDensity: 45%"; close $_f
            }
            "erc" - "perc" - "xor" {
                set _f [open "$_reports_dir/${stage_name}.rpt" w]
                puts $_f "${stage_name} Report - $_ts\nStatus: PASS"; close $_f
            }
            "power_analysis" - "ir_drop" - "thermal_analysis" {
                set _f [open "$_reports_dir/${stage_name}.rpt" w]
                puts $_f "${stage_name} Report - $_ts\nStatus: PASS"; close $_f
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
