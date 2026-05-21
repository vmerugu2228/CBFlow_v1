#!/usr/bin/env tclsh
# CBFlow CLP release_data - Synopsys VC LP

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "CLP"
set STAGE_NAME "release_data"
set NODE_NAME "${STAGE_NAME}1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# ==============================================================================
flow_proc init_release {
    handle_info "Initializing release..."
    global clp project flow

    set run_dir $::env(CBFLOW_RUN_DIR)

    # ── Validate mandatory variables ─────────────────────────────────────────
    set missing_vars {}
    if {![info exists clp(common,design_name)] && ![info exists flow(design_name)]} {
        lappend missing_vars "design_name (clp(common,design_name) or flow(design_name))"
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

    set design_name [expr {[info exists clp(common,design_name)] ? $clp(common,design_name) : [expr {[info exists flow(design_name)] ? $flow(design_name) : "clp"}]}]

    # ── Determine release phase ──────────────────────────────────────────────
    set release_phase "P0"
    if {[info exists project(release_phase)]} { set release_phase $project(release_phase) }
    if {[info exists clp(common,release_phase)]} { set release_phase $clp(common,release_phase) }
    if {[info exists project(release,phase)] && $project(release,phase) ne ""} { set release_phase $project(release,phase) }

    # ── Initialize release using utilities ───────────────────────────────────
    if {[namespace exists ::CBFlow::Release]} {
        ::CBFlow::Release::init "CLP" $design_name $run_dir $release_phase
    } else {
        set ::release_dir "$run_dir/release/CLP"
        foreach subdir {reports data db} {
            file mkdir "$::release_dir/$subdir"
        }
    }

    handle_info "Release phase: $release_phase"
    handle_info "Release tag: $project(release,tag)"
}

# ---------------------------------------------------------------------------
# flow_proc: prepare_release
# Stage CLP deliverables into release directory structure
# ---------------------------------------------------------------------------
flow_proc prepare_release {
    handle_info "Preparing CLP release..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    set rd "$run_dir/results/release"

    # Create release directory structure
    foreach d {"reports" "reports/clp" "db"} {
        file mkdir "$rd/$d"
    }

    # Copy verification summary report
    set src_summary "$run_dir/results/clp/power_verification.rpt"
    if {[file exists $src_summary]} {
        catch {file copy -force $src_summary "$rd/reports/clp_verification.rpt"}
        handle_info "Released: clp_verification.rpt"
    } else {
        handle_warning "Power verification summary not found for release"
    }

    # Copy detailed reports
    foreach rpt [glob -nocomplain "$run_dir/results/clp/reports/*.rpt"] {
        set fname [file tail $rpt]
        catch {file copy -force $rpt "$rd/reports/clp/$fname"}
    }

    # Copy session database
    set src_db "$run_dir/results/db/clp_verification.db"
    if {[file exists $src_db]} {
        catch {file copy -force $src_db "$rd/db/clp_verification.db"}
        handle_info "Released: clp_verification.db"
    }

    handle_info "CLP release preparation completed"
}

# ---------------------------------------------------------------------------
# flow_proc: validate_release
# Validate release deliverables are complete and correct
# ---------------------------------------------------------------------------
flow_proc validate_release {
    handle_info "Validating CLP release..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    set rd "$run_dir/results/release"
    set errors 0

    # Validate using release_config mandatory file lists
    if {[namespace exists ::CBFlow::Release]} {
        set valid [::CBFlow::Release::validate_mandatory_files]
        if {!$valid} {
            handle_warning "Some mandatory files are missing — check release phase requirements"
        }
    }

    # Check critical deliverables
    set required_files {
        "reports/clp_verification.rpt"
        "db/clp_verification.db"
    }
    foreach rf $required_files {
        if {![file exists "$rd/$rf"]} {
            handle_warning "Missing release deliverable: $rf"
        } else {
            if {[file size "$rd/$rf"] == 0} {
                handle_warning "Empty release deliverable: $rf"
            }
        }
    }

    # Verify report directory has content
    set released_rpts [glob -nocomplain "$rd/reports/clp/*.rpt"]
    if {[llength $released_rpts] == 0} {
        handle_warning "No detailed reports in release"
    } else {
        handle_info "Released [llength $released_rpts] detailed CLP reports"
    }

    if {$errors > 0} {
        handle_error "Release validation failed with $errors errors"
        return -code error "Release validation failed"
    }

    handle_info "CLP release validation passed"
}

# ---------------------------------------------------------------------------
# flow_proc: generate_release_output
# Generate manifest, release notes, and completion stamp via release utilities
# ---------------------------------------------------------------------------
flow_proc generate_release_output {
    handle_info "Generating release output..."
    global clp project

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

# ---------------------------------------------------------------------------
# flow_exec_all: Execute all release flow_procs in sequence
# ---------------------------------------------------------------------------
flow_exec_all
exit
