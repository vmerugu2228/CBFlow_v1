#!/usr/bin/env tclsh
# FP release_data - Cadence Innovus

# -- Bootstrap -----------------------------------------------------------------
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "FP"
set STAGE_NAME "release_data"
set NODE_NAME [cbflow_node_name]

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME


# Release writer (::CBFlow::Release — the only release layout). Mandatory.
set release_utils "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/release_utils.tcl"
if {![file exists $release_utils]} {
    handle_error "release_utils.tcl not found: $release_utils"
}
source $release_utils

# Source release_config for phase/milestone file expectations (mandatory)
set release_config "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/release_config.tcl"
if {![file exists $release_config]} {
    handle_error "release_config.tcl not found: $release_config"
}
source $release_config

set WORK_DIR [cbflow_node_dir $NODE_NAME]
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
    set design_name ""
    if {[info exists fp(common,design_name)] && $fp(common,design_name) ne ""} {
        set design_name $fp(common,design_name)
    } elseif {[info exists flow(design_name)] && $flow(design_name) ne ""} {
        set design_name $flow(design_name)
    } else {
        lappend missing_vars "design_name (fp(common,design_name) or flow(design_name))"
    }
    if {![info exists ::env(FLOW_DIR)] || $::env(FLOW_DIR) eq ""} {
        lappend missing_vars "FLOW_DIR"
    }
    if {![info exists ::env(CONFIG_ROOT)] || $::env(CONFIG_ROOT) eq ""} {
        lappend missing_vars "CONFIG_ROOT"
    }

    if {[llength $missing_vars] > 0} {
        handle_error "Missing mandatory variables for release: [join $missing_vars {, }]"
        return
    }

    # ── Determine release phase ──────────────────────────────────────────────
    set release_phase ""   ;# from project(release,phase) below — no built-in phase
    if {[info exists project(release_phase)]} { set release_phase $project(release_phase) }
    if {[info exists fp(common,release_phase)] && $fp(common,release_phase) ne ""} { set release_phase $fp(common,release_phase) }
    if {[info exists project(release,phase)] && $project(release,phase) ne ""} { set release_phase $project(release,phase) }

    # ── Initialize release (<path>/<phase>/<block>/FP/<tag>) ─────────────────
    set ::release_dir [::CBFlow::Release::init $::FLOW_TYPE $design_name $run_dir $release_phase]

    handle_info "Release phase: $::CBFlow::Release::release_phase"
    handle_info "Release tag: $::CBFlow::Release::release_tag"
}

# ==============================================================================
# flow_proc: prepare_release
# Copy FP deliverables (as written by the export_data / floorplan / powerplan
# nodes) into the release directory
# ==============================================================================
flow_proc prepare_release {
    global fp project tech flow
    handle_info "Preparing FP release deliverables..."
    set run_dir $::env(CBFLOW_RUN_DIR)

    # export_data_innovus.tcl writes results/{def,netlist}/<top>_fp.* and
    # results/<top>_fp.enc[.dat] (top = project(top_module)).
    set dname [cbflow_require project top_module]

    # DEF
    if {![::CBFlow::Release::copy_file "results/def/${dname}_fp.def" def "${dname}_fp.def"]} {
        handle_warning "DEF not found: $run_dir/results/def/${dname}_fp.def"
    } else {
        handle_info "  Released DEF: ${dname}_fp.def"
    }

    # Design database (.enc + .enc.dat)
    set _n [::CBFlow::Release::copy_glob "$run_dir/results/${dname}_fp.enc*" db]
    handle_info "  Released DB: $_n item(s)"

    # Netlist
    if {[::CBFlow::Release::copy_file "results/netlist/${dname}_fp.v" netlist "${dname}_fp.v"]} {
        handle_info "  Released netlist: ${dname}_fp.v"
    }

    # Reports — from the producing nodes on this node's upstream graph
    foreach _type {floorplan powerplan export_data} {
        set _node [cbflow_dep_node $_type]
        set src "[cbflow_node_dir $_node]/reports"
        if {![file isdirectory $src]} { continue }
        foreach rpt [glob -nocomplain "$src/*.rpt"] {
            set rpt_name [file tail $rpt]
            if {[string match "*timing*" $rpt_name] || [string match "*clock*" $rpt_name]} {
                ::CBFlow::Release::copy_file $rpt reports/timing $rpt_name
            } elseif {[string match "*pg*" $rpt_name] || [string match "*power*" $rpt_name]} {
                ::CBFlow::Release::copy_file $rpt reports/powerplan $rpt_name
            } else {
                ::CBFlow::Release::copy_file $rpt reports/floorplan $rpt_name
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

    set valid [::CBFlow::Release::validate_mandatory_files]
    if {!$valid} {
        handle_warning "Some mandatory files are missing — check release phase requirements"
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

    ::CBFlow::Release::generate_manifest
    ::CBFlow::Release::generate_release_notes $notes
    ::CBFlow::Release::stamp_complete
    ::CBFlow::Release::summary

    handle_info "Release output generated"
}

# ==============================================================================
# Execution control
# ==============================================================================
flow_exec_all

# Exit tool after stage completion
exit
