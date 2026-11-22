#!/usr/bin/env tclsh
# ===============================================================================
# CBFlow - FCFP Release Data Command File (Innovus)
# Description: Prepare and validate release deliverables for fullchip
#              floorplanning data
# Sources release_config.tcl for phase-wise mandatory file validation
# Generates: release directory, manifest, release notes, completion stamp
# Tool: Cadence Innovus
# ===============================================================================

set run_dir $::env(CBFLOW_RUN_DIR)
set env_file "$run_dir/.run.cbflow.tcl"
if {[file exists $env_file]} { source $env_file } else { puts stderr "ERROR: .run.cbflow.tcl not found"; exit 1 }
if {[info exists ::env(FLOW_DIR)]} { set FLOW_DIR $::env(FLOW_DIR) } else { puts stderr "ERROR: FLOW_DIR not set"; exit 1 }
if {![info exists ::env(UTILITIES_VERSION)] || $::env(UTILITIES_VERSION) eq ""} { puts stderr "ERROR: UTILITIES_VERSION not set"; exit 1 }
set utils_path "$FLOW_DIR/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} { source $utils_path } else { puts stderr "ERROR: Utils not found"; exit 1 }
namespace import ::CBFlow::Utilities::print_header

set FLOW_TYPE "FCFP"
set STAGE_NAME "release_data"
set NODE_NAME [cbflow_node_name]

# Generated per-node config (project + tech + flow + node + user cascade).
set config_file "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
if {![file exists $config_file]} { puts stderr "ERROR: node config not found: $config_file (run the $NODE_NAME setup subnode)"; exit 1 }
source $config_file
global fcfp project tech flow
# Source user_config for overrides
if {[file exists "$run_dir/setup/user_config.tcl"]} { source "$run_dir/setup/user_config.tcl" }

# Release writer (::CBFlow::Release — the only release layout). Mandatory.
set release_utils "$FLOW_DIR/global/utils/utilities/$::env(UTILITIES_VERSION)/release_utils.tcl"
if {![file exists $release_utils]} { puts stderr "ERROR: release_utils.tcl not found: $release_utils"; exit 1 }
source $release_utils

# Source release_config for phase/milestone file expectations (mandatory)
set release_config "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/release_config.tcl"
if {![file exists $release_config]} { puts stderr "ERROR: release_config.tcl not found: $release_config"; exit 1 }
source $release_config

set WORK_DIR [cbflow_node_dir $NODE_NAME]
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

handle_info "Starting FCFP release_data stage with Innovus..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

# ==============================================================================
# flow_proc: init_release
# Initialize release and validate mandatory variables
# ==============================================================================
flow_proc init_release {
    handle_info "Initializing release..."
    global fcfp project flow

    set run_dir $::env(CBFLOW_RUN_DIR)

    # ── Validate mandatory variables ─────────────────────────────────────────
    set missing_vars {}
    set design_name ""
    if {[info exists fcfp(common,design_name)] && $fcfp(common,design_name) ne ""} {
        set design_name $fcfp(common,design_name)
    } elseif {[info exists flow(design_name)] && $flow(design_name) ne ""} {
        set design_name $flow(design_name)
    } else {
        lappend missing_vars "design_name (fcfp(common,design_name) or flow(design_name))"
    }
    if {![info exists ::env(FLOW_DIR)] || $::env(FLOW_DIR) eq ""} {
        lappend missing_vars "FLOW_DIR"
    }
    if {![info exists ::env(CONFIG_ROOT)] || $::env(CONFIG_ROOT) eq ""} {
        lappend missing_vars "CONFIG_ROOT"
    }

    if {[llength $missing_vars] > 0} {
        handle_error "Missing mandatory variables for release: [join $missing_vars {, }]"
        return
    }

    # ── Determine release phase ──────────────────────────────────────────────
    set release_phase ""   ;# from project(release,phase) below — no built-in phase
    if {[info exists project(release_phase)]} { set release_phase $project(release_phase) }
    if {[info exists fcfp(common,release_phase)] && $fcfp(common,release_phase) ne ""} { set release_phase $fcfp(common,release_phase) }
    if {[info exists project(release,phase)] && $project(release,phase) ne ""} { set release_phase $project(release,phase) }

    # ── Initialize release (<path>/<phase>/<block>/FCFP/<tag>) ───────────────
    set ::release_dir [::CBFlow::Release::init $::FLOW_TYPE $design_name $run_dir $release_phase]

    handle_info "Release phase: $::CBFlow::Release::release_phase"
    handle_info "Release tag: $::CBFlow::Release::release_tag"
}

