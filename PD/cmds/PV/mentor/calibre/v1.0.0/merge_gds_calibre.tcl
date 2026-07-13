#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow PV merge_gds — Siemens Calibre (Calibre nmPlatform 2024.x)
# Merges fill GDS with base layout using calibredrv layout filemerge.
# Reference flow: Calibre User's Manual — "Layout Manipulation" chapter.
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$::env(CBFLOW_RUN_DIR)/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "PV"
set STAGE_NAME "merge_gds"
set NODE_NAME "${STAGE_NAME}1"

source "$::env(CBFLOW_RUN_DIR)/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$::env(CBFLOW_RUN_DIR)/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $::env(CBFLOW_RUN_DIR) $FLOW_TYPE $NODE_NAME

# ── Design name (project fallback) ──
set DESIGN_NAME [expr {[info exists pv(common,design_name)] ? $pv(common,design_name) :
                       [expr {[info exists flow(design_name)] ? $flow(design_name) : "design"}]}]
set ::DESIGN_NAME $DESIGN_NAME

flow_proc configure_merge_gds {
    global pv tech project
    handle_info "Configuring GDS merge (calibredrv layout filemerge)..."

    # ── Base layout (GDS from PNR/PV setup) ──
    if {[info exists pv(input,gds)] && $pv(input,gds) ne ""} {
        set ::merge_base_gds $pv(input,gds)
    } elseif {[info exists pv(input,gds_file)] && $pv(input,gds_file) ne ""} {
        set ::merge_base_gds $pv(input,gds_file)
    } else {
        handle_error "No base GDS — set pv(input,gds) in user_config"
        return
    }

    # ── Fill GDS (produced by an earlier PNR fill_metal step) ──
    # Resolution chain (mirrors DRC's runset convention):
    #   pv(merge_gds,fill_gds) → pv(input,fill_gds) → empty (passthrough)
    if {[info exists pv(merge_gds,fill_gds)] && $pv(merge_gds,fill_gds) ne ""} {
        set ::merge_fill_gds $pv(merge_gds,fill_gds)
    } elseif {[info exists pv(input,fill_gds)] && $pv(input,fill_gds) ne ""} {
        set ::merge_fill_gds $pv(input,fill_gds)
    } else {
        # Fill GDS optional — if unset, treat this stage as a passthrough merge.
        set ::merge_fill_gds ""
    }

    # ── Top cell for merge boundary ──
    if {[info exists pv(common,top_cell)]} {
        set ::merge_top $pv(common,top_cell)
    } elseif {[info exists project(top_module)]} {
        set ::merge_top $project(top_module)
    } else {
        set ::merge_top $::DESIGN_NAME
    }

    set ::merge_out "$::WORK_DIR/results/${::DESIGN_NAME}_merged.gds"
    set ::merge_log "$::env(CBFLOW_RUN_DIR)/logs/pv/merge_gds_calibre.log"

    handle_info "GDS merge configuration:"
    handle_info "  Base GDS:  $::merge_base_gds"
    handle_info "  Fill GDS:  [expr {$::merge_fill_gds eq {} ? {<none — passthrough>} : $::merge_fill_gds}]"
    handle_info "  Top cell:  $::merge_top"
    handle_info "  Output:    $::merge_out"
}

flow_proc run_merge_gds {
    set ::merge_gds_status "PASS"
    handle_info "Running GDS merge with calibredrv..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    file mkdir "$::WORK_DIR/results"
    file mkdir "$::REPORTS_DIR"
    file mkdir "$::env(CBFLOW_RUN_DIR)/logs/pv"

    # calibredrv layout filemerge syntax (2024.x):
    #   calibredrv -a "layout filemerge -in <a> -in <b> -out <c> -mode <mode> -topcell <top>"
    # -mode replace  → later layers overwrite earlier
    # -mode combine  → union of layers (used for fill merge)
    if {$::merge_fill_gds ne ""} {
        set drv_cmd [list "layout filemerge" \
                          "-in" $::merge_base_gds \
                          "-in" $::merge_fill_gds \
                          "-out" $::merge_out \
                          "-outform" "OASIS" \
                          "-topcell" $::merge_top \
                          "-mode" "combine"]
        set calibre_cmd [list calibredrv -64 -a [join $drv_cmd " "]]
    } else {
        # Passthrough — copy base to output so downstream stages have a stable path.
        set drv_cmd [list "layout copy" \
                          "-in" $::merge_base_gds \
                          "-out" $::merge_out \
                          "-topcell" $::merge_top]
        set calibre_cmd [list calibredrv -64 -a [join $drv_cmd " "]]
    }

    handle_info "  CMD: $calibre_cmd"
    handle_info "  Log: $::merge_log"

    if {[catch {exec {*}$calibre_cmd >& $::merge_log} _r]} {
        handle_warning "calibredrv layout filemerge failed: $_r"
        set ::merge_gds_status "FAIL"
    } else {
        set ::merge_gds_status "PASS"
        handle_info "GDS merge completed"
    }
}

flow_proc report_merge_gds {
    file mkdir $::REPORTS_DIR
    set fp [open "$::REPORTS_DIR/merge_gds_summary.rpt" w]
    puts $fp "═══════════════════════════════════════════════════════════════════════════════"
    puts $fp "PV GDS Merge Summary — Siemens Calibre"
    puts $fp "═══════════════════════════════════════════════════════════════════════════════"
    puts $fp "Design:     $::DESIGN_NAME"
    puts $fp "Base GDS:   $::merge_base_gds"
    puts $fp "Fill GDS:   [expr {$::merge_fill_gds eq {} ? {<none — passthrough>} : $::merge_fill_gds}]"
    puts $fp "Top cell:   $::merge_top"
    puts $fp "Output:     $::merge_out"
    puts $fp "Status:     $::merge_gds_status"
    close $fp
    handle_info "Report written: $::REPORTS_DIR/merge_gds_summary.rpt"
}

flow_proc merge_gds_flow {
    flow_exec configure_merge_gds
    flow_exec run_merge_gds
    flow_exec report_merge_gds
    if {[info exists ::merge_gds_status] && $::merge_gds_status eq "FAIL"} {
        handle_error "merge_gds failed — see $::REPORTS_DIR/merge_gds_summary.rpt"
    }
}
if {[info exists argv0] && $argv0 eq [info script]} { flow_exec merge_gds_flow } else { puts " PV merge_gds procedures loaded" }
exit
