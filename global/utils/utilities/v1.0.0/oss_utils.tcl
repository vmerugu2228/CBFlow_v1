#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow — open-source tool helpers (vendor "opensource")
#
# Sourced by the command files under cmds/<FLOW>/opensource/<tool>/ AFTER the
# standard bootstrap (config.tcl + setup.tcl). Works inside Yosys, OpenROAD
# and OpenSTA (all Tcl 8.6) and under plain tclsh in test mode.
#
# Every lookup reads the resolved config — tech(), project(), the MMMC
# analysis_views / node assignments, and the flow array. Missing keys are
# errors; nothing here carries a default. (Config files stay data-only — the
# procs live here.)
#
# Hierarchy: a design's children are `children` of flow(design_name) in
# project(design_hierarchy). Each child is consumed from the active library
# tag (project(lib_config_tag)) after its release was integrated with
# `library-manager add --category block`: tech(blocks), tech(block,<child>,
# lef|gds|netlist|lib,<lib_set>) — see hier_block_views.
# ═══════════════════════════════════════════════════════════════════════════════

# ── Mandatory config access ──────────────────────────────────────────────────
proc oss_get {arr key} {
    upvar #0 $arr _a
    if {![info exists _a($key)] || $_a($key) eq ""} {
        error "${arr}($key) is not set — required by the opensource flow"
    }
    return $_a($key)
}

proc oss_flow_arr {} { return [string tolower $::FLOW_TYPE] }

# Active track / metal stack, and a metal-stack-scoped tech key.
proc oss_track {} { return [oss_get project track_variant] }
proc oss_stack {} { return [oss_get project metal_stack] }
proc oss_ms {key} { return [oss_get tech "[oss_stack],$key"] }
proc oss_trk {key} { return [oss_get tech "[oss_track],$key"] }

# ── MMMC: corners for a node ────────────────────────────────────────────────
# One OpenROAD/OpenSTA corner per analysis view assigned to the node in
# mmmc_node_scenarios.tcl (single-mode designs: the view IS the corner).
# mmmc_node_scenarios.tcl keys nodes by stage name (place, cts, …); accept
# the node name (place1) too.
proc oss_node_views {node} {
    set _stage [string trimright $node 0123456789]
    set _v [get_node_scenarios $node all]
    if {[llength $_v] == 0} { set _v [get_node_scenarios $_stage all] }
    if {[llength $_v] == 0} {
        error "no MMMC scenarios assigned to node '$_stage' — add it with `cbflow flow mmmc-manager set-node --node $_stage`"
    }
    return $_v
}

proc oss_view_attr {view attr} {
    global analysis_views
    if {![info exists analysis_views($view)]} {
        error "analysis view '$view' is not defined in mmmc_config.tcl"
    }
    if {![dict exists $analysis_views($view) $attr]} {
        error "analysis view '$view' has no '$attr'"
    }
    return [dict get $analysis_views($view) $attr]
}

proc oss_lib_set_files {lib_set} {
    set _k "[oss_track],lib,$lib_set,timing"
    if {![info exists ::tech($_k)] || $::tech($_k) eq ""} {
        error "tech($_k) not set — lib set '$lib_set' is missing from the active library tag"
    }
    return $::tech($_k)
}

# ── Memory macros (library tag category memory) ─────────────────────────────
# A tag without memories has an empty tech(lef,memory); its gds / cdl keys may
# then be absent (tags generated before views were bundled).
proc oss_has_memories {} {
    return [expr {[info exists ::tech(lef,memory)] && [llength $::tech(lef,memory)] > 0}]
}
# tech(<kind>,memory): lef / gds / cdl / verilog files of the memory macros
proc oss_memory_files {kind} {
    if {![oss_has_memories]} { return {} }
    if {![info exists ::tech($kind,memory)] || [llength $::tech($kind,memory)] == 0} {
        error "tech($kind,memory) empty but the library tag has memory LEFs — re-run library-manager add --category memory"
    }
    return $::tech($kind,memory)
}
# Memory macro cell names (MACRO statements of the tag's memory LEFs)
proc oss_memory_cells {} {
    set _out {}
    foreach _l [oss_memory_files lef] {
        set _fh [open $_l]; set _t [read $_fh]; close $_fh
        foreach {_ _m} [regexp -all -inline -line {^\s*MACRO\s+(\S+)} $_t] { lappend _out $_m }
    }
    return [lsort -unique $_out]
}
# Memory timing libs for a standard-cell lib set (tech(memory,lib_set_map))
proc oss_memory_libs {lib_set} {
    if {![oss_has_memories]} { return {} }
    set _map [oss_get tech memory,lib_set_map]
    if {![dict exists $_map $lib_set]} {
        error "tech(memory,lib_set_map) has no entry for lib set '$lib_set'"
    }
    set _c [dict get $_map $lib_set]
    if {![info exists ::tech(lib,$_c,timing,memory)] || [llength $::tech(lib,$_c,timing,memory)] == 0} {
        error "tech(lib,$_c,timing,memory) empty (tech(memory,lib_set_map): $lib_set -> $_c)"
    }
    return $::tech(lib,$_c,timing,memory)
}
# Memory macro instances of the loaded design (hard blocks that are not
# hierarchy children)
proc oss_memory_insts {blocks} {
    set _child {}
    foreach _b $blocks { lappend _child {*}[oss_block_insts $_b] }
    set _out {}
    foreach _i [[ord::get_db_block] getInsts] {
        if {[[$_i getMaster] isBlock] && [$_i getName] ni $_child} { lappend _out [$_i getName] }
    }
    return $_out
}

# Lib sets used by a node (unique, in view order).
proc oss_node_lib_sets {node} {
    set _out {}
    foreach _v [oss_node_views $node] {
        set _ls [oss_view_attr $_v lib_set_ref]
        if {[lsearch -exact $_out $_ls] < 0} { lappend _out $_ls }
    }
    return $_out
}

# ── Physical views (OpenROAD) ───────────────────────────────────────────────
proc oss_read_lefs {{blocks {}}} {
    read_lef [oss_ms "[oss_track],lef_tech"]
    foreach _l [oss_trk lef] { read_lef $_l }
    foreach _l [oss_memory_files lef] { read_lef $_l }
    foreach _b $blocks { read_lef [dict get [hier_block_views $_b] lef] }
}

# define_corners + read_liberty for every view of the node; child timing
# models are read per corner from the child's lib for that view's lib set.
proc oss_read_corners {node {blocks {}}} {
    set _views [oss_node_views $node]
    define_corners {*}$_views
    foreach _v $_views {
        set _ls [oss_view_attr $_v lib_set_ref]
        foreach _lib [oss_lib_set_files $_ls] { read_liberty -corner $_v $_lib }
        foreach _lib [oss_memory_libs $_ls] { read_liberty -corner $_v $_lib }
        foreach _b $blocks {
            read_liberty -corner $_v [hier_block_lib [hier_block_views $_b] $_b $_ls]
        }
    }
    return $_views
}

# Placement-stage wire RC from the metal stack's representative layers.
proc oss_set_wire_rc {} {
    set_wire_rc -signal -layer [oss_ms wire_rc_signal_layer]
    set_wire_rc -clock  -layer [oss_ms wire_rc_clock_layer]
}

proc oss_make_tracks {} {
    set _f [oss_ms tracks_file]
    set _fh [open $_f]
    set _trk [dict create]
    foreach _line [split [read $_fh] "\n"] {
        if {[llength $_line] == 4} {
            dict set _trk [lindex $_line 0] [lindex $_line 1] [lrange $_line 2 3]
        }
    }
    close $_fh
    foreach _l [oss_ms metal_layers] {
        if {![dict exists $_trk $_l X] || ![dict exists $_trk $_l Y]} {
            error "tracks file $_f has no X/Y entry for layer $_l"
        }
        lassign [dict get $_trk $_l X] _xo _xp
        lassign [dict get $_trk $_l Y] _yo _yp
        make_tracks $_l -x_offset $_xo -x_pitch $_xp -y_offset $_yo -y_pitch $_yp
    }
}

# Power grid by hierarchy position (design_hierarchy parent/children).
# Rails: met1 follow-pins of the design's primary supplies (UPF scope domain).
#   leaf with a parent (DL3)  vertical straps (primary nets), extended to the
#                             die edge                          pins: vertical
#   middle (DL2)              vertical straps (primary) + horizontal straps
#                             cycling project(power,rail_nets) edge to edge;
#                             via-only macro grid on each DL3 child's pins
#                                                               pins: horizontal
#   top (DL1)                 same horizontal cycle; DL2 children are reached
#                             by oss_bridge_rails (straps over their same-net
#                             pins, ring ties for the switched rails)
#                                                               pins: horizontal
#   standalone                vertical + horizontal straps      pins: horizontal
# A child's switched rail reaches it as a secondary power net of the core
# domain. The horizontal cycle is identical in every block, so DL2 macros
# placed on the cycle pitch (oss_rail_pitch) line up with the DL1 straps.
proc oss_rail_pitch {} {
    lassign [oss_ms pdn_strap_h] _l _w _pitch _off
    return [expr {($_pitch / 2.0) * [llength [oss_get project power,rail_nets]]}]
}

