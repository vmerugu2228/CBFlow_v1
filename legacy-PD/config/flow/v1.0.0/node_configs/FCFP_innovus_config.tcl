#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# FCFP — Cadence Innovus Tool Configuration
# Sourced from FCFP_config.tcl when tool=innovus
# ═══════════════════════════════════════════════════════════════════════════════

# ┌─ Innovus Tool Settings ────────────────────────────────────────────────────┐
array set fcfp {
    tool,vendor   "cadence"
    tool,name     "innovus"
    tool,version  "v1.0.0"
    tool,args     "-batch -no_gui"
}

# ─────────────────────────────────────────────────────────────────────────────
# STAGE LIST OVERRIDE — Innovus's FCFP equivalent is different from FC's.
#
# FC's hierarchical-planning stages (init_design, commit_blocks, init_compile,
# create_floorplan, shaping, placement, create_power, place_pins, top_compile,
# timing_budget) don't map 1:1 to Innovus. Innovus collapses these into three
# floorplan stages (fc_floorplan / fc_powerplan / fc_post_floorplan) — that's
# what's actually implemented under PD/cmds/FCFP/cadence/innovus/v1.0.0/.
#
# Unset every FC-shaped per-stage key inherited from FCFP_config.tcl and
# redefine for the Innovus stage set so `cbflow flow check` no longer flags
# "missing <stage>_subnode_handler.tcl" warnings for stages Innovus doesn't
# implement.
# ─────────────────────────────────────────────────────────────────────────────

foreach _k [array names fcfp dependencies,*]            { unset fcfp($_k) }
foreach _k [array names fcfp node_types,*]              { unset fcfp($_k) }
foreach _k [array names fcfp stage_types,*]             { unset fcfp($_k) }
foreach _k [array names fcfp node_descriptions,*]       { unset fcfp($_k) }
foreach _k [array names fcfp subnodes,*]                { unset fcfp($_k) }
foreach _k [array names fcfp subnode_dependencies,*]    { unset fcfp($_k) }
foreach _k [array names fcfp subnode_work_dirs,*]       { unset fcfp($_k) }
foreach _k [array names fcfp runtime,timeout,*]         { unset fcfp($_k) }

# Innovus FCFP stages: 5 input nodes (handled by inputs_subnode_handler.tcl)
# + 3 floorplan stages + export + release. No FC-only stages.
array set fcfp {
    stages {netlist1 sdc1 def1 upf1 library1 fc_floorplan1 fc_powerplan1 fc_post_floorplan1 export_data1 release_data1}

    dependencies,netlist1            {}
    dependencies,sdc1                {}
    dependencies,def1                {}
    dependencies,upf1                {}
    dependencies,library1            {}
    dependencies,fc_floorplan1       {netlist1 sdc1 def1 upf1 library1}
    dependencies,fc_powerplan1       {fc_floorplan1}
    dependencies,fc_post_floorplan1  {fc_powerplan1}
    dependencies,export_data1        {fc_post_floorplan1}
    dependencies,release_data1       {export_data1}

    node_types,netlist1              "inputs"
    node_types,sdc1                  "inputs"
    node_types,def1                  "inputs"
    node_types,upf1                  "inputs"
    node_types,library1              "inputs"
    node_types,fc_floorplan1         "fc_floorplan"
    node_types,fc_powerplan1         "fc_powerplan"
    node_types,fc_post_floorplan1    "fc_post_floorplan"
    node_types,export_data1          "export_data"
    node_types,release_data1         "release_data"

    stage_types,netlist1             "inputs"
    stage_types,sdc1                 "inputs"
    stage_types,def1                 "inputs"
    stage_types,upf1                 "inputs"
    stage_types,library1             "inputs"
    stage_types,fc_floorplan1        "execution"
    stage_types,fc_powerplan1        "execution"
    stage_types,fc_post_floorplan1   "execution"
    stage_types,export_data1         "export_data"
    stage_types,release_data1        "release_data"

    node_descriptions,netlist1            "Gate-level netlist input"
    node_descriptions,sdc1                "SDC timing constraints input"
    node_descriptions,def1                "DEF floorplan input"
    node_descriptions,upf1                "UPF power intent input"
    node_descriptions,library1            "Technology library input"
    node_descriptions,fc_floorplan1       "Innovus FCFP: hierarchical floorplan create"
    node_descriptions,fc_powerplan1       "Innovus FCFP: power network synthesis"
    node_descriptions,fc_post_floorplan1  "Innovus FCFP: post-floorplan refinement"
    node_descriptions,export_data1        "Export hierarchical design data"
    node_descriptions,release_data1       "Release FCFP deliverables"

    runtime,timeout,netlist1              10
    runtime,timeout,sdc1                  10
    runtime,timeout,def1                  10
    runtime,timeout,upf1                  10
    runtime,timeout,library1              10
    runtime,timeout,fc_floorplan1         60
    runtime,timeout,fc_powerplan1         60
    runtime,timeout,fc_post_floorplan1    45
    runtime,timeout,export_data1          20
    runtime,timeout,release_data1         15
}

