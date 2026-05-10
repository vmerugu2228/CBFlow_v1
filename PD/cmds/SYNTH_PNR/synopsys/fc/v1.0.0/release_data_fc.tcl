#!/usr/bin/env tclsh
# CBFlow SYNTH_PNR release_data — Package and validate all deliverables
# Sources release_config.tcl for phase-wise mandatory file validation
# Generates: release directory, manifest, release notes, completion stamp
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
global synth_pnr project tech flow

# Source release utilities
set release_utils "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/release_utils.tcl"
if {[file exists $release_utils]} { source $release_utils }

# Source release_config for phase/milestone file expectations
set release_config "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/release_config.tcl"
if {[file exists $release_config]} { source $release_config }

handle_info "Starting SYNTH_PNR release_data..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

set WORK_DIR "$run_dir/work/SYNTH_PNR/release_data1"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

# ==============================================================================
# flow_proc: init_release
# Initialize release directory and validate mandatory variables
# ==============================================================================
flow_proc init_release {
    handle_info "Initializing release..."
    global synth_pnr project flow

    set run_dir $::env(CBFLOW_RUN_DIR)

    # ── Validate mandatory variables ─────────────────────────────────────────
    set missing_vars {}
    if {![info exists synth_pnr(design_name)] && ![info exists flow(design_name)]} {
        lappend missing_vars "design_name (synth_pnr(design_name) or flow(design_name))"
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

    set design_name [expr {[info exists synth_pnr(design_name)] ? $synth_pnr(design_name) : $flow(design_name)}]

    # ── Determine release phase ──────────────────────────────────────────────
    set release_phase "P0"
    if {[info exists project(release_phase)]} { set release_phase $project(release_phase) }
    if {[info exists synth_pnr(release_phase)]} { set release_phase $synth_pnr(release_phase) }
    if {[info exists project(release,phase)] && $project(release,phase) ne ""} { set release_phase $project(release,phase) }

    # ── Initialize release using utilities ───────────────────────────────────
    if {![namespace exists ::CBFlow::Release]} {
        error "ERROR: release_utils.tcl not loaded. Cannot proceed with release."
    }
    ::CBFlow::Release::init "SYNTH_PNR" $design_name $run_dir $release_phase

    handle_info "Release phase: $release_phase"
    handle_info "Release tag: $project(release,tag)"
}

# ==============================================================================
# flow_proc: copy_deliverables
# Copy all design deliverables from outputs/ and work/ to release directory
# ==============================================================================
flow_proc copy_deliverables {
    handle_info "Copying deliverables to release directory..."
    global synth_pnr flow

    set run_dir $::env(CBFLOW_RUN_DIR)
    set design_name [expr {[info exists synth_pnr(design_name)] ? $synth_pnr(design_name) : $flow(design_name)}]
    set out "$run_dir/outputs"

    namespace import ::CBFlow::Release::copy_file ::CBFlow::Release::copy_glob

    # ── Netlists ─────────────────────────────────────────────────────────
    copy_file "$out/${design_name}.v"       netlist "${design_name}.v"
    copy_file "$out/${design_name}.pt.v"    netlist "${design_name}.pt.v"
    copy_file "$out/${design_name}.fm.v"    netlist "${design_name}.fm.v"
    copy_file "$out/${design_name}.lvs.v"   netlist "${design_name}.lvs.v"
    copy_file "$out/${design_name}.vc_lp.v" netlist "${design_name}.vc_lp.v"
    copy_file "$out/${design_name}.dc.v"    netlist "${design_name}.dc.v"

    # ── Physical ─────────────────────────────────────────────────────────
    copy_file "$out/${design_name}.gds"     gds  "${design_name}.gds"
    copy_file "$out/${design_name}.def"     def  "${design_name}.def"
    copy_file "$out/${design_name}.lef"     data "${design_name}.lef"

    # ── Constraints & Power ──────────────────────────────────────────────
    copy_file "$out/${design_name}.upf"     upf  "${design_name}.upf"
    copy_glob "$out/${design_name}_*.sdc"   sdc

    # ── Parasitics ───────────────────────────────────────────────────────
    copy_glob "$out/${design_name}*.spef*"  spef

    # ── Scripts & Maps ───────────────────────────────────────────────────
    copy_file "$out/${design_name}_wscript"           data "wscript"
    copy_file "$out/${design_name}_wscript_for_pt"    data "wscript_for_pt"
    copy_file "$out/${design_name}_routing_constraints" data "routing_constraints"
    copy_file "$out/${design_name}_floorplan"         data "floorplan"
    copy_file "$out/${design_name}.saif.ptpx.map"     data "saif.ptpx.map"
    copy_file "$out/${design_name}.saif.fc.map"       data "saif.fc.map"

    # ── SVF for Formality ────────────────────────────────────────────────
    copy_glob "$out/${design_name}_*.svf"  data

    # ── Reports (from each stage) ────────────────────────────────────────
    foreach stage {init_design1 synthesis1 place1 cts1 cts_opt1 route1 pro1 signoff1 export_data1} {
        set stage_rpt "$run_dir/work/SYNTH_PNR/$stage/reports"
        if {[file isdirectory $stage_rpt]} {
            copy_glob "$stage_rpt/*.rpt" "reports/$stage"
        }
    }

    handle_info "Deliverables copied to release directory"
}

# ==============================================================================
# flow_proc: validate_release
# Validate against release_config.tcl phase-wise mandatory files
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
# Generate manifest, release notes, and completion stamp
# ==============================================================================
flow_proc generate_release_output {
    handle_info "Generating release output..."
    global synth_pnr project

    set notes ""
    if {[info exists project(release_notes)]} { set notes $project(release_notes) }

    ::CBFlow::Release::generate_manifest
    ::CBFlow::Release::generate_release_notes $notes
    ::CBFlow::Release::stamp_complete
    ::CBFlow::Release::summary

    handle_info "Release output generated"
}

# ==============================================================================
# Source setup.tcl (flow_proc hooks: prepend, append, replace)
# ==============================================================================
set _setup_file "$run_dir/work/SYNTH_PNR/release_data1/run/setup.tcl"
if {[file exists $_setup_file]} {
    handle_info "Sourcing setup hooks: $_setup_file"
    source -e $_setup_file
}
set _override_file "$run_dir/setup/override_setup.tcl"
if {[file exists $_override_file]} {
    handle_info "Sourcing user override: $_override_file"
    source -e $_override_file
}
set _stage_override "$run_dir/setup/override_setup.release_data.tcl"
if {[file exists $_stage_override]} {
    handle_info "Sourcing stage override: $_stage_override"
    source -e $_stage_override
}

flow_exec_all

# Exit tool after stage completion
exit
