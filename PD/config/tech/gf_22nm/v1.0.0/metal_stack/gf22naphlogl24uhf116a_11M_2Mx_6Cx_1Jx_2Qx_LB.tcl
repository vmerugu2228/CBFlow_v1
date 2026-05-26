#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# Metal Stack: gf22naphlogl24uhf116a_11M_2Mx_6Cx_1Jx_2Qx_LB
# Process:     GF 22FDX (22nm FD-SOI)
# Layers:      11 metals — 2 thick (Mx) + 6 intermediate (Cx) + 1 junction (Jx) + 2 thin (Qx)
# Bump:        Local Bump (LB)
# Tech file:   gf22naphlogl24uhf116a_10M_2Mx_5Cx_1Jx_2Qx_LB.tf
# ═══════════════════════════════════════════════════════════════════════════════

set tech(metal_stack_label)  "11M"
set tech(metal_count)        11
set tech(metal_stack_full)   "1P11M_2Mx_6Cx_1Jx_2Qx_LB"

# Tech file for this metal stack
set tech(tech_file)          "$_R/Back_End/tech/gf22naphlogl24uhf116a_11M_2Mx_6Cx_1Jx_2Qx_LB.tf"

# ── Layer Definitions ─────────────────────────────────────────────────────
# Layer order bottom to top
set tech(metal_layers) {M1 M2 M3 M4 M5 M6 M7 M8 M9 M10 M11}

# Layer types: Qx=thin/local, Cx=intermediate, Jx=junction, Mx=thick/global
set tech(metal_layer_types) {
    M1   Qx
    M2   Qx
    M3   Cx
    M4   Cx
    M5   Cx
    M6   Cx
    M7   Cx
    M8   Cx
    M9   Jx
    M10  Mx
    M11  Mx
}

# ── Per-Layer Properties ──────────────────────────────────────────────────
# Format: {direction pitch_nm width_nm spacing_nm}
# Direction: H=horizontal, V=vertical (alternating by convention)
array set tech_metal_layer {
    M1,direction   "V"
    M1,pitch       64
    M1,min_width   28
    M1,min_spacing 28
    M1,type        "Qx"

    M2,direction   "H"
    M2,pitch       64
    M2,min_width   28
    M2,min_spacing 28
    M2,type        "Qx"

    M3,direction   "V"
    M3,pitch       80
    M3,min_width   32
    M3,min_spacing 32
    M3,type        "Cx"

    M4,direction   "H"
    M4,pitch       80
    M4,min_width   32
    M4,min_spacing 32
    M4,type        "Cx"

    M5,direction   "V"
    M5,pitch       80
    M5,min_width   32
    M5,min_spacing 32
    M5,type        "Cx"

    M6,direction   "H"
    M6,pitch       80
    M6,min_width   32
    M6,min_spacing 32
    M6,type        "Cx"

    M7,direction   "V"
    M7,pitch       80
    M7,min_width   32
    M7,min_spacing 32
    M7,type        "Cx"

    M8,direction   "H"
    M8,pitch       80
    M8,min_width   32
    M8,min_spacing 32
    M8,type        "Cx"

    M9,direction   "V"
    M9,pitch       160
    M9,min_width   64
    M9,min_spacing 64
    M9,type        "Jx"

    M10,direction  "H"
    M10,pitch      320
    M10,min_width  160
    M10,min_spacing 160
    M10,type       "Mx"

    M11,direction  "V"
    M11,pitch      320
    M11,min_width  160
    M11,min_spacing 160
    M11,type       "Mx"
}

# ── Routing Constraints (derived from layer definitions) ──────────────────
set tech(min_routing_layer)       "M2"
set tech(max_routing_layer)       "M10"
set tech(clock_routing_layer_min) "M4"
set tech(clock_routing_layer_max) "M8"

# ── Routing Layer Direction + Offset (for tech_setup.tcl) ─────────────────
# Format: {layer direction offset}
set tech(routing_layer_direction_offset) {
    {M1  vertical   0.032}
    {M2  horizontal 0.032}
    {M3  vertical   0.040}
    {M4  horizontal 0.040}
    {M5  vertical   0.040}
    {M6  horizontal 0.040}
    {M7  vertical   0.040}
    {M8  horizontal 0.040}
    {M9  vertical   0.080}
    {M10 horizontal 0.160}
    {M11 vertical   0.160}
}

# ── Via Definitions ───────────────────────────────────────────────────────
set tech(via_layers) {VIA1 VIA2 VIA3 VIA4 VIA5 VIA6 VIA7 VIA8 VIA9 VIA10}

# ── Power Strap Recommendations ──────────────────────────────────────────
# Recommended layers for PG straps (thick metals for low IR drop)
set tech(pg_strap_layers)         {M10 M11}
set tech(pg_strap_secondary)      {M8 M9}
set tech(pg_ring_layer_h)         "M10"
set tech(pg_ring_layer_v)         "M11"

# ── Metal Fill Rules ──────────────────────────────────────────────────────
set tech(metal_fill_min_density)  20.0
set tech(metal_fill_max_density)  80.0

puts "INFO: Metal stack loaded: $tech(metal_stack) — $tech(metal_count) layers ($tech(metal_stack_full))"