# ==============================================================================
# flow_proc: prepare_release
# Copy FCFP deliverables (export_data results/fcfp/*) to the release directory
# ==============================================================================
flow_proc prepare_release {
    global fcfp project tech flow
    handle_info "Preparing FCFP release deliverables..."
    set run_dir $::env(CBFLOW_RUN_DIR)

    # Copy DEF files
    set _n [::CBFlow::Release::copy_glob "$run_dir/results/fcfp/def/*.def" def]
    handle_info "  Released DEF: $_n file(s)"

    # Copy design database
    set _n [::CBFlow::Release::copy_glob "$run_dir/results/fcfp/db/*" db]
    handle_info "  Released DB: $_n item(s)"

    # Copy netlist
    set _n [::CBFlow::Release::copy_glob "$run_dir/results/fcfp/netlist/*.v" netlist]
    handle_info "  Released netlist: $_n file(s)"

    # Copy SDC
    set _n [::CBFlow::Release::copy_glob "$run_dir/results/fcfp/sdc/*.sdc" sdc]
    handle_info "  Released SDC: $_n file(s)"

    # Copy reports (collected by export_data under results/fcfp/reports/)
    foreach rpt_dir {"floorplan" "powerplan" "post_floorplan"} {
        ::CBFlow::Release::copy_glob "$run_dir/results/fcfp/reports/$rpt_dir/*.rpt" "reports/$rpt_dir"
    }

    handle_info "  Release directory: $::release_dir"
    puts " Release preparation completed"
}

# ==============================================================================
# flow_proc: validate_release
# Validate FCFP release deliverables
# ==============================================================================
flow_proc validate_release {
    global fcfp project tech flow
    handle_info "Validating FCFP release deliverables..."
    set errors 0

    set release_base $::release_dir

    # Validate using release_config mandatory file lists
    set valid [::CBFlow::Release::validate_mandatory_files]
    if {!$valid} {
        handle_warning "Some mandatory files are missing — check release phase requirements"
    }

    # Validate DEF files
    set def_count [llength [glob -nocomplain "$release_base/def/*.def"]]
    if {$def_count == 0} {
        handle_warning "No DEF files in release"
        incr errors
    } else {
        puts "  DEF files: $def_count"
    }

    # Validate database
    set db_count [llength [glob -nocomplain "$release_base/db/*"]]
    if {$db_count == 0} {
        handle_warning "No database files in release"
        incr errors
    } else {
        puts "  Database files: $db_count"
    }

    # Validate netlist
    set netlist_count [llength [glob -nocomplain "$release_base/netlist/*"]]
    puts "  Netlist files: $netlist_count"

    # Validate SDC
    set sdc_count [llength [glob -nocomplain "$release_base/sdc/*"]]
    puts "  SDC files: $sdc_count"

    handle_info "  Validation completed ($errors warnings)"
}

# ==============================================================================
# flow_proc: generate_release_output
# Generate manifest, release notes, and completion stamp via release utilities
# ==============================================================================
flow_proc generate_release_output {
    handle_info "Generating release output..."
    global fcfp project

    set notes ""
    if {[info exists project(release_notes)]} { set notes $project(release_notes) }

    ::CBFlow::Release::generate_manifest
    ::CBFlow::Release::generate_release_notes $notes
    ::CBFlow::Release::stamp_complete
    ::CBFlow::Release::summary

    handle_info "Release output generated"
}

# ==============================================================================
# Execution control
# ==============================================================================
handle_info "==============================================================================="
handle_info " CBFlow FCFP release_data with Innovus"
handle_info "==============================================================================="

flow_exec_all

# Exit tool after stage completion
exit
