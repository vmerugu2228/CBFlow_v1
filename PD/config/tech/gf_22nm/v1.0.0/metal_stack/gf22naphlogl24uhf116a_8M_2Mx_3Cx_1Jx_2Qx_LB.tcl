#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# Metal Stack: gf22naphlogl24uhf116a_8M_2Mx_3Cx_1Jx_2Qx_LB
# Process:     GF 22FDX (22nm FD-SOI)
# Layers:      8 metals — 2 thick (Mx) + 3 intermediate (Cx) + 1 junction (Jx) + 2 thin (Qx)
# Bump:        Local Bump (LB)
# Tech file:   gf22naphlogl24uhf116a_8M_2Mx_3Cx_1Jx_2Qx_LB.tf
# ═══════════════════════════════════════════════════════════════════════════════

set tech(metal_stack_label)  "8M"
set tech(metal_count)        8
set tech(metal_stack_full)   "1P8M_2Mx_3Cx_1Jx_2Qx_LB"

# Tech file for this metal stack
set tech(tech_file)          "$_R/Back_End/tech/gf22naphlogl24uhf116a_8M_2Mx_3Cx_1Jx_2Qx_LB.tf"

# ── Layer Definitions ─────────────────────────────────────────────────────
# Layer order bottom to top
set tech(metal_layers) {M1 M2 M3 M4 M5 M6 M7 M8}

# Layer types: Qx=thin/local, Cx=intermediate, Jx=junction, Mx=thick/global
set tech(metal_layer_types) {
    M1   Qx
    M2   Qx
    M3   Cx
    M4   Cx
    M5   Cx
    M6   Jx
    M7   Mx
    M8   Mx
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
    M6,pitch       160
    M6,min_width   64
    M6,min_spacing 64
    M6,type        "Jx"

    M7,direction   "V"
    M7,pitch       320
    M7,min_width   160
    M7,min_spacing 160
    M7,type        "Mx"

    M8,direction   "H"
    M8,pitch       320
    M8,min_width   160
    M8,min_spacing 160
    M8,type        "Mx"
}

# ── Routing Constraints (derived from layer definitions) ──────────────────
set tech(min_routing_layer)       "M2"
set tech(max_routing_layer)       "M7"
set tech(clock_routing_layer_min) "M3"
set tech(clock_routing_layer_max) "M5"

# ── Routing Layer Direction + Offset (for tech_setup.tcl) ─────────────────
# Format: {layer direction offset}
set tech(routing_layer_direction_offset) {
    {M1  vertical   0.032}
    {M2  horizontal 0.032}
    {M3  vertical   0.040}
    {M4  horizontal 0.040}
    {M5  vertical   0.040}
    {M6  horizontal 0.080}
    {M7  vertical   0.160}
    {M8  horizontal 0.160}
}

# ── Via Definitions ───────────────────────────────────────────────────────
set tech(via_layers) {VIA1 VIA2 VIA3 VIA4 VIA5 VIA6 VIA7}

# ── Power Strap Recommendations ──────────────────────────────────────────
# Recommended layers for PG straps (thick metals for low IR drop)
set tech(pg_strap_layers)         {M7 M8}
set tech(pg_strap_secondary)      {M5 M6}
set tech(pg_ring_layer_h)         "M8"
set tech(pg_ring_layer_v)         "M7"

# ── Metal Fill Rules ──────────────────────────────────────────────────────
set tech(metal_fill_min_density)  20.0
set tech(metal_fill_max_density)  80.0

puts "INFO: Metal stack loaded: $tech(metal_stack) — $tech(metal_count) layers ($tech(metal_stack_full))"