# Re-build subnode setup for the Innovus execution stages
set _fcfp_innovus_exec_stages {fc_floorplan1 fc_powerplan1 fc_post_floorplan1 export_data1 release_data1}
foreach _s $_fcfp_innovus_exec_stages {
    set fcfp(subnodes,$_s) {setup run validate finish}
    set fcfp(subnode_dependencies,${_s},setup)    {}
    set fcfp(subnode_dependencies,${_s},run)      {setup}
    set fcfp(subnode_dependencies,${_s},validate) {run}
    set fcfp(subnode_dependencies,${_s},finish)   {validate}
    foreach _sub {setup run validate finish} {
        set fcfp(subnode_work_dirs,${_s},${_sub}) "work/${_s}/${_sub}"
    }
}


# ┌─ FCFP App Settings (moved from common FCFP_config.tcl) ────────────────────┐
array set fcfp {
    design_style            "hier"
    physical_hierarchy_level "top"

    floorplan,die_width         ""
    floorplan,die_height        ""
    floorplan,core_utilization  0.65
    floorplan,core_aspect_ratio 1.0
    floorplan,macro_placement   true
    floorplan,macro_spacing     "5.0"
    floorplan,boundary_cells    true
    floorplan,tap_cells         true
    floorplan,place_pins        true

    power,net_names             "VDD VSS"
    power,ring_width            "3.0"
    power,ring_spacing          "1.0"
    power,strap_width           "1.0"
    power,strap_pitch           "20.0"
    power,mesh_layers           "M8 M9 M10"

    place_pins,legalize         true
    place_pins,constraint_file  ""
    place_pins,fix_ports        true
}

# ┌─ Innovus Commit Blocks Control ────────────────────────────────────────────┐
array set fcfp {
    sub_block_refs          {}
    sub_block_libraries     {}
}

# ┌─ Innovus Init Compile Control ─────────────────────────────────────────────┐
array set fcfp {
    compile,effort          "medium"
    compile,timing_driven   true
    compile,leakage_opt     false
}

# ┌─ Innovus Shaping Control ──────────────────────────────────────────────────┐
array set fcfp {
    shaping,style               "auto"
    shaping,min_channel_width   ""
    shaping,target_utilization  ""
}

# ┌─ Innovus Placement Control ────────────────────────────────────────────────┐
array set fcfp {
    placement,congestion_driven true
    placement,timing_driven     true
    placement,max_density       0.70
}

# ┌─ Innovus Create Power Control ─────────────────────────────────────────────┐
array set fcfp {
    powerplan,pns_file          ""
    powerplan,stdcell_placement true
    powerplan,add_stripes       true
}

# ┌─ Innovus Top Compile Control ──────────────────────────────────────────────┐
array set fcfp {
    top_compile,effort          "medium"
    top_compile,timing_driven   true
}

