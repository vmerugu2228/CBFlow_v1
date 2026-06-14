#!/usr/bin/env tclsh
# CBflow STA per-scenario timing — Cadence Tempus
# Aligned with Tempus 20.1 STA RAK reference flow
# Each scenario runs independently: libs → design → MMMC → parasitics → SI → timing → reports

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "STA"
set STAGE_NAME "timing"
set NODE_NAME "${STAGE_NAME}1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# Source scenario context (globals set by subnode handler)
if {[info exists ::env(CBFLOW_SCENARIO)]} {
    set _ctx "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/$::env(CBFLOW_SCENARIO)_context.tcl"
    if {[file exists $_ctx]} { source $_ctx }
}

set ::DESIGN_NAME [expr {[info exists ::DESIGN_NAME] ? $::DESIGN_NAME : $flow(design_name)}]

# ═══════════════════════════════════════════════════════════════════════════════
# 1. CPU THREADING
# ═══════════════════════════════════════════════════════════════════════════════
flow_proc setup_threading {
    handle_info "Setting CPU threading..."
    set cpu_count [expr {$sta(tool,cpu_count) ne "" ? $sta(tool,cpu_count) : 8}]
    set_multi_cpu_usage -localCpu $cpu_count
    handle_info "  CPUs: $cpu_count"
}

# ═══════════════════════════════════════════════════════════════════════════════
# 2. READ LIBRARIES (per-corner timing libs from tech_config)
# ═══════════════════════════════════════════════════════════════════════════════
flow_proc read_libraries {
    handle_info "Reading libraries for corner $::LIB_SET..."
    global tech

    set _trk $tech(track)
    set _lib_key "${_trk},lib,${::LIB_SET},timing"

    if {[info exists tech($_lib_key)]} {
        foreach lib $tech($_lib_key) {
            if {[file exists $lib]} {
                read_lib $lib
                handle_info "  read_lib: [file tail $lib]"
            } else {
                handle_warning "  Library not found: $lib"
            }
        }
    } else {
        # Fallback: nominal libs
        if {[info exists tech(${_trk},lib_nom)]} {
            foreach lib $tech(${_trk},lib_nom) {
                if {[file exists $lib]} { read_lib $lib }
            }
        }
    }
    handle_info "Libraries loaded"
}

# ═══════════════════════════════════════════════════════════════════════════════
# 3. READ PHYSICAL (LEF)
# ═══════════════════════════════════════════════════════════════════════════════
flow_proc read_physical_data {
    handle_info "Reading physical data (LEF)..."
    global project tech

    # Technology LEF (metal_stack × track)
    set _ms $project(metal_stack)
    set _trk $project(track_variant)
    set _tech_lef $tech(${_ms},${_trk},lef_tech)
    if {$_tech_lef ne "" && [file exists $_tech_lef]} {
        read_lef $_tech_lef
        handle_info "  Tech LEF: [file tail $_tech_lef]"
    }

    # Cell LEFs (per track)
    set _trk $tech(track)
    if {[info exists tech(${_trk},lef)]} {
        foreach lef $tech(${_trk},lef) {
            if {[file exists $lef]} {
                read_lef $lef
                handle_info "  Cell LEF: [file tail $lef]"
            }
        }
    }
    handle_info "Physical data loaded"
}

# ═══════════════════════════════════════════════════════════════════════════════
# 4. READ DESIGN (netlist + link)
# ═══════════════════════════════════════════════════════════════════════════════
flow_proc read_design {
    handle_info "Reading design netlist..."
    global sta tech

    if {[info exists sta(input,netlist)] && $sta(input,netlist) ne "" && [file exists $sta(input,netlist)]} {
        read_verilog $sta(input,netlist)
        handle_info "  read_verilog: [file tail $sta(input,netlist)]"
    } else {
        handle_error "Netlist not found: $sta(input,netlist)"
        return
    }

    set_top_module $::DESIGN_NAME -ignore_undefined_cell
    set cellCnt [sizeof_collection [get_cells -hier *]]
    handle_info "  Design: $::DESIGN_NAME ($cellCnt instances)"
}

