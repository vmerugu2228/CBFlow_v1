#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow — open-source flow helpers shared by the RTL / DFT / DV command files
#
# Sourced (after utils.tcl / oss_utils.tcl) by the vendor-opensource command
# files that run as Tcl drivers inside the CBflow tool container (tool shells
# fault / iverilog / verilator / rtlcheck / vplan / oss_tclsh → the container's
# tclsh): run a tool with its log, find a staged input, read report values,
# write files, look up a release name, and the test-mode step wrapper.
# Discipline helpers (oss_dft_utils.tcl, oss_rtl_utils.tcl, …) build on these.
# ═══════════════════════════════════════════════════════════════════════════════

proc oss_test_mode {} {
    return [expr {[info exists ::flow(test_mode)] && [is_true $::flow(test_mode)]}]
}

# oss_run <log> <argv…> — run a tool, its output to <log>; on failure the
# error carries the log tail. Test mode prints the command and returns.
proc oss_run {log args} {
    if {[oss_test_mode]} {
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

# The single input file a flow's input node staged: work/<FLOW>/<type>1/<type>/.
proc oss_input {type {pattern *}} {
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

# Value of `<label> : <number>` in a report (error when missing).
proc oss_report_value {file label} {
    set _fh [open $file]; set _t [read $_fh]; close $_fh
    if {![regexp -line "^\\s*[string map {( \\( ) \\) . \\. % \\%} $label]\\s*:\\s*(-?\[0-9.\]+)" $_t -> _v]} {
        error "'$label' not found in $file"
    }
    return $_v
}

# Words after `<label> : <n>` on a report line (e.g. the cell names of
# "Sequential types  : 2  a b").
proc oss_report_list {file label} {
    set _fh [open $file]; set _t [read $_fh]; close $_fh
    if {![regexp -line "^\\s*$label\\s*:\\s*\\d+\\s*(.*)\$" $_t -> _w]} { error "'$label' not found in $file" }
    return [string trim $_w]
}

# {category file} a downstream flow reads from this release:
# flow_input_handshake(<flow>,<input>) of the release config (PD tree — one
# handshake map for every discipline).
proc oss_release_name {flow input} {
    if {![array exists ::flow_input_handshake]} {
        uplevel #0 [list source "$::env(CBFLOW_CORE_DIR)/config/flow/[cbflow_version FLOW_CONFIG_VERSION]/release_config.tcl"]
    }
    if {![info exists ::flow_input_handshake($flow,$input)]} {
        error "flow_input_handshake($flow,$input) is not set (release_config.tcl)"
    }
    lassign $::flow_input_handshake($flow,$input) _src _cat _file
    return [list $_cat [string map [list {${design_name}} $::design_name] $_file]]
}

# Run the command file's flow_proc steps. Test mode (command file run by the
# host tclsh, no container, no inputs) lists the steps instead — the handler
# writes the test-mode stub outputs.
proc oss_exec_all {} {
    if {[oss_test_mode]} {
        handle_info "TEST MODE — $::FLOW_TYPE/$::NODE_NAME steps (not executed): $::flow::steps"
        return
    }
    flow_exec_all
}

proc oss_write_file {file text} {
    file mkdir [file dirname $file]
    set _fh [open $file w]; puts -nonewline $_fh $text; close $_fh
}

# Optional list key: <arr>(<key>) or {} when unset / empty.
proc oss_get_opt {arr key} {
    upvar #0 $arr _a
    return [expr {[info exists _a($key)] ? $_a($key) : {}}]
}

# python3 on a CBflow helper script, with the tool-dir Python packages
# (CBFLOW_OSS_PYTHON — PeakRDL, openpyxl) on that process's path only.
proc oss_py {log script args} {
    set _env {}
    if {[info exists ::env(CBFLOW_OSS_PYTHON)] && $::env(CBFLOW_OSS_PYTHON) ne ""} {
        set _env [list env PYTHONPATH=$::env(CBFLOW_OSS_PYTHON)]
    }
    oss_run $log {*}$_env python3 $script {*}$args
}
