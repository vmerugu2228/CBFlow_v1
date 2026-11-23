# ═══════════════════════════════════════════════════════════════════════════════
# Checklist library reports — clock group (global/config/exit/v1.0.0/checks/
# clock_checks.tcl). Sourced by oss_checks_run (oss_checks.tcl); runs inside
# OpenROAD with the stage's design, corners and SDC loaded. Clock-tree data
# exists from CTS on, so nothing is written before the cts stage.
#
# Reports fed (one "Key : value" line per check, units per check threshold):
#   report_clock_qor.rpt           tree structure: coverage, fanout, depth, cells
#   report_clock_timing.setup.rpt  sink latency / transition / duty cycle / CRPR
#   report_clock_timing.skew.rpt   inter-domain skew, hold margin
#   report_power.rpt               clock network power, clock gating
#
# Not written (cannot be measured here — the check reads NA):
#   clock_occ_timing (CLOCK_0021)       no OCC instances are identified in the
#                                       PnR database / config
#   clock_power_vs_budget (CLOCK_0025)  no clock power budget in the config
# Clock tree skew / insertion delay (CLOCK_0001/0002) come from
# checklist_metrics.rpt (tool checklist map), not from here.
# ═══════════════════════════════════════════════════════════════════════════════

namespace eval ::oss_clk {}

# STA time (user units) -> ps
proc ::oss_clk::ps {t} { return [expr {$t * [sta::unit_scale time] / 1e-12}] }

# Run a report command, return its text (temp file under reports/).
proc ::oss_clk::text {args} {
    set _tmp "$::REPORTS_DIR/.oss_clk_[pid].tmp"
    set _rc [catch {oss_report $_tmp {*}$args} _e]
    set _t ""
    if {[file exists $_tmp]} { set _fh [open $_tmp]; set _t [read $_fh]; close $_fh; file delete $_tmp }
    if {$_rc} { error $_e }
    return $_t
}

# Liberty cell of an STA instance (cached per master): {lib_cell buffer inverter}
proc ::oss_clk::cell_kind {inst} {
    variable kind
    set _m [get_property $inst ref_name]
    if {![info exists kind($_m)]} {
        set _lc [get_property $inst liberty_cell]
        if {$_lc eq "" || $_lc eq "NULL"} {
            set kind($_m) {0 0 0}
        } else {
            set kind($_m) [list 1 [$_lc is_buffer] [$_lc is_inverter]]
        }
    }
    return $kind($_m)
}

# Net driven by a pin (a top-level port pin resolves through its port).
proc ::oss_clk::net_of {pin} {
    set _n [get_nets -quiet -of_objects $pin]
    if {($_n eq "" || $_n eq "NULL") && [get_property $pin is_port]} {
        set _bt [[ord::get_db_block] findBTerm [get_full_name $pin]]
        set _n ""
        if {$_bt ne "NULL" && $_bt ne "" && [$_bt getNet] ne "NULL"} {
            set _n [get_nets -quiet [[$_bt getNet] getName]]
        }
    }
    if {$_n eq "NULL"} { set _n "" }
    return [lindex $_n 0]
}

