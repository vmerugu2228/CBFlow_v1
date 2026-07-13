#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow PV perc_ldl — Siemens Calibre PERC (2024.x)
# Latch-up / leakage-driven layout (LDL) analysis. Runs in parallel with the
# standard perc1 stage. Reference: Calibre PERC User's Manual — LDL flow.
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$::env(CBFLOW_RUN_DIR)/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "PV"
set STAGE_NAME "perc_ldl"
set NODE_NAME "${STAGE_NAME}1"

source "$::env(CBFLOW_RUN_DIR)/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$::env(CBFLOW_RUN_DIR)/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $::env(CBFLOW_RUN_DIR) $FLOW_TYPE $NODE_NAME

set DESIGN_NAME [expr {[info exists pv(common,design_name)] ? $pv(common,design_name) :
                       [expr {[info exists flow(design_name)] ? $flow(design_name) : "design"}]}]
set ::DESIGN_NAME $DESIGN_NAME

flow_proc configure_perc_ldl {
    global pv tech project
    handle_info "Configuring PERC-LDL run..."

    # Post-signoff GDS from producer stage decomp_merge_gds1 (per-stage
    # $WORK_DIR/results). The legacy shared $CBFLOW_RUN_DIR/results/pv/
    # path is no longer written to after the fill1/erc1 → new-DAG rework.
    #
    # NO fallback to pv(input,gds) — that is the raw pre-fill, pre-decomp
    # layout. Running latch-up analysis on it silently gives a "clean"
    # result for a check that must verify the POST-fill electrical
    # topology. Fail loudly if the producer output is missing so the real
    # upstream problem surfaces instead of a phantom PASS at sign-off.
    set ::perc_ldl_gds "$::env(CBFLOW_RUN_DIR)/work/PV/decomp_merge_gds1/results/${::DESIGN_NAME}_signoff.gds"
    # Guard fires only in REAL runs (test_mode not set OR explicitly disabled).
    # The prior formulation `![info exists ::flow(test_mode)]` was inverted —
    # a user setting `set flow(test_mode) "false"` (a documented pattern to
    # turn test mode OFF) made the variable EXIST, the guard skipped, and a
    # missing producer output silently propagated to a phantom PASS. Match
    # the convention used everywhere else in the tree.
    set _tm [expr {[info exists ::flow(test_mode)] && $::flow(test_mode) eq "true"}]
    if {![file exists $::perc_ldl_gds] && !$_tm} {
        handle_error "perc_ldl input GDS missing: $::perc_ldl_gds — decomp_merge_gds1 must run first"
    }

    # LDL-specific SVRF runset. Resolution (matches DRC's convention):
    #   pv(perc_ldl,runset) → pv(input,rule_deck_perc_ldl) → standard PERC deck
    if {[info exists pv(perc_ldl,runset)] && $pv(perc_ldl,runset) ne ""} {
        set ::perc_ldl_runset $pv(perc_ldl,runset)
    } elseif {[info exists pv(input,rule_deck_perc_ldl)] && $pv(input,rule_deck_perc_ldl) ne ""} {
        set ::perc_ldl_runset $pv(input,rule_deck_perc_ldl)
    } elseif {[info exists pv(input,rule_deck_perc)] && $pv(input,rule_deck_perc) ne ""} {
        set ::perc_ldl_runset $pv(input,rule_deck_perc)
    } else {
        set ::perc_ldl_runset ""
    }

    if {[info exists pv(common,top_cell)]} {
        set ::perc_ldl_top $pv(common,top_cell)
    } elseif {[info exists project(top_module)]} {
        set ::perc_ldl_top $project(top_module)
    } else {
        set ::perc_ldl_top $::DESIGN_NAME
    }

    set ::perc_ldl_out_dir "$::env(CBFLOW_RUN_DIR)/results/pv/perc_ldl"
    set ::perc_ldl_log     "$::env(CBFLOW_RUN_DIR)/logs/pv/perc_ldl_calibre.log"

    handle_info "PERC-LDL configuration:"
    handle_info "  GDS input: $::perc_ldl_gds"
    handle_info "  Runset:    [expr {$::perc_ldl_runset eq {} ? {<none — will skip>} : $::perc_ldl_runset}]"
    handle_info "  Top cell:  $::perc_ldl_top"
    handle_info "  Out dir:   $::perc_ldl_out_dir"
}

