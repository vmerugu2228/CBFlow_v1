# ═══════════════════════════════════════════════════════════════════════════════
# Checklist group "physical": exit-checklist library checks of the physical and
# placement categories (global/config/exit/v1.0.0/checks/physical_checks.tcl,
# placement_checks.tcl), measured on the stage's loaded design (OpenROAD: odb,
# OpenSTA, DPL, PSM, DRT). Called by oss_checks_run (oss_checks.tcl) at every
# placed PNR stage; each line matches its check's metric_pattern.
#
#   check_connectivity.rpt  Unconnected cells, Floating input pins,
#                           Open signal nets, Missing tie cells
#   report_pg.rpt           Missing power vias, Unconnected PG cells, IO ring breaks
#   report_power.rpt        Power strap coverage / width violations,
#                           Worst IR drop, EM violations (pro / signoff)
#   check_legality.rpt      Well tap coverage / violations, Missing endcap cells,
#                           Missing boundary cells, Cell padding violations,
#                           Halo / Blockage overlap / Cell orientation /
#                           Pin access / Power domain boundary violations,
#                           Filler gaps (pro / signoff)
#   report_utilization.rpt  Max local density, Utilization std dev,
#                           Filler coverage (pro / signoff)
#   report_design.rpt       Decap / spare cell coverage, Pin density hotspots,
#                           Blockage coverage errors, Average cell displacement,
#                           Min macro channel width, Scan chain reorder distance
#   report_congestion.rpt   Max overflow (RUDY estimate per bin)
#   report_qor.rpt          Total wire length (HPWL pre-route, routed after)
#
# Density-type metrics use one bin grid: square bins of 10 standard-cell rows
# from the core origin; a bin is counted when at least half of it is row area.
# A metric that cannot be measured on this design is left out (the check
# reads NA) and the reason is logged.
# ═══════════════════════════════════════════════════════════════════════════════

namespace eval ::oss_phys {
    variable bin_rows 10       ;# bin edge in standard-cell rows
    variable bin_min_avail 0.5 ;# bin counted when row area >= this share of it
}

proc oss_checkgrp_physical {stage} {
    if {$stage ni {place cts cts_opt route pro signoff}} return
    ::oss_phys::init $stage
    foreach _f {connectivity pg_grid legality bins macros wirelength displacement
                pin_access_chk io_ring scan_chains ir_em} {
        if {[catch {::oss_phys::$_f $stage} _e]} {
            handle_warning "checklist physical: $_f at $stage not measured: $_e"
        }
    }
}

# ── Shared data ──────────────────────────────────────────────────────────────
proc ::oss_phys::skip {what why} { handle_info "checklist physical: $what not measured — $why" }
proc ::oss_phys::um {v} { variable dbu; return [expr {$v / double($dbu)}] }
proc ::oss_phys::ovl {a0 a1 b0 b1} { return [expr {max(0, min($a1, $b1) - max($a0, $b0))}] }
proc ::oss_phys::hit {a b} {
    lassign $a ax0 ay0 ax1 ay1; lassign $b bx0 by0 bx1 by1
    return [expr {$ax0 < $bx1 && $bx0 < $ax1 && $ay0 < $by1 && $by0 < $ay1}]
}
# {x0 y0 x1 y1} of an odb object with a bounding box, or of a box / Rect
proc ::oss_phys::bbox {o} {
    if {[catch {$o getBBox} b]} { set b $o }
    return [list [$b xMin] [$b yMin] [$b xMax] [$b yMax]]
}

# Instances by role, rows, row ends, macros, core.
#   role: macro | filler | tap | endcap (endcap master at a row end) |
#         physical (other spacer / antenna cells) | logic
proc ::oss_phys::init {stage} {
    variable blk [ord::get_db_block]
    variable dbu [[ord::get_db_tech] getDbUnitsPerMicron]
    variable core [bbox [$blk getCoreArea]]
    variable routed [expr {$stage in {route pro signoff}}]
    variable rows {}; variable row_y; array unset row_y; array set row_y {}
    variable role; array unset role; array set role {}
    variable macros {}
    set _fill [oss_trk fillers]
    set _tap  [oss_trk well_tap]
    set _ec   [oss_trk endcap]
    variable decap_masters [expr {[catch {oss_trk decap} _d] ? {} : $_d}]
    set _ends [dict create]
    foreach _r [$blk getRows] {
        lassign [bbox $_r] _x0 _y0 _x1 _y1
        lappend rows [list $_x0 $_y0 $_x1 $_y1 [$_r getOrient]]
        lappend row_y($_y0) [expr {[llength $rows] - 1}]
        dict set _ends "$_y0,$_x0" 1; dict set _ends "$_y0,$_x1" 1
    }
    if {[llength $rows] == 0} { error "design has no rows" }
    variable row_h [expr {[lindex $rows 0 3] - [lindex $rows 0 1]}]
    variable site_w [[[lindex [$blk getRows] 0] getSite] getWidth]
    foreach _i [$blk getInsts] {
        set _m [$_i getMaster]; set _n [$_m getName]
        if {[$_m isBlock]} { set role($_i) macro; lappend macros $_i; continue }
        if {$_n in $_fill} { set role($_i) filler; continue }
        if {$_n eq $_tap} { set role($_i) tap; continue }
        if {$_n eq $_ec} {
            lassign [bbox $_i] _x0 _y0 _x1 _y1
            if {[dict exists $_ends "$_y0,$_x0"] || [dict exists $_ends "$_y0,$_x1"]} { set role($_i) endcap; continue }
        }
        if {[$_m getType] in {CORE_SPACER CORE_WELLTAP CORE_ANTENNACELL CORE_FEEDTHRU} || [string match ENDCAP* [$_m getType]]} {
            set role($_i) physical; continue
        }
        set role($_i) logic
    }
}

# ── check_connectivity.rpt ───────────────────────────────────────────────────
# Driven: the net has an output / inout instance pin or an input / inout port.
proc ::oss_phys::driven {net} {
    variable drv
    if {[info exists drv($net)]} { return $drv($net) }
    set _d 0
    foreach _it [$net getITerms] { if {[[$_it getMTerm] getIoType] in {OUTPUT INOUT}} { set _d 1; break } }
    if {!$_d} { foreach _bt [$net getBTerms] { if {[$_bt getIoType] in {INPUT INOUT}} { set _d 1; break } } }
    set drv($net) $_d
    return $_d
}

