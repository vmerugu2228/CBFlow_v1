#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow shared lowpower_fc.tcl — Synopsys Fusion Compiler low-power insertion
#
# Stage-aware. Two callers:
#   1. FP / powerplan_fc.tcl       — inserts power switches (PG cells) into
#                                    the power network. Only PSW work runs;
#                                    ISO/LS/AON are skipped (not yet placed).
#   2. PNR / SYNTH_PNR / place_fc.tcl  — inserts isolation cells, level
#                                    shifters, and always-on buffers, which
#                                    must coexist with the standard cells
#                                    during placement. PSW skipped (already
#                                    in the power network).
#
# Standalone recipe sourced by `insert_power_switches` (powerplan) and
# `insert_low_power_cells` (place) flow_procs. Single canonical copy lives
# under cmds/PNR/synopsys/fc/<ver>/.
#
# FC-RM source of truth: Y-2026.03 — PSW handled with the PG ring/strap pass;
# ISO/LS/AON inserted by compile_fusion / place_opt with app_options enabled.
#
# Prerequisite: UPF MUST already be loaded earlier in the flow (init_design's
# load_constraints does `load_upf`). This recipe enables FC's implementation
# engine + runs checks/reports — it does NOT re-load the UPF.
#
# Caller protocol: the flow_proc that sources this recipe sets these globals.
# Required:   ::LOWPOWER_STAGE                 "powerplan" | "place"
# Optional (sensible defaults):
#   ::LOWPOWER_ENABLE_PWR_SWITCH    "true"   (powerplan only)
#   ::LOWPOWER_ENABLE_ISOLATION     "true"   (place only)
#   ::LOWPOWER_ENABLE_LEVEL_SHIFTER "true"   (place only)
#   ::LOWPOWER_ENABLE_AON_BUFFER    "true"   (place only)
#   ::LOWPOWER_PWR_SWITCH_LIBCELL   ""       (powerplan only, optional)
#   ::LOWPOWER_REPORTS_DIR          ""       — empty → ::REPORTS_DIR/lowpower
# ═══════════════════════════════════════════════════════════════════════════════

# ── Input validation + defaults ──────────────────────────────────────────────
if {![info exists ::LOWPOWER_STAGE] || $::LOWPOWER_STAGE eq ""} {
    return -code error "lowpower_fc.tcl: required global ::LOWPOWER_STAGE is not set"
}
if {[lsearch -exact {powerplan place} $::LOWPOWER_STAGE] < 0} {
    return -code error "lowpower_fc.tcl: ::LOWPOWER_STAGE must be 'powerplan' or 'place', got '$::LOWPOWER_STAGE'"
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
handle_info "  Reports dir: $::LOWPOWER_REPORTS_DIR"

# ── Enable UPF implementation engine (both stages) ───────────────────────────
# Tells FC to physically realize what UPF declares (power domains, switches,
# iso strategies, level-shifter strategies, always-on buffers).
handle_info "set_app_options -name design.upf.enable_implementation -value true"
set_app_options -name design.upf.enable_implementation -value true

# ╔══════════════════════════════════════════════════════════════════════════╗
# ║ STAGE: powerplan — insert power switches (PG cells)                      ║
# ╚══════════════════════════════════════════════════════════════════════════╝
if {$::LOWPOWER_STAGE eq "powerplan"} {
    handle_info "  Power switches:  $::LOWPOWER_ENABLE_PWR_SWITCH"
    handle_info "  PSW lib_cell:    $::LOWPOWER_PWR_SWITCH_LIBCELL"

    if {[string is true -strict $::LOWPOWER_ENABLE_PWR_SWITCH]} {
        handle_info "Enabling power switch insertion in the power network"
        # FC implements UPF create_power_switch strategies during powerplan
        # when the coarse PSW insertion knob is true.
        set_app_options -name place.coarse.enable_power_switch -value true
        set_app_options -name opt.power_switch.enable_insertion -value true
        if {$::LOWPOWER_PWR_SWITCH_LIBCELL ne ""} {
            handle_info "Power switch lib cells: $::LOWPOWER_PWR_SWITCH_LIBCELL"
            set_app_options -name place.coarse.power_switch_lib_cells \
                -value $::LOWPOWER_PWR_SWITCH_LIBCELL
        }
    }

    # commit_upf finalizes UPF strategies; it's the canonical point after
    # PSW insertion to bake the power network into the design.
    handle_info "Committing UPF (post-PSW)"
    catch { commit_upf }

    # Validate the multi-voltage design after PSW insertion
    redirect -file $::LOWPOWER_REPORTS_DIR/check_mv_design.${::LOWPOWER_STAGE}.rpt {
        check_mv_design -verbose
    }

    # Reports specific to PSW + the power network
    redirect -file $::LOWPOWER_REPORTS_DIR/report_power_switches.${::LOWPOWER_STAGE}.rpt {
        catch { report_power_switches }
    }
    redirect -file $::LOWPOWER_REPORTS_DIR/report_power_domain.${::LOWPOWER_STAGE}.rpt {
        catch { report_power_domain }
    }
}

# ╔══════════════════════════════════════════════════════════════════════════╗
# ║ STAGE: place — insert isolation, level shifters, always-on buffers       ║
# ╚══════════════════════════════════════════════════════════════════════════╝
if {$::LOWPOWER_STAGE eq "place"} {
    handle_info "  Isolation cells:   $::LOWPOWER_ENABLE_ISOLATION"
    handle_info "  Level shifters:    $::LOWPOWER_ENABLE_LEVEL_SHIFTER"
    handle_info "  Always-on buffers: $::LOWPOWER_ENABLE_AON_BUFFER"

    if {[string is true -strict $::LOWPOWER_ENABLE_ISOLATION]} {
        handle_info "Enabling isolation cell insertion at power-domain crossings"
        set_app_options -name mv.upf.isolation.auto_insert -value true
    }
    if {[string is true -strict $::LOWPOWER_ENABLE_LEVEL_SHIFTER]} {
        handle_info "Enabling level shifter insertion at voltage crossings"
        set_app_options -name mv.upf.level_shifter.auto_insert -value true
    }
    if {[string is true -strict $::LOWPOWER_ENABLE_AON_BUFFER]} {
        handle_info "Enabling always-on buffer insertion"
        set_app_options -name place.opt.enable_always_on_buf_insertion -value true
    }

    # Re-validate after place-stage insertion strategies are set
    redirect -file $::LOWPOWER_REPORTS_DIR/check_mv_design.${::LOWPOWER_STAGE}.rpt {
        check_mv_design -verbose
    }

    # Reports specific to ISO + LS
    redirect -file $::LOWPOWER_REPORTS_DIR/report_isolation_cells.${::LOWPOWER_STAGE}.rpt {
        catch { report_isolation_cells }
    }
    redirect -file $::LOWPOWER_REPORTS_DIR/report_level_shifters.${::LOWPOWER_STAGE}.rpt {
        catch { report_level_shifters }
    }
}

# ── Common report: full multi-voltage view (both stages) ─────────────────────
redirect -file $::LOWPOWER_REPORTS_DIR/report_mv_design.${::LOWPOWER_STAGE}.rpt {
    report_mv_design
}

handle_info "─── FC low-power insertion completed: stage=$::LOWPOWER_STAGE ───"
