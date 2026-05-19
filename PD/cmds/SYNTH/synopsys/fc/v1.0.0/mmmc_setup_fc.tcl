#!/usr/bin/env tclsh
# CBFlow SYNTH mmmc_setup - Synopsys Fusion Compiler | MMMC scenario configuration
set run_dir $::env(CBFLOW_RUN_DIR)
set env_file "$run_dir/.run.cbflow.tcl"
if {[file exists $env_file]} { source $env_file } else { puts stderr "ERROR: .run.cbflow.tcl not found"; exit 1 }
if {[info exists ::env(FLOW_DIR)]} { set FLOW_DIR $::env(FLOW_DIR) } else { puts stderr "ERROR: FLOW_DIR not set"; exit 1 }
if {![info exists ::env(UTILITIES_VERSION)] || $::env(UTILITIES_VERSION) eq ""} { puts stderr "ERROR: UTILITIES_VERSION not set"; exit 1 }
set utils_path "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} { source $utils_path } else { puts stderr "ERROR: Utils not found"; exit 1 }
namespace import ::CBFlow::Utilities::print_header
set config_file "$run_dir/work/$::env(CBFLOW_FLOW_TYPE)/$::env(CBFLOW_NODE_NAME)/run/config.tcl"
if {[file exists $config_file]} { source $config_file }
global sta project tech flow
# Source FC tool config
set _tool_config "[file dirname [info script]]/fc_config.tcl"
if {[file exists $_tool_config]} { source $_tool_config }
handle_info "Starting SYNTH MMMC setup with Synopsys Fusion Compiler..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

# ── Directories ──────────────────────────────────────────────────────────────
set WORK_DIR "$run_dir/work/SYNTH/mmmc_setup"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

# Source tech_config
if {[info exists ::env(TECH_NAME)] && $::env(TECH_NAME) ne "" &&
    [info exists ::env(TECH_VERSION)] && $::env(TECH_VERSION) ne ""} {
    set _tc "$::env(CONFIG_ROOT)/tech/$::env(TECH_NAME)/$::env(TECH_VERSION)/tech_config.tcl"
    if {[file exists $_tc]} { source -e $_tc }
}

# Source MMMC configuration
set mmmc_config_file "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/mmmc_config.tcl"
if {[file exists $mmmc_config_file]} {
    source -e $mmmc_config_file
} else {
    puts stderr "ERROR: MMMC config not found: $mmmc_config_file"
    exit 1
}

flow_proc setup_mmmc_dirs {
    handle_info "Setting up MMMC directories..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    foreach dir {"work/SYNTH/mmmc_setup/run" "work/SYNTH/mmmc_setup/setup" "reports/sta" "results/sta" "logs/mmmc_setup"} {
        file mkdir "$run_dir/$dir"
    }
    puts " MMMC directories created"
}

flow_proc resolve_scenarios {
    handle_info "Resolving active MMMC scenario set..."
    global sta mmmc_scenario_sets analysis_views
    set run_dir $::env(CBFLOW_RUN_DIR)

    # Determine scenario set: user override or default "signoff"
    if {[info exists sta(mmmc,scenario_set)]} {
        set scenario_set $sta(mmmc,scenario_set)
    } else {
        set scenario_set "signoff"
    }
    handle_info "Using scenario set: $scenario_set"

    # Retrieve scenarios from the selected set
    if {![info exists mmmc_scenario_sets($scenario_set)]} {
        puts stderr "ERROR: Unknown scenario set: $scenario_set"
        puts stderr "ERROR: Available sets: [join [array names mmmc_scenario_sets] { }]"
        exit 1
    }
    array set set_info $mmmc_scenario_sets($scenario_set)
    set active_scenarios $set_info(scenarios)
    handle_info "Resolved [llength $active_scenarios] scenarios for set '$scenario_set'"

    # Validate each scenario exists in analysis_views
    foreach scenario $active_scenarios {
        if {![info exists analysis_views($scenario)]} {
            puts stderr "ERROR: Scenario '$scenario' not found in analysis_views"
            exit 1
        }
    }

    # Write active scenarios file
    set out_file "$run_dir/work/SYNTH/mmmc_setup/run/active_scenarios.tcl"
    file mkdir [file dirname $out_file]
    set fh [open $out_file "w"]
    puts $fh "#!/usr/bin/env tclsh"
    puts $fh "# Auto-generated MMMC active scenarios - [clock format [clock seconds]]"
    puts $fh "# Scenario set: $scenario_set"
    puts $fh ""
    puts $fh "set mmmc_active_scenario_set \"$scenario_set\""
    puts $fh "set mmmc_active_scenarios [list $active_scenarios]"
    puts $fh ""
    # Write per-scenario view details
    foreach scenario $active_scenarios {
        array set view_info $analysis_views($scenario)
        puts $fh "array set scenario_view_${scenario} [list [array get view_info]]"
        array unset view_info
    }
    close $fh
    handle_info "Active scenarios written to: $out_file"

    # Create per-scenario directory structure
    foreach scenario $active_scenarios {
        file mkdir "$run_dir/work/SYNTH/mmmc_setup/run/$scenario"
        file mkdir "$run_dir/reports/sta/$scenario"
        handle_info "  Created directory for scenario: $scenario"
    }
    puts " Scenario resolution completed"

    # Generate dynamic per-scenario makefiles after resolving scenarios
    flow_exec generate_dynamic_makefiles
}

