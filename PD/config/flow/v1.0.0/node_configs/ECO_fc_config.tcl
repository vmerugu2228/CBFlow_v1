#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# ECO — Synopsys Fusion Compiler (FC) Tool Configuration
# Sourced from ECO_config.tcl when tool=fc
# ═══════════════════════════════════════════════════════════════════════════════

# ┌─ FC Tool Settings ────────────────────────────────────────────────────────┐
array set eco {
    tool,vendor   "synopsys"
    tool,name     "fc"
    tool,version  "v1.0.0"
    tool,args     "-batch -no_gui"
}

# ┌─ ECO App Settings (moved from common ECO_config.tcl) ──────────────────────┐
array set eco {
    eco,type                   "functional"
    eco,metal_eco              true
    eco,cell_replacement       true
    eco,spare_cell_prefix      "SPARE_"
    eco,legalize_placement     true
    eco,reroute_modified       true
    eco,incr_route_post        true
}

# ┌─ FC-RM Timing ECO Control ────────────────────────────────────────────────┐
array set eco {
    eco,engine                  "smsa"
    eco,pba_mode                "path"
    eco,extraction_mode         "fusion_adv"
    eco,filler_cell_prefix      "FILL"
}

# ┌─ FC-RM Functional ECO Control ────────────────────────────────────────────┐
array set eco {
    eco,mode                    "mpi"
}

# ── FC-RM App Variables ──────────────────────────────────────────────
# --- ANALYSIS (1 vars) ---
array set eco {
    analysis,max_paths                                   ""
}

# --- COMMON (6 vars) ---
array set eco {
    common,design_lib_name                               ""
    common,design_name                                   ""
    common,eco_post_script                               ""
    common,eco_pre_script                                ""
    common,non_persistent_script                         ""
    common,top_cell                                      ""
}

# --- ECO (13 vars) ---
array set eco {
    eco,active_scenarios                                 ""
    eco,custom_options                                   ""
    eco,engine                                           ""
    eco,extraction_mode                                  ""
    eco,filler_cell_prefix                               ""
    eco,incr_route_post                                  ""
    eco,legalize_placement                               ""
    eco,mode                                             ""
    eco,pba_mode                                         ""
    eco,pt_exec_path                                     ""
    eco,recipe                                           ""
    eco,starrc_config                                    ""
    eco,type                                             ""
}

# --- EXPORT (2 vars) ---
array set eco {
    export,incremental_def                               ""
    export,pg_netlist                                    ""
}

# --- OUTPUT (1 vars) ---
array set eco {
    output,block_labeling                                ""
}
