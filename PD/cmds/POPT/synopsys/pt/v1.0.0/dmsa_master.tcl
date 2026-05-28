#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# DMSA Master — Multi-Scenario VT Swap Controller for PrimeTime
# Sourced by power_opt_pt.tcl when popt(dmsa,enabled) = true
#
# This script sets up DMSA scenarios and provides procs for cross-scenario
# optimization. The actual optimization loop is in power_opt_pt.tcl — this
# just provides the DMSA infrastructure.
#
# When DMSA is not available (single-scenario mode), all procs gracefully
# fall back to single-scenario PT commands.
# ═══════════════════════════════════════════════════════════════════════════════

# ── Detect DMSA availability ───────────────────────────────────────────────
# PT DMSA requires pt_shell -multi_scenario. If we are running in single
# session mode, set a flag so every proc below can degrade gracefully.
set ::dmsa_available false
if {[info commands create_scenario] ne ""} {
    set ::dmsa_available true
}

# ── Setup DMSA scenarios from MMMC config ──────────────────────────────────
# Reads scenarios from popt(dmsa,scenarios) or falls back to analysis_views.
# For each scenario:
#   - create_scenario with setup/hold classification
#   - generate a per-scenario worker script via dmsa_generate_worker
#
# In single-scenario mode: logs a warning and returns without action.
proc dmsa_setup_scenarios {} {
    global popt analysis_views mmmc_scenario_sets

    set run_dir $::env(CBFLOW_RUN_DIR)
    set worker_dir "$run_dir/work/POPT/dmsa_workers"
    file mkdir $worker_dir

    # Resolve scenario list: explicit config > scenario set > all analysis_views
    if {[info exists popt(dmsa,scenarios)]} {
        set scenarios $popt(dmsa,scenarios)
    } elseif {[info exists popt(dmsa,scenario_set)] && [info exists mmmc_scenario_sets($popt(dmsa,scenario_set))]} {
        set scenarios $mmmc_scenario_sets($popt(dmsa,scenario_set))
    } elseif {[array exists analysis_views]} {
        set scenarios [lsort [array names analysis_views]]
    } else {
        handle_warning "DMSA: No scenarios resolved — running single-scenario"
        return
    }

    if {!$::dmsa_available} {
        handle_warning "DMSA: pt_shell DMSA commands not available — single-scenario fallback"
        handle_info "DMSA: Resolved [llength $scenarios] scenario(s) for reference only"
        return
    }

    handle_info "DMSA: Setting up [llength $scenarios] scenario(s)..."

    foreach scenario_name $scenarios {
        # Retrieve view metadata from analysis_views
        if {![info exists analysis_views($scenario_name)]} {
            handle_warning "DMSA: Scenario '$scenario_name' not found in analysis_views — skipping"
            continue
        }
        array set view $analysis_views($scenario_name)

        # Determine setup/hold classification from analysis_type
        set is_setup false
        set is_hold  false
        if {[info exists view(analysis_type)]} {
            switch $view(analysis_type) {
                "setup"      { set is_setup true }
                "hold"       { set is_hold true }
                "setup_hold" { set is_setup true; set is_hold true }
            }
        } else {
            # Default: classify from corner name
            if {[string match "*ss*" $scenario_name]} { set is_setup true }
            if {[string match "*ff*" $scenario_name]} { set is_hold true }
            if {!$is_setup && !$is_hold} { set is_setup true; set is_hold true }
        }

        # PT DMSA: create_scenario
        #   create_scenario -name <name>
        #   set_scenario_options -name <name> -setup <bool> -hold <bool>
        #     -script "<worker_script>"
        create_scenario -name $scenario_name
        set worker_script "$worker_dir/${scenario_name}_worker.tcl"
        set_scenario_options -name $scenario_name \
            -setup $is_setup -hold $is_hold \
            -script $worker_script

        # Generate the per-scenario worker script
        dmsa_generate_worker $scenario_name $worker_dir

        handle_info "DMSA:   $scenario_name (setup=$is_setup hold=$is_hold)"
        array unset view
    }

    handle_info "DMSA: Scenario setup completed"
}

