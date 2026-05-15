#!/usr/bin/env tclsh
# ===============================================================================
# CBFlow EMIR release_data - Cadence Voltus
# Description: Package EMIR analysis results for release
# Sources release_config.tcl for phase-wise mandatory file validation
# Generates: release directory, manifest, release notes, completion stamp
# Deliverables: power/IR drop/thermal reports
# Tool: Cadence Voltus
# ===============================================================================

set run_dir $::env(CBFLOW_RUN_DIR)
set env_file "$run_dir/.run.cbflow.tcl"
if {[file exists $env_file]} { source $env_file } else { puts stderr "ERROR: .run.cbflow.tcl not found"; exit 1 }
if {[info exists ::env(FLOW_DIR)]} { set FLOW_DIR $::env(FLOW_DIR) } else { puts stderr "ERROR: FLOW_DIR not set"; exit 1 }
if {![info exists ::env(UTILITIES_VERSION)] || $::env(UTILITIES_VERSION) eq ""} { puts stderr "ERROR: UTILITIES_VERSION not set"; exit 1 }
set utils_path "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} { source $utils_path } else { puts stderr "ERROR: Utils not found"; exit 1 }
namespace import ::CBFlow::Utilities::print_header

set config_file "$run_dir/work/EMIR/release_data/run/config.tcl"
if {[file exists $config_file]} { source $config_file }
global emir project tech flow

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

# Source VOLTUS tool config
set _tool_config "[file dirname [info script]]/voltus_config.tcl"
if {[file exists $_tool_config]} { source $_tool_config }
handle_info "Starting EMIR release_data with Cadence Voltus..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

set WORK_DIR "$run_dir/work/EMIR/release_data"
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
    global emir project flow

    set run_dir $::env(CBFLOW_RUN_DIR)

    # ── Validate mandatory variables ─────────────────────────────────────────
    set missing_vars {}
    if {![info exists voltus(common,design_name)] && ![info exists flow(design_name)]} {
        lappend missing_vars "design_name (voltus(common,design_name) or flow(design_name))"
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

    set design_name [expr {[info exists voltus(common,design_name)] ? $voltus(common,design_name) : [expr {[info exists flow(design_name)] ? $flow(design_name) : "emir"}]}]

    # ── Determine release phase ──────────────────────────────────────────────
    set release_phase "P0"
    if {[info exists project(release_phase)]} { set release_phase $project(release_phase) }
    if {[info exists voltus(common,release_phase)]} { set release_phase $voltus(common,release_phase) }
    if {[info exists project(release,phase)] && $project(release,phase) ne ""} { set release_phase $project(release,phase) }

    # ── Initialize release using utilities ───────────────────────────────────
    if {[namespace exists ::CBFlow::Release]} {
        ::CBFlow::Release::init "EMIR" $design_name $run_dir $release_phase
    } else {
        set ::release_dir "$run_dir/release/EMIR"
        foreach subdir {reports data power ir_drop thermal} {
            file mkdir "$::release_dir/$subdir"
        }
    }

    handle_info "Release phase: $release_phase"
    handle_info "Release tag: $project(release,tag)"
}

# ==============================================================================
# flow_proc: prepare_release
# Copy EMIR deliverables (power, IR drop, thermal reports) to release directory
# ==============================================================================
flow_proc prepare_release {
    handle_info "Preparing EMIR release deliverables..."
    global emir project

    set run_dir $::env(CBFLOW_RUN_DIR)
    set release_dir "$run_dir/results/release"

    # Create release directory structure
    foreach d {"reports" "reports/power" "reports/ir_drop" "reports/thermal" "reports/em" "data"} {
        file mkdir "$release_dir/$d"
    }

    # ── Power analysis reports ───────────────────────────────────────────────
    set power_src "$run_dir/work/EMIR/power_analysis1/reports"
    if {[file isdirectory $power_src]} {
        foreach rpt [glob -nocomplain "$power_src/*.rpt"] {
            catch {file copy -force $rpt "$release_dir/reports/power/[file tail $rpt]"}
            handle_info "  Released power report: [file tail $rpt]"
        }
    }

    # Copy power summary
    set power_summary "$run_dir/results/emir/power_summary.rpt"
    if {[file exists $power_summary]} {
        catch {file copy -force $power_summary "$release_dir/reports/power/power_summary.rpt"}
    }

    # ── IR drop reports ──────────────────────────────────────────────────────
    set ir_src "$run_dir/work/EMIR/ir_drop1/reports"
    if {[file isdirectory $ir_src]} {
        foreach rpt [glob -nocomplain "$ir_src/*.rpt"] {
            catch {file copy -force $rpt "$release_dir/reports/ir_drop/[file tail $rpt]"}
            handle_info "  Released IR drop report: [file tail $rpt]"
        }
    }

    # Copy IR drop maps
    foreach map [glob -nocomplain "$run_dir/results/emir/ir_drop_map*"] {
        catch {file copy -force $map "$release_dir/data/[file tail $map]"}
        handle_info "  Released IR drop map: [file tail $map]"
    }

    # ── EM reports ───────────────────────────────────────────────────────────
    set em_summary "$run_dir/work/EMIR/ir_drop1/reports/em_summary.rpt"
    if {[file exists $em_summary]} {
        catch {file copy -force $em_summary "$release_dir/reports/em/em_summary.rpt"}
        handle_info "  Released EM summary"
    }

    # ── Thermal analysis reports ─────────────────────────────────────────────
    set thermal_src "$run_dir/work/EMIR/thermal_analysis1/reports"
    if {[file isdirectory $thermal_src]} {
        foreach rpt [glob -nocomplain "$thermal_src/*.rpt"] {
            catch {file copy -force $rpt "$release_dir/reports/thermal/[file tail $rpt]"}
            handle_info "  Released thermal report: [file tail $rpt]"
        }
    }

    # Copy thermal maps
    foreach map [glob -nocomplain "$run_dir/results/emir/thermal_map*"] {
        catch {file copy -force $map "$release_dir/data/[file tail $map]"}
    }

    handle_info "EMIR release preparation completed"
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

    # Basic sanity checks
    set run_dir $::env(CBFLOW_RUN_DIR)
    set release_dir "$run_dir/results/release"

    set power_rpts [glob -nocomplain "$release_dir/reports/power/*.rpt"]
    set ir_rpts [glob -nocomplain "$release_dir/reports/ir_drop/*.rpt"]
    set thermal_rpts [glob -nocomplain "$release_dir/reports/thermal/*.rpt"]

    handle_info "Released power reports: [llength $power_rpts]"
    handle_info "Released IR drop reports: [llength $ir_rpts]"
    handle_info "Released thermal reports: [llength $thermal_rpts]"

    if {[llength $power_rpts] == 0} {
        handle_warning "No power analysis reports in release"
    }

    handle_info "Release validation completed"
}

# ==============================================================================
# flow_proc: generate_release_output
# Generate manifest, release notes, and completion stamp via release utilities
# ==============================================================================
flow_proc generate_release_output {
    handle_info "Generating release output..."
    global emir project

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
