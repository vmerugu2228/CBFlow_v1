#!/usr/bin/env tclsh
# CBFlow FCFP release_data - Synopsys Fusion Compiler
# Release floorplan deliverables -- DEF, netlist, SDC, reports, manifest
# Sources release_config.tcl for phase-wise mandatory file validation
# Generates: release directory, manifest, release notes, completion stamp
# Aligned with FC-RM Y-2026.03
set run_dir $::env(CBFLOW_RUN_DIR)
set env_file "$run_dir/.run.cbflow.tcl"
if {[file exists $env_file]} { source $env_file } else { puts stderr "ERROR: .run.cbflow.tcl not found"; exit 1 }
if {[info exists ::env(FLOW_DIR)]} { set FLOW_DIR $::env(FLOW_DIR) } else { puts stderr "ERROR: FLOW_DIR not set"; exit 1 }
if {![info exists ::env(UTILITIES_VERSION)] || $::env(UTILITIES_VERSION) eq ""} { puts stderr "ERROR: UTILITIES_VERSION not set"; exit 1 }
set utils_path "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} { source $utils_path } else { puts stderr "ERROR: Utils not found"; exit 1 }
namespace import ::CBFlow::Utilities::print_header
set config_file "$run_dir/work/$::env(CBFLOW_FLOW_TYPE)/$::env(CBFLOW_NODE_NAME)/run/config.tcl"
if {[file exists $config_file]} { source $config_file }
global fcfp project tech flow

# Source tech_config
if {[info exists ::env(TECH_NAME)] && $::env(TECH_NAME) ne "" &&
    [info exists ::env(TECH_VERSION)] && $::env(TECH_VERSION) ne ""} {
    set _tc "$::env(CONFIG_ROOT)/tech/$::env(TECH_NAME)/$::env(TECH_VERSION)/tech_config.tcl"
    if {[file exists $_tc]} { source -e $_tc }
}

# Source release utilities
set release_utils "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/release_utils.tcl"
if {[file exists $release_utils]} { source $release_utils }

# Source release_config for phase/milestone file expectations
set release_config "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/release_config.tcl"
if {[file exists $release_config]} { source $release_config }

# Source FC tool config
set _tool_config "[file dirname [info script]]/fc_config.tcl"
if {[file exists $_tool_config]} { source $_tool_config }
handle_info "Starting FCFP release_data..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

set WORK_DIR "$run_dir/work/FCFP/release_data1"
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
    global fcfp project flow

    set run_dir $::env(CBFLOW_RUN_DIR)

    # ── Validate mandatory variables ─────────────────────────────────────────
    set missing_vars {}
    if {![info exists fc(common,design_name)] && ![info exists flow(design_name)]} {
        lappend missing_vars "design_name (fc(common,design_name) or flow(design_name))"
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

    set design_name [expr {[info exists fc(common,design_name)] ? $fc(common,design_name) : [expr {[info exists flow(design_name)] ? $flow(design_name) : "fcfp"}]}]

    # ── Determine release phase ──────────────────────────────────────────────
    set release_phase "P0"
    if {[info exists project(release_phase)]} { set release_phase $project(release_phase) }
    if {[info exists fc(common,release_phase)]} { set release_phase $fc(common,release_phase) }
    if {[info exists project(release,phase)] && $project(release,phase) ne ""} { set release_phase $project(release,phase) }

    # ── Initialize release using utilities ───────────────────────────────────
    if {[namespace exists ::CBFlow::Release]} {
        ::CBFlow::Release::init "FCFP" $design_name $run_dir $release_phase
    } else {
        set ::release_dir "$run_dir/release/FCFP"
        foreach subdir {reports data def netlist sdc budgets} {
            file mkdir "$::release_dir/$subdir"
        }
    }

    handle_info "Release phase: $release_phase"
    handle_info "Release tag: $project(release,tag)"
}

