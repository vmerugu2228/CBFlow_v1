#!/usr/bin/env tclsh
# CBFlow STA export_data - Synopsys PrimeTime | Collect STA results for downstream
set run_dir $::env(CBFLOW_RUN_DIR)
set env_file "$run_dir/.run.cbflow.tcl"
if {[file exists $env_file]} { source -e $env_file } else { puts stderr "ERROR: .run.cbflow.tcl not found"; exit 1 }
if {[info exists ::env(FLOW_DIR)]} { set FLOW_DIR $::env(FLOW_DIR) } else { puts stderr "ERROR: FLOW_DIR not set"; exit 1 }
if {![info exists ::env(UTILITIES_VERSION)] || $::env(UTILITIES_VERSION) eq ""} { puts stderr "ERROR: UTILITIES_VERSION not set"; exit 1 }
set utils_path "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} { source -e $utils_path } else { puts stderr "ERROR: Utils not found"; exit 1 }
namespace import ::CBFlow::Utilities::print_header
set config_file "$run_dir/work/STA/export_data/run/config.tcl"
if {[file exists $config_file]} { source -e $config_file }

# Source tech_config
if {[info exists ::env(TECH_NAME)] && $::env(TECH_NAME) ne "" && [info exists ::env(TECH_VERSION)]} {
    set _tc "$::env(CONFIG_ROOT)/tech/$::env(TECH_NAME)/$::env(TECH_VERSION)/tech_config.tcl"
    if {[file exists $_tc]} { source -e $_tc }
}

# Source user_config for overrides
if {[file exists "$run_dir/setup/user_config.tcl"]} { source -e "$run_dir/setup/user_config.tcl" }

global sta project tech flow
handle_info "Starting STA export_data with Synopsys PrimeTime..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

set WORK_DIR "$run_dir/work/STA/export_data"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

# Source active scenarios
set scenarios_file "$run_dir/work/STA/mmmc_setup/run/active_scenarios.tcl"
if {[file exists $scenarios_file]} {
    source -e $scenarios_file
} else {
    puts stderr "ERROR: Active scenarios file not found: $scenarios_file"
    puts stderr "ERROR: Run mmmc_setup stage first"
    exit 1
}

flow_proc setup_export_dirs {
    handle_info "Setting up export directories..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    foreach dir {"results/sta/timing_reports" "results/sta/spef" "results/sta/constraints" "logs/export_data"} {
        file mkdir "$run_dir/$dir"
    }
    puts " Export directories created"
}

flow_proc export_timing_reports {
    handle_info "Exporting timing reports..."
    global mmmc_active_scenarios
    set run_dir $::env(CBFLOW_RUN_DIR)
    set dest_dir "$run_dir/results/sta/timing_reports"

    # Copy per-scenario setup reports
    foreach scenario $mmmc_active_scenarios {
        set setup_rpt "$run_dir/reports/sta/setup_timing_${scenario}.rpt"
        if {[file exists $setup_rpt]} {
            file copy -force $setup_rpt "$dest_dir/setup_timing_${scenario}.rpt"
            handle_info "  Exported: setup_timing_${scenario}.rpt"
        }
    }

    # Copy per-scenario hold reports
    foreach scenario $mmmc_active_scenarios {
        set hold_rpt "$run_dir/reports/sta/hold_timing_${scenario}.rpt"
        if {[file exists $hold_rpt]} {
            file copy -force $hold_rpt "$dest_dir/hold_timing_${scenario}.rpt"
            handle_info "  Exported: hold_timing_${scenario}.rpt"
        }
    }

    # Copy summary reports
    foreach summary {"mmmc_setup_summary.rpt" "mmmc_hold_summary.rpt" "mmmc_timing_summary.rpt"} {
        set src "$run_dir/reports/sta/$summary"
        if {[file exists $src]} {
            file copy -force $src "$dest_dir/$summary"
            handle_info "  Exported: $summary"
        }
    }
    puts " Timing reports exported"
}

flow_proc export_spef_files {
    handle_info "Exporting SPEF files..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    set src_dir "$run_dir/work/STA/inputs/spef"
    set dest_dir "$run_dir/results/sta/spef"

    if {[file isdirectory $src_dir]} {
        foreach spef_file [glob -nocomplain -directory $src_dir *.spef] {
            file copy -force $spef_file "$dest_dir/[file tail $spef_file]"
            handle_info "  Exported SPEF: [file tail $spef_file]"
        }
    }
    puts " SPEF files exported"
}

flow_proc export_constraint_files {
    handle_info "Exporting constraint files..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    set src_dir "$run_dir/work/STA/inputs/sdc"
    set dest_dir "$run_dir/results/sta/constraints"

    if {[file isdirectory $src_dir]} {
        foreach sdc_file [glob -nocomplain -directory $src_dir *.sdc] {
            file copy -force $sdc_file "$dest_dir/[file tail $sdc_file]"
            handle_info "  Exported SDC: [file tail $sdc_file]"
        }
    }
    puts " Constraint files exported"
}

flow_proc export_data_flow {
    handle_info "Executing STA export_data flow..."
    flow_exec setup_export_dirs
    flow_exec export_timing_reports
    flow_exec export_spef_files
    flow_exec export_constraint_files
    handle_info "STA export_data completed successfully"
}
if {[info exists argv0] && $argv0 eq [info script]} { flow_exec export_data_flow } else { puts " STA export_data procedures loaded" }
exit