# ── Generate worker script for a scenario ──────────────────────────────────
# Writes a TCL script that will be executed by the PT DMSA worker process.
# The worker reads corner-specific libs, SPEF, SDC and runs update_timing.
# Uses analysis_views($scenario_name) metadata to resolve corner/mode/voltage/temp.
#
# In single-scenario mode: generates the file for reference but it will not
# be executed by DMSA.
proc dmsa_generate_worker {scenario_name worker_dir} {
    global popt analysis_views

    set run_dir $::env(CBFLOW_RUN_DIR)

    # Extract view metadata
    if {![info exists analysis_views($scenario_name)]} {
        handle_error "DMSA: Cannot generate worker — no view data for '$scenario_name'"
        return
    }
    array set view $analysis_views($scenario_name)

    # Resolve per-scenario files from view metadata
    set corner      [expr {[info exists view(corner)]          ? $view(corner)          : ""}]
    set mode        [expr {[info exists view(mode)]            ? $view(mode)            : ""}]
    set voltage     [expr {[info exists view(voltage)]         ? $view(voltage)         : ""}]
    set temperature [expr {[info exists view(temperature)]     ? $view(temperature)     : ""}]
    set rc_corner   [expr {[info exists view(rc_corner)]       ? $view(rc_corner)       : ""}]
    set lib_set_ref [expr {[info exists view(lib_set_ref)]     ? $view(lib_set_ref)     : ""}]
    set sdc_file    [expr {[info exists view(constraint_file)] ? $view(constraint_file) : ""}]

    # Resolve SPEF path from popt config or convention
    set spef_file ""
    if {[info exists popt(input,spef,$scenario_name)]} {
        set spef_file $popt(input,spef,$scenario_name)
    } elseif {[info exists popt(input,spef,$rc_corner)]} {
        set spef_file $popt(input,spef,$rc_corner)
    } elseif {[info exists popt(input,spef)]} {
        set spef_file $popt(input,spef)
    }

    # Resolve SDC path: per-mode from popt config or operating_modes
    if {[info exists popt(input,sdc,${mode})]} {
        set sdc_file $popt(input,sdc,${mode})
    } elseif {[info exists popt(input,sdc_func_file)] && $sdc_file eq ""} {
        set sdc_file $popt(input,sdc_func_file)
    }

    # Write the worker script from the template
    set template_file "$::env(FLOW_DIR)/cmds/POPT/synopsys/pt/v1.0.0/dmsa_worker.tcl"
    set out_file "$worker_dir/${scenario_name}_worker.tcl"

    if {[file exists $template_file]} {
        # Read template and substitute placeholders
        set fh [open $template_file r]
        set template_content [read $fh]
        close $fh

        set content $template_content
        set content [string map [list \
            "<SCENARIO_NAME>" $scenario_name \
            "<CORNER>"        $corner \
            "<MODE>"          $mode \
            "<VOLTAGE>"       $voltage \
            "<TEMPERATURE>"   $temperature \
            "<RC_CORNER>"     $rc_corner \
            "<LIB_SET>"       $lib_set_ref \
            "<SDC_FILE>"      $sdc_file \
            "<SPEF_FILE>"     $spef_file \
            "<RUN_DIR>"       $run_dir \
        ] $content]

        set wfh [open $out_file w]
        puts $wfh $content
        close $wfh
    } else {
        handle_warning "DMSA: Worker template not found at $template_file — generating inline"

        set wfh [open $out_file w]
        puts $wfh "#!/usr/bin/env tclsh"
        puts $wfh "# DMSA Worker — generated by dmsa_master.tcl"
        puts $wfh "# Scenario: $scenario_name"
        puts $wfh "# Generated: [clock format [clock seconds]]"
        puts $wfh ""
        puts $wfh "set ::SCENARIO_NAME  \"$scenario_name\""
        puts $wfh "set ::CORNER         \"$corner\""
        puts $wfh "set ::MODE           \"$mode\""
        puts $wfh "set ::VOLTAGE        \"$voltage\""
        puts $wfh "set ::TEMPERATURE    \"$temperature\""
        puts $wfh "set ::RC_CORNER      \"$rc_corner\""
        puts $wfh "set ::LIB_SET        \"$lib_set_ref\""
        puts $wfh "set ::SDC_FILE       \"$sdc_file\""
        puts $wfh "set ::SPEF_FILE      \"$spef_file\""
        puts $wfh ""
        puts $wfh "if {\[file exists \$::SPEF_FILE\]} { read_parasitics -format spef \$::SPEF_FILE }"
        puts $wfh "if {\[file exists \$::SDC_FILE\]}  { read_sdc \$::SDC_FILE }"
        puts $wfh "update_timing -full"
        close $wfh
    }

    handle_info "DMSA:   Worker generated: [file tail $out_file]"
    array unset view
}

# ── Cross-scenario timing update ──────────────────────────────────────────
# DMSA mode:   update_timing -full -scenarios all
# Single mode: update_timing -full
# Returns: worst WNS across all scenarios (or single scenario)
proc dmsa_update_timing {} {
    if {$::dmsa_available} {
        # PT DMSA: update_timing across all active scenarios
        #   update_timing -full -scenarios all
        update_timing -full -scenarios all
        handle_info "DMSA: Timing updated across all scenarios"
    } else {
        # Single-scenario fallback
        update_timing -full
        handle_info "DMSA: Timing updated (single-scenario)"
    }

    # Return worst slack
    return [dmsa_get_worst_slack max]
}