proc ::oss_phys::connectivity {stage} {
    variable blk; variable role; variable routed; variable drv
    array unset drv; array set drv {}
    set _unc 0; set _flt 0; set _tie 0
    foreach _i [$blk getInsts] {
        if {$role($_i) ni {logic macro}} continue
        set _in_open 0; set _sig_c 0
        foreach _it [$_i getITerms] {
            set _mt [$_it getMTerm]
            if {[$_mt getSigType] in {POWER GROUND}} continue
            set _io [$_mt getIoType]; set _n [$_it getNet]
            if {$_n ne "NULL"} { incr _sig_c }
            if {$_io eq "INPUT"} {
                if {$_n eq "NULL"} { set _in_open 1; incr _flt; continue }
                # input wired straight to a supply net instead of a tie cell
                if {[$_n getSigType] in {POWER GROUND}} { incr _tie; continue }
                if {![driven $_n]} { incr _flt }
            }
        }
        # Unconnected cell: a logic cell with an input pin on no net, or with
        # no signal pin connected at all. A connected cell with unused outputs
        # (e.g. CTS dummy loads, unused QN) is not counted.
        if {$role($_i) eq "logic" && ($_in_open || $_sig_c == 0)} { incr _unc }
    }
    # Open signal net: sinks without a driver; from route on also a net with
    # two or more pins and no routed wire
    set _open 0
    foreach _n [$blk getNets] {
        if {[$_n getSigType] in {POWER GROUND}} continue
        set _pins [expr {[llength [$_n getITerms]] + [llength [$_n getBTerms]]}]
        if {$_pins == 0} continue
        if {![driven $_n]} { incr _open; continue }
        if {$routed && $_pins >= 2 && [$_n getWire] eq "NULL"} { incr _open }
    }
    oss_check_line check_connectivity.rpt "Unconnected cells : $_unc"
    oss_check_line check_connectivity.rpt "Floating input pins : $_flt"
    oss_check_line check_connectivity.rpt "Open signal nets : $_open"
    oss_check_line check_connectivity.rpt "Missing tie cells : $_tie"
}

# ── report_pg.rpt / report_power.rpt: power grid geometry ───────────────────
# PG special-wire shapes per net: shp(<net>) {x0 y0 x1 y1 layer shape_type},
# via(<net>) {x0 y0 x1 y1 bottom_level top_level}.
proc ::oss_phys::pg_shapes {} {
    variable blk; variable shp; variable via; variable pg_nets {}
    array unset shp; array unset via; array set shp {}; array set via {}
    foreach _n [$blk getNets] {
        if {[$_n getSigType] ni {POWER GROUND} || [llength [$_n getSWires]] == 0} continue
        set _nm [$_n getName]; lappend pg_nets $_nm
        set shp($_nm) {}; set via($_nm) {}
        foreach _sw [$_n getSWires] {
            foreach _b [$_sw getWires] {
                set _r [list [$_b xMin] [$_b yMin] [$_b xMax] [$_b yMax]]
                if {[$_b isVia]} {
                    set _v [$_b getTechVia]
                    if {$_v eq "NULL"} { set _v [$_b getBlockVia] }
                    lappend via($_nm) [concat $_r [[$_v getBottomLayer] getRoutingLevel] [[$_v getTopLayer] getRoutingLevel]]
                } else {
                    lappend shp($_nm) [concat $_r [[$_b getTechLayer] getName] [$_b getWireShapeType]]
                }
            }
        }
    }
}

proc ::oss_phys::lvl {layer} { return [[[ord::get_db_tech] findLayer $layer] getRoutingLevel] }

proc ::oss_phys::pg_grid {stage} {
    variable blk; variable shp; variable via; variable pg_nets
    # Unconnected PG cells: instances with a supply pin on no net
    set _upg 0
    foreach _i [$blk getInsts] {
        foreach _it [$_i getITerms] {
            if {[[$_it getMTerm] getSigType] in {POWER GROUND} && [$_it getNet] eq "NULL"} { incr _upg; break }
        }
    }
    oss_check_line report_pg.rpt "Unconnected PG cells : $_upg"

    if {![oss_pdn_enabled]} { skip "power vias / strap coverage / strap width" "PDN off (project(pdn,enable))"; return }
    pg_shapes
    set _rail [oss_ms pdn_rail_layer]
    lassign [oss_ms pdn_strap_v] _lv _wv
    lassign [oss_ms pdn_strap_h] _lh _wh
    set _grid {FOLLOWPIN STRIPE RING}

    # Missing power vias: same-net crossings of the grid's connected layer
    # pairs (rail-vertical strap, vertical-horizontal strap) without a via on
    # every cut layer between them
    set _miss 0; set _cross 0
    foreach _nm $pg_nets {
        foreach {_lo _hi} [list $_rail $_lv $_lv $_lh] {
            set _llo [lvl $_lo]; set _lhi [lvl $_hi]
            set _A {}; set _B {}
            foreach _s $shp($_nm) {
                if {[lindex $_s 5] ni $_grid} continue
                if {[lindex $_s 4] eq $_lo} { lappend _A $_s } elseif {[lindex $_s 4] eq $_hi} { lappend _B $_s }
            }
            foreach _b $_B {
                set _vs {}
                foreach _v $via($_nm) { if {[hit $_v $_b] && [lindex $_v 4] >= $_llo && [lindex $_v 5] <= $_lhi} { lappend _vs $_v } }
                foreach _a $_A {
                    if {![hit $_a $_b]} continue
                    set _x [list [expr {max([lindex $_a 0], [lindex $_b 0])}] [expr {max([lindex $_a 1], [lindex $_b 1])}] \
                                 [expr {min([lindex $_a 2], [lindex $_b 2])}] [expr {min([lindex $_a 3], [lindex $_b 3])}]]
                    incr _cross
                    for {set _k $_llo} {$_k < $_lhi} {incr _k} {
                        set _ok 0
                        foreach _v $_vs { if {[lindex $_v 4] == $_k && [hit $_v $_x]} { set _ok 1; break } }
                        if {!$_ok} { incr _miss; break }
                    }
                }
            }
        }
    }
    oss_check_line report_pg.rpt "Missing power vias : $_miss"
    handle_info "checklist physical: $_cross power-grid crossings, $_miss without a full via stack"

    # Power strap coverage: share of the follow-pin rail length fed by the
    # strap grid (rail segments with a via up from the rail layer)
    set _llo [lvl $_rail]; set _tot 0.0; set _fed 0.0
    foreach _nm $pg_nets {
        foreach _s $shp($_nm) {
            if {[lindex $_s 4] ne $_rail || [lindex $_s 5] ne "FOLLOWPIN"} continue
            set _len [expr {max([lindex $_s 2] - [lindex $_s 0], [lindex $_s 3] - [lindex $_s 1])}]
            set _tot [expr {$_tot + $_len}]
            foreach _v $via($_nm) { if {[lindex $_v 4] == $_llo && [hit $_v $_s]} { set _fed [expr {$_fed + $_len}]; break } }
        }
    }
    if {$_tot > 0} {
        oss_check_line report_power.rpt [format "Power strap coverage : %.2f%%" [expr {100.0 * $_fed / $_tot}]]
    } else {
        skip "power strap coverage" "no follow-pin rails on $_rail"
    }

    # Power strap width violations: grid shapes narrower than the layer's
    # minimum width or the configured PDN width, or wider than its maximum
    variable dbu
    set _cfg [dict create $_rail [expr {round([oss_ms pdn_rail_width] * $dbu)}] \
                          $_lv [expr {round($_wv * $dbu)}] $_lh [expr {round($_wh * $dbu)}]]
    set _bad 0
    foreach _nm $pg_nets {
        foreach _s $shp($_nm) {
            if {[lindex $_s 5] ni $_grid} continue
            set _l [[ord::get_db_tech] findLayer [lindex $_s 4]]
            set _w [expr {[$_l getDirection] eq "HORIZONTAL" ? [lindex $_s 3] - [lindex $_s 1] : [lindex $_s 2] - [lindex $_s 0]}]
            set _min [$_l getMinWidth]
            if {[dict exists $_cfg [lindex $_s 4]]} { set _min [expr {max($_min, [dict get $_cfg [lindex $_s 4]])}] }
            set _max [$_l getMaxWidth]
            if {$_w < $_min || ($_max > 0 && $_w > $_max)} { incr _bad }
        }
    }
    oss_check_line report_power.rpt "Power strap width violations : $_bad"
}

