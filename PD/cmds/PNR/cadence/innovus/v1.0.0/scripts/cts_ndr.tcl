#!/usr/bin/env tclsh
# ==============================================================================
# CTS NDR (Non-Default Routing) — Cadence Innovus
# Description: Define NDR rules, create route types, assign to clock net types.
#   Follows Cadence Foundation Flow pattern:
#     add_ndr → create_route_type → set_ccopt_property route_type
#
# Config variables (set in user_config or FP/PNR tool config):
#   pnr(cts,ndr_name)           — NDR rule name (e.g., "2w2s")
#   pnr(cts,ndr_widths)         — per-layer widths  {Metal1 0.12 Metal2 0.14 ...}
#   pnr(cts,ndr_spacings)       — per-layer spacings {Metal1 0.12 Metal2 0.14 ...}
#   pnr(cts,route_type_name)    — route type name (e.g., "clkroute")
#   pnr(cts,ndr_bottom_layer)   — bottom preferred routing layer for clocks
#   pnr(cts,ndr_top_layer)      — top preferred routing layer for clocks
#   pnr(cts,ndr_trunk_type)     — route type for trunk nets (defaults to route_type_name)
#   pnr(cts,ndr_leaf_type)      — route type for leaf nets (defaults to route_type_name)
#   pnr(cts,buffer_cells)       — CTS buffer cells list
#   pnr(cts,inverter_cells)     — CTS inverter cells list
#   pnr(cts,clock_gating_cells) — ICG cells pattern
# ==============================================================================

global pnr tech

# ── Validate mandatory config ──
foreach _var {
    pnr(cts,ndr_name)
    pnr(cts,ndr_widths)
    pnr(cts,ndr_spacings)
    pnr(cts,ndr_bottom_layer)
    pnr(cts,ndr_top_layer)
    pnr(cts,buffer_cells)
    pnr(cts,inverter_cells)
} {
    if {![info exists $_var] || [set $_var] eq ""} {
        handle_error "$_var not set — required for CTS NDR setup"
        return -code error "$_var not set — required for CTS NDR setup"
    }
}

# ── 1. Create NDR rule ──
# Reference: add_ndr -width {M1 0.12 M2 0.14 ...} -spacing {M1 0.12 M2 0.14 ...} -name 2w2s
set ndr_name $pnr(cts,ndr_name)

handle_info "Creating NDR rule: $ndr_name"
handle_info "  Widths:   $pnr(cts,ndr_widths)"
handle_info "  Spacings: $pnr(cts,ndr_spacings)"

add_ndr \
    -name $ndr_name \
    -width $pnr(cts,ndr_widths) \
    -spacing $pnr(cts,ndr_spacings)

# ── 2. Create route type ──
# Reference: create_route_type -name clkroute -non_default_rule 2w2s
#            -bottom_preferred_layer Metal5 -top_preferred_layer Metal6
set route_type_name "clkroute"
if {[info exists pnr(cts,route_type_name)] && $pnr(cts,route_type_name) ne ""} {
    set route_type_name $pnr(cts,route_type_name)
}

handle_info "Creating route type: $route_type_name"
handle_info "  Layers: $pnr(cts,ndr_bottom_layer) - $pnr(cts,ndr_top_layer)"

create_route_type \
    -name $route_type_name \
    -non_default_rule $ndr_name \
    -bottom_preferred_layer $pnr(cts,ndr_bottom_layer) \
    -top_preferred_layer $pnr(cts,ndr_top_layer)

# ── 3. Assign route type to clock net types ──
# Reference: set_ccopt_property route_type clkroute -net_type trunk
#            set_ccopt_property route_type clkroute -net_type leaf

# Trunk nets
set trunk_type $route_type_name
if {[info exists pnr(cts,ndr_trunk_type)] && $pnr(cts,ndr_trunk_type) ne ""} {
    set trunk_type $pnr(cts,ndr_trunk_type)
}
handle_info "Trunk route type: $trunk_type"
set_ccopt_property route_type $trunk_type -net_type trunk

# Leaf nets
set leaf_type $route_type_name
if {[info exists pnr(cts,ndr_leaf_type)] && $pnr(cts,ndr_leaf_type) ne ""} {
    set leaf_type $pnr(cts,ndr_leaf_type)
}
handle_info "Leaf route type: $leaf_type"
set_ccopt_property route_type $leaf_type -net_type leaf

# ── 4. Set CTS cells ──
# Reference: set_ccopt_property buffer_cells {CLKBUFX8 CLKBUFX12}
#            set_ccopt_property inverter_cells {CLKINVX8 CLKINVX12}
#            set_ccopt_property clock_gating_cells TLATNTSCA*

handle_info "CTS buffer cells: $pnr(cts,buffer_cells)"
set_ccopt_property buffer_cells $pnr(cts,buffer_cells)

handle_info "CTS inverter cells: $pnr(cts,inverter_cells)"
set_ccopt_property inverter_cells $pnr(cts,inverter_cells)

if {[info exists pnr(cts,clock_gating_cells)] && $pnr(cts,clock_gating_cells) ne ""} {
    handle_info "CTS clock gating cells: $pnr(cts,clock_gating_cells)"
    set_ccopt_property clock_gating_cells $pnr(cts,clock_gating_cells)
}

# ── 5. Don't-use cells for CTS ──
if {[info exists pnr(cts,dont_use)] && $pnr(cts,dont_use) ne ""} {
    foreach pat $pnr(cts,dont_use) {
        handle_info "CTS dont_use: $pat"
        setDontUse $pat true
    }
}

# ── Summary ──
handle_info "CTS NDR setup complete"
handle_info "  NDR rule:    $ndr_name"
handle_info "  Route type:  $route_type_name"
handle_info "  Clock layers: $pnr(cts,ndr_bottom_layer) - $pnr(cts,ndr_top_layer)"
handle_info "  Buffers:     $pnr(cts,buffer_cells)"
handle_info "  Inverters:   $pnr(cts,inverter_cells)"
