#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow SYNTH — synthesis (opensource / yosys)
# Read the RTL filelist (library cells and child blocks as blackboxes —
# children come from the library tag), elaborate, synthesize and map to the
# active track's cells on the node's first lib set; netlist + area report.
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "SYNTH"
set STAGE_NAME "synthesis"
set NODE_NAME [cbflow_node_name]

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_utils.tcl"

set design_name [oss_get flow design_name]
set blocks      [hier_children $design_name]

if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

# write_port_stub <netlist> <module> <stub> — the module statement and its
# input/output/inout declarations, streamed from the head of the netlist.
proc write_port_stub {netlist module stub} {
    set _in [open $netlist]
    set _keep {}; set _stmt ""; set _found 0
    while {[gets $_in _line] >= 0} {
        append _stmt " " [string trim $_line]
        while {[set _i [string first ";" $_stmt]] >= 0} {
            set _s [string trim [string range $_stmt 0 $_i]]
            set _stmt [string range $_stmt [expr {$_i + 1}] end]
            if {!$_found} {
                if {[regexp -- "^module\\s+\\\\?$module\[\\s(;\]" $_s]} { set _found 1; lappend _keep $_s }
            } elseif {[regexp {^(input|output|inout)\M} $_s]} {
                lappend _keep $_s
            } else {
                break
            }
        }
        if {$_found && $_i >= 0} break
    }
    close $_in
    if {!$_found} { error "write_port_stub: module $module not found in $netlist" }
    set _out [open $stub w]
    puts $_out "[join $_keep \n]\nendmodule"
    close $_out
}

flow_proc read_design {
    global design_name blocks synth
    set _lib_set [lindex [oss_node_lib_sets $::NODE_NAME] 0]
    set ::oss_libs [oss_lib_set_files $_lib_set]
    handle_info "Mapping library set: $_lib_set"
    # Cell library as blackboxes: RTL may instantiate library cells directly.
    foreach _l $::oss_libs { yosys read_liberty -lib $_l }
    # Staged by the rtl input node under the name of synth(input,rtl_filelist).
    set _fl "$::RTL_DIR/[file tail [cbflow_require synth input,rtl_filelist]]"
    if {![file exists $_fl]} { error "RTL filelist not staged: $_fl (synth(input,rtl_filelist))" }
    set _sv [expr {[oss_get synth input,rtl_format] eq "sverilog" ? "-sv" : ""}]
    set _fh [open $_fl]
    foreach _src [split [read $_fh] "\n"] {
        set _src [string trim $_src]
        if {$_src eq "" || [string match "#*" $_src] || [string match "//*" $_src]} continue
        handle_info "  RTL: $_src"
        yosys read_verilog {*}$_sv -defer $_src
    }
    close $_fh
    # Hard-macro children: interface only, from the library tag. A child's
    # gate netlist can be ~100 MB; read a ports-only stub cut from its header.
    foreach _b $blocks {
        set _v [hier_block_views $_b]
        handle_info "  child block $_b ([hier_level $_b]) from [dict get $_v release]"
        set _stub "[cbflow_node_dir $::NODE_NAME]/run/${_b}.bb.v"
        write_port_stub [dict get $_v netlist] $_b $_stub
        yosys read_verilog -lib $_stub
    }
    yosys hierarchy -check -top $design_name
    yosys tee -o "$::REPORTS_DIR/synthesis_hierarchy.rpt" ls
}

# Synthesis + technology mapping (netlist written by write_design)
flow_proc synthesize {
    global design_name synth
    set _libs $::oss_libs
    set _flat [expr {[is_true [oss_get synth oss,synth,flatten]] ? "-flatten" : ""}]
    yosys synth -top $design_name {*}$_flat
    yosys opt_clean -purge
    set _dont_use {}
    foreach _c [oss_trk dont_use] { lappend _dont_use -dont_use $_c }
    foreach _l $_libs { yosys dfflibmap -liberty $_l }
    set _abc [list abc -liberty [lindex $_libs 0] {*}$_dont_use]
    set _d [oss_get synth oss,synth,abc_delay_ps]
    if {$_d > 0} { lappend _abc -D $_d }
    yosys {*}$_abc
    lassign [split [oss_trk tie_hi] /] _hi_cell _hi_pin
    lassign [split [oss_trk tie_lo] /] _lo_cell _lo_pin
    yosys hilomap -singleton -hicell $_hi_cell $_hi_pin -locell $_lo_cell $_lo_pin
    yosys setundef -zero
    yosys splitnets
    # tech(<track>,buffer_cell) = <cell>/<in pin>/<out pin>
    lassign [split [oss_trk buffer_cell] /] _buf_cell _buf_in _buf_out
    if {$_buf_out eq ""} { error "tech key [oss_track],buffer_cell must be <cell>/<in pin>/<out pin>, got '[oss_trk buffer_cell]'" }
    yosys insbuf -buf $_buf_cell $_buf_in $_buf_out
    yosys opt_clean -purge
    yosys check -assert
}