# ── report_power.rpt: IR drop + EM (PSM), pro / signoff ─────────────────────
# Worst IR drop over the node's views and supply nets (mV). EM: per resistor
# of PSM's EM output, DC current against the tech LEF's DCCURRENTDENSITY
# AVERAGE (wires: mA/um over the narrowest grid shape of the layer; vias:
# mA per cut, the whole via current on one cut — conservative).
proc ::oss_phys::lef_em_limits {} {
    set _f [oss_get tech lef_tech]
    set _fh [open $_f]; set _t [read $_fh]; close $_fh
    set _lim [dict create]; set _layer ""
    foreach _ln [split $_t \n] {
        if {[regexp {^\s*LAYER\s+(\S+)} $_ln -> _l]} { set _layer $_l; continue }
        if {[regexp {^\s*END\s+(\S+)} $_ln -> _l] && $_l eq $_layer} { set _layer ""; continue }
        if {$_layer ne "" && [regexp {^\s*DCCURRENTDENSITY\s+AVERAGE\s+([\d.eE+-]+)\s*;} $_ln -> _v]} {
            dict set _lim $_layer $_v
        }
    }
    return $_lim
}

proc ::oss_phys::ir_em {stage} {
    variable blk; variable dbu; variable shp; variable pg_nets
    if {$stage ni {pro signoff}} return
    if {![oss_pdn_enabled]} { skip "IR drop / EM" "PDN off (project(pdn,enable))"; return }
    if {![info exists pg_nets]} { pg_shapes }
    set _lim [lef_em_limits]
    if {[dict size $_lim] == 0} { skip "EM violations" "no DCCURRENTDENSITY AVERAGE in [oss_get tech lef_tech]" }
    # cut layer between two routing layers (tech layer order)
    set _layers [lmap _l [[ord::get_db_tech] getLayers] {$_l getName}]
    set _worst ""; set _em 0; set _runs 0
    set _tmp "$::REPORTS_DIR/.phys_psm.tmp"; set _emf "$::REPORTS_DIR/.phys_em.tmp"
    foreach _v [oss_node_views $::NODE_NAME] {
        foreach _nm $pg_nets {
            set _n [$blk findNet $_nm]
            if {[llength [$_n getITerms]] == 0} continue
            if {[catch {oss_report $_tmp analyze_power_grid -net $_nm -corner $_v -enable_em -em_outfile $_emf} _e]} {
                handle_info "checklist physical: analyze_power_grid $_nm ($_v) failed: $_e"
                continue
            }
            set _fh [open $_tmp]; set _t [read $_fh]; close $_fh
            if {[regexp {Worstcase IR drop\s*:\s*([-\d.eE+]+)\s*V} $_t -> _d]} {
                incr _runs
                set _mv [expr {abs($_d) * 1000.0}]
                if {$_worst eq "" || $_mv > $_worst} { set _worst $_mv }
            }
            if {[dict size $_lim] > 0 && [file exists $_emf]} {
                # narrowest grid shape per layer of this net (um)
                set _wmin [dict create]
                foreach _s $shp($_nm) {
                    set _w [um [expr {min([lindex $_s 2] - [lindex $_s 0], [lindex $_s 3] - [lindex $_s 1])}]]
                    set _l [lindex $_s 4]
                    if {![dict exists $_wmin $_l] || $_w < [dict get $_wmin $_l]} { dict set _wmin $_l $_w }
                }
                set _fh [open $_emf]; gets $_fh
                while {[gets $_fh _ln] >= 0} {
                    lassign [split $_ln ,] _l0 _ _ _l1 _ _ _i
                    if {![string is double -strict $_i]} continue
                    set _ma [expr {abs($_i) * 1000.0}]
                    if {$_l0 eq $_l1} {
                        if {![dict exists $_lim $_l0] || ![dict exists $_wmin $_l0]} continue
                        if {$_ma / [dict get $_wmin $_l0] > [dict get $_lim $_l0]} { incr _em }
                    } else {
                        set _a [lsearch -exact $_layers $_l0]; set _b [lsearch -exact $_layers $_l1]
                        set _cut [lindex $_layers [expr {($_a + $_b) / 2}]]
                        if {abs($_a - $_b) == 2 && [dict exists $_lim $_cut] && $_ma > [dict get $_lim $_cut]} { incr _em }
                    }
                }
                close $_fh
            }
        }
    }
    file delete -force $_tmp $_emf
    if {$_worst ne ""} {
        oss_check_line report_power.rpt [format "Worst IR drop : %.4f mV" $_worst]
        if {[dict size $_lim] > 0} { oss_check_line report_power.rpt "EM violations : $_em" }
        handle_info "checklist physical: PSM $_runs net/view run(s)"
    } else {
        skip "IR drop / EM" "analyze_power_grid produced no IR report"
    }
}

