#!/usr/bin/env tclsh
# CBflow PV XOR check - Synopsys ICV

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
# XOR: Compare pre-fill vs post-fill layouts
# ═══════════════════════════════════════════════════════════════════════════════
flow_proc run_xor_check {
    handle_info "Running XOR comparison..."

    set lib_format [expr {[info exists pv(icv,library_format)] ? $pv(icv,library_format) : "GDSII"}]
    set num_cpus [expr {[info exists pv(icv,num_cpus)] ? $pv(icv,num_cpus) : 8}]

    # Pre-fill layout (original input)
    set pre_fill ""
    if {[info exists pv(input,gds_file)]} {
        set pre_fill $pv(input,gds_file)
    }

    # Post-fill / signoff layout from the ICV chain
    # (decomp_merge_gds1 → fill_merge_gds1). ICV producers write bare filenames
    # (signoff_layout.gds, fill_merged.gds) — the ${DESIGN_NAME}_ prefix
    # convention is Calibre-only, so xor_calibre.tcl still uses prefixed names.
    set _run_dir $::env(CBFLOW_RUN_DIR)
    set post_fill "$_run_dir/work/PV/decomp_merge_gds1/results/signoff_layout.gds"
    if {![file exists $post_fill]} {
        set post_fill "$_run_dir/work/PV/fill_merge_gds1/results/fill_merged.gds"
    }

    if {$pre_fill ne "" && [file exists $pre_fill]} {
        handle_info "  Pre-fill:  [file tail $pre_fill]"
    } else {
        handle_warning "  Pre-fill layout not found"
    }

    if {[file exists $post_fill]} {
        handle_info "  Post-fill: [file tail $post_fill]"
    } else {
        handle_info "  Post-fill not yet generated (will be available after fill stage)"
    }

    # ICV XOR command
    # icv -dp $num_cpus -c $DESIGN_NAME -i $pre_fill -i2 $post_fill \
    #     -f $lib_format -xor -vue \
    #     -o $WORK_DIR/${DESIGN_NAME}_xor_results.gds

    handle_info "  CMD: icv -dp $num_cpus -c $::DESIGN_NAME -xor -i <pre> -i2 <post>"

    # NOTE: the actual `icv -xor` invocation is not wired here yet — the
    # ICV command line above is a comment for future implementation. We
    # therefore cannot honestly report "0 (clean)". Previously the report
    # hard-coded that clean status, which made pv_xor_clean pass at
    # PV_SIGNOFF whether or not the check ever ran — a silent-PASS. Now
    # emit N/A so metric-parsing consumers report metric-not-found
    # instead of interpreting the missing tool as success. When ICV
    # `-xor` is wired for real, parse actual output and replace the N/A
    # with the numeric diff count.
    set _xor_diffs "N/A (icv -xor not yet wired)"
    if {$pre_fill eq "" || ![file exists $pre_fill]} {
        set _xor_diffs "N/A (pre-fill layout missing)"
    } elseif {![file exists $post_fill]} {
        set _xor_diffs "N/A (post-fill layout missing)"
    }

    # Generate XOR summary report
    set rpt [open "$::REPORTS_DIR/${::DESIGN_NAME}_xor_summary.rpt" "w"]
    puts $rpt "═══════════════════════════════════════════════════════"
    puts $rpt "  XOR Check Summary: $::DESIGN_NAME"
    puts $rpt "  Generated: [expr {[catch {clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}} _ts] ? "epoch [clock seconds]" : $_ts}]"
    puts $rpt "═══════════════════════════════════════════════════════"
    puts $rpt ""
    puts $rpt "  Pre-fill layout:  $pre_fill"
    puts $rpt "  Post-fill layout: $post_fill"
    puts $rpt "  XOR differences:  $_xor_diffs"
    puts $rpt ""
    close $rpt
    handle_info "  XOR report: $::REPORTS_DIR/${::DESIGN_NAME}_xor_summary.rpt"
}

flow_exec_all
handle_info "ICV XOR Check completed: $DESIGN_NAME"
exit
