#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow PV — lvs (opensource / magic + netgen)
# LVS: Magic extracts the staged GDS (hierarchical, LVS mode), Netgen
# compares it with the staged power-aware netlist plus the LVS netlist of every
# descendant block from the library tag (tech(block,<b>,lvs_netlist)).
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "PV"
set STAGE_NAME "lvs"
set NODE_NAME "lvs1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_utils.tcl"

set design_name [oss_get flow design_name]

if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

flow_proc extract {
    global design_name
    set _gds [lindex [glob -nocomplain "$::GDS_DIR/${design_name}.gds" "$::GDS_DIR/*.gds"] 0]
    if {$_gds eq ""} { error "no GDS staged in $::GDS_DIR (pv(input,gds))" }
    set _script "$::WORK_DIR/lvs_extract.tcl"
    set _fh [open $_script w]
    puts $_fh "gds read $_gds"
    puts $_fh "load $design_name"
    puts $_fh "select top cell"
    puts $_fh "extract do local"
    puts $_fh "extract all"
    puts $_fh "ext2spice lvs"
    puts $_fh "ext2spice -o [oss_stage_out ${design_name}_extracted.spice]"
    puts $_fh "quit -noprompt"
    close $_fh
    oss_exec_tool magic $_script "$::REPORTS_DIR/lvs_extract.log"
}

flow_proc compare {
    global design_name
    set _top [lindex [glob -nocomplain "$::NETLIST_DIR/${design_name}.lvs.v" "$::NETLIST_DIR/*.v"] 0]
    if {$_top eq ""} { error "no netlist staged in $::NETLIST_DIR (pv(input,netlist))" }
    set _nets [list $_top]
    foreach _b [hier_descendants $design_name] { lappend _nets [oss_get tech block,$_b,lvs_netlist] }
    set _rpt "$::REPORTS_DIR/lvs_netgen.rpt"
    set _script "$::WORK_DIR/lvs_netgen.tcl"
    set _fh [open $_script w]
    puts $_fh "set c2 \[readnet verilog [lindex $_nets 0]\]"
    foreach _n [lrange $_nets 1 end] { puts $_fh "readnet verilog $_n \$c2" }
    puts $_fh "set c1 \[readnet spice [oss_stage_out ${design_name}_extracted.spice]\]"
    puts $_fh "lvs \"\$c1 $design_name\" \"\$c2 $design_name\" [oss_get tech netgen,setup] $_rpt -json"
    close $_fh
    oss_exec_tool netgen $_script "$::REPORTS_DIR/lvs_netgen.log"
    if {![is_true $::flow(test_mode)]} {
        set _fh [open $_rpt]; set _txt [read $_fh]; close $_fh
        set _ok [regexp {Final result: (Circuits match uniquely|Netlists match)} $_txt -> _res]
        set _fh [open [oss_stage_out lvs.rpt] w]
        puts $_fh "design $design_name\nnetlists $_nets\nresult [expr {$_ok ? $_res : "MISMATCH"}]"
        close $_fh
        handle_info "Netgen LVS: [expr {$_ok ? $_res : "MISMATCH"}]"
        if {!$_ok} {
            if {[is_true [oss_get pv oss,fail_on_violations]]} { error "LVS mismatch — see $_rpt" }
            handle_warning "LVS mismatch — see $_rpt — reported, flow continues (pv(oss,fail_on_violations) false)"
        }
    }
}

flow_exec_all
exit
