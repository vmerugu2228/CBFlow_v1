#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow PV decomp_merge_gds — Siemens Calibre (Calibre nmPlatform 2024.x)
# Bakes the decomposed color layers back into the signoff GDS that downstream
# check stages (drc/lvs/perc/perc_ldl/xor) consume. Uses `calibredrv -mp`
# stream-out with color mapping honored.
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$::env(CBFLOW_RUN_DIR)/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "PV"
set STAGE_NAME "decomp_merge_gds"
set NODE_NAME "${STAGE_NAME}1"

source "$::env(CBFLOW_RUN_DIR)/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$::env(CBFLOW_RUN_DIR)/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $::env(CBFLOW_RUN_DIR) $FLOW_TYPE $NODE_NAME

set DESIGN_NAME [expr {[info exists pv(common,design_name)] ? $pv(common,design_name) :
                       [expr {[info exists flow(design_name)] ? $flow(design_name) : "design"}]}]
set ::DESIGN_NAME $DESIGN_NAME

flow_proc configure_decomp_merge_gds {
    global pv tech project
    handle_info "Configuring decomposed GDS merge (calibredrv -mp)..."

    # Two upstream artifacts feed this stage: the fill-verified base GDS and
    # the colored GDS from decomp1. Both parents guaranteed by the DAG.
    # Inputs from producer stages fill_merge_gds1 and decomp1 (per-stage
    # $WORK_DIR/results). Legacy shared results/pv/ path no longer written to.
    set ::dm_fill_input   "$::env(CBFLOW_RUN_DIR)/work/PV/fill_merge_gds1/results/${::DESIGN_NAME}_fill_verified.gds"
    set ::dm_decomp_input "$::env(CBFLOW_RUN_DIR)/work/PV/decomp1/results/${::DESIGN_NAME}_colored.gds"

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
    #                     -out signoff.gds -outform OASIS -mode combine
    #                     -topcell TOP -mp_runset <deck>"
    set drv_args [list "layout filemerge" \
                       "-in" $::dm_fill_input \
                       "-in" $::dm_decomp_input \
                       "-out" $::dm_out \
                       "-outform" "OASIS" \
                       "-topcell" $::dm_top \
                       "-mode" "combine"]
    if {$::dm_runset ne "" && [file exists $::dm_runset]} {
        lappend drv_args "-mp_runset" $::dm_runset
    }
    set calibre_cmd [list calibredrv -64 -a [join $drv_args " "]]

    handle_info "  CMD: $calibre_cmd"
    handle_info "  Log: $::dm_log"

    if {[catch {exec {*}$calibre_cmd >& $::dm_log} _r]} {
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
    if {[info exists ::dm_status] && $::dm_status eq "FAIL"} {
        handle_error "decomp_merge_gds failed — see $::REPORTS_DIR/decomp_merge_gds_summary.rpt"
    }
}
if {[info exists argv0] && $argv0 eq [info script]} { flow_exec decomp_merge_gds_flow } else { puts " PV decomp_merge_gds procedures loaded" }
exit