flow_proc run_perc_ldl {
    set ::perc_ldl_status "PASS"
    handle_info "Running PERC-LDL with Calibre..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    file mkdir "$::perc_ldl_out_dir"
    file mkdir "$::REPORTS_DIR"
    file mkdir "$::env(CBFLOW_RUN_DIR)/logs/pv"

    if {$::perc_ldl_runset eq "" || ![file exists $::perc_ldl_runset]} {
        handle_warning "No PERC-LDL runset available — skipping run (report only)"
        set ::perc_ldl_status "SKIPPED"
        return
    }

    # Calibre PERC-LDL invocation (2024.x):
    #   calibre -perc -ldl -hier -64 -turbo N <runset>
    # -ldl enables the latch-up/leakage-driven-layout topology check pass.
    set num_cpus [expr {[info exists pv(perc_ldl,num_cpus)] ? $pv(perc_ldl,num_cpus) : 8}]
    set calibre_cmd [list calibre -perc -ldl -hier -64 -turbo $num_cpus $::perc_ldl_runset]

    handle_info "  CMD: $calibre_cmd"
    handle_info "  Log: $::perc_ldl_log"

    if {[catch {exec {*}$calibre_cmd >& $::perc_ldl_log} _r]} {
        handle_warning "Calibre PERC-LDL returned non-zero (may have violations): $_r"
        set ::perc_ldl_status "FAIL"
    } else {
        set ::perc_ldl_status "PASS"
        handle_info "PERC-LDL completed"
    }
}

flow_proc report_perc_ldl {
    file mkdir $::REPORTS_DIR
    file mkdir "$::perc_ldl_out_dir"

    # Per-category violation counts. In a real Calibre run these come from
    # parsing the tool's SVDB — the checklist regexes (pv_perc_ldl_*)
    # in PD/config/exit/v1.0.0/checks/pv_flow_checks.tcl key off the
    # exact label strings emitted here.
    #
    # SKIPPED status (no runset available — the tool never ran) MUST emit
    # a non-numeric marker so metric-parsing consumers can't misread 0 as
    # "0 violations, all clean". The consumer regex `([0-9]+)` won't
    # match "N/A", so the check reports "metric not found" instead of a
    # silent PASS.
    if {$::perc_ldl_status eq "SKIPPED"} {
        set ::perc_ldl_total          "N/A (runset unavailable)"
        set ::perc_ldl_well_contact   "N/A (runset unavailable)"
        set ::perc_ldl_floating_gate  "N/A (runset unavailable)"
        set ::perc_ldl_latchup        "N/A (runset unavailable)"
    } else {
        set _fail [expr {$::perc_ldl_status eq "FAIL"}]
        set ::perc_ldl_total          [expr {$_fail ? 1 : 0}]
        set ::perc_ldl_well_contact   [expr {$_fail ? 1 : 0}]
        set ::perc_ldl_floating_gate  [expr {$_fail ? 1 : 0}]
        set ::perc_ldl_latchup        [expr {$_fail ? 1 : 0}]
    }

    set fp [open "$::REPORTS_DIR/perc_ldl_summary.rpt" w]
    puts $fp "═══════════════════════════════════════════════════════════════════════════════"
    puts $fp "PV PERC-LDL Summary — Siemens Calibre"
    puts $fp "═══════════════════════════════════════════════════════════════════════════════"
    puts $fp "Design:    $::DESIGN_NAME"
    puts $fp "GDS input: $::perc_ldl_gds"
    puts $fp "Runset:    $::perc_ldl_runset"
    puts $fp "Top cell:  $::perc_ldl_top"
    puts $fp "Status:    $::perc_ldl_status"
    puts $fp "Total Violations:         $::perc_ldl_total"
    puts $fp "Well Contact Violations:  $::perc_ldl_well_contact"
    puts $fp "Floating Gate Violations: $::perc_ldl_floating_gate"
    puts $fp "Latch-up Violations:      $::perc_ldl_latchup"
    close $fp
    # Signoff artifact expected by mandatory_outputs
    set mp [open "$::perc_ldl_out_dir/perc_ldl.rpt" w]
    puts $mp "PERC-LDL sign-off report — $::perc_ldl_status"
    close $mp
    handle_info "Report written: $::REPORTS_DIR/perc_ldl_summary.rpt"
}

flow_proc perc_ldl_flow {
    flow_exec configure_perc_ldl
    flow_exec run_perc_ldl
    flow_exec report_perc_ldl
    flow_fail_if_status ::perc_ldl_status "$::REPORTS_DIR/perc_ldl_summary.rpt"
}
if {[info exists argv0] && $argv0 eq [info script]} { flow_exec perc_ldl_flow } else { puts " PV perc_ldl procedures loaded" }
exit
