#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow DV — open-source helpers (TB_SETUP, M1-M4_EXEC, DV_SIGNOFF: UVM on
# Verilator)
#
# Sourced by the DV command files of vendor opensource after oss_utils.tcl and
# oss_flow_utils.tcl. Stages run in the CBflow tool container (tool shell
# verilator → the container's tclsh): Verilator + UVM (UVM_HOME), z3 (the
# constraint solver), ccache (CCACHE_DIR), DV/utils/oss/{uvmgen,dv_tool}.py.
# ═══════════════════════════════════════════════════════════════════════════════

proc dv_tool {log args} { oss_py $log "$::env(CBFLOW_DV_DIR)/utils/oss/dv_tool.py" {*}$args }
proc uvmgen  {log args} { oss_py $log "$::env(CBFLOW_DV_DIR)/utils/oss/uvmgen.py" {*}$args }

# The testbench directory of a compile list (its +incdir+ line).
proc dv_tb_dir {tbf} {
    set _fh [open $tbf]; set _t [read $_fh]; close $_fh
    if {![regexp -line {^\+incdir\+(\S+)} $_t -> _d]} { error "$tbf: no +incdir+ line (uvmgen compile list expected)" }
    return $_d
}

# DUT sources of a testbench (rtl.f beside tb.f): the code-coverage scope.
proc dv_dut_files {tbf} {
    set _rf "[dv_tb_dir $tbf]/rtl.f"
    if {![file exists $_rf]} { error "$_rf not found (uvmgen writes it beside tb.f)" }
    set _fh [open $_rf]; set _t [string trim [read $_fh]]; close $_fh
    return [split $_t \n]
}

# Verilator build of the UVM testbench <tbf> (top <design>_tb_top) with
# coverage -> <outdir>/sim. <arr>(oss,verilator,flags|jobs).
proc dv_build {arr tbf outdir log} {
    if {![info exists ::env(UVM_HOME)] || ![file isdirectory "$::env(UVM_HOME)/src"]} {
        error "UVM_HOME not set / no UVM sources — install with global/utils/oss/install_uvm.sh (cbflow-oss exports UVM_HOME)"
    }
    set _u "$::env(UVM_HOME)/src"
    file mkdir "$outdir/obj"                 ;# Verilator creates only the last -Mdir level
    oss_run $log env OBJCACHE=ccache verilator --binary --timing --coverage \
        -j [oss_get $arr oss,verilator,jobs] {*}[oss_get_opt $arr oss,verilator,flags] \
        +define+UVM_NO_DPI +incdir+$_u $_u/uvm_pkg.sv -f $tbf \
        --top-module ${::design_name}_tb_top -Mdir "$outdir/obj" -o sim
    file copy -force "$outdir/obj/sim" "$outdir/sim"
    return "$outdir/sim"
}

# project(dv,targets,<M>) as dv_tool --targets k=v arguments.
proc dv_targets {milestone} {
    global project
    if {![info exists project(dv,targets,$milestone)]} {
        error "project(dv,targets,$milestone) is not set (DV project overlay <proj>_dv_config.tcl)"
    }
    return [lmap {_k _v} $project(dv,targets,$milestone) {set _x "$_k=$_v"}]
}

# Report value "<key> : <value>" (first match) or "".
proc dv_status {rpt} {
    set _fh [open $rpt]; set _t [read $_fh]; close $_fh
    return [expr {[regexp -line {^\s*Status\s*:\s*(\S+)} $_t -> _s] ? $_s : ""}]
}
