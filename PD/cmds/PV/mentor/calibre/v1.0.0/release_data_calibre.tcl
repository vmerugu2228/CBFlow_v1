#!/usr/bin/env tclsh
# CBFlow PV release_data - Mentor Calibre

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "PV"
set STAGE_NAME "release_data"
set NODE_NAME [cbflow_node_name]

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME



# Source release utilities for ::CBFlow::Release namespace (mandatory — the
# release layout is defined only there).
set _ru "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/release_utils.tcl"
if {![file exists $_ru]} { handle_error "release_utils.tcl not found: $_ru" }
source $_ru
# ==============================================================================
flow_proc init_release {
    handle_info "Initializing release..."
    global pv project flow

    set run_dir $::env(CBFLOW_RUN_DIR)

    # ── Validate mandatory variables ─────────────────────────────────────────
    # (project(release,tag) is resolved by ::CBFlow::Release::init — it
    # defaults to the flow's exit name when unset.)
    set missing_vars {}
    if {!([info exists pv(common,design_name)] && $pv(common,design_name) ne "") &&
        !([info exists flow(design_name)] && $flow(design_name) ne "")} {
        lappend missing_vars "design_name (pv(common,design_name) or flow(design_name))"
    }
    if {![info exists ::env(FLOW_DIR)] || $::env(FLOW_DIR) eq ""} {
        lappend missing_vars "FLOW_DIR"
    }
    if {![info exists ::env(CONFIG_ROOT)] || $::env(CONFIG_ROOT) eq ""} {
        lappend missing_vars "CONFIG_ROOT"
    }

    if {[llength $missing_vars] > 0} {
        handle_error "Missing mandatory variables for release: [join $missing_vars {, }]"
    }

    set design_name [expr {[info exists pv(common,design_name)] && $pv(common,design_name) ne "" ? $pv(common,design_name) : $flow(design_name)}]

    # ── Determine release phase ──────────────────────────────────────────────
    set release_phase ""   ;# from project(release,phase) below — no built-in phase
    if {[info exists project(release_phase)]} { set release_phase $project(release_phase) }
    if {[info exists pv(release_phase)]} { set release_phase $pv(release_phase) }
    if {[info exists project(release,phase)] && $project(release,phase) ne ""} { set release_phase $project(release,phase) }

    # ── Initialize release using utilities ───────────────────────────────────
    ::CBFlow::Release::init "PV" $design_name $run_dir $release_phase

    handle_info "Release phase: $release_phase"
    set _release_tag [expr {[info exists project(release,tag)] ? $project(release,tag) : "(unset)"}]
    handle_info "Release tag: $_release_tag"
}

flow_proc prepare_release {
    handle_info "Preparing release directory..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    set release_dir $::CBFlow::Release::release_dir
    foreach dir {"reports" "drc" "lvs" "perc" "perc_ldl"} { file mkdir "$release_dir/$dir" }

    # Check BOTH candidate locations: work/PV/<node>/results/<type>/
    # (real output location) first, then $run_dir/results/<type>/ for the
    # mirror-copies the handlers also write. Nodes are resolved from the DAG
    # (upstream node of each stage type; erc was removed from the PV DAG).
    foreach {_type file dest} {
        drc       drc.rpt          drc/drc.rpt
        drc       drc_results.rpt  drc/drc_results.rpt
        lvs       lvs.rpt          lvs/lvs.rpt
        lvs       lvs_results.rpt  lvs/lvs_results.rpt
        perc      perc.rpt         perc/perc.rpt
        perc      perc_results.rpt perc/perc_results.rpt
        perc_ldl  perc_ldl.rpt     perc_ldl/perc_ldl.rpt
    } {
        set node [cbflow_dep_node $_type]
        set work_src "[cbflow_node_dir $node]/results/$_type/$file"
        set run_src  "$run_dir/results/$_type/$file"
        set found ""
        if {[file exists $work_src]} { set found $work_src
        } elseif {[file exists $run_src]} { set found $run_src }
        if {$found ne ""} {
            if {[catch {file copy -force $found "$release_dir/$dest"} _err]} {
                handle_warning "release copy failed for $dest: $_err"
            } else {
                puts "  Copied: $found -> $dest"
            }
        } else {
            puts "  Skipped (not produced): $dest"
        }
    }
    # Verification summary — produced by the merge_data node at
    # results/verification/verification_summary.rpt (new) and
    # results/phyv/phyv_summary.rpt (legacy).
    foreach {src dest} {
        results/verification/verification_summary.rpt reports/verification_summary.rpt
        results/phyv/phyv_summary.rpt                 reports/phyv_summary.rpt
    } {
        if {[file exists "$run_dir/$src"]} {
            if {[catch {file copy -force "$run_dir/$src" "$release_dir/$dest"} _cp_err]} {
                handle_warning "release copy failed for $src → $dest: $_cp_err"
            } else {
                puts "  Copied: $src"
            }
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
    global project

    set notes ""
    if {[info exists project(release_notes)]} { set notes $project(release_notes) }

    ::CBFlow::Release::generate_manifest
    ::CBFlow::Release::generate_release_notes $notes
    ::CBFlow::Release::stamp_complete
    ::CBFlow::Release::summary

    handle_info "Release output generated"
}

flow_exec_all

# Exit tool after stage completion
exit