proc oss_pdn {design blocks} {
    global oss_upf
    set _parent [dict get [dict get [oss_get project design_hierarchy] $design] parent]
    set _td  $oss_upf(top_domain)
    set _vdd $oss_upf(power,$_td)
    set _vss $oss_upf(ground,$_td)
    set _rail [oss_ms pdn_rail_layer]
    lassign [oss_ms pdn_strap_v] _lv _wv _pv _ov
    lassign [oss_ms pdn_strap_h] _lh _wh _ph _oh
    set _leaf   [expr {[llength $blocks] == 0}]
    set _pos [expr {$_parent ne "" ? ($_leaf ? "leaf" : "middle") : ($_leaf ? "standalone" : "top")}]
    # A leaf with memory macros: their power pins sit on the vertical-strap
    # layer inside the macro, so the leaf draws its own horizontal straps
    # (primary supplies) over them and exports those to the parent instead.
    set _mems [oss_memory_insts $blocks]
    if {$_pos eq "leaf" && [llength $_mems] > 0} { set _pos leaf_mem }

    set _hnets [list $_vdd $_vss]
    set _hpitch $_ph
    set _created {}
    if {$_pos in {middle top}} {
        set _hnets [oss_get project power,rail_nets]
        set _hpitch [oss_rail_pitch]
        foreach _n $_hnets {
            if {[[ord::get_db_block] findNet $_n] eq "NULL"} {
                set _net [odb::dbNet_create [ord::get_db_block] $_n]
                $_net setSpecial
                $_net setSigType [expr {$_n eq $_vss ? "GROUND" : "POWER"}]
                lappend _created $_n
                handle_info "PDN: feedthrough rail $_n created"
            }
        }
    }
    set _secondary [lsearch -all -inline -not -regexp $_hnets "^($_vdd|$_vss)\$"]
    if {[llength $_secondary] > 0} {
        set_voltage_domain -power $_vdd -ground $_vss -secondary_power $_secondary
    } else {
        set_voltage_domain -power $_vdd -ground $_vss
    }

    set _pins [dict get {leaf {v} leaf_mem {h} middle {h} top {h} standalone {h}} $_pos]
    set _pins [string map [list v $_lv h $_lh] $_pins]
    if {$_pins ne ""} {
        define_pdn_grid -name stdcell -pins $_pins
    } else {
        define_pdn_grid -name stdcell
    }
    add_pdn_stripe -layer $_rail -width [oss_ms pdn_rail_width] -followpins -nets [list $_vdd $_vss]
    set _vext [expr {$_pos eq "leaf" ? "-extend_to_boundary" : ""}]
    add_pdn_stripe -layer $_lv -width $_wv -pitch $_pv -offset $_ov -nets [list $_vdd $_vss] {*}$_vext
    add_pdn_connect -layers [list $_rail $_lv]
    if {$_pos ne "leaf"} {
        set _hext [expr {$_pos in {middle leaf_mem} ? "-extend_to_boundary" : ""}]
        add_pdn_stripe -layer $_lh -width $_wh -pitch $_hpitch -offset $_oh -nets $_hnets {*}$_hext
        add_pdn_connect -layers [list $_lv $_lh]
    }
    # Leaf children (vertical pins): via-only macro grid onto their pins.
    # Children with horizontal pins (DL2): rail bridge after pdngen.
    set _bridge {}
    set _halo [oss_get [oss_flow_arr] oss,macro,halo]
    foreach _b $blocks {
        if {[llength [hier_children $_b]] > 0} { lappend _bridge {*}[oss_block_insts $_b]; continue }
        foreach _inst [oss_block_insts $_b] {
            define_pdn_grid -macro -instances $_inst -name "macro_$_inst" -halo [list $_halo $_halo $_halo $_halo]
            add_pdn_connect -grid "macro_$_inst" -layers [list $_lv $_lh]
        }
    }
    # Memory macros: via-only grid from the horizontal straps onto their pins
    foreach _inst $_mems {
        define_pdn_grid -macro -instances $_inst -name "mem_$_inst" -halo [list $_halo $_halo $_halo $_halo]
        add_pdn_connect -grid "mem_$_inst" -layers [list $_lv $_lh]
    }
    if {[llength $_mems] > 0} { handle_info "PDN: [llength $_mems] memory macro(s) hooked from $_lh" }
    pdngen
    # A feedthrough rail nothing in this block connects to gets no shapes from
    # pdngen; drop it (and its shapeless terminal) instead of exporting an
    # unplaced pin. The parent's rail bridge routes around this block.
    foreach _n $_created {
        set _net [[ord::get_db_block] findNet $_n]
        if {$_net eq "NULL" || [llength [$_net getSWires]] > 0} continue
        foreach _bt [$_net getBTerms] { odb::dbBTerm_destroy $_bt }
        odb::dbNet_destroy $_net
        set _hnets [lsearch -all -inline -not -exact $_hnets $_n]
        handle_info "PDN: feedthrough rail $_n has no shapes in this block — removed"
    }
    if {[llength $_bridge] > 0} { oss_bridge_rails [list $_vdd $_vss] $_bridge }
    return [list position $_pos pins $_pins rails $_hnets]
}

# Rail bridge (top / middle blocks whose children export horizontal-strap
# pins, i.e. DL2 macros): pdngen keeps its straps a spacing away from every
# macro and prunes rails no standard cell uses. Draw the full rail cycle on
# the horizontal-strap layer edge to edge instead: every slot k carries
# rail_nets[k mod n] at y = core_y0 + offset + k * (pitch/2). Over a DL2 macro
# placed on oss_rail_pitch the strap lands exactly on the macro's same-net
# pin; where the macro has no pin of that net at that y (rails pruned inside
# it) the strap is cut around the macro instead. pdngen's own straps are
# overlapped by identical same-net shapes. Each strap that reaches the die
# edge gets a pin there (the block's supply ports / the chip's supplies).
proc oss_bridge_rails {primary macros} {
    set _blk [ord::get_db_block]
    set _tech [ord::get_db_tech]
    set _dbu [$_tech getDbUnitsPerMicron]
    lassign [oss_ms pdn_strap_h] _ln _w _pitch _off
    set _layer [$_tech findLayer $_ln]
    set _nets [oss_get project power,rail_nets]
    set _n [llength $_nets]
    set _step [expr {round($_pitch / 2.0 * $_dbu)}]
    set _hw [expr {round($_w * $_dbu / 2.0)}]
    set _core [$_blk getCoreArea]
    set _die  [$_blk getDieArea]
    set _x0 [$_die xMin]; set _x1 [$_die xMax]
    set _pinlen [expr {round(2.0 * $_dbu)}]
    set _gap [expr {round(2.0 * $_dbu)}]

    # Same-layer power pins of each DL2 macro: pin(<inst>,<net>,<y>) = 1
    set _boxes {}
    foreach _inst $macros {
        set _i [$_blk findInst $_inst]
        if {[$_i getOrient] ne "R0"} { error "rail bridge supports R0 macros only ($_inst is [$_i getOrient])" }
        lassign [$_i getLocation] _ix _iy
        set _bb [$_i getBBox]
        lappend _boxes [list $_inst [$_bb xMin] [$_bb yMin] [$_bb xMax] [$_bb yMax]]
        foreach _it [$_i getITerms] {
            set _nt [$_it getNet]
            if {$_nt eq "NULL" || [$_nt getSigType] ni {POWER GROUND}} continue
            foreach _mp [[$_it getMTerm] getMPins] {
                foreach _g [$_mp getGeometry] {
                    if {[$_g getTechLayer] ne $_layer} continue
                    set _pin($_inst,[$_nt getName],[expr {$_iy + ([$_g yMin] + [$_g yMax]) / 2}]) 1
                }
            }
        }
    }

    set _k 0
    set _cnt 0
    for {set _y [expr {[$_core yMin] + round($_off * $_dbu)}]} {$_y + $_hw <= [$_core yMax]} {incr _y $_step} {
        set _netname [lindex $_nets [expr {$_k % $_n}]]
        incr _k
        set _net [$_blk findNet $_netname]
        if {$_net eq "NULL"} continue
        # Segments of [die x0, die x1] minus the macros this strap may not cross.
        set _segs [list [list $_x0 $_x1]]
        foreach _b $_boxes {
            lassign $_b _inst _bx0 _by0 _bx1 _by1
            if {$_y + $_hw <= $_by0 || $_y - $_hw >= $_by1} continue
            if {[info exists _pin($_inst,$_netname,$_y)]} continue
            set _new {}
            foreach _sg $_segs {
                lassign $_sg _a _b2
                if {$_b2 <= $_bx0 - $_gap || $_a >= $_bx1 + $_gap} { lappend _new $_sg; continue }
                if {$_a < $_bx0 - $_gap} { lappend _new [list $_a [expr {$_bx0 - $_gap}]] }
                if {$_b2 > $_bx1 + $_gap} { lappend _new [list [expr {$_bx1 + $_gap}] $_b2] }
            }
            set _segs $_new
        }
        set _sw [odb::dbSWire_create $_net "ROUTED"]
        foreach _sg $_segs {
            odb::dbSBox_create $_sw $_layer [lindex $_sg 0] [expr {$_y - $_hw}] [lindex $_sg 1] [expr {$_y + $_hw}] "STRIPE"
        }
        set _bt [$_blk findBTerm $_netname]
        if {$_bt eq "NULL"} {
            set _bt [odb::dbBTerm_create $_net $_netname]
            $_bt setSigType [$_net getSigType]
            $_bt setIoType INOUT
            $_bt setSpecial
        }
        foreach _sg $_segs {
            lassign $_sg _a _b2
            if {$_a == $_x0} {
                set _bp [odb::dbBPin_create $_bt]; $_bp setPlacementStatus FIRM
                odb::dbBox_create $_bp $_layer $_x0 [expr {$_y - $_hw}] [expr {$_x0 + $_pinlen}] [expr {$_y + $_hw}]
            }
            if {$_b2 == $_x1} {
                set _bp [odb::dbBPin_create $_bt]; $_bp setPlacementStatus FIRM
                odb::dbBox_create $_bp $_layer [expr {$_x1 - $_pinlen}] [expr {$_y - $_hw}] $_x1 [expr {$_y + $_hw}]
            }
        }
        lappend _ys($_netname) $_y
        incr _cnt
    }
    handle_info "PDN: rail bridge — $_cnt full-width $_ln straps cycling {$_nets}"

    # Rails pdngen does not mesh (the switched ones, which no standard cell of
    # this block uses) get tied together like a ring: one vertical strap per
    # rail in the left and right die margins, with a via onto each of that
    # rail's own horizontal straps only.
    lassign [oss_ms pdn_strap_v] _lvn _wv
    set _lv [$_tech findLayer $_lvn]
    set _via ""
    foreach _v [$_tech getVias] {
        if {[$_v getBottomLayer] eq $_lv && [$_v getTopLayer] eq $_layer} { set _via $_v; break }
    }
    if {$_via eq ""} { error "no $_lvn -> $_ln via in the tech LEF" }
    set _hv [expr {round($_wv * $_dbu / 2.0)}]
    set _pitchv [expr {round(($_wv + 1.4) * $_dbu)}]
    set _i 0
    foreach _netname $_nets {
        if {$_netname in $primary || ![info exists _ys($_netname)]} continue
        set _net [$_blk findNet $_netname]
        set _ylo [expr {[lindex $_ys($_netname) 0] - $_hw}]
        set _yhi [expr {[lindex $_ys($_netname) end] + $_hw}]
        set _off [expr {round(1.0 * $_dbu) + $_hv + $_i * $_pitchv}]
        incr _i
        foreach _xc [list [expr {$_x0 + $_off}] [expr {$_x1 - $_off}]] {
            if {($_xc + $_hv > [$_core xMin] && $_xc - $_hv < [$_core xMax])} {
                error "die margin too small for the rail ties ($_netname) — increase oss,fp,core_margin"
            }
            set _sw [odb::dbSWire_create $_net "ROUTED"]
            odb::dbSBox_create $_sw $_lv [expr {$_xc - $_hv}] $_ylo [expr {$_xc + $_hv}] $_yhi "RING"
            foreach _y $_ys($_netname) { odb::dbSBox_create $_sw $_via $_xc $_y "RING" }
        }
    }
    if {$_i > 0} { handle_info "PDN: rail ties on $_lvn for $_i switched rail(s)" }
}

# Instance names of a child block's master in the linked design.
proc oss_block_insts {block} {
    set _out {}
    foreach _i [[ord::get_db_block] getInsts] {
        if {[[$_i getMaster] getName] eq $block} { lappend _out [$_i getName] }
    }
    if {[llength $_out] == 0} { error "child block '$block' has no instance in [oss_get flow design_name]" }
    return $_out
}

# project(pdn,enable): false builds no power grid (supply nets stay logical
# only) — for bring-up of signal routing; power checks are skipped.
proc oss_pdn_enabled {} {
    return [is_true [oss_get project pdn,enable]]
}

