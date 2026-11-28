#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow PV decomp_merge_gds — Siemens Calibre (Calibre nmPlatform 2024.x)
# Bakes the decomposed color layers back into the signoff GDS that downstream
# check stages (drc/lvs/perc/perc_ldl/xor) consume. Uses `calibredrv -mp`
# stream-out with color mapping honored.
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$::env(CBFLOW_RUN_DIR)/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "PV"
set STAGE_NAME "decomp_merge_gds"
set NODE_NAME [cbflow_node_name]

source "$::env(CBFLOW_RUN_DIR)/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$::env(CBFLOW_RUN_DIR)/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $::env(CBFLOW_RUN_DIR) $FLOW_TYPE $NODE_NAME

if {[info exists pv(common,design_name)] && $pv(common,design_name) ne ""} {
    set DESIGN_NAME $pv(common,design_name)
} elseif {[info exists flow(design_name)] && $flow(design_name) ne ""} {
    set DESIGN_NAME $flow(design_name)
} else {
    handle_error "Design name not set — set pv(common,design_name) or flow(design_name) in user_config"
}
set ::DESIGN_NAME $DESIGN_NAME

flow_proc configure_decomp_merge_gds {
    global pv tech project
    handle_info "Configuring decomposed GDS merge (calibredrv -mp)..."

    # Two upstream artifacts feed this stage: the fill-verified base GDS and
    # the colored GDS from the decomp node. Both parents guaranteed by the DAG.
    # Inputs from the upstream fill_merge_gds and decomp nodes (per-stage
    # $WORK_DIR/results). Legacy shared results/pv/ path no longer written to.
    set ::dm_fill_input   "[cbflow_node_dir [cbflow_dep_node fill_merge_gds]]/results/${::DESIGN_NAME}_fill_verified.gds"
    set ::dm_decomp_input "[cbflow_node_dir [cbflow_dep_node decomp]]/results/${::DESIGN_NAME}_colored.gds"
    set ::dm_outform      [cbflow_require pv decomp_merge_gds,outform]

    if {[info exists pv(common,top_cell)]} {
        set ::dm_top $pv(common,top_cell)
    } elseif {[info exists project(top_module)]} {
        set ::dm_top $project(top_module)
    } else {
        set ::dm_top $::DESIGN_NAME
    }

    # MP layer map — same runset used by decomp1 (color assignments must
    # match). Resolution matches decomp1's fallback chain.
    if {[info exists pv(decomp,runset)] && $pv(decomp,runset) ne ""} {
        set ::dm_runset $pv(decomp,runset)
    } elseif {[info exists pv(input,rule_deck_multi_patterning)] && $pv(input,rule_deck_multi_patterning) ne ""} {
        set ::dm_runset $pv(input,rule_deck_multi_patterning)
    } else {
        set ::dm_runset ""
    }

    set ::dm_out "$::WORK_DIR/results/${::DESIGN_NAME}_signoff.gds"
    set ::dm_log "$::env(CBFLOW_RUN_DIR)/logs/pv/decomp_merge_gds_calibre.log"

    handle_info "Decomposed GDS merge configuration:"
    handle_info "  Fill-verified input: $::dm_fill_input"
    handle_info "  Colored input:       $::dm_decomp_input"
    handle_info "  MP runset:           [expr {$::dm_runset eq {} ? {<merge-only>} : $::dm_runset}]"
    handle_info "  Top cell:            $::dm_top"
    handle_info "  Signoff output:      $::dm_out"
}

flow_proc run_decomp_merge_gds {
    set ::dm_status "PASS"
    handle_info "Running decomposed GDS merge with calibredrv..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    file mkdir "$::WORK_DIR/results"
    file mkdir "$::REPORTS_DIR"
    file mkdir "$::env(CBFLOW_RUN_DIR)/logs/pv"

    # calibredrv layout filemerge with MP color propagation:
    #   calibredrv -64 -a "layout filemerge -in fill.gds -in colored.gds
    #                     -out signoff.gds -outform <pv(decomp_merge_gds,outform)> -mode combine
    #                     -topcell TOP -mp_runset <deck>"
    set drv_args [list "layout filemerge" \
                       "-in" $::dm_fill_input \
                       "-in" $::dm_decomp_input \
                       "-out" $::dm_out \
                       "-outform" $::dm_outform \
                       "-topcell" $::dm_top \
                       "-mode" "combine"]
    if {$::dm_runset ne "" && [file exists $::dm_runset]} {
        lappend drv_args "-mp_runset" $::dm_runset
    }
    set calibre_cmd [list calibredrv -64 -a [join $drv_args " "]]

    handle_info "  CMD: $calibre_cmd"
    handle_info "  Log: $::dm_log"

    # test_mode guard: Tcl's `exec` is a builtin, so test_mode's unknown-based
    # EDA interceptor doesn't catch it. Without this, test_mode tries to exec
    # a real calibre binary (not on PATH) → non-zero exit → stage fails.
    set _tm [expr {[info exists ::flow(test_mode)] && [is_true $::flow(test_mode)]}]
    if {$_tm} {
    handle_info "  TEST_CMD: (calibre exec skipped in test_mode)"
    return
    }

    if {[catch {exec {*}$calibre_cmd >& $::dm_log} _r]} {
        if {[classify_tool_exit_log $::dm_log] eq "FATAL"} {
            handle_error "calibredrv layout filemerge (mp) crashed (license / perms / tool error) — see $::dm_log"
        }
        handle_warning "calibredrv layout filemerge (mp) failed: $_r"
        set ::dm_status "FAIL"
    } else {
        set ::dm_status "PASS"
        handle_info "Decomposed GDS merge completed"
    }
}

flow_proc report_decomp_merge_gds {
    file mkdir $::REPORTS_DIR
    set fp [open "$::REPORTS_DIR/decomp_merge_gds_summary.rpt" w]
    puts $fp "═══════════════════════════════════════════════════════════════════════════════"
    puts $fp "PV Decomposed GDS Merge Summary — Siemens Calibre"
    puts $fp "═══════════════════════════════════════════════════════════════════════════════"
    puts $fp "Design:              $::DESIGN_NAME"
    puts $fp "Fill-verified input: $::dm_fill_input"
    puts $fp "Colored input:       $::dm_decomp_input"
    puts $fp "MP runset:           [expr {$::dm_runset eq {} ? {<merge-only>} : $::dm_runset}]"
    puts $fp "Signoff output:      $::dm_out"
    puts $fp "Status:              $::dm_status"
    close $fp
    handle_info "Report written: $::REPORTS_DIR/decomp_merge_gds_summary.rpt"
}

flow_proc decomp_merge_gds_flow {
    flow_exec configure_decomp_merge_gds
    flow_exec run_decomp_merge_gds
    flow_exec report_decomp_merge_gds
    flow_fail_if_status ::dm_status "$::REPORTS_DIR/decomp_merge_gds_summary.rpt"
}
if {[info exists argv0] && $argv0 eq [info script]} { flow_exec decomp_merge_gds_flow } else { puts " PV decomp_merge_gds procedures loaded" }
exit
