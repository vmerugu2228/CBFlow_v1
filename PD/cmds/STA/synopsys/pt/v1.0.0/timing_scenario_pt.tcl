#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow STA Per-Corner Timing Analysis — Synopsys PrimeTime
# Aligned with PT-RM W-2024.09 (dmsa_analysis.tcl)
#
# Runs setup + hold + noise + power analysis for a single PVT corner
# Usage: pt_shell -f timing_scenario_pt.tcl <scenario_name>
# ═══════════════════════════════════════════════════════════════════════════════

# ── Environment ──────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source -e "$run_dir/.run.cbflow.tcl"
set FLOW_DIR $::env(FLOW_DIR)
source -e "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

# Source configs
if {[file exists "$run_dir/work/STA/timing1/run/config.tcl"]} {
    source -e "$run_dir/work/STA/timing1/run/config.tcl"
}

# Source tech_config
if {[info exists ::env(TECH_NAME)] && $::env(TECH_NAME) ne "" && [info exists ::env(TECH_VERSION)]} {
    set _tc "$::env(CONFIG_ROOT)/tech/$::env(TECH_NAME)/$::env(TECH_VERSION)/tech_config.tcl"
    if {[file exists $_tc]} { source -e $_tc }
}

# Source user_config for overrides
if {[file exists "$run_dir/setup/user_config.tcl"]} { source -e "$run_dir/setup/user_config.tcl" }

global sta project tech flow library_sets

# Source MMMC config
source -e "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/mmmc_config.tcl"

# ── Scenario ─────────────────────────────────────────────────────────────────
if {$argc < 1} { puts stderr "ERROR: Usage: pt_shell -f timing_scenario_pt.tcl <scenario>"; exit 1 }
set scenario_name [lindex $argv 0]

global analysis_views
if {![info exists analysis_views($scenario_name)]} {
    puts stderr "ERROR: Scenario '$scenario_name' not in analysis_views"
    exit 1
}
array set VIEW $analysis_views($scenario_name)

set DESIGN_NAME [expr {[info exists project(top_module)] ? $project(top_module) : $::env(CBFLOW_DESIGN_NAME)}]
set CORNER      $VIEW(corner)
set MODE        $VIEW(mode)
set VOLTAGE     $VIEW(voltage)
set TEMPERATURE $VIEW(temperature)
set RC_CORNER   $VIEW(rc_corner)
set LIB_SET     $VIEW(lib_set_ref)
set SDC_FILE    $VIEW(constraint_file)

set REPORTS_DIR "$run_dir/reports/sta/$scenario_name"
set RESULTS_DIR "$run_dir/results/sta/$scenario_name"
file mkdir $REPORTS_DIR $RESULTS_DIR

handle_info "═══════════════════════════════════════════════════════"
handle_info "  PT-RM Per-Corner: $scenario_name"
handle_info "  Design=$DESIGN_NAME  Corner=$CORNER  V=${VOLTAGE}V  T=${TEMPERATURE}C"
handle_info "═══════════════════════════════════════════════════════"

