#!/usr/bin/env tclsh
# CBFlow SYNTH_PNR release_data -- Package and validate all deliverables
# Sources release_config.tcl for phase-wise mandatory file validation
# Generates: release directory, manifest, release notes, completion stamp

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "SYNTH_PNR"
set STAGE_NAME "release_data"
set NODE_NAME "release_data1"

# ── Config (full cascade: project → tech → flow → node → mmmc → tool → user) ─
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"

# ── Directories ──────────────────────────────────────────────────────────────
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

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
    if {$synth_pnr(common,design_name) eq "" && ![info exists flow(design_name)]} {
        lappend missing_vars "design_name (synth_pnr(common,design_name) or flow(design_name))"
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

    set design_name [expr {$synth_pnr(common,design_name) ne "" ? $synth_pnr(common,design_name) : $flow(design_name)}]

    # ── Determine release phase ──────────────────────────────────────────────
    set release_phase "P0"
    if {[info exists project(release_phase)]} { set release_phase $project(release_phase) }
    if {[info exists synth_pnr(release_data,release_phase)] && $synth_pnr(release_data,release_phase) ne ""} { set release_phase $synth_pnr(release_data,release_phase) }
    if {[info exists project(release,phase)] && $project(release,phase) ne ""} { set release_phase $project(release,phase) }

    # ── Initialize release using utilities ───────────────────────────────────
    if {![namespace exists ::CBFlow::Release]} {
        error "ERROR: release_utils.tcl not loaded. Cannot proceed with release."
    }
    ::CBFlow::Release::init "SYNTH_PNR" $design_name $run_dir $release_phase

    handle_info "Release phase: $release_phase"
    handle_info "Release tag: $project(release,tag)"
# ==============================================================================
# flow_proc: copy_deliverables
# Copy all design deliverables from outputs/ and work/ to release directory
# ==============================================================================
flow_proc copy_deliverables {
    handle_info "Copying deliverables to release directory..."
    global synth_pnr flow

    set run_dir $::env(CBFLOW_RUN_DIR)
    set design_name [expr {$synth_pnr(common,design_name) ne "" ? $synth_pnr(common,design_name) : $flow(design_name)}]
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
# ==============================================================================
# ==============================================================================
flow_exec_all

# Exit tool after stage completion
exit
