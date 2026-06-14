#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow PV LVS — Siemens Calibre
# Invokes Calibre LVS with foundry SVRF runset
# ═══════════════════════════════════════════════════════════════════════════════

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "PV"
set STAGE_NAME "lvs"
set NODE_NAME "${STAGE_NAME}1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME


# ── Design name (resolve from pv(...) or flow(...)) ──────────────────────
set DESIGN_NAME [expr {[info exists pv(common,design_name)] ? $pv(common,design_name) :
                       [expr {[info exists flow(design_name)] ? $flow(design_name) : "design"}]}]
set ::DESIGN_NAME $DESIGN_NAME
# ═══════════════════════════════════════════════════════════════════════════════
# Setup Calibre LVS environment variables for SVRF runset
# ═══════════════════════════════════════════════════════════════════════════════
flow_proc setup_lvs_environment {
    global pv project tech

    handle_info "Setting up Calibre LVS environment..."

    # LAYOUT_FILE — GDS/OASIS input layout
    if {[info exists pv(input,gds)] && $pv(input,gds) ne ""} {
        set ::env(LAYOUT_FILE) $pv(input,gds)
        handle_info "  LAYOUT_FILE: $pv(input,gds)"
    } elseif {[info exists pv(input,gds_file)] && $pv(input,gds_file) ne ""} {
        set ::env(LAYOUT_FILE) $pv(input,gds_file)
        handle_info "  LAYOUT_FILE: $pv(input,gds_file)"
    } else {
        handle_error "pv(input,gds) not set — cannot run LVS"
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

    # SOURCE_PATH — source netlist for LVS comparison
    if {[info exists pv(input,netlist)] && $pv(input,netlist) ne ""} {
        set ::env(SOURCE_PATH) $pv(input,netlist)
        handle_info "  SOURCE_PATH: $pv(input,netlist)"
    } elseif {[info exists pv(input,lvs_reference_netlist)] && $pv(input,lvs_reference_netlist) ne ""} {
        set ::env(SOURCE_PATH) $pv(input,lvs_reference_netlist)
        handle_info "  SOURCE_PATH: $pv(input,lvs_reference_netlist)"
    } else {
        handle_error "pv(input,netlist) not set — cannot run LVS"
    }

    # SOURCE_PRIMARY — top cell in netlist (same as layout top cell)
    if {[info exists ::env(LAYOUT_PRIMARY)]} {
        set ::env(SOURCE_PRIMARY) $::env(LAYOUT_PRIMARY)
    }

    # RESULTS_DB — LVS results database output path
    set ::env(RESULTS_DB) "$::WORK_DIR/results/lvs"
    file mkdir $::env(RESULTS_DB)
    handle_info "  RESULTS_DB: $::env(RESULTS_DB)"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Run Calibre LVS
# ═══════════════════════════════════════════════════════════════════════════════
flow_proc run_lvs_comparison {
    global pv

    handle_info "Running Calibre LVS..."

    # Resolve runset
    set runset ""
    if {[info exists pv(lvs,runset)] && $pv(lvs,runset) ne ""} {
        set runset $pv(lvs,runset)
    } elseif {[info exists pv(input,rule_deck_lvs)] && $pv(input,rule_deck_lvs) ne ""} {
        set runset $pv(input,rule_deck_lvs)
    }
    if {$runset eq "" || ![file exists $runset]} {
        handle_error "LVS runset not found: '$runset' — set pv(lvs,runset) in user_config"
    }

    # Build command
    set num_cpus [expr {[info exists pv(lvs,num_cpus)] ? $pv(lvs,num_cpus) : 8}]
    set turbo [expr {[info exists pv(lvs,turbo_mode)] && $pv(lvs,turbo_mode) eq "true"}]

    set calibre_cmd "calibre -lvs -hier -64"
    if {$turbo} {
        append calibre_cmd " -turbo $num_cpus"
    }
    if {[info exists pv(lvs,hcell_file)] && $pv(lvs,hcell_file) ne "" && [file exists $pv(lvs,hcell_file)]} {
        append calibre_cmd " -hcell $pv(lvs,hcell_file)"
    }
    if {[info exists pv(lvs,spice_netlist)] && $pv(lvs,spice_netlist) ne ""} {
        set ::env(SOURCE_PATH) $pv(lvs,spice_netlist)
    }
    append calibre_cmd " $runset"

    file mkdir "$::WORK_DIR/results/lvs"
    file mkdir "$::REPORTS_DIR"

    handle_info "  CMD: $calibre_cmd"
    handle_info "  Log: $::WORK_DIR/results/lvs/lvs.log"

    if {[catch {exec {*}$calibre_cmd >& "$::WORK_DIR/results/lvs/lvs.log"} result]} {
        handle_warning "Calibre LVS returned non-zero (may have mismatches): $result"
    }
    handle_info "  LVS run completed"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Generate LVS summary report
# ═══════════════════════════════════════════════════════════════════════════════
flow_proc generate_lvs_report {
    global pv project tech

    handle_info "Generating LVS report..."

    set rpt_file "$::REPORTS_DIR/lvs_results.rpt"
    set rpt [open $rpt_file "w"]
    puts $rpt "═══════════════════════════════════════════════════════════════════════════════"
    puts $rpt "CBflow PV — LVS Results (Siemens Calibre)"
    puts $rpt "═══════════════════════════════════════════════════════════════════════════════"
    puts $rpt "Generated: [expr {[catch {clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}} _ts] ? "epoch [clock seconds]" : $_ts}]"
    if {[info exists project(top_module)]} { puts $rpt "Design: $project(top_module)" }
    if {[info exists tech(node)]} { puts $rpt "Technology: $tech(node)" }
    puts $rpt "Tool: Siemens Calibre LVS"
    if {[info exists pv(lvs,runset)]} { puts $rpt "Runset: $pv(lvs,runset)" }
    puts $rpt ""

    # Parse LVS result from log
    set lvs_log "$::WORK_DIR/results/lvs/lvs.log"
    set lvs_status "UNKNOWN"
    if {[file exists $lvs_log]} {
        set f [open $lvs_log "r"]
        set content [read $f]
        close $f
        if {[string match "*CORRECT*" $content]} {
            set lvs_status "CORRECT"
        } elseif {[string match "*INCORRECT*" $content]} {
            set lvs_status "INCORRECT"
        }
    }
    puts $rpt "LVS Status: $lvs_status"
    puts $rpt ""
    puts $rpt "Results DB: $::WORK_DIR/results/lvs/"
    puts $rpt "═══════════════════════════════════════════════════════════════════════════════"
    close $rpt

    # Copy as mandatory output
    file copy -force $rpt_file "$::WORK_DIR/results/lvs/lvs.rpt"
    handle_info "  LVS report: $rpt_file (Status: $lvs_status)"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Execute
# ═══════════════════════════════════════════════════════════════════════════════
flow_exec_all
handle_info "Calibre LVS completed: $DESIGN_NAME"
exit
