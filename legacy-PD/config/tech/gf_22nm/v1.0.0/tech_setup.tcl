#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow Technology Setup — Routing Direction, Site Default, Site Symmetry
# FC-RM: init_design.tech_setup.tcl
# Sourced by init_design flow_proc: setup_technology
# Variables come from tech() array in tech_config.tcl
# ═══════════════════════════════════════════════════════════════════════════════
global tech

# Set routing layer direction and track offset
if {[info exists tech(routing_layer_direction_offset)] && [llength $tech(routing_layer_direction_offset)] > 0} {
    foreach pair $tech(routing_layer_direction_offset) {
        set layer [lindex $pair 0]
        set direction [lindex $pair 1]
        set offset [lindex $pair 2]
        set_attribute [get_layers $layer] routing_direction $direction
        if {$offset ne ""} {
            set_attribute [get_layers $layer] track_offset $offset
        }
    }
    handle_info "Routing directions set for [llength $tech(routing_layer_direction_offset)] layers"
} else {
    handle_warning "tech(routing_layer_direction_offset) not set — routing directions must be in tech file"
}

# Set site default
if {[info exists tech(site_default)] && $tech(site_default) ne ""} {
    set_attribute [get_site_defs] is_default false
    set_attribute [get_site_defs $tech(site_default)] is_default true
    handle_info "Site default: $tech(site_default)"
}

# Set site symmetry
if {[info exists tech(site_symmetry)] && [llength $tech(site_symmetry)] > 0} {
    foreach pair $tech(site_symmetry) {
        set_attribute [get_site_defs [lindex $pair 0]] symmetry [lindex $pair 1]
    }
    handle_info "Site symmetry set for [llength $tech(site_symmetry)] sites"
}
