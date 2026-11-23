# ═══════════════════════════════════════════════════════════════════════════════
# Checklist library reports — routing + manufacturing checks (open-source flow)
#
# oss_checkgrp_routing_mfg <stage>: called by oss_checks_run (oss_checks.tcl)
# with the stage's design loaded in OpenROAD. Routed stages only (route, pro,
# signoff). Every value is measured on the loaded database:
#   DRC        drt::check_drc on the database   (detail: reports/<stage>_drc_markers.rpt)
#   antenna    check_antennas
#   PG opens   check_power_grid per supply net
#   wires      dbWire decode (lengths, vias, metal area) + odb shapes
#   timing     OpenSTA paths (critical nets)
#
# Not producible here (no engine / no rule data in the open-source PNR flow —
# left out, the check reads NA): critical area (CAA), lithography hotspots,
# OPC-unfriendly patterns, etch proximity, CMP uniformity (foundry DFM / litho
# models), ESD completeness (PERC), metal-fill coverage (no metal fill in the
# PNR flow, tech(rules,fill) unset), density-window checks (density-window
# rules not in the tech config), excess vias per net (no minimum-via
# definition), shielding coverage (OpenROAD routes no shields; no shielded-net
# spec). Full-chip DRC on the GDS (KLayout / Magic) runs in the PV flow.
# ═══════════════════════════════════════════════════════════════════════════════

namespace eval ::oss_rmfg {}

# drt::check_drc on the route database → list of {type layer nets} markers.
# The DRC marker category check_drc adds to the block is removed again so it
# never lands in the saved database. From pro on the route node's markers are
# used: OpenRCX extraction (pro) rewrites the wire encoding in the database and
# check_drc then reports thousands of false shorts / spacing / min-area markers
# (ctrl_subsys P1: 0 on route.odb, 5519 on pro.odb, while Magic DRC / Netgen
# LVS of the released layout are clean). pro adds only fillers (no DRC change).
proc ::oss_rmfg::drc_markers {stage} {
    set _blk [ord::get_db_block]
    if {$stage eq "route"} {
        set _f "$::REPORTS_DIR/${stage}_drc_markers.rpt"
        drt::check_drc -output_file $_f -marker_name oss_checks_drc
        set _c [$_blk findMarkerCategory oss_checks_drc]
        if {$_c ne "NULL"} { odb::dbMarkerCategory_destroy $_c }
    } else {
        set _rn [cbflow_chain_node route]
        set _f "[cbflow_node_dir $_rn]/reports/route_drc_markers.rpt"
        if {![file exists $_f]} {
            error "$_f missing — run the checklist reports on $_rn first (cbflow-oss-checks <run> $_rn)"
        }
        file copy -force $_f "$::REPORTS_DIR/${stage}_drc_markers.rpt"
    }
    set _m {}
    set _fh [open $_f]
    set _type ""; set _nets {}
    while {[gets $_fh _ln] >= 0} {
        if {[regexp {violation type:\s*(.+?)\s*$} $_ln -> _t]} {
            set _type $_t; set _nets {}
        } elseif {[regexp {^\s*srcs:\s*(.*)$} $_ln -> _s]} {
            set _nets [regexp -all -inline {net:(\S+)} $_s]
            set _nets [lmap {_ _n} $_nets {set _n}]
        } elseif {[regexp {on Layer\s+(\S+)} $_ln -> _l] && $_type ne ""} {
            lappend _m [list $_type $_l $_nets]
            set _type ""
        }
    }
    close $_fh
    return $_m
}

# DRC marker class: short | via | area | width | spacing | other
proc ::oss_rmfg::drc_class {type layer} {
    set _tl [[ord::get_db_tech] findLayer $layer]
    set _cut [expr {$_tl ne "NULL" && [$_tl getType] eq "CUT"}]
    if {[string equal -nocase $type "Short"]}                       { return short }
    if {$_cut || [regexp -nocase {cut|enclos|via} $type]}           { return via }
    if {[regexp -nocase {area|hole} $type]}                         { return area }
    if {[regexp -nocase {width|step} $type]}                        { return width }
    if {[regexp -nocase {spac|eol|end.of.line|ns metal|corner|notch|parallel} $type]} { return spacing }
    return other
}

