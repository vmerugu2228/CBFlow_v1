#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# OMNI FLOW - Synthesis Command File
# Description: Synthesis flow using flow_proc framework - Genus Implementation
# Usage: Source this file in Genus or run standalone
# ═══════════════════════════════════════════════════════════════════════════════

# Source environment variables first
# Use environment variable to find run directory, fallback to current directory
set run_dir $::env(CBFLOW_RUN_DIR)
set env_file "$run_dir/.run.cbflow.tcl"

if {[file exists $env_file]} {
    source $env_file
} else {
    puts stderr "ERROR: Environment file (.run.cbflow.tcl) not found at $env_file"
    exit 1
}

# Source flow utilities (includes flow procedure management)
# Get FLOW_DIR from environment
if {[info exists ::env(FLOW_DIR)]} {
    set FLOW_DIR $::env(FLOW_DIR)
} else {
    puts stderr "ERROR: FLOW_DIR not found in environment"
    exit 1
}

# Validate UTILITIES_VERSION is set from release environment
if {![info exists ::env(UTILITIES_VERSION)] || $::env(UTILITIES_VERSION) eq ""} {
    puts stderr "ERROR: UTILITIES_VERSION not set. Ensure .run.cbflow.tcl is properly generated."
    exit 1
}

set utils_path "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} {
    source $utils_path
} else {
    puts stderr "ERROR: Cannot find flow utilities at $utils_path"
    exit 1
}

# Import required utilities into global namespace
namespace import ::CBFlow::Utilities::print_header
# CBFLOW_HEADER is already available globally from error_utils.tcl

# Source generated configuration file (from setup stage)
set config_file "$run_dir/work/SYNTH/synthesis/run/config.tcl"

if {[file exists $config_file]} {
    source $config_file

# Source tech_config
if {[info exists ::env(TECH_NAME)] && $::env(TECH_NAME) ne "" && [info exists ::env(TECH_VERSION)]} {
    set _tc "$::env(CONFIG_ROOT)/tech/$::env(TECH_NAME)/$::env(TECH_VERSION)/tech_config.tcl"
    if {[file exists $_tc]} { source -e $_tc }
}

# Source user_config for overrides
if {[file exists "$run_dir/setup/user_config.tcl"]} { source -e "$run_dir/setup/user_config.tcl" }
} else {
    puts stderr "ERROR: Cannot find generated config file at $config_file. Run 'make synthesis_setup' first."
    exit 1
}

# Setup file will source this command file - no need to source setup here

