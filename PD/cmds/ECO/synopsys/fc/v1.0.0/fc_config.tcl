#!/usr/bin/env tclsh
# =============================================================================
# FC Tool Configuration - ECO Flow
# =============================================================================
# Convention: fc(common,var) shared, fc(<node>,var) node-specific
# Override: set fc(<key>) "value" in user_config.tcl
# =============================================================================

# --- ANALYSIS (1 vars) ---
array set fc {
    analysis,max_paths                                   ""
}

# --- COMMON (6 vars) ---
array set fc {
    common,design_lib_name                               ""
    common,design_name                                   ""
    common,eco_post_script                               ""
    common,eco_pre_script                                ""
    common,non_persistent_script                         ""
    common,top_cell                                      ""
}

# --- ECO (13 vars) ---
array set fc {
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
array set fc {
    export,incremental_def                               ""
    export,pg_netlist                                    ""
}

# --- OUTPUT (1 vars) ---
array set fc {
    output,block_labeling                                ""
}

