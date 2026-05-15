#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# Fusion Compiler Tool Configuration — SYNTH_PNR Flow
# ═══════════════════════════════════════════════════════════════════════════════
#
# All FC tool-specific variables organized in the fc() array.
# Convention:
#   fc(common,var)     — Used by multiple nodes (design_name, chip_type, etc.)
#   fc(<node>,var)     — Used by a specific node only (place,effort, cts,style)
#
# Sourced by all *_fc.tcl command files after user_config.tcl and tech_config.tcl.
# Users can override any variable in user_config.tcl or override_config.tcl:
#   set fc(place,effort) "medium"
#
# Usage: source fc_config.tcl
# ═══════════════════════════════════════════════════════════════════════════════

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │ COMMON — Used across multiple nodes                                        │
# └─────────────────────────────────────────────────────────────────────────────┘

array set fc {
    common,design_name              ""
    common,design_lib_name          ""
    common,chip_type                "flat"
    common,upf_mode                 "golden"
    common,enable_fusa              "false"
    common,non_persistent_script    ""
    common,lib_cell_purpose_file    ""
    common,multi_vt_constraint_file ""
    common,mcmm_adjustment_file     ""
    common,connect_pg_net_script    ""
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │ COMPILE / QoR — Shared optimization settings                               │
# └─────────────────────────────────────────────────────────────────────────────┘

array set fc {
    common,compile,qor_version      ""
    common,compile,qor_metric       ""
    common,compile,qor_mode         ""
    common,compile,reduced_effort   "false"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │ INIT_DESIGN — Library creation, floorplan setup                            │
# └─────────────────────────────────────────────────────────────────────────────┘

array set fc {
    init_design,tech_setup_script   ""
    init_design,fp_tap_cell_distance "30"
    init_design,design_lib_scale_factor ""
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │ SYNTHESIS — Logic synthesis                                                │
# └─────────────────────────────────────────────────────────────────────────────┘

array set fc {
    synthesis,effort                "high"
    synthesis,active_scenarios      ""
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │ PLACE — Placement optimization                                            │
# └─────────────────────────────────────────────────────────────────────────────┘

array set fc {
    place,effort                    "high"
    place,timing_driven             "true"
    place,max_density               "0.70"
    place,congestion_aware          "true"
    place,opt_active_scenarios      ""
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │ CTS — Clock tree synthesis                                                 │
# └─────────────────────────────────────────────────────────────────────────────┘

array set fc {
    cts,style                       ""
    cts,redundant_via               ""
    cts,active_scenarios            ""
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │ CTS_OPT — Post-CTS optimization                                           │
# └─────────────────────────────────────────────────────────────────────────────┘

array set fc {
    cts_opt,active_scenarios        ""
    cts_opt,effort                  "high"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │ ROUTE — Detailed routing                                                   │
# └─────────────────────────────────────────────────────────────────────────────┘

array set fc {
    route,effort                    "high"
    route,opt_active_scenarios      ""
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │ PRO — Post-route optimization                                             │
# └─────────────────────────────────────────────────────────────────────────────┘

array set fc {
    pro,block_abstract              "false"
    pro,route_opt_sidefile          ""
    pro,opt_active_scenarios        ""
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │ SIGNOFF — Timing/power signoff                                            │
# └─────────────────────────────────────────────────────────────────────────────┘

array set fc {
    signoff,active_scenarios        ""
    signoff,power_analysis          "true"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │ EXPORT_DATA — Write output data (GDS, DEF, netlist)                        │
# └─────────────────────────────────────────────────────────────────────────────┘

array set fc {
    export_data,write_gds           "true"
    export_data,write_oasis         "false"
    export_data,def_convert_sites   "false"
    export_data,block_labeling      "false"
    export_data,name_rules          ""
    export_data,pre_script          ""
    export_data,post_script         ""
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │ RELEASE_DATA — Release packaging                                           │
# └─────────────────────────────────────────────────────────────────────────────┘

array set fc {
    release_data,release_phase      "P0"
    release_data,include_gds        "true"
    release_data,include_netlist    "true"
}

# ═══════════════════════════════════════════════════════════════════════════════
# NOTE: Users can override any fc() variable in:
#   - setup/user_config.tcl:       set fc(place,effort) "medium"
#   - setup/override_config.*.tcl: set fc(place,max_density) "0.65"
# ═══════════════════════════════════════════════════════════════════════════════
