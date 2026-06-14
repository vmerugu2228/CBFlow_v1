#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow PV DRC — Siemens Calibre
# Invokes Calibre DRC with foundry SVRF runset
# ═══════════════════════════════════════════════════════════════════════════════

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "PV"
set STAGE_NAME "drc"
set NODE_NAME "${STAGE_NAME}1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME


# ── Design name (resolve from pv(...) or flow(...)) ──────────────────────
set DESIGN_NAME [expr {[info exists pv(common,design_name)] ? $pv(common,design_name) :
                       [expr {[info exists flow(design_name)] ? $flow(design_name) : "design"}]}]
set ::DESIGN_NAME $DESIGN_NAME
# ═══════════════════════════════════════════════════════════════════════════════
# Setup Calibre DRC environment variables for SVRF runset
# ═══════════════════════════════════════════════════════════════════════════════
flow_proc setup_drc_environment {
    global pv project tech

    handle_info "Setting up Calibre DRC environment..."

    # LAYOUT_FILE — GDS/OASIS input layout
    if {[info exists pv(input,gds)] && $pv(input,gds) ne ""} {
        set ::env(LAYOUT_FILE) $pv(input,gds)
        handle_info "  LAYOUT_FILE: $pv(input,gds)"
    } elseif {[info exists pv(input,gds_file)] && $pv(input,gds_file) ne ""} {
        set ::env(LAYOUT_FILE) $pv(input,gds_file)
        handle_info "  LAYOUT_FILE: $pv(input,gds_file)"
    } else {
        handle_error "pv(input,gds) not set — cannot run DRC"
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

    # RESULTS_DB — DRC results database output path
    set ::env(RESULTS_DB) "$::WORK_DIR/results/drc"
    file mkdir $::env(RESULTS_DB)
    handle_info "  RESULTS_DB: $::env(RESULTS_DB)"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Run Calibre DRC
# ═══════════════════════════════════════════════════════════════════════════════
flow_proc run_drc_checks {
    global pv

    handle_info "Running Calibre DRC..."

    # Resolve runset
    set runset ""
    if {[info exists pv(drc,runset)] && $pv(drc,runset) ne ""} {
        set runset $pv(drc,runset)
    } elseif {[info exists pv(input,rule_deck_drc)] && $pv(input,rule_deck_drc) ne ""} {
        set runset $pv(input,rule_deck_drc)
    }
    if {$runset eq "" || ![file exists $runset]} {
        handle_error "DRC runset not found: '$runset' — set pv(drc,runset) in user_config"
    }

    # Build command
    set num_cpus [expr {[info exists pv(drc,num_cpus)] ? $pv(drc,num_cpus) : 8}]
    set turbo [expr {[info exists pv(drc,turbo_mode)] && $pv(drc,turbo_mode) eq "true"}]

    set calibre_cmd "calibre -drc -hier -64"
    if {$turbo} {
        append calibre_cmd " -turbo $num_cpus"
    }
    if {[info exists pv(drc,hcell_file)] && $pv(drc,hcell_file) ne "" && [file exists $pv(drc,hcell_file)]} {
        append calibre_cmd " -hcell $pv(drc,hcell_file)"
    }
    append calibre_cmd " $runset"

    file mkdir "$::WORK_DIR/results/drc"
    file mkdir "$::REPORTS_DIR"

    handle_info "  CMD: $calibre_cmd"
    handle_info "  Log: $::WORK_DIR/results/drc/drc.log"

    if {[catch {exec {*}$calibre_cmd >& "$::WORK_DIR/results/drc/drc.log"} result]} {
        handle_warning "Calibre DRC returned non-zero (may have violations): $result"
    }
    handle_info "  DRC run completed"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Run Calibre Antenna DRC (optional)
# ═══════════════════════════════════════════════════════════════════════════════
flow_proc run_antenna_check {
    global pv

    set antenna_runset ""
    if {[info exists pv(drc,antenna_runset)] && $pv(drc,antenna_runset) ne ""} {
        set antenna_runset $pv(drc,antenna_runset)
    }
    if {$antenna_runset eq "" || ![file exists $antenna_runset]} {
        handle_info "Antenna runset not specified — skipping antenna check"
        return
    }

    handle_info "Running Calibre Antenna DRC..."
    set num_cpus [expr {[info exists pv(drc,num_cpus)] ? $pv(drc,num_cpus) : 8}]

    set calibre_cmd "calibre -drc -hier -64 -turbo $num_cpus $antenna_runset"
    handle_info "  CMD: $calibre_cmd"

    if {[catch {exec {*}$calibre_cmd >& "$::WORK_DIR/results/drc/antenna.log"} result]} {
        handle_warning "Antenna DRC returned non-zero: $result"
    }
    handle_info "  Antenna check completed"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Generate DRC summary report
# ═══════════════════════════════════════════════════════════════════════════════
flow_proc generate_drc_report {
    global pv project tech

    handle_info "Generating DRC report..."

    set rpt_file "$::REPORTS_DIR/drc_results.rpt"
    set rpt [open $rpt_file "w"]
    puts $rpt "═══════════════════════════════════════════════════════════════════════════════"
    puts $rpt "CBflow PV — DRC Results (Siemens Calibre)"
    puts $rpt "═══════════════════════════════════════════════════════════════════════════════"
    puts $rpt "Generated: [expr {[catch {clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}} _ts] ? "epoch [clock seconds]" : $_ts}]"
    if {[info exists project(top_module)]} { puts $rpt "Design: $project(top_module)" }
    if {[info exists tech(node)]} { puts $rpt "Technology: $tech(node)" }
    puts $rpt "Tool: Siemens Calibre DRC"
    if {[info exists pv(drc,runset)]} { puts $rpt "Runset: $pv(drc,runset)" }
    puts $rpt ""

    # Parse DRC summary from log if available
    set drc_log "$::WORK_DIR/results/drc/drc.log"
    if {[file exists $drc_log]} {
        set f [open $drc_log "r"]
        set content [read $f]
        close $f
        # Look for violation summary lines
        set total_violations 0
        foreach line [split $content "\n"] {
            if {[regexp -nocase {TOTAL.*Results.*?(\d+)} $line -> count]} {
                set total_violations $count
            }
            if {[regexp -nocase {TOTAL DRC Results.*?(\d+)} $line -> count]} {
                set total_violations $count
            }
        }
        puts $rpt "Total DRC violations: $total_violations"
    } else {
        puts $rpt "DRC log not found — check execution"
    }

    puts $rpt ""
    puts $rpt "Results DB: $::WORK_DIR/results/drc/"
    puts $rpt "═══════════════════════════════════════════════════════════════════════════════"
    close $rpt

    # Copy as mandatory output
    file copy -force $rpt_file "$::WORK_DIR/results/drc/drc.rpt"
    handle_info "  DRC report: $rpt_file"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Execute
# ═══════════════════════════════════════════════════════════════════════════════
flow_exec_all
handle_info "Calibre DRC completed: $DESIGN_NAME"
exit
