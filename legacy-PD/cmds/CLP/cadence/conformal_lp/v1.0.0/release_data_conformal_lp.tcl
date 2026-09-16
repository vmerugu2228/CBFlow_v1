#!/usr/bin/env tclsh
# CLP release_data - Cadence Conformal LP

# -- Bootstrap -----------------------------------------------------------------
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "CLP"
set STAGE_NAME "release_data"
set NODE_NAME "release_data1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME


# Source release utilities for ::CBFlow::Release namespace
set _ru "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/release_utils.tcl"
if {[file exists $_ru]} { source $_ru }
set release_utils "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/release_utils.tcl"
if {[file exists $release_utils]} { source $release_utils }

# Source release_config for phase/milestone file expectations
set release_config "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/release_config.tcl"
if {[file exists $release_config]} { source $release_config }

set WORK_DIR "$run_dir/work/CLP/release_data1"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

# Declare global arrays
global clp project tech flow

# Note: conformal_lp_config.tcl merged into CLP_conformal_lp_config.tcl (node_configs)
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
        foreach subdir {reports data db logs} {
            file mkdir "$::release_dir/$subdir"
        }
    }

    handle_info "Release phase: $release_phase"
    set _release_tag [expr {[info exists project(release,tag)] ? $project(release,tag) : "(unset)"}]
    handle_info "Release tag: $_release_tag"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                       PREPARE RELEASE DIRECTORY                            │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc prepare_release_directory {
    handle_info "Preparing release directory..."

    set run_dir $::env(CBFLOW_RUN_DIR)
    set release_dir "$run_dir/results/release"

    # Create release directory structure
    foreach dir {
        "reports"
        "db"
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
    set release_dir "$run_dir/results/release"

    # Copy power verification report
    set power_rpt "$run_dir/results/clp/power_verification.rpt"
    if {[file exists $power_rpt]} {
        file copy -force $power_rpt "$release_dir/reports/clp_verification.rpt"
        puts "  Copied: power_verification.rpt -> reports/clp_verification.rpt"
    }

    # Copy database
    set db_file "$run_dir/results/db/clp_verification.db"
    if {[file exists $db_file]} {
        file copy -force $db_file "$release_dir/db/clp_verification.db"
        puts "  Copied: clp_verification.db -> db/clp_verification.db"
    }

    # Copy individual check reports
    foreach rpt [glob -nocomplain "$run_dir/work/CLP/clp1/reports/*.rpt"] {
        if {[catch {file copy -force $rpt "$release_dir/reports/[file tail $rpt]"}]} {
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

    set run_dir $::env(CBFLOW_RUN_DIR)
    set release_dir "$run_dir/results/release"
    set all_ok true

    # Validate using release_config mandatory file lists
    if {[namespace exists ::CBFlow::Release]} {
        set valid [::CBFlow::Release::validate_mandatory_files]
        if {!$valid} {
            handle_warning "Some mandatory files are missing — check release phase requirements"
        }
    }

    # Check required release files
    set required_files {
        "reports/clp_verification.rpt"
        "db/clp_verification.db"
    }

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

    if {[namespace exists ::CBFlow::Release]} {
        ::CBFlow::Release::generate_manifest
        ::CBFlow::Release::generate_release_notes $notes
        ::CBFlow::Release::stamp_complete
        ::CBFlow::Release::summary
    } else {
        # Legacy manifest
        set run_dir $::env(CBFLOW_RUN_DIR)
        set release_dir "$run_dir/results/release"
        set manifest_file "$release_dir/MANIFEST.txt"

        set fp [open $manifest_file w]
        puts $fp "==============================================================================="
        puts $fp "CBFlow CLP - Release Manifest"
        puts $fp "==============================================================================="
        puts $fp "Generated: [expr {[catch {clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}} _ts] ? "epoch [clock seconds]" : $_ts}]"
        puts $fp "Flow: CLP (Conformal Low Power)"
        puts $fp "Tool: Cadence Conformal LP"
        if {[info exists project(top_module)]} { puts $fp "Design: $project(top_module)" }
        if {[info exists project(name)]} { puts $fp "Project: $project(name)" }
        if {[info exists tech(node)]} { puts $fp "Technology: $tech(node)" }
        puts $fp ""
        puts $fp "Release Contents:"
        foreach f [glob -nocomplain "$release_dir/reports/*" "$release_dir/db/*" "$release_dir/logs/*"] {
            set rel_path [string range $f [expr {[string length $release_dir] + 1}] end]
            puts $fp "  $rel_path ([file size $f] bytes)"
        }
        close $fp
        puts " Release manifest: $manifest_file"
    }

    handle_info "Release output generated"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                           EXECUTION CONTROL                                │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_exec_all

# Exit tool after stage completion
exit