# Cut shapes in a via definition (dbVia / dbTechVia); metal boxes per layer.
proc ::oss_rmfg::via_info {via} {
    set _cuts 0; set _metal {}
    foreach _b [$via getBoxes] {
        set _l [$_b getTechLayer]
        if {$_l eq "NULL"} continue
        if {[$_l getType] eq "CUT"} { incr _cuts
        } elseif {[$_l getType] eq "ROUTING"} {
            dict incr _metal [$_l getName] [expr {[$_b getDX] * wide([$_b getDY])}]
        }
    }
    return [list $_cuts $_metal]
}

# Pin location of an ITerm / BTerm (dbu), "" when it has none.
proc ::oss_rmfg::term_xy {term} {
    set _r [expr {[string match *dbBTerm* $term] ? [$term getFirstPinLocation] : [$term getAvgXY]}]
    if {[lindex $_r 0]} { return [lrange $_r 1 2] }
    return ""
}

proc oss_checkgrp_routing_mfg {stage} {
    if {$stage ni {route pro signoff}} return
    set _blk  [ord::get_db_block]
    set _tech [ord::get_db_tech]
    set _dbu  [$_tech getDbUnitsPerMicron]
    set _arr  [oss_flow_arr]
    upvar #0 $_arr _fa
    set _skipped {}

    # Net classes from the database
    set _pg {}; set _clk {}; set _ndr {}
    foreach _n [$_blk getNets] {
        set _st [$_n getSigType]
        if {$_st in {POWER GROUND}} { dict set _pg [$_n getName] 1 }
        if {$_st eq "CLOCK"} { dict set _clk [$_n getName] 1 }
        if {[$_n getNonDefaultRule] ne "NULL"} { dict set _ndr [$_n getName] 1 }
    }

    # ── Detailed-route DRC on this database (drt::check_drc) ─────────────────
    set _cnt [dict create short 0 via 0 area 0 width 0 spacing 0 other 0]
    set _pgshort 0; set _clkdrc 0; set _ndrdrc 0
    set _markers [::oss_rmfg::drc_markers $stage]
    foreach _mk $_markers {
        lassign $_mk _type _layer _nets
        set _cl [::oss_rmfg::drc_class $_type $_layer]
        dict incr _cnt $_cl
        set _npg 0; set _nsig 0; set _isclk 0; set _isndr 0
        foreach _nn $_nets {
            if {[dict exists $_pg $_nn]} { incr _npg } else { incr _nsig }
            if {[dict exists $_clk $_nn]} { set _isclk 1 }
            if {[dict exists $_ndr $_nn]} { set _isndr 1 }
        }
        if {$_cl eq "short" && $_npg > 0 && $_nsig > 0} { incr _pgshort }
        incr _clkdrc $_isclk
        incr _ndrdrc $_isndr
    }
    # ROUTING_0004: every check_drc marker
    oss_check_line signoff_check_drc.rpt "Total DRC violations : [llength $_markers]"
    # ROUTING_0005: metal spacing / EOL / corner / NS-metal markers on metal layers
    oss_check_line signoff_check_drc.rpt "Spacing violations : [dict get $_cnt spacing]"
    # ROUTING_0006: min-width / min-step markers
    oss_check_line signoff_check_drc.rpt "Min width violations : [dict get $_cnt width]"
    # ROUTING_0007: markers on cut layers or cut / enclosure rules
    oss_check_line signoff_check_drc.rpt "Via enclosure violations : [dict get $_cnt via]"
    # ROUTING_0008: min-area / min-hole markers
    oss_check_line signoff_check_drc.rpt "Min area violations : [dict get $_cnt area]"
    oss_check_line signoff_check_drc.rpt "Short violations : [dict get $_cnt short]"
    # ROUTING_0021: shorts between a supply net and a signal net
    oss_check_line check_routes.rpt "Power-to-signal shorts : $_pgshort"
    # ROUTING_0024: markers involving a clock net (CLOCK sig type, set by CTS)
    oss_check_line check_routes.final.rpt "Clock route DRC violations : $_clkdrc"

    # ── Antenna (check_antennas) ─────────────────────────────────────────────
    set _tmp "$::REPORTS_DIR/.oss_rmfg_antenna.tmp"
    oss_report $_tmp check_antennas -verbose      ;# per-pin ratios, kept out of the log
    set _viol {}; set _lyr {}; set _worst 0.0; set _net ""; set _cur ""; set _last ""
    set _fh [open $_tmp]
    while {[gets $_fh _ln] >= 0} {
        if {[regexp {^Net:\s*(\S+)} $_ln -> _net]} continue
        if {[regexp {^\s*Layer:\s*(\S+)} $_ln -> _cur]} continue
        if {[regexp {(Partial|Cumulative) area ratio:\s*([0-9.eE+-]+)} $_ln -> _ _last]} continue
        if {[regexp {Required ratio:\s*([0-9.eE+-]+)} $_ln -> _req] && $_last ne ""} {
            if {$_req > 0} {
                set _r [expr {$_last / $_req}]
                if {$_r > $_worst} { set _worst $_r }
            }
            if {[string match *VIOLATED* $_ln]} { dict set _viol $_net 1; dict incr _lyr $_cur }
            set _last ""
        }
    }
    close $_fh
    file delete $_tmp
    # ROUTING_0011 / MANUFACTURING_0007: nets with an antenna violation
    oss_check_line signoff_check_drc.rpt "Antenna violations : [dict size $_viol]"
    oss_check_line report_antenna.rpt "Antenna violations : [dict size $_viol]"
    foreach _l [dict keys $_lyr] { oss_check_line report_antenna.rpt "Antenna violations $_l : [dict get $_lyr $_l]" }
    # ROUTING_0012: worst antenna ratio / allowed ratio (1.0 = at the limit)
    oss_check_line signoff_check_drc.rpt "Worst antenna ratio : [format %.3f $_worst]"

    # ── Power-grid opens (check_power_grid per connected supply net) ─────────
    if {![is_true [oss_get project pdn,enable]]} {
        lappend _skipped "power_opens (PDN off)"
    } else {
        set _opens 0
        foreach _nn [dict keys $_pg] {
            set _n [$_blk findNet $_nn]
            if {[llength [$_n getITerms]] == 0} continue        ;# feedthrough rail
            set _tmp "$::REPORTS_DIR/.oss_rmfg_pg.tmp"
            file delete $_tmp
            set _rc [catch {check_power_grid -net $_nn -error_file $_tmp} _ok]
            set _k 0
            if {[file exists $_tmp]} {
                set _fh [open $_tmp]; set _k [regexp -all {violation type} [read $_fh]]; close $_fh
                file delete $_tmp
            }
            # unconnected shapes / instances reported; a failed check counts at least once
            if {$_k == 0 && ($_rc || $_ok != 1)} { set _k 1 }
            incr _opens $_k
        }
        # ROUTING_0022
        oss_check_line check_routes.rpt "Power mesh opens : $_opens"
    }

    # ── Wire decode: lengths, vias, metal area per layer ─────────────────────
    set _cut {}                     ;# via handle → {cuts metal-dict}
    set _area {}                    ;# layer → metal area (dbu²)
    set _vias 0; set _multi 0
    set _len {}                     ;# net → routed length (dbu)
    set _ndrbad 0
    set PATH $::odb::dbWireDecoder_PATH; set JCT $::odb::dbWireDecoder_JUNCTION
    set SHORT $::odb::dbWireDecoder_SHORT; set VWIRE $::odb::dbWireDecoder_VWIRE
    set PT $::odb::dbWireDecoder_POINT; set PTX $::odb::dbWireDecoder_POINT_EXT
    set VIA $::odb::dbWireDecoder_VIA; set TVIA $::odb::dbWireDecoder_TECH_VIA
    set RULE $::odb::dbWireDecoder_RULE
    set END $::odb::dbWireDecoder_END_DECODE
    set _dec [odb::dbWireDecoder]
    foreach _n [$_blk getNets] {
        if {[dict exists $_pg [$_n getName]]} continue
        set _w [$_n getWire]
        if {$_w eq "NULL"} continue
        set _isndr [dict exists $_ndr [$_n getName]]
        set _l 0; set _prev ""; set _rule ""; set _bad 0
        $_dec begin $_w
        while {[set _op [$_dec next]] != $END} {
            if {$_op == $PATH || $_op == $JCT || $_op == $SHORT || $_op == $VWIRE} {
                set _prev ""; set _rule ""
            } elseif {$_op == $RULE} {
                set _rule [$_dec getRule]
            } elseif {$_op == $PT || $_op == $PTX} {
                set _p [lrange [expr {$_op == $PT ? [$_dec getPoint] : [$_dec getPoint_ext]}] 0 1]
                if {$_prev ne ""} {
                    set _d [expr {abs([lindex $_p 0] - [lindex $_prev 0]) + abs([lindex $_p 1] - [lindex $_prev 1])}]
                    if {$_d > 0} {
                        set _ly [$_dec getLayer]
                        set _wd [expr {$_rule ne "" ? [$_rule getWidth] : [$_ly getWidth]}]
                        incr _l $_d
                        dict incr _area [$_ly getName] [expr {wide($_d) * $_wd}]
                        if {$_isndr && $_rule eq ""} { set _bad 1 }
                    }
                }
                set _prev $_p
            } elseif {$_op == $VIA || $_op == $TVIA} {
                set _v [expr {$_op == $VIA ? [$_dec getVia] : [$_dec getTechVia]}]
                if {![dict exists $_cut $_v]} { dict set _cut $_v [::oss_rmfg::via_info $_v] }
                lassign [dict get $_cut $_v] _nc _vm
                incr _vias
                if {$_nc > 1} { incr _multi }
                dict for {_ly _a} $_vm { dict incr _area $_ly $_a }
            }
            # RECT (router min-area patches): not counted — tiny, and
            # dbWireDecoder::getRect has no Tcl binding (output args)
        }
        dict set _len [$_n getName] $_l
        incr _ndrbad $_bad
    }

    # ROUTING_0016: NDR nets with segments routed without their rule + DRC
    # markers on NDR nets (0 when the design has no NDR nets)
    oss_check_line check_routes.final.rpt "NDR nets : [dict size $_ndr]"
    oss_check_line check_routes.final.rpt "NDR violations : [expr {$_ndrbad + $_ndrdrc}]"

    # ROUTING_0013: routed nets longer than <flow>(oss,checks,max_net_length) µm
    if {[info exists _fa(oss,checks,max_net_length)] && $_fa(oss,checks,max_net_length) ne ""} {
        set _max [expr {$_fa(oss,checks,max_net_length) * $_dbu}]
        set _k 0
        dict for {_nn _l} $_len { if {$_l > $_max} { incr _k } }
        oss_check_line report_design.rpt "Max net length um : $_fa(oss,checks,max_net_length)"
        oss_check_line report_design.rpt "Nets exceeding length threshold : $_k"
    } else {
        lappend _skipped "net_length_threshold (${_arr}(oss,checks,max_net_length) not set)"
    }

    # ROUTING_0014: 2-pin nets — routed length over pin-to-pin HPWL
    set _rl 0; set _hp 0
    foreach _n [$_blk getNets] {
        set _nn [$_n getName]
        if {![dict exists $_len $_nn]} continue
        set _t [concat [$_n getITerms] [$_n getBTerms]]
        if {[llength $_t] != 2} continue
        set _a [::oss_rmfg::term_xy [lindex $_t 0]]; set _b [::oss_rmfg::term_xy [lindex $_t 1]]
        if {$_a eq "" || $_b eq ""} continue
        set _h [expr {abs([lindex $_a 0] - [lindex $_b 0]) + abs([lindex $_a 1] - [lindex $_b 1])}]
        if {$_h == 0} continue
        incr _hp $_h; incr _rl [dict get $_len $_nn]
    }
    if {$_hp > 0} {
        oss_check_line report_design.rpt "Detour percentage : [format %.2f [expr {100.0 * ($_rl - $_hp) / $_hp}]]%"
    }

    # ROUTING_0025: signal vias with more than one cut
    if {$_vias > 0} {
        oss_check_line report_design.rpt "Signal vias : $_vias"
        oss_check_line report_design.rpt "Multi-cut via ratio : [format %.2f [expr {100.0 * $_multi / $_vias}]]%"
    }

    # ── Metal density per metal layer (shape area / die area) ────────────────
    # Signal wires (length × width) + signal-via metal + power-grid straps /
    # rails + IO pins + standard-cell pin and obstruction shapes. Left out:
    # power-grid via metal (inside the straps it joins), cell supply pins on
    # layers the grid covers with its own rails, hard-macro obstructions
    # (abstract blockages, not drawn metal). Overlaps between the remaining
    # shapes are each counted (no polygon merge).
    set _pgl {}
    foreach _nn [dict keys $_pg] {
        foreach _sw [[$_blk findNet $_nn] getSWires] {
            foreach _b [$_sw getWires] {
                if {![$_b isVia]} {
                    set _ly [[$_b getTechLayer] getName]
                    dict set _pgl $_ly 1
                    dict incr _area $_ly [expr {[$_b getDX] * wide([$_b getDY])}]
                }
            }
        }
    }
    set _mc {}
    foreach _i [$_blk getInsts] { dict incr _mc [$_i getMaster] }
    dict for {_m _k} $_mc {
        set _shapes {}
        foreach _mt [$_m getMTerms] {
            set _sup [expr {[$_mt getSigType] in {POWER GROUND}}]
            foreach _mp [$_mt getMPins] {
                foreach _g [$_mp getGeometry] { lappend _shapes [list $_g $_sup] }
            }
        }
        if {![$_m isBlock]} {
            foreach _g [$_m getObstructions] { lappend _shapes [list $_g 0] }
        }
        foreach _s $_shapes {
            lassign $_s _g _sup
            if {[$_g isVia]} continue
            set _l [$_g getTechLayer]
            if {$_l eq "NULL" || [$_l getType] ne "ROUTING"} continue
            if {$_sup && [dict exists $_pgl [$_l getName]]} continue
            dict incr _area [$_l getName] [expr {$_k * [$_g getDX] * wide([$_g getDY])}]
        }
    }
    foreach _bt [$_blk getBTerms] {
        foreach _bp [$_bt getBPins] {
            foreach _b [$_bp getBoxes] {
                set _l [$_b getTechLayer]
                if {$_l ne "NULL"} { dict incr _area [$_l getName] [expr {[$_b getDX] * wide([$_b getDY])}] }
            }
        }
    }
    set _die  [$_blk getDieArea]
    set _diea [expr {[$_die dx] * double([$_die dy])}]
    # Metal layers M1..Mn: the last tech(<stack>,metal_count) entries of
    # tech(<stack>,metal_layers) (sky130: met1..met5; li1 is local interconnect)
    set _ml [oss_ms metal_layers]
    set _mn [oss_ms metal_count]
    set _metal [lrange $_ml end-[expr {$_mn - 1}] end]
    set _dens {}
    foreach _ly $_metal {
        set _d [expr {100.0 * [expr {[dict exists $_area $_ly] ? [dict get $_area $_ly] : 0}] / $_diea}]
        dict set _dens $_ly $_d
        oss_check_line report_density.rpt "Metal density $_ly : [format %.2f $_d]%"
    }
    set _dv [dict values $_dens]
    # ROUTING_0018 / ROUTING_0019: lowest / highest metal-layer density
    oss_check_line report_design.rpt "Min metal density : [format %.2f [tcl::mathfunc::min {*}$_dv]]%"
    oss_check_line report_design.rpt "Max metal density : [format %.2f [tcl::mathfunc::max {*}$_dv]]%"
    # MANUFACTURING_0001 / 0002: first / second metal layer
    oss_check_line report_density.rpt "M1 density : [format %.2f [dict get $_dens [lindex $_metal 0]]]%"
    oss_check_line report_density.rpt "M2 density : [format %.2f [dict get $_dens [lindex $_metal 1]]]%"
    # MANUFACTURING_0003: layers above M2 outside the tech density limits
    set _stk [oss_stack]
    upvar #0 tech _tc
    set _lo [expr {[info exists _tc($_stk,metal_fill_min_density)] ? $_tc($_stk,metal_fill_min_density) : 0}]
    set _hi [expr {[info exists _tc($_stk,metal_fill_max_density)] ? $_tc($_stk,metal_fill_max_density) : 0}]
    if {$_lo > 0 || $_hi > 0} {
        set _k 0
        foreach _ly [lrange $_metal 2 end] {
            set _d [dict get $_dens $_ly]
            if {($_lo > 0 && $_d < $_lo) || ($_hi > 0 && $_d > $_hi)} { incr _k }
        }
        oss_check_line report_density.rpt "Upper metal density violations : $_k"
    } else {
        lappend _skipped "metal_density_upper (tech($_stk,metal_fill_min/max_density) not set)"
    }

    # MANUFACTURING_0008: no multi-patterning layer in the tech → no DP rules
    set _mp 0
    foreach _l [$_tech getLayers] {
        if {[$_l getType] eq "ROUTING" && [$_l getNumMasks] > 1} { incr _mp }
    }
    if {$_mp == 0} {
        oss_check_line signoff_check_drc.rpt "Double patterning violations : 0"
    } else {
        lappend _skipped "double_patterning ($_mp multi-mask layers; no colouring checker)"
    }

    # ── ROUTING_0023: DRC markers on timing-critical nets (setup paths with
    # slack below <flow>(oss,repair,setup_margin)) ────────────────────────────
    if {![info exists _fa(oss,repair,setup_margin)] || $_fa(oss,repair,setup_margin) eq ""} {
        lappend _skipped "critical_net_routing (${_arr}(oss,repair,setup_margin) not set)"
    } else {
        set _crit {}
        set _ends [find_timing_paths -path_delay max -group_path_count 100000 \
                       -endpoint_path_count 1 -slack_max $_fa(oss,repair,setup_margin)]
        foreach _pe $_ends {
            foreach _pin [[$_pe path] pins] {
                foreach _net [get_nets -quiet -of_objects $_pin] {
                    if {$_net ne "NULL"} { dict set _crit [get_full_name $_net] 1 }
                }
            }
        }
        set _k 0
        foreach _mk $_markers {
            foreach _nn [lindex $_mk 2] { if {[dict exists $_crit $_nn]} { incr _k; break } }
        }
        oss_check_line check_routes.final.rpt "Critical nets : [dict size $_crit]"
        oss_check_line check_routes.final.rpt "Critical net DRC violations : $_k"
    }

    if {[llength $_skipped]} {
        handle_info "routing_mfg checks not produced at $stage: [join $_skipped {; }]"
    }
}
