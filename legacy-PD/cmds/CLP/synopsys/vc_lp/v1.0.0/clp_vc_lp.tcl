#!/usr/bin/env tclsh
# CBFlow CLP verification - Synopsys VC LP (FC-RM Y-2026.03)

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "CLP"
set STAGE_NAME "clp"
set NODE_NAME "${STAGE_NAME}1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# ==============================================================================
flow_proc configure_lp_checks {
    global clp project tech
    handle_info "Configuring VC LP check settings..."

    set run_dir $::env(CBFLOW_RUN_DIR)
    file mkdir $::REPORTS_DIR
    file mkdir $::OUTPUTS_DIR

    # Core app_vars from FC-RM vc_lp.tcl
    set_app_var sh_continue_on_error true
    set_app_var handle_hanging_crossover true
    set_app_var enable_local_policy_match true
    set_app_var upf_iso_filter_elements_with_applies_to ENABLE
    set_app_var enable_multi_driver_analysis true
    set_app_var implicit_scmr_pins true
    set_app_var enable_verdi_debug true

    # Optional overrides from config
    if {[info exists clp(check,continue_on_error)] && $clp(check,continue_on_error) ne ""} {
        set_app_var sh_continue_on_error $clp(check,continue_on_error)
    }
    if {[info exists clp(check,hanging_crossover)] && $clp(check,hanging_crossover) ne ""} {
        set_app_var handle_hanging_crossover $clp(check,hanging_crossover)
    }
    if {[info exists clp(check,multi_driver)] && $clp(check,multi_driver) ne ""} {
        set_app_var enable_multi_driver_analysis $clp(check,multi_driver)
    }
    if {[info exists clp(check,verdi_debug)] && $clp(check,verdi_debug) ne ""} {
        set_app_var enable_verdi_debug $clp(check,verdi_debug)
    }

    # Set link_library
    if {[info exists clp(input,link_library)] && $clp(input,link_library) ne ""} {
        set_app_var link_library $clp(input,link_library)
    } elseif {[info exists tech(lib,link_library)] && $tech(lib,link_library) ne ""} {
        set_app_var link_library $tech(lib,link_library)
    }

    handle_info "VC LP check configuration completed"
}

# ==============================================================================
# flow_proc: read_design
# Description: Read PG netlist from PNR output
# FC-RM: read_file -netlist -top $DESIGN_NAME <netlist>
# ==============================================================================
flow_proc read_design {
    global clp project tech
    handle_info "Reading design netlist..."

    set design_name $project(top_module)

    if {[info exists clp(input,reference_netlist)] && $clp(input,reference_netlist) ne ""} {
        handle_info "Reading netlist: $clp(input,reference_netlist)"
        read_file -netlist -top $design_name $clp(input,reference_netlist)
    } else {
        handle_error "clp(input,reference_netlist) not specified"
    }

    handle_info "Design netlist read completed"
}

# ==============================================================================
# flow_proc: read_power_intent
# Description: Read UPF file (golden or prime mode)
# FC-RM: read_upf with -supplemental for golden, direct for prime
# ==============================================================================
flow_proc read_power_intent {
    global clp project tech
    handle_info "Reading power intent (UPF)..."

    # Determine UPF mode: golden or prime
    set upf_mode "prime"
    if {[info exists clp(common,upf_mode)] && $clp(common,upf_mode) ne ""} {
        set upf_mode $clp(common,upf_mode)
    }

    if {![info exists clp(input,upf_file)] || $clp(input,upf_file) eq ""} {
        handle_error "clp(input,upf_file) not specified"
        return
    }

    if {$upf_mode eq "golden"} {
        # Golden UPF flow -- primary + supplemental
        handle_info "Reading UPF (golden mode): $clp(input,upf_file)"
        set read_upf_cmd "read_upf $clp(input,upf_file) -strict_check false"
        if {[info exists clp(input,supplemental_upf)] && $clp(input,supplemental_upf) ne ""} {
            lappend read_upf_cmd -supplemental $clp(input,supplemental_upf)
        }
        eval $read_upf_cmd
    } else {
        # Prime UPF flow -- single unified UPF
        handle_info "Reading UPF (prime mode): $clp(input,upf_file)"
        read_upf $clp(input,upf_file)
    }

    handle_info "Power intent loading completed"
}