# ── Cross-scenario VT swap ────────────────────────────────────────────────
# Applies size_cell across all DMSA scenarios simultaneously.
# DMSA mode:   size_cell applies to shared netlist, all scenarios see the change
# Single mode: size_cell on current session
# Returns: timing impact (worst slack after swap)
proc dmsa_swap_cells {cell_list target_ref} {
    # PT: size_cell $cell_list $target_ref
    # In DMSA, the netlist is shared — size_cell affects all scenarios
    if {[catch {size_cell $cell_list $target_ref} result]} {
        handle_warning "DMSA: size_cell failed for $target_ref — $result"
        return -1.0
    }

    # Update timing across all scenarios after the swap
    if {$::dmsa_available} {
        update_timing -full -scenarios all
    } else {
        update_timing -full
    }

    # Return worst slack post-swap
    return [dmsa_get_worst_slack max]
}

# ── Cross-scenario worst slack ─────────────────────────────────────────────
# DMSA mode:   queries report_timing across all scenarios, returns worst value
# Single mode: queries report_timing on current session
# delay_type: "max" (setup) or "min" (hold)
proc dmsa_get_worst_slack {delay_type} {
    set worst_slack 999999.0

    if {$::dmsa_available} {
        # PT DMSA: get_timing_paths across all scenarios
        #   get_timing_paths -delay_type $delay_type -max_paths 1 -scenarios all
        if {[catch {
            set paths [get_timing_paths -delay_type $delay_type -max_paths 1 -scenarios all]
            if {[sizeof_collection $paths] > 0} {
                set worst_slack [get_attribute $paths slack]
            }
        } err]} {
            handle_warning "DMSA: get_timing_paths failed — $err"
            set worst_slack 0.0
        }
    } else {
        # Single-scenario fallback
        #   get_timing_paths -delay_type $delay_type -max_paths 1
        if {[catch {
            set paths [get_timing_paths -delay_type $delay_type -max_paths 1]
            if {[sizeof_collection $paths] > 0} {
                set worst_slack [get_attribute $paths slack]
            }
        } err]} {
            handle_warning "DMSA: get_timing_paths failed (single) — $err"
            set worst_slack 0.0
        }
    }

    return $worst_slack
}

# ── Cross-scenario critical paths ─────────────────────────────────────────
# Returns a list of critical path info dicts across all scenarios.
# Each element: {endpoint <ep> slack <slack> scenario <scenario> cells <cell_list>}
# DMSA mode:   queries all scenarios with slack filter
# Single mode: queries current session
proc dmsa_get_critical_paths {max_paths slack_threshold} {
    set result {}

    if {$::dmsa_available} {
        # PT DMSA: get_timing_paths across all scenarios with slack filter
        #   get_timing_paths -delay_type max \
        #     -slack_lesser_than $slack_threshold \
        #     -max_paths $max_paths \
        #     -scenarios all
        if {[catch {
            set paths [get_timing_paths -delay_type max \
                -slack_lesser_than $slack_threshold \
                -max_paths $max_paths \
                -scenarios all]
            foreach_in_collection path $paths {
                set ep    [get_attribute $path endpoint]
                set slack [get_attribute $path slack]
                set scen  [get_attribute $path scenario]
                set cells [get_attribute [get_attribute $path points] object]
                lappend result [list endpoint $ep slack $slack scenario $scen cells $cells]
            }
        } err]} {
            handle_warning "DMSA: get_critical_paths failed — $err"
        }
    } else {
        # Single-scenario fallback — no scenario attribute
        #   get_timing_paths -delay_type max \
        #     -slack_lesser_than $slack_threshold \
        #     -max_paths $max_paths
        if {[catch {
            set paths [get_timing_paths -delay_type max \
                -slack_lesser_than $slack_threshold \
                -max_paths $max_paths]
            foreach_in_collection path $paths {
                set ep    [get_attribute $path endpoint]
                set slack [get_attribute $path slack]
                set cells [get_attribute [get_attribute $path points] object]
                lappend result [list endpoint $ep slack $slack scenario "default" cells $cells]
            }
        } err]} {
            handle_warning "DMSA: get_critical_paths failed (single) — $err"
        }
    }

    return $result
}

