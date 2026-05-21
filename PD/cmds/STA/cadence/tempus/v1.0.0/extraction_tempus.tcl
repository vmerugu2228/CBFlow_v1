#!/usr/bin/env tclsh
# STA extraction - Cadence Tempus

# -- Bootstrap -----------------------------------------------------------------
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "STA"
set STAGE_NAME "extraction"
set NODE_NAME "extraction1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

handle_info "Starting STA extraction stage with Cadence Tempus..."

# ── CPU threading (Tempus RAK) ───────────────────────────────────────────────
set _cpu [expr {[info exists sta(tool,cpu_count)] && $sta(tool,cpu_count) ne "" ? $sta(tool,cpu_count) : 8}]
set_multi_cpu_usage -localCpu $_cpu
handle_info "CPUs: $_cpu"

# ── SI-aware delay cal mode (before extraction, Tempus RAK) ──────────────────
if {[info exists sta(timing,si_aware)] && $sta(timing,si_aware) eq "true"} {
    set_delay_cal_mode -siAware true
    handle_info "SI-aware delay calculation: enabled (pre-extraction)"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                       MMMC CONFIGURATION                                   │
# └─────────────────────────────────────────────────────────────────────────────┘

# Source MMMC multi-corner configuration for extraction
set mmmc_config_file "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/mmmc_config.tcl"
if {[file exists $mmmc_config_file]} {
    source $mmmc_config_file
    handle_info "MMMC configuration loaded: $mmmc_config_file"
    global analysis_views
    if {[info exists analysis_views]} {
        handle_info "  MMMC scenarios available: [llength [array names analysis_views]]"
    }
} else {
    handle_warning "MMMC config not found: $mmmc_config_file -- single-corner extraction"
}

# Source active scenarios if available
set scenarios_file "$run_dir/work/STA/mmmc_setup/run/active_scenarios.tcl"
if {[file exists $scenarios_file]} {
    source $scenarios_file
    handle_info "Active scenarios loaded for extraction"
}

if {![namespace exists ::flow]} {
    namespace eval ::flow {
        variable exec_mode "auto"
        variable current_stage ""
        variable start_time [clock seconds]
        variable flow_errors {}
    }
}
set ::flow::exec_mode "auto"

set WORK_DIR "$run_dir/work/STA/extraction"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                       SETUP LIBRARIES                                      │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc setup_libraries {
    global sta project tech flow FLOW_DIR
    handle_info "Setting up libraries for extraction..."

    if {[info exists tech(lib,timing)]} {
        puts "Reading Liberty files:"
        set lib_files [expr {[string match "*{*}*" $tech(lib,timing)] ? $tech(lib,timing) : [list $tech(lib,timing)]}]
        foreach lib $lib_files {
            set project_root [file dirname $FLOW_DIR]
            set expanded_lib [subst $lib]
            set lib_path [file join $project_root $expanded_lib]
            if {[file exists $lib_path]} {
                puts "   $lib"
                read_lib $lib_path
            } else {
                handle_warning "Liberty file not found: $lib_path"
            }
        }
    } else {
        handle_warning "tech(lib,timing) not defined"
    }

    # Read LEF files for physical data
    if {[info exists tech(lef,standard_cells)]} {
        puts "Reading LEF files:"
        set project_root [file dirname $FLOW_DIR]
        if {[info exists tech(lef,technology)]} {
            set lef_path [file join $project_root [subst $tech(lef,technology)]]
            if {[file exists $lef_path]} {
                puts "   [file tail $tech(lef,technology)]"
                read_lef $lef_path
            }
        }
        set lef_path [file join $project_root [subst $tech(lef,standard_cells)]]
        if {[file exists $lef_path]} {
            puts "   [file tail $tech(lef,standard_cells)]"
            read_lef $lef_path
        }
    }

    puts " Libraries setup completed"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                       READ DESIGN                                          │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc read_design {
    global sta project tech flow FLOW_DIR
    handle_info "Reading design for extraction..."

    set run_dir $::env(CBFLOW_RUN_DIR)
    set netlist_dir "$run_dir/work/STA/inputs/netlist"
    set netlist_files [glob -nocomplain "$netlist_dir/*.v" "$netlist_dir/*.sv" "$netlist_dir/*.vg"]

    if {[llength $netlist_files] > 0} {
        puts "Found [llength $netlist_files] netlist files"
        foreach netlist $netlist_files {
            puts "   Reading: [file tail $netlist]"
            read_verilog $netlist
        }
    } else {
        handle_error "No netlist files found in $netlist_dir"
    }

    if {[info exists project(top_module)]} {
        puts "Setting top module: $project(top_module)"
        set_top_module $project(top_module)
    }

    puts " Design loaded"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                       READ CONSTRAINTS                                     │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc read_constraints {
    global sta project tech flow
    handle_info "Reading SDC constraints..."

    set run_dir $::env(CBFLOW_RUN_DIR)
    set sdc_files [glob -nocomplain "$run_dir/work/STA/inputs/sdc/*.sdc"]

    if {[llength $sdc_files] > 0} {
        foreach sdc $sdc_files {
            puts "   Reading: [file tail $sdc]"
            read_sdc $sdc
        }
        puts " Constraints loaded"
    } else {
        handle_warning "No SDC files found"
    }
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                       RUN EXTRACTION                                       │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc run_extraction {
    global sta project tech flow
    handle_info "Running parasitic extraction..."

    file mkdir "$::OUTPUTS_DIR/extraction"
    file mkdir "$::REPORTS_DIR"

    # Configure extraction settings
    if {[info exists sta(extraction,mode)]} {
        puts "Extraction mode: $sta(extraction,mode)"
    } else {
        puts "Extraction mode: default (coupled)"
    }

    if {[info exists sta(extraction,effort)]} {
        puts "Extraction effort: $sta(extraction,effort)"
    }

    # Run extraction
    puts "Running parasitic extraction..."
    extract_rc

    # Write SPEF output
    puts "Writing SPEF file..."
    write_spef "$::OUTPUTS_DIR/extraction/parasitic.spef"

    # Generate extraction report
    report_extraction > "$::REPORTS_DIR/extraction_summary.rpt"

    puts " Extraction completed"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                       VALIDATE EXTRACTION                                  │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc validate_extraction_results {
    global sta project tech flow FLOW_DIR
    handle_info "Validating extraction results..."

    set current_dir $::env(CBFLOW_RUN_DIR)

    set spef_file "$current_dir/results/extraction/parasitic.spef"
    if {[file exists $spef_file]} {
        handle_info "SPEF file verified: $spef_file"
    } else {
        handle_warning "SPEF file not found: $spef_file"
    }

    set validation_flow_dir [expr {[info exists FLOW_DIR] ? $FLOW_DIR : $::env(FLOW_DIR)}]
    set enhanced_validation_script "$validation_flow_dir/utils/validation/v1.0.0/enhanced_validate_run.tcl"
    if {[file exists $enhanced_validation_script]} {
        if {[catch {exec tclsh $enhanced_validation_script STA extraction $current_dir $validation_flow_dir} result]} {
            handle_warning "Validation completed with warnings: $result"
        } else {
            handle_info "Validation completed successfully"
        }
    }
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                           EXECUTION CONTROL                                │
# └─────────────────────────────────────────────────────────────────────────────┘

handle_info "═══════════════════════════════════════════════════════════════════════════════"
handle_info " CBFlow STA Extraction with Cadence Tempus"
handle_info "═══════════════════════════════════════════════════════════════════════════════"

flow_proc extraction_flow {
    handle_info "Executing STA extraction flow..."

    flow_exec setup_libraries
    flow_exec read_design
    flow_exec read_constraints
    flow_exec run_extraction
    flow_exec validate_extraction_results

    handle_info "═══════════════════════════════════════════════════════════════════════════════"
    handle_info " STA Extraction Complete!"
    handle_info "═══════════════════════════════════════════════════════════════════════════════"
    puts "SPEF output: results/extraction/parasitic.spef"
    handle_info "STA extraction completed successfully"
}

if {[info exists argv0] && $argv0 eq [info script]} {
    flow_exec extraction_flow
} else {
    puts " CBFlow STA extraction procedures loaded"
    puts "Available: setup_libraries, read_design, read_constraints, run_extraction, validate_extraction_results, extraction_flow"
}

# Exit tool after stage completion
exit
