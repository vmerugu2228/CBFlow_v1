#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow shared lowpower_fc.tcl — Synopsys Fusion Compiler low-power insertion
# Standalone recipe sourced by the `insert_low_power_cells` flow_proc in
# place_fc.tcl. Single canonical copy lives under cmds/PNR/synopsys/fc/<ver>/;
# the synth_pnr copy of place_fc.tcl (when symlinked or hand-synced) reaches
# the same recipe from PNR's tree.
#
# FC-RM source of truth: Y-2026.03 low-power flow inside init_design.tcl /
# place_opt.tcl — UPF-driven insertion of power switches, isolation cells,
# level shifters, always-on buffers, plus check_mv_design.
#
# Prerequisite: the UPF file MUST already be loaded earlier in the flow
# (init_design's load_constraints does `load_upf`). This recipe enables FC's
# UPF implementation engine and runs the insertion checks/reports — it does
# NOT re-load the UPF.
#
# Caller protocol: the flow_proc that sources this recipe sets these globals.
# Required:   ::LOWPOWER_STAGE                 e.g. "place"
# Optional (sensible defaults):
#   ::LOWPOWER_ENABLE_PWR_SWITCH   "true"
#   ::LOWPOWER_ENABLE_ISOLATION    "true"
#   ::LOWPOWER_ENABLE_LEVEL_SHIFTER "true"
#   ::LOWPOWER_ENABLE_AON_BUFFER   "true"
#   ::LOWPOWER_PWR_SWITCH_LIBCELL  ""       (lib_cell pattern, optional)
#   ::LOWPOWER_REPORTS_DIR         ""       — empty → ::REPORTS_DIR/lowpower
# ═══════════════════════════════════════════════════════════════════════════════

# ── Input validation + defaults ──────────────────────────────────────────────
if {![info exists ::LOWPOWER_STAGE] || $::LOWPOWER_STAGE eq ""} {
    return -code error "lowpower_fc.tcl: required global ::LOWPOWER_STAGE is not set"
}

foreach {_var _default} {
    LOWPOWER_ENABLE_PWR_SWITCH    "true"
    LOWPOWER_ENABLE_ISOLATION     "true"
    LOWPOWER_ENABLE_LEVEL_SHIFTER "true"
    LOWPOWER_ENABLE_AON_BUFFER    "true"
    LOWPOWER_PWR_SWITCH_LIBCELL   ""
    LOWPOWER_REPORTS_DIR          ""
} {
    if {![info exists ::$_var] || [set ::$_var] eq ""} {
        set ::$_var $_default
    }
}

if {$::LOWPOWER_REPORTS_DIR eq ""} {
    set ::LOWPOWER_REPORTS_DIR "$::REPORTS_DIR/lowpower"
}
file mkdir $::LOWPOWER_REPORTS_DIR

handle_info "─── FC low-power insertion: stage=$::LOWPOWER_STAGE ───"
handle_info "  Power switches:    $::LOWPOWER_ENABLE_PWR_SWITCH"
handle_info "  Isolation cells:   $::LOWPOWER_ENABLE_ISOLATION"
handle_info "  Level shifters:    $::LOWPOWER_ENABLE_LEVEL_SHIFTER"
handle_info "  Always-on buffers: $::LOWPOWER_ENABLE_AON_BUFFER"
handle_info "  PSW lib_cell:      $::LOWPOWER_PWR_SWITCH_LIBCELL"
handle_info "  Reports dir:       $::LOWPOWER_REPORTS_DIR"

# ── Enable UPF implementation engine ─────────────────────────────────────────
# Master switch — tells FC to physically realize what UPF declares (power
# domains, switches, iso strategies, level-shifter strategies).
handle_info "set_app_options -name design.upf.enable_implementation -value true"
set_app_options -name design.upf.enable_implementation -value true

# ── Power switch insertion ───────────────────────────────────────────────────
if {[string is true -strict $::LOWPOWER_ENABLE_PWR_SWITCH]} {
    handle_info "Enabling power switch insertion (compile/opt will insert per UPF strategies)"
    set_app_options -name place.coarse.enable_power_switch -value true
    set_app_options -name opt.power_switch.enable_insertion -value true
    if {$::LOWPOWER_PWR_SWITCH_LIBCELL ne ""} {
        handle_info "Power switch lib cells: $::LOWPOWER_PWR_SWITCH_LIBCELL"
        set_app_options -name place.coarse.power_switch_lib_cells \
            -value $::LOWPOWER_PWR_SWITCH_LIBCELL
    }
}

# ── Isolation cell insertion ─────────────────────────────────────────────────
if {[string is true -strict $::LOWPOWER_ENABLE_ISOLATION]} {
    handle_info "Enabling isolation cell insertion at power-domain crossings"
    set_app_options -name mv.upf.isolation.auto_insert -value true
}

# ── Level shifter insertion ──────────────────────────────────────────────────
if {[string is true -strict $::LOWPOWER_ENABLE_LEVEL_SHIFTER]} {
    handle_info "Enabling level shifter insertion at voltage crossings"
    set_app_options -name mv.upf.level_shifter.auto_insert -value true
}

# ── Always-on buffer insertion ───────────────────────────────────────────────
if {[string is true -strict $::LOWPOWER_ENABLE_AON_BUFFER]} {
    handle_info "Enabling always-on buffer insertion"
    set_app_options -name place.opt.enable_always_on_buf_insertion -value true
}

# ── Commit UPF + validate the multi-voltage design ───────────────────────────
# commit_upf finalizes the UPF strategies onto the design. check_mv_design
# catches missing isolation strategies, illegal voltage crossings, etc.
handle_info "Committing UPF and checking multi-voltage design"
catch { commit_upf }
redirect -file $::LOWPOWER_REPORTS_DIR/check_mv_design.${::LOWPOWER_STAGE}.rpt {
    check_mv_design -verbose
}

# ── Reports: what got inserted / what UPF declared ───────────────────────────
redirect -file $::LOWPOWER_REPORTS_DIR/report_mv_design.${::LOWPOWER_STAGE}.rpt {
    report_mv_design
}
redirect -file $::LOWPOWER_REPORTS_DIR/report_power_switches.${::LOWPOWER_STAGE}.rpt {
    catch { report_power_switches }
}
redirect -file $::LOWPOWER_REPORTS_DIR/report_isolation_cells.${::LOWPOWER_STAGE}.rpt {
    catch { report_isolation_cells }
}
redirect -file $::LOWPOWER_REPORTS_DIR/report_level_shifters.${::LOWPOWER_STAGE}.rpt {
    catch { report_level_shifters }
}
redirect -file $::LOWPOWER_REPORTS_DIR/report_power_domain.${::LOWPOWER_STAGE}.rpt {
    catch { report_power_domain }
}

handle_info "─── FC low-power insertion completed: stage=$::LOWPOWER_STAGE ───"
handle_info "  Reports written to: $::LOWPOWER_REPORTS_DIR"
