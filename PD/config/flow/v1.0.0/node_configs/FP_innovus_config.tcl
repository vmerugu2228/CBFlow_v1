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

    power,ring_width            "2.0"
    power,ring_spacing          "1.0"
}

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
    power,macro_ring_offset                              ""
    power,macro_ring_spacing                             ""
    power,macro_ring_width                               ""
    power,macro_rings                                    ""
    power,ring_layer_h                                   ""
    power,ring_layer_v                                   ""
    power,ring_offset                                    ""
    power,ring_spacing                                   ""
    power,ring_width                                     ""
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
