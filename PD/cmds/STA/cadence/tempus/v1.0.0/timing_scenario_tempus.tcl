#!/usr/bin/env tclsh
# STA Per-Corner Timing Analysis - Cadence Tempus

# -- Bootstrap -----------------------------------------------------------------
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "STA"
set STAGE_NAME "timing"
set NODE_NAME "timing1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# Source scenario context written by subnode_handler
if {[info exists ::env(CBFLOW_SCENARIO)]} {
    set _ctx "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/$::env(CBFLOW_SCENARIO)_context.tcl"
    if {[file exists $_ctx]} { source $_ctx }
}

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 1: CREATE MMMC OBJECTS (Tempus native MMMC)
# ═══════════════════════════════════════════════════════════════════════════════
flow_proc create_mmmc_view {
    handle_info "Creating MMMC analysis view for: $::scenario_name"

    # Create library set from library_sets array
    set lib_files {}
    if {[info exists library_sets(${::LIB_SET},timing)]} {
        set lib_files $library_sets(${::LIB_SET},timing)
    }
    create_library_set -name $::LIB_SET -timing $lib_files
    handle_info "  Library set: $::LIB_SET ([llength $lib_files] libs)"

    # Create RC corner
    create_rc_corner -name $::RC_CORNER -T $::TEMPERATURE
    handle_info "  RC corner: $::RC_CORNER (T=${::TEMPERATURE}C)"

    # Create delay corner (library set + RC corner)
    set dc_name "dc_${::CORNER}_${::RC_CORNER}"
    create_delay_corner -name $dc_name \
        -library_set $::LIB_SET \
        -rc_corner $::RC_CORNER
    handle_info "  Delay corner: $dc_name"

    # Create constraint mode
    set cm_name "cm_${::MODE}"
    set sdc_file ""
    if {[info exists ::SDC_FILE] && $::SDC_FILE ne ""} {
        set sdc_file $::SDC_FILE
    } elseif {[info exists sta(input,sdc_func_file)]} {
        set sdc_file $sta(input,sdc_func_file)
    }
    if {$sdc_file ne "" && [file exists $sdc_file]} {
        create_constraint_mode -name $cm_name -sdc_files $sdc_file
        handle_info "  Constraint mode: $cm_name (SDC: [file tail $sdc_file])"
    }

    # Create analysis view
    create_analysis_view -name $::scenario_name \
        -delay_corner $dc_name \
        -constraint_mode $cm_name
    handle_info "  Analysis view: $::scenario_name"

    # Set as active view for both setup and hold
    set_analysis_view -setup $::scenario_name -hold $::scenario_name
    handle_info "  Active view set for setup + hold"
}

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 2: READ DESIGN
# ═══════════════════════════════════════════════════════════════════════════════
flow_proc read_design {
    handle_info "Reading design..."

    # Read LEF (physical)
    if {[info exists tech(lef,technology)] && [file exists $tech(lef,technology)]} {
        read_lef $tech(lef,technology)
        handle_info "  Tech LEF: [file tail $tech(lef,technology)]"
    }
    if {[info exists tech(lef,standard_cells)] && [file exists $tech(lef,standard_cells)]} {
        read_lef $tech(lef,standard_cells)
    }

    # Read netlist
    set netlist $sta(input,netlist)
    if {[file exists $netlist]} {
        read_verilog $netlist
        handle_info "  Netlist: [file tail $netlist]"
    } else {
        handle_error "Netlist not found: $netlist"
    }

    set top [expr {[info exists project(top_module)] ? $project(top_module) : $::env(CBFLOW_DESIGN_NAME)}]
    set_top_module $top
    handle_info "  Top module: $top"
}

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 3: READ PARASITICS
# ═══════════════════════════════════════════════════════════════════════════════
flow_proc read_parasitics_data {
    handle_info "Reading parasitics..."

    if {[info exists ::SPEF_FILE] && $::SPEF_FILE ne "" && [file exists $::SPEF_FILE]} {
        read_spef $::SPEF_FILE
        handle_info "  SPEF: [file tail $::SPEF_FILE]"
    } elseif {[info exists sta(input,spef)] && $sta(input,spef) ne ""} {
        foreach spef $sta(input,spef) {
            if {[file exists $spef]} {
                read_spef $spef
                handle_info "  SPEF: [file tail $spef]"
            }
        }
    } else {
        handle_warning "No SPEF — timing without parasitics"
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 4: UPDATE TIMING
# ═══════════════════════════════════════════════════════════════════════════════
flow_proc update_timing_data {
    handle_info "Updating timing..."
    update_timing -full
    handle_info "  Timing updated"
}

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 5: SETUP (LATE) ANALYSIS
# ═══════════════════════════════════════════════════════════════════════════════
flow_proc run_setup_analysis {
    handle_info "Running SETUP analysis (late paths)..."

    set max_paths [expr {[info exists sta(analysis,max_paths)] ? $sta(analysis,max_paths) : 100}]

    # Setup timing
    report_timing -late \
        -max_paths $max_paths \
        -path_type full_clock \
        -net \
        > "$::REPORTS_DIR/setup_timing.rpt"
    handle_info "  Setup timing report written"

    # Constraint violations
    report_constraint -all_violators \
        > "$::REPORTS_DIR/setup_violations.rpt"
    handle_info "  Setup violations written"

    # Clock timing
    report_clock_timing -type summary \
        > "$::REPORTS_DIR/clock_timing_setup.rpt"

    # QoR
    report_qor > "$::REPORTS_DIR/qor_setup.rpt"

    set ::setup_wns [get_property [get_timing_paths -max_paths 1 -late] slack]
    handle_info "  Setup WNS: $::setup_wns"
}

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 6: HOLD (EARLY) ANALYSIS
# ═══════════════════════════════════════════════════════════════════════════════
flow_proc run_hold_analysis {
    handle_info "Running HOLD analysis (early paths)..."

    set max_paths [expr {[info exists sta(analysis,max_paths)] ? $sta(analysis,max_paths) : 100}]

    # Hold timing
    report_timing -early \
        -max_paths $max_paths \
        -path_type full_clock \
        -net \
        > "$::REPORTS_DIR/hold_timing.rpt"
    handle_info "  Hold timing report written"

    # Hold violations
    report_constraint -all_violators \
        > "$::REPORTS_DIR/hold_violations.rpt"

    # QoR
    report_qor > "$::REPORTS_DIR/qor_hold.rpt"

    set ::hold_wns [get_property [get_timing_paths -max_paths 1 -early] slack]
    handle_info "  Hold WNS: $::hold_wns"
}

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 7: POWER ANALYSIS
# ═══════════════════════════════════════════════════════════════════════════════
flow_proc run_power_analysis {
    if {[info exists sta(analysis,report_power)] && $sta(analysis,report_power) eq "true"} {
        handle_info "Running power analysis..."
        report_power > "$::REPORTS_DIR/power.rpt"
        report_power -hierarchy > "$::REPORTS_DIR/power_hierarchy.rpt"
        handle_info "  Power reports written"
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 8: SUMMARY
# ═══════════════════════════════════════════════════════════════════════════════
flow_proc generate_scenario_summary {
    handle_info "Generating summary..."

    set summary "$::REPORTS_DIR/timing_${::scenario_name}_summary.rpt"
    set fh [open $summary "w"]
    puts $fh "═══════════════════════════════════════════════════════════════"
    puts $fh "  CBFlow Tempus Per-Corner Timing Summary"
    puts $fh "  Generated: [clock format [clock seconds]]"
    puts $fh "═══════════════════════════════════════════════════════════════"
    puts $fh ""
    puts $fh "Scenario:    $::scenario_name"
    puts $fh "Corner:      $::CORNER"
    puts $fh "Mode:        $::MODE"
    puts $fh "Voltage:     ${::VOLTAGE}V"
    puts $fh "Temperature: ${::TEMPERATURE}C"
    puts $fh "RC Corner:   $::RC_CORNER"
    puts $fh "Library Set: $::LIB_SET"
    puts $fh ""
    puts $fh [string repeat "─" 60]
    puts $fh [format "  %-20s  %12s  %12s" "Analysis" "WNS (ns)" "Status"]
    puts $fh [string repeat "─" 60]

    set s_status [expr {$::setup_wns >= 0 ? "MET" : "VIOLATED"}]
    set h_status [expr {$::hold_wns >= 0 ? "MET" : "VIOLATED"}]
    puts $fh [format "  %-20s  %12.4f  %12s" "Setup (late)" $::setup_wns $s_status]
    puts $fh [format "  %-20s  %12.4f  %12s" "Hold (early)" $::hold_wns $h_status]
    puts $fh [string repeat "─" 60]
    puts $fh ""
    puts $fh "Reports: $::REPORTS_DIR/"
    puts $fh ""
    close $fh
    handle_info "  Summary: $summary"
}

# ═══════════════════════════════════════════════════════════════════════════════
# EXECUTE
# ═══════════════════════════════════════════════════════════════════════════════
set ::setup_wns 0.0
set ::hold_wns  0.0

flow_exec_all

handle_info "Tempus per-corner timing completed: $scenario_name"

# Exit tool after stage completion
exit
