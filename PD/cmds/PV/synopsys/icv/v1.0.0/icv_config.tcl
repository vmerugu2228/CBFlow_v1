#!/usr/bin/env tclsh
# =============================================================================
# ICV Tool Configuration - PV Flow
# =============================================================================
# Convention: icv(common,var) shared, icv(<node>,var) node-specific
# Override: set icv(<key>) "value" in user_config.tcl
# =============================================================================

# --- COMMON (3 vars) ---
array set icv {
    common,design_name                                   ""
    common,release_phase                                 ""
    common,top_cell                                      ""
}

# --- DRC (4 vars) ---
array set icv {
    drc,max_results                                      ""
    drc,rule_deck                                        ""
    drc,select_rules                                     ""
    drc,threads                                          ""
}

# --- ERC (4 vars) ---
array set icv {
    erc,ground_nets                                      ""
    erc,power_nets                                       ""
    erc,rule_deck                                        ""
    erc,threads                                          ""
}

# --- FILL (5 vars) ---
array set icv {
    fill,beol_runset                                     ""
    fill,feol_runset                                     ""
    fill,met1_direction                                  ""
    fill,metal_stack                                     ""
    fill,num_cpus                                        ""
}

# --- ICV (4 vars) ---
array set icv {
    icv,design_state                                     ""
    icv,include_paths                                    ""
    icv,library_format                                   ""
    icv,num_cpus                                         ""
}

# --- LVS (4 vars) ---
array set icv {
    lvs,flatten                                          ""
    lvs,rule_deck                                        ""
    lvs,source_netlist                                   ""
    lvs,threads                                          ""
}

# --- ODFILL (1 vars) ---
array set icv {
    odfill,runset                                        ""
}

# --- PERC (5 vars) ---
array set icv {
    perc,esd_check                                       ""
    perc,latchup_check                                   ""
    perc,rule_deck                                       ""
    perc,threads                                         ""
    perc,voltage_aware                                   ""
}

