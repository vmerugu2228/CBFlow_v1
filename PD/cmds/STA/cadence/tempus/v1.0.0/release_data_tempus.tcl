#!/usr/bin/env tclsh
# STA release_data - Cadence Tempus

# -- Bootstrap -----------------------------------------------------------------
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "STA"
set STAGE_NAME "release_data"
set NODE_NAME "release_data1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

set release_utils "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/release_utils.tcl"
if {[file exists $release_utils]} { source $release_utils }

# Source release_config for phase/milestone file expectations
set release_config "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/release_config.tcl"
if {[file exists $release_config]} { source $release_config }

global sta project tech flow
# Note: tempus_config.tcl merged into STA_tempus_config.tcl (node_configs)
handle_info "Starting STA release_data with Cadence Tempus..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

set WORK_DIR "$run_dir/work/STA/release_data"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

# Source MMMC configuration
set mmmc_config_file "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/mmmc_config.tcl"
if {[file exists $mmmc_config_file]} {
    source $mmmc_config_file
    handle_info "MMMC configuration loaded: $mmmc_config_file"
} else {
    handle_warning "MMMC config not found: $mmmc_config_file"
}

# Source active scenarios
set scenarios_file "$run_dir/work/STA/mmmc_setup/run/active_scenarios.tcl"
if {[file exists $scenarios_file]} {
    source $scenarios_file
} else {
    puts stderr "ERROR: Active scenarios file not found: $scenarios_file"
    puts stderr "ERROR: Run mmmc_setup stage first"
    exit 1
}

# ==============================================================================
# flow_proc: setup_release_dirs
# Set up release directories and initialize release utilities
# ==============================================================================
flow_proc setup_release_dirs {
    handle_info "Setting up release directories..."
    global sta project flow

    set run_dir $::env(CBFLOW_RUN_DIR)

    # ── Validate mandatory variables ─────────────────────────────────────────
    set missing_vars {}
    if {![info exists sta(common,design_name)] && ![info exists flow(design_name)]} {
        lappend missing_vars "design_name (sta(common,design_name) or flow(design_name))"
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

    set design_name [expr {[info exists sta(common,design_name)] ? $sta(common,design_name) : [expr {[info exists flow(design_name)] ? $flow(design_name) : "sta"}]}]

    # ── Determine release phase ──────────────────────────────────────────────
    set release_phase "P0"
    if {[info exists project(release_phase)]} { set release_phase $project(release_phase) }
    if {[info exists sta(common,release_phase)]} { set release_phase $sta(common,release_phase) }
    if {[info exists project(release,phase)] && $project(release,phase) ne ""} { set release_phase $project(release,phase) }

    # ── Initialize release using utilities ───────────────────────────────────
    if {[namespace exists ::CBFlow::Release]} {
        ::CBFlow::Release::init "STA" $design_name $run_dir $release_phase
    } else {
        if {[info exists sta(common,release_dir)]} {
            set release_base $sta(common,release_dir)
        } else {
            set release_base "$run_dir/release/sta"
        }
        set ::release_dir $release_base
    }

    handle_info "Release phase: $release_phase"
    handle_info "Release tag: $project(release,tag)"

    # Determine release directory
    if {[info exists sta(common,release_dir)]} {
        set release_base $sta(common,release_dir)
    } else {
        set release_base "$run_dir/release/sta"
    }

    file mkdir "$release_base/timing_reports"
    file mkdir "$release_base/summaries"
    file mkdir "$run_dir/work/STA/release_data/run"
    file mkdir "$run_dir/logs/release_data"

    # Store release path for other procs
    set ::release_dir $release_base
    puts " Release directories created at: $release_base"
}

flow_proc release_timing_reports {
    handle_info "Releasing timing reports..."
    global mmmc_active_scenarios
    set run_dir $::env(CBFLOW_RUN_DIR)
    set dest_dir "$::release_dir/timing_reports"

    # Copy per-scenario setup reports
    foreach scenario $mmmc_active_scenarios {
        set setup_rpt "$run_dir/reports/sta/setup_timing_${scenario}.rpt"
        if {[file exists $setup_rpt]} {
            file copy -force $setup_rpt "$dest_dir/setup_timing_${scenario}.rpt"
            handle_info "  Released: setup_timing_${scenario}.rpt"
        }
    }

    # Copy per-scenario hold reports
    foreach scenario $mmmc_active_scenarios {
        set hold_rpt "$run_dir/reports/sta/hold_timing_${scenario}.rpt"
        if {[file exists $hold_rpt]} {
            file copy -force $hold_rpt "$dest_dir/hold_timing_${scenario}.rpt"
            handle_info "  Released: hold_timing_${scenario}.rpt"
        }
    }
    puts " Per-scenario reports released"
}

flow_proc release_summaries {
    handle_info "Releasing summary reports..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    set dest_dir "$::release_dir/summaries"

    foreach summary {"mmmc_setup_summary.rpt" "mmmc_hold_summary.rpt" "mmmc_timing_summary.rpt"} {
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

    if {[namespace exists ::CBFlow::Release]} {
        set valid [::CBFlow::Release::validate_mandatory_files]
        if {!$valid} {
            handle_warning "Some mandatory files are missing — check release phase requirements"
        }
    } else {
        handle_info "Release utilities not loaded — skipping validation"
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

    if {[namespace exists ::CBFlow::Release]} {
        ::CBFlow::Release::generate_manifest
        ::CBFlow::Release::generate_release_notes $notes
        ::CBFlow::Release::stamp_complete
        ::CBFlow::Release::summary
    } else {
        # Legacy manifest
        set manifest_file "$::release_dir/release_manifest.tcl"
        set fh [open $manifest_file "w"]
        puts $fh "#!/usr/bin/env tclsh"
        puts $fh "# CBFlow STA Release Manifest"
        puts $fh "# Generated: [clock format [clock seconds]]"
        puts $fh ""
        puts $fh "set release_info(tool)       \"Tempus\""
        puts $fh "set release_info(vendor)     \"Cadence\""
        puts $fh "set release_info(timestamp)  \"[clock format [clock seconds]]\""
        puts $fh "set release_info(scenario_set) \"$::mmmc_active_scenario_set\""
        puts $fh "set release_info(scenarios)  [list $::mmmc_active_scenarios]"
        puts $fh ""
        puts $fh "set release_files {}"
        foreach f [glob -nocomplain -directory "$::release_dir/timing_reports" *.rpt] {
            puts $fh "lappend release_files \"timing_reports/[file tail $f]\""
        }
        foreach f [glob -nocomplain -directory "$::release_dir/summaries" *.rpt] {
            puts $fh "lappend release_files \"summaries/[file tail $f]\""
        }
        close $fh
        handle_info "Release manifest written: $manifest_file"
    }

    handle_info "Release output generated"
}

flow_exec_all

# Exit tool after stage completion
exit