# Walk every clock's network from its source pins (STA netlist): fills
#   tree(cells)  {inst ...}  cells driving clock nets toward sinks
#   tree(nets)   {net level fanout ...}
#   tree(sinks)  {pin depth gated icg pi ...} register / macro clock pins (STA pins)
proc ::oss_clk::walk {icg_masters} {
    variable tree
    array unset tree
    set tree(cells) {}; set tree(nets) {}; set tree(sinks) {}
    array set clkpin {}
    foreach _p [all_registers -clock_pins] { set clkpin([get_full_name $_p]) 1 }
    array set seen_cell {}; array set seen_sink {}; array set seen_net {}
    foreach _clk [all_clocks] {
        foreach _src [get_property $_clk sources] {
            # pi: the source is a top-level port (controllable from outside)
            set _pi [expr {[get_property $_src is_port] ? 1 : 0}]
            # queue: {driver_pin depth gated icg pi}
            set _q [list [list $_src 0 0 0 $_pi]]
            while {[llength $_q]} {
                set _q [lassign $_q _it]
                lassign $_it _drv _depth _gated _icg _pi
                set _net [net_of $_drv]
                if {$_net eq ""} continue
                set _nn [get_full_name $_net]
                set _loads {}
                foreach _lp [get_pins -quiet -of_objects $_net] {
                    if {[get_full_name $_lp] eq [get_full_name $_drv]} continue
                    if {[get_property $_lp direction] ni {input inout}} continue
                    lappend _loads $_lp
                }
                if {![info exists seen_net($_nn)]} {
                    set seen_net($_nn) 1
                    lappend tree(nets) $_nn $_depth [llength $_loads]
                }
                foreach _lp $_loads {
                    set _ln [get_full_name $_lp]
                    if {[info exists clkpin($_ln)]} {
                        if {![info exists seen_sink($_ln)]} {
                            set seen_sink($_ln) 1
                            lappend tree(sinks) $_lp $_depth $_gated $_icg $_pi
                        }
                        continue
                    }
                    set _inst [get_cells -of_objects $_lp]
                    set _in [get_full_name $_inst]
                    if {[info exists seen_cell($_in)]} continue
                    set seen_cell($_in) 1
                    lassign [cell_kind $_inst] _haslib _buf _inv
                    if {!$_haslib} continue
                    set _outs [get_pins -quiet -of_objects $_inst -filter "direction == output"]
                    if {![llength $_outs]} continue  ;# e.g. clock used as data on a sequential pin
                    lappend tree(cells) $_inst
                    set _isicg [expr {[get_property $_inst ref_name] in $icg_masters}]
                    set _g [expr {$_gated || (!$_buf && !$_inv)}]
                    set _i [expr {$_icg || $_isicg}]
                    # non buffer/inverter/ICG logic: no longer directly controllable
                    set _p [expr {$_pi && ($_buf || $_inv || $_isicg)}]
                    foreach _op $_outs { lappend _q [list $_op [expr {$_depth + 1}] $_g $_i $_p] }
                }
            }
        }
    }
}