# ── check_legality.rpt ───────────────────────────────────────────────────────
proc ::oss_phys::legality {stage} {
    variable blk; variable role; variable rows; variable row_y; variable row_h
    variable site_w; variable macros; variable dbu
    # instances per row y (bottom row of each instance)
    array set _at {}
    foreach _i [$blk getInsts] {
        if {$role($_i) eq "macro"} continue
        lassign [bbox $_i] _x0 _y0 _x1 _y1
        lappend _at($_y0) [list $_x0 $_x1 $role($_i) $_i $_y1]
    }

    # Well taps: a row's two wells are each shared with one abutting row
    # (rows flip in pairs) and tapcell staggers the taps between them. A
    # point is covered when within tech(<track>,well_tap_distance) of a tap
    # in its own row, or of taps in both abutting rows (each well tapped).
    # Well tap violations: rows with uncovered length.
    set _D [expr {round([oss_trk well_tap_distance] * $dbu)}]
    array set _taps {}
    foreach _y [array names _at] {
        foreach _c $_at($_y) { if {[lindex $_c 2] eq "tap"} { lappend _taps($_y) [lrange $_c 0 1] } }
    }
    set _tot 0; set _cov 0; set _wtv 0
    foreach _r $rows {
        lassign $_r _x0 _y0 _x1 _y1
        set _reach {}
        foreach _yy [list $_y0 [expr {$_y0 - $row_h}] [expr {$_y0 + $row_h}]] {
            set _iv {}
            if {[info exists _taps($_yy)]} {
                foreach _t $_taps($_yy) {
                    lassign $_t _a _b
                    set _a [expr {max($_x0, $_a - $_D)}]; set _b [expr {min($_x1, $_b + $_D)}]
                    if {$_b > $_a} { lappend _iv [list $_a $_b] }
                }
            }
            lappend _reach [merge_iv $_iv]
        }
        lassign $_reach _own _below _above
        set _c [merged_len [concat $_own [intersect_iv $_below $_above]]]
        incr _tot [expr {$_x1 - $_x0}]; incr _cov $_c
        if {$_c < $_x1 - $_x0} { incr _wtv }
    }
    oss_check_line check_legality.rpt [format "Well tap coverage : %.2f%%" [expr {$_tot ? 100.0 * $_cov / $_tot : 0.0}]]
    oss_check_line check_legality.rpt "Well Tap Violations : $_wtv"

    # Endcaps: every row segment end carries an endcap cell
    set _ec [dict create]
    foreach _i [$blk getInsts] {
        if {$role($_i) ne "endcap"} continue
        lassign [bbox $_i] _x0 _y0 _x1 _y1
        dict set _ec "$_y0,$_x0" 1; dict set _ec "$_y0,$_x1" 1
    }
    set _mec 0
    foreach _r $rows {
        lassign $_r _x0 _y0 _x1
        if {![dict exists $_ec "$_y0,$_x0"]} { incr _mec }
        if {![dict exists $_ec "$_y0,$_x1"]} { incr _mec }
    }
    oss_check_line check_legality.rpt "Missing endcap cells : $_mec"
    oss_check_line check_legality.rpt "Missing Endcap Cells : $_mec"

    # Power domains with a physical area: region boxes (voltage areas) and
    # hard-macro elements. Boundary cells: the row ends facing a domain macro
    # and the rows crossing a region edge carry an endcap at the boundary.
    # Domain boundary violations: non-member cells inside a domain area,
    # member cells outside their region.
    set _mbc 0; set _pdv 0; set _areas {}
    foreach _pd [$blk getPowerDomains] {
        set _boxes {}; set _mac {}
        set _grp [$_pd getGroup]
        if {$_grp ne "NULL" && [$_grp getRegion] ne "NULL"} {
            foreach _bx [[$_grp getRegion] getBoundaries] { lappend _boxes [bbox $_bx] }
        }
        set _els [lsearch -all -inline -not -exact [$_pd getElements] .]
        foreach _el $_els {
            set _mi [$blk findInst $_el]
            if {$_mi ne "NULL" && [[$_mi getMaster] isBlock]} { lappend _mac $_mi }
        }
        foreach _mi $_mac {
            set _mb [bbox $_mi]
            lassign $_mb _mx0 _my0 _mx1 _my1
            # facing row segments left / right of the macro, per row y
            array unset _lf; array unset _rt; array set _lf {}; array set _rt {}
            foreach _r $rows {
                lassign $_r _x0 _y0 _x1 _y1
                if {$_y1 <= $_my0 || $_y0 >= $_my1} continue
                if {$_x1 <= $_mx0 && (![info exists _lf($_y0)] || $_x1 > $_lf($_y0))} { set _lf($_y0) $_x1 }
                if {$_x0 >= $_mx1 && (![info exists _rt($_y0)] || $_x0 < $_rt($_y0))} { set _rt($_y0) $_x0 }
            }
            foreach _y [array names _lf] { if {![dict exists $_ec "$_y,$_lf($_y)"]} { incr _mbc } }
            foreach _y [array names _rt] { if {![dict exists $_ec "$_y,$_rt($_y)"]} { incr _mbc } }
            foreach _i [$blk getInsts] {
                if {$_i ne $_mi && [hit [bbox $_i] $_mb]} { incr _pdv }
            }
        }
        foreach _b $_boxes {
            lassign $_b _bx0 _by0 _bx1 _by1
            foreach _r $rows {
                lassign $_r _x0 _y0 _x1 _y1
                if {$_y0 < $_by0 || $_y1 > $_by1} continue
                foreach _e [list $_bx0 $_bx1] {
                    if {$_e <= $_x0 || $_e >= $_x1} continue
                    set _ok 0
                    if {[info exists _at($_y0)]} {
                        foreach _c $_at($_y0) {
                            if {[lindex $_c 2] in {endcap physical} && ([lindex $_c 0] == $_e || [lindex $_c 1] == $_e)} { set _ok 1; break }
                        }
                    }
                    if {!$_ok} { incr _mbc }
                }
            }
            foreach _i [$blk getInsts] {
                if {$role($_i) eq "macro"} continue
                set _mem 0
                foreach _el $_els { if {[string match "$_el/*" [$_i getName]]} { set _mem 1; break } }
                set _in [hit [bbox $_i] $_b]
                if {($_mem && !$_in) || (!$_mem && $_in && [llength $_els] > 0)} { incr _pdv }
            }
        }
    }
    oss_check_line check_legality.rpt "Missing boundary cells : $_mbc"
    oss_check_line check_legality.rpt "Power Domain Boundary Violations : $_pdv"

    # Cell orientation: a cell on a row is R0/MY on R0 rows, MX/R180 on MX rows
    set _flip [dict create R0 MY MY R0 MX R180 R180 MX]
    set _cov 0
    foreach _y [array names _at] {
        if {![info exists row_y($_y)]} continue
        set _ro [lindex $rows [lindex $row_y($_y) 0] 4]
        foreach _c $_at($_y) {
            set _o [[lindex $_c 3] getOrient]
            if {$_o ne $_ro && (![dict exists $_flip $_ro] || $_o ne [dict get $_flip $_ro])} { incr _cov }
        }
    }
    oss_check_line check_legality.rpt "Cell Orientation Violations : $_cov"

    # Macro keepout: the instance halo, else the keepout as built (the row-free
    # band tapcell cut around the macro, per side). Halo violation: a cell
    # inside the macro or its keepout.
    set _hv 0
    foreach _mi $macros {
        lassign [bbox $_mi] _mx0 _my0 _mx1 _my1
        set _h [$_mi getHalo]
        if {$_h ne "NULL"} {
            set _k [list [$_h xMin] [$_h yMin] [$_h xMax] [$_h yMax]]
        } else {
            set _k [keepout_as_built $_mx0 $_my0 $_mx1 $_my1]
        }
        lassign $_k _hl _hb _hr _ht
        set _kb [list [expr {$_mx0 - $_hl}] [expr {$_my0 - $_hb}] [expr {$_mx1 + $_hr}] [expr {$_my1 + $_ht}]]
        foreach _i [$blk getInsts] {
            if {$role($_i) ne "macro" && [hit [bbox $_i] $_kb]} { incr _hv }
        }
    }
    oss_check_line check_legality.rpt "Halo Violations : $_hv"

    # Hard placement blockages: cells placed over one (partial-density
    # blockages excluded)
    set _bo 0
    foreach _bk [$blk getBlockages] {
        if {[$_bk isSoft] || ([$_bk getMaxDensity] > 0 && [$_bk getMaxDensity] < 100)} continue
        set _bb [bbox $_bk]
        set _own [$_bk getInstance]
        foreach _i [$blk getInsts] {
            if {$_i ne $_own && $role($_i) ne "macro" && [hit [bbox $_i] $_bb]} { incr _bo }
        }
    }
    oss_check_line check_legality.rpt "Blockage Overlap Violations : $_bo"

    # Cell padding / spacing: DPL check_placement failures of the spacing
    # categories (edge spacing, one-site gap, padding)
    set _tmp "$::REPORTS_DIR/.phys_dpl.tmp"
    set _rc [catch {oss_report $_tmp check_placement -verbose} _e]
    set _t ""
    if {[file exists $_tmp]} { set _fh [open $_tmp]; set _t [read $_fh]; close $_fh; file delete $_tmp }
    set _pad 0
    foreach {_ _cat _n} [regexp -all -inline -line {([A-Za-z][A-Za-z -]*?) check failed \((\d+)\)} $_t] {
        if {[regexp -nocase {spacing|site gap|padding} $_cat]} { incr _pad $_n }
    }
    if {!$_rc || [regexp {check failed} $_t]} {
        oss_check_line check_legality.rpt "Cell padding violations : $_pad"
    } else {
        skip "cell padding violations" "check_placement failed without a per-check summary: $_e"
    }

    # Fillers (pro / signoff, after filler insertion): uncovered row gaps of
    # a site or more
    if {$stage in {pro signoff}} {
        set _gaps 0
        foreach _r $rows {
            lassign $_r _x0 _y0 _x1 _y1
            set _iv {}
            # cells overlapping this row segment (multi-row cells included)
            foreach _yy [array names _at] {
                if {$_yy > $_y0 || $_yy + 8 * $row_h < $_y0} continue
                foreach _c $_at($_yy) {
                    if {[lindex $_c 4] <= $_y0} continue
                    set _a [expr {max($_x0, [lindex $_c 0])}]; set _b [expr {min($_x1, [lindex $_c 1])}]
                    if {$_b > $_a} { lappend _iv [list $_a $_b] }
                }
            }
            set _p $_x0
            foreach _s [lsort -integer -index 0 $_iv] {
                if {[lindex $_s 0] - $_p >= $site_w} { incr _gaps }
                set _p [expr {max($_p, [lindex $_s 1])}]
            }
            if {$_x1 - $_p >= $site_w} { incr _gaps }
        }
        oss_check_line check_legality.rpt "Filler gaps : $_gaps"
    }
}

