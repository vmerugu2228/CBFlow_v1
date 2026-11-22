#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow PV — release_data (opensource / tclsh)
# Publish the PV reports next to the block's SYNTH_PNR release
# (<release,path>/<phase>/<design>/<tag>/reports/pv/).
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "PV"
set STAGE_NAME "release_data"
set NODE_NAME [cbflow_node_name]

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_utils.tcl"

set design_name [oss_get flow design_name]

if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/release_utils.tcl"

flow_proc publish {
    global design_name
    set _dir [::CBFlow::Release::init $::FLOW_TYPE $design_name $::DIRS(run) [cbflow_run_phase]]
    set _drcn [cbflow_dep_node drc]
    set _lvsn [cbflow_dep_node lvs]
    set _mrgn [cbflow_chain_node merge_data]
    foreach _n [list $_drcn $_lvsn $_mrgn] _f {drc.rpt lvs.rpt verification_summary.rpt} {
        ::CBFlow::Release::copy_file "[cbflow_node_dir $_n]/outputs/$_f" reports/pv $_f
    }
    foreach _n [list $_drcn $_lvsn] { ::CBFlow::Release::copy_glob "[cbflow_node_dir $_n]/reports/*.rpt" reports/pv }
    # The checked layout: the GDS PV ran on and its CDL — a parent's lib tag
    # takes a block's GDS / CDL from this release (library-manager add)
    set _gds "$::GDS_DIR/${design_name}.gds"
    if {![file exists $_gds]} { error "checked GDS not staged: $_gds (pv(input,gds))" }
    ::CBFlow::Release::copy_file $_gds gds ${design_name}.gds
    set _cdl "$::NETLIST_DIR/${design_name}.cdl"
    if {[file exists $_cdl]} {
        ::CBFlow::Release::copy_file $_cdl netlist ${design_name}.cdl
    } elseif {[is_true [oss_get pv signoff,lvs_required]]} {
        error "CDL not staged: $_cdl (pv(input,netlist_cdl)) — required with pv(signoff,lvs_required)"
    } else {
        handle_info "no CDL in the checked release (pv(signoff,lvs_required) false) — GDS only"
    }
    # Signoff metrics + verdict for SmartGrid (attached to the exit it checked)
    set _fh [open "[cbflow_node_dir $_mrgn]/outputs/verification_summary.rpt"]; set _t [read $_fh]; close $_fh
    set _drc ""; set _lvs ""
    regexp -line {^drc_errors\s+(\d+)} $_t -> _drc
    regexp -line {^result\s+(.+)$} $_t -> _lvs
    # pv(signoff,lvs_required) false (e.g. PV on a floorplan release — no
    # signal routing yet): the verdict is DRC only; LVS is still reported.
    set _lvs_ok [expr {![is_true [oss_get pv signoff,lvs_required]] || [regexp -- [oss_get pv signoff,lvs_pass] $_lvs]}]
    set _ok [expr {$_drc ne "" && $_drc <= [oss_get pv signoff,max_drc] && $_lvs_ok}]
    set _L [list "# category: drc" "DRC errors : $_drc" "# category: lvs" "LVS result : $_lvs" \
                 "# category: signoff" "Status : [expr {$_ok ? "PASS" : "FAIL"}]"]
    set _fh [open "$_dir/metrics.rpt" w]; puts $_fh [join $_L \n]; close $_fh
    ::CBFlow::Release::generate_manifest
    ::CBFlow::Release::stamp_complete
    set _fh [open [oss_stage_out release.manifest] w]
    puts $_fh "release_dir $_dir"
    puts $_fh "attach_to [oss_get pv input,release_tag]"
    close $_fh
    handle_info "PV reports + checked GDS / CDL released -> $_dir"
}

flow_exec_all
exit
