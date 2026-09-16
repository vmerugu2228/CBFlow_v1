#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow Library Cell Purpose Restrictions
# FC-RM: set_lib_cell_purpose.tcl
# Sourced by command files via tech(lib_cell_purpose_file)
# Variables come from tech() array in tech_config.tcl
# ═══════════════════════════════════════════════════════════════════════════════
global tech

suppress_message ATTR-11

# ── Dont-use cells ───────────────────────────────────────────────────────────
if {[info exists tech(dont_use_cells)] && [llength $tech(dont_use_cells)] > 0} {
    foreach pattern $tech(dont_use_cells) {
        set_lib_cell_purpose -exclude optimization [get_lib_cells $pattern]
    }
    handle_info "Dont-use cells applied: [llength $tech(dont_use_cells)] patterns"
}

# ── Tie cells ────────────────────────────────────────────────────────────────
if {[info exists tech(tie_lib_cells)] && $tech(tie_lib_cells) ne ""} {
    set_dont_touch [get_lib_cells $tech(tie_lib_cells)] false
    set_lib_cell_purpose -include optimization [get_lib_cells $tech(tie_lib_cells)]
    handle_info "Tie cells included: $tech(tie_lib_cells)"
}

# ── Hold fix cells ──────────────────────────────────────────────────────────
if {[info exists tech(hold_fix_lib_cells)] && $tech(hold_fix_lib_cells) ne ""} {
    set_dont_touch [get_lib_cells $tech(hold_fix_lib_cells)] false
    set_lib_cell_purpose -exclude hold [get_lib_cells */*]
    set_lib_cell_purpose -include hold [get_lib_cells $tech(hold_fix_lib_cells)]
    handle_info "Hold fix cells: $tech(hold_fix_lib_cells)"
}

# ── CTS cells (non-exclusive) ───────────────────────────────────────────────
# Include repeaters, always-on buffers, gates, and flops (CCD can size flops)
if {[info exists tech(cts_lib_cells)] && $tech(cts_lib_cells) ne ""} {
    set_lib_cell_purpose -exclude cts [get_lib_cells */*]
    set_dont_touch [get_lib_cells $tech(cts_lib_cells)] false
    set_lib_cell_purpose -include cts [get_lib_cells $tech(cts_lib_cells)]
    handle_info "CTS cells: $tech(cts_lib_cells)"
}

# ── CTS-exclusive cells ─────────────────────────────────────────────────────
# These cells are used ONLY for CTS (not optimization or hold)
if {[info exists tech(cts_only_lib_cells)] && $tech(cts_only_lib_cells) ne ""} {
    if {![info exists tech(cts_lib_cells)] || $tech(cts_lib_cells) eq ""} {
        set_lib_cell_purpose -exclude cts [get_lib_cells */*]
    }
    set_dont_touch [get_lib_cells $tech(cts_only_lib_cells)] false
    set_lib_cell_purpose -include none [get_lib_cells $tech(cts_only_lib_cells)]
    set_lib_cell_purpose -include cts [get_lib_cells $tech(cts_only_lib_cells)]
    handle_info "CTS-exclusive cells: $tech(cts_only_lib_cells)"
}
