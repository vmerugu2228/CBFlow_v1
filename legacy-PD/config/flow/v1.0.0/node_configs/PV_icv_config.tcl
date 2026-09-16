#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# PV — Synopsys ICV Tool Configuration
# Sourced from PV_config.tcl when tool=icv
# ═══════════════════════════════════════════════════════════════════════════════

# ┌─ ICV Tool Settings ───────────────────────────────────────────────────────┐
array set pv {
    tool,vendor   "synopsys"
    tool,name     "icv"
    tool,version  "v1.0.0"
    tool,args     "-batch -no_gui"
}

# ┌─ PV App Settings (moved from common PV_config.tcl) ────────────────────────┐
array set pv {
    drc,abort_limit            0
    drc,max_results            1000
    lvs,property_mapping       ""
    lvs,abort_on_mismatch      false
}

# ┌─ ICV-RM V-2023.12 Configuration Variables ────────────────────────────────┐
array set pv {
    icv,design_state       "MATURE"
    icv,library_format     "GDSII"
    icv,num_cpus           8
    icv,include_paths      ""
}

# ┌─ ICV DRC Settings ────────────────────────────────────────────────────────┐
array set pv {
    drc,runset             ""
    drc,antenna_runset     ""
    drc,num_cpus           8
    drc,error_limit        1000
    drc,blackbox_cells     ""
    drc,blackbox_layers    ""
}

# ┌─ ICV LVS Settings ────────────────────────────────────────────────────────┐
array set pv {
    lvs,runset             ""
    lvs,equiv_file         ""
    lvs,schematic_netlist  ""
    lvs,top_subckt_name    ""
    lvs,num_cpus           8
}

# ┌─ ICV Fill Settings ───────────────────────────────────────────────────────┐
array set pv {
    fill,feol_runset       ""
    fill,beol_runset       ""
    fill,num_cpus          8
    fill,metal_stack       ""
    fill,met1_direction    "HORIZONTAL"
}

# ┌─ ICV PERC Settings ───────────────────────────────────────────────────────┐
array set pv {
    perc,runset            ""
    perc,schematic_netlist ""
    perc,num_cpus          8
}

# ┌─ ICV ERC Settings ────────────────────────────────────────────────────────┐
array set pv {
    erc,runset             ""
    erc,num_cpus           4
}

# ── ICV-RM App Variables ──────────────────────────────────────────────
# --- COMMON (3 vars) ---
array set pv {
    common,design_name                                   ""
    common,release_phase                                 ""
    common,top_cell                                      ""
}

# --- DRC (4 vars) ---
array set pv {
    drc,max_results                                      ""
    drc,rule_deck                                        ""
    drc,select_rules                                     ""
    drc,threads                                          ""
}

# --- ERC (4 vars) ---
array set pv {
    erc,ground_nets                                      ""
    erc,power_nets                                       ""
    erc,rule_deck                                        ""
    erc,threads                                          ""
}

# --- FILL (5 vars) ---
array set pv {
    fill,beol_runset                                     ""
    fill,feol_runset                                     ""
    fill,met1_direction                                  ""
    fill,metal_stack                                     ""
    fill,num_cpus                                        ""
}

# --- ICV (4 vars) ---
array set pv {
    icv,design_state                                     ""
    icv,include_paths                                    ""
    icv,library_format                                   ""
    icv,num_cpus                                         ""
}

# --- LVS (4 vars) ---
array set pv {
    lvs,flatten                                          ""
    lvs,rule_deck                                        ""
    lvs,source_netlist                                   ""
    lvs,threads                                          ""
}

# --- ODFILL (1 vars) ---
array set pv {
    odfill,runset                                        ""
}

# --- PERC (5 vars) ---
array set pv {
    perc,esd_check                                       ""
    perc,latchup_check                                   ""
    perc,rule_deck                                       ""
    perc,threads                                         ""
    perc,voltage_aware                                   ""
}
