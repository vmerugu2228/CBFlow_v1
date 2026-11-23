# ═══════════════════════════════════════════════════════════════════════════════
# Checklist library reports — group: power (low-power / UPF checks,
# global/config/exit/v1.0.0/checks/power_checks.tcl). Called by oss_checks_run
# with the stage's design loaded.
#
# Power intent: the staged design UPF (<work>/upf1/upf/<design>.upf) parsed
# with oss_upf_parse (the run's ::oss_upf is saved and restored) + the odb
# power domains / isolation strategies read_upf stored. Domain of an instance:
# its region group's domain, else the longest create_power_domain -elements
# prefix, else the scope (top) domain. A domain is switchable when its primary
# power has an "off" add_port_state or is a create_power_switch output.
# Interface cells: tech(<track>,isolation|level_shifter|power_switch) plus the
# lib cells the UPF names (use_interface_cell / map_power_switch).
# Block ports are the parent's side of a crossing and are not checked here.
#
# Not produced (no open-source engine measures them; the checks stay NA):
#   power_state_coverage  POWER_0012  — power-aware simulation coverage
#   corruption_analysis   POWER_0013  — power-aware simulation / MV corruption analysis
#   sleep_wakeup_sequence POWER_0014  — dynamic power-sequence verification
#   esd_path_check        POWER_0019  — ESD path analysis (PERC-class tool)
#   power_gating_leakage  POWER_0020  — off-state (switch residual) leakage: not in liberty / report_power
# ═══════════════════════════════════════════════════════════════════════════════

# tech(<track>,<key>) or "" when unset / empty (oss_trk errors on empty).
proc oss_pw_trk {key} {
    if {[catch {oss_trk $key} _v]} { return "" }
    return $_v
}

# Value following option <opt> in a UPF command arg list, or "".
proc oss_pw_opt {args_list opt} {
    set _k [lsearch -exact $args_list $opt]
    if {$_k < 0} { return "" }
    return [lindex $args_list [expr {$_k + 1}]]
}

# Every value of a repeatable option (-state {...} -state {...}).
proc oss_pw_opts {args_list opt} {
    set _out {}
    for {set _i 0} {$_i < [llength $args_list] - 1} {incr _i} {
        if {[lindex $args_list $_i] eq $opt} { lappend _out [lindex $args_list [incr _i]] }
    }
    return $_out
}