# ==============================================================================
# flow_proc: prepare_release
# Stage FCFP deliverables into release directory
# ==============================================================================
flow_proc prepare_release {
    handle_info "Preparing FCFP release..."
    global fcfp project

    set run_dir $::env(CBFLOW_RUN_DIR)
    set rd "$run_dir/results/release"

    foreach d {"def" "def/partitions" "reports" "reports/fcfp" "netlist" "sdc" "budgets"} {
        file mkdir "$rd/$d"
    }

    # Release DEF files
    foreach def [glob -nocomplain "$run_dir/results/fcfp/def/*.def"] {
        catch {file copy -force $def "$rd/def/[file tail $def]"}
        handle_info "Released: [file tail $def]"
    }

    # Release partition DEFs
    foreach def [glob -nocomplain "$run_dir/results/fcfp/def/partitions/*.def"] {
        catch {file copy -force $def "$rd/def/partitions/[file tail $def]"}
    }

    # Release netlist
    if {[file exists "$run_dir/results/fcfp/fcfp_floorplan.v"]} {
        catch {file copy -force "$run_dir/results/fcfp/fcfp_floorplan.v" "$rd/netlist/"}
    }

    # Release SDC
    if {[file exists "$run_dir/results/fcfp/fcfp_floorplan.sdc"]} {
        catch {file copy -force "$run_dir/results/fcfp/fcfp_floorplan.sdc" "$rd/sdc/"}
    }

    # Release timing budgets
    foreach sdc [glob -nocomplain "$run_dir/results/fcfp/timing_budgets/*/*.sdc" "$run_dir/results/fcfp/timing_budgets/*.sdc"] {
        catch {file copy -force $sdc "$rd/budgets/[file tail $sdc]"}
    }

    # Release reports
    foreach subdir {"create_floorplan" "shaping" "placement" "create_power" "place_pins" "top_compile" "timing_budget"} {
        set src "$run_dir/results/fcfp/reports/$subdir"
        if {[file isdirectory $src]} {
            file mkdir "$rd/reports/fcfp/$subdir"
            foreach rpt [glob -nocomplain "$src/*.rpt"] {
                catch {file copy -force $rpt "$rd/reports/fcfp/$subdir/[file tail $rpt]"}
            }
        }
    }

    handle_info "FCFP release prepared"
}

# ==============================================================================
# flow_proc: validate_release
# Validate release deliverables are complete
# ==============================================================================
flow_proc validate_release {
    handle_info "Validating FCFP release..."

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

    if {![file exists "$rd/def/fcfp_floorplan.def"]} {
        handle_error "Missing floorplan DEF in release"
        incr errors
    }

    # Validate file sizes
    foreach f [glob -nocomplain "$rd/def/*.def"] {
        if {[file size $f] == 0} {
            handle_warning "Empty DEF file: [file tail $f]"
        }
    }

    set released_rpts [glob -nocomplain "$rd/reports/fcfp/*.rpt" "$rd/reports/fcfp/*/*.rpt"]
    handle_info "Released [llength $released_rpts] FCFP reports"

    if {$errors > 0} {
        handle_error "FCFP release validation failed with $errors errors"
        return -code error "Release validation failed"
    }

    handle_info "FCFP release validation passed"
}

# ==============================================================================
# flow_proc: generate_release_output
# Generate manifest, release notes, and completion stamp via release utilities
# ==============================================================================
flow_proc generate_release_output {
    handle_info "Generating release output..."
    global fcfp project

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
# Source setup.tcl and overrides before flow_exec_all
# ==============================================================================
set _setup_file "$run_dir/work/$::env(CBFLOW_FLOW_TYPE)/$::env(CBFLOW_NODE_NAME)/run/setup.tcl"
if {[file exists $_setup_file]} { handle_info "Sourcing setup hooks: $_setup_file"; source $_setup_file }
set _override_file "$run_dir/setup/override_setup.tcl"
if {[file exists $_override_file]} { handle_info "Sourcing user override: $_override_file"; source $_override_file }
set _stage_override "$run_dir/setup/override_setup.release_data.tcl"
if {[file exists $_stage_override]} { handle_info "Sourcing stage override: $_stage_override"; source $_stage_override }

flow_exec_all

# Exit tool after stage completion
exit
