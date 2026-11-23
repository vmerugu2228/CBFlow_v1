# ═══════════════════════════════════════════════════════════════════════════════
# Checklist group "milestone" — data for the milestone (PNR_00xx) checks of
# PLACE_EXIT / CTS_EXIT / PRO_EXIT / BTO / MTO that checklist_metrics.rpt does
# not already carry. One report per placed PNR stage:
#   reports/milestone_checks.rpt   (read through pnr(checklist,report,<check>)
#                                   in PNR_openroad_config.tcl)
# Lines (all measured on the stage's loaded design):
#   VT group mix         — std-cell count per tech(vt_variants_available) group
#                          (tech(vt_pattern,<vt>) on the master name)
#   Power                — report_power per node view: worst-view total and
#                          clock-network power (mW)
#   Constraints          — max slew/cap/fanout violations (sum) and check_setup
#                          issues (unconstrained endpoints, unclocked, loops ...)
#   Clock path timing    — worst setup slack / violators reg -> reg
#   Congestion (RUDY)    — routing-demand estimate per gcell (net bounding
#                          boxes, as used by routability-driven placement)
#                          against the routing-layer track supply, macro
#                          obstructions removed; for stages before global route
#   UPF                  — supply nets of the staged UPF (signoff)
# ═══════════════════════════════════════════════════════════════════════════════

proc oss_checkgrp_milestone {stage} {
    if {$::FLOW_TYPE ne "PNR" || $stage ni {place cts cts_opt route pro signoff}} { return }
    set R milestone_checks.rpt
    set _blk [ord::get_db_block]
    set _dbu [[ord::get_db_tech] getDbUnitsPerMicron]

    # ── VT group mix (logic std cells only: no macros, fillers, taps, endcaps)
    set _vts [oss_get tech vt_variants_available]
    set _pats {}
    foreach _v $_vts { lappend _pats [list $_v [oss_get tech vt_pattern,$_v]] }
    # most specific pattern first (*ulvt* before *lvt*, * last)
    set _pats [lsort -decreasing -command {apply {{a b} {
        expr {[string length [lindex $a 1]] - [string length [lindex $b 1]]}}}} $_pats]
    foreach _v $_vts { set _cnt($_v) 0 }
    set _tot 0; set _unm 0
    foreach _i [$_blk getInsts] {
        set _m [$_i getMaster]
        if {[$_m isBlock] || [$_m isFiller] || [$_m getType] ni {CORE CORE_TIEHIGH CORE_TIELOW}} continue
        incr _tot
        set _hit ""
        foreach _p $_pats {
            if {[string match [lindex $_p 1] [$_m getName]]} { set _hit [lindex $_p 0]; break }
        }
        if {$_hit eq ""} { incr _unm } else { incr _cnt($_hit) }
    }
    oss_check_line $R "VT cells total : $_tot"
    set _used 0
    foreach _v $_vts {
        if {$_cnt($_v)} { incr _used }
        oss_check_line $R "VT $_v cells : $_cnt($_v)"
        oss_check_line $R "VT $_v pct : [format %.1f [expr {$_tot ? 100.0 * $_cnt($_v) / $_tot : 0.0}]]"
    }
    oss_check_line $R "VT unmatched cells : $_unm"
    oss_check_line $R "VT groups used : $_used"

    # ── Power per view (report_power "Total" / "Clock" rows, W -> mW)
    set _copt [oss_corner_opt report_power]
    set _worst ""; set _worst_v ""; set _clk ""
    foreach _v [oss_node_views $::NODE_NAME] {
        set _tmp "$::REPORTS_DIR/.milestone_power.tmp"
        if {[catch {oss_report $_tmp report_power $_copt $_v}]} { file delete $_tmp; continue }
        set _fh [open $_tmp]; set _t [read $_fh]; close $_fh; file delete $_tmp
        if {![regexp -line {^Total\s+\S+\s+\S+\s+\S+\s+(\S+)} $_t -> _tw] || ![string is double -strict $_tw]} continue
        if {$_worst eq "" || $_tw > $_worst} {
            set _worst $_tw; set _worst_v $_v; set _clk ""
            if {[regexp -line {^Clock\s+\S+\s+\S+\s+\S+\s+(\S+)} $_t -> _cw] && [string is double -strict $_cw]} { set _clk $_cw }
        }
    }
    if {$_worst ne ""} {
        oss_check_line $R "Total power mW : [format %.4g [expr {$_worst * 1e3}]]"
        oss_check_line $R "Power view : $_worst_v"
        if {$_clk ne ""} { oss_check_line $R "Clock power mW : [format %.4g [expr {$_clk * 1e3}]]" }
    }

    # ── Constraints: design-rule violations + check_setup issues
    set _drv 0; set _drv_ok 1
    foreach _c {sta::max_slew_violation_count sta::max_capacitance_violation_count sta::max_fanout_violation_count} {
        if {[catch {$_c} _n] || ![string is integer -strict $_n]} { set _drv_ok 0; break }
        incr _drv $_n
    }
    set _tmp "$::REPORTS_DIR/.milestone_setup.tmp"
    set _cs ""
    if {![catch {oss_report $_tmp check_setup -verbose}]} {
        set _fh [open $_tmp]; set _t [read $_fh]; close $_fh
        set _cs 0
        foreach {_ _n} [regexp -all -inline {There (?:is|are) (\d+)} $_t] { incr _cs $_n }
    }
    file delete $_tmp
    if {$_drv_ok} { oss_check_line $R "DRV violations total : $_drv" }
    if {$_cs ne ""} { oss_check_line $R "Timing constraint issues : $_cs" }
    if {$_drv_ok && $_cs ne ""} { oss_check_line $R "All constraint violations : [expr {$_drv + $_cs}]" }

    # ── Clock (reg -> reg) path setup timing, worst over the loaded corners
    set _regs [all_registers]
    if {[llength $_regs]} {
        set _ends [find_timing_paths -from $_regs -to $_regs -path_delay max \
                       -group_path_count 1000000 -endpoint_path_count 1 -sort_by_slack]
        set _w ""; set _nv 0
        foreach _pe $_ends {
            set _sl [get_property $_pe slack]
            if {![string is double -strict $_sl]} continue
            if {$_w eq "" || $_sl < $_w} { set _w $_sl }
            if {$_sl < 0} { incr _nv }
        }
        if {$_w ne ""} {
            oss_check_line $R "Clock path setup WNS : [cbflow_fmt_slack $_w]"
            oss_check_line $R "Clock path setup NVP : $_nv"
        }
    }

    # ── Congestion estimate (RUDY), stages before global routing
    if {$stage in {place cts cts_opt}} { oss_milestone_rudy $R $_blk $_dbu }

    # ── UPF power intent staged for signoff
    if {$stage eq "signoff" && [info exists ::UPF_DIR]} {
        set _upf "$::UPF_DIR/[oss_get flow design_name].upf"
        if {[file exists $_upf]} {
            set _fh [open $_upf]; set _t [read $_fh]; close $_fh
            oss_check_line $R "UPF supply nets : [regexp -all -line {^\s*create_supply_net\s} $_t]"
            oss_check_line $R "UPF power domains : [regexp -all -line {^\s*create_power_domain\s} $_t]"
        }
    }
}

