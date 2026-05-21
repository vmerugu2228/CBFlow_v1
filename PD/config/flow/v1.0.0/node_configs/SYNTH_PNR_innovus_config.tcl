#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# SYNTH_PNR — Cadence Innovus Tool Configuration
# Sourced from SYNTH_PNR_config.tcl when tool=innovus
# ═══════════════════════════════════════════════════════════════════════════════

# ┌─ Innovus Tool Settings ─────────────────────────────────────────────────────┐
array set synth_pnr {
    tool,vendor   "cadence"
    tool,name     "innovus"
    tool,version  "v1.0.0"
    tool,args     "-batch -no_gui"
}

# ┌─ Innovus Place/CTS/Route/Analysis Settings ─────────────────────────────────┐
array set synth_pnr {
    place,effort               "high"
    place,congestion_aware     true
    place,timing_driven        true
    place,max_density          0.85

    cts,target_skew            "50"
    cts,max_transition         "100"
    cts,buffer_cells           ""
    cts,inverter_cells         ""

    route,min_layer            "M2"
    route,max_layer            "M8"
    route,antenna_fix          true
    route,si_aware             true

    analysis,max_paths         100
    analysis,significant_digits 4
}

# ┌─ Innovus Synthesis (Genus) Control ─────────────────────────────────────────┐
array set synth_pnr {
    compile,effort                "high"
    compile,enable_cpf            false
    compile,leakage_optimization  true
    compile,dft_insert_enable     false
    upf_mode                      "none"
}

# ┌─ Innovus CTS Control ──────────────────────────────────────────────────────┐
array set synth_pnr {
    cts,style                     "ccopt"
    cts,max_skew                  "50"
    cts,max_insertion_delay        ""
    cts,ccopt_effort              "medium"
}

# ┌─ Innovus Route Control ────────────────────────────────────────────────────┐
array set synth_pnr {
    route,nanoroute_mode          "route"
    route,enable_via_optimization true
    route,timing_driven           true
    route,si_driven               true
}

# ┌─ Innovus Route Optimization ───────────────────────────────────────────────┐
array set synth_pnr {
    route_opt,effort              "high"
    route_opt,hold_fix            true
    route_opt,enable_si_aware     true
    route_opt,useful_skew         true
}

# ┌─ Innovus Signoff/Chip Finish ──────────────────────────────────────────────┐
array set synth_pnr {
    signoff,insert_filler     true
    signoff,insert_decap      true
    signoff,drc_check         true
    signoff,metal_fill        true
    signoff,add_tieoff        true
}

# ┌─ Innovus Required Inputs (enc handoff between stages) ─────────────────────┐
set synth_pnr(required_inputs,init_design1)  "work/SYNTH_PNR/rtl1/rtl work/SYNTH_PNR/sdc1/sdc work/SYNTH_PNR/upf1/upf"
set synth_pnr(required_inputs,synthesis1)    "work/SYNTH_PNR/init_design1/run/init_design1.enc"
set synth_pnr(required_inputs,place1)        "work/SYNTH_PNR/synthesis1/run/synthesis1.enc"
set synth_pnr(required_inputs,cts1)          "work/SYNTH_PNR/place1/run/place1.enc"
set synth_pnr(required_inputs,cts_opt1)      "work/SYNTH_PNR/cts1/run/cts1.enc"
set synth_pnr(required_inputs,route1)        "work/SYNTH_PNR/cts_opt1/run/cts_opt1.enc"
set synth_pnr(required_inputs,pro1)          "work/SYNTH_PNR/route1/run/route1.enc"
set synth_pnr(required_inputs,signoff1)      "work/SYNTH_PNR/pro1/run/pro1.enc"
set synth_pnr(required_inputs,export_data1)  "work/SYNTH_PNR/signoff1/run/signoff1.enc"
