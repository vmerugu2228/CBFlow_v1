#!/usr/bin/env tclsh
# ===============================================================================
# CBFlow - CLP Low-Power Verification Command File
# Description: Low-power static signoff verification using Synopsys VC LP
# Tool: Synopsys Verification Compiler Low Power
# Based on: FC-RM Y-2026.03 vc_lp.tcl
# ===============================================================================

set run_dir $::env(CBFLOW_RUN_DIR)
set env_file "$run_dir/.run.cbflow.tcl"
if {[file exists $env_file]} { source -e $env_file } else { puts stderr "ERROR: .run.cbflow.tcl not found"; exit 1 }
if {[info exists ::env(FLOW_DIR)]} { set FLOW_DIR $::env(FLOW_DIR) } else { puts stderr "ERROR: FLOW_DIR not set"; exit 1 }
if {![info exists ::env(UTILITIES_VERSION)] || $::env(UTILITIES_VERSION) eq ""} { puts stderr "ERROR: UTILITIES_VERSION not set"; exit 1 }
set utils_path "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} { source -e $utils_path } else { puts stderr "ERROR: Utils not found"; exit 1 }
namespace import ::CBFlow::Utilities::print_header
set config_file "$run_dir/work/CLP/clp1/run/config.tcl"
if {[file exists $config_file]} { source -e $config_file }

# Source tech_config
if {[info exists ::env(TECH_NAME)] && $::env(TECH_NAME) ne "" && [info exists ::env(TECH_VERSION)]} {
    set _tc "$::env(CONFIG_ROOT)/tech/$::env(TECH_NAME)/$::env(TECH_VERSION)/tech_config.tcl"
    if {[file exists $_tc]} { source -e $_tc }
}

# Source user_config for overrides
if {[file exists "$run_dir/setup/user_config.tcl"]} { source -e "$run_dir/setup/user_config.tcl" }

global clp project tech flow
# Source VC_LP tool config
set _tool_config "[file dirname [info script]]/vc_lp_config.tcl"
if {[file exists $_tool_config]} { source $_tool_config }
handle_info "Starting CLP verification with Synopsys VC LP..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

# ── Directories ──────────────────────────────────────────────────────────────
set WORK_DIR "$run_dir/work/CLP/clp1"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

# ==============================================================================
# flow_proc: configure_lp_checks
# Description: Set app_vars for LP verification options
# FC-RM: sh_continue_on_error, handle_hanging_crossover, enable_local_policy_match,
#         upf_iso_filter_elements_with_applies_to, enable_multi_driver_analysis, etc.
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
    if {[info exists vc_lp(check,continue_on_error)] && $vc_lp(check,continue_on_error) ne ""} {
        set_app_var sh_continue_on_error $vc_lp(check,continue_on_error)
    }
    if {[info exists vc_lp(check,hanging_crossover)] && $vc_lp(check,hanging_crossover) ne ""} {
        set_app_var handle_hanging_crossover $vc_lp(check,hanging_crossover)
    }
    if {[info exists vc_lp(check,multi_driver)] && $vc_lp(check,multi_driver) ne ""} {
        set_app_var enable_multi_driver_analysis $vc_lp(check,multi_driver)
    }
    if {[info exists vc_lp(check,verdi_debug)] && $vc_lp(check,verdi_debug) ne ""} {
        set_app_var enable_verdi_debug $vc_lp(check,verdi_debug)
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
    if {[info exists vc_lp(common,upf_mode)] && $vc_lp(common,upf_mode) ne ""} {
        set upf_mode $vc_lp(common,upf_mode)
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
    puts $fp "Generated: [clock format [clock seconds]]"
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
# Source setup.tcl and overrides before flow_exec_all
# ==============================================================================
set _setup_file "$run_dir/work/CLP/clp1/run/setup.tcl"
if {[file exists $_setup_file]} { handle_info "Sourcing setup hooks: $_setup_file"; source -e $_setup_file }
set _override_file "$run_dir/setup/override_setup.tcl"
if {[file exists $_override_file]} { handle_info "Sourcing user override: $_override_file"; source -e $_override_file }
set _stage_override "$run_dir/setup/override_setup.clp.tcl"
if {[file exists $_stage_override]} { handle_info "Sourcing stage override: $_stage_override"; source -e $_stage_override }

flow_exec_all
exit