# Union of intervals {{a b} ...} as sorted disjoint intervals
proc ::oss_phys::merge_iv {iv} {
    set _out {}
    foreach _s [lsort -integer -index 0 $iv] {
        lassign $_s _a _b
        if {[llength $_out] && $_a <= [lindex $_out end 1]} {
            lset _out end 1 [expr {max([lindex $_out end 1], $_b)}]
        } else { lappend _out [list $_a $_b] }
    }
    return $_out
}

# Intersection of two sorted disjoint interval lists
proc ::oss_phys::intersect_iv {p q} {
    set _out {}; set i 0; set j 0
    while {$i < [llength $p] && $j < [llength $q]} {
        lassign [lindex $p $i] _a0 _a1; lassign [lindex $q $j] _b0 _b1
        set _lo [expr {max($_a0, $_b0)}]; set _hi [expr {min($_a1, $_b1)}]
        if {$_hi > $_lo} { lappend _out [list $_lo $_hi] }
        if {$_a1 < $_b1} { incr i } else { incr j }
    }
    return $_out
}

# Total length of a union of intervals {{a b} ...}
proc ::oss_phys::merged_len {iv} {
    set _len 0; set _e ""
    foreach _s [lsort -integer -index 0 $iv] {
        lassign $_s _a _b
        if {$_e eq "" || $_a > $_e} { incr _len [expr {$_b - $_a}]; set _e $_b } elseif {$_b > $_e} { incr _len [expr {$_b - $_e}]; set _e $_b }
    }
    return $_len
}

# Row-free band around a macro per side {left bottom right top} (dbu): the
# distance to the nearest facing row segment; 0 toward the core edge.
proc ::oss_phys::keepout_as_built {mx0 my0 mx1 my1} {
    variable rows; variable core
    set _l ""; set _r ""; set _b ""; set _t ""
    foreach _rw $rows {
        lassign $_rw _x0 _y0 _x1 _y1
        if {$_y1 > $my0 && $_y0 < $my1} {
            if {$_x1 <= $mx0 && ($_l eq "" || $mx0 - $_x1 < $_l)} { set _l [expr {$mx0 - $_x1}] }
            if {$_x0 >= $mx1 && ($_r eq "" || $_x0 - $mx1 < $_r)} { set _r [expr {$_x0 - $mx1}] }
        }
        if {$_x1 > $mx0 && $_x0 < $mx1} {
            if {$_y1 <= $my0 && ($_b eq "" || $my0 - $_y1 < $_b)} { set _b [expr {$my0 - $_y1}] }
            if {$_y0 >= $my1 && ($_t eq "" || $_y0 - $my1 < $_t)} { set _t [expr {$_y0 - $my1}] }
        }
    }
    return [lmap _v [list $_l $_b $_r $_t] {expr {$_v eq "" ? 0 : $_v}}]
}

# ── Bin grid: utilization, pin density, decap / spare coverage, RUDY ────────
# Bins covered by a box: {ix0 ix1 iy0 iy1}
proc ::oss_phys::_span {x0 y0 x1 y1 cx0 cy0 bs nx ny} {
    return [list [expr {max(0, int(($x0 - $cx0) / $bs))}] [expr {min($nx - 1, int(($x1 - 1 - $cx0) / $bs))}] \
                 [expr {max(0, int(($y0 - $cy0) / $bs))}] [expr {min($ny - 1, int(($y1 - 1 - $cy0) / $bs))}]]
}