# Vt flavours: project(vt_flavors) must be a subset of the tech's
# tech(vt_variants_available); cells of the other Vts become dont_use.
proc oss_vt_dont_use {} {
    set _avail [oss_get tech vt_variants_available]
    set _use   [oss_get project vt_flavors]
    foreach _v $_use {
        if {$_v ni $_avail} { error "project(vt_flavors): '$_v' not in tech(vt_variants_available) {$_avail}" }
    }
    set _out {}
    foreach _v $_avail {
        if {$_v ni $_use} { lappend _out [oss_get tech vt_pattern,$_v] }
    }
    return $_out
}

# pv(oss,pv,mode): flat = full layout / whole-hierarchy LVS; hier = child
# blocks as abstracts (emptied for DRC, black boxes for LVS)
proc pv_mode {} {
    set _m [oss_get pv oss,pv,mode]
    if {$_m ni {flat hier}} { error "pv(oss,pv,mode) must be flat or hier, got '$_m'" }
    return $_m
}

# PNR dont_use: tech(<track>,dont_use_pnr) + cells of Vts outside
# project(vt_flavors).
proc oss_pnr_dont_use {} {
    return [concat [oss_trk dont_use_pnr] [oss_vt_dont_use]]
}

# Per-net check that every supply is one connected network.
proc oss_check_power {} {
    global oss_upf
    if {![oss_pdn_enabled]} { handle_info "PDN off (project(pdn,enable)) — power grid check skipped"; return }
    set _bad {}
    foreach _n [lsort -unique [concat $oss_upf(nets) [oss_get project power,rail_nets]]] {
        set _net [[ord::get_db_block] findNet $_n]
        if {$_net eq "NULL"} continue
        if {[llength [$_net getITerms]] == 0} { continue }    ;# feedthrough rail
        if {[catch {check_power_grid -net $_n} _e]} { lappend _bad $_n }
    }
    if {[llength $_bad] > 0} {
        set _msg "power grid not connected for: $_bad (see the PSM warnings above)"
        if {[is_true [oss_get [oss_flow_arr] oss,fail_on_violations]]} { error $_msg }
        handle_warning "$_msg — reported, flow continues"
        return
    }
    handle_info "Power grid connectivity OK"
}

# Routing layer range: a block with a parent leaves the parent the layer(s)
# its power pins don't use — leaf blocks route up to the vertical-strap
# layer, middle blocks stop below the horizontal straps.
proc oss_signal_layers {design blocks} {
    set _parent [dict get [dict get [oss_get project design_hierarchy] $design] parent]
    set _min [oss_get tech min_routing_layer]
    if {$_parent eq ""} { return [list $_min [oss_get tech max_routing_layer]] }
    lassign [oss_ms pdn_strap_v] _lv
    if {[llength $blocks] == 0} { return [list $_min $_lv] }
    lassign [oss_ms pdn_strap_h] _lh
    set _layers [oss_ms metal_layers]
    return [list $_min [lindex $_layers [expr {[lsearch -exact $_layers $_lh] - 1}]]]
}

# The design's SDC: staged by the flow's sdc1 input stage (PNR/STA take it
# from the SYNTH release: <design>.sdc; source RTL flows: <design>.<mode>.sdc).
proc oss_sdc_file {} {
    set _d [oss_get flow design_name]
    set _f [lindex [glob -nocomplain "$::SDC_DIR/${_d}.sdc" "$::SDC_DIR/${_d}.*.sdc" "$::SDC_DIR/*.sdc"] 0]
    if {$_f eq ""} { error "no SDC staged in $::SDC_DIR (<flow>(input,sdc_func_file) / release_tag)" }
    return $_f
}

# Reload a stage's starting point: previous database + timing views + SDC.
# Design-rule limits from overrides: <flow>(oss,drv,max_fanout), when set
# (the run's setup/override_config.tcl), becomes a design max-fanout
# constraint — repair_design buffers to it and the stage metrics count
# against it. Unset = no fanout constraint (the SDC / library limits only).
proc oss_drv_limits {} {
    set _k "[oss_flow_arr](oss,drv,max_fanout)"
    if {[info exists ::$_k] && [set ::$_k] ne ""} {
        set_max_fanout [set ::$_k] [current_design]
        handle_info "max fanout [set ::$_k] ($_k)"
    }
}

proc oss_load_stage {prev_node} {
    global design_name blocks
    set_thread_count [oss_get [oss_flow_arr] oss,threads]
    # Liberty BEFORE the database: OpenSTA binds liberty cells to the LEF
    # masters when the block is loaded (CTS/repair need the physical masters).
    oss_read_corners $::NODE_NAME $blocks
    read_db [oss_prev_odb $prev_node]
    read_sdc [oss_sdc_file]
    oss_drv_limits
    set_dont_use [oss_pnr_dont_use]
    oss_set_wire_rc
}

# ── Floorplan steps (FP flow; PNR init_design when no FP DEF is given) ───────
# Knobs come from the running flow's array (fp(oss,…) / pnr(oss,…)).
proc oss_fp_opt {key} {
    upvar #0 [oss_flow_arr] _a
    return [expr {[info exists _a($key)] ? $_a($key) : ""}]
}

# Netlist + SDC: the synthesized netlist linked against LEF / liberty views.
proc oss_fp_load_netlist {design blocks} {
    set_thread_count [oss_get [oss_flow_arr] oss,threads]
    oss_read_lefs $blocks
    oss_read_corners $::NODE_NAME $blocks
    read_verilog [lindex [glob -nocomplain "$::NETLIST_DIR/${design}.v" "$::NETLIST_DIR/*.v"] 0]
    link_design $design
    read_sdc [oss_sdc_file]
    set_dont_use [oss_pnr_dont_use]
}

# Die / core (oss,fp,die_area wins over utilization sizing), rows, tracks.
# Utilization sizing: oss,fp,core_utilization is the STANDARD-CELL
# utilization. Without hard macros OpenROAD sizes the core directly; with
# hard macros the core is macro area (incl. halo) + std-cell area / util,
# wide enough for the macros side by side (sum of widths + halos) and as tall
# as the tallest — so a parent block is not inflated by its children's area
# and its children fit in one row from the core corner.
proc oss_fp_floorplan {} {
    set _arr  [oss_flow_arr]
    set _site [oss_trk site]
    set _m    [oss_get $_arr oss,fp,core_margin]
    set _die  [oss_fp_opt oss,fp,die_area]
    if {$_die ne ""} {
        lassign $_die _x0 _y0 _x1 _y1
        initialize_floorplan -site $_site -die_area $_die \
            -core_area [list [expr {$_x0 + $_m}] [expr {$_y0 + $_m}] [expr {$_x1 - $_m}] [expr {$_y1 - $_m}]]
        oss_make_tracks
        return
    }
    set _util [oss_get $_arr oss,fp,core_utilization]
    set _ar   [oss_get $_arr oss,fp,aspect_ratio]
    set _halo [oss_get $_arr oss,macro,halo]
    set _chan [oss_get $_arr oss,fp,macro_channel]
    set _dbu  [[ord::get_db_tech] getDbUnitsPerMicron]
    set _std 0.0; set _mac 0.0; set _mw 0.0; set _mh 0.0; set _sumw 0.0
    foreach _i [[ord::get_db_block] getInsts] {
        set _ms [$_i getMaster]
        set _w [expr {[$_ms getWidth] / double($_dbu)}]
        set _h [expr {[$_ms getHeight] / double($_dbu)}]
        if {[$_ms isBlock]} {
            set _mac [expr {$_mac + ($_w + 2*$_halo) * ($_h + 2*$_halo)}]
            set _mw [expr {max($_mw, $_w + 2*$_halo)}]
            set _sumw [expr {$_sumw + $_w + 2*$_halo}]
            set _mh [expr {max($_mh, $_h + 2*$_halo)}]
        } else {
            set _std [expr {$_std + $_w * $_h}]
        }
    }
    if {$_mac == 0.0} {
        initialize_floorplan -site $_site -utilization $_util \
            -aspect_ratio $_ar -core_space $_m
    } else {
        # macro_channel: std-cell / routing band kept around and between macros
        set _nmac [llength [lsearch -all -inline [lmap _i [[ord::get_db_block] getInsts] {expr {[[$_i getMaster] isBlock]}}] 1]]
        set _area [expr {$_mac + $_std / ($_util / 100.0)}]
        set _cw [expr {max($_area / sqrt($_area * $_ar), $_sumw + ($_nmac + 1) * $_chan)}]
        set _ch [expr {max($_area / $_cw, $_mh + 2 * $_chan)}]
        handle_info [format "Floorplan: std-cell %.0f um^2 @ %s%% + macros %.0f um^2 -> core %.1f x %.1f um" \
                         $_std $_util $_mac $_cw $_ch]
        initialize_floorplan -site $_site \
            -die_area  [list 0 0 [expr {$_cw + 2*$_m}] [expr {$_ch + 2*$_m}]] \
            -core_area [list $_m $_m [expr {$_cw + $_m}] [expr {$_ch + $_m}]]
    }
    oss_make_tracks
}

# Child hard blocks: explicit oss,macro,placement {inst x y orient ...} or
# rtl_macro_placer; DL2 children snapped to the rail pitch. Report:
# oss_fp_macro_report.
proc oss_fp_place_macros {blocks} {
    # every hard macro: child blocks and memory macros
    if {[llength $blocks] == 0 && [llength [oss_memory_insts $blocks]] == 0} return
    set _halo [oss_get [oss_flow_arr] oss,macro,halo]
    set _pl   [oss_fp_opt oss,macro,placement]
    if {$_pl eq "row"} {
        # One row from the core corner, macro_channel apart (see oss_fp_floorplan)
        set _chan [oss_get [oss_flow_arr] oss,fp,macro_channel]
        set _dbu  [[ord::get_db_tech] getDbUnitsPerMicron]
        set _core [[ord::get_db_block] getCoreArea]
        set _x [expr {[$_core xMin] / double($_dbu) + $_chan}]
        set _y [expr {[$_core yMin] / double($_dbu) + $_chan}]
        foreach _i [[ord::get_db_block] getInsts] {
            if {![[$_i getMaster] isBlock]} continue
            place_macro -macro_name [$_i getName] -location [list $_x $_y] -orientation R0
            set _x [expr {$_x + [[$_i getMaster] getWidth] / double($_dbu) + $_chan}]
        }
    } elseif {$_pl ne ""} {
        foreach {_inst _x _y _o} $_pl {
            place_macro -macro_name $_inst -location [list $_x $_y] -orientation $_o
        }
    } else {
        # min channel between macros = the halo (the -halo_width/-halo_height
        # flags are deprecated: MPL-0074)
        rtl_macro_placer -min_channel_size $_halo
    }
    # Children that export horizontal-strap pins (DL2) must sit on the rail
    # cycle pitch so their straps abut ours with the same net order.
    set _pitch [oss_rail_pitch]
    set _dbu [[ord::get_db_tech] getDbUnitsPerMicron]
    foreach _b $blocks {
        if {[llength [hier_children $_b]] == 0} continue
        foreach _inst [oss_block_insts $_b] {
            set _i [[ord::get_db_block] findInst $_inst]
            set _x [expr {[lindex [$_i getLocation] 0] / double($_dbu)}]
            set _y [expr {[lindex [$_i getLocation] 1] / double($_dbu)}]
            set _ys [expr {round($_y / $_pitch) * $_pitch}]
            if {abs($_ys - $_y) > 1e-6} {
                handle_info "  $_inst y $_y -> $_ys (rail pitch $_pitch)"
                place_macro -macro_name $_inst -location [list $_x $_ys] -orientation [$_i getOrient]
            }
        }
    }
}

