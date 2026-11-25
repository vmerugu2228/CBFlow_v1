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
    # Memory macros (library tag): blackboxes from their timing lib
    foreach _l [oss_memory_libs $_lib_set] { yosys read_liberty -lib $_l }
    # Staged by the rtl input node under the name of synth(input,rtl_filelist).
    set _fl "$::RTL_DIR/[file tail [cbflow_require synth input,rtl_filelist]]"
    if {![file exists $_fl]} { error "RTL filelist not staged: $_fl (synth(input,rtl_filelist))" }
    # Hard-macro children: interface only, from the library tag. A child's
    # gate netlist can be ~100 MB; read a ports-only stub cut from its header.
    # Read before the RTL so every front end sees them as blackboxes.
    foreach _b $blocks {
        set _v [hier_block_views $_b]
        handle_info "  child block $_b ([hier_level $_b]) from [dict get $_v release]"
        set _stub "[cbflow_node_dir $::NODE_NAME]/run/${_b}.bb.v"
        write_port_stub [dict get $_v netlist] $_b $_stub
        yosys read_verilog -lib $_stub
    }
    set _srcs {}
    set _fh [open $_fl]
    foreach _src [split [read $_fh] "\n"] {
        set _src [string trim $_src]
        if {$_src eq "" || [string match "#*" $_src] || [string match "//*" $_src]} continue
        handle_info "  RTL: $_src"
        lappend _srcs $_src
    }
    close $_fh
    # synth(input,rtl_format): verilog -> yosys's Verilog front end;
    # sverilog -> the slang front end (yosys-slang plugin: full IEEE 1800 —
    # packages, structs, interfaces, the PeakRDL register block), the whole
    # filelist elaborated at once from the top
    switch -- [oss_get synth input,rtl_format] {
        verilog  { foreach _src $_srcs { yosys read_verilog -defer $_src } }
        sverilog {
            yosys plugin -i slang
            yosys read_slang --top $design_name {*}$_srcs
        }
        default  { error "synth(input,rtl_format) must be verilog or sverilog, got '[oss_get synth input,rtl_format]'" }
    }
    yosys hierarchy -check -top $design_name
    # Memory macro instances are kept even with unused outputs (hard macros)
    foreach _m [oss_memory_cells] { yosys setattr -set keep 1 t:$_m }
    yosys tee -o "$::REPORTS_DIR/synthesis_hierarchy.rpt" ls
}

