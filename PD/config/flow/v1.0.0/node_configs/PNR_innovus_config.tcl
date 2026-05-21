#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# PNR — Cadence Innovus Tool Configuration
# Sourced from PNR_config.tcl when tool=innovus
# ═══════════════════════════════════════════════════════════════════════════════

# ┌─ Innovus Tool Settings ────────────────────────────────────────────────────┐
array set pnr {
    tool,vendor   "cadence"
    tool,name     "innovus"
    tool,version  "v1.0.0"
    tool,args     "-batch -no_gui"
}

# ┌─ PNR App Settings (moved from common PNR_config.tcl) ──────────────────────┐
array set pnr {
    place,effort               "high"
    place,congestion_aware     true
    place,timing_driven        true
    place,max_density          0.85
    place,high_utilization_flow false

    cts,target_skew            "50"
    cts,max_transition         "100"
    cts,buffer_cells           ""
    cts,inverter_cells         ""

    route,min_layer            "M2"
    route,max_layer            "M8"
    route,antenna_fix          true
    route,metal_fill           true
    route,si_aware             true

    analysis,max_paths         100
    analysis,significant_digits 4
}

# ┌─ Innovus CTS Control ─────────────────────────────────────────────────────┐
array set pnr {
    cts,style                     "ccopt"
    cts,max_skew                  "50"
    cts,max_insertion_delay        ""
    cts,ccopt_effort              "medium"
}

# ┌─ Innovus Route Control ───────────────────────────────────────────────────┐
array set pnr {
    route,nanoroute_mode          "route"
    route,enable_via_optimization true
    route,timing_driven           true
    route,si_driven               true
}

# ┌─ Innovus Route Optimization ──────────────────────────────────────────────┐
array set pnr {
    route_opt,effort              "high"
    route_opt,hold_fix            true
    route_opt,enable_si_aware     true
    route_opt,useful_skew         true
}

# ┌─ Innovus Signoff/Chip Finish ─────────────────────────────────────────────┐
array set pnr {
    signoff,insert_filler     true
    signoff,insert_decap      true
    signoff,drc_check         true
    signoff,metal_fill        true
    signoff,add_tieoff        true
}

# ┌─ Innovus Required Inputs (enc handoff between stages) ────────────────────┐
set pnr(required_inputs,init_design1)  "work/PNR/netlist1/netlist work/PNR/sdc1/sdc work/PNR/def1/def work/PNR/upf1/upf"
set pnr(required_inputs,place1)        "work/PNR/init_design1/run/init_design1.enc"
set pnr(required_inputs,cts1)          "work/PNR/place1/run/place1.enc"
set pnr(required_inputs,cts_opt1)      "work/PNR/cts1/run/cts1.enc"
set pnr(required_inputs,route1)        "work/PNR/cts_opt1/run/cts_opt1.enc"
set pnr(required_inputs,pro1)          "work/PNR/route1/run/route1.enc"
set pnr(required_inputs,signoff1)      "work/PNR/pro1/run/pro1.enc"
set pnr(required_inputs,export_data1)  "work/PNR/signoff1/run/signoff1.enc"

# ── Innovus-RM App Variables ──────────────────────────────────────────────
# --- ANALYSIS (1 vars) ---
array set pnr {
    analysis,max_paths                                   ""
}

# --- CHIP_FINISH (22 vars) ---
array set pnr {
    chip_finish,antenna_check                            ""
    chip_finish,antenna_fix                              ""
    chip_finish,cleanup                                  ""
    chip_finish,cleanup_level                            ""
    chip_finish,eco_check                                ""
    chip_finish,eco_timing                               ""
    chip_finish,fill_density                             ""
    chip_finish,fill_layers                              ""
    chip_finish,fill_spacing                             ""
    chip_finish,filler_cells                             ""
    chip_finish,filler_prefix                            ""
    chip_finish,filler_types                             ""
    chip_finish,ir_drop_target                           ""
    chip_finish,keep_checkpoints                         ""
    chip_finish,lvs_netlist                              ""
    chip_finish,lvs_prep                                 ""
    chip_finish,metal_fill                               ""
    chip_finish,power_opt                                ""
    chip_finish,rail_analysis                            ""
    chip_finish,spare_cells                              ""
    chip_finish,spare_ratio                              ""
    chip_finish,spare_types                              ""
}

