#!/usr/bin/env tclsh
# CLP release_data - Cadence Conformal LP

# -- Bootstrap -----------------------------------------------------------------
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "CLP"
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

# Source release_config for phase/milestone file expectations + report contracts
set release_config "$::env(CONFIG_ROOT)/flow/[cbflow_version FLOW_CONFIG_VERSION]/release_config.tcl"
if {![file exists $release_config]} { handle_error "release_config.tcl not found: $release_config" }
source $release_config

set WORK_DIR "$run_dir/work/$FLOW_TYPE/$NODE_NAME"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

# Declare global arrays
global clp project tech flow

handle_info "Starting CLP release data stage..."

# Initialize flow namespace
if {![namespace exists ::flow]} {
    namespace eval ::flow {
        variable exec_mode "auto"
        variable current_stage ""
        variable start_time [clock seconds]
        variable flow_errors {}
    }
}

set ::flow::exec_mode "auto"

# ==============================================================================
# flow_proc: init_release
# Initialize release and validate mandatory variables
# ==============================================================================
flow_proc init_release {
    handle_info "Initializing release..."
    global clp project flow

    set run_dir $::env(CBFLOW_RUN_DIR)

    # ── Validate mandatory variables (hard error — no partial releases) ──────
    set missing_vars {}
    set design_name ""
    if {[info exists clp(common,design_name)] && $clp(common,design_name) ne ""} {
        set design_name $clp(common,design_name)
    } elseif {[info exists flow(design_name)] && $flow(design_name) ne ""} {
        set design_name $flow(design_name)
    } else {
        lappend missing_vars "design_name (clp(common,design_name) or flow(design_name))"
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

    # ── Determine release phase ──────────────────────────────────────────────
    set release_phase [cbflow_run_phase]   ;# the run's phase
    if {[info exists project(release_phase)]} { set release_phase $project(release_phase) }
    if {[info exists clp(common,release_phase)]} { set release_phase $clp(common,release_phase) }

    # ── Initialize release (single layout: <path>/<phase>/<block>/<FLOW>/<tag>) ─
    set ::release_dir [::CBFlow::Release::init "CLP" $design_name $run_dir $release_phase]

    handle_info "Release phase: $::CBFlow::Release::release_phase"
    handle_info "Release tag: $::CBFlow::Release::release_tag"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                       PREPARE RELEASE DIRECTORY                            │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc prepare_release_directory {
    handle_info "Preparing release directory..."

    set release_dir $::release_dir

    # Create release directory structure
    foreach dir {
        "reports"
        "logs"
    } {
        file mkdir "$release_dir/$dir"
    }

    puts " Release directory prepared: $release_dir"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                       COPY RELEASE ARTIFACTS                               │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc copy_release_artifacts {
    global clp project tech flow
    handle_info "Copying release artifacts..."

    set run_dir $::env(CBFLOW_RUN_DIR)

    # Power verification summary — written by the clp stage to $OUTPUTS_DIR.
    set power_rpt "$::DIRS(outputs)/power_verification.rpt"
    if {[file exists $power_rpt]} {
        ::CBFlow::Release::copy_file $power_rpt reports clp_verification.rpt
        puts "  Copied: power_verification.rpt -> reports/clp_verification.rpt"
    }

    # Copy individual check reports of the upstream clp node
    set clp_rpt_dir "[cbflow_node_dir [cbflow_chain_node clp]]/reports"
    foreach rpt [glob -nocomplain "$clp_rpt_dir/*.rpt"] {
        if {[catch {::CBFlow::Release::copy_file $rpt reports [file tail $rpt]}]} {
            handle_warning "Could not copy: [file tail $rpt]"
        } else {
            puts "  Copied: [file tail $rpt]"
        }
    }

    puts " Release artifacts copied"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                       VERIFY RELEASE INTEGRITY                             │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc verify_release_integrity {
    global clp
    handle_info "Verifying release integrity..."

    set release_dir $::release_dir
    set all_ok true

    # Validate using release_config mandatory file lists
    set valid [::CBFlow::Release::validate_mandatory_files]
    if {!$valid} {
        handle_warning "Some mandatory files are missing — check release phase requirements"
    }

    # Check required release files (release_deliverables(CLP,required))
    set required_files [cbflow_require release_deliverables CLP,required]

    foreach rf $required_files {
        set full_path "$release_dir/$rf"
        if {[file exists $full_path]} {
            puts "  OK: $rf"
        } else {
            handle_warning "Missing release file: $rf"
            set all_ok false
        }
    }

    if {$all_ok} {
        handle_info "Release integrity verified - all required files present"
    } else {
        handle_warning "Release integrity check found missing files"
    }
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                       GENERATE RELEASE OUTPUT                              │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc generate_release_output {
    global clp project tech flow
    handle_info "Generating release output..."

    set notes ""
    if {[info exists project(release_notes)]} { set notes $project(release_notes) }

    ::CBFlow::Release::generate_manifest
    ::CBFlow::Release::generate_release_notes $notes
    ::CBFlow::Release::stamp_complete
    ::CBFlow::Release::summary

    handle_info "Release output generated"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                           EXECUTION CONTROL                                │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_exec_all

# Exit tool after stage completion
exit
