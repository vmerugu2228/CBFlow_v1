# ═══════════════════════════════════════════════════════════════════════════════
# Checklist group: floorplan (FP_EXIT) — runs at the FP export_data report step
# (oss_checklist_safe fp), with the floorplan database, liberty and SDC loaded.
#
#   report_clocks.rpt            fp_clock_definitions (FP_0004)
#   check_timing.rpt             fp_constraint_check  (FP_0006)
#   check_floorplan_rules.rpt    fp_floorplan_rules   (FP_0007)
#   report_design.rpt            macro_channel_width  (PLACEMENT_0008)
#   report_upf.rpt               power_intent_lint    (POWER_0015)
#
# The FP tool's checklist map (FP_openroad_config.tcl fp(checklist,*)) points
# the FP_00xx checks at these lines; the library checks read their own
# report_pattern basename from the exit node's reports/.
# ═══════════════════════════════════════════════════════════════════════════════

proc oss_checkgrp_fp {stage} {
    if {$stage ne "fp"} { return }
    oss_fpchk_clocks
    oss_fpchk_constraints
    oss_fpchk_rules
    oss_fpchk_channels
    oss_fpchk_upf
}

# Clocks defined by the SDC: name, period (library time units), sources.
proc oss_fpchk_clocks {} {
    set _clks [sta::all_clocks]
    oss_check_line report_clocks.rpt "Clocks defined : [llength $_clks]"
    foreach _c $_clks {
        set _src {}
        foreach _p [$_c sources] { lappend _src [get_full_name $_p] }
        set _kind [expr {[$_c is_generated] ? "generated" : ([$_c is_virtual] ? "virtual" : "master")}]
        oss_check_line report_clocks.rpt \
            "Clock [get_name $_c] : period [sta::format_time [$_c period] 3] $_kind sources {[join $_src]}"
    }
}

# Constraint completeness: OpenSTA check_setup (unclocked registers, unconstrained
# endpoints, missing input/output delays, multiple clocks, loops, generated clocks).
proc oss_fpchk_constraints {} {
    set _errs [sta::check_timing_cmd 1 1 1 1 1 1 1]
    set _n 0
    set _detail {}
    foreach _e $_errs {
        set _objs [llength [lrange $_e 1 end]]
        incr _n [expr {$_objs > 0 ? $_objs : 1}]
        lappend _detail "  [lindex $_e 0]"
    }
    oss_check_line check_timing.rpt "Constraint check categories : [llength $_errs]"
    oss_check_line check_timing.rpt "Constraint check issues : $_n"
    foreach _d $_detail { oss_check_line check_timing.rpt $_d }
}

# Floorplan rules: core inside die, die/core on the manufacturing grid, rows
# inside the core, placed instances inside the core, hard macros placed and
# on the manufacturing grid, IO pins placed on the die boundary.
proc oss_fpchk_rules {} {
    set _blk  [ord::get_db_block]
    set _tech [ord::get_db_tech]
    set _mg   [expr {[$_tech hasManufacturingGrid] ? [$_tech getManufacturingGrid] : 1}]
    set _die  [$_blk getDieArea]
    set _core [$_blk getCoreArea]
    lassign [list [$_die xMin] [$_die yMin] [$_die xMax] [$_die yMax]] dx0 dy0 dx1 dy1
    lassign [list [$_core xMin] [$_core yMin] [$_core xMax] [$_core yMax]] cx0 cy0 cx1 cy1

    set _core_out [expr {($cx0 < $dx0 || $cy0 < $dy0 || $cx1 > $dx1 || $cy1 > $dy1) ? 1 : 0}]
    set _off 0
    foreach _v [list $dx0 $dy0 $dx1 $dy1 $cx0 $cy0 $cx1 $cy1] { if {$_v % $_mg} { incr _off } }

    set _rows [$_blk getRows]
    set _row_out 0
    foreach _r $_rows {
        set _b [$_r getBBox]
        if {[$_b xMin] < $cx0 || [$_b yMin] < $cy0 || [$_b xMax] > $cx1 || [$_b yMax] > $cy1} { incr _row_out }
    }

    set _inst_out 0; set _macro_unpl 0; set _macro_off 0
    foreach _i [$_blk getInsts] {
        set _st [$_i getPlacementStatus]
        set _blkm [[$_i getMaster] isBlock]
        if {$_st in {NONE UNPLACED}} {
            if {$_blkm} { incr _macro_unpl }
            continue
        }
        set _b [$_i getBBox]
        if {[$_b xMin] < $cx0 || [$_b yMin] < $cy0 || [$_b xMax] > $cx1 || [$_b yMax] > $cy1} { incr _inst_out }
        if {$_blkm && ([$_b xMin] % $_mg || [$_b yMin] % $_mg)} { incr _macro_off }
    }

    set _pin_unpl 0; set _pin_off_edge 0
    foreach _bt [$_blk getBTerms] {
        set _placed 0
        foreach _bp [$_bt getBPins] {
            if {[$_bp getPlacementStatus] in {NONE UNPLACED}} continue
            set _placed 1
            set _b [$_bp getBBox]
            set _inside [expr {[$_b xMin] >= $dx0 && [$_b yMin] >= $dy0 && [$_b xMax] <= $dx1 && [$_b yMax] <= $dy1}]
            set _edge [expr {[$_b xMin] == $dx0 || [$_b yMin] == $dy0 || [$_b xMax] == $dx1 || [$_b yMax] == $dy1}]
            if {!$_inside || !$_edge} { incr _pin_off_edge }
        }
        # Supply ports have no pin shape at FP (connected by the power grid)
        if {!$_placed && [$_bt getSigType] ni {POWER GROUND}} { incr _pin_unpl }
    }

    set _no_rows [expr {[llength $_rows] == 0 ? 1 : 0}]
    set _total [expr {$_core_out + $_off + $_no_rows + $_row_out + $_inst_out + $_macro_unpl + $_macro_off + $_pin_unpl + $_pin_off_edge}]
    set R check_floorplan_rules.rpt
    oss_check_line $R "Floorplan rule violations : $_total"
    oss_check_line $R "  Core area outside die : $_core_out"
    oss_check_line $R "  Die/core edges off manufacturing grid : $_off"
    oss_check_line $R "  No placement rows : $_no_rows"
    oss_check_line $R "  Rows outside core : $_row_out  (of [llength $_rows])"
    oss_check_line $R "  Placed instances outside core : $_inst_out"
    oss_check_line $R "  Hard macros unplaced : $_macro_unpl"
    oss_check_line $R "  Hard macros off manufacturing grid : $_macro_off"
    oss_check_line $R "  Signal IO pins unplaced : $_pin_unpl"
    oss_check_line $R "  IO pins not on the die boundary : $_pin_off_edge"
}

