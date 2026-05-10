#!/usr/bin/env tclsh
# ===============================================================================
# CBFlow - FP Release Data Command File (Innovus)
# Description: Prepare and validate release deliverables for floorplan data
# Sources release_config.tcl for phase-wise mandatory file validation
# Generates: release directory, manifest, release notes, completion stamp
# Tool: Cadence Innovus
# ===============================================================================

set run_dir $::env(CBFLOW_RUN_DIR)
set env_file "$run_dir/.run.cbflow.tcl"
if {[file exists $env_file]} { source $env_file } else { puts stderr "ERROR: .run.cbflow.tcl not found"; exit 1 }
if {[info exists ::env(FLOW_DIR)]} { set FLOW_DIR $::env(FLOW_DIR) } else { puts stderr "ERROR: FLOW_DIR not set"; exit 1 }
if {![info exists ::env(UTILITIES_VERSION)] || $::env(UTILITIES_VERSION) eq ""} { puts stderr "ERROR: UTILITIES_VERSION not set"; exit 1 }
set utils_path "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} { source $utils_path } else { puts stderr "ERROR: Utils not found"; exit 1 }
namespace import ::CBFlow::Utilities::print_header

set config_file "$run_dir/work/FP/release_data/run/config.tcl"
if {[file exists $config_file]} { source $config_file }
global fp project tech flow

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

set WORK_DIR "$run_dir/work/FP/release_data"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

handle_info "Starting FP release_data stage with Innovus..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

# ==============================================================================
# flow_proc: init_release
# Initialize release and validate mandatory variables
# ==============================================================================
flow_proc init_release {
    handle_info "Initializing release..."
    global fp project flow

    set run_dir $::env(CBFLOW_RUN_DIR)

    # ── Validate mandatory variables ─────────────────────────────────────────
    set missing_vars {}
    if {![info exists fp(design_name)] && ![info exists flow(design_name)]} {
        lappend missing_vars "design_name (fp(design_name) or flow(design_name))"
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

    set design_name [expr {[info exists fp(design_name)] ? $fp(design_name) : [expr {[info exists flow(design_name)] ? $flow(design_name) : "fp"}]}]

    # ── Determine release phase ──────────────────────────────────────────────
    set release_phase "P0"
    if {[info exists project(release_phase)]} { set release_phase $project(release_phase) }
    if {[info exists fp(release_phase)]} { set release_phase $fp(release_phase) }
    if {[info exists project(release,phase)] && $project(release,phase) ne ""} { set release_phase $project(release,phase) }

    # ── Initialize release using utilities ───────────────────────────────────
    if {[namespace exists ::CBFlow::Release]} {
        ::CBFlow::Release::init "FP" $design_name $run_dir $release_phase
    } else {
        set ::release_dir "$run_dir/release/FP"
        foreach subdir {reports data def db} {
            file mkdir "$::release_dir/$subdir"
        }
    }

    handle_info "Release phase: $release_phase"
    handle_info "Release tag: $project(release,tag)"
}

# ==============================================================================
# flow_proc: prepare_release
# Copy FP deliverables to release directory
# ==============================================================================
flow_proc prepare_release {
    global fp project tech flow
    handle_info "Preparing FP release deliverables..."
    set run_dir $::env(CBFLOW_RUN_DIR)

    # Create release directory structure
    set release_dir "$run_dir/results/release"
    foreach d {"def" "db" "reports" "reports/floorplan" "reports/powerplan" "reports/timing"} {
        file mkdir "$release_dir/$d"
    }

    # Determine design name
    set dname [expr {[info exists fp(design_name)] ? $fp(design_name) : "fp"}]

    # Copy DEF
    set def_src "$run_dir/results/fp/def/${dname}.def"
    if {[file exists $def_src]} {
        file copy -force $def_src "$release_dir/def/${dname}.def"
        handle_info "  Released DEF: ${dname}.def"
    } else {
        handle_warning "DEF not found: $def_src"
    }

    # Copy design database
    foreach db [glob -nocomplain "$run_dir/results/fp/db/*"] {
        catch {file copy -force $db "$release_dir/db/[file tail $db]"}
        handle_info "  Released DB: [file tail $db]"
    }

    # Copy reports
    foreach rpt_dir {"floorplan" "powerplan" "post_floorplan"} {
        set src "$run_dir/results/fp/reports/$rpt_dir"
        if {[file isdirectory $src]} {
            foreach rpt [glob -nocomplain "$src/*.rpt"] {
                set rpt_name [file tail $rpt]
                if {[string match "*timing*" $rpt_name] || [string match "*clock*" $rpt_name]} {
                    file copy -force $rpt "$release_dir/reports/timing/$rpt_name"
                } elseif {[string match "*pg*" $rpt_name] || [string match "*power*" $rpt_name]} {
                    file copy -force $rpt "$release_dir/reports/powerplan/$rpt_name"
                } else {
                    file copy -force $rpt "$release_dir/reports/floorplan/$rpt_name"
                }
            }
        }
    }

    handle_info "FP release preparation completed"
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
    global fp project

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

# ==============================================================================
# Execution control
# ==============================================================================
flow_exec_all

# Exit tool after stage completion
exit
