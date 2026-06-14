#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow PV PERC — Siemens Calibre
# Invokes Calibre PERC with foundry SVRF runset
# ═══════════════════════════════════════════════════════════════════════════════

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "PV"
set STAGE_NAME "perc"
set NODE_NAME "${STAGE_NAME}1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME


# ── Design name (resolve from pv(...) or flow(...)) ──────────────────────
set DESIGN_NAME [expr {[info exists pv(common,design_name)] ? $pv(common,design_name) :
                       [expr {[info exists flow(design_name)] ? $flow(design_name) : "design"}]}]
set ::DESIGN_NAME $DESIGN_NAME
# ═══════════════════════════════════════════════════════════════════════════════
# Setup Calibre PERC environment variables for SVRF runset
# ═══════════════════════════════════════════════════════════════════════════════
flow_proc setup_perc_environment {
    global pv project tech

    handle_info "Setting up Calibre PERC environment..."

    # LAYOUT_FILE — GDS/OASIS input layout
    if {[info exists pv(input,gds)] && $pv(input,gds) ne ""} {
        set ::env(LAYOUT_FILE) $pv(input,gds)
        handle_info "  LAYOUT_FILE: $pv(input,gds)"
    } elseif {[info exists pv(input,gds_file)] && $pv(input,gds_file) ne ""} {
        set ::env(LAYOUT_FILE) $pv(input,gds_file)
        handle_info "  LAYOUT_FILE: $pv(input,gds_file)"
    } else {
        handle_error "pv(input,gds) not set — cannot run PERC"
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

    # SOURCE_PATH — source netlist for PERC (schematic-driven checks)
    if {[info exists pv(perc,spice_netlist)] && $pv(perc,spice_netlist) ne ""} {
        set ::env(SOURCE_PATH) $pv(perc,spice_netlist)
        handle_info "  SOURCE_PATH: $pv(perc,spice_netlist)"
    } elseif {[info exists pv(input,netlist)] && $pv(input,netlist) ne ""} {
        set ::env(SOURCE_PATH) $pv(input,netlist)
        handle_info "  SOURCE_PATH: $pv(input,netlist)"
    }

    # RESULTS_DB
    set ::env(RESULTS_DB) "$::WORK_DIR/results/perc"
    file mkdir $::env(RESULTS_DB)
    handle_info "  RESULTS_DB: $::env(RESULTS_DB)"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Run Calibre PERC
# ═══════════════════════════════════════════════════════════════════════════════
flow_proc run_perc_checks {
    global pv

    handle_info "Running Calibre PERC..."

    # Resolve runset
    set runset ""
    if {[info exists pv(perc,runset)] && $pv(perc,runset) ne ""} {
        set runset $pv(perc,runset)
    } elseif {[info exists pv(input,rule_deck_perc)] && $pv(input,rule_deck_perc) ne ""} {
        set runset $pv(input,rule_deck_perc)
    }
    if {$runset eq "" || ![file exists $runset]} {
        handle_error "PERC runset not found: '$runset' — set pv(perc,runset) in user_config"
    }

    # Build command
    set num_cpus [expr {[info exists pv(perc,num_cpus)] ? $pv(perc,num_cpus) : 8}]

    set calibre_cmd "calibre -perc -64 -turbo $num_cpus"
    append calibre_cmd " $runset"

    file mkdir "$::WORK_DIR/results/perc"
    file mkdir "$::REPORTS_DIR"

    handle_info "  CMD: $calibre_cmd"
    handle_info "  Log: $::WORK_DIR/results/perc/perc.log"

    if {[catch {exec {*}$calibre_cmd >& "$::WORK_DIR/results/perc/perc.log"} result]} {
        handle_warning "Calibre PERC returned non-zero (may have violations): $result"
    }
    handle_info "  PERC run completed"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Generate PERC summary report
# ═══════════════════════════════════════════════════════════════════════════════
flow_proc generate_perc_report {
    global pv project tech

    handle_info "Generating PERC report..."

    set rpt_file "$::REPORTS_DIR/perc_results.rpt"
    set rpt [open $rpt_file "w"]
    puts $rpt "═══════════════════════════════════════════════════════════════════════════════"
    puts $rpt "CBflow PV — PERC Results (Siemens Calibre)"
    puts $rpt "═══════════════════════════════════════════════════════════════════════════════"
    puts $rpt "Generated: [expr {[catch {clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}} _ts] ? "epoch [clock seconds]" : $_ts}]"
    if {[info exists project(top_module)]} { puts $rpt "Design: $project(top_module)" }
    if {[info exists tech(node)]} { puts $rpt "Technology: $tech(node)" }
    puts $rpt "Tool: Siemens Calibre PERC"
    if {[info exists pv(perc,runset)]} { puts $rpt "Runset: $pv(perc,runset)" }
    puts $rpt ""

    # Parse PERC results from log
    set perc_log "$::WORK_DIR/results/perc/perc.log"
    if {[file exists $perc_log]} {
        set f [open $perc_log "r"]
        set content [read $f]
        close $f
        set total_violations 0
        foreach line [split $content "\n"] {
            if {[regexp -nocase {TOTAL.*Results.*?(\d+)} $line -> count]} {
                set total_violations $count
            }
        }
        puts $rpt "Total PERC violations: $total_violations"
    } else {
        puts $rpt "PERC log not found — check execution"
    }

    puts $rpt ""
    puts $rpt "Results DB: $::WORK_DIR/results/perc/"
    puts $rpt "═══════════════════════════════════════════════════════════════════════════════"
    close $rpt

    # Copy as mandatory output
    file copy -force $rpt_file "$::WORK_DIR/results/perc/perc.rpt"
    handle_info "  PERC report: $rpt_file"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Execute
# ═══════════════════════════════════════════════════════════════════════════════
flow_exec_all
handle_info "Calibre PERC completed: $DESIGN_NAME"
exit
