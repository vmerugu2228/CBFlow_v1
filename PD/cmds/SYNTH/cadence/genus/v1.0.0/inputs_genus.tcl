#!/usr/bin/env tclsh
# SYNTH Inputs Stage (Genus)

# -- Bootstrap -----------------------------------------------------------------
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "SYNTH"
set STAGE_NAME "inputs"
set NODE_NAME "inputs1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

handle_info "Starting SYNTH inputs stage with Genus..."
namespace eval ::flow {
    variable exec_mode "auto"
    variable start_time [clock seconds]
    variable flow_errors {}
}
# ── Directories ──────────────────────────────────────────────────────────────
# Source release utilities for input resolution
set _release_utils "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/release_utils.tcl"

if {[file exists $_release_utils]} { source $_release_utils }
set _release_config "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/release_config.tcl"
if {[file exists $_release_config]} { source $_release_config }

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                     RESOLVE INPUTS                                         │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc resolve_inputs {
    handle_info "Resolving input files..."
    global synth flow project flow_input_handshake

    set design_name [expr {[info exists synth(common,design_name)] ? $synth(common,design_name) : $flow(design_name)}]

    if {![namespace exists ::CBFlow::InputResolve]} {
        handle_info "Release input resolution not available — using direct paths only"
        return
    }

    # ── rtl: synth(input,rtl_release_tag) -> synth(input,rtl_filelist) ──────
    if {[info exists synth(input,rtl_release_tag)] && $synth(input,rtl_release_tag) ne ""} {
        set hs [get_input_handshake "SYNTH" "rtl"]
        if {[llength $hs] == 3} {
            set _file [::CBFlow::InputResolve::resolve synth "rtl" \
                [lindex $hs 0] [lindex $hs 1] \
                [regsub -all {\$\{design_name\}} [lindex $hs 2] $design_name]]
            set synth(input,rtl_filelist) $_file
            handle_info "  RTL filelist resolved: $_file"
        }
    }

    # ── sdc: synth(input,sdc_release_tag) -> synth(input,sdc) ──────────────
    if {[info exists synth(input,sdc_release_tag)] && $synth(input,sdc_release_tag) ne ""} {
        set hs [get_input_handshake "SYNTH" "sdc"]
        if {[llength $hs] == 3} {
            set _file [::CBFlow::InputResolve::resolve synth "sdc" \
                [lindex $hs 0] [lindex $hs 1] \
                [regsub -all {\$\{design_name\}} [lindex $hs 2] $design_name]]
            set synth(input,sdc) $_file
            handle_info "  SDC resolved: $_file"
        }
    }

    handle_info "Input resolution completed"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                     SOURCE MMMC CONFIGURATION                              │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc source_mmmc_config {
    global synth project tech flow
    handle_info "Loading MMMC configuration for synthesis..."

    # Source MMMC config file
    set mmmc_config_file "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/mmmc_config.tcl"
    if {[file exists $mmmc_config_file]} {
        source $mmmc_config_file
        handle_info "  MMMC config loaded: $mmmc_config_file"
    } else {
        handle_warning "MMMC config not found: $mmmc_config_file"
        handle_info "  Falling back to single-corner mode"
        return
    }

    # Get synthesis-relevant scenarios using node scenario query
    global analysis_views
    if {[info exists analysis_views]} {
        set scenario_count [llength [array names analysis_views]]
        handle_info "  Available MMMC scenarios: $scenario_count"
        foreach scenario [lsort [array names analysis_views]] {
            array set view_info $analysis_views($scenario)
            handle_info "    $scenario: corner=$view_info(corner) mode=$view_info(mode) voltage=$view_info(voltage)V temp=$view_info(temperature)C"
            array unset view_info
        }
    }

    puts " MMMC configuration loaded"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                     LOAD MULTI-CORNER LIBRARIES                            │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc load_multi_corner_libraries {
    global synth project tech flow analysis_views
    handle_info "Loading multi-corner libraries from MMMC scenarios..."

    set project_root [file dirname $::env(FLOW_DIR)]

    # Get all synthesis scenarios
    if {[info exists analysis_views]} {
        # Retrieve synthesis-relevant scenarios
        set synth_scenarios [lsort [array names analysis_views]]
        handle_info "  Loading libraries for [llength $synth_scenarios] scenarios"

        foreach scenario $synth_scenarios {
            array set view_info $analysis_views($scenario)

            handle_info "  Loading libraries for scenario: $scenario (corner: $view_info(corner))"

            # Load corner-specific timing libraries
            if {[info exists view_info(lib_set_ref)]} {
                set lib_ref $view_info(lib_set_ref)
                handle_info "    Library set reference: $lib_ref"
                # Libraries will be loaded via lib_sets defined in mmmc_config
            }

            array unset view_info
        }
    } else {
        handle_info "  No MMMC scenarios defined, using single-corner library loading"
    }

    # Fall back to standard tech(lib,timing) loading
    if {[info exists tech(lib,timing)]} {
        puts "  Loading Liberty files from tech config:"
        set lib_files [expr {[string match "*{*}*" $tech(lib,timing)] ? $tech(lib,timing) : [list $tech(lib,timing)]}]
        foreach lib $lib_files {
            set expanded_lib [subst $lib]
            set lib_path [file join $project_root $expanded_lib]
            if {[file exists $lib_path]} {
                puts "    $lib"
            } else {
                handle_warning "Liberty file not found: $lib_path"
            }
        }
    }

    puts " Multi-corner library loading completed"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                     GENERATE INPUTS                                        │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc generate_synth_inputs {
    handle_info "Linking SYNTH input files using generate_inputs.tcl..."
    log_stage_status "inputs" "RUNNING" "Linking SYNTH input files"

    set run_dir $::env(CBFLOW_RUN_DIR)

    # Call generate_inputs.tcl script directly
    set generate_script "$::env(FLOW_DIR)/utils/generate_inputs.tcl"
    if {![file exists $generate_script]} {
        handle_error "generate_inputs.tcl script not found: $generate_script"
    }

    handle_info "Executing: tclsh $generate_script SYNTH $run_dir $::env(FLOW_DIR)"

    if {[catch {exec tclsh $generate_script SYNTH $run_dir $::env(FLOW_DIR)} result]} {
        handle_error "Failed to link SYNTH inputs: $result"
    } else {
        handle_info "Generate inputs completed: $result"
    }

    handle_info "SYNTH inputs linking completed successfully"
    log_stage_status "inputs" "COMPLETE" "All SYNTH input files linked to work directory"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                     VALIDATE INPUTS                                        │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc validate_synth_inputs {
    global synth project tech flow
    handle_info "Validating SYNTH inputs..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    set errors 0

    # Validate RTL files
    set rtl_files [glob -nocomplain "$run_dir/work/SYNTH/inputs/rtl/*"]
    if {[llength $rtl_files] > 0} {
        puts "  RTL files: [llength $rtl_files]"
    } else {
        handle_warning "No RTL files found in work/SYNTH/inputs/rtl/"
        incr errors
    }

    # Validate SDC constraints
    set sdc_files [glob -nocomplain "$run_dir/work/SYNTH/inputs/constraints/*.sdc"]
    puts "  SDC files: [llength $sdc_files]"

    # Validate top module config
    if {![info exists project(top_module)]} {
        handle_warning "project(top_module) not defined"
        incr errors
    } else {
        puts "  Top module: $project(top_module)"
    }

    # Validate library config
    if {![info exists tech(lib,timing)]} {
        handle_warning "tech(lib,timing) not defined"
        incr errors
    }

    puts " Input validation completed ($errors warnings)"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                           EXECUTION CONTROL                                │
# └─────────────────────────────────────────────────────────────────────────────┘

handle_info "═══════════════════════════════════════════════════════════════"
handle_info " CBFlow SYNTH inputs with Genus (MMMC-enabled)"
handle_info "═══════════════════════════════════════════════════════════════"

flow_proc inputs_flow {
    handle_info "Executing SYNTH inputs flow..."
    flow_exec source_mmmc_config
    flow_exec load_multi_corner_libraries
    flow_exec generate_synth_inputs
    flow_exec validate_synth_inputs
    handle_info "SYNTH inputs stage completed successfully"
}

# Execute inputs generation
if {[info exists ::flow::exec_mode] && $::flow::exec_mode eq "auto"} {
    flow_exec inputs_flow
} else {
    handle_info "SYNTH inputs stage loaded - call 'inputs_flow' to execute"
}

# Exit tool after stage completion
exit
