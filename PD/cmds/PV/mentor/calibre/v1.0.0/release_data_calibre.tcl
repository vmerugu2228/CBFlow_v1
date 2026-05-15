#!/usr/bin/env tclsh
# ===============================================================================
# CBFlow - PV Release Data Command File
# Description: Package physical verification results for release
# Sources release_config.tcl for phase-wise mandatory file validation
# Generates: release directory, manifest, release notes, completion stamp
# Tool: Mentor Calibre
# ===============================================================================

set run_dir $::env(CBFLOW_RUN_DIR)
set env_file "$run_dir/.run.cbflow.tcl"
if {[file exists $env_file]} { source $env_file } else { puts stderr "ERROR: .run.cbflow.tcl not found"; exit 1 }
if {[info exists ::env(FLOW_DIR)]} { set FLOW_DIR $::env(FLOW_DIR) } else { puts stderr "ERROR: FLOW_DIR not set"; exit 1 }
if {![info exists ::env(UTILITIES_VERSION)] || $::env(UTILITIES_VERSION) eq ""} { puts stderr "ERROR: UTILITIES_VERSION not set"; exit 1 }
set utils_path "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} { source $utils_path } else { puts stderr "ERROR: Utils not found"; exit 1 }
namespace import ::CBFlow::Utilities::print_header

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

global phyv project tech flow
# Source CALIBRE tool config
set _tool_config "[file dirname [info script]]/calibre_config.tcl"
if {[file exists $_tool_config]} { source $_tool_config }
handle_info "Starting PV release data stage..."
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
    global phyv project flow

    set run_dir $::env(CBFLOW_RUN_DIR)

    # ── Validate mandatory variables ─────────────────────────────────────────
    set missing_vars {}
    if {![info exists phyv(design_name)] && ![info exists flow(design_name)]} {
        lappend missing_vars "design_name (phyv(design_name) or flow(design_name))"
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

    set design_name [expr {[info exists phyv(design_name)] ? $phyv(design_name) : [expr {[info exists flow(design_name)] ? $flow(design_name) : "pv"}]}]

    # ── Determine release phase ──────────────────────────────────────────────
    set release_phase "P0"
    if {[info exists project(release_phase)]} { set release_phase $project(release_phase) }
    if {[info exists phyv(release_phase)]} { set release_phase $phyv(release_phase) }
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

flow_proc prepare_release {
    handle_info "Preparing release directory..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    set release_dir "$run_dir/results/release"
    foreach dir {"reports" "drc" "lvs" "erc" "perc"} { file mkdir "$release_dir/$dir" }

    # Copy results
    foreach {src dest} {
        "results/drc/drc_results.rpt" "drc/drc_results.rpt"
        "results/lvs/lvs_results.rpt" "lvs/lvs_results.rpt"
        "results/erc/erc_results.rpt" "erc/erc_results.rpt"
        "results/perc/perc_results.rpt" "perc/perc_results.rpt"
        "results/phyv/phyv_summary.rpt" "reports/phyv_summary.rpt"
    } {
        if {[file exists "$run_dir/$src"]} {
            catch {file copy -force "$run_dir/$src" "$release_dir/$dest"}
            puts "  Copied: $src"
        }
    }
    puts " Release artifacts prepared"
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
    global phyv project tech

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
        set release_dir "$run_dir/results/release"
        set manifest "$release_dir/MANIFEST.txt"
        set fp [open $manifest w]
        puts $fp "==============================================================================="
        puts $fp "CBFlow PV - Release Manifest"
        puts $fp "==============================================================================="
        puts $fp "Generated: [clock format [clock seconds]]"
        puts $fp "Flow: PV (Physical Verification)"
        puts $fp "Tool: Mentor Calibre"
        if {[info exists project(top_module)]} { puts $fp "Design: $project(top_module)" }
        if {[info exists tech(node)]} { puts $fp "Technology: $tech(node)" }
        puts $fp "\nRelease Contents:"
        foreach f [glob -nocomplain "$release_dir/*/*" "$release_dir/*"] {
            if {[file isfile $f]} {
                set rel [string range $f [expr {[string length $release_dir] + 1}] end]
                puts $fp "  $rel ([file size $f] bytes)"
            }
        }
        close $fp
        puts " Manifest: $manifest"
    }

    handle_info "Release output generated"
}

flow_exec_all

# Exit tool after stage completion
exit
