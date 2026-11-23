#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow PNR — release_data (opensource / tclsh)
# Publish the block to <release,path>/<phase>/<design>/<tag>/: the views a
# parent block consumes (lef, gds, netlist, lib per lib set) + DEF/SPEF/SDC/CDL/db
# and signoff reports.
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "PNR"
set STAGE_NAME "release_data"
set NODE_NAME [cbflow_node_name]

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_utils.tcl"

set design_name [oss_get flow design_name]
set blocks      [hier_children $design_name]

if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/release_utils.tcl"

# PD release_config.tcl (handshake map, release(file,*)) — not part of the
# node config; loaded once on demand.
proc release_config_load {} {
    if {![array exists ::flow_input_handshake]} {
        uplevel #0 [list source "$::env(FLOW_DIR)/PD/config/flow/[cbflow_version FLOW_CONFIG_VERSION]/release_config.tcl"]
    }
}

# Release names that downstream flows consume: {category file} from
# flow_input_handshake(<flow>,<input>).
proc release_handshake {flow input} {
    release_config_load
    if {![info exists ::flow_input_handshake($flow,$input)]} {
        error "flow_input_handshake($flow,$input) is not set (PD release_config.tcl)"
    }
    lassign $::flow_input_handshake($flow,$input) _src _cat _file
    return [list $_cat [string map [list {${design_name}} $::design_name] $_file]]
}

# Source stage of the chained export node (outputs/export.source) and the
# implementation nodes from it upward (first-dependency chain): the stages
# this release can report.
proc release_source {} {
    set _ex [oss_chain_node export_data]
    set _fh [open [oss_node_output $_ex export.source]]; set _t [read $_fh]; close $_fh
    if {![regexp -line {^source_node\s+(\S+)} $_t -> _sn] || ![regexp -line {^source_type\s+(\S+)} $_t -> _st]} {
        error "export.source of $_ex has no source_node / source_type"
    }
    set _chain {}
    set _n $_sn; set _seen {}
    while {$_n ne "" && $_n ni $_seen} {
        lappend _seen $_n
        set _t [oss_node_type $_n]
        # nearest node of each type wins (a branch node over the trunk one)
        if {![cbflow_node_bypassed $_n] && ![dict exists $_chain $_t]} { dict set _chain $_t $_n }
        set _n [lindex [oss_node_deps $_n] 0]
    }
    return [list $_ex $_sn $_st $_chain]
}

