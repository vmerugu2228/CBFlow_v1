#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow STA Per-Corner Timing Analysis — Cadence Tempus
# Runs setup (late) + hold (early) analysis for a single PVT corner/scenario
# Usage: tempus -batch -f timing_scenario_tempus.tcl <scenario_name>
# ═══════════════════════════════════════════════════════════════════════════════

# ── Environment & Utilities ──────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
set FLOW_DIR $::env(FLOW_DIR)
source "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
namespace import ::CBFlow::Utilities::print_header

# Source configs
set config_file "$run_dir/work/STA/timing1/run/config.tcl"
if {[file exists $config_file]} { source $config_file }
if {[file exists "$run_dir/setup/user_config.tcl"]} { source "$run_dir/setup/user_config.tcl" }
global sta project tech flow library_sets

# Source MMMC and tech config
set mmmc_config "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/mmmc_config.tcl"
if {[file exists $mmmc_config]} { source $mmmc_config }
set tech_config "$::env(CONFIG_ROOT)/tech/$::env(TECH_NAME)/$::env(TECH_VERSION)/tech_config.tcl"
if {[file exists $tech_config]} { source $tech_config }

# ── Scenario Name ────────────────────────────────────────────────────────────
if {$argc < 1} {
    puts stderr "ERROR: Missing scenario_name. Usage: tempus -batch -f timing_scenario_tempus.tcl <scenario>"
    exit 1
}
set scenario_name [lindex $argv 0]
set FLOW_TYPE "STA"
set STAGE_NAME "timing"

global analysis_views
if {![info exists analysis_views($scenario_name)]} {
    puts stderr "ERROR: Scenario '$scenario_name' not found in analysis_views"
    exit 1
}
array set VIEW $analysis_views($scenario_name)

set CORNER      $VIEW(corner)
set MODE        $VIEW(mode)
set VOLTAGE     $VIEW(voltage)
set TEMPERATURE $VIEW(temperature)
set RC_CORNER   $VIEW(rc_corner)
set LIB_SET     $VIEW(lib_set_ref)
set SDC_FILE    $VIEW(constraint_file)

set WORK_DIR    "$run_dir/work/$FLOW_TYPE/timing1/run"
set REPORTS_DIR "$run_dir/reports/sta/$scenario_name"
file mkdir $WORK_DIR $REPORTS_DIR

# Source TEMPUS tool config
set _tool_config "[file dirname [info script]]/tempus_config.tcl"
if {[file exists $_tool_config]} { source $_tool_config }
handle_info "═══════════════════════════════════════════════════════════"
handle_info "  Tempus Per-Corner Timing: $scenario_name"
handle_info "  Corner=$CORNER  Mode=$MODE  V=${VOLTAGE}V  T=${TEMPERATURE}C"
handle_info "  RC=$RC_CORNER  LibSet=$LIB_SET"
handle_info "═══════════════════════════════════════════════════════════"

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
    set sdc_file [expr {[info exists sta(input,sdc_func_file)] ? $sta(input,sdc_func_file) : ""}]
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

    if {[info exists sta(input,spef)] && $sta(input,spef) ne ""} {
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

    set max_paths [expr {[info exists tempus(analysis,max_paths)] ? $tempus(analysis,max_paths) : 100}]

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

    set max_paths [expr {[info exists tempus(analysis,max_paths)] ? $tempus(analysis,max_paths) : 100}]

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
    if {[info exists tempus(analysis,report_power)] && $tempus(analysis,report_power) eq "true"} {
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
