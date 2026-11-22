#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# FP — Cadence Innovus Tool Configuration
# Sourced from FP_config.tcl when tool=innovus
# ═══════════════════════════════════════════════════════════════════════════════

# ┌─ Innovus Tool Settings ────────────────────────────────────────────────────┐
array set fp {
    tool,vendor   "cadence"
    tool,name     "innovus"
    tool,version  "v1.0.0"
    tool,args     "-batch -no_gui"
}

# ┌─ FP App Settings (moved from common FP_config.tcl) ────────────────────────┐
array set fp {
    endcap,prefix               "ENDCAP"
    welltap,interval            ""
    welltap,prefix              "WELLTAP"
}
# (power,ring_width / power,ring_spacing live in the POWER block below — a
#  second definition here was silently overwritten by that block.)

# ┌─ Innovus Init Design Control ──────────────────────────────────────────────┐
# ┌─ Innovus Compile/Import Control ───────────────────────────────────────────┐
# ┌─ Innovus Create Power Control ─────────────────────────────────────────────┐
# ┌─ Innovus Required Inputs (enc handoff between stages) ────────────────────┐
set fp(required_inputs,init_design1)      "work/FP/netlist1/netlist work/FP/sdc1/sdc work/FP/def1/def work/FP/upf1/upf work/FP/library1/library"
set fp(required_inputs,floorplan1)        "work/FP/init_design1/outputs/init_design.enc.dat"
set fp(required_inputs,powerplan1)        "work/FP/floorplan1/outputs/floorplan.enc.dat"
set fp(required_inputs,export_data1)      "work/FP/powerplan1/outputs/powerplan.enc.dat"

# ── Innovus-RM App Variables ──────────────────────────────────────────────
# --- POWER (21 vars) ---
array set fp {
    power,additional_nets                                 ""
    power,add_vias                                       ""
    power,analyze_ir                                     ""
    power,ir_drop_limit                                  ""
    power,macro_ring_offset                              "0.5"
    power,macro_ring_spacing                             "0.5"
    power,macro_ring_width                               "1.0"
    power,macro_rings                                    ""
    power,ring_layer_h                                   ""
    power,ring_layer_v                                   ""
    power,ring_offset                                    "1.0"
    power,ring_spacing                                   "1.0"
    power,ring_width                                     "2.0"
    power,sroute_bottom_layer                            ""
    power,sroute_top_layer                               ""
    power,straps                                         ""
    power,tie_high_pin                                   ""
    power,tie_low_pin                                    ""
    power,vdd_net                                        ""
    power,vdd_pin                                        ""
    power,via_bottom_layer                               ""
    power,via_top_layer                                  ""
    power,vss_net                                        ""
    power,vss_pin                                        ""
}

# ┌─ Power-plan geometry / layer resolution (hardcode-fix 2026-11-22) ────────┐
# Values below were literals / derived defaults in powerplan_innovus.tcl.
#   power,ring_jog_distance / ring_threshold — addRing -jog_distance/-threshold
#   power,ring_offset       — was "= ring_spacing" when unset
#   power,macro_ring_*      — was width = ring_width*0.5, spacing = width*0.5,
#                             offset = spacing (derived from ring_width 2.0)
# Empty override keys resolve from the single source of truth:
#   power,vdd_net/vss_net/vdd_pin/vss_pin -> project(power,<key>)
#   power,ring_layer_h/v   -> tech(<project(metal_stack)>,pg_ring_layer_h/v)
#   power,sroute_bottom_layer -> first layer of tech(<ms>,metal_layers)
#   power,sroute_top_layer -> highest PG ring layer in tech(<ms>,metal_layers)
#   power,via_*_layer      -> the sroute range
array set fp {
    power,ring_jog_distance                              "0.5"
    power,ring_threshold                                 "0.5"
}