# --- COMMON (7 vars) ---
array set pnr {
    common,design_name                                   ""
    common,ground_net                                    ""
    common,input_netlist                                 ""
    common,lib_cell_purpose_file                         ""
    common,mmmc_setup_file                               ""
    common,power_net                                     ""
    common,release_phase                                 ""
}

# --- CTS (6 vars) ---
array set pnr {
    cts,buffer_cells                                     ""
    cts,inverter_cells                                   ""
    cts,max_cap                                          ""
    cts,max_trans                                        ""
    cts,opt_effort                                       ""
    cts,target_skew                                      ""
}

# --- CTS_OPT (4 vars) ---
array set pnr {
    cts_opt,balance_effort                               ""
    cts_opt,effort                                       ""
    cts_opt,fix_hold                                     ""
    cts_opt,refine_iterations                            ""
}

# --- EXPORT (19 vars) ---
array set pnr {
    export,abstract                                      ""
    export,antenna                                       ""
    export,def                                           ""
    export,drc                                           ""
    export,floorplan                                     ""
    export,gds                                           ""
    export,lef                                           ""
    export,lvs                                           ""
    export,oasis                                         ""
    export,placement                                     ""
    export,power_reports                                 ""
    export,rail_analysis                                 ""
    export,routing                                       ""
    export,sdc                                           ""
    export,sdf                                           ""
    export,spef                                          ""
    export,spice                                         ""
    export,upf                                           ""
    export,verilog                                       ""
}

# --- EXTRACT (3 vars) ---
array set pnr {
    extract,effort                                       ""
    extract,mode                                         ""
    extract,rc_corner                                    ""
}

# --- FLOORPLAN (12 vars) ---
array set pnr {
    floorplan,aspect_ratio                               ""
    floorplan,core_margins                               ""
    floorplan,core_util                                  ""
    floorplan,io_pin_depth                               ""
    floorplan,io_pin_spacing                             ""
    floorplan,io_pin_width                               ""
    floorplan,io_placement_file                          ""
    floorplan,io_placement_mode                          ""
    floorplan,mode                                       ""
    floorplan,power_domains                              ""
    floorplan,site_name                                  ""
    floorplan,upf_file                                   ""
}

# --- OPT (3 vars) ---
array set pnr {
    opt,hold_margin                                      ""
    opt,insert_metal_fill                                ""
    opt,setup_margin                                     ""
}

# --- OUTPUT (1 vars) ---
array set pnr {
    output,gds                                           ""
}

# --- PLACE (5 vars) ---
array set pnr {
    place,congestion_effort                              ""
    place,density                                        ""
    place,effort                                         ""
    place,opt_effort                                     ""
    place,timing_driven                                  ""
}

# --- POWERPLAN (13 vars) ---
array set pnr {
    powerplan,ring_layers                                ""
    powerplan,ring_nets                                  ""
    powerplan,ring_offset                                ""
    powerplan,ring_spacing                               ""
    powerplan,ring_width                                 ""
    powerplan,stripe_direction                           ""
    powerplan,stripe_layers                              ""
    powerplan,stripe_nets                                ""
    powerplan,stripe_spacing                             ""
    powerplan,stripe_width                               ""
    powerplan,well_tie_cells                             ""
    powerplan,well_tie_rule                              ""
    powerplan,well_tie_spacing                           ""
}

# --- ROUTE (7 vars) ---
array set pnr {
    route,effort                                         ""
    route,fix_antenna                                    ""
    route,layers                                         ""
    route,post_opt_effort                                ""
    route,si_aware                                       ""
    route,timing_driven                                  ""
    route,via_opt                                        ""
}

# --- SIGNOFF (1 vars) ---
array set pnr {
    signoff,extract_effort                               ""
}