# Source synthesis configuration
if {[file exists "$FLOW_DIR/config/SYNTH/synthesis_config.tcl"]} {
    source "$FLOW_DIR/config/SYNTH/synthesis_config.tcl"
} else {
    handle_warning "Cannot find synthesis configuration file"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                     MMMC CONFIGURATION                                     │
# └─────────────────────────────────────────────────────────────────────────────┘

# Source MMMC multi-corner configuration for synthesis
set mmmc_config_file "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/mmmc_config.tcl"
if {[file exists $mmmc_config_file]} {
    source $mmmc_config_file
    # Source GENUS tool config
set _tool_config "[file dirname [info script]]/genus_config.tcl"
if {[file exists $_tool_config]} { source $_tool_config }
handle_info "MMMC configuration loaded: $mmmc_config_file"
} else {
    handle_warning "MMMC config not found: $mmmc_config_file -- single-corner mode"
}

# Load multi-corner libraries from MMMC scenarios
global analysis_views
if {[info exists analysis_views]} {
    set project_root [file dirname $FLOW_DIR]
    set synth_scenarios [lsort [array names analysis_views]]
    handle_info "MMMC: Loading libraries for [llength $synth_scenarios] corner scenarios"

    foreach scenario $synth_scenarios {
        array set view_info $analysis_views($scenario)
        handle_info "  Scenario: $scenario (corner=$view_info(corner), voltage=$view_info(voltage)V, temp=$view_info(temperature)C)"

        # Load corner-specific libraries via lib_set reference
        if {[info exists view_info(lib_set_ref)]} {
            set lib_ref $view_info(lib_set_ref)
            # Library sets are defined in mmmc_config; bind them for this corner
            handle_info "    Library set: $lib_ref"
        }
        array unset view_info
    }
}

# Declare global arrays for hierarchical variables
global synth pnr project tech flow

handle_info "Starting synthesis flow with Cadence Genus..."

# Initialize flow namespace for proper flow_proc integration
if {![namespace exists ::flow]} {
    namespace eval ::flow {
        variable exec_mode "auto"
        variable current_stage ""
        variable start_time [clock seconds]
        variable flow_errors {}
    }
}

# Global variable declarations to access configuration arrays
global synth project tech flow

# Set execution mode to auto for proper flow_proc integration
set ::flow::exec_mode "auto"

# ── Directories ──────────────────────────────────────────────────────────────
set WORK_DIR "$run_dir/work/SYNTH/synthesis1"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                           SETUP LIBRARIES                                  │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc setup_libraries {
    global synth project tech flow FLOW_DIR RUN_DIR ROOT_DIR
    handle_info "Setting up libraries and search paths..."

    # Get library configuration from hierarchical structure
    
    # Read timing library files
    if {[info exists tech(lib,timing)]} {
        puts "Reading Liberty files:"
        set lib_files [expr {[string match "*{*}*" $tech(lib,timing)] ? $tech(lib,timing) : [list $tech(lib,timing)]}]
        foreach lib $lib_files {
            # ROOT_DIR should be project root, construct from FLOW_DIR
            set project_root [file dirname $FLOW_DIR]
            # Expand any variables in the library path
            set expanded_lib [subst $lib]
            set lib_path [file join $project_root $expanded_lib]
            if {[file exists $lib_path]} {
                puts "   $lib"
                read_libs $lib_path
            } else {
                puts "   Liberty file not found: $lib_path"
                handle_warning "Liberty file not found: $lib_path"
            }
        }
    } else {
        handle_error "tech(lib,timing) not defined in configuration"
    }
    
    # Read LEF files if available
    if {[info exists tech(lef,standard_cells)]} {
        puts "Reading LEF files:"

        # ROOT_DIR should be project root, construct from FLOW_DIR
        set project_root [file dirname $FLOW_DIR]

        # Read technology LEF
        if {[info exists tech(lef,technology)]} {
            set expanded_lef [subst $tech(lef,technology)]
            set lef_path [file join $project_root $expanded_lef]
            if {[file exists $lef_path]} {
                puts "   [file tail $tech(lef,technology)]"
                read_physical -lef $lef_path
            } else {
                puts "   Technology LEF file not found: $lef_path"
            }
        }
        
        # Read standard cell LEF
        set expanded_lef [subst $tech(lef,standard_cells)]
        set lef_path [file join $project_root $expanded_lef]
        if {[file exists $lef_path]} {
            puts "   [file tail $tech(lef,standard_cells)]"
            read_physical -lef $lef_path
        } else {
            puts "   Standard cell LEF file not found: $lef_path"
        }
    }
    
    puts " Libraries setup completed"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                            READ RTL FILES                                  │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc read_rtl_files {
    global synth project tech flow FLOW_DIR RUN_DIR ROOT_DIR
    puts " Reading RTL files..."

    # Find RTL files from inputs directory (relative to workspace root)
    set rtl_files [glob -nocomplain "$RUN_DIR/work/SYNTH/inputs/rtl/*"]

    if {[llength $rtl_files] > 0} {
        puts "Found [llength $rtl_files] RTL files in work/SYNTH/inputs/rtl/"
        
        # Auto-detect RTL format
        if {![info exists synth(input,format)]} {
            if {[llength [glob -nocomplain "$RUN_DIR/work/SYNTH/inputs/rtl/*.sv"]] > 0} {
                set synth(input,format) "sv"
            } elseif {[llength [glob -nocomplain "$RUN_DIR/work/SYNTH/inputs/rtl/*.v"]] > 0} {
                set synth(input,format) "verilog"
            } elseif {[llength [glob -nocomplain "$RUN_DIR/work/SYNTH/inputs/rtl/*.vhd*"]] > 0} {
                set synth(input,format) "vhdl"
            } else {
                set synth(input,format) "verilog"  # Default
            }
            puts "Auto-detected RTL format: $synth(input,format)"
        }
        
        # Read RTL files
        foreach rtl_file $rtl_files {
            puts "   Reading: [file tail $rtl_file]"
        }
        read_hdl -format $synth(input,format) $rtl_files
        puts " Read [llength $rtl_files] RTL files"
    } else {
        handle_error "No RTL files found in work/SYNTH/inputs/rtl/"
    }
    
    # Set top module
    if {[info exists project(top_module)]} {
        puts "Setting top module: $project(top_module)"
        set_top_module $project(top_module)
    } else {
        handle_error "project(top_module) not defined in configuration"
    }
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                          READ CONSTRAINTS                                  │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc read_constraints {
    global synth project tech flow FLOW_DIR RUN_DIR ROOT_DIR
    puts " Reading constraints..."
    
    # Find SDC files
    set sdc_files [glob -nocomplain "work/SYNTH/inputs/constraints/*.sdc"]
    if {[llength $sdc_files] > 0} {
        puts "Found [llength $sdc_files] SDC files"
        foreach sdc_file $sdc_files {
            puts "   Reading: [file tail $sdc_file]"
            read_sdc $sdc_file
        }
        puts " Constraints loaded successfully"
    } else {
        puts " No SDC files found in work/SYNTH/inputs/constraints/"
        handle_warning "No constraint files found - synthesis may not meet timing"
    }
    
    # Apply additional synthesis constraints from config
    if {[info exists project(clock,period)]} {
        puts "Clock period constraint: $project(clock,period) ns"
    }
    
    if {[info exists project(estimated_area)]} {
        puts "Estimated area: $project(estimated_area) um²"
    }
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                         ELABORATE DESIGN                                   │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc elaborate_design {
    puts " Starting RTL elaboration..."
    
    # Create reports directory
    file mkdir $::REPORTS_DIR

    # Elaborate the design
    if {[info exists project(top_module)]} {
        elaborate $project(top_module)
    } else {
        handle_error "project(top_module) not defined"
    }

    # Basic design checks
    check_design -type pre_mapping > "$::REPORTS_DIR/synth_check.rpt"

    # Generate hierarchy report
    report_design > "$::REPORTS_DIR/synth_hierarchy.rpt"

    puts " RTL elaboration completed"
    puts " Check reports: $::REPORTS_DIR/synth_check.rpt"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                        SYNTHESIZE DESIGN                                   │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc synthesize_design {
    puts " Starting synthesis and mapping..."
    
    # Configure synthesis options from hierarchical structure
    if {[info exists genus(common,effort)]} {
        set_db syn_opt_effort $genus(common,effort)
        puts "Synthesis effort: $genus(common,effort)"
    }
    
    if {[info exists genus(effort,mapping)]} {
        set_db syn_map_effort $genus(effort,mapping)
        puts "Mapping effort: $genus(effort,mapping)"
    }
    
    # Set timing-driven synthesis
    if {[info exists genus(effort,timing)]} {
        set_db syn_opt_timing_effort $genus(effort,timing)
        puts "Timing effort: $genus(effort,timing)"
    }
    
    # Set area-driven synthesis
    if {[info exists genus(effort,area)]} {
        set_db syn_opt_area_effort $genus(effort,area)
        puts "Area effort: $genus(effort,area)"
    }
    
    # Set synthesis strategy
    if {[info exists genus(common,strategy)]} {
        puts "Synthesis strategy: $genus(common,strategy)"
        switch $genus(common,strategy) {
            "timing" {
                set_db syn_opt_timing_driven true
                set_db syn_opt_area_driven false
            }
            "area" {
                set_db syn_opt_timing_driven false  
                set_db syn_opt_area_driven true
            }
            "power" {
                set_db syn_opt_timing_driven false
                set_db syn_opt_area_driven false
                set_db syn_opt_power_effort high
            }
            "timing_power" {
                set_db syn_opt_timing_driven true
                set_db syn_opt_area_driven false
                set_db syn_opt_power_effort medium
            }
            default {
                # Default balanced approach
                set_db syn_opt_timing_driven true
                set_db syn_opt_area_driven true
            }
        }
    }
    
    # Configure boundary optimization
    if {[info exists genus(optimization,boundary)]} {
        set_db syn_opt_boundary_optimization $genus(optimization,boundary)
    }
    
    # Set design constraints from hierarchical structure
    if {[info exists genus(constraints,max_fanout)]} {
        set_db design_max_fanout $genus(constraints,max_fanout)
        puts "Max fanout: $genus(constraints,max_fanout)"
    }
    
    if {[info exists genus(constraints,max_transition)]} {
        set_db design_max_transition $genus(constraints,max_transition)
        puts "Max transition: $genus(constraints,max_transition)"
    }
    
    # Run synthesis steps
    puts "Running syn_generic..."
    syn_generic
    
    puts "Running syn_map..."
    syn_map
    
    puts " Initial synthesis and mapping completed"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                         OPTIMIZE DESIGN                                    │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc optimize_design {
    puts " Starting optimization..."
    
    # Set up optimization options from hierarchical structure
    if {[info exists genus(area,recover_design_area)] && $genus(area,recover_design_area) eq "true"} {
        set_db syn_opt_area_recovery true
        puts "Area recovery: enabled"
    }
    
    # Fix hold violations if required
    if {[info exists genus(optimization,hold_fix)] && $genus(optimization,hold_fix) eq "true"} {
        set_db syn_opt_fix_hold_all_clocks true
        puts "Hold violation fixing: enabled"
    }
    
    # Multi-Vt optimization
    if {[info exists genus(optimization,multi_vt)] && $genus(optimization,multi_vt) eq "true"} {
        set_db syn_opt_multiple_vt_optimization true
        puts "Multi-Vt optimization: enabled"
    }
    
    # Power optimization
    if {[info exists genus(power,effort)] && $genus(power,effort) ne "none"} {
        set_db syn_opt_power_effort $genus(power,effort)
        puts "Power effort: $genus(power,effort)"
    }
    
    # Run optimization
    puts "Running syn_opt..."
    syn_opt
    
    puts " Optimization completed"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                          GENERATE REPORTS                                  │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc generate_reports {
    puts " Generating reports..."
    
    # Ensure reports directory exists
    file mkdir $::REPORTS_DIR

    # Generate timing reports
    puts "Generating timing reports..."
    report_timing -format {instance cell arc delay slew load} > "$::REPORTS_DIR/synth_timing.rpt"
    report_timing -summary > "$::REPORTS_DIR/synth_timing_summary.rpt"

    # Generate area reports
    puts "Generating area reports..."
    report_area > "$::REPORTS_DIR/synth_area.rpt"
    report_gates > "$::REPORTS_DIR/synth_gates.rpt"

    # Generate power reports
    puts "Generating power reports..."
    report_power > "$::REPORTS_DIR/synth_power.rpt"

    # Generate QoR report
    puts "Generating QoR report..."
    report_qor > "$::REPORTS_DIR/synth_qor.rpt"

    # Generate constraint reports
    puts "Generating constraint reports..."
    report_constraints > "$::REPORTS_DIR/synth_constraints.rpt"

    # Generate design summary
    puts "Generating design summary..."
    report_design -summary > "$::REPORTS_DIR/synth_design_summary.rpt"
    
    # ┌─────────────────────────────────────────────────────────────────────────┐
    # │                     PER-CORNER MMMC REPORTING                         │
    # └─────────────────────────────────────────────────────────────────────────┘

    global analysis_views
    if {[info exists analysis_views]} {
        puts "Generating per-corner MMMC reports..."
        file mkdir "$::REPORTS_DIR/mmmc"

        foreach scenario [lsort [array names analysis_views]] {
            array set view_info $analysis_views($scenario)

            puts "  Reporting for scenario: $scenario (corner=$view_info(corner))"

            # Per-corner timing report
            report_timing -format {instance cell arc delay slew load} \
                > "$::REPORTS_DIR/mmmc/timing_${scenario}.rpt"

            # Per-corner power report
            report_power > "$::REPORTS_DIR/mmmc/power_${scenario}.rpt"

            # Per-corner area report
            report_area > "$::REPORTS_DIR/mmmc/area_${scenario}.rpt"

            handle_info "  Corner $scenario reports generated"
            array unset view_info
        }

        # Generate MMMC synthesis summary
        set mmmc_summary "$::REPORTS_DIR/mmmc/synthesis_mmmc_summary.rpt"
        set fh [open $mmmc_summary "w"]
        puts $fh "═══════════════════════════════════════════════════════════════"
        puts $fh "CBFlow MMMC Synthesis Summary - Genus"
        puts $fh "═══════════════════════════════════════════════════════════════"
        puts $fh "Generated: [clock format [clock seconds]]"
        puts $fh "Scenarios: [llength [array names analysis_views]]"
        puts $fh ""
        puts $fh [format "%-40s %-10s %-10s %-10s" "Scenario" "Corner" "Voltage" "Temp"]
        puts $fh [string repeat "-" 80]
        foreach scenario [lsort [array names analysis_views]] {
            array set view_info $analysis_views($scenario)
            puts $fh [format "%-40s %-10s %-10s %-10s" \
                $scenario $view_info(corner) "$view_info(voltage)V" "$view_info(temperature)C"]
            array unset view_info
        }
        puts $fh [string repeat "-" 80]
        puts $fh ""
        puts $fh "Per-corner reports in: $::REPORTS_DIR/mmmc/"
        close $fh
        handle_info "MMMC synthesis summary: $mmmc_summary"
    }

    puts " Reports generated successfully"
    puts " Check reports in: reports/synthesis/"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                            SAVE OUTPUTS                                    │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc save_outputs {
    puts " Saving outputs..."
    
    # Create output directories
    file mkdir "$::OUTPUTS_DIR/netlist"
    file mkdir "$::OUTPUTS_DIR/sdc"
    
    # Save in different formats
    if {![info exists genus(output,save_ddc)] || $genus(output,save_ddc) eq "true"} {
        puts "Saving design database..."
        write_design -basename "$::OUTPUTS_DIR/synthesize"
    }
    
    if {![info exists genus(output,save_verilog)] || $genus(output,save_verilog) eq "true"} {
        puts "Saving Verilog netlist..."
        write_hdl > "$::OUTPUTS_DIR/netlist/synth.v"
    }
    
    if {[info exists genus(output,save_sdf)] && $genus(output,save_sdf) eq "true"} {
        puts "Saving SDF..."
        write_sdf > "$::OUTPUTS_DIR/netlist/synth.sdf"
    }
    
    if {![info exists genus(output,save_constraints)] || $genus(output,save_constraints) eq "true"} {
        puts "Saving constraints..."
        write_sdc > "$::OUTPUTS_DIR/sdc/synth.sdc"
    }
    
    # Generate Conformal scripts
    if {[info exists genus(output,save_svf)] && $genus(output,save_svf) eq "true"} {
        puts "Saving formal verification scripts..."
        file mkdir "$::OUTPUTS_DIR/fv_scripts"
        write_design_verification_files -dir "$::OUTPUTS_DIR/fv_scripts"
    }
    
    # Create output summary
    set summary_file "$::OUTPUTS_DIR/synthesis_summary.txt"
    set fp [open $summary_file w]
    puts $fp "═══════════════════════════════════════════════════════════════════════════════"
    puts $fp "OMNI FLOW - Synthesis Output Summary"
    puts $fp "═══════════════════════════════════════════════════════════════════════════════"
    puts $fp "Generated: [clock format [clock seconds]]"
    if {[info exists project(top_module)]} { puts $fp "Design: $project(top_module)" }
    if {[info exists tech(node)]} { puts $fp "Technology: $tech(node)" }
    if {[info exists project(name)]} { puts $fp "Project: $project(name)" }
    puts $fp ""
    puts $fp "Output Files:"
    puts $fp "  • results/netlist/synth.v"
    puts $fp "  • results/sdc/synth.sdc"
    puts $fp "  • work/SYNTH/synthesize.g"
    puts $fp ""
    puts $fp "Reports:"
    puts $fp "  • reports/synthesis/synth_qor.rpt"
    puts $fp "  • reports/synthesis/synth_timing.rpt"
    puts $fp "  • reports/synthesis/synth_area.rpt"
    puts $fp "  • reports/synthesis/synth_power.rpt"
    puts $fp ""
    puts $fp "Command Summary:"
    if {[info exists tech(lib,timing)]} {
        set lib_count [llength [expr {[string match "*{*}*" $tech(lib,timing)] ? $tech(lib,timing) : [list $tech(lib,timing)]}]]
        puts $fp "  Libraries: $lib_count timing libs loaded"
    }
    if {[info exists tech(lef,standard_cells)]} {
        puts $fp "  Physical: LEF files loaded"
    }
    puts $fp "  RTL Format: $synth(input,format)"
    if {[info exists genus(common,strategy)]} {
        puts $fp "  Strategy: $genus(common,strategy)"
    }
    close $fp
    
    puts " Outputs saved successfully"
    puts " Summary: $summary_file"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                         ENHANCED VALIDATION INTEGRATION                    │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc validate_synthesis_results {
    global synth project tech flow FLOW_DIR RUN_DIR ROOT_DIR

    handle_info "Running enhanced validation for synthesis stage..."

    # Determine current working directory and flow directory
    set current_dir $::env(CBFLOW_RUN_DIR)
    set validation_flow_dir ""

    if {[info exists FLOW_DIR]} {
        set validation_flow_dir $FLOW_DIR
    } elseif {[info exists ::env(FLOW_DIR)]} {
        set validation_flow_dir $::env(FLOW_DIR)
    } else {
        # Try to determine flow directory from current location
        set script_dir [file dirname [file normalize [info script]]]
        set validation_flow_dir [file dirname [file dirname [file dirname [file dirname $script_dir]]]]
    }

    # Enhanced validation script path
    set enhanced_validation_script "$validation_flow_dir/utils/validation/v1.0.0/enhanced_validate_run.tcl"

    if {![file exists $enhanced_validation_script]} {
        handle_warning "Enhanced validation script not found: $enhanced_validation_script"
        handle_info "Falling back to basic validation if available..."

        # Try basic validation
        set basic_validation_script "$validation_flow_dir/utils/validation/v1.0.0/validate_run.tcl"
        if {[file exists $basic_validation_script]} {
            handle_info "Running basic validation for synthesis..."
            if {[catch {exec tclsh $basic_validation_script SYNTH synthesis $current_dir $validation_flow_dir} validation_result]} {
                handle_error "Basic validation failed: $validation_result"
                return 0
            } else {
                handle_info "Basic validation completed successfully"
                return 1
            }
        } else {
            handle_warning "No validation script available, skipping validation"
            return 1
        }
    }

    # Run enhanced validation
    handle_info "Executing enhanced validation with critical error detection..."
    handle_info "Command: tclsh $enhanced_validation_script SYNTH synthesis $current_dir $validation_flow_dir"

    if {[catch {exec tclsh $enhanced_validation_script SYNTH synthesis $current_dir $validation_flow_dir} validation_result]} {
        handle_error "Enhanced validation failed with critical errors detected"
        handle_info "Validation output: $validation_result"

        # Check if this is a critical error failure (exit code 1) vs other errors
        if {[string match "*critical*error*" [string tolower $validation_result]] ||
            [string match "*xterm*" [string tolower $validation_result]]} {
            handle_error "Critical errors detected in synthesis logs - check xterm display"
        }
        return 0
    } else {
        handle_info "Enhanced validation completed successfully"
        handle_info "Validation output: $validation_result"
        return 1
    }
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                            EXECUTION CONTROL                               │
# └─────────────────────────────────────────────────────────────────────────────┘

handle_info "═══════════════════════════════════════════════════════════════════════════════"
handle_info " CBFlow Synthesis with flow_proc Integration"
handle_info "═══════════════════════════════════════════════════════════════════════════════"
puts "Starting synthesis flow sequence with proper flow_proc hooks..."

# Define the synthesis flow sequence
flow_proc synthesis_flow {
    handle_info "Executing complete synthesis flow..."

    # Execute synthesis procedures in sequence using flow_proc framework
    flow_exec setup_libraries
    flow_exec read_rtl_files
    flow_exec read_constraints
    flow_exec elaborate_design
    flow_exec synthesize_design
    flow_exec optimize_design
    flow_exec generate_reports
    flow_exec save_outputs

    # Enhanced validation with critical error detection
    flow_exec validate_synthesis_results

    # Flow completion summary
    handle_info "═══════════════════════════════════════════════════════════════════════════════"
    handle_info " Synthesis Flow Complete!"
    handle_info "═══════════════════════════════════════════════════════════════════════════════"
    puts "Final netlist: results/netlist/synth.v"
    puts "Final constraints: results/sdc/synth.sdc"
    puts "Check reports in: reports/synthesis/"
    handle_info "Synthesis flow completed successfully"
}

# Check if being run directly or sourced
if {[info exists argv0] && $argv0 eq [info script]} {
    # Running directly - execute the synthesis flow
    puts "Direct execution mode - running complete synthesis flow with flow_proc integration"
    flow_exec synthesis_flow
} else {
    # Being sourced - procedures are available for interactive use
    puts " CBFlow Synthesis procedures loaded and ready with flow_proc integration"
    puts "Available flow_proc procedures: setup_libraries, read_rtl_files, read_constraints, elaborate_design, synthesize_design, optimize_design, generate_reports, save_outputs, validate_synthesis_results, synthesis_flow"
    puts "Simply call procedure names directly (e.g., 'setup_libraries', 'synthesis_flow')"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                         FLOW_PROC INTEGRATION NOTES                        │
# └─────────────────────────────────────────────────────────────────────────────┘

# CBFlow flow_proc Integration:
# - All procedures are now defined using flow_proc with proper prepend/append hooks
# - Status tracking and stage management is handled automatically by flow_proc framework
# - Procedures can be called directly by name (setup_libraries, read_rtl_files, etc.)
# - Manual wrapper functions are no longer needed
# - Override capabilities available through setup.tcl flow_proc hooks

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                         CONVENIENCE FUNCTIONS                              │
# └─────────────────────────────────────────────────────────────────────────────┘

proc run_synthesis_subset {stage_list} {
    # Run a subset of synthesis stages using flow_proc integration
    puts " Running synthesis subset: [join $stage_list {, }]"

    foreach stage $stage_list {
        switch $stage {
            "setup_libraries" { setup_libraries }
            "read_rtl_files" { read_rtl_files }
            "read_constraints" { read_constraints }
            "elaborate_design" { elaborate_design }
            "synthesize_design" { synthesize_design }
            "optimize_design" { optimize_design }
            "generate_reports" { generate_reports }
            "save_outputs" { save_outputs }
            "validate_synthesis_results" { validate_synthesis_results }
            "synthesis_flow" { synthesis_flow }
            default {
                puts "Unknown stage: $stage"
                puts "Valid stages: setup_libraries, read_rtl_files, read_constraints, elaborate_design, synthesize_design, optimize_design, generate_reports, save_outputs, validate_synthesis_results, synthesis_flow"
            }
        }
    }
}

# Display completion message
puts " CBFlow Synthesis command file loaded successfully with flow_proc integration"

if {[info exists argv0] && $argv0 ne [info script]} {
    puts " Interactive mode available:"
    puts "  • synthesis_flow                   - Run complete synthesis flow with enhanced validation"
    puts "  • run_synthesis_subset {stages}    - Run specific stages"
    puts "  • <stage_name>                     - Run individual stage directly"
    puts "  Available stages: setup_libraries, read_rtl_files, read_constraints, elaborate_design, synthesize_design, optimize_design, generate_reports, save_outputs, validate_synthesis_results"
    puts ""
}

# Exit tool after stage completion
exit