# ==============================================================================
# flow_proc: verify_lp_upf
# Description: UPF syntax and semantic checks
# FC-RM: check_lp -stage upf
# ==============================================================================
flow_proc verify_lp_upf {
    global clp project
    handle_info "Running UPF syntax/semantic verification (check_lp -stage upf)..."

    check_lp -stage upf

    handle_info "UPF stage verification completed"
}

# ==============================================================================
# flow_proc: verify_lp_design
# Description: Design implementation checks (isolation, level-shifter, retention)
# FC-RM: check_lp -stage design
# ==============================================================================
flow_proc verify_lp_design {
    global clp project
    handle_info "Running design implementation verification (check_lp -stage design)..."

    check_lp -stage design

    handle_info "Design stage verification completed"
}

# ==============================================================================
# flow_proc: verify_lp_pg
# Description: Power grid connectivity checks
# FC-RM: check_lp -stage pg
# ==============================================================================
flow_proc verify_lp_pg {
    global clp project
    handle_info "Running power grid connectivity verification (check_lp -stage pg)..."

    check_lp -stage pg

    handle_info "PG stage verification completed"
}

# ==============================================================================
# flow_proc: generate_reports
# Description: Generate standard and verbose LP violation reports
# FC-RM: report_lp, report_lp -verbose
# ==============================================================================
flow_proc generate_reports {
    global clp project
    handle_info "Generating LP verification reports..."

    set run_dir $::env(CBFLOW_RUN_DIR)
    set design_name $project(top_module)

    file mkdir $::REPORTS_DIR
    file mkdir $::OUTPUTS_DIR

    # Standard violation report
    report_lp -file $::REPORTS_DIR/${design_name}.vc_lp_report_violations.rpt

    # Verbose violation report
    report_lp -verbose -file $::REPORTS_DIR/${design_name}.vc_lp_report_violations.verbose.rpt

    # Summary results file
    set rpt "$::OUTPUTS_DIR/power_verification.rpt"
    set fp [open $rpt w]
    puts $fp "==============================================================================="
    puts $fp "CBFlow CLP - VC LP Power Verification Summary"
    puts $fp "==============================================================================="
    puts $fp "Generated: [expr {[catch {clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}} _ts] ? "epoch [clock seconds]" : $_ts}]"
    if {[info exists project(top_module)]} { puts $fp "Design: $project(top_module)" }
    if {[info exists project(name)]}       { puts $fp "Project: $project(name)" }
    puts $fp ""
    puts $fp "Stages Verified:"
    puts $fp "  check_lp -stage upf    (UPF syntax/semantic)"
    puts $fp "  check_lp -stage design (design implementation)"
    puts $fp "  check_lp -stage pg     (power grid connectivity)"
    puts $fp ""
    puts $fp "Detailed Reports:"
    puts $fp "  $::REPORTS_DIR/${design_name}.vc_lp_report_violations.rpt"
    puts $fp "  $::REPORTS_DIR/${design_name}.vc_lp_report_violations.verbose.rpt"
    close $fp

    handle_info "LP reports generated in $::REPORTS_DIR"
}

# ==============================================================================
# flow_proc: save_session
# Description: Save VC LP session for interactive debug
# FC-RM: save_session
# ==============================================================================
flow_proc save_session {
    global clp project
    handle_info "Saving VC LP session..."

    set run_dir $::env(CBFLOW_RUN_DIR)
    set out_dir "$run_dir/results/clp"
    set design_name $project(top_module)

    file mkdir $out_dir

    handle_info "Saving session to ${out_dir}/${design_name}"
    save_session -session ${out_dir}/${design_name}

    handle_info "Session save completed"
}

# ==============================================================================
# ==============================================================================

flow_exec_all
exit
