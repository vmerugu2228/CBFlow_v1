#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow RTL_SPEC — gen_ipxact (opensource / container tclsh)
# IP-XACT component (IEEE 1685-2014) of the block: ports (from the spec),
# bus interfaces (APB4 with the AMBA busType + port maps; valid/ready with a
# CBflow bus definition), the register memory map (PeakRDL), the RTL file set
# and the model view — validated against the Accellera 1685-2014 schema
# (lsf(oss,tools_dir)/rtl_spec(oss,ipxact,schema)).
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "RTL_SPEC"
set STAGE_NAME "gen_ipxact"
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

flow_proc generate {
    set _sc "[cbflow_node_dir [oss_chain_node spec_check]]/outputs"
    set _rg "[cbflow_node_dir [oss_chain_node gen_regs]]/outputs/regs"
    if {![info exists ::env(CBFLOW_OSS_TOOLS)]} { error "CBFLOW_OSS_TOOLS is not set (lsf(oss,tools_dir))" }
    set _xsd "$::env(CBFLOW_OSS_TOOLS)/[oss_get rtl_spec oss,ipxact,schema]"
    if {![file exists $_xsd]} { error "IP-XACT schema not found: $_xsd — run global/utils/oss/install_ipxact_schema.sh" }
    set _regs [expr {[file isdirectory $_rg] ? [list --regs $_rg] : {}}]
    oss_py "$::REPORTS_DIR/filelist.log" $::spec_tool filelist --spec "$_sc/spec.json" {*}$_regs -o "$::WORK_DIR/run/files.f"
    set _fh [open "$::WORK_DIR/run/files.f"]; set _files [split [string trim [read $_fh]] \n]; close $_fh
    set _mm [glob -nocomplain "$_rg/ipxact/*.memmap.xml"]
    set _mma [expr {[llength $_mm] ? [list --memmap [lindex $_mm 0]] : {}}]
    oss_py "$::REPORTS_DIR/ipxact.log" $::spec_tool ipxact --spec "$_sc/spec.json" {*}$_mma \
        --files {*}[lmap f $_files {file tail $f}] -o [oss_stage_out component.xml] \
        --schema $_xsd --report "$::REPORTS_DIR/ipxact.rpt"
}

oss_exec_all
exit