proc ::oss_phys::bins {stage} {
    variable blk; variable role; variable rows; variable row_h; variable site_w
    variable core; variable dbu; variable bin_rows; variable bin_min_avail
    variable decap_masters; variable routed
    lassign $core _cx0 _cy0 _cx1 _cy1
    set _bs [expr {$bin_rows * $row_h}]
    set _nx [expr {int(ceil(($_cx1 - $_cx0) / double($_bs)))}]
    set _ny [expr {int(ceil(($_cy1 - $_cy0) / double($_bs)))}]
    set _bin_area [expr {double($_bs) * $_bs}]
    array set _avail {}; array set _cell {}; array set _pins {}; array set _dec {}; array set _spr {}; array set _dem {}
    # row area per bin, minus hard placement blockages over rows
    set _hb {}
    foreach _bk [$blk getBlockages] {
        if {[$_bk isSoft] || ([$_bk getMaxDensity] > 0 && [$_bk getMaxDensity] < 100)} continue
        lappend _hb [bbox $_bk]
    }
    foreach _r $rows {
        lassign $_r _x0 _y0 _x1 _y1
        lassign [_span $_x0 $_y0 $_x1 $_y1 $_cx0 $_cy0 $_bs $_nx $_ny] _ia _ib _ja _jb
        for {set _i $_ia} {$_i <= $_ib} {incr _i} {
            set _bx0 [expr {$_cx0 + $_i * $_bs}]; set _bx1 [expr {$_bx0 + $_bs}]
            for {set _j $_ja} {$_j <= $_jb} {incr _j} {
                set _by0 [expr {$_cy0 + $_j * $_bs}]; set _by1 [expr {$_by0 + $_bs}]
                set _a [expr {double([ovl $_x0 $_x1 $_bx0 $_bx1]) * [ovl $_y0 $_y1 $_by0 $_by1]}]
                foreach _h $_hb {
                    lassign $_h _hx0 _hy0 _hx1 _hy1
                    set _a [expr {$_a - double([ovl [expr {max($_x0, $_hx0)}] [expr {min($_x1, $_hx1)}] $_bx0 $_bx1]) \
                                               * [ovl [expr {max($_y0, $_hy0)}] [expr {min($_y1, $_hy1)}] $_by0 $_by1]}]
                }
                set _k "$_i,$_j"
                set _avail($_k) [expr {([info exists _avail($_k)] ? $_avail($_k) : 0.0) + max(0.0, $_a)}]
            }
        }
    }
    # cell area (all placed standard cells but fillers), signal pins, decaps
    # (not endcaps), spare cells (master / instance name contains "spare")
    foreach _i [$blk getInsts] {
        set _ro $role($_i)
        if {$_ro in {macro filler}} continue
        lassign [bbox $_i] _x0 _y0 _x1 _y1
        lassign [_span $_x0 $_y0 $_x1 $_y1 $_cx0 $_cy0 $_bs $_nx $_ny] _ia _ib _ja _jb
        for {set _a $_ia} {$_a <= $_ib} {incr _a} {
            set _bx0 [expr {$_cx0 + $_a * $_bs}]
            for {set _b $_ja} {$_b <= $_jb} {incr _b} {
                set _by0 [expr {$_cy0 + $_b * $_bs}]
                set _k "$_a,$_b"
                set _ar [expr {double([ovl $_x0 $_x1 $_bx0 [expr {$_bx0 + $_bs}]]) * [ovl $_y0 $_y1 $_by0 [expr {$_by0 + $_bs}]]}]
                set _cell($_k) [expr {([info exists _cell($_k)] ? $_cell($_k) : 0.0) + $_ar}]
            }
        }
        set _k "[expr {min($_nx - 1, max(0, int((($_x0 + $_x1) / 2 - $_cx0) / $_bs)))}],[expr {min($_ny - 1, max(0, int((($_y0 + $_y1) / 2 - $_cy0) / $_bs)))}]"
        set _mn [[$_i getMaster] getName]
        if {$_ro ne "endcap" && $_mn in $decap_masters} { set _dec($_k) 1 }
        if {[string match -nocase *spare* $_mn] || [string match -nocase *spare* [$_i getName]]} { set _spr($_k) 1 }
        if {$_ro eq "logic"} {
            set _np 0
            foreach _it [$_i getITerms] {
                if {[[$_it getMTerm] getSigType] ni {POWER GROUND} && [$_it getNet] ne "NULL"} { incr _np }
            }
            set _pins($_k) [expr {([info exists _pins($_k)] ? $_pins($_k) : 0) + $_np}]
        }
    }
    # RUDY: each signal net spreads (w+h)/(w*h) wire per unit area over its
    # pin bounding box; capacity = sum over the signal routing layers of
    # area / pitch
    set _lr [oss_signal_layers [oss_get flow design_name] [hier_children [oss_get flow design_name]]]
    set _l0 [lvl [lindex $_lr 0]]; set _l1 [lvl [lindex $_lr 1]]
    set _inv_p 0.0; set _pmin ""
    foreach _l [[ord::get_db_tech] getLayers] {
        if {[$_l getType] ne "ROUTING"} continue
        set _lv [$_l getRoutingLevel]
        if {$_lv < $_l0 || $_lv > $_l1} continue
        set _inv_p [expr {$_inv_p + 1.0 / [$_l getPitch]}]
        if {$_pmin eq "" || [$_l getPitch] < $_pmin} { set _pmin [$_l getPitch] }
    }
    variable net_box; array unset net_box; array set net_box {}
    foreach _n [$blk getNets] {
        if {[$_n getSigType] in {POWER GROUND}} continue
        set _pts {}
        foreach _it [$_n getITerms] {
            lassign [$_it getAvgXY] _ok _x _y
            if {!$_ok} { lassign [[$_it getInst] getLocation] _x _y }
            lappend _pts $_x $_y
        }
        foreach _bt [$_n getBTerms] {
            set _bb [$_bt getBBox]
            lappend _pts [expr {([$_bb xMin] + [$_bb xMax]) / 2}] [expr {([$_bb yMin] + [$_bb yMax]) / 2}]
        }
        if {[llength $_pts] < 4} continue
        set _xs {}; set _ys {}
        foreach {_x _y} $_pts { lappend _xs $_x; lappend _ys $_y }
        set _x0 [tcl::mathfunc::min {*}$_xs]; set _x1 [tcl::mathfunc::max {*}$_xs]
        set _y0 [tcl::mathfunc::min {*}$_ys]; set _y1 [tcl::mathfunc::max {*}$_ys]
        set net_box($_n) [list $_x0 $_y0 $_x1 $_y1]
        # degenerate boxes: at least one track pitch wide
        if {$_x1 - $_x0 < $_pmin} { set _x1 [expr {$_x0 + $_pmin}] }
        if {$_y1 - $_y0 < $_pmin} { set _y1 [expr {$_y0 + $_pmin}] }
        set _w [expr {double($_x1 - $_x0)}]; set _h [expr {double($_y1 - $_y0)}]
        set _rho [expr {($_w + $_h) / ($_w * $_h)}]
        lassign [_span $_x0 $_y0 $_x1 $_y1 $_cx0 $_cy0 $_bs $_nx $_ny] _ia _ib _ja _jb
        for {set _a $_ia} {$_a <= $_ib} {incr _a} {
            set _bx0 [expr {$_cx0 + $_a * $_bs}]
            for {set _b $_ja} {$_b <= $_jb} {incr _b} {
                set _by0 [expr {$_cy0 + $_b * $_bs}]
                set _k "$_a,$_b"
                set _ar [expr {double([ovl $_x0 $_x1 $_bx0 [expr {$_bx0 + $_bs}]]) * [ovl $_y0 $_y1 $_by0 [expr {$_by0 + $_bs}]]}]
                set _dem($_k) [expr {([info exists _dem($_k)] ? $_dem($_k) : 0.0) + $_rho * $_ar}]
            }
        }
    }

    set _dens {}; set _hot 0; set _ndec 0; set _nspr 0; set _nb 0; set _ovf 0.0; set _peak 0.0
    for {set _a 0} {$_a < $_nx} {incr _a} {
        for {set _b 0} {$_b < $_ny} {incr _b} {
            set _k "$_a,$_b"
            # congestion over every bin inside the core
            set _bx0 [expr {$_cx0 + $_a * $_bs}]; set _by0 [expr {$_cy0 + $_b * $_bs}]
            set _carea [expr {double([ovl $_bx0 [expr {$_bx0 + $_bs}] $_cx0 $_cx1]) * [ovl $_by0 [expr {$_by0 + $_bs}] $_cy0 $_cy1]}]
            set _cap [expr {$_carea * $_inv_p}]
            if {$_cap > 0 && [info exists _dem($_k)]} { set _peak [expr {max($_peak, 100.0 * $_dem($_k) / $_cap)}] }
            if {$_cap > 0 && [info exists _dem($_k)] && $_dem($_k) > $_cap} {
                set _ovf [expr {max($_ovf, 100.0 * ($_dem($_k) - $_cap) / $_cap)}]
            }
            if {![info exists _avail($_k)] || $_avail($_k) < $bin_min_avail * $_bin_area} continue
            incr _nb
            set _c [expr {[info exists _cell($_k)] ? $_cell($_k) : 0.0}]
            lappend _dens [expr {100.0 * $_c / $_avail($_k)}]
            set _sites [expr {$_avail($_k) / (double($site_w) * $row_h)}]
            if {[info exists _pins($_k)] && $_pins($_k) > $_sites} { incr _hot }
            if {[info exists _dec($_k)]} { incr _ndec }
            if {[info exists _spr($_k)]} { incr _nspr }
        }
    }
    if {$_nb == 0} { skip "bin metrics" "no bin with [expr {int($bin_min_avail * 100)}]% row area"; return }
    set _mean [expr {[tcl::mathop::+ {*}$_dens] / double($_nb)}]
    set _var 0.0
    foreach _d $_dens { set _var [expr {$_var + ($_d - $_mean) ** 2}] }
    # Max local density: peak bin standard-cell density (fillers excluded)
    oss_check_line report_utilization.rpt [format "Max Local Density : %.2f %%" [tcl::mathfunc::max {*}$_dens]]
    # Utilization std dev: spread of the bin densities
    oss_check_line report_utilization.rpt [format "Utilization Std Dev : %.2f %%" [expr {sqrt($_var / $_nb)}]]
    # Pin density hotspots: bins with more signal pins than placement sites
    # (one vertical access track per site)
    oss_check_line report_design.rpt "Pin density hotspots : $_hot"
    # Decap coverage: bins holding a decap cell (row-end endcaps excluded)
    oss_check_line report_design.rpt [format "Decap coverage : %.2f%%" [expr {100.0 * $_ndec / $_nb}]]
    # Spare cell coverage: bins holding a spare cell
    oss_check_line report_design.rpt [format "Spare cell coverage : %.2f%%" [expr {100.0 * $_nspr / $_nb}]]
    # Max overflow: worst bin RUDY wire demand above routing capacity
    oss_check_line report_congestion.rpt [format "Max Overflow : %.2f %%" $_ovf]
    handle_info [format "checklist physical: peak RUDY demand %.1f%% of routing capacity" $_peak]
    handle_info "checklist physical: $_nb bins of [expr {$bin_rows}] rows ($_nx x $_ny grid)"

    # Filler coverage (pro / signoff): row area occupied by cells incl. fillers
    if {$stage in {pro signoff}} {
        set _tot 0.0; set _occ 0.0
        foreach _k [array names _avail] { set _tot [expr {$_tot + $_avail($_k)}] }
        foreach _i [$blk getInsts] {
            if {$role($_i) eq "macro"} continue
            set _b [$_i getBBox]
            set _occ [expr {$_occ + double([$_b xMax] - [$_b xMin]) * ([$_b yMax] - [$_b yMin])}]
        }
        if {$_tot > 0} {
            oss_check_line report_utilization.rpt [format "Filler Coverage : %.2f %%" [expr {min(100.0, 100.0 * $_occ / $_tot)}]]
        }
    }
}

