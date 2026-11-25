#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow RTL — open-source helpers (RTL_LINT / RTL_CDC / UPF_CHECK)
#
# Sourced by the RTL command files of vendor opensource after oss_utils.tcl and
# oss_flow_utils.tcl. The checks run in the CBflow tool container (tool shells
# rtlcheck / verilator / oss_tclsh → the container's tclsh): slang, Verilator,
# Verible, sv2v, yosys (+ slang plugin), opencdc, and
# RTL/utils/oss/rtl_check.py for the violations CSV / waivers / sign-off.
# ═══════════════════════════════════════════════════════════════════════════════

proc rtl_check_script {} { return "$::env(CBFLOW_RTL_DIR)/utils/oss/rtl_check.py" }
proc rtl_py {log args} { oss_py $log [rtl_check_script] {*}$args }

# RTL top: <arr>(oss,top), else the design.
proc rtl_top {} {
    set _t [oss_get_opt [oss_flow_arr] oss,top]
    return [expr {$_t ne "" ? $_t : $::design_name}]
}

# Sources of the staged RTL filelist (input rtl): absolute paths, in order.
proc rtl_sources {} {
    set _fh [open [oss_input rtl]]; set _t [read $_fh]; close $_fh
    set _out {}
    foreach _l [split $_t \n] {
        set _l [string trim $_l]
        if {$_l eq "" || [string match "#*" $_l] || [string match "//*" $_l]} continue
        if {![file exists $_l]} { error "RTL source not found: $_l ([oss_input rtl])" }
        lappend _out $_l
    }
    if {![llength $_out]} { error "RTL filelist [oss_input rtl] is empty" }
    return $_out
}

# Blackbox stubs (ports only) of the memories of the library tag and the
# child blocks — the RTL instantiates them; lint / CDC tools need their
# interfaces. Verilator warnings inside the stubs are switched off.
proc rtl_write_stubs {out log} {
    set _cmds {}
    foreach _m [oss_memory_files verilog] { lappend _cmds "read_verilog -lib $_m" }
    foreach _b [hier_children $::design_name] {
        lappend _cmds "read_verilog -lib [dict get [hier_block_views $_b] netlist]"
    }
    set _raw "[file rootname $out].raw.v"
    if {[llength $_cmds]} {
        lappend _cmds "write_verilog -blackboxes -noattr $_raw"
        oss_run $log yosys -q -p [join $_cmds "; "]
        set _fh [open $_raw]; set _body [read $_fh]; close $_fh
    } else {
        set _body ""
    }
    oss_write_file $out "/* verilator lint_off */\n// CBflow: blackbox stubs (memories / child blocks)\n$_body/* verilator lint_on */\n"
}

# Common init stage: the sources (sources.f) and the stubs (stubs.v).
proc rtl_init {} {
    set _src [rtl_sources]
    oss_write_file [oss_stage_out sources.f] "[join $_src \n]\n"
    rtl_write_stubs [oss_stage_out stubs.v] "$::REPORTS_DIR/stubs.log"
    handle_info "[llength $_src] RTL source(s), top [rtl_top]"
}

proc rtl_init_out {file} { return "[cbflow_node_dir [oss_chain_node init]]/outputs/$file" }
proc rtl_init_sources {} {
    set _fh [open [rtl_init_out sources.f]]; set _t [string trim [read $_fh]]; close $_fh
    return [split $_t \n]
}

# Waivers (<arr>(oss,waivers)) on the stage's violations.csv →
# violations_final.csv + waivers.rpt.
proc rtl_waive {violations} {
    set _w [oss_get_opt [oss_flow_arr] oss,waivers]
    set _wa [expr {$_w ne "" ? [list --waivers $_w] : {}}]
    if {$_w ne "" && ![file exists $_w]} { error "[oss_flow_arr](oss,waivers): $_w not found" }
    rtl_py "$::REPORTS_DIR/waive.log" waive --violations $violations {*}$_wa \
        -o [oss_stage_out violations_final.csv] --report "$::REPORTS_DIR/waivers.rpt"
    file copy -force [oss_stage_out violations_final.csv] "$::REPORTS_DIR/violations_final.csv"
}

# Sign-off of violations_final.csv: <rpt>, outputs/signoff.status; a FAIL
# fails the stage.
proc rtl_signoff {check rpt} {
    set _vf "[cbflow_node_dir [oss_chain_node waiver_apply]]/outputs/violations_final.csv"
    set _fw [expr {[is_true [oss_get [oss_flow_arr] oss,signoff,fail_on_warning]] ? "true" : "false"}]
    rtl_py "$::REPORTS_DIR/signoff.log" summary --violations $_vf --check $check --design $::design_name \
        --fail-on-warning $_fw -o "$::REPORTS_DIR/$rpt"
    set _st [expr {[string match "*Status          : PASS*" [read [set _h [open "$::REPORTS_DIR/$rpt"]]]] ? "PASS" : "FAIL"}]
    close $_h
    oss_write_file [oss_stage_out signoff.status] "$_st\n"
    file copy -force $_vf "$::REPORTS_DIR/violations_final.csv"
    if {$_st ne "PASS"} {
        error "$check sign-off FAILED: [oss_report_value $::REPORTS_DIR/$rpt {Open errors}] open error(s), [oss_report_value $::REPORTS_DIR/$rpt {Open warnings}] open warning(s) — $::REPORTS_DIR/$rpt"
    }
    handle_info "$check sign-off PASS"
}

# Release of an RTL check: the sign-off report, violations, waivers (+ files).
proc rtl_release_reports {} {
    foreach _t {init compile waiver_apply} {
        catch { ::CBFlow::Release::copy_glob "[cbflow_node_dir [oss_chain_node $_t]]/reports/*.rpt" reports }
    }
    set _w [oss_get_opt [oss_flow_arr] oss,waivers]
    if {$_w ne ""} { ::CBFlow::Release::copy_file $_w reports [file tail $_w] }
}