# Build ::oss_pw(...) from the parsed UPF + odb: domains, supplies, states,
# interface-cell masters, instance → domain.
proc oss_pw_model {} {
    global oss_upf oss_pw
    array unset oss_pw
    set _blk [ord::get_db_block]
    set oss_pw(domains) $oss_upf(domains)
    set oss_pw(top) [expr {[info exists oss_upf(top_domain)] ? $oss_upf(top_domain) : ""}]
    # supply port states (add_port_state) → voltage, can-be-off
    foreach _c $oss_upf(skipped) {
        if {[lindex $_c 0] ne "add_port_state"} continue
        set _p [lindex $_c 1]
        foreach _s [oss_pw_opts [lrange $_c 2 end] -state] {
            lassign $_s _sn _sv
            if {[string tolower $_sv] eq "off"} { set oss_pw(off,$_p) 1 } \
            elseif {[string is double -strict $_sv]} {
                if {![info exists oss_pw(volt,$_p)] || $_sv > $oss_pw(volt,$_p)} { set oss_pw(volt,$_p) $_sv }
            }
        }
    }
    # interface strategies / lib cells
    set oss_pw(iso_cells) [oss_pw_trk isolation]
    set oss_pw(ls_cells)  [oss_pw_trk level_shifter]
    set oss_pw(sw_cells)  [oss_pw_trk power_switch]
    set oss_pw(switched_nets) {}
    set _iso_strat {}; set _ls_strat {}
    foreach _c $oss_upf(forward) {
        switch -- [lindex $_c 0] {
            set_isolation     { lappend _iso_strat [lindex $_c 1] }
            set_level_shifter { lappend _ls_strat  [lindex $_c 1] }
            create_power_switch {
                set _o [oss_pw_opt $_c -output_supply_port]
                if {[llength $_o] > 1} { lappend oss_pw(switched_nets) [lindex $_o 1] }
            }
            map_power_switch { lappend oss_pw(sw_cells) {*}[oss_pw_opt $_c -lib_cells] }
        }
    }
    foreach _c $oss_upf(forward) {
        if {[lindex $_c 0] ne "use_interface_cell"} continue
        set _st [oss_pw_opt $_c -strategy]
        set _lc [oss_pw_opt $_c -lib_cells]
        if {[lsearch -exact $_ls_strat $_st] >= 0} { lappend oss_pw(ls_cells) {*}$_lc } \
        else { lappend oss_pw(iso_cells) {*}$_lc }
    }
    foreach _k {iso_cells ls_cells sw_cells} { set oss_pw($_k) [lsort -unique $oss_pw($_k)] }
    # per domain: primary supplies, switchable, voltage, area, region group
    foreach _d $oss_pw(domains) {
        set _pw [expr {[info exists oss_upf(power,$_d)] ? $oss_upf(power,$_d) : ""}]
        set oss_pw(pwr,$_d) $_pw
        set oss_pw(gnd,$_d) [expr {[info exists oss_upf(ground,$_d)] ? $oss_upf(ground,$_d) : ""}]
        set oss_pw(sw,$_d) [expr {$_pw ne "" && ([info exists oss_pw(off,$_pw)] || [lsearch -exact $oss_pw(switched_nets) $_pw] >= 0)}]
        set oss_pw(volt,$_d) [expr {[info exists oss_pw(volt,$_pw)] ? $oss_pw(volt,$_pw) : ""}]
        set oss_pw(el,$_d) {}
        foreach _e $oss_upf(elements,$_d) { if {$_e ne "."} { lappend oss_pw(el,$_d) $_e } }
    }
    # no scope domain (lint error): instances fall into an empty pseudo-domain
    foreach _k {pwr gnd volt el} { set oss_pw($_k,) "" }
    set oss_pw(sw,) 0
    foreach _pd [$_blk getPowerDomains] {
        set _d [$_pd getName]
        lassign [$_pd getArea] _ok _r
        if {$_ok && [$_r xMax] > [$_r xMin] && [$_r yMax] > [$_r yMin]} {
            set oss_pw(area,$_d) [list [$_r xMin] [$_r yMin] [$_r xMax] [$_r yMax]]
        }
        set _g [$_pd getGroup]
        if {$_g ne "NULL"} { set oss_pw(group,[$_g getName]) $_d }
    }
    array set oss_pw {}
}

proc oss_pw_inst_domain {inst} {
    global oss_pw
    set _n [$inst getName]
    if {[info exists oss_pw(dom,$_n)]} { return $oss_pw(dom,$_n) }
    set _g [$inst getGroup]
    set _best $oss_pw(top); set _len -1
    if {$_g ne "NULL" && [info exists oss_pw(group,[$_g getName])]} {
        set _best $oss_pw(group,[$_g getName])
    } else {
        foreach _d $oss_pw(domains) {
            foreach _e $oss_pw(el,$_d) {
                if {($_n eq $_e || [string first "$_e/" $_n] == 0) && [string length $_e] > $_len} {
                    set _best $_d; set _len [string length $_e]
                }
            }
        }
    }
    set oss_pw(dom,$_n) $_best
    return $_best
}

proc oss_pw_sw {d} { global oss_pw; return [expr {$d ne "" && [info exists oss_pw(sw,$d)] && $oss_pw(sw,$d)}] }
proc oss_pw_is {kind master} { global oss_pw; return [expr {[lsearch -exact $oss_pw(${kind}_cells) $master] >= 0}] }

# liberty is_buffer / is_inverter of a master (cached)
proc oss_pw_is_buf {master} {
    global oss_pw
    if {![info exists oss_pw(buf,$master)]} {
        set _lc [lindex [get_lib_cells -quiet */$master] 0]
        set oss_pw(buf,$master) [expr {$_lc ne "" && ([$_lc is_buffer] || [$_lc is_inverter])}]
    }
    return $oss_pw(buf,$master)
}

# Signal driver of a net: {inst} | {port} | {} (undriven)
proc oss_pw_driver {net} {
    foreach _it [$net getITerms] { if {[$_it isOutputSignal]} { return [list inst [$_it getInst]] } }
    foreach _bt [$net getBTerms] { if {[$_bt getIoType] in {INPUT INOUT}} { return [list port $_bt] } }
    return {}
}

proc oss_pw_num {v} { return [expr {[string is double -strict $v] ? $v : ""}] }