# ── report_qor.rpt: total wire length (um) ──────────────────────────────────
# Pre-route: half-perimeter of every signal net's pin box; from route on: the
# detailed-route length (report_wire_length).
proc ::oss_phys::wirelength {stage} {
    variable routed; variable net_box
    if {$routed} {
        set _tmp "$::REPORTS_DIR/.phys_wl.tmp"
        oss_report "$::REPORTS_DIR/.phys_wl.log" report_wire_length -net * -detailed_route -file $_tmp
        file delete -force "$::REPORTS_DIR/.phys_wl.log"
        set _fh [open $_tmp]; set _t [read $_fh]; close $_fh; file delete -force $_tmp
        set _wl 0.0; set _n 0
        foreach _ln [split $_t \n] {
            if {[regexp {^\S+:\s+\S+\s+([\d.]+)\s+\d+} $_ln -> _l]} { set _wl [expr {$_wl + $_l}]; incr _n }
        }
        if {$_n == 0} { skip "total wire length" "report_wire_length returned no routed net"; return }
    } else {
        if {![info exists net_box] || [array size net_box] == 0} { skip "total wire length" "no signal net with two or more pins"; return }
        set _wl 0.0
        foreach {_n _b} [array get net_box] {
            lassign $_b _x0 _y0 _x1 _y1
            set _wl [expr {$_wl + [um [expr {($_x1 - $_x0) + ($_y1 - $_y0)}]]}]
        }
    }
    oss_check_line report_qor.rpt [format "Total Wire Length : %.0f" $_wl]
}

# ── report_design.rpt: average cell displacement (um) ───────────────────────
# Detailed placement's "average displacement" (legalization from the global /
# incremental placement), worst over the place / cts / cts_opt nodes on this
# node's chain, read from their run logs.
proc ::oss_phys::displacement {stage} {
    set _best ""; set _src {}
    foreach _t {place cts cts_opt} {
        if {[catch {oss_chain_node $_t} _nd]} continue
        set _log "[cbflow_node_dir $_nd]/run/$_nd.log"
        if {![file exists $_log]} continue
        set _fh [open $_log]; set _txt [read $_fh]; close $_fh
        set _m [regexp -all -inline -line {^\s*average displacement\s+([\d.]+)\s*u} $_txt]
        if {[llength $_m] == 0} continue
        set _v [lindex $_m end]
        lappend _src "$_nd=$_v"
        if {$_best eq "" || $_v > $_best} { set _best $_v }
    }
    if {$_best eq ""} { skip "average cell displacement" "no detailed-placement summary in the place / cts / cts_opt logs"; return }
    oss_check_line report_design.rpt [format "Average Cell Displacement : %.2f" $_best]
    handle_info "checklist physical: displacement (um) $_src"
}