# RUDY: each signal net spreads its half-perimeter wire length uniformly over
# its pin bounding box; per gcell, demand (um of wire) / supply (um of routing
# track: area x sum(1/pitch) over the routing layers between
# tech(min_routing_layer) and tech(max_routing_layer), minus the layers a hard
# macro obstructs over its footprint).
proc oss_milestone_rudy {R blk dbu} {
    set _tech [ord::get_db_tech]
    set _min [oss_get tech min_routing_layer]
    set _max [oss_get tech max_routing_layer]
    set _in 0; set _inv_pitch 0.0; set _layers {}
    foreach _l [$_tech getLayers] {
        if {[$_l getType] ne "ROUTING"} continue
        if {[$_l getName] eq $_min} { set _in 1 }
        if {$_in && [$_l getPitch] > 0} {
            set _ip [expr {double($dbu) / [$_l getPitch]}]
            set _inv_pitch [expr {$_inv_pitch + $_ip}]
            dict set _layers [$_l getName] $_ip
        }
        if {[$_l getName] eq $_max} break
    }
    if {$_inv_pitch <= 0} { error "no routing layers between $_min and $_max" }
    set _d [$blk getDieArea]
    set _x0 [$_d xMin]; set _y0 [$_d yMin]
    set _W [expr {[$_d xMax] - $_x0}]; set _H [expr {[$_d yMax] - $_y0}]
    # gcell: at most 100 x 100 grid, at least 10 std-cell rows
    set _row [[lindex [$blk getRows] 0] getSite]
    set _gs [expr {max(10 * [$_row getHeight], ($_W > $_H ? $_W : $_H) / 100)}]
    set _nx [expr {int(ceil(double($_W) / $_gs))}]; set _ny [expr {int(ceil(double($_H) / $_gs))}]
    set _ga [expr {(double($_gs) / $dbu) ** 2}]
    for {set i 0} {$i < $_nx * $_ny} {incr i} { set _dem($i) 0.0; set _cap($i) [expr {$_ga * $_inv_pitch}] }

    # supply: macro obstructions (OBS + pin layers) remove those layers' tracks
    foreach _i [$blk getInsts] {
        set _m [$_i getMaster]
        if {![$_m isBlock]} continue
        set _ip 0.0; set _seen {}
        foreach _o [$_m getObstructions] {
            set _ln [[$_o getTechLayer] getName]
            if {[dict exists $_layers $_ln] && $_ln ni $_seen} { lappend _seen $_ln; set _ip [expr {$_ip + [dict get $_layers $_ln]}] }
        }
        foreach _mt [$_m getMTerms] { foreach _mp [$_mt getMPins] { foreach _g [$_mp getGeometry] {
            set _tl [$_g getTechLayer]
            if {$_tl eq "NULL"} continue
            set _ln [$_tl getName]
            if {[dict exists $_layers $_ln] && $_ln ni $_seen} { lappend _seen $_ln; set _ip [expr {$_ip + [dict get $_layers $_ln]}] }
        } } }
        if {$_ip == 0.0} continue
        set _b [$_i getBBox]
        oss_milestone_spread _cap [$_b xMin] [$_b yMin] [$_b xMax] [$_b yMax] \
            $_x0 $_y0 $_gs $_nx $_ny $dbu [expr {-$_ip}] 1
    }

    # demand: signal nets
    set _minw [expr {double($dbu) / [lindex [lsort -real -decreasing [dict values $_layers]] 0]}]
    foreach _n [$blk getNets] {
        if {[$_n getSigType] in {POWER GROUND}} continue
        set _xs {}; set _ys {}
        foreach _it [$_n getITerms] {
            set _b [$_it getBBox]
            lappend _xs [expr {([$_b xMin] + [$_b xMax]) / 2}]; lappend _ys [expr {([$_b yMin] + [$_b yMax]) / 2}]
        }
        foreach _bt [$_n getBTerms] {
            set _b [$_bt getBBox]
            lappend _xs [expr {([$_b xMin] + [$_b xMax]) / 2}]; lappend _ys [expr {([$_b yMin] + [$_b yMax]) / 2}]
        }
        if {[llength $_xs] < 2} continue
        set _xs [lsort -integer $_xs]; set _ys [lsort -integer $_ys]
        set _lx [lindex $_xs 0]; set _hx [lindex $_xs end]
        set _ly [lindex $_ys 0]; set _hy [lindex $_ys end]
        # degenerate boxes: one routing pitch wide
        if {$_hx - $_lx < $_minw} { set _hx [expr {$_lx + $_minw}] }
        if {$_hy - $_ly < $_minw} { set _hy [expr {$_ly + $_minw}] }
        set _w [expr {double($_hx - $_lx) / $dbu}]; set _h [expr {double($_hy - $_ly) / $dbu}]
        oss_milestone_spread _dem $_lx $_ly $_hx $_hy $_x0 $_y0 $_gs $_nx $_ny $dbu \
            [expr {($_w + $_h) / ($_w * $_h)}] 0
    }

    # gcells without track supply (fully obstructed by macros) are left out
    set _mx 0.0; set _ovf 0; set _n 0
    for {set i 0} {$i < $_nx * $_ny} {incr i} {
        if {$_cap($i) <= 1e-9} continue
        incr _n
        set _r [expr {100.0 * $_dem($i) / $_cap($i)}]
        if {$_r > $_mx} { set _mx $_r }
        if {$_r > 100.0} { incr _ovf }
    }
    oss_check_line $R "Congestion RUDY gcells : $_n (of [expr {$_nx * $_ny}], [expr {$_nx * $_ny - $_n}] macro-blocked)"
    oss_check_line $R "Congestion RUDY max pct : [format %.1f $_mx]"
    oss_check_line $R "Congestion RUDY overflow gcells : $_ovf"
    oss_check_line $R "Congestion RUDY overflow pct : [format %.3f [expr {$_n ? 100.0 * $_ovf / $_n : 0.0}]]"
}