# ═══════════════════════════════════════════════════════════════════════════════
# PT-RM: APP VARIABLES (from pt_setup.tcl)
# ═══════════════════════════════════════════════════════════════════════════════
flow_proc pt_app_setup {
    handle_info "PT-RM: Setting app variables..."

    # PT-RM recommended variables
    set_app_var timing_report_unconstrained_paths true
    set_app_var timing_save_pin_arrival_and_slack true
    set_app_var timing_enable_preset_clear_arcs true
    set_app_var report_default_significant_digits 4
    set_app_var timing_clock_reconvergence_pessimism removal

    # PBA exhaustive endpoint path limit (from dmsa_analysis.tcl)
    set pba_exhaustive_endpoint_path_limit infinity

    # SI / Crosstalk
    if {[info exists sta(analysis,si_aware)] && $sta(analysis,si_aware) eq "true"} {
        set_app_var si_enable_analysis true
        handle_info "  SI analysis: enabled"
    }

    # OCV mode (PT-RM: AOCV/POCV)
    if {[info exists sta(analysis,ocv_mode)]} {
        switch $sta(analysis,ocv_mode) {
            "aocv" {
                set_app_var timing_aocvm_enable_analysis true
                handle_info "  OCV: AOCV enabled"
            }
            "pocv" {
                set_app_var timing_pocvm_enable_analysis true
                handle_info "  OCV: POCV enabled"
            }
            default {
                set_app_var timing_enable_multiple_clocks_per_reg true
                handle_info "  OCV: standard"
            }
        }
    }

    # OCV derate file
    if {[info exists tech(ocv,derate_file)] && $tech(ocv,derate_file) ne "" && [file exists $tech(ocv,derate_file)]} {
        source -e $tech(ocv,derate_file)
        handle_info "  OCV derate: [file tail $tech(ocv,derate_file)]"
    }

    # Power analysis (PT-PX)
    if {[info exists sta(analysis,report_power)] && $sta(analysis,report_power) eq "true"} {
        set power_enable_analysis true
        set power_clock_network_include_register_clock_pin_power false
        handle_info "  Power analysis: enabled (PT-PX)"
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# PT-RM: LIBRARY SETUP (from common_setup.tcl)
# ═══════════════════════════════════════════════════════════════════════════════
flow_proc read_libraries {
    handle_info "PT-RM: Reading libraries for $::LIB_SET..."

    # Target library files from library_sets
    if {[info exists library_sets(${::LIB_SET},timing)]} {
        set TARGET_LIBRARY_FILES $library_sets(${::LIB_SET},timing)
        foreach lib $TARGET_LIBRARY_FILES {
            if {[file exists $lib]} {
                read_db $lib
                handle_info "  read_db: [file tail $lib]"
            } else {
                handle_warning "  Library not found: $lib"
            }
        }
    } else {
        handle_error "Library set '$::LIB_SET' not found"
    }

    # Additional link libraries (memory, IO, macros)
    if {[info exists tech(db,memory)] && [file exists $tech(db,memory)]} {
        read_db $tech(db,memory)
        handle_info "  Memory lib: [file tail $tech(db,memory)]"
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# PT-RM: READ DESIGN
# ═══════════════════════════════════════════════════════════════════════════════
flow_proc read_design {
    handle_info "PT-RM: Reading design..."

    # Read gate-level netlist
    if {[info exists sta(input,netlist)] && [file exists $sta(input,netlist)]} {
        read_verilog $sta(input,netlist)
        handle_info "  read_verilog: [file tail $sta(input,netlist)]"
    } else {
        handle_error "Netlist not found"
    }

    current_design $::DESIGN_NAME
    link_design
    handle_info "  Linked: $::DESIGN_NAME"
}

# ═══════════════════════════════════════════════════════════════════════════════
# PT-RM: READ PARASITICS (SPEF)
# ═══════════════════════════════════════════════════════════════════════════════
flow_proc read_parasitics_spef {
    handle_info "PT-RM: Reading parasitics..."

    if {[info exists sta(input,spef)] && $sta(input,spef) ne ""} {
        foreach spef $sta(input,spef) {
            if {[file exists $spef]} {
                read_parasitics -format spef $spef
                handle_info "  read_parasitics: [file tail $spef]"
            }
        }
    } else {
        handle_warning "No SPEF specified"
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# PT-RM: READ CONSTRAINTS (SDC)
# ═══════════════════════════════════════════════════════════════════════════════
flow_proc read_constraints {
    handle_info "PT-RM: Reading constraints..."

    # Primary SDC
    if {[info exists sta(input,sdc_func_file)] && [file exists $sta(input,sdc_func_file)]} {
        read_sdc $sta(input,sdc_func_file)
        handle_info "  read_sdc: [file tail $sta(input,sdc_func_file)]"
    }

    # UPF (IEEE 1801)
    if {[info exists sta(input,upf_file)] && $sta(input,upf_file) ne "" && [file exists $sta(input,upf_file)]} {
        load_upf $sta(input,upf_file)
        handle_info "  load_upf: [file tail $sta(input,upf_file)]"
    }

    # Propagate clocks (post-CTS design)
    set_propagated_clock [all_clocks]
    handle_info "  set_propagated_clock: all clocks"
}

# ═══════════════════════════════════════════════════════════════════════════════
# PT-RM: CHECK CONSTRAINTS (from dmsa_analysis.tcl)
# ═══════════════════════════════════════════════════════════════════════════════
flow_proc check_constraints_and_timing {
    handle_info "PT-RM: Constraint and timing check..."

    check_constraints -verbose > $::REPORTS_DIR/${::DESIGN_NAME}_check_constraints.rpt
    handle_info "  check_constraints written"

    set_operating_conditions -analysis_type on_chip_variation

    update_timing -full
    handle_info "  update_timing -full completed"

    check_timing -verbose > $::REPORTS_DIR/${::DESIGN_NAME}_check_timing.rpt
    handle_info "  check_timing written"
}

# ═══════════════════════════════════════════════════════════════════════════════
# PT-RM: TIMING ANALYSIS (from dmsa_analysis.tcl report_timing section)
# ═══════════════════════════════════════════════════════════════════════════════
flow_proc run_timing_analysis {
    handle_info "PT-RM: Timing analysis..."

    set max_paths [expr {[info exists sta(analysis,max_paths)] ? $sta(analysis,max_paths) : 100}]

    # PT-RM: report_global_timing (merged view)
    report_global_timing > $::REPORTS_DIR/${::DESIGN_NAME}_report_global_timing.rpt
    handle_info "  report_global_timing written"

    # PT-RM: Setup timing with PBA exhaustive (from dmsa_analysis.tcl)
    report_timing -crosstalk_delta \
        -slack_lesser_than 0.0 \
        -pba_mode exhaustive \
        -delay_type max \
        -nosplit \
        -input_pins -nets \
        -significant_digits 4 \
        -max_paths $max_paths \
        > $::REPORTS_DIR/${::DESIGN_NAME}_setup_timing_pba.rpt
    handle_info "  Setup timing (PBA exhaustive) written"

    # Setup — all paths (graph based)
    report_timing -delay_type max \
        -max_paths $max_paths \
        -path_type full_clock \
        -input_pins -nets -transition_time -capacitance \
        -significant_digits 4 \
        > $::REPORTS_DIR/${::DESIGN_NAME}_setup_timing.rpt
    handle_info "  Setup timing (GBA) written"

    # Hold timing
    report_timing -delay_type min \
        -max_paths $max_paths \
        -path_type full_clock \
        -input_pins -nets -transition_time -capacitance \
        -significant_digits 4 \
        > $::REPORTS_DIR/${::DESIGN_NAME}_hold_timing.rpt
    handle_info "  Hold timing written"

    # PT-RM: Analysis coverage
    report_analysis_coverage > $::REPORTS_DIR/${::DESIGN_NAME}_analysis_coverage.rpt
    handle_info "  Analysis coverage written"

    # Extract WNS
    catch {
        set ::setup_wns [get_attribute [get_timing_paths -delay_type max -max_paths 1] slack]
        set ::hold_wns  [get_attribute [get_timing_paths -delay_type min -max_paths 1] slack]
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# PT-RM: CONSTRAINT VIOLATIONS
# ═══════════════════════════════════════════════════════════════════════════════
flow_proc report_violations {
    handle_info "PT-RM: Constraint violations..."

    # PT-RM: report_constraints -all_violators (both per-scenario and merged)
    report_constraints -all_violators -verbose > $::REPORTS_DIR/${::DESIGN_NAME}_constraints_violations.rpt
    handle_info "  Constraint violations written"

    # Design and net reports
    report_design > $::REPORTS_DIR/${::DESIGN_NAME}_report_design.rpt
    report_net > $::REPORTS_DIR/${::DESIGN_NAME}_report_net.rpt
    handle_info "  Design/net reports written"
}

# ═══════════════════════════════════════════════════════════════════════════════
# PT-RM: CLOCK ANALYSIS
# ═══════════════════════════════════════════════════════════════════════════════
flow_proc report_clock_analysis {
    handle_info "PT-RM: Clock analysis..."

    # PT-RM: report_clock -skew -attribute
    report_clock -skew -attribute > $::REPORTS_DIR/${::DESIGN_NAME}_clock_skew.rpt
    handle_info "  Clock skew written"

    # Clock timing summary
    report_clock_timing -type summary > $::REPORTS_DIR/${::DESIGN_NAME}_clock_timing.rpt
    handle_info "  Clock timing written"
}

# ═══════════════════════════════════════════════════════════════════════════════
# PT-RM: NOISE / SI ANALYSIS (from dmsa_analysis.tcl noise section)
# ═══════════════════════════════════════════════════════════════════════════════
flow_proc run_noise_analysis {
    if {![info exists sta(analysis,si_aware)] || $sta(analysis,si_aware) ne "true"} {
        handle_info "SI/Noise: skipped (si_aware not enabled)"
        return
    }

    handle_info "PT-RM: Noise/SI analysis..."

    # PT-RM: SI double switching
    report_si_double_switching -nosplit -rise -fall > $::REPORTS_DIR/${::DESIGN_NAME}_si_double_switching.rpt
    handle_info "  SI double switching written"

    # PT-RM: Noise settings and analysis
    set_noise_parameters -enable_propagation -analysis_mode report_at_endpoint
    check_noise > $::REPORTS_DIR/${::DESIGN_NAME}_check_noise.rpt
    update_noise
    handle_info "  Noise updated"

    # Noise reports (above low, below high — from PT-RM)
    report_noise -nosplit -all_violators -above -low > $::REPORTS_DIR/${::DESIGN_NAME}_noise_above_low.rpt
    report_noise -nosplit -nworst 10 -above -low > $::REPORTS_DIR/${::DESIGN_NAME}_noise_nworst_above_low.rpt
    report_noise -nosplit -all_violators -below -high > $::REPORTS_DIR/${::DESIGN_NAME}_noise_below_high.rpt
    report_noise -nosplit -nworst 10 -below -high > $::REPORTS_DIR/${::DESIGN_NAME}_noise_nworst_below_high.rpt
    handle_info "  Noise reports written"
}

# ═══════════════════════════════════════════════════════════════════════════════
# PT-RM: AOCV / IVM REPORTS
# ═══════════════════════════════════════════════════════════════════════════════
flow_proc report_ocv {
    if {[info exists sta(analysis,ocv_mode)] && $sta(analysis,ocv_mode) eq "aocv"} {
        handle_info "PT-RM: AOCV reporting..."
        report_aocvm > $::REPORTS_DIR/${::DESIGN_NAME}_aocvm.rpt
        handle_info "  AOCV report written"
    }
    catch { report_ivm > $::REPORTS_DIR/${::DESIGN_NAME}_ivm.rpt }
}

# ═══════════════════════════════════════════════════════════════════════════════
# PT-RM: POWER ANALYSIS (PT-PX)
# ═══════════════════════════════════════════════════════════════════════════════
flow_proc run_power_analysis {
    if {![info exists sta(analysis,report_power)] || $sta(analysis,report_power) ne "true"} {
        return
    }
    handle_info "PT-RM: Power analysis (PT-PX)..."

    report_power > $::REPORTS_DIR/${::DESIGN_NAME}_power.rpt
    report_power -hierarchy > $::REPORTS_DIR/${::DESIGN_NAME}_power_hierarchy.rpt
    handle_info "  Power reports written"
}

# ═══════════════════════════════════════════════════════════════════════════════
# PT-RM: ETM EXTRACTION (from dmsa_analysis.tcl)
# ═══════════════════════════════════════════════════════════════════════════════
flow_proc extract_timing_model {
    if {[info exists sta(extract_etm)] && $sta(extract_etm) eq "true"} {
        handle_info "PT-RM: Extracting ETM..."
        extract_model -library_cell -test_design \
            -output $::RESULTS_DIR/${::DESIGN_NAME} -format {lib db}
        write_interface_timing $::REPORTS_DIR/${::DESIGN_NAME}_etm_interface_timing.rpt
        handle_info "  ETM extracted"
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# PT-RM: SAVE SESSION
# ═══════════════════════════════════════════════════════════════════════════════
flow_proc save_session_data {
    handle_info "PT-RM: Saving session..."
    save_session $::RESULTS_DIR/${::DESIGN_NAME}_${::scenario_name}_ss
    handle_info "  Session saved: ${::DESIGN_NAME}_${::scenario_name}_ss"
}

# ═══════════════════════════════════════════════════════════════════════════════
# SUMMARY REPORT
# ═══════════════════════════════════════════════════════════════════════════════
flow_proc generate_summary {
    handle_info "Generating corner summary..."

    set summary "$::REPORTS_DIR/timing_${::scenario_name}_summary.rpt"
    set fh [open $summary "w"]
    puts $fh "═══════════════════════════════════════════════════════════════"
    puts $fh "  CBflow PT-RM W-2024.09 Per-Corner Timing Summary"
    puts $fh "  Generated: [clock format [clock seconds]]"
    puts $fh "═══════════════════════════════════════════════════════════════"
    puts $fh ""
    puts $fh "  Scenario:    $::scenario_name"
    puts $fh "  Design:      $::DESIGN_NAME"
    puts $fh "  Corner:      $::CORNER"
    puts $fh "  Mode:        $::MODE"
    puts $fh "  Voltage:     ${::VOLTAGE}V"
    puts $fh "  Temperature: ${::TEMPERATURE}C"
    puts $fh "  RC Corner:   $::RC_CORNER"
    puts $fh "  Library Set: $::LIB_SET"
    puts $fh ""
    puts $fh [string repeat "─" 60]
    puts $fh [format "  %-20s  %12s  %12s" "Analysis" "WNS (ns)" "Status"]
    puts $fh [string repeat "─" 60]
    set s_st [expr {$::setup_wns >= 0 ? "MET" : "VIOLATED"}]
    set h_st [expr {$::hold_wns >= 0 ? "MET" : "VIOLATED"}]
    puts $fh [format "  %-20s  %12.4f  %12s" "Setup (max)" $::setup_wns $s_st]
    puts $fh [format "  %-20s  %12.4f  %12s" "Hold (min)" $::hold_wns $h_st]
    puts $fh [string repeat "─" 60]
    puts $fh ""
    puts $fh "  Reports: $::REPORTS_DIR/"
    puts $fh "  Session: $::RESULTS_DIR/${::DESIGN_NAME}_${::scenario_name}_ss"
    puts $fh ""
    close $fh
    handle_info "  Summary: $summary"
}

# ═══════════════════════════════════════════════════════════════════════════════
# EXECUTE ALL (PT-RM flow order)
# ═══════════════════════════════════════════════════════════════════════════════
set ::setup_wns 0.0
set ::hold_wns  0.0

flow_exec_all

handle_info "PT-RM per-corner completed: $scenario_name"
exit