# ═══════════════════════════════════════════════════════════════════════════════
# 5. MMMC SETUP (per scenario — library set, RC corner, delay corner, constraints, view)
# ═══════════════════════════════════════════════════════════════════════════════
flow_proc setup_mmmc {
    handle_info "Setting up MMMC for scenario: $::scenario_name..."
    global tech sta

    set _trk $tech(track)
    set _lib_key "${_trk},lib,${::LIB_SET},timing"

    # Library set
    set _ls_name "${::LIB_SET}_ls"
    if {[info exists tech($_lib_key)]} {
        create_library_set -name $_ls_name -timing $tech($_lib_key)
        handle_info "  Library set: $_ls_name ([llength $tech($_lib_key)] libs)"
    }

    # RC corner
    set _rc_name "${::RC_CORNER}_rc"
    create_rc_corner -name $_rc_name -temperature $::TEMPERATURE
    handle_info "  RC corner: $_rc_name (temp=$::TEMPERATURE)"

    # Delay corner
    set _dc_name "${::scenario_name}_dc"
    create_delay_corner -name $_dc_name -library_set $_ls_name -rc_corner $_rc_name
    handle_info "  Delay corner: $_dc_name"

    # Constraint mode (per-mode SDC)
    set _cm_name "${::MODE}_cm"
    if {[info exists ::SDC_FILE] && $::SDC_FILE ne "" && [file exists $::SDC_FILE]} {
        create_constraint_mode -name $_cm_name -sdc_files $::SDC_FILE
        handle_info "  Constraint mode: $_cm_name (SDC: [file tail $::SDC_FILE])"
    } else {
        # Fallback: use sdc_func_file
        if {[info exists sta(input,sdc_func_file)] && $sta(input,sdc_func_file) ne "" && [file exists $sta(input,sdc_func_file)]} {
            create_constraint_mode -name $_cm_name -sdc_files $sta(input,sdc_func_file)
            handle_info "  Constraint mode: $_cm_name (SDC: [file tail $sta(input,sdc_func_file)])"
        } else {
            handle_error "No SDC file found for mode $::MODE"
            return
        }
    }

    # Analysis view
    create_analysis_view -name $::scenario_name -delay_corner $_dc_name -constraint_mode $_cm_name
    set_analysis_view -setup $::scenario_name -hold $::scenario_name
    handle_info "  Analysis view: $::scenario_name (setup+hold)"
}

