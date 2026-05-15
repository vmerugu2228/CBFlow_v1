#!/usr/bin/env tclsh
# CBFlow PV release_data - Synopsys ICV | PV data release
# Sources release_config.tcl for phase-wise mandatory file validation
# Generates: release directory, manifest, release notes, completion stamp
set run_dir $::env(CBFLOW_RUN_DIR)
set env_file "$run_dir/.run.cbflow.tcl"
if {[file exists $env_file]} { source -e $env_file } else { puts stderr "ERROR: .run.cbflow.tcl not found"; exit 1 }
if {[info exists ::env(FLOW_DIR)]} { set FLOW_DIR $::env(FLOW_DIR) } else { puts stderr "ERROR: FLOW_DIR not set"; exit 1 }
if {![info exists ::env(UTILITIES_VERSION)] || $::env(UTILITIES_VERSION) eq ""} { puts stderr "ERROR: UTILITIES_VERSION not set"; exit 1 }
set utils_path "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} { source -e $utils_path } else { puts stderr "ERROR: Utils not found"; exit 1 }
namespace import ::CBFlow::Utilities::print_header
set config_file "$run_dir/work/PV/release_data/run/config.tcl"
if {[file exists $config_file]} { source -e $config_file }

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

global pv project tech flow
# Source ICV tool config
set _tool_config "[file dirname [info script]]/icv_config.tcl"
if {[file exists $_tool_config]} { source $_tool_config }
handle_info "Starting PV release_data with Synopsys ICV..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

set WORK_DIR "$run_dir/work/PV/release_data"
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
    global pv project flow

    set run_dir $::env(CBFLOW_RUN_DIR)

    # ── Validate mandatory variables ─────────────────────────────────────────
    set missing_vars {}
    if {![info exists icv(common,design_name)] && ![info exists flow(design_name)]} {
        lappend missing_vars "design_name (icv(common,design_name) or flow(design_name))"
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

    set design_name [expr {[info exists icv(common,design_name)] ? $icv(common,design_name) : [expr {[info exists flow(design_name)] ? $flow(design_name) : "pv"}]}]

    # ── Determine release phase ──────────────────────────────────────────────
    set release_phase "P0"
    if {[info exists project(release_phase)]} { set release_phase $project(release_phase) }
    if {[info exists icv(common,release_phase)]} { set release_phase $icv(common,release_phase) }
    if {[info exists project(release,phase)] && $project(release,phase) ne ""} { set release_phase $project(release,phase) }

    # ── Initialize release using utilities ───────────────────────────────────
    if {[namespace exists ::CBFlow::Release]} {
        ::CBFlow::Release::init "PV" $design_name $run_dir $release_phase
    } else {
        set ::release_dir "$run_dir/release/PV"
        foreach subdir {reports data drc lvs erc perc} {
            file mkdir "$::release_dir/$subdir"
        }
    }

    handle_info "Release phase: $release_phase"
    handle_info "Release tag: $project(release,tag)"
}

# --------------------------------------------------------------------------
# Procedure: prepare_release
#   Stages all PV deliverables for release
# --------------------------------------------------------------------------
flow_proc prepare_release {
    handle_info "Preparing PV data for release..."
    set run_dir $::env(CBFLOW_RUN_DIR)

    # Create release directory structure
    set release_dir "$run_dir/results/release/pv"
    foreach sub_dir {"drc" "lvs" "erc" "perc" "reports" "summary"} {
        file mkdir "$release_dir/$sub_dir"
    }

    # Copy DRC results
    set drc_files [glob -nocomplain "$run_dir/results/drc/*" "$run_dir/reports/pv/drc/*"]
    foreach f $drc_files {
        if {[file isfile $f]} {
            catch {file copy -force $f "$release_dir/drc/[file tail $f]"}
        }
    }
    handle_info "DRC results staged: [llength $drc_files] file(s)"

    # Copy LVS results
    set lvs_files [glob -nocomplain "$run_dir/results/lvs/*" "$run_dir/reports/pv/lvs/*"]
    foreach f $lvs_files {
        if {[file isfile $f]} {
            catch {file copy -force $f "$release_dir/lvs/[file tail $f]"}
        }
    }
    handle_info "LVS results staged: [llength $lvs_files] file(s)"

    # Copy ERC results
    set erc_files [glob -nocomplain "$run_dir/results/erc/*" "$run_dir/reports/pv/erc/*"]
    foreach f $erc_files {
        if {[file isfile $f]} {
            catch {file copy -force $f "$release_dir/erc/[file tail $f]"}
        }
    }
    handle_info "ERC results staged: [llength $erc_files] file(s)"

    # Copy PERC results
    set perc_files [glob -nocomplain "$run_dir/results/perc/*" "$run_dir/reports/pv/perc/*"]
    foreach f $perc_files {
        if {[file isfile $f]} {
            catch {file copy -force $f "$release_dir/perc/[file tail $f]"}
        }
    }
    handle_info "PERC results staged: [llength $perc_files] file(s)"

    # Copy merged summary
    if {[file exists "$run_dir/reports/pv/pv_merged_summary.rpt"]} {
        file copy -force "$run_dir/reports/pv/pv_merged_summary.rpt" "$release_dir/summary/"
    }
    if {[file exists "$run_dir/results/pv/pv_summary.rpt"]} {
        file copy -force "$run_dir/results/pv/pv_summary.rpt" "$release_dir/summary/"
    }

    handle_info "Release preparation completed"
}

