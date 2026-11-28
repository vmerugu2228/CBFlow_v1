#!/usr/bin/env tclsh
# CBflow RTL_LINT release_data — Synopsys Spyglass
# Package lint deliverables (signoff.rpt, violations_final.csv/html,
# waivers_applied.rpt) into the release area under release(base_dir)/
# <block>/<tag>/rtl_lint/.

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
# Source release utilities for ::CBFlow::Release namespace
set _ru "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/release_utils.tcl"
if {[file exists $_ru]} { source $_ru }

set FLOW_TYPE  "RTL_LINT"
set STAGE_NAME "release_data"
set NODE_NAME  "${STAGE_NAME}1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# ---------------------------------------------------------------------------

flow_proc init_release {
    global rtl_lint project run_dir
    handle_info "RTL_LINT release initialization..."

    set release_dir "$run_dir/results/release/rtl_lint"
    foreach sub {"reports" "data"} {
        file mkdir "$release_dir/$sub"
    }
    handle_info "  Release dir: $release_dir"
}

flow_proc stage_release_files {
    global rtl_lint run_dir
    handle_info "Staging RTL_LINT release files..."

    set release_dir "$run_dir/results/release/rtl_lint"
    set src_dir     "$run_dir/reports/rtl_lint"
    set staged 0

    foreach {src dest} {
        lint_signoff.rpt       reports/lint_signoff.rpt
        violations_final.csv   reports/violations_final.csv
        violations_final.html  reports/violations_final.html
        waivers_applied.rpt    reports/waivers_applied.rpt
    } {
        if {[file exists "$src_dir/$src"]} {
            if {[catch {file copy -force "$src_dir/$src" "$release_dir/$dest"} _cp_err]} {
                handle_warning "release copy failed ($src → $dest): $_cp_err"
            } else {
                incr staged
            }
        }
    }
    handle_info "  Staged $staged RTL_LINT deliverables"
}

flow_proc release_run {
    init_release
    stage_release_files
}

flow_proc release_data_flow { flow_exec release_run }
if {[info exists argv0] && $argv0 eq [info script]} { flow_exec release_data_flow } else { puts "RTL_LINT release_data procedures loaded" }
exit