flow_proc publish {
    global design_name project
    lassign [release_source] _ex _src _st _chain
    # Exit this release fills: the source stage's (place -> PLACE_EXIT, ...,
    # signoff -> BTO), else the phase's latest earlier exit
    set _ms [::CBFlow::Release::release_exit_for_stage $::FLOW_TYPE $_st [cbflow_run_phase]]
    set _dir [::CBFlow::Release::init $::FLOW_TYPE $design_name $::DIRS(run) [cbflow_run_phase] $_ms]
    handle_info "release source: $_src ($_st) -> exit $_ms"
    set _eo "[cbflow_node_dir $_ex]/outputs"
    ::CBFlow::Release::copy_file "$_eo/final.gds"                       gds     ${design_name}.gds
    ::CBFlow::Release::copy_file "$_eo/final.lef"                       lef     ${design_name}.lef
    ::CBFlow::Release::copy_file "$_eo/final.v"                         netlist ${design_name}.v
    # STA handshake names: netlist (STA,netlist) and the per-mode SDC (operating_modes)
    ::CBFlow::Release::copy_file "$_eo/final.v"                         {*}[release_handshake STA netlist]
    if {[array exists ::operating_modes]} {
        foreach _mode [array names ::operating_modes] {
            set _cf [string map [list {${design_name}} $design_name] \
                         [dict get $::operating_modes($_mode) constraint_file]]
            if {$_cf ne "${design_name}.sdc"} {
                ::CBFlow::Release::copy_file "$_eo/final.sdc" sdc $_cf
            }
        }
    }
    # PV handshake name: power-aware LVS netlist (PV,netlist)
    ::CBFlow::Release::copy_file "$_eo/final.lvs.v"                     {*}[release_handshake PV netlist]
    ::CBFlow::Release::copy_file "$_eo/final.cdl"                       netlist ${design_name}.cdl
    ::CBFlow::Release::copy_file "$_eo/final.def"                       {*}[release_handshake STA def_file]
    ::CBFlow::Release::copy_file "$_eo/final.sdc"                       sdc     ${design_name}.sdc
    ::CBFlow::Release::copy_file "$_eo/final.odb"                       db      ${design_name}.odb
    # Timing models: signoff only (written there per lib set)
    foreach _lib [glob -nocomplain "$_eo/final__*.lib"] {
        regsub {^final__} [file tail $_lib] "${design_name}__" _name
        ::CBFlow::Release::copy_file $_lib lib $_name
    }
    # Parasitics: from the pro stage, when the source is pro or later
    if {[dict exists $_chain pro]} {
        foreach _spef [glob -nocomplain "[cbflow_node_dir [dict get $_chain pro]]/outputs/final_*.spef"] {
            regsub {^final_} [file tail $_spef] "${design_name}_" _name
            ::CBFlow::Release::copy_file $_spef spef $_name
        }
    }
    # Reports of the stages at or above the source (per node: several nodes
    # write the same report names)
    foreach _t [oss_get pnr oss,release,report_stages] {
        if {![dict exists $_chain $_t]} continue
        set _n [dict get $_chain $_t]
        ::CBFlow::Release::copy_glob "[cbflow_node_dir $_n]/reports/*.rpt" reports/$_n
        ::CBFlow::Release::copy_glob "[cbflow_node_dir $_n]/reports/*[oss_get pnr oss,qor_file_suffix]" reports/$_n
    }
    # SmartGrid data of the exit this release fills: the source node's
    # metrics and timing snapshot, and the layout image.
    # metrics.rpt: the source node's design-level metrics (its per-corner
    # '# scenario:' sections left out), then one '# stage: <type>' block per
    # reported stage with everything that stage measured (categories +
    # per-corner path-group timing) — SmartGrid's stage x corner tables.
    set _crpt [file tail [oss_get pnr checklist,report]]
    set _M {}
    set _fh [open "$::run_dir/[string map [list {${exit_node}} $_src] [oss_get pnr checklist,report]]"]
    set _skip 0
    foreach _ln [split [read $_fh] \n] {
        if {[regexp {^#\s*category:\s*(\S+)} $_ln -> _c]} { set _skip [expr {$_c eq "scenario"}] }
        if {!$_skip} { lappend _M $_ln }
    }
    close $_fh
    foreach _t [oss_get pnr oss,release,report_stages] {
        if {![dict exists $_chain $_t]} continue
        set _f "[cbflow_node_dir [dict get $_chain $_t]]/reports/$_crpt"
        if {![file exists $_f]} continue
        set _fh [open $_f]; lappend _M "# stage: $_t" {*}[split [string trimright [read $_fh]] \n]; close $_fh
    }
    lappend _M "# stage: -"
    set _fh [open "$_dir/metrics.rpt" w]; puts $_fh [join $_M \n]; close $_fh
    release_config_load
    set _ts [cbflow_require release file,timing_snapshot]
    if {[file exists "[cbflow_node_dir $_src]/reports/$_ts"]} {
        ::CBFlow::Release::copy_file "[cbflow_node_dir $_src]/reports/$_ts" . $_ts
    }
    # Layout image (written by export_data; reporting only)
    set _img "$_eo/[oss_get pnr oss,export,layout_image,file]"
    if {[file exists $_img]} {
        ::CBFlow::Release::copy_file $_img [oss_get pnr oss,release,layout_image,dir] [oss_get pnr oss,release,layout_image,file]
    }
    ::CBFlow::Release::generate_manifest
    ::CBFlow::Release::stamp_complete
    set _fh [open [oss_stage_out release.manifest] w]
    puts $_fh "release_dir $_dir"
    puts $_fh "design $design_name"
    puts $_fh "level [hier_level $design_name]"
    # Exit milestone this release fills in SmartGrid — the source stage's
    # exit (published with it: handler_publish_release / cbflow run release).
    puts $_fh "milestone $_ms"
    puts $_fh "source_node $_src"
    close $_fh
    handle_info "Released $design_name ($_ms from $_src) -> $_dir"
}

flow_exec_all
exit
