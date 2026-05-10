#!/usr/bin/env tclsh
# CBFlow POPT release_data - Synopsys Power Compiler | Release power optimization data
# Sources release_config.tcl for phase-wise mandatory file validation
# Generates: release directory, manifest, release notes, completion stamp
set run_dir $::env(CBFLOW_RUN_DIR)
if {[file exists "$run_dir/.run.cbflow.tcl"]} { source "$run_dir/.run.cbflow.tcl" } else { puts stderr "ERROR: .run.cbflow.tcl not found"; exit 1 }
if {[info exists ::env(FLOW_DIR)]} { set FLOW_DIR $::env(FLOW_DIR) } else { puts stderr "ERROR: FLOW_DIR not set"; exit 1 }
if {![info exists ::env(UTILITIES_VERSION)] || $::env(UTILITIES_VERSION) eq ""} { puts stderr "ERROR: UTILITIES_VERSION not set"; exit 1 }
set utils_path "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} { source $utils_path } else { puts stderr "ERROR: Utils not found"; exit 1 }
namespace import ::CBFlow::Utilities::print_header
set config_file "$run_dir/work/POPT/release_data/run/config.tcl"
if {[file exists $config_file]} { source $config_file }

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

global popt project tech flow
handle_info "Starting POPT release_data with Synopsys Power Compiler..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

set WORK_DIR "$run_dir/work/POPT/release_data"
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
    global popt project flow

    set run_dir $::env(CBFLOW_RUN_DIR)

    # ── Validate mandatory variables ─────────────────────────────────────────
    set missing_vars {}
    if {![info exists popt(design_name)] && ![info exists flow(design_name)]} {
        lappend missing_vars "design_name (popt(design_name) or flow(design_name))"
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

    set design_name [expr {[info exists popt(design_name)] ? $popt(design_name) : [expr {[info exists flow(design_name)] ? $flow(design_name) : "popt"}]}]

    # ── Determine release phase ──────────────────────────────────────────────
    set release_phase "P0"
    if {[info exists project(release_phase)]} { set release_phase $project(release_phase) }
    if {[info exists popt(release_phase)]} { set release_phase $popt(release_phase) }
    if {[info exists project(release,phase)] && $project(release,phase) ne ""} { set release_phase $project(release,phase) }

    # ── Initialize release using utilities ───────────────────────────────────
    if {[namespace exists ::CBFlow::Release]} {
        ::CBFlow::Release::init "POPT" $design_name $run_dir $release_phase
    } else {
        set ::release_dir "$run_dir/release/POPT"
        foreach subdir {reports data netlist db} {
            file mkdir "$::release_dir/$subdir"
        }
    }

    handle_info "Release phase: $release_phase"
    handle_info "Release tag: $project(release,tag)"
}

# ---------------------------------------------------------------------------
# flow_proc: prepare_release
# Stage Power Compiler deliverables into release directory
# ---------------------------------------------------------------------------
flow_proc prepare_release {
    handle_info "Preparing Power Compiler release..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    set rd "$run_dir/results/release"

    # Create release structure
    foreach d {"reports" "reports/popt" "reports/popt/power" "reports/popt/merge_timing" "reports/popt/post_merge" "netlist" "db"} {
        file mkdir "$rd/$d"
    }

    # Copy summary reports
    foreach {src dst} {
        "results/popt/pc_power_opt.rpt"           "reports/pc_power_opt.rpt"
        "results/popt/pc_merge_timing_summary.rpt" "reports/pc_merge_timing_summary.rpt"
        "results/popt/pc_post_merge_summary.rpt"   "reports/pc_post_merge_summary.rpt"
    } {
        if {[file exists "$run_dir/$src"]} {
            catch {file copy -force "$run_dir/$src" "$rd/$dst"}
            handle_info "Released: [file tail $dst]"
        }
    }

    # Copy detailed reports
    foreach subdir {"power" "merge_timing" "post_merge"} {
        foreach rpt [glob -nocomplain "$::REPORTS_DIR/"] {
            catch {file copy -force $rpt "$rd/reports/popt/$subdir/[file tail $rpt]"}
        }
    }

    # Export optimized netlist
    set opt_netlist "$run_dir/results/popt/pc_optimized.v"
    if {[file exists $opt_netlist]} {
        catch {file copy -force $opt_netlist "$rd/netlist/"}
    }

    # Save design database
    write_file -format ddc -hierarchy -output "$rd/db/pc_optimized.ddc"
    handle_info "Design database saved"

    handle_info "Power Compiler release prepared"
}

# ---------------------------------------------------------------------------
# flow_proc: validate
# Validate release deliverables are complete
# ---------------------------------------------------------------------------
flow_proc validate {
    handle_info "Validating Power Compiler release..."
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

    # Check manifest
    if {![file exists "$rd/pc_release_manifest.txt"]} {
        handle_error "Missing release manifest"
        incr errors
    }

    # Check critical files
    foreach rf {"reports/pc_power_opt.rpt" "db/pc_optimized.ddc"} {
        if {![file exists "$rd/$rf"]} {
            handle_warning "Missing deliverable: $rf"
        }
    }

    # Check report subdirectories
    foreach subdir {"power" "merge_timing" "post_merge"} {
        set rpts [glob -nocomplain "$rd/reports/popt/$subdir/*.rpt"]
        handle_info "Released [llength $rpts] reports in $subdir"
    }

    if {$errors > 0} {
        handle_error "Release validation failed with $errors errors"
        return -code error "Release validation failed"
    }

    handle_info "Power Compiler release validation passed"
}

# ---------------------------------------------------------------------------
# flow_proc: generate_release_output
# Generate manifest, release notes, and completion stamp via release utilities
# ---------------------------------------------------------------------------
flow_proc generate_release_output {
    handle_info "Generating release output..."
    global popt project

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
        set rd "$run_dir/results/release"
        set fp [open "$rd/pc_release_manifest.txt" w]
        puts $fp "Power Compiler Release Manifest - [clock format [clock seconds]]"
        puts $fp "======================================================="
        puts $fp "Flow:    POPT (Power Optimization)"
        puts $fp "Tool:    Synopsys Power Compiler"
        if {[info exists ::project(DESIGN_NAME)]} {
            puts $fp "Design:  $::project(DESIGN_NAME)"
        }
        puts $fp ""
        puts $fp "Deliverables:"
        foreach f [glob -nocomplain "$rd/reports/*.rpt" "$rd/reports/popt/*/*.rpt" "$rd/netlist/*" "$rd/db/*"] {
            puts $fp "  [string map [list $rd/ ""] $f]"
        }
        close $fp
    }

    handle_info "Release output generated"
}

# ---------------------------------------------------------------------------
# flow_exec_all: Execute all release flow_procs in sequence
# ---------------------------------------------------------------------------
flow_exec_all

# Exit tool after stage completion
exit