# <flow>(oss,macro,blockage_sides) {left right bottom}: hard placement
# blockages from each child macro out to the core edge on those sides (side
# strips run from the core bottom to the macro top + halo), so standard cells
# sit only where the floorplan leaves room — e.g. above a macro in the bottom
# corner. Runs after tapcell: each region is clipped to the rows that remain,
# leaving the endcap sites at every row end outside it (detailed placement
# rejects fixed cells under a blockage). Written to the DEF (BLOCKAGES).
proc oss_fp_macro_blockages {} {
    set _arr [oss_flow_arr]
    if {![info exists ::${_arr}(oss,macro,blockage_sides)]} { error "${_arr}(oss,macro,blockage_sides) is not set" }
    set _sides [set ::${_arr}(oss,macro,blockage_sides)]
    if {[llength $_sides] == 0} return
    foreach _s $_sides {
        if {$_s ni {left right bottom top}} { error "${_arr}(oss,macro,blockage_sides): unknown side '$_s' (left right bottom top)" }
    }
    set _blk  [ord::get_db_block]
    set _dbu  [[ord::get_db_tech] getDbUnitsPerMicron]
    set _halo [expr {round([oss_get $_arr oss,macro,halo] * $_dbu)}]
    set _c    [$_blk getCoreArea]
    lassign [list [$_c xMin] [$_c yMin] [$_c xMax] [$_c yMax]] _cx0 _cy0 _cx1 _cy1
    set _ecm  [[ord::get_db] findMaster [oss_trk endcap]]
    if {$_ecm eq "NULL"} { error "endcap master [oss_trk endcap] not in the LEFs" }
    set _ecw  [$_ecm getWidth]
    foreach _i [$_blk getInsts] {
        if {![[$_i getMaster] isBlock]} continue
        set _b [$_i getBBox]
        lassign [list [$_b xMin] [$_b yMin] [$_b xMax] [$_b yMax]] _x0 _y0 _x1 _y1
        set _rects {}
        foreach _s $_sides {
            switch $_s {
                left   { lappend _rects $_s $_cx0 $_cy0 $_x0 [expr {$_y1 + $_halo}] }
                right  { lappend _rects $_s $_x1 $_cy0 $_cx1 [expr {$_y1 + $_halo}] }
                bottom { lappend _rects $_s $_x0 $_cy0 $_x1 $_y0 }
                top    { lappend _rects $_s $_x0 $_y1 $_x1 $_cy1 }
            }
        }
        foreach {_s _a _bb _cc _d} $_rects {
            set _a [expr {max($_a, $_cx0)}]; set _bb [expr {max($_bb, $_cy0)}]
            set _cc [expr {min($_cc, $_cx1)}]; set _d [expr {min($_d, $_cy1)}]
            # rows inside the region, minus their endcap sites; rows with the
            # same x span merge into one blockage
            set _spans [dict create]
            foreach _r [$_blk getRows] {
                set _rb [$_r getBBox]
                if {[$_rb yMax] <= $_bb || [$_rb yMin] >= $_d} continue
                set _sx0 [expr {max($_a, [$_rb xMin] + $_ecw)}]
                set _sx1 [expr {min($_cc, [$_rb xMax] - $_ecw)}]
                if {$_sx1 <= $_sx0} continue
                set _k "$_sx0 $_sx1"
                if {[dict exists $_spans $_k]} {
                    lassign [dict get $_spans $_k] _ya _yb
                    dict set _spans $_k [list [expr {min($_ya, [$_rb yMin])}] [expr {max($_yb, [$_rb yMax])}]]
                } else {
                    dict set _spans $_k [list [$_rb yMin] [$_rb yMax]]
                }
            }
            if {[dict size $_spans] == 0} {
                handle_info "  [$_i getName] $_s: no rows between macro and core edge — no blockage"
                continue
            }
            dict for {_k _y} $_spans {
                lassign $_k _sx0 _sx1
                lassign $_y _sy0 _sy1
                odb::dbBlockage_create $_blk $_sx0 $_sy0 $_sx1 $_sy1
                handle_info [format "  placement blockage [$_i getName] %-6s (%.2f %.2f %.2f %.2f)" $_s \
                    [expr {$_sx0 / double($_dbu)}] [expr {$_sy0 / double($_dbu)}] [expr {$_sx1 / double($_dbu)}] [expr {$_sy1 / double($_dbu)}]]
            }
        }
    }
}

# place_macros.rpt: every child hard-block instance with its origin,
# orientation and bounding box (nothing to report without child blocks).
proc oss_fp_macro_report {blocks} {
    set _rows {}
    foreach _b $blocks { foreach _inst [oss_block_insts $_b] { lappend _rows $_inst $_b } }
    foreach _inst [oss_memory_insts $blocks] {
        lappend _rows $_inst [[[[ord::get_db_block] findInst $_inst] getMaster] getName]
    }
    if {[llength $_rows] == 0} return
    set _dbu [[ord::get_db_tech] getDbUnitsPerMicron]
    set _fh [open "$::REPORTS_DIR/place_macros.rpt" w]
    foreach {_inst _b} $_rows {
        set _i [[ord::get_db_block] findInst $_inst]
        set _bb [$_i getBBox]
        puts $_fh [format "%-20s %-14s origin (%.3f, %.3f) %s  bbox (%.3f %.3f %.3f %.3f)" $_inst $_b \
            [expr {[lindex [$_i getLocation] 0] / double($_dbu)}] [expr {[lindex [$_i getLocation] 1] / double($_dbu)}] \
            [$_i getOrient] [expr {[$_bb xMin] / double($_dbu)}] [expr {[$_bb yMin] / double($_dbu)}] \
            [expr {[$_bb xMax] / double($_dbu)}] [expr {[$_bb yMax] / double($_dbu)}]]
    }
    close $_fh
}

# IO pins + well taps / endcaps. Report: oss_fp_io_report.
proc oss_fp_pins_taps {} {
    set _arr [oss_flow_arr]
    # <flow>(oss,pins,constraints): per-group port placement — a list of
    # {region pin_glob ...} (region as set_io_pin_constraint: top:*,
    # left:100-400 …); each group's pins stay together (-group) in its region.
    # A glob matching no signal pin is an error.
    # <flow>(oss,pins,region): region for every signal pin no group took
    # (e.g. top:* — a macro's pins facing its parent's logic); "" = all edges
    if {![info exists ::${_arr}(oss,pins,region)]} { error "${_arr}(oss,pins,region) is not set" }
    set _rg [set ::${_arr}(oss,pins,region)]
    set _sig {}
    foreach _bt [[ord::get_db_block] getBTerms] {
        if {[$_bt getSigType] ni {POWER GROUND}} { lappend _sig [$_bt getName] }
    }
    set _taken {}
    foreach _grp [oss_fp_opt oss,pins,constraints] {
        set _reg [lindex $_grp 0]
        set _names {}
        foreach _g [lrange $_grp 1 end] {
            set _m [lsearch -all -inline -glob $_sig $_g]
            if {![llength $_m]} { error "${_arr}(oss,pins,constraints): '$_g' matches no signal pin" }
            foreach _n $_m { if {$_n ni $_taken && $_n ni $_names} { lappend _names $_n } }
        }
        if {![llength $_names]} continue
        set_io_pin_constraint -pin_names $_names -region $_reg -group
        lappend _taken {*}$_names
        handle_info "IO pins: [llength $_names] pins grouped on $_reg ([join [lrange $_grp 1 end] { }])"
    }
    set _rest [lmap _n $_sig { expr {$_n in $_taken ? [continue] : $_n} }]
    if {$_rg ne "" && [llength $_rest]} {
        set_io_pin_constraint -pin_names $_rest -region $_rg
        handle_info "IO pins: [llength $_rest] signal pins on $_rg"
    }
    place_pins -hor_layers [oss_get $_arr oss,pins,hor_layer] \
               -ver_layers [oss_get $_arr oss,pins,ver_layer]
    set _halo [oss_get $_arr oss,macro,halo]
    tapcell -distance [oss_trk well_tap_distance] \
            -tapcell_master [oss_trk well_tap] -endcap_master [oss_trk endcap] \
            -halo_width_x $_halo -halo_width_y $_halo
    oss_fp_macro_blockages           ;# after tapcell: clipped to the remaining rows
}

# io_placement.rpt: every placed IO pin with its direction, layer, location.
proc oss_fp_io_report {} {
    set _dbu [[ord::get_db_tech] getDbUnitsPerMicron]
    set _fh [open "$::REPORTS_DIR/io_placement.rpt" w]
    foreach _bt [[ord::get_db_block] getBTerms] {
        foreach _p [$_bt getBPins] {
            set _boxes [$_p getBoxes]
            if {[llength $_boxes] == 0} continue
            set _bb [$_p getBBox]
            set _l [[[lindex $_boxes 0] getTechLayer] getName]
            puts $_fh [format "%-32s %-6s %-5s (%.3f, %.3f)" [$_bt getName] [$_bt getIoType] $_l \
                [expr {[$_bb xMin] / double($_dbu)}] [expr {[$_bb yMin] / double($_dbu)}]]
        }
    }
    close $_fh
}

# Power intent (UPF supplies / global connections) + hierarchical power grid.
proc oss_fp_power {design blocks} {
    oss_apply_upf $design
    if {![oss_pdn_enabled]} {
        handle_info "PDN off (project(pdn,enable)) — supplies connected logically, no power grid"
        return
    }
    set _p [oss_pdn $design $blocks]
    handle_info "PDN: [dict get $_p position] pins=[dict get $_p pins] rails=[dict get $_p rails]"
    oss_check_power
}

# ── Node graph (branches) ────────────────────────────────────────────────────
# Command files are shared by every node of a stage type: main-trunk place1
# and branch nodes (place2, route2_fix, …) created with add-node /
# create-branch. The node being run comes from the launch wrapper
# (CBFLOW_NODE_NAME); its upstream from setup/runtime_flow_config.tcl for
# branch nodes, else the flow's dependencies,<node>.
# Thin aliases of the shared cbflow_* node-graph helpers (utils.tcl).
proc oss_node_name {stage} { return [cbflow_node_name] }
proc oss_load_runtime_nodes {} { cbflow_load_runtime_nodes }
proc oss_node_deps {node} { return [cbflow_node_deps $node] }
proc oss_node_type {node} { return [cbflow_node_type $node] }
proc oss_upstream_node {} { return [cbflow_upstream_node] }
proc oss_chain_node {type} { return [cbflow_chain_node $type] }
proc oss_source_node {types} { return [cbflow_source_node $types] }

