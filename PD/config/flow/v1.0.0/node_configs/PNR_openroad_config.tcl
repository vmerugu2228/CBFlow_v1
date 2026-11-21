#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# PNR — Open-source tool configuration (OpenROAD + KLayout)
# Sourced from PNR_config.tcl when pnr(tool,name) = openroad.
# Input: the SYNTH release (netlist + SDC + UPF) — pnr(input,release_tag).
# Command files: PD/cmds/PNR/opensource/openroad/v1.0.0/
# Tools run inside the CBflow tool container (global/bin/cbflow-oss).
# ═══════════════════════════════════════════════════════════════════════════════

array set pnr {
    tool,vendor   "opensource"
    tool,name     "openroad"
    tool,version  "v1.0.0"
    tool,args     ""
}

# ┌─ Stage list: the floorplan is built here, so no DEF input ─────────────────┐
array set pnr {
    stages {netlist1 sdc1 upf1 init_design1 place1 cts1 cts_opt1 route1 pro1 signoff1 export_data1 release_data1}
    dependencies,init_design1 {netlist1 sdc1 upf1}

    mandatory_user_inputs {
        pnr(input,netlist)
        pnr(input,sdc_func_file)
        pnr(input,upf_file)
    }
    mandatory_input_groups {
        netlist_inputs {pnr(input,netlist)}
        sdc_inputs {pnr(input,sdc_release_tag) pnr(input,sdc_release_dir) pnr(input,sdc_func_file)}
        upf_inputs {pnr(input,upf_file)}
    }
}
unset -nocomplain pnr(dependencies,def1) pnr(node_types,def1) pnr(stage_types,def1) \
    pnr(runtime,timeout,def1) pnr(subnode_input_types,def1,def) pnr(critical_files,place1)

# ┌─ Tool binary per stage (lsf(tool_shell,<tool>) → cbflow-oss) ──────────────┐
array set pnr {
    oss,tool,init_design  "openroad"
    oss,tool,place        "openroad"
    oss,tool,cts          "openroad"
    oss,tool,cts_opt      "openroad"
    oss,tool,route        "openroad"
    oss,tool,pro          "openroad"
    oss,tool,signoff      "openroad"
    oss,tool,export_data  "oss_tclsh"
    oss,tool,release_data "oss_tclsh"
}

# ┌─ Floorplan / placement (OpenROAD) ─────────────────────────────────────────┐
# oss,fp,die_area {x0 y0 x1 y1} (µm) overrides utilization-based sizing — use
# it for blocks that integrate hard macros.
# oss,macro,placement {inst x y orient ...} overrides rtl_macro_placer.
array set pnr {
    oss,fp,die_area          ""
    oss,fp,core_utilization  45
    oss,fp,aspect_ratio      1.0
    oss,fp,core_margin       10
    oss,pins,hor_layer       "met3"
    oss,pins,ver_layer       "met2"
    oss,macro,halo           10
    oss,macro,placement      ""
    oss,place,density        0.55
}

# ┌─ Optimization / routing ───────────────────────────────────────────────────┐
# oss,threads: OpenROAD worker threads. Detailed-route memory grows with it —
# 6 threads route a ~140k-cell sky130 block within a 12 GB container.
# oss,cts,apply_ndr: clock non-default rule (none | root_only | half | full).
# "none": the NDR clock root left sub-minimum-area met3 via pads that the
# router did not repair (Magic met3.6) on sky130.
array set pnr {
    oss,threads              6
    oss,cts,apply_ndr        "none"
    oss,repair,setup_margin  0.0
    oss,repair,hold_margin   0.05
    oss,route,max_drc        0
    oss,fail_on_violations   false
}
# oss,fail_on_violations: false = detailed-route DRC above oss,route,max_drc
# and power-grid connectivity failures are reported and the flow continues;
# true = the stage fails (sign-off mode).

# ┌─ GDS stream-out ───────────────────────────────────────────────────────────┐
# oss,export,min_area_layers {gds_layer gds_datatype min_area_um2 ...}: layers
# whose undersized routing polygons are grown to the minimum at stream-out
# (sky130 met2 / met3 / met4 drawing: {69 20 0.0676 70 20 0.24 71 20 0.24}).
# Empty = off: violations are left in the layout and reported by PV DRC.
array set pnr {
    oss,export,min_area_layers {}
}

# ┌─ SmartGrid ────────────────────────────────────────────────────────────────┐
# Exit milestone a PNR release fills in SmartGrid (MILESTONE_STAGE_MAPPING:
# BTO = after signoff). Published by `cbflow run all` when the run passes
# and the project's SmartGrid daemon is running.
array set pnr {
    smartgrid,milestone "BTO"
}

# ┌─ Runtime (minutes) — large blocks route longer than the FC defaults ───────┐
array set pnr {
    runtime,timeout,place1     240
    runtime,timeout,route1     600
    runtime,timeout,pro1       240
    runtime,timeout,signoff1   240
}

# ┌─ Inputs consumed per stage ─────────────────────────────────────────────────┐
set pnr(required_inputs,init_design1)  "work/PNR/netlist1/netlist work/PNR/sdc1/sdc work/PNR/upf1/upf"
set pnr(required_inputs,place1)        "work/PNR/init_design1/outputs/init_design.odb"
set pnr(required_inputs,cts1)          "work/PNR/place1/outputs/place.odb"
set pnr(required_inputs,cts_opt1)      "work/PNR/cts1/outputs/cts.odb"
set pnr(required_inputs,route1)        "work/PNR/cts_opt1/outputs/cts_opt.odb"
set pnr(required_inputs,pro1)          "work/PNR/route1/outputs/route.odb"
set pnr(required_inputs,signoff1)      "work/PNR/pro1/outputs/pro.odb"
set pnr(required_inputs,export_data1)  "work/PNR/signoff1/outputs/final.def"
set pnr(required_inputs,release_data1) "work/PNR/export_data1/outputs/final.gds"

# ┌─ Mandatory outputs (relative to work/PNR/<node>/outputs/) ────────────┐
set pnr(mandatory_outputs,init_design1)  {init_design.odb}
set pnr(mandatory_outputs,place1)        {place.odb}
set pnr(mandatory_outputs,cts1)          {cts.odb}
set pnr(mandatory_outputs,cts_opt1)      {cts_opt.odb}
set pnr(mandatory_outputs,route1)        {route.odb}
set pnr(mandatory_outputs,pro1)          {pro.odb}
set pnr(mandatory_outputs,signoff1)      {final.odb final.def final.v final.lvs.v final.lef final.sdc}
set pnr(mandatory_outputs,export_data1)  {final.gds}
set pnr(mandatory_outputs,release_data1) {release.manifest}
