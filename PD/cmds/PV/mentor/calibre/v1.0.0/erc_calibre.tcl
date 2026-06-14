#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow PV ERC — Siemens Calibre
# Invokes Calibre ERC (via DRC engine) with foundry SVRF runset
# ═══════════════════════════════════════════════════════════════════════════════

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "PV"
set STAGE_NAME "erc"
set NODE_NAME "${STAGE_NAME}1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME


# ── Design name (resolve from pv(...) or flow(...)) ──────────────────────
set DESIGN_NAME [expr {[info exists pv(common,design_name)] ? $pv(common,design_name) :
                       [expr {[info exists flow(design_name)] ? $flow(design_name) : "design"}]}]
set ::DESIGN_NAME $DESIGN_NAME
# ═══════════════════════════════════════════════════════════════════════════════
# Setup Calibre ERC environment variables for SVRF runset
# ═══════════════════════════════════════════════════════════════════════════════
flow_proc setup_erc_environment {
    global pv project tech

    handle_info "Setting up Calibre ERC environment..."

    # LAYOUT_FILE — GDS/OASIS input layout
    if {[info exists pv(input,gds)] && $pv(input,gds) ne ""} {
        set ::env(LAYOUT_FILE) $pv(input,gds)
        handle_info "  LAYOUT_FILE: $pv(input,gds)"
    } elseif {[info exists pv(input,gds_file)] && $pv(input,gds_file) ne ""} {
        set ::env(LAYOUT_FILE) $pv(input,gds_file)
        handle_info "  LAYOUT_FILE: $pv(input,gds_file)"
    } else {
        handle_error "pv(input,gds) not set — cannot run ERC"
    }

    # LAYOUT_PRIMARY — top cell name
    if {[info exists pv(common,top_cell)] && $pv(common,top_cell) ne ""} {
        set ::env(LAYOUT_PRIMARY) $pv(common,top_cell)
    } elseif {[info exists project(top_module)] && $project(top_module) ne ""} {
        set ::env(LAYOUT_PRIMARY) $project(top_module)
    }
    if {[info exists ::env(LAYOUT_PRIMARY)]} {
        handle_info "  LAYOUT_PRIMARY: $::env(LAYOUT_PRIMARY)"
    }

    # RESULTS_DB
    set ::env(RESULTS_DB) "$::WORK_DIR/results/erc"
    file mkdir $::env(RESULTS_DB)
    handle_info "  RESULTS_DB: $::env(RESULTS_DB)"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Run Calibre ERC (uses DRC engine with ERC-specific runset)
# ═══════════════════════════════════════════════════════════════════════════════
flow_proc run_erc_checks {
    global pv

    handle_info "Running Calibre ERC..."

    # Resolve runset
    set runset ""
    if {[info exists pv(erc,runset)] && $pv(erc,runset) ne ""} {
        set runset $pv(erc,runset)
    } elseif {[info exists pv(input,rule_deck_erc)] && $pv(input,rule_deck_erc) ne ""} {
        set runset $pv(input,rule_deck_erc)
    }
    if {$runset eq "" || ![file exists $runset]} {
        handle_error "ERC runset not found: '$runset' — set pv(erc,runset) in user_config"
    }

    # Build command — ERC uses the DRC engine with an ERC-specific runset
    set num_cpus [expr {[info exists pv(erc,num_cpus)] ? $pv(erc,num_cpus) : 4}]

    set calibre_cmd "calibre -drc -hier -64 -turbo $num_cpus"
    append calibre_cmd " $runset"

    file mkdir "$::WORK_DIR/results/erc"
    file mkdir "$::REPORTS_DIR"

    handle_info "  CMD: $calibre_cmd"
    handle_info "  Log: $::WORK_DIR/results/erc/erc.log"

    if {[catch {exec {*}$calibre_cmd >& "$::WORK_DIR/results/erc/erc.log"} result]} {
        handle_warning "Calibre ERC returned non-zero (may have violations): $result"
    }
    handle_info "  ERC run completed"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Generate ERC summary report
# ═══════════════════════════════════════════════════════════════════════════════
flow_proc generate_erc_report {
    global pv project tech

    handle_info "Generating ERC report..."

    set rpt_file "$::REPORTS_DIR/erc_results.rpt"
    set rpt [open $rpt_file "w"]
    puts $rpt "═══════════════════════════════════════════════════════════════════════════════"
    puts $rpt "CBflow PV — ERC Results (Siemens Calibre)"
    puts $rpt "═══════════════════════════════════════════════════════════════════════════════"
    puts $rpt "Generated: [expr {[catch {clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}} _ts] ? "epoch [clock seconds]" : $_ts}]"
    if {[info exists project(top_module)]} { puts $rpt "Design: $project(top_module)" }
    if {[info exists tech(node)]} { puts $rpt "Technology: $tech(node)" }
    puts $rpt "Tool: Siemens Calibre ERC (via DRC engine)"
    if {[info exists pv(erc,runset)]} { puts $rpt "Runset: $pv(erc,runset)" }
    puts $rpt ""

    # Parse ERC results from log
    set erc_log "$::WORK_DIR/results/erc/erc.log"
    if {[file exists $erc_log]} {
        set f [open $erc_log "r"]
        set content [read $f]
        close $f
        set total_violations 0
        foreach line [split $content "\n"] {
            if {[regexp -nocase {TOTAL.*Results.*?(\d+)} $line -> count]} {
                set total_violations $count
            }
        }
        puts $rpt "Total ERC violations: $total_violations"
    } else {
        puts $rpt "ERC log not found — check execution"
    }

    puts $rpt ""
    puts $rpt "Results DB: $::WORK_DIR/results/erc/"
    puts $rpt "═══════════════════════════════════════════════════════════════════════════════"
    close $rpt

    # Copy as mandatory output
    file copy -force $rpt_file "$::WORK_DIR/results/erc/erc.rpt"
    handle_info "  ERC report: $rpt_file"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Execute
# ═══════════════════════════════════════════════════════════════════════════════
flow_exec_all
handle_info "Calibre ERC completed: $DESIGN_NAME"
exit
