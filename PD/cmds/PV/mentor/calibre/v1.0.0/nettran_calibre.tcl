#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow PV nettran — Siemens Calibre v2lvs (Calibre nmPlatform 2024.x)
# Translates the gate-level Verilog netlist into a hierarchical SPICE deck that
# Calibre nmLVS consumes. Reference: Calibre Verilog-to-SPICE User's Manual.
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$::env(CBFLOW_RUN_DIR)/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "PV"
set STAGE_NAME "nettran"
set NODE_NAME "${STAGE_NAME}1"

source "$::env(CBFLOW_RUN_DIR)/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$::env(CBFLOW_RUN_DIR)/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $::env(CBFLOW_RUN_DIR) $FLOW_TYPE $NODE_NAME

set DESIGN_NAME [expr {[info exists pv(common,design_name)] ? $pv(common,design_name) :
                       [expr {[info exists flow(design_name)] ? $flow(design_name) : "design"}]}]
set ::DESIGN_NAME $DESIGN_NAME

flow_proc configure_nettran {
    global pv tech project
    handle_info "Configuring netlist translation (v2lvs)..."

    if {[info exists pv(input,netlist)] && $pv(input,netlist) ne ""} {
        set ::nettran_source $pv(input,netlist)
    } else {
        handle_error "No source netlist — set pv(input,netlist) in user_config"
        return
    }

    # Standard-cell + macro SPICE models required for hierarchical translation.
    # v2lvs uses -s <sourcedeck> to bring in existing SPICE subckts so it
    # doesn't fabricate empty ones for cells it doesn't recognise.
    # SPICE source-deck resolution (matches DRC's runset convention):
    #   pv(nettran,source_decks) → pv(input,spice_stdcell) → empty
    set ::nettran_source_decks [list]
    if {[info exists pv(nettran,source_decks)] && $pv(nettran,source_decks) ne ""} {
        set ::nettran_source_decks $pv(nettran,source_decks)
    } elseif {[info exists pv(input,spice_stdcell)] && $pv(input,spice_stdcell) ne ""} {
        lappend ::nettran_source_decks $pv(input,spice_stdcell)
    }

    # Explicit power/ground nets (default VDD/VSS unless overridden by design).
    set ::nettran_power  [expr {[info exists pv(nettran,power)]  ? $pv(nettran,power)  : "VDD"}]
    set ::nettran_ground [expr {[info exists pv(nettran,ground)] ? $pv(nettran,ground) : "VSS"}]

    # Top cell to match against the Verilog top module.
    if {[info exists pv(common,top_cell)]} {
        set ::nettran_top $pv(common,top_cell)
    } elseif {[info exists project(top_module)]} {
        set ::nettran_top $project(top_module)
    } else {
        set ::nettran_top $::DESIGN_NAME
    }

    set ::nettran_out "$::WORK_DIR/results/${::DESIGN_NAME}.cdl"
    set ::nettran_log "$::env(CBFLOW_RUN_DIR)/logs/pv/nettran_calibre.log"

    handle_info "Netlist translation configuration:"
    handle_info "  Verilog:      $::nettran_source"
    handle_info "  SPICE decks:  [expr {[llength $::nettran_source_decks] == 0 ? {<none>} : $::nettran_source_decks}]"
    handle_info "  Top cell:     $::nettran_top"
    handle_info "  Power/Ground: $::nettran_power / $::nettran_ground"
    handle_info "  Output CDL:   $::nettran_out"
}

flow_proc run_nettran {
    set ::nettran_status "PASS"
    handle_info "Running netlist translation with v2lvs..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    file mkdir "$::WORK_DIR/results"
    file mkdir "$::REPORTS_DIR"
    file mkdir "$::env(CBFLOW_RUN_DIR)/logs/pv"

    # v2lvs invocation (Calibre 2024.x):
    #   v2lvs -v <verilog> -o <cdl> -c <top> -p <power> -g <ground>
    #         -s <sourcedeck1> [-s <sourcedeck2>...]  -lsp
    # -lsp expands `assign` statements as short circuits (typical for LVS).
    set cmd [list v2lvs \
                  -v $::nettran_source \
                  -o $::nettran_out \
                  -c $::nettran_top \
                  -p $::nettran_power \
                  -g $::nettran_ground \
                  -lsp]
    foreach _deck $::nettran_source_decks {
        if {[file exists $_deck]} {
            lappend cmd -s $_deck
        }
    }

    handle_info "  CMD: $cmd"
    handle_info "  Log: $::nettran_log"

    if {[catch {exec {*}$cmd >& $::nettran_log} _r]} {
        handle_warning "v2lvs failed: $_r"
        set ::nettran_status "FAIL"
    } else {
        set ::nettran_status "PASS"
        handle_info "Netlist translation completed"
    }
}

flow_proc report_nettran {
    file mkdir $::REPORTS_DIR
    set fp [open "$::REPORTS_DIR/nettran_summary.rpt" w]
    puts $fp "═══════════════════════════════════════════════════════════════════════════════"
    puts $fp "PV Netlist Translation Summary — Siemens Calibre v2lvs"
    puts $fp "═══════════════════════════════════════════════════════════════════════════════"
    puts $fp "Design:      $::DESIGN_NAME"
    puts $fp "Verilog in:  $::nettran_source"
    puts $fp "CDL out:     $::nettran_out"
    puts $fp "Top cell:    $::nettran_top"
    puts $fp "Power:       $::nettran_power"
    puts $fp "Ground:      $::nettran_ground"
    puts $fp "SPICE decks: $::nettran_source_decks"
    puts $fp "Status:      $::nettran_status"
    close $fp
    handle_info "Report written: $::REPORTS_DIR/nettran_summary.rpt"
}

flow_proc nettran_flow {
    flow_exec configure_nettran
    flow_exec run_nettran
    flow_exec report_nettran
    if {[info exists ::nettran_status] && $::nettran_status eq "FAIL"} {
        handle_error "nettran failed — see $::REPORTS_DIR/nettran_summary.rpt"
    }
}
if {[info exists argv0] && $argv0 eq [info script]} { flow_exec nettran_flow } else { puts " PV nettran procedures loaded" }
exit
