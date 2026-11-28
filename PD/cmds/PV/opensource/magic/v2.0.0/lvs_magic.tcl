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
set NODE_NAME [cbflow_node_name]

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_utils.tcl"

set design_name [oss_get flow design_name]

if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

# Load: the staged GDS
flow_proc load_design {
    global design_name
    set ::lvs_gds "$::GDS_DIR/${design_name}.gds"
    if {![file exists $::lvs_gds]} { error "GDS not staged: $::lvs_gds (pv(input,gds))" }
}

# Magic extraction (hierarchical, LVS mode) -> outputs/<design>_extracted.spice
# (the layout netlist compare reads)
flow_proc extract {
    global design_name
    set _script "$::WORK_DIR/lvs_extract.tcl"
    set _fh [open $_script w]
    # Memory macros extract as abstract cells (pins only, from their LEF;
    # noduplicates keeps the GDS from replacing them) — black boxes in Netgen
    foreach _l [oss_memory_files lef] { puts $_fh "lef read $_l" }
    # pv(oss,pv,mode) hier: child blocks extract as abstract cells too
    set _abs [oss_has_memories]
    if {[pv_mode] eq "hier"} {
        foreach _b [hier_children $design_name] { puts $_fh "lef read [oss_get tech block,$_b,lef]"; set _abs 1 }
    }
    if {$_abs} { puts $_fh "gds noduplicates true" }
    puts $_fh "gds read $::lvs_gds"
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

# Netgen: extracted layout vs the staged power-aware netlist + every
# descendant block's LVS netlist -> reports/lvs_netgen.rpt
flow_proc compare {
    global design_name
    set _top [lindex [glob -nocomplain "$::NETLIST_DIR/${design_name}.lvs.v" "$::NETLIST_DIR/${design_name}.v"] 0]
    if {$_top eq ""} { error "netlist not staged in $::NETLIST_DIR (expected ${design_name}.lvs.v or ${design_name}.v; pv(input,netlist))" }
    set ::lvs_nets [list $_top]
    # flat: every descendant's LVS netlist; hier: children stay black boxes
    if {[pv_mode] eq "flat"} {
        foreach _b [hier_descendants $design_name] { lappend ::lvs_nets [oss_get tech block,$_b,lvs_netlist] }
    }
    set ::lvs_rpt "$::REPORTS_DIR/lvs_netgen.rpt"
    set _script "$::WORK_DIR/lvs_netgen.tcl"
    set _fh [open $_script w]
    puts $_fh "set c2 \[readnet verilog [lindex $::lvs_nets 0]\]"
    foreach _n [lrange $::lvs_nets 1 end] { puts $_fh "readnet verilog $_n \$c2" }
    puts $_fh "set c1 \[readnet spice [oss_stage_out ${design_name}_extracted.spice]\]"
    puts $_fh "lvs \"\$c1 $design_name\" \"\$c2 $design_name\" [oss_get tech netgen,setup] $::lvs_rpt -json"
    close $_fh
    oss_exec_tool netgen $_script "$::REPORTS_DIR/lvs_netgen.log"
}

# Report: the Netgen final result. Pass = it matches pv(signoff,lvs_pass)
# (the same regex the release verdict applies to lvs.rpt).
flow_proc report {
    if {![is_true $::flow(test_mode)]} {
        set _fh [open $::lvs_rpt]; set _txt [read $_fh]; close $_fh
        set _res ""
        regexp -line {Final result: ([^\n]*[^.\s])} $_txt -> _res
        set ::lvs_ok [expr {$_res ne "" && [regexp -- [oss_get pv signoff,lvs_pass] $_res]}]
        set ::lvs_result [expr {$::lvs_ok ? $_res : "MISMATCH"}]
    }
}

# Save the LVS result -> outputs/lvs.rpt
flow_proc save_design {
    global design_name
    if {![is_true $::flow(test_mode)]} {
        set _fh [open [oss_stage_out lvs.rpt] w]
        puts $_fh "design $design_name\nnetlists $::lvs_nets\nresult $::lvs_result"
        close $_fh
    }
}

# LVS gate — last, so lvs.rpt exists when it fails
flow_proc check_lvs {
    if {![is_true $::flow(test_mode)]} {
        handle_info "Netgen LVS: $::lvs_result"
        if {!$::lvs_ok} {
            if {[is_true [oss_get pv oss,fail_on_violations]]} { error "LVS mismatch — see $::lvs_rpt" }
            handle_warning "LVS mismatch — see $::lvs_rpt — reported, flow continues (pv(oss,fail_on_violations) false)"
        }
    }
}

flow_exec_all
exit
