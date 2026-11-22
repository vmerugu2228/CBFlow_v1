#!/usr/bin/env tclsh
# STA release_data - Cadence Tempus

# -- Bootstrap -----------------------------------------------------------------
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "STA"
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

global sta project tech flow
handle_info "Starting STA release_data with Cadence Tempus..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

set WORK_DIR "$run_dir/work/$FLOW_TYPE/$NODE_NAME"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

# Source active scenarios
set scenarios_file "$run_dir/work/STA/mmmc_setup/run/active_scenarios.tcl"
if {[file exists $scenarios_file]} {
    source $scenarios_file
} else {
    puts "INFO: active_scenarios.tcl not found ($scenarios_file) — proceeding"
    puts "      with no MMMC scenarios (downstream flow_procs no-op cleanly)."
    set mmmc_active_scenarios {}
}

# ==============================================================================
# flow_proc: setup_release_dirs
# Set up release directories and initialize release utilities
# ==============================================================================
flow_proc setup_release_dirs {
    handle_info "Setting up release directories..."
    global sta project flow

    set run_dir $::env(CBFLOW_RUN_DIR)

    # ── Validate mandatory variables (hard error — no partial releases) ──────
    set missing_vars {}
    set design_name ""
    if {[info exists sta(common,design_name)] && $sta(common,design_name) ne ""} {
        set design_name $sta(common,design_name)
    } elseif {[info exists flow(design_name)] && $flow(design_name) ne ""} {
        set design_name $flow(design_name)
    } else {
        lappend missing_vars "design_name (sta(common,design_name) or flow(design_name))"
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
    set release_phase ""   ;# from project(release,phase) below — no built-in phase
    if {[info exists project(release_phase)]} { set release_phase $project(release_phase) }
    if {[info exists sta(common,release_phase)]} { set release_phase $sta(common,release_phase) }
    if {[info exists project(release,phase)] && $project(release,phase) ne ""} { set release_phase $project(release,phase) }

    # ── Initialize release (single layout: <path>/<phase>/<block>/<FLOW>/<tag>) ─
    set release_base [::CBFlow::Release::init "STA" $design_name $run_dir $release_phase]

    handle_info "Release phase: $::CBFlow::Release::release_phase"
    handle_info "Release tag: $::CBFlow::Release::release_tag"

    file mkdir "$release_base/timing_reports"
    file mkdir "$release_base/summaries"
    file mkdir "$::WORK_DIR/run"
    file mkdir "$run_dir/logs/$::STAGE_NAME"

    # Store release path for other procs
    set ::release_dir $release_base
    puts " Release directories created at: $release_base"
}

flow_proc release_timing_reports {
    handle_info "Releasing timing reports..."
    global mmmc_active_scenarios
    set run_dir $::env(CBFLOW_RUN_DIR)
    set dest_dir "$::release_dir/timing_reports"

    # Copy per-scenario setup/hold reports (patterns: release_deliverables(STA,scenario_reports))
    foreach pattern [cbflow_require release_deliverables STA,scenario_reports] {
        foreach scenario $mmmc_active_scenarios {
            set rpt_name [format $pattern $scenario]
            set src_rpt "$run_dir/reports/sta/$rpt_name"
            if {[file exists $src_rpt]} {
                file copy -force $src_rpt "$dest_dir/$rpt_name"
                handle_info "  Released: $rpt_name"
            }
        }
    }
    puts " Per-scenario reports released"
}

flow_proc release_summaries {
    handle_info "Releasing summary reports..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    set dest_dir "$::release_dir/summaries"

    foreach summary [cbflow_require release_deliverables STA,summaries] {
        set src "$run_dir/reports/sta/$summary"
        if {[file exists $src]} {
            file copy -force $src "$dest_dir/$summary"
            handle_info "  Released: $summary"
        }
    }
    puts " Summary reports released"
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
    global sta project

    set notes ""
    if {[info exists project(release_notes)]} { set notes $project(release_notes) }

    ::CBFlow::Release::generate_manifest
    ::CBFlow::Release::generate_release_notes $notes
    ::CBFlow::Release::stamp_complete
    ::CBFlow::Release::summary

    handle_info "Release output generated"
}

flow_exec_all

# Exit tool after stage completion
exit