# Stage artefacts use design-independent names so node configs can declare
# mandatory_outputs as data: every stage writes outputs/<stage>.<ext>, the
# signoff/export stages write outputs/final.<ext>; release renames to
# <design>.<ext>.
proc oss_node_output {node file} {
    set _f "$::DIRS(run)/work/$::FLOW_TYPE/$node/outputs/$file"
    if {![file exists $_f]} { error "upstream artefact not found: $_f (did $node complete?)" }
    return $_f
}

# Physical deliverables of a loaded design, as OpenROAD command lines (so
# signoff evals them in its own session and export_data runs them in an
# OpenROAD it starts on another stage's database): DEF, logical netlist,
# power-aware LVS netlist (no physical-only cells — fillers / well taps hold
# no devices), abstract LEF, CDL (standard-cell + memory + child-block
# masters), database. outdir/final.<ext>.
# (+ final.scandef when the database holds scan chains — read from the
# SYNTH scandef by PNR init_design with project(dft,enable))
proc oss_deliverable_cmds {outdir blocks} {
    set _cdl [list [oss_trk cdl_stdcell] {*}[oss_memory_files cdl]]
    foreach _b $blocks { lappend _cdl [oss_get tech block,$_b,cdl] }
    return [list \
        [list write_def $outdir/final.def] \
        [list write_verilog $outdir/final.v] \
        [list write_verilog -include_pwr_gnd -remove_cells [concat [oss_trk fillers] [oss_trk well_tap]] $outdir/final.lvs.v] \
        [list write_abstract_lef -bloat_occupied_layers $outdir/final.lef] \
        [list write_cdl -masters $_cdl $outdir/final.cdl] \
        [list write_db $outdir/final.odb] \
        [list source [file join $::env(FLOW_DIR) global utils utilities $::env(UTILITIES_VERSION) oss_scandef.tcl]] \
        "if {\[llength \[\[\[ord::get_db_block\] getDft\] getScanChains\]\]} { oss_write_scandef $outdir/final.scandef [oss_get project dft,max_chain_length] }"]
}

# Views KLayout merges into a block's GDS: tech + track LEFs, standard-cell
# GDS, memory macros, every child block's LEF / GDS -> {lefs gds}.
proc oss_export_views {blocks} {
    set _lefs [list [oss_ms "[oss_track],lef_tech"]]
    foreach _l [oss_trk lef] { lappend _lefs $_l }
    set _gds [list [oss_trk gds_stdcell]]
    lappend _lefs {*}[oss_memory_files lef]
    lappend _gds  {*}[oss_memory_files gds]
    foreach _b $blocks {
        set _v [hier_block_views $_b]
        lappend _lefs [dict get $_v lef]
        lappend _gds  [dict get $_v gds]
    }
    return [list $_lefs $_gds]
}

# DEF -> GDS recipe (a KLayout Python script at _py): the DEF over the LEFs,
# every macro filled from its GDS, min-area repair per
# <arr>(oss,export,min_area_layers). Shared by the PNR and ECO export steps.
proc oss_def2gds_script {_py design_name _def _lefs _gds _out arr} {
    upvar #0 $arr _fa
    set _fh [open $_py w]
    puts $_fh "import pya, sys"
    puts $_fh "opts = pya.LoadLayoutOptions()"
    puts $_fh "cfg = opts.lefdef_config"
    puts $_fh "cfg.map_file = '[oss_get tech klayout,def_layer_map]'"
    puts $_fh "cfg.lef_files = \[[join [lmap _l $_lefs {format "'%s'" $_l}] {, }]\]"
    # 2 = never draw LEF geometry: every macro (std cell or child block) is an
    # empty cell filled from its GDS. (1 draws LEF geometry — child-block OBS
    # blankets shorted the child for LVS.)
    puts $_fh "cfg.macro_resolution_mode = 2"
    puts $_fh "cfg.read_lef_with_def = False"
    puts $_fh "ly = pya.Layout()"
    puts $_fh "ly.read('$_def', opts)"
    foreach _g $_gds { puts $_fh "ly.read('$_g')" }
    puts $_fh "top = ly.cell('$design_name')"
    puts $_fh "out = pya.Layout(); out.dbu = ly.dbu"
    puts $_fh "out.create_cell('$design_name').copy_tree(top)"
    puts $_fh "empty = sorted(c.name for c in out.each_cell() if c.is_empty() and c.name != '$design_name')"
    puts $_fh "if empty:"
    puts $_fh "    print('ERROR: cells without GDS geometry: ' + ' '.join(empty)); sys.exit(1)"
    # Min-area repair: the detailed router leaves via-pair pads (M2M3+M3M4
    # 0.23 um apart) below the layer AREA rule on sky130 while reporting them
    # clean. Grow each undersized top-level polygon along its long axis to
    # the minimum, on the manufacturing grid. PV DRC/LVS verify the result.
    puts $_fh "import math"
    puts $_fh "fixes = \[\]"
    # Empty list = repair off (violations stay in the layout, PV reports them).
    if {![info exists _fa(oss,export,min_area_layers)]} { error "${arr}(oss,export,min_area_layers) is not set" }
    # Layout units: out.dbu (um per DBU, from the DEF); patches snap to
    # tech(manufacturing_grid) (um).
    if {[llength $_fa(oss,export,min_area_layers)]} {
        puts $_fh "dbu = out.dbu; grid = int(round([oss_get tech manufacturing_grid] / dbu))"
    }
    foreach {_gl _gd _amin} $_fa(oss,export,min_area_layers) {
        puts $_fh "li = out.layer($_gl, $_gd); amin = int(round($_amin / (dbu * dbu)))"
        puts $_fh "allm = pya.Region(out.top_cell().begin_shapes_rec(li)).merged()"
        puts $_fh "for p in allm.each():"
        puts $_fh "    if p.area() >= amin: continue"
        puts $_fh "    b = p.bbox(); w, h = b.width(), b.height()"
        puts $_fh "    if w >= h:"
        puts $_fh "        need = int(math.ceil((amin / h - w) / 2.0 / grid)) * grid + grid"
        puts $_fh "        nb = pya.Box(b.left - need, b.bottom, b.right + need, b.top)"
        puts $_fh "    else:"
        puts $_fh "        need = int(math.ceil((amin / w - h) / 2.0 / grid)) * grid + grid"
        puts $_fh "        nb = pya.Box(b.left, b.bottom - need, b.right, b.top + need)"
        puts $_fh "    out.top_cell().shapes(li).insert(nb)"
        puts $_fh "    fixes.append('$_gl/$_gd %.4f um2 at (%.3f,%.3f) -> %.4f um2' % (p.area()*dbu*dbu, b.left*dbu, b.bottom*dbu, nb.area()*dbu*dbu))"
    }
    puts $_fh "open('$::REPORTS_DIR/export_min_area_fixes.rpt', 'w').write('min-area patches (GDS only, not in DEF): %d\\n' % len(fixes) + '\\n'.join(fixes) + '\\n')"
    puts $_fh "print('min-area patches: %d' % len(fixes))"
    puts $_fh "out.write('$_out')"
    puts $_fh "print('GDS written: $_out cells=%d' % out.cells())"
    close $_fh
}

# Load a finished node's design for reporting / interactive work: its
# database (outputs/<stage>.odb, else final.odb, else any .odb), timing views,
# SDC; propagated clocks from CTS on; the pro SPEF from pro on, else
# placement-estimated parasitics. Used by checks_openroad.tcl
# (cbflow-oss-checks) and the OpenROAD interactive session.
# Node whose MMMC views a node times on: its own; FP nodes use the FP run's
# init_design node's (the FP stages read them the same way)
proc oss_view_node {node} {
    return [expr {$::FLOW_TYPE eq "FP" ? [cbflow_chain_node init_design] : $node}]
}

proc oss_load_node {node blocks} {
    set _st [cbflow_node_type $node]
    set_thread_count [oss_get [oss_flow_arr] oss,threads]
    set _vn [oss_view_node $node]
    oss_read_corners $_vn $blocks
    set _out "[cbflow_node_dir $node]/outputs"
    set _odb [lindex [glob -nocomplain "$_out/$_st.odb" "$_out/final.odb" "$_out/*.odb"] 0]
    if {$_odb eq ""} { error "no database in $_out — did $node complete?" }
    read_db $_odb
    read_sdc [oss_sdc_file]
    if {$_st in {cts cts_opt route pro signoff}} { set_propagated_clock [all_clocks] }
    set _pro ""
    if {$_st eq "pro"} { set _pro $node } elseif {$_st eq "signoff"} { set _pro [lindex [cbflow_node_deps $node] 0] }
    if {$_pro ne ""} {
        foreach _v [oss_node_views $_vn] {
            set _s "[cbflow_node_dir $_pro]/outputs/final_[oss_view_attr $_v rc_corner].spef"
            if {[file exists $_s]} { read_spef -corner $_v $_s }
        }
    } else {
        oss_set_wire_rc
        catch { estimate_parasitics -placement }
    }
    return $_odb
}

# Database written by an upstream node: <node>/outputs/<stage type>.odb.
proc oss_prev_odb {prev_node} {
    return [oss_node_output $prev_node "[oss_node_type $prev_node].odb"]
}

proc oss_stage_out {file} {
    file mkdir "$::WORK_DIR/outputs"
    return "$::WORK_DIR/outputs/$file"
}

# The per-corner option of an OpenSTA command: newer builds call corners
# "scenes" (-scene), older builds -corner.
proc oss_corner_opt {cmd} {
    if {![catch {info body $cmd} _b] && [string match "*-scene*" $_b]} { return "-scene" }
    return "-corner"
}

# Write any command's output to a report file (OpenSTA redirection — works
# for OpenROAD commands that have no `>` / -out_file support).
proc oss_report {file args} {
    sta::redirect_file_begin $file
    set _rc [catch {uplevel 1 $args} _err]
    sta::redirect_file_end
    if {$_rc} { error $_err }
}

# Worst setup/hold slack across the node's corners, written to a metrics file
# the validate step and dashboards can read.
# Path-group timing: <flow>(oss,path_groups) {NAME {from to} ...} (from / to =
# all_registers | all_inputs | all_outputs). For every view (corner; {} =
# the single loaded corner) x group x setup/hold: report
# <prefix>_<setup|hold>_<group>[_<view>].rpt (<flow>(oss,path_groups,
# report_paths) paths) and return "# scenario:"-ready lines
# "<Setup|Hold> <group> <WNS|TNS> : value" per view as {view lines ...}.
# Number of violating paths (endpoints with negative slack), max = setup,
# min = hold; args e.g. -corner <view>. (sta::endpoint_violation_count
# crashes this OpenROAD build.)
proc oss_nvp {min_max args} {
    return [llength [find_timing_paths -path_delay $min_max -slack_max 0 \
                         -group_path_count 1000000 -endpoint_path_count 1 {*}$args]]
}

