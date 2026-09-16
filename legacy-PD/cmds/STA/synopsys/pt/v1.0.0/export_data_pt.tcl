#!/usr/bin/env tclsh
# CBFlow STA export_data - Synopsys PrimeTime

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "STA"
set STAGE_NAME "export_data"
set NODE_NAME "${STAGE_NAME}1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

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
