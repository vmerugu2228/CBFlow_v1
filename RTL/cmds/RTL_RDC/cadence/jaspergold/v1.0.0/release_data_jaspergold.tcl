#!/usr/bin/env tclsh
# CBflow RTL_RDC release_data — cadence jaspergold (SCAFFOLD)

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
set _ru "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/release_utils.tcl"
if {[file exists $_ru]} { source $_ru }

set FLOW_TYPE  "RTL_RDC"
set STAGE_NAME "release_data"
set NODE_NAME  "${STAGE_NAME}1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

flow_proc release_run {
    global run_dir
    set release_dir "$run_dir/results/release/rtl_rdc"
    foreach sub {"reports" "data"} { file mkdir "$release_dir/$sub" }
    handle_info "  Release dir: $release_dir (jaspergold scaffold — real staging TBD)"
}

release_run
