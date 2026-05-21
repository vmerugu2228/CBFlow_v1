#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# PV — Siemens Calibre Tool Configuration
# Sourced from PV_config.tcl when tool=calibre
# ═══════════════════════════════════════════════════════════════════════════════

# ┌─ Calibre Tool Settings ───────────────────────────────────────────────────┐
array set pv {
    tool,vendor   "siemens"
    tool,name     "calibre"
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

# ┌─ Calibre DRC Settings ────────────────────────────────────────────────────┐
array set pv {
    drc,runset             ""
    drc,antenna_runset     ""
    drc,num_cpus           8
    drc,error_limit        1000
    drc,turbo_mode         true
    drc,hcell_file         ""
}

# ┌─ Calibre LVS Settings ────────────────────────────────────────────────────┐
array set pv {
    lvs,runset             ""
    lvs,hcell_file         ""
    lvs,spice_netlist      ""
    lvs,top_cell_name      ""
    lvs,num_cpus           8
    lvs,turbo_mode         true
}

# ┌─ Calibre Fill Settings ───────────────────────────────────────────────────┐
array set pv {
    fill,runset            ""
    fill,num_cpus          8
    fill,metal_stack       ""
}

# ┌─ Calibre PERC Settings ───────────────────────────────────────────────────┐
array set pv {
    perc,runset            ""
    perc,spice_netlist     ""
    perc,num_cpus          8
}

# ┌─ Calibre ERC Settings ────────────────────────────────────────────────────┐
array set pv {
    erc,runset             ""
    erc,num_cpus           4
}

# ── Calibre-RM App Variables (user overrides via user_config) ──
array set pv {
    common,design_name                                   ""
}
