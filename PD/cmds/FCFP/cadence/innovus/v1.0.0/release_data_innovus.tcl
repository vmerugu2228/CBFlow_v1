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
set utils_path "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} { source $utils_path } else { puts stderr "ERROR: Utils not found"; exit 1 }
namespace import ::CBFlow::Utilities::print_header

set config_file "$run_dir/work/FCFP/release_data/run/config.tcl"
if {[file exists $config_file]} { source $config_file }
global fcfp project tech flow

# Source tech_config
if {[info exists ::env(TECH_NAME)] && $::env(TECH_NAME) ne "" && [info exists ::env(TECH_VERSION)]} {
    set _tc "$::env(CONFIG_ROOT)/tech/$::env(TECH_NAME)/$::env(TECH_VERSION)/tech_config.tcl"
    if {[file exists $_tc]} { source -e $_tc }
}
# Source user_config for overrides
if {[file exists "$run_dir/setup/user_config.tcl"]} { source -e "$run_dir/setup/user_config.tcl" }

# Source release utilities
set release_utils "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/release_utils.tcl"
if {[file exists $release_utils]} { source $release_utils }

# Source release_config for phase/milestone file expectations
set release_config "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/release_config.tcl"
if {[file exists $release_config]} { source $release_config }

set WORK_DIR "$run_dir/work/FCFP/release_data"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

# Source INNOVUS tool config
set _tool_config "[file dirname [info script]]/innovus_config.tcl"
if {[file exists $_tool_config]} { source $_tool_config }
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
    if {![info exists innovus(common,design_name)] && ![info exists flow(design_name)]} {
        lappend missing_vars "design_name (innovus(common,design_name) or flow(design_name))"
    }
    if {![info exists project(release,tag)] || $project(release,tag) eq ""} {
        lappend missing_vars "project(release,tag) in project_config.tcl"
    }
    if {![info exists ::env(FLOW_DIR)] || $::env(FLOW_DIR) eq ""} {
        lappend missing_vars "FLOW_DIR"
    }
    if {![info exists ::env(CONFIG_ROOT)] || $::env(CONFIG_ROOT) eq ""} {
        lappend missing_vars "CONFIG_ROOT"
    }

    if {[llength $missing_vars] > 0} {
        handle_warning "Missing mandatory variables for release:"
        foreach v $missing_vars { handle_warning "  - $v" }
        handle_warning "Release may be incomplete"
    }

    set design_name [expr {[info exists innovus(common,design_name)] ? $innovus(common,design_name) : [expr {[info exists flow(design_name)] ? $flow(design_name) : "fcfp"}]}]

    # ── Determine release phase ──────────────────────────────────────────────
    set release_phase "P0"
    if {[info exists project(release_phase)]} { set release_phase $project(release_phase) }
    if {[info exists innovus(common,release_phase)]} { set release_phase $innovus(common,release_phase) }
    if {[info exists project(release,phase)] && $project(release,phase) ne ""} { set release_phase $project(release,phase) }

    # ── Initialize release using utilities ───────────────────────────────────
    if {[namespace exists ::CBFlow::Release]} {
        ::CBFlow::Release::init "FCFP" $design_name $run_dir $release_phase
    } else {
        set ::release_dir "$run_dir/release/FCFP"
        foreach subdir {reports data def db netlist sdc} {
            file mkdir "$::release_dir/$subdir"
        }
    }

    handle_info "Release phase: $release_phase"
    handle_info "Release tag: $project(release,tag)"
}

# ==============================================================================
# flow_proc: prepare_release
# Copy FCFP deliverables to release directory
# ==============================================================================
flow_proc prepare_release {
    global fcfp project tech flow
    handle_info "Preparing FCFP release deliverables..."
    set run_dir $::env(CBFLOW_RUN_DIR)

    # Determine release directory
    if {[info exists innovus(common,release_dir)]} {
        set release_base $innovus(common,release_dir)
    } else {
        set release_base "$run_dir/release/fcfp"
    }

    # Create release directory structure
    foreach d {"def" "db" "netlist" "sdc" "reports" "reports/floorplan" "reports/powerplan" "reports/post_floorplan"} {
        file mkdir "$release_base/$d"
    }

    # Copy DEF files
    foreach def [glob -nocomplain "$run_dir/results/fcfp/def/*.def"] {
        file copy -force $def "$release_base/def/[file tail $def]"
        handle_info "  Released DEF: [file tail $def]"
    }

    # Copy design database
    foreach db [glob -nocomplain "$run_dir/results/fcfp/db/*"] {
        catch {file copy -force $db "$release_base/db/[file tail $db]"}
        handle_info "  Released DB: [file tail $db]"
    }

    # Copy netlist
    foreach netlist [glob -nocomplain "$run_dir/results/fcfp/netlist/*.v"] {
        file copy -force $netlist "$release_base/netlist/[file tail $netlist]"
        handle_info "  Released netlist: [file tail $netlist]"
    }

    # Copy SDC
    foreach sdc [glob -nocomplain "$run_dir/results/fcfp/sdc/*.sdc"] {
        file copy -force $sdc "$release_base/sdc/[file tail $sdc]"
        handle_info "  Released SDC: [file tail $sdc]"
    }

    # Copy reports
    foreach rpt_dir {"floorplan" "powerplan" "post_floorplan"} {
        set src "$run_dir/results/fcfp/reports/$rpt_dir"
        set dest "$release_base/reports/$rpt_dir"
        if {[file isdirectory $src]} {
            foreach rpt [glob -nocomplain "$src/*.rpt"] {
                file copy -force $rpt "$dest/[file tail $rpt]"
            }
        }
    }

    # Store release path for validation
    set ::release_dir $release_base

    handle_info "  Release directory: $release_base"
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
    if {[namespace exists ::CBFlow::Release]} {
        set valid [::CBFlow::Release::validate_mandatory_files]
        if {!$valid} {
            handle_warning "Some mandatory files are missing — check release phase requirements"
        }
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

    if {[namespace exists ::CBFlow::Release]} {
        ::CBFlow::Release::generate_manifest
        ::CBFlow::Release::generate_release_notes $notes
        ::CBFlow::Release::stamp_complete
        ::CBFlow::Release::summary
    } else {
        handle_info "Release utilities not loaded — skipping output generation"
    }

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