# Synthesis + technology mapping (netlist written by write_design)
flow_proc synthesize {
    global design_name synth
    set _libs $::oss_libs
    handle_info "Vt flavours [oss_get project vt_flavors] of {[oss_get tech vt_variants_available]}; [llength $_libs] librar[expr {[llength $_libs] == 1 ? "y" : "ies"}]"
    set _flat [expr {[is_true [oss_get synth oss,synth,flatten]] ? "-flatten" : ""}]
    # begin + coarse (memories inferred), report them, then the rest
    yosys synth -top $design_name {*}$_flat -run :fine
    synth_memory_report
    yosys synth -top $design_name {*}$_flat -run fine:
    yosys opt_clean -purge
    synth_clock_gating
    set _dont_use {}
    foreach _c [concat [oss_trk dont_use] [oss_vt_dont_use]] { lappend _dont_use -dont_use $_c }
    set _lib_args {}
    foreach _l $_libs { lappend _lib_args -liberty $_l }
    yosys dfflibmap {*}$_lib_args {*}$_dont_use
    set _abc [list abc {*}$_lib_args {*}$_dont_use]
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

# Memories (register arrays) inferred in the coarse pass: synthesis_memory.rpt.
# Synthesis maps them to flops (memory_map), clock-gated with the other flops.
proc synth_memory_report {} {
    set _rpt "$::REPORTS_DIR/synthesis_memory.rpt"
    yosys tee -q -o $_rpt select -list t:\$mem_v2
    set _fh [open $_rpt]; set _m [string trim [read $_fh]]; close $_fh
    set _n [expr {$_m eq "" ? 0 : [llength [split $_m \n]]}]
    set _fh [open $_rpt w]
    puts $_fh "# Memories inferred (mapped to register arrays): $_n"
    if {$_n > 0} { puts $_fh $_m }
    close $_fh
    handle_info "Memories inferred: $_n (register arrays)"
}

# Clock gating (synth(oss,clock_gating,enable)): flops sharing clock + enable
# -> ICG + enable-less flops. With DFT the scan ICG, its test enable tied low
# here and connected to scan enable by dft_insert.
proc synth_clock_gating {} {
    if {![is_true [oss_get synth oss,clock_gating,enable]]} {
        handle_info "Clock gating off (synth(oss,clock_gating,enable))"
        return
    }
    set _dft [is_true [oss_get project dft,enable]]
    set _spec [oss_trk [expr {$_dft ? "icg_scan_cell" : "icg_cell"}]]
    lassign [split $_spec /] _cell _en _clk _gclk _te
    if {$_gclk eq "" || ($_dft && $_te eq "")} {
        error "tech key [oss_track],[expr {$_dft ? "icg_scan_cell" : "icg_cell"}] must be <cell>/<enable>/<clock>/<gated clock>[expr {$_dft ? "/<test enable>" : ""}], got '$_spec'"
    }
    set _args [list -pos $_cell $_en:$_clk:$_gclk -min_net_size [oss_get synth oss,clock_gating,min_ffs]]
    if {$_dft} { lappend _args -tie_lo $_te }
    yosys clockgate {*}$_args
    set _rpt "$::REPORTS_DIR/synthesis_clock_gating.rpt"
    yosys tee -q -o $_rpt select -count t:$_cell
    set _fh [open $_rpt]; set _t [read $_fh]; close $_fh
    regexp {(\d+) objects} $_t -> _n
    if {![info exists _n]} { set _n 0 }
    set _fh [open $_rpt w]; puts $_fh "ICG cell : $_cell\nICG count : $_n"; close $_fh
    handle_info "Clock gating: $_n $_cell"
}

# Reports of the mapped design
flow_proc report {
    set _lib_args {}
    foreach _l $::oss_libs { lappend _lib_args -liberty $_l }
    yosys tee -o "$::REPORTS_DIR/synthesis_stat.rpt" stat {*}$_lib_args
}

# Save the mapped netlist — synthesis.v, or synthesis_pre_dft.v when DFT
# (project(dft,enable)) inserts scan into it next
flow_proc write_design {
    set _out [expr {[is_true [oss_get project dft,enable]] ? "synthesis_pre_dft.v" : "synthesis.v"}]
    yosys write_verilog -noattr -noexpr -nohex -nodec [oss_stage_out $_out]
}

# Scan insertion (project(dft,enable)): OpenROAD DFT on the mapped netlist —
# scan_replace (flops -> scan flops) + execute_dft_plan (chains stitched,
# scan_enable_* / scan_in_* / scan_out_* ports added) -> synthesis.v plus the
# scandef synthesis.scandef (mandatory with DFT; PNR reads it). SDCs:
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
    foreach _l [oss_memory_files lef] { puts $_fh "read_lef $_l" }
    foreach _l [oss_memory_libs $_lib_set] { puts $_fh "read_liberty $_l" }
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
    # Scan ICGs from clock gating: test enable (tied low in synthesis) ->
    # the scan enable port, so gated flops shift in scan mode
    set _icg [split [oss_trk icg_scan_cell] /]
    puts $_fh [string map [list @CELL@ [lindex $_icg 0] @TE@ [lindex $_icg 4] @SE@ [oss_get project dft,scan_enable_pattern]] {
set _blk [ord::get_db_block]
set _se ""
foreach _bt [$_blk getBTerms] { if {[string match {@SE@} [$_bt getName]]} { set _se [$_bt getNet]; break } }
set _n 0
foreach _i [$_blk getInsts] {
    if {[[$_i getMaster] getName] ne "@CELL@"} continue
    if {$_se eq ""} { error "scan ICG [$_i getName]: no scan enable port (@SE@) after DFT" }
    set _it [$_i findITerm @TE@]
    $_it disconnect
    $_it connect $_se
    incr _n
}
puts "ICG_TEST_ENABLE $_n"}]
    puts $_fh "report_dft_plan"           ;# to the log; cut into dft_plan.rpt below
    puts $_fh "write_verilog [oss_stage_out synthesis.v]"
    # scandef (mandatory DFT output; PNR reads it): DEF SCANCHAINS in
    # scan-in -> scan-out order, checked against the netlist (oss_scandef.tcl)
    puts $_fh "source $::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_scandef.tcl"
    puts $_fh [list oss_write_scandef [oss_stage_out synthesis.scandef] [oss_get project dft,max_chain_length]]
    puts $_fh "exit"
    close $_fh
    set _log "$::REPORTS_DIR/dft_insert.log"
    if {[is_true $::flow(test_mode)]} {
        file copy -force [oss_stage_out synthesis_pre_dft.v] [oss_stage_out synthesis.v]
    } elseif {[catch {exec {*}[oss_get synth oss,dft,openroad_cmd] $_or >& $_log} _e]} {
        error "DFT insertion failed (see $_log): $_e"
    } elseif {![file exists [oss_stage_out synthesis.scandef]] || [file size [oss_stage_out synthesis.scandef]] == 0} {
        error "DFT on but no scandef written ([oss_stage_out synthesis.scandef], see $_log) — it is a mandatory SYNTH output with project(dft,enable)"
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