# Reports of the mapped design
flow_proc report {
    yosys tee -o "$::REPORTS_DIR/synthesis_stat.rpt" stat -liberty [lindex $::oss_libs 0]
}

# Save the mapped netlist — synthesis.v, or synthesis_pre_dft.v when DFT
# (project(dft,enable)) inserts scan into it next
flow_proc write_design {
    set _out [expr {[is_true [oss_get project dft,enable]] ? "synthesis_pre_dft.v" : "synthesis.v"}]
    yosys write_verilog -noattr -noexpr -nohex -nodec [oss_stage_out $_out]
}

# Scan insertion (project(dft,enable)): OpenROAD DFT on the mapped netlist —
# scan_replace (flops -> scan flops) + execute_dft_plan (chains stitched,
# scan_enable_* / scan_in_* / scan_out_* ports added) -> synthesis.v. SDCs:
# synthesis.func.sdc (scan_enable held 0) and synthesis.scan.sdc (scan_enable
# 1, shift mode). Child macros keep their own chains (not stitched here).
flow_proc dft_insert {
    global design_name blocks
    if {![is_true [oss_get project dft,enable]]} {
        handle_info "DFT off (project(dft,enable)) — no scan insertion"
        return
    }
    set _lib_set [lindex [oss_node_lib_sets $::NODE_NAME] 0]
    set _sdc [lindex [glob -nocomplain "$::SDC_DIR/${design_name}.*.sdc" "$::SDC_DIR/${design_name}.sdc"] 0]
    if {$_sdc eq ""} { error "SDC not staged in $::SDC_DIR (${design_name}.sdc)" }
    set _or "$::WORK_DIR/run/dft_insert.tcl"
    set _fh [open $_or w]
    puts $_fh "read_lef [oss_ms "[oss_track],lef_tech"]"
    foreach _l [oss_trk lef] { puts $_fh "read_lef $_l" }
    foreach _l $::oss_libs { puts $_fh "read_liberty $_l" }
    foreach _b $blocks {
        set _v [hier_block_views $_b]
        puts $_fh "read_lef [dict get $_v lef]"
        # linking needs the child's pins / functions, not its timing: the
        # mapping lib set when the child has it, else its first lib set
        set _cls [oss_get tech block,$_b,lib_sets]
        set _cl [expr {$_lib_set in $_cls ? $_lib_set : [lindex $_cls 0]}]
        puts $_fh "read_liberty [hier_block_lib $_v $_b $_cl]"
    }
    puts $_fh "read_verilog [oss_stage_out synthesis_pre_dft.v]"
    puts $_fh "link_design $design_name"
    puts $_fh "read_sdc $_sdc"
    puts $_fh "set_dft_config -max_length [oss_get project dft,max_chain_length] -clock_mixing [oss_get project dft,clock_mixing]"
    puts $_fh "scan_replace"
    puts $_fh "execute_dft_plan"
    puts $_fh "report_dft_plan"           ;# to the log; cut into dft_plan.rpt below
    puts $_fh "write_verilog [oss_stage_out synthesis.v]"
    puts $_fh "exit"
    close $_fh
    set _log "$::REPORTS_DIR/dft_insert.log"
    if {[is_true $::flow(test_mode)]} {
        file copy -force [oss_stage_out synthesis_pre_dft.v] [oss_stage_out synthesis.v]
    } elseif {[catch {exec {*}[oss_get synth oss,dft,openroad_cmd] $_or >& $_log} _e]} {
        error "DFT insertion failed (see $_log): $_e"
    }
    # SDCs: functional (scan_enable 0) and scan shift (scan_enable 1)
    set _fh [open $_sdc]; set _base [read $_fh]; close $_fh
    foreach {_mode _val} {func 0 scan 1} {
        set _fh [open [oss_stage_out synthesis.$_mode.sdc] w]
        puts $_fh $_base
        puts $_fh "\n# DFT ($_mode mode): scan enable held at $_val"
        puts $_fh "set_case_analysis $_val \[get_ports {[oss_get project dft,scan_enable_pattern]}\]"
        close $_fh
    }
    if {![is_true $::flow(test_mode)]} {
        set _fh [open $_log]; set _lg [read $_fh]; close $_fh
        set _i [string first "Report DFT Plan" $_lg]
        if {$_i < 0} { error "DFT plan not reported (see $_log)" }
        set _t [string range $_lg $_i end]
        set _fh [open "$::REPORTS_DIR/dft_plan.rpt" w]; puts -nonewline $_fh $_t; close $_fh
        regexp {Number of chains: (\d+)} $_t -> _nc
        set _nb 0; foreach {_ _b} [regexp -all -inline {has (\d+) cells} $_t] { incr _nb $_b }
        handle_info "DFT: $_nc scan chain(s), $_nb scan flops"
    }
}

flow_exec_all
exit