proc oss_group_timing {views prefix} {
    set _arr [oss_flow_arr]
    set _groups [oss_get $_arr oss,path_groups]
    set _np [oss_get $_arr oss,path_groups,report_paths]
    foreach {_g _ft} $_groups {
        lassign $_ft _from _to
        catch {group_path -name $_g -from [$_from] -to [$_to]}
    }
    set _copt [oss_corner_opt find_timing_paths]
    set _out {}
    foreach _v [expr {[llength $views] ? $views : [list {}]}] {
        set _cor [expr {$_v eq "" ? {} : [list $_copt $_v]}]
        set _L {}
        foreach {_chk _mm} {Setup max Hold min} {
            foreach {_g _ft} $_groups {
                set _ends [find_timing_paths -path_group $_g -path_delay $_mm {*}$_cor \
                               -group_path_count 1000000 -endpoint_path_count 1 -sort_by_slack]
                set _w ""; set _t 0.0; set _nv 0
                foreach _pe $_ends {
                    set _sl [get_property $_pe slack]
                    if {$_w eq "" || $_sl < $_w} { set _w $_sl }
                    if {$_sl < 0} { set _t [expr {$_t + $_sl}]; incr _nv }
                }
                # (not an expr ternary: expr would turn "15.310" back into 15.31)
                if {$_w eq ""} { set _ws N/A; set _ts N/A; set _nv N/A } else { set _ws [cbflow_fmt_slack $_w]; set _ts [cbflow_fmt_slack $_t] }
                lappend _L "$_chk $_g WNS : $_ws" "$_chk $_g TNS : $_ts" "$_chk $_g NVP : $_nv"
                set _rpt "${prefix}_[string tolower $_chk]_${_g}[expr {$_v eq "" ? "" : "_$_v"}].rpt"
                oss_report $_rpt report_checks -path_group $_g -path_delay $_mm {*}$_cor \
                    -group_path_count $_np -format full_clock_expanded
            }
        }
        lappend _out $_v $_L
    }
    return $_out
}

# DEF -> GDS with KLayout (inside the tool container): the design's DEF over
# the tech + track LEFs, every macro filled from its GDS (std cells, child
# blocks). min_area {layer datatype area_um2 ...}: grow undersized polygons
# to the layer AREA rule ({} = off). Errors when a cell has no GDS geometry.
proc oss_def2gds {def out min_area klayout_cmd} {
    global blocks
    set _design [oss_get flow design_name]
    set _lefs [list [oss_ms "[oss_track],lef_tech"]]
    foreach _l [oss_trk lef] { lappend _lefs $_l }
    set _gds [list [oss_trk gds_stdcell]]
    lappend _lefs {*}[oss_memory_files lef]
    lappend _gds  {*}[oss_memory_files gds]
    foreach _b $blocks {
        set _v [hier_block_views $_b]
        lappend _lefs [dict get $_v lef]
        lappend _gds  [dict get $_v gds]
    }
    set _py "$::WORK_DIR/def2gds.py"
    set _fh [open $_py w]
    puts $_fh "import pya, sys, math"
    puts $_fh "opts = pya.LoadLayoutOptions()"
    puts $_fh "cfg = opts.lefdef_config"
    puts $_fh "cfg.map_file = '[oss_get tech klayout,def_layer_map]'"
    puts $_fh "cfg.lef_files = \[[join [lmap _l $_lefs {format "'%s'" $_l}] {, }]\]"
    puts $_fh "cfg.macro_resolution_mode = 2"      ;# macros only from their GDS
    puts $_fh "cfg.read_lef_with_def = False"
    puts $_fh "ly = pya.Layout()"
    puts $_fh "ly.read('$def', opts)"
    foreach _g $_gds { puts $_fh "ly.read('$_g')" }
    puts $_fh "top = ly.cell('$_design')"
    puts $_fh "out = pya.Layout(); out.dbu = ly.dbu"
    puts $_fh "out.create_cell('$_design').copy_tree(top)"
    puts $_fh "empty = sorted(c.name for c in out.each_cell() if c.is_empty() and c.name != '$_design')"
    puts $_fh "if empty:"
    puts $_fh "    print('ERROR: cells without GDS geometry: ' + ' '.join(empty)); sys.exit(1)"
    puts $_fh "fixes = \[\]"
    if {[llength $min_area]} {
        puts $_fh "dbu = out.dbu; grid = int(round([oss_get tech manufacturing_grid] / dbu))"
    }
    foreach {_gl _gd _amin} $min_area {
        puts $_fh "li = out.layer($_gl, $_gd); amin = int(round($_amin / (dbu * dbu)))"
        puts $_fh "for p in pya.Region(out.top_cell().begin_shapes_rec(li)).merged().each():"
        puts $_fh "    if p.area() >= amin: continue"
        puts $_fh "    b = p.bbox(); w, h = b.width(), b.height()"
        puts $_fh "    if w >= h:"
        puts $_fh "        need = int(math.ceil((amin / h - w) / 2.0 / grid)) * grid + grid"
        puts $_fh "        nb = pya.Box(b.left - need, b.bottom, b.right + need, b.top)"
        puts $_fh "    else:"
        puts $_fh "        need = int(math.ceil((amin / w - h) / 2.0 / grid)) * grid + grid"
        puts $_fh "        nb = pya.Box(b.left, b.bottom - need, b.right, b.top + need)"
        puts $_fh "    out.top_cell().shapes(li).insert(nb)"
        puts $_fh "    fixes.append('$_gl/$_gd %.4f um2 at (%.3f,%.3f) -> %.4f um2' % (p.area()*dbu*dbu, b.left*dbu, b.bottom*dbu, nb.area()*dbu*dbu))"
    }
    puts $_fh "open('$::REPORTS_DIR/export_min_area_fixes.rpt', 'w').write('min-area patches (GDS only, not in DEF): %d\\n' % len(fixes) + '\\n'.join(fixes) + '\\n')"
    puts $_fh "out.write('$out')"
    puts $_fh "print('GDS written: $out cells=%d' % out.cells())"
    close $_fh
    if {[is_true $::flow(test_mode)]} {
        puts "  TEST_CMD: $klayout_cmd $_py"
        return
    }
    set _log "$::REPORTS_DIR/export_klayout.log"
    if {[catch {exec {*}$klayout_cmd $_py >& $_log} _err]} {
        error "KLayout DEF->GDS failed (see $_log): $_err"
    }
    handle_info [exec tail -1 $_log]
}

proc oss_write_qor {tag} {
    set _f "$::REPORTS_DIR/${tag}_qor.tcl"
    set _fh [open $_f w]
    puts $_fh "set qor(stage) \"$tag\""
    puts $_fh "set qor(wns_setup) [sta::worst_slack -max]"
    puts $_fh "set qor(wns_hold) [sta::worst_slack -min]"
    puts $_fh "set qor(tns_setup) [sta::total_negative_slack -max]"
    puts $_fh "set qor(instances) [llength [[ord::get_db_block] getInsts]]"
    close $_fh
    oss_report "$::REPORTS_DIR/${tag}_setup.rpt" report_checks -path_delay max -group_path_count 5
    oss_report "$::REPORTS_DIR/${tag}_hold.rpt" report_checks -path_delay min -group_path_count 5
    oss_report "$::REPORTS_DIR/${tag}_area.rpt" report_design_area
    puts "QOR $tag: wns_setup=[sta::worst_slack -max] wns_hold=[sta::worst_slack -min] instances=[llength [[ord::get_db_block] getInsts]]"
    oss_checklist_safe $tag
    if {[catch {oss_timing_snapshot} _e]} { handle_warning "timing snapshot not written: $_e" }
}

