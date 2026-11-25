#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow RTL_SPEC — release_data (opensource / container tclsh)
# Publish <release,path>/<phase>/<design>/RTL_SPEC/<tag> (tag: SPEC_EXIT
# unless project(release,tag)): rtl/ — every RTL source (generated register
# block + designer RTL) and <d>.f listing them at their released paths (the
# filelist RTL_LINT / SYNTH / DV read); spec/ — the YAML spec, the IP-XACT
# component, the SystemRDL, the vPlan; sdc/, upf/; ral/<d>_ral.sv (UVM register
# model, handshake TB_SETUP,ral); data/regs/ — UVM register
# model, C header, HTML register docs; the reports.
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "RTL_SPEC"
set STAGE_NAME "release_data"
set NODE_NAME [cbflow_node_name]

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_utils.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_flow_utils.tcl"

set design_name [oss_get flow design_name]
set spec_tool "$::env(CBFLOW_RTL_DIR)/utils/oss/spec_tool.py"

if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/release_utils.tcl"

flow_proc publish {
    global design_name
    set _dir [::CBFlow::Release::init $::FLOW_TYPE $design_name $::DIRS(run) [cbflow_run_phase]]
    set _sc "[cbflow_node_dir [oss_chain_node spec_check]]/outputs"
    set _rg "[cbflow_node_dir [oss_chain_node gen_regs]]/outputs/regs"
    set _co "[cbflow_node_dir [oss_chain_node gen_collateral]]/outputs"
    set _ix "[cbflow_node_dir [oss_chain_node gen_ipxact]]/outputs"
    # RTL: every source, and the filelist at the released paths
    set _fh [open "$_co/design.f"]; set _files [split [string trim [read $_fh]] \n]; close $_fh
    set _rel {}
    foreach _f $_files {
        ::CBFlow::Release::copy_file $_f rtl [file tail $_f]
        lappend _rel "$_dir/rtl/[file tail $_f]"
    }
    oss_write_file "$::WORK_DIR/outputs/${design_name}.f" "[join $_rel \n]\n"
    ::CBFlow::Release::copy_file "$::WORK_DIR/outputs/${design_name}.f" {*}[oss_release_name RTL_LINT rtl]
    # spec collateral
    ::CBFlow::Release::copy_file [oss_input spec] spec ${design_name}.spec.yaml
    ::CBFlow::Release::copy_file "$_ix/component.xml" spec ${design_name}.xml
    if {[file exists "$_sc/regs.rdl"]} { ::CBFlow::Release::copy_file "$_sc/regs.rdl" spec ${design_name}_regs.rdl }
    if {[file exists "$_co/vplan.xlsx"]} { ::CBFlow::Release::copy_file "$_co/vplan.xlsx" spec ${design_name}_vplan.xlsx }
    ::CBFlow::Release::copy_file "$_co/design.sdc" sdc ${design_name}.sdc
    if {[file exists "$_co/design.upf"]} { ::CBFlow::Release::copy_file "$_co/design.upf" upf ${design_name}.upf }
    if {[file isdirectory $_rg]} {
        foreach _f [glob -nocomplain "$_rg/uvm/*" "$_rg/c/*"] { ::CBFlow::Release::copy_file $_f data/regs [file tail $_f] }
        # the UVM register model under its canonical name (handshake TB_SETUP,ral)
        set _ral [glob -nocomplain "$_rg/uvm/*_ral_pkg.sv"]
        if {[llength $_ral] != 1} { error "one UVM register model expected in $_rg/uvm, found: $_ral" }
        ::CBFlow::Release::copy_file [lindex $_ral 0] {*}[oss_release_name TB_SETUP ral]
        file mkdir "$_dir/data/regs"
        file copy -force "$_rg/html" "$_dir/data/regs/html"
    }
    foreach _t {spec_check gen_regs gen_ipxact gen_collateral} {
        ::CBFlow::Release::copy_glob "[cbflow_node_dir [oss_chain_node $_t]]/reports/*.rpt" reports
    }
    ::CBFlow::Release::generate_manifest
    ::CBFlow::Release::stamp_complete
    oss_write_file [oss_stage_out release.manifest] "release_dir $_dir\ndesign $design_name\n"
    handle_info "Released $design_name spec collateral -> $_dir"
}

oss_exec_all
exit
