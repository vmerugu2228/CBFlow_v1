#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# PV — Siemens Calibre Tool Configuration
# Sourced from PV_config.tcl when tool=calibre
# ═══════════════════════════════════════════════════════════════════════════════

# ┌─ Calibre Tool Settings ───────────────────────────────────────────────────┐
array set pv {
    tool,vendor   "mentor"
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
    fill,beol_runset       ""
    fill,feol_runset       ""
    fill,metal_stack       ""
}

# ┌─ Calibre Fill-Merge / Decomposition / Layout-Merge Settings ──────────────┐
# Read by fill_merge_gds_calibre.tcl / decomp_calibre.tcl / merge_gds_calibre.tcl
# / decomp_merge_gds_calibre.tcl (previously hard-coded in those scripts).
# fill_merge_gds,num_cpus replaces the old fill,num_cpus (the fill1 stage was
# removed; the script reads the fill_merge_gds key).
# *,outform is the calibredrv `layout filemerge -outform` value. The stage
# outputs keep their .gds file names (contract shared with the ICV scripts and
# the test-mode stubs) — set "GDSII" to make the content match the name.
array set pv {
    fill_merge_gds,num_cpus   8
    decomp,num_cpus           8
    decomp,colors             2
    perc_ldl,num_cpus         8
    merge_gds,outform         "OASIS"
    decomp_merge_gds,outform  "OASIS"
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

# ┌─ Calibre XOR Settings ───────────────────────────────────────────────────┐
array set pv {
    xor,runset             ""
    xor,num_cpus           4
}

# ── Calibre-RM App Variables (user overrides via user_config) ──
array set pv {
    common,design_name                                   ""
    common,top_cell                                      ""
}