# ── report_design.rpt: macro channels, blockage coverage ────────────────────
proc ::oss_phys::macros {stage} {
    variable blk; variable macros; variable core
    lassign $core _cx0 _cy0 _cx1 _cy1
    # Blockage coverage errors: hard / soft placement blockages that are
    # empty or reach outside the core area
    set _be 0
    foreach _bk [$blk getBlockages] {
        lassign [bbox $_bk] _x0 _y0 _x1 _y1
        if {$_x1 <= $_x0 || $_y1 <= $_y0 || $_x0 < $_cx0 || $_y0 < $_cy0 || $_x1 > $_cx1 || $_y1 > $_cy1} { incr _be }
    }
    oss_check_line report_design.rpt "Blockage coverage errors : $_be"
    # Min macro channel width (um): narrowest gap between facing macros, or
    # between a macro and the core edge it faces (abutted edges excluded)
    if {[llength $macros] == 0} { skip "min macro channel width" "no hard macros"; return }
    set _min ""
    set _bx [lmap _m $macros {bbox $_m}]
    foreach _a $_bx {
        lassign $_a _x0 _y0 _x1 _y1
        foreach _g [list [expr {$_x0 - $_cx0}] [expr {$_cx1 - $_x1}] [expr {$_y0 - $_cy0}] [expr {$_cy1 - $_y1}]] {
            if {$_g > 0 && ($_min eq "" || $_g < $_min)} { set _min $_g }
        }
        foreach _b $_bx {
            if {$_a eq $_b} continue
            lassign $_b _u0 _v0 _u1 _v1
            set _g ""
            if {[ovl $_y0 $_y1 $_v0 $_v1] > 0} { set _g [expr {max($_u0 - $_x1, $_x0 - $_u1)}] }
            if {[ovl $_x0 $_x1 $_u0 $_u1] > 0} { set _g [expr {max($_v0 - $_y1, $_y0 - $_v1)}] }
            if {$_g ne "" && $_g > 0 && ($_min eq "" || $_g < $_min)} { set _min $_g }
        }
    }
    if {$_min eq ""} { skip "min macro channel width" "every macro edge abuts the core edge or another macro"; return }
    oss_check_line report_design.rpt [format "Min Macro Channel Width : %.2f" [um $_min]]
}

# ── check_legality.rpt: pin access (DRT) ────────────────────────────────────
# Standard-cell pins without a valid access point (pin_access
# #stdCellPinNoAp). pin_access stores access points in the database, so it
# runs only when this node's database is not saved afterwards (report-only
# cbflow-oss-checks) or the placement is final (pro / signoff).
proc ::oss_phys::pin_access_chk {stage} {
    if {$stage ni {pro signoff} && [info exists ::flow::procs(save_design)]} {
        skip "pin access violations" "pin_access would store access points in the $stage database — measured by cbflow-oss-checks"
        return
    }
    set _tmp "$::REPORTS_DIR/.phys_pa.tmp"
    catch {oss_report $_tmp ::pin_access} _e
    set _t ""
    if {[file exists $_tmp]} { set _fh [open $_tmp]; set _t [read $_fh]; close $_fh; file delete $_tmp }
    if {![regexp {#stdCellPinNoAp\s*=\s*(\d+)} $_t -> _n]} { skip "pin access violations" "pin_access gave no summary: $_e"; return }
    oss_check_line check_legality.rpt "Pin Access Violations : $_n"
}

# ── report_pg.rpt: IO ring continuity ───────────────────────────────────────
# Pad-ring designs: gaps between consecutive pad / corner cells along each die
# edge (the IO power ring runs through abutted pad cells).
proc ::oss_phys::io_ring {stage} {
    variable blk
    set _die [bbox [$blk getDieArea]]
    lassign $_die _dx0 _dy0 _dx1 _dy1
    set _side [dict create]
    foreach _i [$blk getInsts] {
        set _t [[$_i getMaster] getType]
        if {![string match PAD* $_t] && ![string match ENDCAP_*TOP* $_t] && ![string match ENDCAP_*BOTTOM* $_t]} continue
        lassign [bbox $_i] _x0 _y0 _x1 _y1
        set _d [dict create B [expr {$_y0 - $_dy0}] T [expr {$_dy1 - $_y1}] L [expr {$_x0 - $_dx0}] R [expr {$_dx1 - $_x1}]]
        set _s [lindex [lsort -stride 2 -index 1 -integer $_d] 0]
        if {$_s in {B T}} { dict lappend _side $_s [list $_x0 $_x1] } else { dict lappend _side $_s [list $_y0 $_y1] }
    }
    if {[dict size $_side] == 0} { skip "IO ring breaks" "no pad cells (block-level design, no IO ring)"; return }
    set _brk 0
    dict for {_s _iv} $_side {
        set _e ""
        foreach _c [lsort -integer -index 0 $_iv] {
            if {$_e ne "" && [lindex $_c 0] > $_e} { incr _brk }
            set _e [expr {$_e eq "" ? [lindex $_c 1] : max($_e, [lindex $_c 1])}]
        }
    }
    oss_check_line report_pg.rpt "IO ring breaks : $_brk"
}

# ── report_design.rpt: scan chain reorder distance (um) ─────────────────────
# Average Manhattan distance between consecutive scan cells of the database's
# scan chains (scan DEF / DFT insertion).
proc ::oss_phys::scan_chains {stage} {
    variable blk
    set _chains {}
    if {[catch {[$blk getDft] getScanChains} _chains] || [llength $_chains] == 0} {
        skip "scan chain reorder distance" "no scan chains in the database"; return
    }
    set _sum 0.0; set _hops 0
    foreach _ch $_chains {
        foreach _p [$_ch getScanPartitions] {
            foreach _l [$_p getScanLists] {
                set _prev ""
                foreach _si [$_l getScanInsts] {
                    set _b [[$_si getInst] getBBox]
                    set _c [list [expr {([$_b xMin] + [$_b xMax]) / 2}] [expr {([$_b yMin] + [$_b yMax]) / 2}]]
                    if {$_prev ne ""} {
                        set _sum [expr {$_sum + abs([lindex $_c 0] - [lindex $_prev 0]) + abs([lindex $_c 1] - [lindex $_prev 1])}]
                        incr _hops
                    }
                    set _prev $_c
                }
            }
        }
    }
    if {$_hops == 0} { skip "scan chain reorder distance" "scan chains hold fewer than two cells"; return }
    oss_check_line report_design.rpt [format "Scan Chain Reorder Distance : %.2f" [um [expr {$_sum / $_hops}]]]
}
