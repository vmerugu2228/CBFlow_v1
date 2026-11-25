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

proc dft_py_script {} {
    if {![info exists ::env(CBFLOW_DFT_DIR)] || $::env(CBFLOW_DFT_DIR) eq ""} {
        error "CBFLOW_DFT_DIR is not set — the DFT tree is needed by the open-source DFT flows"
    }
    return "$::env(CBFLOW_DFT_DIR)/utils/oss/oss_dft.py"
}

# dft_run <log> <argv…> — run a tool, its output to <log>; on failure the
# error carries the log tail. Test mode prints the command and returns.
proc dft_run {log args} {
    if {[is_true [expr {[info exists ::flow(test_mode)] ? $::flow(test_mode) : false}]]} {
        puts "  TEST_CMD: $args (log $log)"
        return 0
    }
    file mkdir [file dirname $log]
    if {[catch {exec {*}$args >& $log} _err]} {
        set _tail ""
        catch { set _tail [exec tail -25 $log] }
        error "[lindex $args 0] failed (see $log): $_err\n$_tail"
    }
    return 0
}
proc dft_py {log args} { dft_run $log python3 [dft_py_script] {*}$args }

# The single input file a flow's input node staged: work/<FLOW>/<type>1/<type>/.
proc dft_input {type {pattern *}} {
    set _d "$::run_dir/work/$::FLOW_TYPE/${type}1/$type"
    # (the staging step leaves <type>_detail.log / <type>_info.tcl beside it)
    set _f [lsort [lsearch -all -inline -not -regexp [glob -nocomplain -types {f l} -directory $_d $pattern] \
                       "/${type}_(detail\\.log|info\\.tcl)\$"]]
    if {[llength $_f] != 1} {
        error "input '$type': expected one file matching '$pattern' in $_d, found [llength $_f] ([join [lmap x $_f {file tail $x}] {, }])"
    }
    set _p [lindex $_f 0]
    # staged inputs are links — the resolved file
    while {[file type $_p] eq "link"} { set _p [file normalize [file join [file dirname $_p] [file readlink $_p]]] }
    return $_p
}

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

# Value of `<label> : <number>` in a report (error when missing).
proc dft_report_value {file label} {
    set _fh [open $file]; set _t [read $_fh]; close $_fh
    if {![regexp -line "^\\s*[string map {( \\( ) \\) . \\. % \\%} $label]\\s*:\\s*(-?\[0-9.\]+)" $_t -> _v]} {
        error "'$label' not found in $file"
    }
    return $_v
}

# {category file} a downstream flow reads from this release:
# flow_input_handshake(<flow>,<input>) of the release config (PD tree — one
# handshake map for every discipline).
proc dft_release_name {flow input} {
    if {![array exists ::flow_input_handshake]} {
        uplevel #0 [list source "$::env(CBFLOW_CORE_DIR)/config/flow/[cbflow_version FLOW_CONFIG_VERSION]/release_config.tcl"]
    }
    if {![info exists ::flow_input_handshake($flow,$input)]} {
        error "flow_input_handshake($flow,$input) is not set (release_config.tcl)"
    }
    lassign $::flow_input_handshake($flow,$input) _src _cat _file
    return [list $_cat [string map [list {${design_name}} $::design_name] $_file]]
}

proc dft_test_mode {} {
    return [expr {[info exists ::flow(test_mode)] && [is_true $::flow(test_mode)]}]
}

# Run the command file's flow_proc steps. Test mode (command file run by the
# host tclsh, no container, no inputs) lists the steps instead — the handler
# writes the test-mode stub outputs.
proc dft_exec_all {} {
    if {[dft_test_mode]} {
        handle_info "TEST MODE — $::FLOW_TYPE/$::NODE_NAME steps (not executed): $::flow::steps"
        return
    }
    flow_exec_all
}

proc dft_write {file text} {
    file mkdir [file dirname $file]
    set _fh [open $file w]; puts -nonewline $_fh $text; close $_fh
}

# Words after `<label> : <n>` on a report line (e.g. the cell names of
# "Sequential types  : 2  a b").
proc dft_report_list {file label} {
    set _fh [open $file]; set _t [read $_fh]; close $_fh
    if {![regexp -line "^\\s*$label\\s*:\\s*\\d+\\s*(.*)\$" $_t -> _w]} { error "'$label' not found in $file" }
    return [string trim $_w]
}

# Chains of a CBflow scandef: {{flop …} …} in load order, one list per chain.
proc dft_scandef_chains {file} {
    set _fh [open $file]; set _t [read $_fh]; close $_fh
    set _out {}; set _cur {}; set _in 0
    foreach _l [split $_t \n] {
        if {[regexp {^- chain} $_l]} { if {$_in} { lappend _out $_cur }; set _cur {}; set _in 1; continue }
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

# Optional list key: <arr>(<key>) or {} when unset / empty.
proc oss_get_opt {arr key} {
    upvar #0 $arr _a
    return [expr {[info exists _a($key)] ? $_a($key) : {}}]
}
