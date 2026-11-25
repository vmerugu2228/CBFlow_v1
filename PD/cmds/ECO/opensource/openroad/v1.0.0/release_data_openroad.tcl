#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow ECO — release_data (opensource / tclsh)
# Release the ECO'd block as <EXIT>_ECO<n> (project(release,tag), required):
# the same views / names as a PNR release (downstream STA / PV / LEC read it
# with <flow>(input,release_tag) "<EXIT>_ECO<n>") + the ECO change list and
# pre / post QoR. SmartGrid shows the tag as a variant of <EXIT>.
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "ECO"
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
    global design_name project
    # Tag <EXIT>_ECO<n>: EXIT must be an exit of the run's phase
    set _tag [expr {[info exists project(release,tag)] ? $project(release,tag) : ""}]
    if {![regexp [oss_get eco oss,release,tag_pattern] $_tag -> _exit _n]} {
        error "project(release,tag) must be <EXIT>_ECO<n> (e.g. BTO_ECO1), got '$_tag'"
    }
    set _px [dict get $project(phase_exits) [cbflow_run_phase]]
    if {$_exit ni $_px} { error "release tag $_tag: $_exit is not an exit of phase [cbflow_run_phase] ($_px)" }
    set _dir [::CBFlow::Release::init $::FLOW_TYPE $design_name $::DIRS(run) [cbflow_run_phase] $_exit]
    set _ex [oss_chain_node export_data]
    set _so [oss_chain_node signoff]
    set _ec [oss_chain_node eco]
    set _eo "[cbflow_node_dir $_ex]/outputs"
    ::CBFlow::Release::copy_file "$_eo/final.gds"    gds     ${design_name}.gds
    ::CBFlow::Release::copy_file "$_eo/final.lef"    lef     ${design_name}.lef
    ::CBFlow::Release::copy_file "$_eo/final.v"      netlist ${design_name}.v
    ::CBFlow::Release::copy_file "$_eo/final.v"      netlist ${design_name}.pt.v
    ::CBFlow::Release::copy_file "$_eo/final.lvs.v"  netlist ${design_name}.lvs.v
    ::CBFlow::Release::copy_file "$_eo/final.cdl"    netlist ${design_name}.cdl
    ::CBFlow::Release::copy_file "$_eo/final.def"    def     ${design_name}.def
    ::CBFlow::Release::copy_file "$_eo/final.sdc"    sdc     ${design_name}.sdc
    ::CBFlow::Release::copy_file "$_eo/final.odb"    db      ${design_name}.odb
    if {[file exists "$_eo/final.scandef"]} {
        ::CBFlow::Release::copy_file "$_eo/final.scandef" def   ${design_name}.scandef
    }
    if {[array exists ::operating_modes]} {
        foreach _mode [array names ::operating_modes] {
            set _cf [string map [list {${design_name}} $design_name] [dict get $::operating_modes($_mode) constraint_file]]
            if {$_cf ne "${design_name}.sdc"} { ::CBFlow::Release::copy_file "$_eo/final.sdc" sdc $_cf }
        }
    }
    foreach _lib [glob -nocomplain "$_eo/final__*.lib"] {
        regsub {^final__} [file tail $_lib] "${design_name}__" _name
        ::CBFlow::Release::copy_file $_lib lib $_name
    }
    foreach _spef [glob -nocomplain "$_eo/final_*.spef"] {
        regsub {^final_} [file tail $_spef] "${design_name}_" _name
        ::CBFlow::Release::copy_file $_spef spef $_name
    }
    foreach _n [list $_ec $_so] {
        ::CBFlow::Release::copy_glob "[cbflow_node_dir $_n]/reports/*.rpt" reports/$_n
        ::CBFlow::Release::copy_glob "[cbflow_node_dir $_n]/reports/*_qor.tcl" reports/$_n
    }
    ::CBFlow::Release::copy_file "[cbflow_node_dir $_ec]/reports/eco_changes.rpt" reports eco_changes.rpt
    set _cr "[cbflow_node_dir $_so]/reports/checklist_metrics.rpt"
    if {[file exists $_cr]} { ::CBFlow::Release::copy_file $_cr . metrics.rpt }
    ::CBFlow::Release::generate_manifest
    ::CBFlow::Release::stamp_complete
    set _fh [open [oss_stage_out release.manifest] w]
    puts $_fh "release_dir $_dir\ndesign $design_name\nmilestone $_exit\nvariant ECO$_n"
    close $_fh
    handle_info "Released $design_name ECO $_tag (variant of $_exit) -> $_dir"
}

flow_exec_all
exit