# Routing channel between hard macros: the smallest gap (um) between two placed
# macros that face each other (their x or y extents overlap). Overlapping
# macros are the macro_spacing check's (checklist_metrics.rpt).
proc oss_fpchk_channels {} {
    set _blk [ord::get_db_block]
    set _dbu [[ord::get_db_tech] getDbUnitsPerMicron]
    set _boxes {}
    foreach _i [$_blk getInsts] {
        if {![[$_i getMaster] isBlock] || [$_i getPlacementStatus] in {NONE UNPLACED}} continue
        set _b [$_i getBBox]
        lappend _boxes [list [$_b xMin] [$_b yMin] [$_b xMax] [$_b yMax]]
    }
    set _min ""; set _pairs 0
    for {set i 0} {$i < [llength $_boxes]} {incr i} {
        lassign [lindex $_boxes $i] ax0 ay0 ax1 ay1
        for {set j [expr {$i + 1}]} {$j < [llength $_boxes]} {incr j} {
            lassign [lindex $_boxes $j] bx0 by0 bx1 by1
            set _g ""
            if {$ay0 < $by1 && $by0 < $ay1} { set _g [expr {max($bx0 - $ax1, $ax0 - $bx1)}] }
            if {$ax0 < $bx1 && $bx0 < $ax1} {
                set _gy [expr {max($by0 - $ay1, $ay0 - $by1)}]
                if {$_g eq "" || $_gy > $_g} { set _g $_gy }
            }
            if {$_g eq "" || $_g < 0} continue
            incr _pairs
            if {$_min eq "" || $_g < $_min} { set _min $_g }
        }
    }
    oss_check_line report_design.rpt "Hard macros placed : [llength $_boxes]"
    oss_check_line report_design.rpt "Facing macro pairs : $_pairs"
    if {$_min eq ""} {
        oss_check_line report_design.rpt "Min Macro Channel Width : not measurable (no facing hard-macro pairs)"
    } else {
        oss_check_line report_design.rpt "Min Macro Channel Width : [format %.3f [expr {double($_min) / $_dbu}]]"
    }
}

# Power intent lint: the staged UPF parses, every domain has primary supplies
# declared with create_supply_net, the domains and supplies exist in the
# database (POWER/GROUND special nets), every cell supply pin is connected.
proc oss_fpchk_upf {} {
    global oss_upf
    set R report_upf.rpt
    set _upf [lindex [glob -nocomplain "$::UPF_DIR/$::design_name.upf" "$::UPF_DIR/*.upf"] 0]
    if {$_upf eq ""} {
        oss_check_line $R "UPF : none staged in $::UPF_DIR"
        oss_check_line $R "UPF Lint Errors : 1"
        return
    }
    oss_check_line $R "UPF : $_upf"
    if {[catch {oss_upf_parse $_upf} _e]} {
        oss_check_line $R "  parse error: $_e"
        oss_check_line $R "UPF Lint Errors : 1"
        return
    }
    set _blk [ord::get_db_block]
    set _errs {}
    if {![info exists oss_upf(top_domain)]} { lappend _errs "no scope domain (create_power_domain -include_scope)" }
    set _dbdoms {}
    foreach _d [$_blk getPowerDomains] { lappend _dbdoms [$_d getName] }
    foreach _d $oss_upf(domains) {
        if {$_d ni $_dbdoms} { lappend _errs "domain $_d not in the database (read_upf)" }
        foreach _k {power ground} {
            if {![info exists oss_upf($_k,$_d)] || $oss_upf($_k,$_d) eq ""} {
                lappend _errs "domain $_d: no primary $_k net (set_domain_supply_net)"
                continue
            }
            set _n $oss_upf($_k,$_d)
            if {$_n ni $oss_upf(nets)} { lappend _errs "domain $_d: primary $_k $_n not declared (create_supply_net)" }
            set _dbn [$_blk findNet $_n]
            if {$_dbn eq "NULL"} {
                lappend _errs "domain $_d: primary $_k $_n not in the database"
            } elseif {[$_dbn getSigType] ne [string toupper $_k]} {
                lappend _errs "domain $_d: net $_n is [$_dbn getSigType], expected [string toupper $_k]"
            }
        }
    }
    set _open 0
    foreach _it [$_blk getITerms] {
        if {[[$_it getMTerm] getSigType] ni {POWER GROUND}} continue
        if {[$_it getNet] eq "NULL"} { incr _open }
    }
    if {$_open} { lappend _errs "$_open cell supply pin(s) unconnected" }
    oss_check_line $R "Domains : $oss_upf(domains)   supply nets : $oss_upf(nets)"
    foreach _e $_errs { oss_check_line $R "  error: $_e" }
    oss_check_line $R "UPF Lint Errors : [llength $_errs]"
}