# ┌─ Innovus Timing Budget Control ────────────────────────────────────────────┐
array set fcfp {
    timing_budget,estimate_timing  true
    timing_budget,distribute       true
}

# ┌─ Innovus Required Inputs (enc handoff between stages) ────────────────────┐
set fcfp(required_inputs,init_design1)      "work/FCFP/netlist1/netlist work/FCFP/sdc1/sdc work/FCFP/def1/def work/FCFP/upf1/upf work/FCFP/library1/library"
set fcfp(required_inputs,commit_blocks1)    "work/FCFP/init_design1/run/init_design1.enc"
set fcfp(required_inputs,init_compile1)     "work/FCFP/commit_blocks1/run/commit_blocks1.enc"
set fcfp(required_inputs,create_floorplan1) "work/FCFP/init_compile1/run/init_compile1.enc"
set fcfp(required_inputs,shaping1)          "work/FCFP/create_floorplan1/run/create_floorplan1.enc"
set fcfp(required_inputs,placement1)        "work/FCFP/shaping1/run/shaping1.enc"
set fcfp(required_inputs,create_power1)     "work/FCFP/placement1/run/placement1.enc"
set fcfp(required_inputs,place_pins1)       "work/FCFP/create_power1/run/create_power1.enc"
set fcfp(required_inputs,top_compile1)      "work/FCFP/place_pins1/run/place_pins1.enc"
set fcfp(required_inputs,timing_budget1)    "work/FCFP/top_compile1/run/top_compile1.enc"
set fcfp(required_inputs,export_data1)      "work/FCFP/timing_budget1/run/timing_budget1.enc"

# ── Innovus-RM App Variables ──────────────────────────────────────────────
# --- COMMON (3 vars) ---
array set fcfp {
    common,design_name                                   ""
    common,release_dir                                   ""
    common,release_phase                                 ""
}

# --- EXPORT (3 vars) ---
array set fcfp {
    export,floorplan_only_def                            ""
    export,skip_netlist                                  ""
    export,skip_sdc                                      ""
}

# --- FLOORPLAN (20 vars) ---
array set fcfp {
    floorplan,aspect_ratio                               ""
    floorplan,blockage_margin                            ""
    floorplan,core_margin_bottom                         ""
    floorplan,core_margin_left                           ""
    floorplan,core_margin_right                          ""
    floorplan,core_margin_top                            ""
    floorplan,create_macro_blockage                      ""
    floorplan,die_height                                 ""
    floorplan,die_width                                  ""
    floorplan,io_constraint_file                         ""
    floorplan,io_filler_cells                            ""
    floorplan,io_pin_layer                               ""
    floorplan,macro_halo_x                               ""
    floorplan,macro_halo_y                               ""
    floorplan,macro_placement_file                       ""
    floorplan,partition_constraints_file                 ""
    floorplan,partition_list                             ""
    floorplan,partition_pin_mode                         ""
    floorplan,site_name                                  ""
    floorplan,utilization                                ""
}

# --- POST_FLOORPLAN (3 vars) ---
array set fcfp {
    post_floorplan,congestion_threshold                  ""
    post_floorplan,max_timing_paths                      ""
    post_floorplan,trial_route_effort                    ""
}

# --- POWER (19 vars) ---
array set fcfp {
    power,block_ring_width                               ""
    power,create_block_rings                             ""
    power,fine_strap_layer                               ""
    power,fine_strap_pitch                               ""
    power,fine_strap_width                               ""
    power,ring_layer_h                                   ""
    power,ring_layer_v                                   ""
    power,ring_offset                                    ""
    power,ring_spacing                                   ""
    power,ring_width                                     ""
    power,strap_layer_h                                  ""
    power,strap_layer_v                                  ""
    power,strap_pitch                                    ""
    power,strap_spacing                                  ""
    power,strap_width                                    ""
    power,tie_high_net                                   ""
    power,tie_low_net                                    ""
    power,vdd_net                                        ""
    power,vss_net                                        ""
}