# reports/timing_snapshot.json — worst setup (max) and hold (min) paths per
# endpoint clock with the instances along each path (DBU locations), the
# shape SmartGrid's timing debugger reads (tracker_db.set_timing).
proc oss_timing_snapshot {{n 10}} {
    set _blk [ord::get_db_block]
    set _dbu [[ord::get_db_tech] getDbUnitsPerMicron]
    set groups [dict create]
    set idx 0
    foreach _type {max min} {
        foreach _pe [find_timing_paths -path_delay $_type -group_path_count $n -sort_by_slack] {
            set _slack [get_property $_pe slack]
            if {![string is double -strict $_slack] || abs($_slack) > 1e20} continue
            set _clk [get_property $_pe endpoint_clock]
            set _cname [expr {$_clk eq "" ? "unclocked" : [get_full_name $_clk]}]
            set _insts {}; set _seen {}; set _arr 0.0
            foreach _pt [get_property $_pe points] {
                set _pin [get_full_name [get_property $_pt pin]]
                set _a [get_property $_pt arrival]
                if {[string is double -strict $_a]} { set _arr $_a }
                set _iname [expr {[string first / $_pin] >= 0 ? [string range $_pin 0 [expr {[string last / $_pin] - 1}]] : $_pin}]
                if {$_iname in $_seen} continue
                lappend _seen $_iname
                set _i [$_blk findInst $_iname]
                if {$_i ne "NULL" && $_i ne ""} {
                    lassign [$_i getLocation] _x _y
                } else {
                    set _bt [$_blk findBTerm $_iname]
                    set _x 0; set _y 0
                    if {$_bt ne "NULL" && $_bt ne ""} {
                        foreach _bp [$_bt getBPins] { set _bb [$_bp getBBox]; set _x [$_bb xMin]; set _y [$_bb yMin] }
                    }
                }
                lappend _insts [format {{"name":"%s","x":%d,"y":%d}} [string map {\" \\\"} $_iname] $_x $_y]
            }
            set _req [expr {$_type eq "max" ? $_arr + $_slack : $_arr - $_slack}]
            incr idx
            set _start [string map {\" \\\"} [get_full_name [get_property $_pe startpoint]]]
            set _end   [string map {\" \\\"} [get_full_name [get_property $_pe endpoint]]]
            dict lappend groups $_cname [format {{"index":%d,"type":"%s","slack":%s,"arrival":%s,"required":%s,"start":"%s","end":"%s","instances":[%s]}} \
                $idx $_type $_slack $_arr $_req $_start $_end [join $_insts ,]]
        }
    }
    set _g {}
    dict for {_c _paths} $groups {
        lappend _g [format {{"name":"%s","paths":[%s]}} $_c [join $_paths ,]]
    }
    set _fh [open "$::REPORTS_DIR/timing_snapshot.json" w]
    puts $_fh [format {{"units":%d,"clock_groups":[%s]}} $_dbu [join $_g ,]]
    close $_fh
}

# Checklist data is reporting, never a reason to fail a stage.
proc oss_checklist_safe {tag} {
    if {[catch {oss_checklist_metrics $tag} _e]} {
        handle_warning "checklist metrics ($tag) not written: $_e"
    }
    # checklist library reports (oss_checks.tcl / oss_checkgrp_*.tcl)
    if {[catch {oss_checks_run $tag} _e]} {
        handle_warning "checklist library reports ($tag) not written: $_e"
    }
}

# Exit-checklist data for this node: reports/checklist_metrics.rpt, one
# "Key : value" line per metric. The tool's checklist map (FP/PNR
# _openroad_config.tcl  <flow>(checklist,*)) points each exit check at a line.
# Metrics this stage cannot measure are left out (the check reads NA).
#   tag: fp | init_design | place | cts | cts_opt | route | pro | signoff
proc oss_checklist_metrics {tag} {
    set _blk [ord::get_db_block]
    set _dbu [[ord::get_db_tech] getDbUnitsPerMicron]
    # "# category: <c>" lines group the metrics for SmartGrid (publish reads
    # this file as metrics.rpt); checklist patterns match the "Key : value" lines.
    set L [list "# category: design" "Design : [$_blk getName]" "Stage : $tag" \
               "Instances : [llength [$_blk getInsts]]"]

    # Area / utilization (report_design_area)
    set _tmp "$::REPORTS_DIR/.checklist_area.tmp"
    if {![catch {oss_report $_tmp report_design_area}]} {
        set _fh [open $_tmp]; set _t [read $_fh]; close $_fh; file delete $_tmp
        if {[regexp {Design area\s+([\d.]+)\s+\S*\^2\s+([\d.]+)% utilization} $_t -> _a _u]} {
            lappend L "Design area um2 : $_a" "Design utilization incl macros : $_u"
        }
    }
    # Standard-cell utilization over the core area not taken by hard macros
    set _std 0.0; set _macro 0.0
    foreach _i [$_blk getInsts] {
        set _m [$_i getMaster]
        set _ar [expr {[$_m getWidth] * double([$_m getHeight]) / ($_dbu * $_dbu)}]
        if {[$_m isBlock]} { set _macro [expr {$_macro + $_ar}] } elseif {![$_m isFiller]} { set _std [expr {$_std + $_ar}] }
    }
    set _c [$_blk getCoreArea]
    set _core [expr {([$_c xMax] - [$_c xMin]) * double([$_c yMax] - [$_c yMin]) / ($_dbu * $_dbu)}]
    if {$_core > $_macro} {
        lappend L "Utilization : [format %.1f [expr {100.0 * $_std / ($_core - $_macro)}]]"
    }

    # Timing (library time units)
    lappend L "# category: timing"
    foreach {_k _c} {"Setup WNS" {sta::worst_slack -max} "Setup TNS" {sta::total_negative_slack -max}
                     "Hold WNS" {sta::worst_slack -min} "Hold TNS" {sta::total_negative_slack -min}} {
        # |slack| ~1e30+ = no constrained path: not measurable, leave it out
        if {![catch {eval $_c} _v] && [string is double -strict $_v] && abs($_v) < 1e20} {
            lappend L "$_k : [cbflow_fmt_slack $_v]"
        }
    }
    if {$tag ni {fp init_design}} {
        foreach {_k _mm} {"Setup NVP" max "Hold NVP" min} {
            if {![catch {oss_nvp $_mm} _v]} { lappend L "$_k : $_v" }
        }
    }
    # Design-rule (electrical) violations
    foreach {_k _c} {"Max slew violations" sta::max_slew_violation_count
                     "Max cap violations" sta::max_capacitance_violation_count
                     "Max fanout violations" sta::max_fanout_violation_count} {
        if {$tag ni {fp init_design} && ![catch {$_c} _v] && [string is integer -strict $_v]} {
            lappend L "$_k : $_v"
        }
    }

    # Hard macros: overlaps, orientation, placement status
    set _boxes {}; set _orient 0; set _unpl 0
    foreach _i [$_blk getInsts] {
        if {![[$_i getMaster] isBlock]} continue
        if {[$_i getPlacementStatus] in {NONE UNPLACED}} { incr _unpl; continue }
        if {[$_i getOrient] ni {R0 R180 MX MY}} { incr _orient }
        set _b [$_i getBBox]
        lappend _boxes [list [$_b xMin] [$_b yMin] [$_b xMax] [$_b yMax]]
    }
    set _ovl 0
    for {set i 0} {$i < [llength $_boxes]} {incr i} {
        lassign [lindex $_boxes $i] ax0 ay0 ax1 ay1
        for {set j [expr {$i + 1}]} {$j < [llength $_boxes]} {incr j} {
            lassign [lindex $_boxes $j] bx0 by0 bx1 by1
            if {$ax0 < $bx1 && $bx0 < $ax1 && $ay0 < $by1 && $by0 < $ay1} { incr _ovl }
        }
    }
    lappend L "# category: placement" "Hard macros : [expr {[llength $_boxes] + $_unpl}]" \
              "Macro spacing violations : [expr {$_ovl + $_unpl}]" \
              "Macro orientation violations : $_orient"

    # IO pins without a placed pin shape
    set _io 0
    foreach _bt [$_blk getBTerms] {
        set _placed 0
        foreach _bp [$_bt getBPins] {
            if {[$_bp getPlacementStatus] ni {NONE UNPLACED}} { set _placed 1 }
        }
        if {!$_placed} { incr _io }
    }
    lappend L "IO pins : [llength [$_blk getBTerms]]" "IO placement violations : $_io"

    # Placement legality (placed stages)
    if {$tag ni {fp init_design}} {
        set _tmp "$::REPORTS_DIR/.checklist_dpl.tmp"
        set _rc [catch {oss_report $_tmp check_placement -verbose}]
        set _n 0
        if {[file exists $_tmp]} {
            set _fh [open $_tmp]; set _t [read $_fh]; close $_fh; file delete $_tmp
            foreach {_ _c} [regexp -all -inline {(\d+)\s+[A-Za-z ]*violations?} $_t] { incr _n $_c }
        }
        if {!$_rc} { lappend L "Illegal cells : 0" } elseif {$_n > 0} { lappend L "Illegal cells : $_n" }
    }

    # Clock tree (post-CTS): skew and latency from report_clock_skew (ps)
    if {$tag in {cts cts_opt route pro signoff}} {
        set _tmp "$::REPORTS_DIR/clock_skew.rpt"
        if {![catch {oss_report $_tmp report_clock_skew -setup}]} {
            set _fh [open $_tmp]; set _t [read $_fh]; close $_fh
            # Clock tree skew = source latency + target latency (the report's
            # "setup skew" also adds clock uncertainty); insertion delay =
            # source latency. Worst over the clocks reported.
            set _skew ""; set _lat ""
            foreach _ln [split $_t \n] {
                if {[regexp -- {^\s*(-?[\d.]+)\s+source latency} $_ln -> _src]} { set _s $_src }
                if {[regexp -- {^\s*(-?[\d.]+)\s+target latency} $_ln -> _tgt] && [info exists _s]} {
                    set _k [expr {abs($_s + $_tgt)}]
                    if {$_skew eq "" || $_k > $_skew} { set _skew $_k }
                    if {$_lat eq "" || $_s > $_lat} { set _lat $_s }
                }
            }
            if {$_skew ne ""} {
                lappend L "# category: clock" \
                          "Clock skew ps : [format %.1f [expr {$_skew * 1000}]]" \
                          "Clock insertion delay ps : [format %.1f [expr {$_lat * 1000}]]"
            }
        }
    }

    # Routing (routed stages): unrouted signal nets, detailed-route DRC,
    # global-route overflow from the route node's reports
    if {$tag in {route pro signoff}} {
        set _sig 0; set _open 0
        foreach _n [$_blk getNets] {
            if {[$_n getSigType] in {POWER GROUND}} continue
            if {[llength [$_n getITerms]] + [llength [$_n getBTerms]] < 2} continue
            incr _sig
            if {[$_n getWire] eq "NULL"} { incr _open }
        }
        set _pct [expr {$_sig ? 100.0 * ($_sig - $_open) / $_sig : 100.0}]
        lappend L "# category: routing" "Routable nets : $_sig" "Open nets : $_open" \
                  "Routing completion : [format %.2f $_pct]"
        set _rdir [expr {$tag eq "route" ? $::REPORTS_DIR
                         : "$::run_dir/work/$::FLOW_TYPE/[oss_chain_node route]/reports"}]
        if {[file exists "$_rdir/route_drc.rpt"]} {
            set _fh [open "$_rdir/route_drc.rpt"]; set _t [read $_fh]; close $_fh
            lappend L "DRC violations : [regexp -all -nocase {violation type} $_t]" \
                      "Shorts : [regexp -all -nocase {violation type:\s*short} $_t]"
            lappend L "Routing opens+shorts : [expr {$_open + [regexp -all -nocase {violation type:\s*short} $_t]}]"
        }
        if {[file exists "$_rdir/route_grt.rpt"]} {
            set _fh [open "$_rdir/route_grt.rpt"]; set _t [read $_fh]; close $_fh
            # "Total  <resource> <demand> <usage>%  <maxH> / <maxV> / <total overflow>"
            if {[regexp -line {^Total\s+(\d+)\s+(\d+)\s+([\d.]+)%\s+(\d+)\s*/\s*(\d+)\s*/\s*(\d+)\s*$} $_t -> _res _dem _use _h _v _tot]} {
                lappend L "Routing resource usage pct : $_use" "Horizontal overflow : $_h" \
                          "Vertical overflow : $_v" "Total overflow : $_tot" \
                          "Overflow pct : [format %.3f [expr {$_res ? 100.0 * $_tot / $_res : 0.0}]]"
            }
        }
    }

    # Per corner (the node's views) x path group: setup / hold WNS + TNS —
    # '# scenario:' sections at the end (first-match checklist patterns keep
    # reading the design-level lines above)
    if {$tag ni {fp init_design}} {
        lappend L "# category: scenario"
        foreach {_v _gl} [oss_group_timing [oss_node_views $::NODE_NAME] "$::REPORTS_DIR/$tag"] {
            lappend L "# scenario: $_v" {*}$_gl
        }
    }

    set _fh [open "$::REPORTS_DIR/checklist_metrics.rpt" w]
    puts $_fh [join $L \n]
    close $_fh
}

# ── Hierarchy ───────────────────────────────────────────────────────────────
proc hier_children {design} {
    set _h [oss_get project design_hierarchy]
    if {![dict exists $_h $design]} {
        error "design '$design' is not in project(design_hierarchy) (valid: [dict keys $_h])"
    }
    set _spec [dict get $_h $design]
    return [expr {[dict exists $_spec children] ? [dict get $_spec children] : {}}]
}

proc hier_level {design} {
    set _spec [dict get [oss_get project design_hierarchy] $design]
    return [dict get $_spec level]
}

# Views of a child block from the active library tag. Children reach their
# parent only through the tag: release the child, then integrate it with
#   cbflow flow library-manager add --tech <tech> --tag <tag> --category block \
#       --path <release,path>/<phase>/<child>/<release_tag>
# which writes tech(block,<child>,...) into the tag's blocks_config.tcl.
proc hier_block_views {child} {
    set _hint "integrate it: cbflow flow library-manager add --tag [oss_get project lib_config_tag] --category block --path <release dir of $child>"
    if {![info exists ::tech(blocks)] || [lsearch -exact $::tech(blocks) $child] < 0} {
        error "child block '$child' is not in library tag [oss_get project lib_config_tag] — $_hint"
    }
    set _v [dict create release [oss_get tech block,$child,release]]
    foreach _k {lef gds netlist} {
        set _f [oss_get tech block,$child,$_k]
        if {![file exists $_f]} { error "child block '$child': $_k view missing in the tag: $_f — $_hint" }
        dict set _v $_k $_f
    }
    return $_v
}

proc hier_block_lib {views child lib_set} {
    set _k "block,$child,lib,$lib_set"
    if {![info exists ::tech($_k)]} {
        error "child block '$child' has no timing model for lib set '$lib_set' (has: [oss_get tech block,$child,lib_sets]) — re-release $child with $lib_set in its signoff1 scenarios, then re-run library-manager add"
    }
    return $::tech($_k)
}

# ── Power intent (UPF) ───────────────────────────────────────────────────────
# OpenROAD's read_upf implements a subset of IEEE 1801 (domains, isolation,
# interface cells, level shifters, switches, domain area/voltage) but not the
# supply network or power states. The design UPF stays standard 1801; this
# evaluates it in a safe child interpreter and splits it:
#   - read_upf subset           → written to <work>/<design>.openroad.upf
#   - supply network            → ::oss_upf(...) → global connections + PDN
#   - power states / PST        → recorded only (no open-source consumer)
#   - load_upf -scope <inst>    → a hard-macro child implemented its own UPF
# Everything not forwarded is listed in reports/upf_subset.rpt.
proc oss_upf_parse {upf_file} {
    global oss_upf
    array unset oss_upf
    set oss_upf(domains) {}
    set oss_upf(nets) {}
    set oss_upf(ports) {}
    set oss_upf(conn) {}           ;# {net inst pin ...}
    set oss_upf(forward) {}
    set oss_upf(skipped) {}
    set _i [interp create -safe]
    set _fwd {create_power_domain set_isolation use_interface_cell set_level_shifter
              create_power_switch map_power_switch set_domain_area set_domain_voltage create_logic_port}
    foreach _c $_fwd {
        interp alias $_i $_c {} oss_upf_record forward $_c
    }
    foreach _c {create_supply_port create_supply_net connect_supply_net set_domain_supply_net} {
        interp alias $_i $_c {} oss_upf_record supply $_c
    }
    foreach _c {upf_version set_scope add_port_state create_pst add_pst_state add_power_state
                create_supply_set associate_supply_set set_retention set_retention_control
                set_isolation_control set_design_attributes} {
        interp alias $_i $_c {} oss_upf_record skip $_c
    }
    interp alias $_i load_upf {} oss_upf_record skip load_upf
    # [info script]/[file …] used by load_upf paths: harmless stubs in the safe interp
    interp alias $_i info {} oss_upf_info $upf_file
    interp alias $_i file {} oss_upf_file
    set _fh [open $upf_file]; set _txt [read $_fh]; close $_fh
    if {[catch {interp eval $_i $_txt} _err]} {
        interp delete $_i
        error "UPF $upf_file: $_err"
    }
    interp delete $_i
}
proc oss_upf_info {upf args} { if {[lindex $args 0] eq "script"} { return $upf }; return "" }
proc oss_upf_file {args} { return [::file {*}$args] }

proc oss_upf_record {kind cmd args} {
    global oss_upf
    switch -- $kind {
        forward {
            set _fargs $args
            # OpenROAD names the scope domain with -elements {.}, not -include_scope.
            if {$cmd eq "create_power_domain"} {
                set _k [lsearch -exact $_fargs -include_scope]
                if {$_k >= 0} { set _fargs [lreplace $_fargs $_k $_k -elements {.}] }
            }
            lappend oss_upf(forward) [linsert $_fargs 0 $cmd]
        }
        skip    { lappend oss_upf(skipped) [linsert $args 0 $cmd] }
        supply {
            switch -- $cmd {
                create_supply_port { lappend oss_upf(ports) [lindex $args 0] }
                create_supply_net  { lappend oss_upf(nets)  [lindex $args 0] }
                connect_supply_net {
                    set _net [lindex $args 0]
                    set _ports [lindex $args [expr {[lsearch -exact $args -ports] + 1}]]
                    foreach _p $_ports {
                        if {[string first / $_p] > 0} {
                            lappend oss_upf(conn) $_net [file dirname $_p] [file tail $_p]
                        }
                    }
                }
                set_domain_supply_net {
                    set _d [lindex $args 0]
                    set oss_upf(power,$_d)  [lindex $args [expr {[lsearch -exact $args -primary_power_net] + 1}]]
                    set oss_upf(ground,$_d) [lindex $args [expr {[lsearch -exact $args -primary_ground_net] + 1}]]
                }
            }
        }
    }
    if {$cmd eq "create_power_domain"} {
        set _d [lindex $args 0]
        lappend oss_upf(domains) $_d
        if {[lsearch -exact $args -include_scope] >= 0} { set oss_upf(top_domain) $_d }
        set _e [lsearch -exact $args -elements]
        set oss_upf(elements,$_d) [expr {$_e >= 0 ? [lindex $args [expr {$_e + 1}]] : {}}]
    }
}

# Keep only the options the running OpenROAD accepts for a UPF command: its
# Tcl wrapper declares them via `sta::parse_key_args … keys {…} flags {…}`.
# Outside OpenROAD (test mode) the command is returned unchanged.
proc oss_upf_fit {cmd} {
    global oss_upf
    set _name [lindex $cmd 0]
    if {[catch {info body $_name} _body] ||
        ![regexp {keys\s+\{([^\}]*)\}\s+flags\s+\{([^\}]*)\}} $_body -> _keys _flags]} {
        return $cmd
    }
    set _out [list $_name]
    set _rest [lrange $cmd 1 end]
    for {set _i 0} {$_i < [llength $_rest]} {incr _i} {
        set _a [lindex $_rest $_i]
        if {[string index $_a 0] ne "-"} { lappend _out $_a; continue }
        if {$_a in $_keys} {
            lappend _out $_a [lindex $_rest [incr _i]]
        } elseif {$_a in $_flags} {
            lappend _out $_a
        } else {
            set _next [lindex $_rest [expr {$_i + 1}]]
            if {$_next ne "" && [string index $_next 0] ne "-"} { incr _i } else { set _next "" }
            lappend oss_upf(dropped_opts) "$_name $_a $_next"
        }
    }
    return $_out
}

# Load the staged UPF: forward the subset to read_upf, connect supplies.
# Standard cells take the scope domain's primary supplies; every
# connect_supply_net <net> -ports {<inst>/<pin>} becomes a global connection
# (hard-macro supply pins).
proc oss_apply_upf {design} {
    global oss_upf
    set _upf [lindex [glob -nocomplain "$::UPF_DIR/${design}.upf" "$::UPF_DIR/*.upf"] 0]
    if {$_upf eq ""} { error "no UPF staged in $::UPF_DIR (synth_pnr(input,upf_file))" }
    oss_upf_parse $_upf
    if {![info exists oss_upf(top_domain)]} { error "UPF $_upf: no create_power_domain -include_scope" }
    set _td $oss_upf(top_domain)
    set _vdd $oss_upf(power,$_td)
    set _vss $oss_upf(ground,$_td)

    set _sub "$::WORK_DIR/${design}.openroad.upf"
    set _fh [open $_sub w]
    puts $_fh "# OpenROAD read_upf subset of $_upf (generated by oss_apply_upf)"
    set oss_upf(dropped_opts) {}
    foreach _c $oss_upf(forward) { puts $_fh [oss_upf_fit $_c] }
    close $_fh
    read_upf -file $_sub

    # Instance-specific rules (hard-macro supply pins) FIRST: OpenROAD applies
    # the first matching rule, so the generic std-cell rules must not shadow
    # e.g. u_gcd/VPWR -> VPWR_GCD.
    set _grounds {}
    foreach _k [array names oss_upf ground,*] { lappend _grounds $oss_upf($_k) }
    foreach {_net _inst _pin} $oss_upf(conn) {
        set _kind [expr {[lsearch -exact $_grounds $_net] >= 0 ? "-ground" : "-power"}]
        add_global_connection -net $_net -inst_pattern "^[string map {[ \\[ ] \\]} $_inst]\$" -pin_pattern "^${_pin}\$" $_kind
    }
    foreach _p [oss_trk power_pins]  { add_global_connection -net $_vdd -pin_pattern "^${_p}\$" -power }
    foreach _p [oss_trk ground_pins] { add_global_connection -net $_vss -pin_pattern "^${_p}\$" -ground }
    if {[oss_has_memories]} {
        foreach _p [oss_get tech memory,power_pins]  { add_global_connection -net $_vdd -pin_pattern "^${_p}\$" -power }
        foreach _p [oss_get tech memory,ground_pins] { add_global_connection -net $_vss -pin_pattern "^${_p}\$" -ground }
    }
    global_connect

    set _fh [open "$::REPORTS_DIR/upf_subset.rpt" w]
    puts $_fh "UPF: $_upf"
    puts $_fh "Scope domain: $_td  primary $_vdd / $_vss"
    puts $_fh "Domains: $oss_upf(domains)"
    puts $_fh "Supply nets: $oss_upf(nets)   supply ports: $oss_upf(ports)"
    puts $_fh "\nForwarded to OpenROAD read_upf ([llength $oss_upf(forward)]):"
    foreach _c $oss_upf(forward) { puts $_fh "  $_c" }
    puts $_fh "\nOptions this OpenROAD build does not accept (dropped):"
    foreach _d $oss_upf(dropped_opts) { puts $_fh "  $_d" }
    puts $_fh "\nSupply connections → add_global_connection:"
    foreach {_net _inst _pin} $oss_upf(conn) { puts $_fh "  $_inst/$_pin -> $_net" }
    puts $_fh "\nNot implemented by OpenROAD — documented intent only ([llength $oss_upf(skipped)]):"
    foreach _c $oss_upf(skipped) { puts $_fh "  $_c" }
    close $_fh
    handle_info "UPF applied: domains=$oss_upf(domains) forwarded=[llength $oss_upf(forward)] skipped=[llength $oss_upf(skipped)]"
}

# Every block below a design (children, grandchildren, …), depth-first.
proc hier_descendants {design} {
    set _out {}
    foreach _c [hier_children $design] {
        lappend _out $_c
        foreach _d [hier_descendants $_c] { if {$_d ni $_out} { lappend _out $_d } }
    }
    return $_out
}

# Run a tool inside the container from a Tcl driver stage (oss_tclsh) and
# fail with the log tail when it exits non-zero. Test mode prints the call.
proc oss_exec_tool {tool script log {extra {}}} {
    global flow
    if {[info exists flow(test_mode)] && [is_true $flow(test_mode)]} {
        puts "  TEST_CMD: $tool $script $extra (log $log)"
        return 0
    }
    switch -- $tool {
        magic   { set _cmd [list magic -dnull -noconsole -rcfile [oss_get tech magic,rcfile] $script] }
        netgen  { set _cmd [list netgen -batch source $script] }
        klayout { set _cmd [list klayout -b -r $script {*}$extra] }   ;# batch ruby/DRC script
        openroad { set _cmd [list openroad -exit -no_init $script] }
        default { error "oss_exec_tool: unknown tool $tool" }
    }
    if {[catch {exec {*}$_cmd >& $log} _err]} {
        set _tail ""
        catch { set _tail [exec tail -20 $log] }
        error "$tool failed (see $log): $_err\n$_tail"
    }
    return 0
}

# Checklist library reports (oss_checks_run, oss_check_line)
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_checks.tcl"
