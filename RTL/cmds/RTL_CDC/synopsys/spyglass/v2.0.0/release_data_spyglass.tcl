#!/usr/bin/env tclsh
# CBflow RTL_CDC release_data — synopsys spyglass

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
# Source release utilities for ::CBFlow::Release namespace
set _ru "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/release_utils.tcl"
if {[file exists $_ru]} { source $_ru }

set FLOW_TYPE  "RTL_CDC"
set STAGE_NAME "release_data"
set NODE_NAME  "${STAGE_NAME}1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# ---------------------------------------------------------------------------

flow_proc init_release {
    global run_dir
    set release_dir "$run_dir/results/release/rtl_cdc"
    foreach sub {"reports" "data"} { file mkdir "$release_dir/$sub" }
    handle_info "  Release dir: $release_dir"
}

flow_proc stage_release_files {
    global run_dir
    set release_dir "$run_dir/results/release/rtl_cdc"
    set src_dir     "$run_dir/reports/rtl_cdc"
    set staged 0
    foreach {src dest} {
        cdc_signoff.rpt  reports/cdc_signoff.rpt
        violations_final.csv  reports/violations_final.csv
        cdc_paths.rpt  reports/cdc_paths.rpt
        clock_summary.rpt  reports/clock_summary.rpt
        waivers_applied.rpt  reports/waivers_applied.rpt
    } {
        if {[file exists "$src_dir/$src"]} {
            if {[catch {file copy -force "$src_dir/$src" "$release_dir/$dest"} _cp_err]} {
                handle_warning "release copy failed ($src → $dest): $_cp_err"
            } else {
                incr staged
            }
        }
    }
    handle_info "  Staged $staged RTL_CDC deliverables"
}

flow_proc release_run {
    init_release
    stage_release_files
}

release_run
