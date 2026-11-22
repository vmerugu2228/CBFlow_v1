#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow LEC — compare (opensource / yosys)
# Gate-level equivalence golden (e.g. SYNTH release) vs revised (e.g. PNR
# release): cell functions from the liberty (read_liberty), physical-only
# cells as empty stubs, child hard blocks as blackboxes (library tag);
# compare points matched by name (equiv_make), proven with equiv_simple +
# equiv_induct. (EQY's partitioner rejects the buffer aliases post-PnR
# netlists contain; this is the same Yosys equivalence engine without it.)
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "LEC"
set STAGE_NAME "compare"
set NODE_NAME [cbflow_node_name]

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_utils.tcl"

set design_name [oss_get flow design_name]
set blocks      [hier_children $design_name]

if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

# Staged netlist of input type netlist_<kind>: the upstream "inputs" node
# netlist_<kind><n> (RACE engine: input type = node name without its number)
# stages it under <node>/netlist_<kind>/<design>.v.
proc lec_netlist {kind} {
    set _it "netlist_${kind}"
    foreach _n [cbflow_node_deps $::NODE_NAME] {
        if {[cbflow_node_type $_n] ne "inputs" || [string trimright $_n 0123456789] ne $_it} continue
        set _f "[cbflow_node_dir $_n]/$_it/${::design_name}.v"
        if {![file exists $_f]} { error "$kind netlist not staged: $_f (lec(input,$_it) / release tag)" }
        return $_f
    }
    error "no $_it input node among the dependencies of $::NODE_NAME (lec(dependencies,$::NODE_NAME))"
}

flow_proc compare {
    global design_name blocks
    # cell functions are corner-independent: one lib set (lec(oss,lec,lib_set))
    set _ls   [oss_get lec oss,lec,lib_set]
    set _libs [oss_lib_set_files $_ls]
    # physical-only cells (no liberty function): empty stub modules
    set _stub "$::WORK_DIR/phys_stubs.v"
    set _fh [open $_stub w]
    foreach _c [concat [oss_trk fillers] [oss_trk well_tap]] { puts $_fh "module $_c (); endmodule" }
    close $_fh
    foreach {_tag _nl} [list gold [lec_netlist golden] gate [lec_netlist revised]] {
        foreach _l $_libs { yosys read_liberty -ignore_miss_func $_l }
        foreach _b $blocks {
            yosys read_liberty -lib [oss_get tech block,$_b,lib,$_ls]
        }
        yosys read_verilog -lib $_stub
        yosys read_verilog $_nl
        yosys hierarchy -top $design_name
        yosys flatten
        yosys opt_clean -purge
        yosys rename $design_name $_tag
        yosys design -stash $_tag
    }
    yosys design -copy-from gold -as gold gold
    yosys design -copy-from gate -as gate gate
    yosys equiv_make gold gate equiv
    yosys hierarchy -top equiv
    yosys async2sync
    yosys equiv_simple -seq [oss_get lec oss,lec,seq_depth]
    yosys equiv_induct -seq [oss_get lec oss,lec,seq_depth]
    yosys tee -o "$::REPORTS_DIR/equiv_status.rpt" equiv_status
}

flow_proc verdict {
    global design_name
    set _fh [open "$::REPORTS_DIR/equiv_status.rpt"]; set _t [read $_fh]; close $_fh
    set _tot 0; set _pro 0; set _unp 0
    regexp {Found (\d+) \$equiv cells} $_t -> _tot
    regexp {(\d+) are proven and (\d+) are unproven} $_t -> _pro _unp
    set _ok [expr {[string match "*Equivalence successfully proven*" $_t] && $_unp == 0}]
    set _fh [open [oss_stage_out lec.rpt] w]
    puts $_fh "design $design_name"
    puts $_fh "golden [lec_netlist golden]"
    puts $_fh "revised [lec_netlist revised]"
    puts $_fh "compare_points $_tot\nproven $_pro\nunproven $_unp"
    puts $_fh "result [expr {$_ok ? "EQUIVALENT" : "NOT EQUIVALENT"}]"
    close $_fh
    handle_info "LEC $design_name: [expr {$_ok ? "EQUIVALENT" : "NOT EQUIVALENT"}] ($_pro/$_tot proven, $_unp unproven)"
    if {!$_ok} {
        if {[is_true [oss_get lec oss,fail_on_violations]]} { error "LEC: $_unp unproven compare point(s) — see $::REPORTS_DIR/equiv_status.rpt" }
        handle_warning "LEC: $_unp unproven compare point(s) — reported, flow continues"
    }
}

flow_exec_all
exit