# --------------------------------------------------------------------------
# Procedure: validate_release
#   Validates that all required release deliverables are present
# --------------------------------------------------------------------------
flow_proc validate_release {
    handle_info "Validating PV release data..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    set release_dir "$run_dir/results/release/pv"
    set errors {}

    # Validate using release_config mandatory file lists
    if {[namespace exists ::CBFlow::Release]} {
        set valid [::CBFlow::Release::validate_mandatory_files]
        if {!$valid} {
            handle_warning "Some mandatory files are missing — check release phase requirements"
        }
    }

    # Check required deliverables
    set required_files {
        "drc/drc_results.rpt"
        "lvs/lvs_results.rpt"
        "erc/erc_results.rpt"
        "perc/perc_results.rpt"
        "summary/pv_summary.rpt"
    }

    foreach req $required_files {
        if {![file exists "$release_dir/$req"]} {
            lappend errors "Missing release deliverable: $req"
        }
    }

    # Check that the overall PV summary indicates pass
    set summary_file "$release_dir/summary/pv_summary.rpt"
    if {[file exists $summary_file]} {
        set fp [open $summary_file r]
        set content [read $fp]
        close $fp
        if {[regexp {OVERALL_STATUS=(\S+)} $content -> status]} {
            if {$status ne "PASS"} {
                handle_warning "PV overall status is $status (not PASS)"
            }
        }
    }

    # Report validation
    if {[llength $errors] > 0} {
        foreach err $errors {
            handle_error "Release validation: $err"
        }
        handle_error "PV release validation FAILED with [llength $errors] error(s)"
    } else {
        handle_info "PV release validation PASSED - all deliverables present"
    }
}

# --------------------------------------------------------------------------
# flow_proc: generate_release_output
# Generate manifest, release notes, and completion stamp via release utilities
# --------------------------------------------------------------------------
flow_proc generate_release_output {
    handle_info "Generating release output..."
    global pv project

    set notes ""
    if {[info exists project(release_notes)]} { set notes $project(release_notes) }

    if {[namespace exists ::CBFlow::Release]} {
        ::CBFlow::Release::generate_manifest
        ::CBFlow::Release::generate_release_notes $notes
        ::CBFlow::Release::stamp_complete
        ::CBFlow::Release::summary
    } else {
        # Legacy manifest
        set run_dir $::env(CBFLOW_RUN_DIR)
        set release_dir "$run_dir/results/release/pv"
        set mfp [open "$release_dir/MANIFEST.txt" w]
        puts $mfp "# PV Release Manifest"
        puts $mfp "# Design:    [expr {[info exists ::project(design_name)] ? $::project(design_name) : \"unknown\"}]"
        puts $mfp "# Date:      [clock format [clock seconds]]"
        puts $mfp "# Tool:      Synopsys ICV"
        puts $mfp ""
        set all_release [glob -nocomplain "$release_dir/*/*"]
        foreach f $all_release {
            puts $mfp "[file tail [file dirname $f]]/[file tail $f]  ([file size $f] bytes)"
        }
        close $mfp
        handle_info "Release manifest written: $release_dir/MANIFEST.txt"
    }

    handle_info "Release output generated"
}

# --------------------------------------------------------------------------
# Top-level flow execution
# --------------------------------------------------------------------------
flow_exec_all
exit
