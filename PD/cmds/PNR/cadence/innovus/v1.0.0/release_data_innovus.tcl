#!/usr/bin/env tclsh
# PNR release_data - Cadence Innovus

# -- Bootstrap -----------------------------------------------------------------
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "PNR"
set STAGE_NAME "release_data"
set NODE_NAME [cbflow_node_name]

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME


# Release writer (::CBFlow::Release) + release_config (deliverable contract).
set _ru "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/release_utils.tcl"
if {![file exists $_ru]} { error "release_utils.tcl not found: $_ru" }
source $_ru
set release_config "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/release_config.tcl"
if {![file exists $release_config]} { error "release_config.tcl not found: $release_config" }
source $release_config

handle_info "Starting PNR release_data stage with Innovus..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

# ==============================================================================
# flow_proc: init_release
# Initialize release and validate mandatory variables
# ==============================================================================
flow_proc init_release {
    handle_info "Initializing release..."
    global pnr project flow

    set run_dir $::env(CBFLOW_RUN_DIR)

    # ── Validate mandatory variables ─────────────────────────────────────────
    set missing_vars {}
    if {!([info exists pnr(common,design_name)] && $pnr(common,design_name) ne "") && \
        !([info exists flow(design_name)] && $flow(design_name) ne "")} {
        lappend missing_vars "design_name (pnr(common,design_name) or flow(design_name))"
    }
    if {![info exists project(release,phase)] || $project(release,phase) eq ""} {
        lappend missing_vars "project(release,phase) in the project config"
    }
    if {![info exists ::env(FLOW_DIR)] || $::env(FLOW_DIR) eq ""} {
        lappend missing_vars "FLOW_DIR"
    }
    if {![info exists ::env(CONFIG_ROOT)] || $::env(CONFIG_ROOT) eq ""} {
        lappend missing_vars "CONFIG_ROOT"
    }
    if {[llength $missing_vars] > 0} {
        foreach v $missing_vars { handle_warning "  missing: $v" }
        error "Missing mandatory variables for PNR release: [join $missing_vars {, }]"
    }

    set design_name [expr {[info exists pnr(common,design_name)] && $pnr(common,design_name) ne "" ? $pnr(common,design_name) : $flow(design_name)}]
    set release_phase $project(release,phase)

    ::CBFlow::Release::init "PNR" $design_name $run_dir $release_phase

    handle_info "Release phase: $release_phase"
    handle_info "Release tag: $::CBFlow::Release::release_tag"
}

# ==============================================================================
# flow_proc: prepare_release
# Copy PNR deliverables to the release directory. What is copied, from where
# and under which name is release_config.tcl release_deliverables(PNR,innovus_*)
# — the paths export_data_innovus.tcl / signoff_innovus.tcl actually write.
# ==============================================================================
flow_proc prepare_release {
    global pnr project flow release_deliverables
    handle_info "Preparing PNR release deliverables..."

    set design_name $::CBFlow::Release::design_name
    set top_module  [cbflow_require project top_module]
    set _map [list %t $top_module %d $design_name]

    # export_data outputs (run-dir relative): {category source release_name}
    foreach {cat src dst} [cbflow_require release_deliverables PNR,innovus_files] {
        set src [string map $_map $src]
        set dst [string map $_map $dst]
        if {[::CBFlow::Release::copy_file $src $cat $dst]} {
            handle_info "  Released $cat: $dst"
        }
    }

    # Per-scenario outputs (one file per MMMC scenario / RC corner the export
    # stage wrote): {category glob}
    foreach {cat pattern} [cbflow_require release_deliverables PNR,innovus_globs] {
        set n [::CBFlow::Release::copy_glob "$::CBFlow::Release::run_dir/[string map $_map $pattern]" $cat]
        handle_info "  Released $cat: $n file(s) from $pattern"
    }

    # Signoff reports from the upstream signoff node: {release_subdir report}
    set _rpt_dir "[cbflow_node_dir [cbflow_dep_node signoff]]/reports"
    foreach {sub rpt} [cbflow_require release_deliverables PNR,innovus_signoff_reports] {
        if {[::CBFlow::Release::copy_file "$_rpt_dir/$rpt" $sub $rpt]} {
            handle_info "  Released report: $sub/$rpt"
        }
    }

    handle_info "PNR release preparation completed"
}

# ==============================================================================
# flow_proc: validate_release
# Validate release against release_config mandatory file lists
# ==============================================================================
flow_proc validate_release {
    handle_info "Validating release completeness..."

    set valid [::CBFlow::Release::validate_mandatory_files]
    if {!$valid} {
        handle_warning "Some mandatory files are missing — check release phase requirements"
    }

    handle_info "Release validation completed"
}

# ==============================================================================
# flow_proc: generate_release_output
# Generate manifest, release notes, and completion stamp via release utilities
# ==============================================================================
flow_proc generate_release_output {
    handle_info "Generating release output..."
    global pnr project

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
flow_exec_all

# Exit tool after stage completion
exit
