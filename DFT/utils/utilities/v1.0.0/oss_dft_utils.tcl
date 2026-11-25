#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow DFT — open-source helpers (SCAN_INSERT / ATPG / GLS_FUNC / GLS_SCAN_MBIST)
#
# Sourced by the DFT command files of vendor opensource after oss_utils.tcl.
# Command files run inside the CBflow tool container (tool shells fault /
# iverilog / oss_tclsh → the container's tclsh), so the tools — fault,
# nl2bench, atalanta (lsf(oss,tools_dir)), yosys, iverilog / vvp, python3 —
# are exec'd directly. The netlist / pattern work is done by
# DFT/utils/oss/oss_dft.py (liberty scan cells, chain tracing, bench
# cleanup, Atalanta pattern mapping, testbenches, fault simulation).
# ═══════════════════════════════════════════════════════════════════════════════

source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_flow_utils.tcl"
# generic helpers live in oss_flow_utils.tcl (shared with RTL / DV); the dft_
# names the DFT command files use
foreach {_dft _oss} {dft_run oss_run dft_input oss_input dft_report_value oss_report_value
                     dft_report_list oss_report_list dft_release_name oss_release_name
                     dft_test_mode oss_test_mode dft_exec_all oss_exec_all dft_write oss_write_file} {
    interp alias {} $_dft {} $_oss
}
unset _dft _oss

proc dft_py_script {} {
    if {![info exists ::env(CBFLOW_DFT_DIR)] || $::env(CBFLOW_DFT_DIR) eq ""} {
        error "CBFLOW_DFT_DIR is not set — the DFT tree is needed by the open-source DFT flows"
    }
    return "$::env(CBFLOW_DFT_DIR)/utils/oss/oss_dft.py"
}

proc dft_py {log args} { dft_run $log python3 [dft_py_script] {*}$args }

# Liberty of the node's first lib set (its MMMC view, mmmc_node_scenarios.tcl).
proc dft_libs {stage} { return [oss_lib_set_files [lindex [oss_node_lib_sets $stage] 0]] }

# Gate-level simulation models: cell primitives + cell models of the track.
proc dft_cell_models {} { return [list [oss_trk verilog_primitives] [oss_trk verilog_stdcell]] }

# Verilog of the blackboxed macros (memories from the library tag, child
# blocks from their releases) — read as blackboxes for port directions.
proc dft_macro_models {design} {
    set _out [oss_memory_files verilog]
    foreach _b [hier_children $design] { lappend _out [dict get [hier_block_views $_b] netlist] }
    return $_out
}

# Flattened netlist as Yosys JSON (library cells / macros blackboxed) — what
# oss_dft.py reads.
proc dft_netlist_json {netlist design libs json log} {
    set _ys "[file rootname $json].ys"
    set _fh [open $_ys w]
    foreach _l $libs { puts $_fh "read_liberty -lib $_l" }
    foreach _m [dft_macro_models $design] { puts $_fh "read_verilog -lib $_m" }
    puts $_fh "read_verilog $netlist"
    puts $_fh "hierarchy -top $design"
    puts $_fh "write_json $json"
    close $_fh
    dft_run $log yosys -q -s $_ys
}

# Ports held at a constant in ATPG / pattern simulation (async resets,
# test-mode pins): <arr>(oss,hold_ports) {port value …} → {port=value …}
proc dft_holds {arr} {
    upvar #0 $arr _a
    set _out {}
    if {[info exists _a(oss,hold_ports)]} {
        foreach {_p _v} $_a(oss,hold_ports) {
            if {$_v ni {0 1}} { error "${arr}(oss,hold_ports): $_p value must be 0 or 1, got '$_v'" }
            lappend _out "$_p=$_v"
        }
    }
    return $_out
}

# iverilog compile + vvp run. Returns the simulation log path; the compile
# log is <log>.compile. Defines: FUNCTIONAL (zero-delay cell models),
# UNIT_DELAY=#1, plus <defs>.
proc dft_simulate {files top vvp log {defs {}} {plusargs {}}} {
    set _d {}
    foreach _x [concat FUNCTIONAL UNIT_DELAY=#1 $defs] { lappend _d "-D$_x" }
    dft_run "$log.compile" iverilog -g2012 {*}$_d -s $top -o $vvp {*}$files
    dft_run $log vvp -n $vvp {*}$plusargs
    return $log
}

# Chains of a CBflow scandef: {{flop …} …} in load order, one list per chain.
proc dft_scandef_chains {file} {
    set _fh [open $file]; set _t [read $_fh]; close $_fh
    set _out {}; set _cur {}; set _in 0
    foreach _l [split $_t \n] {
        if {[regexp {^-\s} $_l]} { if {$_in} { lappend _out $_cur }; set _cur {}; set _in 1; continue }
        if {[regexp {^\s+(\S+) \( IN } $_l -> _f]} { lappend _cur $_f }
    }
    if {$_in} { lappend _out $_cur }
    return $_out
}

# Scan clock (port) of a scan_chains.rpt — the open-source ATPG / pattern
# testbench supports one scan clock.
proc dft_scan_clock {rpt} {
    set _fh [open $rpt]; set _t [read $_fh]; close $_fh
    set _ports [lsort -unique [lmap {_m _p} [regexp -all -inline {clock (\S+)/(?:pos|neg)} $_t] {set _p}]]
    if {[llength $_ports] != 1} { error "one scan clock expected, chains use: $_ports ($rpt)" }
    return [lindex $_ports 0]
}