# ── Report timing across scenarios ─────────────────────────────────────────
# Generates per-scenario WNS/TNS reports and a cross-scenario worst summary.
proc dmsa_report_timing {rpt_dir prefix} {
    file mkdir $rpt_dir
    global popt

    set max_paths [expr {[info exists popt(analysis,max_paths)] ? $popt(analysis,max_paths) : 100}]

    if {$::dmsa_available} {
        # PT DMSA: report_timing per scenario and across all scenarios
        #   report_timing -delay_type max -scenarios all -max_paths $max_paths
        report_timing -delay_type max -max_paths $max_paths -scenarios all \
            -significant_digits 4 \
            > "$rpt_dir/${prefix}_setup_all_scenarios.rpt"

        report_timing -delay_type min -max_paths $max_paths -scenarios all \
            -significant_digits 4 \
            > "$rpt_dir/${prefix}_hold_all_scenarios.rpt"

        handle_info "DMSA: Cross-scenario timing reports written"

        # Per-scenario WNS/TNS summary
        set summary_file "$rpt_dir/${prefix}_dmsa_wns_tns_summary.rpt"
        set sfh [open $summary_file w]
        puts $sfh "═══════════════════════════════════════════════════════════════"
        puts $sfh "  DMSA Per-Scenario WNS/TNS Summary"
        puts $sfh "  Generated: [clock format [clock seconds]]"
        puts $sfh "═══════════════════════════════════════════════════════════════"
        puts $sfh ""
        puts $sfh [format "  %-40s  %10s  %10s" "Scenario" "WNS (ns)" "Status"]
        puts $sfh [string repeat "─" 65]

        set global_worst 999999.0
        foreach scen [get_scenarios -active] {
            if {[catch {
                set paths [get_timing_paths -delay_type max -max_paths 1 -scenarios $scen]
                set wns [get_attribute $paths slack]
            }]} {
                set wns "N/A"
            }
            set status [expr {$wns ne "N/A" && $wns >= 0 ? "MET" : "VIOLATED"}]
            puts $sfh [format "  %-40s  %10s  %10s" $scen $wns $status]
            if {$wns ne "N/A" && $wns < $global_worst} { set global_worst $wns }
        }

        puts $sfh [string repeat "─" 65]
        set gstatus [expr {$global_worst >= 0 ? "MET" : "VIOLATED"}]
        puts $sfh [format "  %-40s  %10.4f  %10s" "WORST ACROSS ALL" $global_worst $gstatus]
        puts $sfh "═══════════════════════════════════════════════════════════════"
        close $sfh
        handle_info "DMSA: WNS/TNS summary: $summary_file"

    } else {
        # Single-scenario fallback
        report_timing -delay_type max -max_paths $max_paths \
            -significant_digits 4 \
            > "$rpt_dir/${prefix}_setup_timing.rpt"

        report_timing -delay_type min -max_paths $max_paths \
            -significant_digits 4 \
            > "$rpt_dir/${prefix}_hold_timing.rpt"

        handle_info "DMSA: Timing reports written (single-scenario)"
    }
}

# ── Report power across scenarios ──────────────────────────────────────────
# Generates per-scenario power reports and a total power summary.
proc dmsa_report_power {rpt_dir prefix} {
    file mkdir $rpt_dir

    if {$::dmsa_available} {
        # PT DMSA: report_power per scenario
        #   report_power -scenarios all
        report_power -scenarios all > "$rpt_dir/${prefix}_power_all_scenarios.rpt"
        report_power -scenarios all -hierarchy -levels 3 \
            > "$rpt_dir/${prefix}_power_hier_all_scenarios.rpt"

        handle_info "DMSA: Cross-scenario power reports written"

        # Per-scenario power summary
        set summary_file "$rpt_dir/${prefix}_dmsa_power_summary.rpt"
        set sfh [open $summary_file w]
        puts $sfh "═══════════════════════════════════════════════════════════════"
        puts $sfh "  DMSA Per-Scenario Power Summary"
        puts $sfh "  Generated: [clock format [clock seconds]]"
        puts $sfh "═══════════════════════════════════════════════════════════════"
        puts $sfh ""

        foreach scen [get_scenarios -active] {
            puts $sfh "── Scenario: $scen ──"
            if {[catch {
                report_power -scenarios $scen > "$rpt_dir/${prefix}_power_${scen}.rpt"
                puts $sfh "  Report: ${prefix}_power_${scen}.rpt"
            } err]} {
                puts $sfh "  ERROR: $err"
            }
            puts $sfh ""
        }

        puts $sfh "═══════════════════════════════════════════════════════════════"
        close $sfh
        handle_info "DMSA: Power summary: $summary_file"

    } else {
        # Single-scenario fallback
        report_power > "$rpt_dir/${prefix}_power.rpt"
        report_power -hierarchy -levels 3 > "$rpt_dir/${prefix}_power_hier.rpt"
        report_power -leakage > "$rpt_dir/${prefix}_power_leakage.rpt"

        handle_info "DMSA: Power reports written (single-scenario)"
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
puts "INFO: DMSA master loaded (dmsa_available=$::dmsa_available)"
