#!/usr/bin/env tclsh
# SYNTH release_data - Cadence Genus

# -- Bootstrap -----------------------------------------------------------------
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "SYNTH"
set STAGE_NAME "release_data"
set NODE_NAME [cbflow_node_name]

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME


# Source release utilities for ::CBFlow::Release namespace (mandatory — the
# release layout is defined only there).
set _ru "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/release_utils.tcl"
if {![file exists $_ru]} { handle_error "release_utils.tcl not found: $_ru" }
source $_ru

# Source release_config for phase/milestone file expectations + deliverables
set release_config "$::env(CONFIG_ROOT)/flow/[cbflow_version FLOW_CONFIG_VERSION]/release_config.tcl"
if {![file exists $release_config]} { handle_error "release_config.tcl not found: $release_config" }
source $release_config

global synth project tech flow
handle_info "Starting SYNTH release_data with Cadence Genus..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

# ── Directories ──────────────────────────────────────────────────────────────
set WORK_DIR "$run_dir/work/$FLOW_TYPE/$NODE_NAME"
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

    # ── Validate mandatory variables (hard error — no partial releases) ──────
    set missing_vars {}
    set design_name ""
    if {[info exists synth(common,design_name)] && $synth(common,design_name) ne ""} {
        set design_name $synth(common,design_name)
    } elseif {[info exists flow(design_name)] && $flow(design_name) ne ""} {
        set design_name $flow(design_name)
    } else {
        lappend missing_vars "design_name (synth(common,design_name) or flow(design_name))"
    }
    if {![info exists ::env(FLOW_DIR)] || $::env(FLOW_DIR) eq ""} {
        lappend missing_vars "FLOW_DIR"
    }
    if {![info exists ::env(CONFIG_ROOT)] || $::env(CONFIG_ROOT) eq ""} {
        lappend missing_vars "CONFIG_ROOT"
    }
    if {[llength $missing_vars] > 0} {
        handle_error "Missing mandatory variables for release: [join $missing_vars {, }]"
    }
    set ::release_design_name $design_name

    # ── Determine release phase ──────────────────────────────────────────────
    set release_phase ""   ;# from project(release,phase) below — no built-in phase
    if {[info exists project(release_phase)]} { set release_phase $project(release_phase) }
    if {[info exists synth(common,release_phase)]} { set release_phase $synth(common,release_phase) }
    if {[info exists project(release,phase)] && $project(release,phase) ne ""} { set release_phase $project(release,phase) }

    # ── Initialize release (single layout: <path>/<phase>/<block>/<FLOW>/<tag>) ─
    set ::release_dir [::CBFlow::Release::init "SYNTH" $design_name $run_dir $release_phase]

    handle_info "Release phase: $::CBFlow::Release::release_phase"
    handle_info "Release tag: $::CBFlow::Release::release_tag"
}

# ==============================================================================
# flow_proc: release_data_database
# Release synthesis outputs for downstream flows. File list comes from
# release_deliverables(SYNTH,genus_files) — {src (rel. to $OUTPUTS_DIR)
# dest_subdir dest_name}, %s = design name.
# ==============================================================================
flow_proc release_data_database {
    handle_info "Releasing synthesis outputs for downstream flows..."
    set _dn $::release_design_name

    foreach entry [cbflow_require release_deliverables SYNTH,genus_files] {
        lassign $entry _src _sub _dst
        set _src [string map [list %s $_dn] $_src]
        set _dst [string map [list %s $_dn] $_dst]
        if {[file exists "$::OUTPUTS_DIR/$_src"]} {
            ::CBFlow::Release::copy_file "$::OUTPUTS_DIR/$_src" $_sub $_dst
            handle_info "Released: $_sub/$_dst"
        }
    }

    # Reports of the upstream synthesis node
    set _rpt_dir "[cbflow_node_dir [cbflow_dep_node synthesis]]/reports"
    set _n [::CBFlow::Release::copy_glob "$_rpt_dir/*.rpt" reports]
    handle_info "Released $_n report(s) from $_rpt_dir"

    handle_info "Synthesis release completed"
}

# ==============================================================================
# flow_proc: verify_release_integrity
# Verify release integrity and validate against release_config
# ==============================================================================
flow_proc verify_release_integrity {
    handle_info "Verifying release integrity..."

    # Validate using release_config mandatory file lists
    set valid [::CBFlow::Release::validate_mandatory_files]
    if {!$valid} {
        handle_warning "Some mandatory files are missing — check release phase requirements"
    }

    set missing_files {}
    foreach f [cbflow_require release_deliverables SYNTH,genus_required] {
        set f [string map [list %s $::release_design_name] $f]
        if {![file exists "$::release_dir/$f"]} {
            lappend missing_files $f
        }
    }

    if {[llength $missing_files] > 0} {
        handle_warning "Missing required release files in $::release_dir: [join $missing_files {, }]"
        return false
    }

    handle_info "Release integrity verification passed"
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

    ::CBFlow::Release::generate_manifest
    ::CBFlow::Release::generate_release_notes $notes
    ::CBFlow::Release::stamp_complete
    ::CBFlow::Release::summary

    handle_info "Release output generated"
}

flow_exec_all
exit