# add density x overlap-area (um2) of box (dbu) to every gcell it covers
# (clip: 1 = supply, never below zero)
proc oss_milestone_spread {arrName lx ly hx hy x0 y0 gs nx ny dbu dens clip} {
    upvar 1 $arrName A
    set i0 [expr {max(0, ($lx - $x0) / $gs)}]; set i1 [expr {min($nx - 1, ($hx - 1 - $x0) / $gs)}]
    set j0 [expr {max(0, ($ly - $y0) / $gs)}]; set j1 [expr {min($ny - 1, ($hy - 1 - $y0) / $gs)}]
    for {set j $j0} {$j <= $j1} {incr j} {
        set gy0 [expr {$y0 + $j * $gs}]
        set oy [expr {double(min($hy, $gy0 + $gs) - max($ly, $gy0)) / $dbu}]
        if {$oy <= 0} continue
        for {set i $i0} {$i <= $i1} {incr i} {
            set gx0 [expr {$x0 + $i * $gs}]
            set ox [expr {double(min($hx, $gx0 + $gs) - max($lx, $gx0)) / $dbu}]
            if {$ox <= 0} continue
            set k [expr {$j * $nx + $i}]
            set A($k) [expr {$A($k) + $dens * $ox * $oy}]
            if {$clip && $A($k) < 0} { set A($k) 0.0 }
        }
    }
}
