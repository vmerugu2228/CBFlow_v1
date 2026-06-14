#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow PV XOR — Siemens Calibre
# Compares pre-fill vs post-fill layouts using calibrediff
# ═══════════════════════════════════════════════════════════════════════════════

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "PV"
set STAGE_NAME "xor"
set NODE_NAME "${STAGE_NAME}1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME


# ── Design name (resolve from pv(...) or flow(...)) ──────────────────────
set DESIGN_NAME [expr {[info exists pv(common,design_name)] ? $pv(common,design_name) :
                       [expr {[info exists flow(design_name)] ? $flow(design_name) : "design"}]}]
set ::DESIGN_NAME $DESIGN_NAME
# ═══════════════════════════════════════════════════════════════════════════════
# Setup XOR environment
# ═══════════════════════════════════════════════════════════════════════════════
flow_proc setup_xor_environment {
    global pv project tech
    set run_dir $::env(CBFLOW_RUN_DIR)

    handle_info "Setting up Calibre XOR environment..."

    # Pre-fill layout (original GDS input)
    set ::_pre_fill ""
    if {[info exists pv(input,gds)] && $pv(input,gds) ne ""} {
        set ::_pre_fill $pv(input,gds)
    } elseif {[info exists pv(input,gds_file)] && $pv(input,gds_file) ne ""} {
        set ::_pre_fill $pv(input,gds_file)
    }
    if {$::_pre_fill ne ""} {
        handle_info "  Pre-fill layout: $::_pre_fill"
    } else {
        handle_error "pv(input,gds) not set — cannot run XOR"
    }

    # Post-fill layout (output from fill stage)
    set ::_post_fill "$run_dir/work/PV/fill1/results/${::DESIGN_NAME}.filled.gds"
    if {[file exists $::_post_fill]} {
        handle_info "  Post-fill layout: $::_post_fill"
    } else {
        handle_info "  Post-fill layout: $::_post_fill (not yet generated)"
    }

    # Top cell
    set ::_top_cell ""
    if {[info exists pv(common,top_cell)] && $pv(common,top_cell) ne ""} {
        set ::_top_cell $pv(common,top_cell)
    } elseif {[info exists project(top_module)] && $project(top_module) ne ""} {
        set ::_top_cell $project(top_module)
    }
    if {$::_top_cell ne ""} {
        handle_info "  Top cell: $::_top_cell"
    }

    file mkdir "$::WORK_DIR/results/xor"
    file mkdir "$::REPORTS_DIR"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Run XOR comparison
# ═══════════════════════════════════════════════════════════════════════════════
flow_proc run_xor_check {
    global pv

    handle_info "Running Calibre XOR comparison..."

    # Option 1: Use XOR-specific runset with calibre -drc
    set xor_runset ""
    if {[info exists pv(xor,runset)] && $pv(xor,runset) ne ""} {
        set xor_runset $pv(xor,runset)
    }

    if {$xor_runset ne "" && [file exists $xor_runset]} {
        # Runset-based XOR — set env vars for the runset
        set ::env(LAYOUT_FILE) $::_pre_fill
        set ::env(LAYOUT_FILE2) $::_post_fill
        if {$::_top_cell ne ""} {
            set ::env(LAYOUT_PRIMARY) $::_top_cell
        }
        set ::env(RESULTS_DB) "$::WORK_DIR/results/xor"

        set num_cpus [expr {[info exists pv(xor,num_cpus)] ? $pv(xor,num_cpus) : 4}]
        set calibre_cmd "calibre -drc -hier -64 -turbo $num_cpus $xor_runset"

        handle_info "  CMD: $calibre_cmd"
        if {[catch {exec {*}$calibre_cmd >& "$::WORK_DIR/results/xor/xor.log"} result]} {
            handle_warning "Calibre XOR returned non-zero: $result"
        }
    } else {
        # calibrediff-based XOR — direct GDS comparison
        set xor_output "$::WORK_DIR/results/xor/${::DESIGN_NAME}_xor.gds"

        set calibre_cmd "calibrediff $::_pre_fill $::_post_fill"
        if {$::_top_cell ne ""} {
            append calibre_cmd " -cell $::_top_cell"
        }
        append calibre_cmd " -xor -gds $xor_output"

        handle_info "  CMD: $calibre_cmd"
        if {[catch {exec {*}$calibre_cmd >& "$::WORK_DIR/results/xor/xor.log"} result]} {
            handle_warning "calibrediff returned non-zero: $result"
        }
    }

    handle_info "  XOR comparison completed"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Generate XOR summary report
# ═══════════════════════════════════════════════════════════════════════════════
flow_proc generate_xor_report {
    global pv project tech

    handle_info "Generating XOR report..."

    set rpt_file "$::REPORTS_DIR/${::DESIGN_NAME}_xor_summary.rpt"
    set rpt [open $rpt_file "w"]
    puts $rpt "═══════════════════════════════════════════════════════════════════════════════"
    puts $rpt "CBflow PV — XOR Results (Siemens Calibre)"
    puts $rpt "═══════════════════════════════════════════════════════════════════════════════"
    puts $rpt "Generated: [expr {[catch {clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}} _ts] ? "epoch [clock seconds]" : $_ts}]"
    if {[info exists project(top_module)]} { puts $rpt "Design: $project(top_module)" }
    if {[info exists tech(node)]} { puts $rpt "Technology: $tech(node)" }
    puts $rpt "Tool: Siemens Calibre XOR (calibrediff)"
    puts $rpt ""
    puts $rpt "Pre-fill layout:  $::_pre_fill"
    puts $rpt "Post-fill layout: $::_post_fill"
    puts $rpt ""

    # Parse XOR log for differences
    set xor_log "$::WORK_DIR/results/xor/xor.log"
    set xor_status "UNKNOWN"
    if {[file exists $xor_log]} {
        set f [open $xor_log "r"]
        set content [read $f]
        close $f
        if {[string match "*no differences*" [string tolower $content]] ||
            [string match "*identical*" [string tolower $content]]} {
            set xor_status "CLEAN (no differences)"
        } elseif {[string match "*difference*" [string tolower $content]]} {
            set xor_status "DIFFERENCES FOUND"
        }
    }

    puts $rpt "XOR Status: $xor_status"
    puts $rpt ""
    puts $rpt "Results: $::WORK_DIR/results/xor/"
    puts $rpt "═══════════════════════════════════════════════════════════════════════════════"
    close $rpt
    handle_info "  XOR report: $rpt_file (Status: $xor_status)"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Execute
# ═══════════════════════════════════════════════════════════════════════════════
flow_exec_all
handle_info "Calibre XOR completed: $DESIGN_NAME"
exit