proc oss_checkgrp_power {stage} {
    global oss_upf oss_pw
    set _blk [ord::get_db_block]
    set _dbu [[ord::get_db_tech] getDbUnitsPerMicron]
    set _design [oss_get flow design_name]
    set _upf [lindex [glob -nocomplain "$::UPF_DIR/${_design}.upf" "$::UPF_DIR/*.upf"] 0]
    if {$_upf eq ""} { handle_warning "power checks: no UPF staged in $::UPF_DIR — power-intent checks not written"; return }

    # The stage's ::oss_upf (if any) is restored after the checks.
    set _saved [array get oss_upf]
    set _rc [catch {
        if {[catch {oss_upf_parse $_upf} _e]} {
            # power_intent_lint: the UPF does not even evaluate
            oss_check_line report_upf.rpt "# UPF $_upf does not evaluate: $_e"
            oss_check_line report_upf.rpt "UPF Lint Errors : 1"
            return
        }
        oss_pw_model
        set _mv check_mv.rpt; set _pd check_power_domains.rpt; set _uf report_upf.rpt
        oss_check_line $_uf "# UPF: $_upf"
        foreach _d $oss_pw(domains) {
            set _line "# domain $_d: primary $oss_pw(pwr,$_d)/$oss_pw(gnd,$_d) switchable=$oss_pw(sw,$_d) voltage=$oss_pw(volt,$_d) elements=[expr {$oss_pw(el,$_d) eq {} ? {(scope)} : $oss_pw(el,$_d)}]"
            oss_check_line $_mv $_line; oss_check_line $_pd $_line
        }
        oss_check_line $_mv "# interface cells: isolation={$oss_pw(iso_cells)} level_shifter={$oss_pw(ls_cells)} switch={$oss_pw(sw_cells)}"

        # ── power_intent_lint POWER_0015: structural UPF lint ───────────────
        # undefined domain / net / port / strategy references, domains without
        # primary supplies, duplicate domains, PST states vs supplies.
        set _lint_msgs {}
        if {$oss_pw(top) eq ""} { lappend _lint_msgs "no create_power_domain -include_scope" }
        foreach _d [lsort -unique $oss_pw(domains)] {
            if {[llength [lsearch -all -exact $oss_pw(domains) $_d]] > 1} { lappend _lint_msgs "domain $_d defined twice" }
            if {$oss_pw(pwr,$_d) eq "" || $oss_pw(gnd,$_d) eq ""} { lappend _lint_msgs "domain $_d has no primary power/ground (set_domain_supply_net)" }
            foreach _n [list $oss_pw(pwr,$_d) $oss_pw(gnd,$_d)] {
                if {$_n ne "" && [lsearch -exact $oss_upf(nets) $_n] < 0} { lappend _lint_msgs "domain $_d supply net $_n not created" }
            }
        }
        foreach {_n _i _p} $oss_upf(conn) {
            if {[lsearch -exact $oss_upf(nets) $_n] < 0} { lappend _lint_msgs "connect_supply_net $_n: net not created" }
        }
        set _states {}
        foreach _c $oss_upf(skipped) {
            switch -- [lindex $_c 0] {
                add_port_state {
                    set _p [lindex $_c 1]
                    if {[lsearch -exact $oss_upf(ports) $_p] < 0 && [lsearch -exact $oss_upf(nets) $_p] < 0} {
                        lappend _lint_msgs "add_port_state $_p: no such supply port"
                    }
                    foreach _s [oss_pw_opts [lrange $_c 2 end] -state] { lappend _states $_p,[lindex $_s 0] }
                }
            }
        }
        array set _pst {}
        foreach _c $oss_upf(skipped) {
            switch -- [lindex $_c 0] {
                create_pst {
                    set _sup [oss_pw_opt $_c -supplies]
                    set _pst([lindex $_c 1]) $_sup
                    foreach _s $_sup {
                        if {[lsearch -exact $oss_upf(ports) $_s] < 0 && [lsearch -exact $oss_upf(nets) $_s] < 0} {
                            lappend _lint_msgs "create_pst [lindex $_c 1]: supply $_s not defined"
                        }
                    }
                }
                add_pst_state {
                    set _pn [oss_pw_opt $_c -pst]
                    set _st [oss_pw_opt $_c -state]
                    if {![info exists _pst($_pn)]} { lappend _lint_msgs "add_pst_state [lindex $_c 1]: pst $_pn not created"; continue }
                    if {[llength $_st] != [llength $_pst($_pn)]} {
                        lappend _lint_msgs "add_pst_state [lindex $_c 1]: [llength $_st] states for [llength $_pst($_pn)] supplies"; continue
                    }
                    foreach _s $_pst($_pn) _v $_st {
                        if {[lsearch -exact $_states $_s,$_v] < 0} { lappend _lint_msgs "add_pst_state [lindex $_c 1]: state $_v of $_s not defined by add_port_state" }
                    }
                }
            }
        }
        set _strats {}
        foreach _c $oss_upf(forward) {
            set _cmd [lindex $_c 0]
            if {$_cmd in {set_isolation set_level_shifter}} { lappend _strats [lindex $_c 1] }
            if {$_cmd in {set_isolation set_level_shifter create_power_switch use_interface_cell set_domain_area set_domain_voltage}} {
                set _d [oss_pw_opt $_c -domain]
                if {$_cmd in {set_domain_area set_domain_voltage}} { set _d [lindex $_c 1] }
                if {$_d ne "" && [lsearch -exact $oss_pw(domains) $_d] < 0} { lappend _lint_msgs "$_cmd [lindex $_c 1]: domain $_d not created" }
            }
        }
        foreach _c $oss_upf(forward) {
            if {[lindex $_c 0] eq "use_interface_cell"} {
                set _st [oss_pw_opt $_c -strategy]
                if {$_st ne "" && [lsearch -exact $_strats $_st] < 0} { lappend _lint_msgs "use_interface_cell [lindex $_c 1]: strategy $_st not defined" }
            }
        }
        foreach _m $_lint_msgs { oss_check_line $_uf "# lint: $_m" }
        oss_check_line $_uf "UPF Lint Errors : [llength $_lint_msgs]"

        # ── signal crossings between domains (instance drivers → loads) ─────
        set _miss_iso 0; set _miss_ls 0; set _unprot 0; set _aobuf 0
        set _ex {}
        foreach _net [$_blk getNets] {
            if {[$_net getSigType] in {POWER GROUND}} continue
            set _drv [oss_pw_driver $_net]
            if {[lindex $_drv 0] ne "inst"} continue
            set _di [lindex $_drv 1]
            set _dd [oss_pw_inst_domain $_di]
            set _dm [[$_di getMaster] getName]
            foreach _it [$_net getITerms] {
                if {![$_it isInputSignal]} continue
                set _li [$_it getInst]
                set _ld [oss_pw_inst_domain $_li]
                if {$_ld eq $_dd} continue
                set _lm [[$_li getMaster] getName]
                set _need_iso [expr {[oss_pw_sw $_dd] && $oss_pw(pwr,$_dd) ne $oss_pw(pwr,$_ld)}]
                set _need_ls  [expr {$oss_pw(volt,$_dd) ne "" && $oss_pw(volt,$_ld) ne "" && $oss_pw(volt,$_dd) != $oss_pw(volt,$_ld)}]
                set _bad_iso [expr {$_need_iso && ![oss_pw_is iso $_dm] && ![oss_pw_is iso $_lm]}]
                set _bad_ls  [expr {$_need_ls  && ![oss_pw_is ls  $_dm] && ![oss_pw_is ls  $_lm]}]
                incr _miss_iso $_bad_iso
                incr _miss_ls  $_bad_ls
                if {$_bad_iso || $_bad_ls} {
                    incr _unprot
                    if {[llength $_ex] < 10} { lappend _ex "[$_net getName]: $_dd -> $_ld ([$_li getName]/[[$_it getMTerm] getName])" }
                }
            }
        }
        foreach _e $_ex { oss_check_line $_mv "# unprotected crossing: $_e" }
        # missing_isolation POWER_0001: switchable-domain driver → other-supply load, no isolation cell on either end
        oss_check_line $_mv "Missing Isolation Cells : $_miss_iso"
        # missing_level_shifters POWER_0002: crossing between domains of different voltage, no level shifter
        oss_check_line $_mv "Missing Level Shifters : $_miss_ls"
        # power_domain_crossing POWER_0007: crossings (load pins) missing isolation and/or level shifting
        oss_check_line $_mv "Unprotected Crossings : $_unprot"

        # ── always-on control and buffering ─────────────────────────────────
        # always_on_violations POWER_0004: isolation cells with no input from an
        # always-on source (enable driven from switchable logic) + power-switch
        # controls driven from switchable logic (other than a switch ack chain).
        # ao_buffer_usage POWER_0017: non-always-on buffers/inverters sitting in a
        # switchable domain that carry an always-on signal (AO driver → AO load).
        set _aov 0; set _iso_en_pins {}
        set _sw_insts {}; set _ls_insts {}
        foreach _inst [$_blk getInsts] {
            set _m [[$_inst getMaster] getName]
            set _d [oss_pw_inst_domain $_inst]
            if {[oss_pw_is sw $_m]} { lappend _sw_insts $_inst }
            if {[oss_pw_is ls $_m]} { lappend _ls_insts $_inst }
            if {[oss_pw_is iso $_m]} {
                set _ao_in 0
                foreach _it [$_inst getITerms] {
                    if {![$_it isInputSignal] || [$_it getNet] eq "NULL"} continue
                    set _drv [oss_pw_driver [$_it getNet]]
                    if {[lindex $_drv 0] eq "port" || ([lindex $_drv 0] eq "inst" && ![oss_pw_sw [oss_pw_inst_domain [lindex $_drv 1]]])} {
                        incr _ao_in
                        lappend _iso_en_pins "[$_inst getName]/[[$_it getMTerm] getName]"
                    }
                }
                if {$_ao_in == 0} { incr _aov; if {$_aov <= 10} { oss_check_line $_mv "# always-on: isolation cell [$_inst getName] enable driven from switchable logic" } }
            } elseif {[oss_pw_sw $_d] && [oss_pw_is_buf $_m]} {
                set _in_ao 0; set _out_ao 0
                foreach _it [$_inst getITerms] {
                    if {[$_it getNet] eq "NULL"} continue
                    if {[$_it isInputSignal]} {
                        set _drv [oss_pw_driver [$_it getNet]]
                        if {[lindex $_drv 0] eq "inst" && ![oss_pw_sw [oss_pw_inst_domain [lindex $_drv 1]]]} { set _in_ao 1 }
                    } elseif {[$_it isOutputSignal]} {
                        foreach _l [[$_it getNet] getITerms] {
                            if {[$_l isInputSignal] && ![oss_pw_sw [oss_pw_inst_domain [$_l getInst]]]} { set _out_ao 1 }
                        }
                    }
                }
                if {$_in_ao && $_out_ao} { incr _aobuf; if {$_aobuf <= 10} { oss_check_line $_mv "# AO buffer: [$_inst getName] ($_m) in switchable $_d carries an always-on signal" } }
            }
        }
        set _chain 0
        foreach _sw $_sw_insts {
            set _ins 0; set _outs 0
            foreach _it [$_sw getITerms] {
                if {[$_it isInputSignal]} {
                    incr _ins
                    if {[$_it getNet] eq "NULL"} { incr _chain; oss_check_line $_pd "# switch chain: [$_sw getName]/[[$_it getMTerm] getName] control unconnected"; continue }
                    set _drv [oss_pw_driver [$_it getNet]]
                    if {[lindex $_drv 0] eq "inst"} {
                        set _di [lindex $_drv 1]
                        if {![oss_pw_is sw [[$_di getMaster] getName]] && [oss_pw_sw [oss_pw_inst_domain $_di]]} {
                            incr _aov; if {$_aov <= 10} { oss_check_line $_mv "# always-on: switch [$_sw getName] control driven from switchable [$_di getName]" }
                        }
                    } elseif {$_drv eq ""} { incr _chain; oss_check_line $_pd "# switch chain: [$_sw getName] control net undriven" }
                } elseif {[$_it isOutputSignal]} {
                    incr _outs
                    if {[$_it getNet] eq "NULL"} { incr _chain; oss_check_line $_pd "# switch chain: [$_sw getName]/[[$_it getMTerm] getName] ack unconnected"; continue }
                    # ack fans out to more than one switch control: a fork, not a chain
                    set _n 0
                    foreach _l [[$_it getNet] getITerms] { if {[$_l isInputSignal] && [oss_pw_is sw [[[$_l getInst] getMaster] getName]]} { incr _n } }
                    if {$_n > 1} { incr _chain; oss_check_line $_pd "# switch chain: [$_sw getName] ack drives $_n switches" }
                }
            }
        }
        oss_check_line $_mv "Always-On Violations : $_aov"
        oss_check_line $_mv "AO Buffer Violations : $_aobuf"

        # isolation_enable_timing POWER_0010: isolation enable pins (inputs fed
        # from an always-on source) with negative setup or hold slack.
        set _ien 0
        foreach _p $_iso_en_pins {
            set _pin [get_pins -quiet $_p]
            if {$_pin eq ""} continue
            foreach _prop {slack_max slack_min} {
                if {![catch {get_property $_pin $_prop} _s] && [oss_pw_num $_s] ne "" && $_s < 0} {
                    incr _ien; oss_check_line $_mv "# isolation enable: $_p $_prop $_s"; break
                }
            }
        }
        oss_check_line $_mv "# isolation enable pins checked: [llength $_iso_en_pins]"
        oss_check_line $_mv "Isolation Enable Violations : $_ien"

        # level_shifter_placement POWER_0011: level shifters outside their
        # domain's area, or inside another domain's area.
        set _lsp 0
        foreach _ls $_ls_insts {
            set _bb [$_ls getBBox]
            set _d [oss_pw_inst_domain $_ls]
            set _bad 0
            if {[info exists oss_pw(area,$_d)]} {
                lassign $oss_pw(area,$_d) _x0 _y0 _x1 _y1
                if {[$_bb xMin] < $_x0 || [$_bb yMin] < $_y0 || [$_bb xMax] > $_x1 || [$_bb yMax] > $_y1} { set _bad 1 }
            }
            foreach _o $oss_pw(domains) {
                if {$_o eq $_d || ![info exists oss_pw(area,$_o)]} continue
                lassign $oss_pw(area,$_o) _x0 _y0 _x1 _y1
                if {[$_bb xMax] > $_x0 && [$_bb xMin] < $_x1 && [$_bb yMax] > $_y0 && [$_bb yMin] < $_y1} { set _bad 1 }
            }
            if {$_bad} { incr _lsp; oss_check_line $_mv "# level shifter misplaced: [$_ls getName] (domain $_d)" }
        }
        oss_check_line $_mv "# level shifters: [llength $_ls_insts]"
        oss_check_line $_mv "Level Shifter Placement Violations : $_lsp"

        # retention_check POWER_0005: set_retention strategies — undefined
        # domain, save/restore signal not in the netlist, no retention cell
        # declared (tech(<track>,retention)), or registers in scope not mapped
        # to a retention cell.
        set _ret_cells [oss_pw_trk retention]
        set _rerr 0; set _nret 0
        foreach _c $oss_upf(skipped) {
            if {[lindex $_c 0] ne "set_retention"} continue
            incr _nret
            set _rn [lindex $_c 1]
            set _rd [oss_pw_opt $_c -domain]
            if {[lsearch -exact $oss_pw(domains) $_rd] < 0} { incr _rerr; oss_check_line $_mv "# retention $_rn: domain $_rd not created"; continue }
            foreach _o {-save_signal -restore_signal} {
                set _sig [lindex [oss_pw_opt $_c $_o] 0]
                if {$_sig ne "" && [$_blk findNet $_sig] eq "NULL" && [$_blk findBTerm $_sig] eq "NULL"} {
                    incr _rerr; oss_check_line $_mv "# retention $_rn: $_o $_sig not in the netlist"
                }
            }
            if {$_ret_cells eq ""} { incr _rerr; oss_check_line $_mv "# retention $_rn: no retention cell declared (tech([oss_track],retention))"; continue }
            set _rel [oss_pw_opt $_c -elements]
            foreach _r [all_registers -cells] {
                set _inst [$_blk findInst [get_full_name $_r]]
                if {$_inst eq "NULL" || [oss_pw_inst_domain $_inst] ne $_rd} continue
                if {$_rel ne ""} {
                    set _in 0
                    foreach _e $_rel { if {[$_inst getName] eq $_e || [string first "$_e/" [$_inst getName]] == 0} { set _in 1 } }
                    if {!$_in} continue
                }
                if {[lsearch -exact $_ret_cells [[$_inst getMaster] getName]] < 0} { incr _rerr }
            }
        }
        oss_check_line $_mv "# retention strategies: $_nret"
        oss_check_line $_mv "Retention Errors : $_rerr"

        # upf_implementation_match POWER_0006: UPF intent vs the database —
        # domains missing in odb, domain elements not in the netlist, domain
        # supply nets missing, connect_supply_net pins on another net,
        # instances whose supply pins are not on their domain's primary nets,
        # interface / switch lib cells with no instance.
        set _mm 0
        set _odb_doms [lmap _x [$_blk getPowerDomains] {$_x getName}]
        foreach _d $oss_pw(domains) {
            if {[lsearch -exact $_odb_doms $_d] < 0} { incr _mm; oss_check_line $_uf "# mismatch: domain $_d not in the database" }
            foreach _e $oss_pw(el,$_d) {
                if {[$_blk findInst $_e] ne "NULL"} continue
                set _f 0
                foreach _i [$_blk getInsts] { if {[string first "$_e/" [$_i getName]] == 0} { set _f 1; break } }
                if {!$_f} { incr _mm; oss_check_line $_uf "# mismatch: domain $_d element $_e not in the netlist" }
            }
            foreach _n [list $oss_pw(pwr,$_d) $oss_pw(gnd,$_d)] {
                if {$_n ne "" && [$_blk findNet $_n] eq "NULL"} { incr _mm; oss_check_line $_uf "# mismatch: domain $_d supply net $_n not in the database" }
            }
        }
        array set _conn {}
        foreach {_n _i _p} $oss_upf(conn) {
            set _conn($_i) 1
            set _inst [$_blk findInst $_i]
            set _it [expr {$_inst eq "NULL" ? "NULL" : [$_inst findITerm $_p]}]
            if {$_it eq "NULL"} { incr _mm; oss_check_line $_uf "# mismatch: connect_supply_net $_n -ports $_i/$_p: pin not in the netlist"; continue }
            set _on [$_it getNet]
            if {$_on eq "NULL" || [$_on getName] ne $_n} {
                incr _mm; oss_check_line $_uf "# mismatch: $_i/$_p on [expr {$_on eq {NULL} ? {no net} : [$_on getName]}], UPF says $_n"
            }
        }
        set _wrong 0
        foreach _inst [$_blk getInsts] {
            if {[info exists _conn([$_inst getName])]} continue
            set _d [oss_pw_inst_domain $_inst]
            foreach _it [$_inst getITerms] {
                set _st [[$_it getMTerm] getSigType]
                if {$_st ni {POWER GROUND}} continue
                set _want [expr {$_st eq "POWER" ? $oss_pw(pwr,$_d) : $oss_pw(gnd,$_d)}]
                set _on [$_it getNet]
                # unconnected supply pins are counted by supply_net_connectivity
                if {$_want ne "" && $_on ne "NULL" && [$_on getName] ne $_want} {
                    incr _wrong
                    if {$_wrong <= 10} { oss_check_line $_uf "# mismatch: [$_inst getName]/[[$_it getMTerm] getName] on [$_on getName], domain $_d primary $_want" }
                    break
                }
            }
        }
        incr _mm $_wrong
        set _used {}
        foreach _i [$_blk getInsts] { lappend _used [[$_i getMaster] getName] }
        set _used [lsort -unique $_used]
        foreach _c $oss_upf(forward) {
            if {[lindex $_c 0] ni {use_interface_cell map_power_switch}} continue
            set _any 0
            foreach _lc [oss_pw_opt $_c -lib_cells] { if {[lsearch -exact -sorted $_used $_lc] >= 0} { set _any 1 } }
            if {!$_any} { incr _mm; oss_check_line $_uf "# mismatch: [lindex $_c 0] [lindex $_c 1]: no instance of [oss_pw_opt $_c -lib_cells]" }
        }
        oss_check_line $_uf "UPF Mismatches : $_mm"

        # supply_net_connectivity POWER_0008: supply pins with no net + (power
        # grid built) supply nets with loads but no grid shapes, or whose grid
        # check_power_grid finds disconnected.
        set _serr 0
        foreach _inst [$_blk getInsts] {
            foreach _it [$_inst getITerms] {
                if {[[$_it getMTerm] getSigType] in {POWER GROUND} && [$_it getNet] eq "NULL"} {
                    incr _serr
                    if {$_serr <= 10} { oss_check_line $_pd "# supply: [$_inst getName]/[[$_it getMTerm] getName] unconnected" }
                }
            }
        }
        set _snets [lsort -unique [concat $oss_upf(nets) [expr {[catch {oss_get project power,rail_nets} _r] ? {} : $_r}]]]
        if {[oss_pdn_enabled]} {
            foreach _n $_snets {
                set _net [$_blk findNet $_n]
                if {$_net eq "NULL" || [llength [$_net getITerms]] == 0} continue
                if {[llength [$_net getSWires]] == 0} { incr _serr; oss_check_line $_pd "# supply: $_n has loads but no power-grid shapes"; continue }
                if {[catch {check_power_grid -net $_n} _ok] || $_ok == 0} { incr _serr; oss_check_line $_pd "# supply: $_n power grid not connected (check_power_grid)" }
            }
        } else {
            oss_check_line $_pd "# supply: power grid off (project(pdn,enable)) — logical supply connections only"
        }
        oss_check_line $_pd "Supply Connectivity Errors : $_serr"

        # power_switch_chain POWER_0009: switch controls unconnected/undriven,
        # acks unconnected or forking to several switches.
        oss_check_line $_pd "# power switches: [llength $_sw_insts]"
        oss_check_line $_pd "Switch Chain Errors : $_chain"

        # power_switch_distance POWER_0003 (um): farthest instance of a
        # switchable domain from its nearest switch of that domain. No switch
        # in the block (domain switched by the parent) → not measurable here.
        set _maxd ""
        foreach _d $oss_pw(domains) {
            if {![oss_pw_sw $_d]} continue
            set _pts {}
            foreach _sw $_sw_insts {
                if {[oss_pw_inst_domain $_sw] ne $_d} continue
                set _b [$_sw getBBox]
                lappend _pts [expr {([$_b xMin] + [$_b xMax]) / 2.0}] [expr {([$_b yMin] + [$_b yMax]) / 2.0}]
            }
            if {[llength $_pts] == 0} continue
            foreach _inst [$_blk getInsts] {
                if {[oss_pw_inst_domain $_inst] ne $_d || [oss_pw_is sw [[$_inst getMaster] getName]]} continue
                set _b [$_inst getBBox]
                set _cx [expr {([$_b xMin] + [$_b xMax]) / 2.0}]; set _cy [expr {([$_b yMin] + [$_b yMax]) / 2.0}]
                set _best ""
                foreach {_sx _sy} $_pts {
                    set _dist [expr {abs($_cx - $_sx) + abs($_cy - $_sy)}]
                    if {$_best eq "" || $_dist < $_best} { set _best $_dist }
                }
                if {$_maxd eq "" || $_best > $_maxd} { set _maxd $_best }
            }
        }
        if {$_maxd eq ""} {
            oss_check_line $_pd "# Max Switch Distance: not measurable — no power switch cell in this block (switchable domains are switched by the parent)"
        } else {
            oss_check_line $_pd "Max Switch Distance : [format %.2f [expr {$_maxd / double($_dbu)}]]"
        }

        # voltage_area_overlap POWER_0016: domain areas (set_domain_area) that overlap.
        set _ov 0; set _ad [lsort [array names oss_pw area,*]]
        for {set _i 0} {$_i < [llength $_ad]} {incr _i} {
            for {set _j [expr {$_i + 1}]} {$_j < [llength $_ad]} {incr _j} {
                lassign $oss_pw([lindex $_ad $_i]) _a0 _b0 _a1 _b1
                lassign $oss_pw([lindex $_ad $_j]) _c0 _d0 _c1 _d1
                if {$_a1 > $_c0 && $_a0 < $_c1 && $_b1 > $_d0 && $_b0 < $_d1} {
                    incr _ov; oss_check_line $_pd "# voltage areas overlap: [lindex $_ad $_i] / [lindex $_ad $_j]"
                }
            }
        }
        oss_check_line $_pd "# voltage areas: [llength $_ad]"
        oss_check_line $_pd "Voltage Area Overlaps : $_ov"

        # power_domain_boundary_cells POWER_0018: row ends (core and domain
        # edges, rows cut at macros) without the boundary (endcap) cell
        # tech(<track>,endcap).
        set _ecm [oss_pw_trk endcap]
        if {$_ecm eq ""} {
            oss_check_line $_pd "# Missing Boundary Cells: not measurable — tech([oss_track],endcap) not set"
        } else {
            array set _ec {}
            foreach _inst [$_blk getInsts] {
                if {[[$_inst getMaster] getName] ne $_ecm} continue
                set _b [$_inst getBBox]
                set _ec(L,[$_b yMin],[$_b xMin]) 1
                set _ec(R,[$_b yMin],[$_b xMax]) 1
            }
            set _mbc 0
            foreach _row [$_blk getRows] {
                set _b [$_row getBBox]
                foreach {_s _x} [list L [$_b xMin] R [$_b xMax]] {
                    if {![info exists _ec($_s,[$_b yMin],$_x)]} {
                        incr _mbc
                        if {$_mbc <= 10} { oss_check_line $_pd "# boundary cell missing: [$_row getName] [expr {$_s eq {L} ? {left} : {right}}] end" }
                    }
                }
            }
            oss_check_line $_pd "# rows: [llength [$_blk getRows]]  boundary cell: $_ecm"
            oss_check_line $_pd "Missing Boundary Cells : $_mbc"
        }
    } _err]
    array unset oss_upf
    array set oss_upf $_saved
    if {$_rc == 1} { error $_err $::errorInfo }
}