# ═══════════════════════════════════════════════════════════════════════════════
# 6. READ PARASITICS (SPEF from extraction stage)
# ═══════════════════════════════════════════════════════════════════════════════
flow_proc read_parasitics {
    handle_info "Reading parasitics..."

    if {[info exists ::SPEF_FILE] && $::SPEF_FILE ne "" && [file exists $::SPEF_FILE]} {
        read_spef $::SPEF_FILE
        handle_info "  read_spef: [file tail $::SPEF_FILE]"
    } elseif {[info exists sta(input,spef)] && $sta(input,spef) ne ""} {
        foreach spef $sta(input,spef) {
            if {[file exists $spef]} {
                read_spef $spef
                handle_info "  read_spef: [file tail $spef]"
            }
        }
    } else {
        handle_warning "No SPEF file specified — timing without parasitics"
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# 7. SI / CROSSTALK SETTINGS (Tempus RAK: set_delay_cal_mode + set_si_mode)
# ═══════════════════════════════════════════════════════════════════════════════
flow_proc setup_si {
    handle_info "Configuring SI/crosstalk settings..."
    global sta

    if {[info exists sta(timing,si_aware)] && $sta(timing,si_aware) ne "" && $sta(timing,si_aware) eq "true"} {
        set_delay_cal_mode -siAware true
        handle_info "  SI-aware delay calculation: enabled"

        set_si_mode -enable_delay_report true
        handle_info "  SI delay reporting: enabled"

        if {[info exists sta(timing,si_glitch_report)] && $sta(timing,si_glitch_report) ne "" && $sta(timing,si_glitch_report) eq "true"} {
            set_si_mode -enable_glitch_report true
            handle_info "  SI glitch reporting: enabled"
        }

        if {[info exists sta(timing,si_glitch_propagation)] && $sta(timing,si_glitch_propagation) ne "" && $sta(timing,si_glitch_propagation) eq "true"} {
            set_si_mode -enable_glitch_propagation true
            handle_info "  SI glitch propagation: enabled"
        }
    } else {
        handle_info "  SI-aware: disabled"
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# 8. PBA / EPBA SETTINGS (Tempus RAK: set_global timing_pba_exhaustive_*)
# ═══════════════════════════════════════════════════════════════════════════════
flow_proc setup_pba {
    handle_info "Configuring PBA/EPBA settings..."
    global sta

    set pba_nworst [expr {$sta(timing,pba_nworst) ne "" ? $sta(timing,pba_nworst) : 2}]
    set pba_max [expr {$sta(timing,pba_max_paths) ne "" ? $sta(timing,pba_max_paths) : 1000}]

    set_global timing_pba_exhaustive_path_nworst_limit $pba_nworst
    set_global timing_path_based_exhaustive_max_paths_limit $pba_max

    handle_info "  PBA nworst: $pba_nworst, max paths: $pba_max"
}

# ═══════════════════════════════════════════════════════════════════════════════
# 9. UPDATE TIMING
# ═══════════════════════════════════════════════════════════════════════════════
flow_proc run_timing_update {
    handle_info "Running update_timing -full..."
    update_timing -full
    handle_info "  Timing updated"
}

# ═══════════════════════════════════════════════════════════════════════════════
# 10. TIMING REPORTS (GBA + EPBA + violations + clock + power)
# ═══════════════════════════════════════════════════════════════════════════════
flow_proc generate_reports {
    handle_info "Generating timing reports for $::scenario_name..."
    global sta

    set max_paths [expr {$sta(analysis,max_paths) ne "" ? $sta(analysis,max_paths) : 100}]
    set rpt_dir "$::REPORTS_DIR"
    set dn $::DESIGN_NAME
    set sc $::scenario_name
    file mkdir $rpt_dir

    # Setup timing (GBA)
    report_timing -late -max_paths $max_paths \
        -path_type full_clock -net \
        > $rpt_dir/${dn}_${sc}_setup_timing.rpt
    handle_info "  Setup timing (GBA): ${dn}_${sc}_setup_timing.rpt"

    # Hold timing (GBA)
    report_timing -early -max_paths $max_paths \
        -path_type full_clock -net \
        > $rpt_dir/${dn}_${sc}_hold_timing.rpt
    handle_info "  Hold timing (GBA): ${dn}_${sc}_hold_timing.rpt"

    # EPBA (Exhaustive Path-Based Analysis) — Tempus RAK highlight
    set epba_max [expr {$sta(timing,epba_max_paths) ne "" ? $sta(timing,epba_max_paths) : 10000}]
    set epba_slack [expr {$sta(timing,epba_max_slack) ne "" ? $sta(timing,epba_max_slack) : "0.200"}]
    report_timing -max_paths $epba_max \
        -retime path_slew_propagation -retime_mode exhaustive \
        -max_slack $epba_slack \
        > $rpt_dir/${dn}_${sc}_epba.rpt
    handle_info "  EPBA: ${dn}_${sc}_epba.rpt (max_slack=$epba_slack)"

    # Constraint violations
    report_constraint -all_violators > $rpt_dir/${dn}_${sc}_violations.rpt
    handle_info "  Violations: ${dn}_${sc}_violations.rpt"

    # Clock timing
    report_clock_timing -type summary > $rpt_dir/${dn}_${sc}_clock_timing.rpt
    handle_info "  Clock timing: ${dn}_${sc}_clock_timing.rpt"

    # QoR summary
    report_qor > $rpt_dir/${dn}_${sc}_qor.rpt
    handle_info "  QoR: ${dn}_${sc}_qor.rpt"

    # Power (if enabled)
    if {[info exists sta(analysis,report_power)] && $sta(analysis,report_power) ne "" && $sta(analysis,report_power) eq "true"} {
        report_power > $rpt_dir/${dn}_${sc}_power.rpt
        handle_info "  Power: ${dn}_${sc}_power.rpt"
    }

    # Extract WNS for summary
    catch {
        set ::setup_wns [get_property [get_timing_paths -max_paths 1 -path_type max] slack]
        set ::hold_wns [get_property [get_timing_paths -max_paths 1 -path_type min] slack]
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# 11. SCENARIO SUMMARY
# ═══════════════════════════════════════════════════════════════════════════════
flow_proc generate_summary {
    handle_info "Generating scenario summary..."

    set summary "$::REPORTS_DIR/timing_${::scenario_name}_summary.rpt"
    set fh [open $summary "w"]
    puts $fh "═══════════════════════════════════════════════════════════════"
    puts $fh "  CBflow Tempus Per-Scenario Timing Summary"
    puts $fh "  Generated: [expr {[catch {clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}} _ts] ? "epoch [clock seconds]" : $_ts}]"
    puts $fh "═══════════════════════════════════════════════════════════════"
    puts $fh ""
    puts $fh "  Scenario:    $::scenario_name"
    puts $fh "  Design:      $::DESIGN_NAME"
    puts $fh "  Corner:      $::CORNER"
    puts $fh "  Mode:        $::MODE"
    puts $fh "  Voltage:     $::VOLTAGE"
    puts $fh "  Temperature: $::TEMPERATURE"
    puts $fh "  RC Corner:   $::RC_CORNER"
    puts $fh "  Library Set: $::LIB_SET"
    puts $fh ""
    puts $fh [string repeat "─" 60]
    set s_st [expr {$::setup_wns >= 0 ? "MET" : "VIOLATED"}]
    set h_st [expr {$::hold_wns >= 0 ? "MET" : "VIOLATED"}]
    puts $fh [format "  %-20s  %12.4f  %12s" "Setup (max)" $::setup_wns $s_st]
    puts $fh [format "  %-20s  %12.4f  %12s" "Hold (min)" $::hold_wns $h_st]
    puts $fh [string repeat "─" 60]
    close $fh
    handle_info "  Summary: $summary"
}

# ═══════════════════════════════════════════════════════════════════════════════
# EXECUTE (Tempus RAK order)
# ═══════════════════════════════════════════════════════════════════════════════
set ::setup_wns 0.0
set ::hold_wns 0.0

flow_exec_all

handle_info "Tempus per-scenario completed: $::scenario_name"
exit