flow_proc generate_dynamic_makefiles {
    handle_info "Generating dynamic per-scenario timing makefiles..."
    global mmmc_scenario_sets sta analysis_views
    set run_dir $::env(CBFLOW_RUN_DIR)

    # Read active scenarios from the file we just wrote
    set scenarios_file "$run_dir/work/SYNTH/mmmc_setup/run/active_scenarios.tcl"
    if {![file exists $scenarios_file]} {
        puts stderr "ERROR: Active scenarios file not found: $scenarios_file"
        exit 1
    }
    source -e $scenarios_file

    # Ensure .make directory exists
    set make_dir "$run_dir/.make"
    file mkdir $make_dir

    # Determine tool version
    set _tool_ver [expr {[info exists ::env(FC_VERSION)] ? $::env(FC_VERSION) : {v1.0.0}}]

    # Generate per-scenario .mk files
    foreach scenario $mmmc_active_scenarios {
        set mk_file "$make_dir/timing_${scenario}.mk"
        set fh [open $mk_file "w"]
        puts $fh "# CBFlow SYNTH Per-Scenario Timing Makefile"
        puts $fh "# Auto-generated by mmmc_setup for scenario: $scenario"
        puts $fh "# Generated: [clock format [clock seconds]]"
        puts $fh ""

        # Create a make-safe variable name (replace dots, dashes with underscores)
        set safe_name [string map {. _ - _ } $scenario]
        set stamp_var "TIMING_[string toupper $safe_name]_SYNTHMP"

        puts $fh "# Scenario: $scenario"
        puts $fh "$stamp_var = \$(SYNTHMP_DIR)/timing_${scenario}.stamp"
        puts $fh ""
        puts $fh ".PHONY: timing_${scenario}"
        puts $fh "timing_${scenario}: \$($stamp_var)"
        puts $fh ""
        puts $fh "\$($stamp_var): \$(SYNTHMP_DIR)/extraction1.stamp"
        puts $fh "\t@echo \"Running timing for scenario: ${scenario}...\""
        puts $fh "\t@mkdir -p \$(SYNTHMP_DIR) \$(LOGS_DIR)"
        puts $fh "\t@tclsh \"\$(FLOW_DIR)/cmds/SYNTH/synopsys/fc/\$(FC_VERSION)/timing_scenario_handler.tcl\" ${scenario} \"\$(PWD)\""
        puts $fh "\t@echo \"done timing scenario ${scenario} completed\""
        puts $fh "\t@touch \$@"
        puts $fh ""
        close $fh
        handle_info "  Generated: $mk_file"
    }

    # Generate the master timing_dynamic.mk that ties all scenarios together
    set master_mk "$make_dir/timing_dynamic.mk"
    set fh [open $master_mk "w"]
    puts $fh "# Auto-generated by mmmc_setup - dynamic per-scenario timing targets"
    puts $fh "# Generated: [clock format [clock seconds]]"
    puts $fh "# Scenario set: $mmmc_active_scenario_set"
    puts $fh ""

    # Build scenario list
    puts $fh "TIMING_SCENARIOS = [join $mmmc_active_scenarios { }]"
    puts $fh ""

    # Include per-scenario makefiles
    puts $fh "# Include per-scenario makefiles"
    foreach scenario $mmmc_active_scenarios {
        puts $fh "-include \$(PWD)/.make/timing_${scenario}.mk"
    }
    puts $fh ""

    # Build the stamp dependency list for timing1
    set scenario_stamps {}
    foreach scenario $mmmc_active_scenarios {
        lappend scenario_stamps "\$(SYNTHMP_DIR)/timing_${scenario}.stamp"
    }

    puts $fh "# Aggregate timing1 target - depends on all per-scenario stamps"
    puts $fh ".PHONY: timing1"
    puts $fh "timing1: \$(SYNTHMP_DIR)/timing1.stamp"
    puts $fh ""
    puts $fh "\$(SYNTHMP_DIR)/timing1.stamp: [join $scenario_stamps { }]"
    puts $fh "\t@echo \"done timing1 stage completed (all scenarios)\""
    puts $fh "\t@touch \$(SYNTHMP_DIR)/timing1.stamp"
    puts $fh ""

    close $fh
    handle_info "  Generated master: $master_mk"
    handle_info "Dynamic makefile generation completed ([llength $mmmc_active_scenarios] scenarios)"
    puts " Dynamic per-scenario makefiles generated"
}

flow_proc mmmc_setup_flow {
    handle_info "Executing SYNTH MMMC setup flow..."
    flow_exec setup_mmmc_dirs
    flow_exec resolve_scenarios
    handle_info "SYNTH MMMC setup completed successfully"
}
if {[info exists argv0] && $argv0 eq [info script]} { flow_exec mmmc_setup_flow } else { puts " SYNTH MMMC setup procedures loaded" }

# Exit tool after stage completion
exit
