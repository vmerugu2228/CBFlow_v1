#!/usr/bin/env tclsh
# SYNTH release_data - Cadence Genus

# -- Bootstrap -----------------------------------------------------------------
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "SYNTH"
set STAGE_NAME "release_data"
set NODE_NAME "release_data1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME


# Source release utilities for ::CBFlow::Release namespace
set _ru "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/release_utils.tcl"
if {[file exists $_ru]} { source $_ru }
# Source release utilities
set release_utils "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/release_utils.tcl"

if {[file exists $release_utils]} { source $release_utils }

# Source release_config for phase/milestone file expectations
set release_config "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/release_config.tcl"
if {[file exists $release_config]} { source $release_config }

global synth project tech flow
handle_info "Starting SYNTH release_data with Cadence Genus..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

# ── Directories ──────────────────────────────────────────────────────────────
set WORK_DIR "$run_dir/work/SYNTH/release_data1"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

# ==============================================================================
# flow_proc: init_release
# Initialize release and validate mandatory variables
# ==============================================================================
flow_proc init_release {
    handle_info "Initializing release..."
    global synth project flow

    set run_dir $::env(CBFLOW_RUN_DIR)

    # ── Validate mandatory variables ─────────────────────────────────────────
    set missing_vars {}
    if {![info exists synth(common,design_name)] && ![info exists flow(design_name)]} {
        lappend missing_vars "design_name (synth(common,design_name) or flow(design_name))"
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

    set design_name [expr {[info exists synth(common,design_name)] ? $synth(common,design_name) : [expr {[info exists flow(design_name)] ? $flow(design_name) : "synth"}]}]

    # ── Determine release phase ──────────────────────────────────────────────
    set release_phase "P0"
    if {[info exists project(release_phase)]} { set release_phase $project(release_phase) }
    if {[info exists synth(common,release_phase)]} { set release_phase $synth(common,release_phase) }
    if {[info exists project(release,phase)] && $project(release,phase) ne ""} { set release_phase $project(release,phase) }

    # ── Initialize release using utilities ───────────────────────────────────
    if {[namespace exists ::CBFlow::Release]} {
        ::CBFlow::Release::init "SYNTH" $design_name $run_dir $release_phase
    } else {
        set ::release_dir "$run_dir/release/SYNTH"
        foreach subdir {reports data netlist db} {
            file mkdir "$::release_dir/$subdir"
        }
    }

    handle_info "Release phase: $release_phase"
    set _release_tag [expr {[info exists project(release,tag)] ? $project(release,tag) : "(unset)"}]
    handle_info "Release tag: $_release_tag"
}

# ==============================================================================
# flow_proc: release_data_database
# Release synthesis database for downstream flows
# ==============================================================================
flow_proc release_data_database {
    puts "INFO: Releasing synthesis database for downstream flows..."

    # Create release directory structure
    file mkdir "results/release"
    file mkdir "results/release/db"
    file mkdir "results/release/netlist"
    file mkdir "results/release/constraints"
    file mkdir "results/release/reports"

    # Copy database files to release area
    if {[file exists "results/db/synth.db"]} {
        file copy "results/db/synth.db" "results/release/db/"
        puts "INFO: Released database: results/release/db/synth.db"
    }

    # Copy netlist files to release area
    if {[file exists "results/netlist/chip_top.v"]} {
        file copy "results/netlist/chip_top.v" "results/release/netlist/"
        puts "INFO: Released netlist: results/release/netlist/chip_top.v"
    }

    # Copy constraint files to release area
    foreach sdc_file [glob -nocomplain "results/constraints/*.sdc"] {
        file copy $sdc_file "results/release/constraints/"
        puts "INFO: Released constraint: results/release/constraints/[file tail $sdc_file]"
    }

    # Copy reports to release area
    foreach rpt_file [glob -nocomplain "reports/*.rpt"] {
        file copy $rpt_file "results/release/reports/"
        puts "INFO: Released report: results/release/reports/[file tail $rpt_file]"
    }

    # Create release manifest
    set manifest_file "results/release/release_manifest.txt"
    set fp [open $manifest_file w]
    puts $fp "# CBFlow Synthesis Release Manifest"
    puts $fp "# Generated: [expr {[catch {clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}} _ts] ? "epoch [clock seconds]" : $_ts}]"
    puts $fp "# Flow: SYNTH"
    puts $fp "# Tool: Genus"
    puts $fp ""
    puts $fp "# Released Files:"
    foreach release_file [glob -nocomplain "results/release/*/*"] {
        puts $fp "  [file tail $release_file]"
    }
    close $fp
    puts "INFO: Created release manifest: $manifest_file"

    puts "INFO: Database release completed successfully"
}

# ==============================================================================
# flow_proc: verify_release_integrity
# Verify release integrity and validate against release_config
# ==============================================================================
flow_proc verify_release_integrity {
    puts "INFO: Verifying release integrity..."

    # Validate using release_config mandatory file lists
    if {[namespace exists ::CBFlow::Release]} {
        set valid [::CBFlow::Release::validate_mandatory_files]
        if {!$valid} {
            puts "WARNING: Some mandatory files are missing — check release phase requirements"
        }
    }

    set required_files {
        "results/release/db/synth.db"
        "results/release/netlist/chip_top.v"
    }

    set missing_files {}
    foreach file $required_files {
        if {![file exists $file]} {
            lappend missing_files $file
        }
    }

    if {[llength $missing_files] > 0} {
        puts "WARNING: Missing required release files:"
        foreach file $missing_files {
            puts "  - $file"
        }
        return false
    }

    puts "INFO: Release integrity verification passed"
    return true
}

# ==============================================================================
# flow_proc: generate_release_output
# Generate manifest, release notes, and completion stamp via release utilities
# ==============================================================================
flow_proc generate_release_output {
    handle_info "Generating release output..."
    global synth project

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

# Main release procedure
flow_proc release_data_main {
    puts "INFO: Starting synthesis database release process..."

    # Release database files
    release_data_database

    # Verify release
    if {[verify_release_integrity]} {
        puts "INFO: Synthesis database release completed successfully"
        return 0
    } else {
        puts "ERROR: Release verification failed"
        return 1
    }
}

# `release_data_main` above is registered via flow_proc (lives in
# ::flow::procs(...), NOT as a real Tcl proc). The legacy direct
# invocation `[release_data_main]` is therefore an undefined command.
# flow_exec_all runs all registered flow_procs in definition order — that
# includes release_data_main — so the legacy call is redundant. Removed.

flow_exec_all
exit
