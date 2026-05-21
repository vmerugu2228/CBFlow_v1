#!/usr/bin/env tclsh
# PNR release_data - Cadence Innovus

# -- Bootstrap -----------------------------------------------------------------
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "PNR"
set STAGE_NAME "release_data"
set NODE_NAME "release_data1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# Source release utilities
set release_utils "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/release_utils.tcl"

if {[file exists $release_utils]} { source $release_utils }

# Source release_config for phase/milestone file expectations
set release_config "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/release_config.tcl"
if {[file exists $release_config]} { source $release_config }

set WORK_DIR "$run_dir/work/PNR/release_data1"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

handle_info "Starting PNR release_data stage with Innovus..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

# ==============================================================================
# flow_proc: init_release
# Initialize release and validate mandatory variables
# ==============================================================================
flow_proc init_release {
    handle_info "Initializing release..."
    global pnr project flow

    set run_dir $::env(CBFLOW_RUN_DIR)

    # ── Validate mandatory variables ─────────────────────────────────────────
    set missing_vars {}
    if {![info exists pnr(common,design_name)] && ![info exists flow(design_name)]} {
        lappend missing_vars "design_name (pnr(common,design_name) or flow(design_name))"
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

    set design_name [expr {[info exists pnr(common,design_name)] ? $pnr(common,design_name) : [expr {[info exists flow(design_name)] ? $flow(design_name) : "pnr"}]}]

    # ── Determine release phase ──────────────────────────────────────────────
    set release_phase "P0"
    if {[info exists project(release_phase)]} { set release_phase $project(release_phase) }
    if {[info exists pnr(common,release_phase)]} { set release_phase $pnr(common,release_phase) }
    if {[info exists project(release,phase)] && $project(release,phase) ne ""} { set release_phase $project(release,phase) }

    # ── Initialize release using utilities ───────────────────────────────────
    if {[namespace exists ::CBFlow::Release]} {
        ::CBFlow::Release::init "PNR" $design_name $run_dir $release_phase
    } else {
        set ::release_dir "$run_dir/release/PNR"
        foreach subdir {reports data netlist def gds spef sdc sdf db} {
            file mkdir "$::release_dir/$subdir"
        }
    }

    handle_info "Release phase: $release_phase"
    handle_info "Release tag: $project(release,tag)"
}

# ==============================================================================
# flow_proc: prepare_release
# Copy PNR deliverables to release directory
# ==============================================================================
flow_proc prepare_release {
    global pnr project tech flow
    handle_info "Preparing PNR release deliverables..."
    set run_dir $::env(CBFLOW_RUN_DIR)

    set design_name [expr {[info exists pnr(common,design_name)] ? $pnr(common,design_name) : "pnr"}]

    # Create release directory structure
    set release_dir "$run_dir/results/release"
    foreach d {"netlist" "netlist/pg" "def" "gds" "spef" "sdc" "sdf" "reports" "reports/timing" "reports/power" "reports/drc" "reports/qor"} {
        file mkdir "$release_dir/$d"
    }

    # Copy GDS
    set gds_src "$run_dir/results/pnr/gds/${design_name}.gds2"
    if {[file exists $gds_src]} {
        file copy -force $gds_src "$release_dir/gds/${design_name}.gds2"
        handle_info "  Released GDS"
    }

    # Copy netlists
    foreach suffix [list "" "_pg"] {
        set nl_src "$run_dir/results/pnr/netlist/${design_name}${suffix}.v"
        if {$suffix eq "_pg"} {
            set nl_dst "$release_dir/netlist/pg/${design_name}_pg.v"
        } else {
            set nl_dst "$release_dir/netlist/${design_name}.v"
        }
        if {[file exists $nl_src]} {
            file copy -force $nl_src $nl_dst
            handle_info "  Released netlist${suffix}"
        }
    }

    # Copy DEF
    set def_src "$run_dir/results/pnr/def/${design_name}.def"
    if {[file exists $def_src]} {
        file copy -force $def_src "$release_dir/def/${design_name}.def"
        handle_info "  Released DEF"
    }

    # Copy SDC
    set sdc_src "$run_dir/results/pnr/sdc/${design_name}.sdc"
    if {[file exists $sdc_src]} {
        file copy -force $sdc_src "$release_dir/sdc/${design_name}.sdc"
        handle_info "  Released SDC"
    }

    # Copy SPEF files (all corners)
    foreach corner {max min nom} {
        set spef_src "$run_dir/results/pnr/spef/${design_name}_${corner}.spef"
        if {[file exists $spef_src]} {
            file copy -force $spef_src "$release_dir/spef/${design_name}_${corner}.spef"
            handle_info "  Released SPEF ($corner)"
        }
    }

    # Copy SDF
    set sdf_src "$run_dir/results/pnr/netlist/${design_name}.sdf"
    if {[file exists $sdf_src]} {
        file copy -force $sdf_src "$release_dir/sdf/${design_name}.sdf"
        handle_info "  Released SDF"
    }

    # Copy signoff reports
    foreach rpt_pattern {"signoff_timing_setup.rpt" "signoff_timing_hold.rpt" "signoff_qor.rpt" "signoff_drc.rpt" "signoff_power.rpt" "signoff_antenna.rpt"} {
        set rpt_src "$run_dir/reports/pnr/$rpt_pattern"
        if {[file exists $rpt_src]} {
            if {[string match "*timing*" $rpt_pattern]} {
                file copy -force $rpt_src "$release_dir/reports/timing/$rpt_pattern"
            } elseif {[string match "*power*" $rpt_pattern]} {
                file copy -force $rpt_src "$release_dir/reports/power/$rpt_pattern"
            } elseif {[string match "*drc*" $rpt_pattern] || [string match "*antenna*" $rpt_pattern]} {
                file copy -force $rpt_src "$release_dir/reports/drc/$rpt_pattern"
            } else {
                file copy -force $rpt_src "$release_dir/reports/qor/$rpt_pattern"
            }
        }
    }

    handle_info "PNR release preparation completed"
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
    global pnr project

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