proc oss_checkgrp_clock {stage} {
    if {$stage ni {cts cts_opt route pro signoff}} return
    sta::worst_slack -max   ;# timing graph up to date before pin queries

    set _icg   [oss_trk icg_cells]
    set _cbuf  [oss_trk clock_buffers]
    set _cinv  [oss_trk clock_inverters]
    set _allow [concat $_cbuf $_cinv $_icg [oss_trk clock_root_buffer]]
    ::oss_clk::walk $_icg
    upvar #0 ::oss_clk::tree tree
    set Q report_clock_qor.rpt
    set T report_clock_timing.setup.rpt
    set K report_clock_timing.skew.rpt
    set W report_power.rpt

    # ── report_clock_qor.rpt ──────────────────────────────────────────────
    # CLOCK_0003 clock_coverage: % of registers / macros with a clock at a clock pin
    set _nreg [llength [all_registers -cells]]
    array set _clocked {}
    foreach _cp [all_registers -clock_pins] {
        if {[llength [get_property $_cp clocks]]} {
            set _clocked([get_full_name [get_cells -of_objects $_cp]]) 1
        }
    }
    if {$_nreg} {
        set _cov [array size _clocked]
        oss_check_line $Q "Clock Coverage : [format %.2f [expr {100.0 * $_cov / $_nreg}]] % ($_cov / $_nreg registers)"
    }

    # Per-clock insertion latency (report_clock_latency: min/max, rise/fall)
    set _lt [::oss_clk::text report_clock_latency -include_internal_latency -digits 4]
    array set _clat {}
    set _c ""
    foreach _ln [split $_lt \n] {
        if {[regexp {^Clock\s+(\S+)} $_ln -> _c]} continue
        if {$_c ne "" && [regexp {^\s*(-?[\d.]+)\s+(-?[\d.]+)\s+latency\s*$} $_ln -> _mn _mx]} {
            if {![info exists _clat($_c)] || $_mx > $_clat($_c)} { set _clat($_c) $_mx }
        }
    }
    # CLOCK_0004 clock_latency_balance: spread of the clocks' max insertion latency (ps)
    if {[array size _clat]} {
        set _v [lsort -real [lmap _k [array names _clat] {set _clat($_k)}]]
        oss_check_line $Q "Latency Imbalance : [format %.1f [::oss_clk::ps [expr {[lindex $_v end] - [lindex $_v 0]}]]] ps ([array size _clat] clock domain(s))"
    }

    # CLOCK_0007 clock_fanout: max load pins on any clock-tree net
    # CLOCK_0016 clock_tree_depth: max tree cells from clock source to a sink
    set _fo 0
    foreach {_n _lvl _f} $tree(nets) { if {$_f > $_fo} { set _fo $_f } }
    set _dep 0
    foreach {_p _d _g _i _pi} $tree(sinks) { if {$_d > $_dep} { set _dep $_d } }
    if {[llength $tree(nets)]} { oss_check_line $Q "Max Fanout : $_fo" }
    if {[llength $tree(sinks)]} { oss_check_line $Q "Max Tree Depth : $_dep" }

    # CLOCK_0009 non_clock_cells_in_clock: tree cells that are not buffer / inverter / ICG
    # CLOCK_0010 undefined_cells_in_clock: tree cells outside tech clock_buffers /
    #            clock_inverters / icg_cells / clock_root_buffer
    # CLOCK_0014 clock_buffer_ratio: clock-tree buffers / inverters
    set _nonclk 0; set _undef 0; set _nb 0; set _ni 0; set _nicg 0
    foreach _inst $tree(cells) {
        set _m [get_property $_inst ref_name]
        lassign [::oss_clk::cell_kind $_inst] _ _buf _inv
        if {$_buf} { incr _nb } elseif {$_inv} { incr _ni } elseif {$_m in $_icg} { incr _nicg } else { incr _nonclk }
        if {$_m ni $_allow} { incr _undef }
    }
    oss_check_line $Q "Non-Clock Cells : $_nonclk"
    oss_check_line $Q "Undefined Clock Cells : $_undef"
    if {$_ni > 0} {
        oss_check_line $Q "Buffer/Inverter Ratio : [format %.2f [expr {double($_nb) / $_ni}]] ($_nb buffers / $_ni inverters)"
    } else {
        oss_check_line $Q "# Buffer/Inverter Ratio : undefined ($_nb buffers / 0 inverters)"
    }

    # CLOCK_0013 icg_usage: % of clock sinks gated by an ICG cell (tech icg_cells)
    set _ns [expr {[llength $tree(sinks)] / 5}]
    set _sg 0; set _si 0; set _spi 0
    foreach {_p _d _g _i _pi} $tree(sinks) { incr _sg $_g; incr _si $_i; incr _spi $_pi }
    if {$_ns} {
        oss_check_line $Q "ICG Utilization : [format %.2f [expr {100.0 * $_si / $_ns}]] % ($_si / $_ns clock sinks, $_nicg ICG cells)"
    }

    # CLOCK_0015 clock_ndr_compliance: clock-tree nets lacking the NDR the CTS
    # policy pnr(oss,cts,apply_ndr) asks for (root_only: level-1 net; half:
    # upper half of the levels; full: every CTS level)
    set _pol [oss_get [oss_flow_arr] oss,cts,apply_ndr]
    set _maxl 0
    foreach {_n _lvl _f} $tree(nets) { if {$_lvl > $_maxl} { set _maxl $_lvl } }
    set _blk [ord::get_db_block]
    set _ndrv 0; set _ndrn 0
    foreach {_n _lvl _f} $tree(nets) {
        switch -- $_pol {
            none      { set _want 0 }
            root_only { set _want [expr {$_lvl == 1}] }
            half      { set _want [expr {$_lvl >= 1 && $_lvl <= ($_maxl + 1) / 2}] }
            default   { set _want [expr {$_lvl >= 1}] }
        }
        set _dn [$_blk findNet $_n]
        if {$_dn eq "NULL" || $_dn eq ""} continue
        set _has [expr {[$_dn getNonDefaultRule] ne "NULL"}]
        if {$_has} { incr _ndrn }
        if {$_want && !$_has} { incr _ndrv }
    }
    oss_check_line $Q "NDR Violations : $_ndrv (policy $_pol, $_ndrn clock nets with an NDR)"

    # CLOCK_0012 clock_mesh_drc: detailed-route DRC markers on clock-tree nets
    # (OpenROAD builds a tree, no mesh — this counts the clock distribution's
    # routing violations from the route node's route_drc.rpt)
    if {$stage in {route pro signoff}} {
        set _rdir [expr {$stage eq "route" ? $::REPORTS_DIR
                         : "$::run_dir/work/$::FLOW_TYPE/[oss_chain_node route]/reports"}]
        if {[file exists "$_rdir/route_drc.rpt"]} {
            array set _cn {}
            foreach {_n _lvl _f} $tree(nets) { set _cn($_n) 1 }
            set _fh [open "$_rdir/route_drc.rpt"]; set _t [read $_fh]; close $_fh
            # one violation = a "violation type" line up to the next one;
            # counted when it names a clock-tree net (srcs: net:<name>)
            set _cd 0; set _hit 0; set _in 0
            foreach _ln [split $_t \n] {
                if {[regexp -nocase {violation type} $_ln]} {
                    incr _cd $_hit; set _hit 0; set _in 1
                }
                if {$_in && !$_hit} {
                    foreach {_ _nm} [regexp -all -inline {net:(\S+)} $_ln] {
                        if {[info exists _cn($_nm)]} { set _hit 1 }
                    }
                }
            }
            incr _cd $_hit
            oss_check_line $Q "Clock Mesh DRC : $_cd"
        }
    }

    # CLOCK_0022 clock_dft_coverage: % of clock sinks controllable from a
    # primary-input clock (reached through buffers / inverters / ICGs only)
    if {$_ns} {
        oss_check_line $Q "DFT Clock Coverage : [format %.2f [expr {100.0 * $_spi / $_ns}]] % ($_spi / $_ns clock sinks)"
    }

    # ── report_clock_timing.setup.rpt ─────────────────────────────────────
    # CLOCK_0023 clock_latency_max: max insertion latency over all clocks/sinks (ps)
    if {[array size _clat]} {
        set _mx [lindex [lsort -real [lmap _k [array names _clat] {set _clat($_k)}]] end]
        oss_check_line $T "Max Latency : [format %.1f [::oss_clk::ps $_mx]] ps"
    }

    # CLOCK_0005 clock_transition: max slew at clock sink pins (ps)
    # CLOCK_0017 clock_duty_cycle: |high-phase change| / period at the worst sink:
    #   (fall - rise arrival) vs the waveform's high (or low, inverted) phase
    set _sl ""; set _dcd ""
    set _us [sta::unit_scale time]
    foreach {_p _d _g _i _pi} $tree(sinks) {
        set _pin $_p
        set _s [get_property $_pin slew_max]
        if {[string is double -strict $_s] && ($_sl eq "" || $_s > $_sl)} { set _sl $_s }
        set _clks [get_property $_pin clocks]
        if {![llength $_clks]} continue
        set _ck [lindex $_clks 0]
        set _per [expr {[$_ck period] / $_us}]
        if {$_per <= 0} continue
        lassign [$_ck waveform] _tr _tf
        set _high [expr {fmod(($_tf - $_tr) / $_us, $_per)}]
        set _ar [get_property $_pin arrival_max_rise]
        set _af [get_property $_pin arrival_max_fall]
        if {![string is double -strict $_ar] || ![string is double -strict $_af]} continue
        if {abs($_ar) > 1e20 || abs($_af) > 1e20} continue
        set _dd [expr {fmod(fmod($_af - $_ar, $_per) + $_per, $_per)}]
        set _e [expr {min(abs($_dd - $_high), abs($_dd - ($_per - $_high)))}]
        set _pc [expr {100.0 * $_e / $_per}]
        if {$_dcd eq "" || $_pc > $_dcd} { set _dcd $_pc }
    }
    if {$_sl ne ""} { oss_check_line $T "Max Transition : [format %.1f [::oss_clk::ps $_sl]] ps" }
    if {$_dcd ne ""} { oss_check_line $T "Duty Cycle Distortion : [format %.3f $_dcd] %" }

    # CLOCK_0011 clock_reconvergence: worst CRPR credit (report_clock_skew, ps)
    # CLOCK_0018 clock_jitter_margin: smallest clock uncertainty reserved in
    #            the timing constraints (jitter + margin budget, ps)
    set _crpr ""; set _unc ""
    foreach _mode {-setup -hold} {
        set _st [::oss_clk::text report_clock_skew $_mode -digits 4]
        foreach _ln [split $_st \n] {
            if {[regexp {^\s*(-?[\d.]+)\s+CRPR\s*$} $_ln -> _v]} {
                if {$_crpr eq "" || abs($_v) > $_crpr} { set _crpr [expr {abs($_v)}] }
            }
            if {$_mode eq "-setup" && [regexp {^\s*(-?[\d.]+)\s+clock uncertainty\s*$} $_ln -> _v]} {
                if {$_unc eq "" || abs($_v) < $_unc} { set _unc [expr {abs($_v)}] }
            }
        }
    }
    if {$_crpr ne ""} { oss_check_line $T "CRPR Pessimism : [format %.1f [::oss_clk::ps $_crpr]] ps" }
    if {$_unc ne ""} { oss_check_line $T "Jitter Margin : [format %.1f [::oss_clk::ps $_unc]] ps (setup clock uncertainty)" }

    # CLOCK_0008 useful_skew: setup WNS with propagated clocks minus WNS with
    # ideal clocks (ps; negative = the clock tree costs setup slack)
    set _prop {}
    foreach _ck [all_clocks] { if {[get_property $_ck is_propagated]} { lappend _prop $_ck } }
    if {[llength $_prop]} {
        set _wp [sta::worst_slack -max]
        unset_propagated_clock $_prop
        set _rc [catch {sta::worst_slack -max} _wi]
        set_propagated_clock $_prop
        sta::worst_slack -max
        if {!$_rc && [string is double -strict $_wp] && [string is double -strict $_wi]
            && abs($_wp) < 1e20 && abs($_wi) < 1e20} {
            oss_check_line $T "Useful Skew Benefit : [format %.1f [::oss_clk::ps [expr {$_wp - $_wi}]]] ps"
        }
    }

    # ── report_clock_timing.skew.rpt ──────────────────────────────────────
    # CLOCK_0019 inter_clock_skew: worst |clock skew| on paths launched and
    # captured by different clocks (ps)
    set _ics 0.0; set _ncross 0
    set _clks [all_clocks]
    foreach _a $_clks {
        foreach _b $_clks {
            if {$_a eq $_b} continue
            foreach _pe [find_timing_paths -path_delay max -from $_a -to $_b \
                             -group_path_count 100 -endpoint_path_count 1] {
                if {[get_property $_pe startpoint_clock] eq [get_property $_pe endpoint_clock]} continue
                incr _ncross
                set _k [expr {abs([$_pe clk_skew])}]
                if {$_k > $_ics} { set _ics $_k }
            }
        }
    }
    # clk_skew is in seconds
    oss_check_line $K "Inter-Domain Skew : [format %.1f [expr {$_ics / 1e-12}]] ps ($_ncross inter-domain path(s), [llength $_clks] clock(s))"

    # CLOCK_0024 clock_hold_margin: worst hold slack register -> register (ps)
    set _hp [find_timing_paths -path_delay min -from [all_registers -clock_pins] \
                 -to [all_registers -data_pins] -group_path_count 1]
    if {[llength $_hp]} {
        set _hs [get_property [lindex $_hp 0] slack]
        if {[string is double -strict $_hs] && abs($_hs) < 1e20} {
            oss_check_line $K "Hold Margin : [format %.1f [::oss_clk::ps $_hs]] ps"
        }
    }

    # ── report_power.rpt ──────────────────────────────────────────────────
    # CLOCK_0006 clock_power: clock network power, worst corner (mW)
    set _cp ""
    set _opt [oss_corner_opt report_power]
    foreach _v [oss_node_views $::NODE_NAME] {
        if {[catch {::oss_clk::text report_power $_opt $_v} _pt]} continue
        if {[regexp -line {^Clock\s+\S+\s+\S+\s+\S+\s+(\S+)} $_pt -> _w] && [string is double -strict $_w]} {
            if {$_cp eq "" || $_w > $_cp} { set _cp $_w }
        }
    }
    if {$_cp ne ""} { oss_check_line $W "Clock Network Power : [format %.4f [expr {$_cp * 1e3}]] mW" }

    # CLOCK_0020 clock_gating_efficiency: % of clock sinks behind clock gating
    # (an ICG or other gating logic in their clock path)
    if {$_ns} {
        oss_check_line $W "Clock Gating Efficiency : [format %.2f [expr {100.0 * $_sg / $_ns}]] % ($_sg / $_ns clock sinks)"
    }
}
