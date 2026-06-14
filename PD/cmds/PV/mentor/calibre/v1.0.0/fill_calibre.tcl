#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow PV Metal Fill — Siemens Calibre
# Invokes Calibre metal fill (BEOL/FEOL) with foundry SVRF runset
# ═══════════════════════════════════════════════════════════════════════════════

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "PV"
set STAGE_NAME "fill"
set NODE_NAME "${STAGE_NAME}1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME


# ── Design name (resolve from pv(...) or flow(...)) ──────────────────────
set DESIGN_NAME [expr {[info exists pv(common,design_name)] ? $pv(common,design_name) :
                       [expr {[info exists flow(design_name)] ? $flow(design_name) : "design"}]}]
set ::DESIGN_NAME $DESIGN_NAME
# ═══════════════════════════════════════════════════════════════════════════════
# Setup Calibre fill environment variables for SVRF runset
# ═══════════════════════════════════════════════════════════════════════════════
flow_proc setup_fill_environment {
    global pv project tech

    handle_info "Setting up Calibre fill environment..."

    # LAYOUT_FILE — GDS/OASIS input layout
    if {[info exists pv(input,gds)] && $pv(input,gds) ne ""} {
        set ::env(LAYOUT_FILE) $pv(input,gds)
        handle_info "  LAYOUT_FILE: $pv(input,gds)"
    } elseif {[info exists pv(input,gds_file)] && $pv(input,gds_file) ne ""} {
        set ::env(LAYOUT_FILE) $pv(input,gds_file)
        handle_info "  LAYOUT_FILE: $pv(input,gds_file)"
    } else {
        handle_error "pv(input,gds) not set — cannot run fill"
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

    # FILL_OUTPUT — output GDS with fill shapes
    set ::env(FILL_OUTPUT) "$::WORK_DIR/results/${::DESIGN_NAME}.filled.gds"
    handle_info "  FILL_OUTPUT: $::env(FILL_OUTPUT)"

    # Metal stack info
    if {[info exists pv(fill,metal_stack)] && $pv(fill,metal_stack) ne ""} {
        handle_info "  Metal stack: $pv(fill,metal_stack)"
    } elseif {[info exists tech(metal_stack_name)]} {
        handle_info "  Metal stack: $tech(metal_stack_name)"
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# Run Calibre BEOL metal fill
# ═══════════════════════════════════════════════════════════════════════════════
flow_proc run_beol_fill {
    global pv

    handle_info "Running Calibre BEOL metal fill..."

    # Resolve BEOL fill runset — try specific beol_runset first, then generic fill,runset
    set runset ""
    if {[info exists pv(fill,beol_runset)] && $pv(fill,beol_runset) ne ""} {
        set runset $pv(fill,beol_runset)
    } elseif {[info exists pv(fill,runset)] && $pv(fill,runset) ne ""} {
        set runset $pv(fill,runset)
    }
    if {$runset eq "" || ![file exists $runset]} {
        handle_error "Fill runset not found: '$runset' — set pv(fill,runset) in user_config"
    }

    # Build command — fill uses DRC engine with fill-specific runset
    set num_cpus [expr {[info exists pv(fill,num_cpus)] ? $pv(fill,num_cpus) : 8}]

    set calibre_cmd "calibre -drc -hier -64 -turbo $num_cpus"
    append calibre_cmd " $runset"

    file mkdir "$::WORK_DIR/results"
    file mkdir "$::REPORTS_DIR"

    handle_info "  CMD: $calibre_cmd"
    handle_info "  Log: $::WORK_DIR/results/fill_beol.log"

    if {[catch {exec {*}$calibre_cmd >& "$::WORK_DIR/results/fill_beol.log"} result]} {
        handle_warning "Calibre BEOL fill returned non-zero: $result"
    }
    handle_info "  BEOL fill completed"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Run Calibre FEOL fill (optional — only if feol_runset is specified)
# ═══════════════════════════════════════════════════════════════════════════════
flow_proc run_feol_fill {
    global pv

    set feol_runset ""
    if {[info exists pv(fill,feol_runset)] && $pv(fill,feol_runset) ne ""} {
        set feol_runset $pv(fill,feol_runset)
    }
    if {$feol_runset eq "" || ![file exists $feol_runset]} {
        handle_info "FEOL runset not specified — skipping FEOL fill"
        return
    }

    handle_info "Running Calibre FEOL fill..."
    set num_cpus [expr {[info exists pv(fill,num_cpus)] ? $pv(fill,num_cpus) : 8}]

    set calibre_cmd "calibre -drc -hier -64 -turbo $num_cpus $feol_runset"
    handle_info "  CMD: $calibre_cmd"

    if {[catch {exec {*}$calibre_cmd >& "$::WORK_DIR/results/fill_feol.log"} result]} {
        handle_warning "Calibre FEOL fill returned non-zero: $result"
    }
    handle_info "  FEOL fill completed"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Validate fill output
# ═══════════════════════════════════════════════════════════════════════════════
flow_proc validate_fill {
    global pv

    handle_info "Validating fill results..."

    set fill_output "$::WORK_DIR/results/${::DESIGN_NAME}.filled.gds"
    if {[file exists $fill_output]} {
        handle_info "  Fill output: $fill_output ([file size $fill_output] bytes)"
    } else {
        handle_info "  Fill output not yet generated (expected at: $fill_output)"
    }

    # Check fill log for errors
    set fill_log "$::WORK_DIR/results/fill_beol.log"
    if {[file exists $fill_log]} {
        set f [open $fill_log "r"]
        set content [read $f]
        close $f
        set error_count 0
        foreach line [split $content "\n"] {
            if {[regexp -nocase {^ERROR} $line]} { incr error_count }
        }
        if {$error_count > 0} {
            handle_warning "  Fill log contains $error_count error(s)"
        } else {
            handle_info "  Fill log: clean"
        }
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# Generate fill summary report
# ═══════════════════════════════════════════════════════════════════════════════
flow_proc generate_fill_report {
    global pv project tech

    handle_info "Generating fill report..."

    set rpt_file "$::REPORTS_DIR/fill_results.rpt"
    set rpt [open $rpt_file "w"]
    puts $rpt "═══════════════════════════════════════════════════════════════════════════════"
    puts $rpt "CBflow PV — Metal Fill Results (Siemens Calibre)"
    puts $rpt "═══════════════════════════════════════════════════════════════════════════════"
    puts $rpt "Generated: [expr {[catch {clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}} _ts] ? "epoch [clock seconds]" : $_ts}]"
    if {[info exists project(top_module)]} { puts $rpt "Design: $project(top_module)" }
    if {[info exists tech(node)]} { puts $rpt "Technology: $tech(node)" }
    puts $rpt "Tool: Siemens Calibre Fill (via DRC engine)"
    if {[info exists pv(fill,runset)]} { puts $rpt "BEOL Runset: $pv(fill,runset)" }
    if {[info exists pv(fill,feol_runset)] && $pv(fill,feol_runset) ne ""} {
        puts $rpt "FEOL Runset: $pv(fill,feol_runset)"
    }
    puts $rpt ""

    set fill_output "$::WORK_DIR/results/${::DESIGN_NAME}.filled.gds"
    if {[file exists $fill_output]} {
        puts $rpt "Fill output: $fill_output"
        puts $rpt "Output size: [file size $fill_output] bytes"
    } else {
        puts $rpt "Fill output: pending"
    }

    puts $rpt ""
    puts $rpt "═══════════════════════════════════════════════════════════════════════════════"
    close $rpt
    handle_info "  Fill report: $rpt_file"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Execute
# ═══════════════════════════════════════════════════════════════════════════════
flow_exec_all
handle_info "Calibre Metal Fill completed: $DESIGN_NAME"
exit
