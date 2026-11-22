#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# FP — Open-source tool configuration (OpenROAD)
# Sourced from FP_config.tcl when fp(tool,name) = openroad.
# Input: the SYNTH release (netlist + SDC + UPF) — fp(input,release_tag).
# Output: the floorplan release (<phase>_FP_v<n>: DEF + db + netlist + SDC +
# UPF) that PNR consumes — pnr(input,def_file_release_tag).
# Command files: PD/cmds/FP/opensource/openroad/v1.0.0/
# Tools run inside the CBflow tool container (global/bin/cbflow-oss).
# ═══════════════════════════════════════════════════════════════════════════════

array set fp {
    tool,vendor   "opensource"
    tool,name     "openroad"
    tool,version  "v1.0.0"
    tool,args     ""
}

# ┌─ Stage list: libraries come from the library tag; no DEF input ────────────┐
array set fp {
    stages {netlist1 sdc1 upf1 init_design1 floorplan1 powerplan1 export_data1 release_data1}
    dependencies,init_design1 {netlist1 sdc1 upf1}

    mandatory_user_inputs {
        fp(input,netlist)
        fp(input,sdc_func_file)
        fp(input,upf_file)
    }
    mandatory_input_groups {
        netlist_inputs {fp(input,netlist)}
        sdc_inputs {fp(input,sdc_release_tag) fp(input,sdc_release_dir) fp(input,sdc_func_file)}
        upf_inputs {fp(input,upf_file)}
    }
}
foreach _s {def1 library1} {
    array unset fp "*,$_s"
    array unset fp "*,$_s,*"
}
unset _s
set fp(critical_files,floorplan1) {fp(input,netlist)}

# ┌─ Tool binary per stage (lsf(tool_shell,<tool>) → cbflow-oss) ──────────────┐
array set fp {
    oss,tool,init_design  "openroad"
    oss,tool,floorplan    "openroad"
    oss,tool,powerplan    "openroad"
    oss,tool,export_data  "openroad"
    oss,tool,release_data "oss_tclsh"
    oss,threads           6
}

# ┌─ Floorplan (OpenROAD) ─────────────────────────────────────────────────────┐
# oss,fp,die_area {x0 y0 x1 y1} (µm) overrides utilization-based sizing — use
# it for blocks that integrate hard macros.
# core_utilization = standard-cell utilization % (macro blocks add macro area on
# top). Default here; set per block in user_config: fp(oss,fp,core_utilization).
# oss,macro,placement {inst x y orient ...} overrides rtl_macro_placer; "row" =
# macros in one row from the core corner, oss,fp,macro_channel (um) apart —
# the std-cell / routing band kept around macros by utilization sizing.
array set fp {
    oss,fp,die_area          ""
    oss,fp,core_utilization  45
    oss,fp,aspect_ratio      1.0
    oss,fp,core_margin       10
    oss,fp,macro_channel     60
    oss,pins,hor_layer       "met3"
    oss,pins,ver_layer       "met2"
    oss,macro,halo           10
    oss,macro,placement      ""
    oss,fail_on_violations   false
}
# oss,fail_on_violations: false = power-grid connectivity failures are
# reported and the flow continues; true = the stage fails.

# ┌─ SmartGrid ────────────────────────────────────────────────────────────────┐
# Exit milestone an FP release fills in SmartGrid (MILESTONE_ORDER: first).
array set fp {
    smartgrid,milestone "FP_EXIT"
}

# ┌─ Exit checklist data (this tool) ─────────────────────────────────────────┐
# Read by `cbflow flow checklist` and at SmartGrid publish: which node holds
# each exit's reports and how to read each check's value from
# reports/checklist_metrics.rpt (written by oss_checklist_metrics). Check
# names, operators and thresholds stay in global/config/exit/.
array set fp {
    checklist,exit_node,FP_EXIT      export_data1
    checklist,report               "work/FP/${exit_node}/reports/checklist_metrics.rpt"
    checklist,mandatory_files,FP_EXIT "work/FP/${exit_node}/outputs/final.def work/FP/${exit_node}/reports/checklist_metrics.rpt"
    checklist,grep,fp_qor                        {^Setup WNS\s*:}
    checklist,metric,fp_utilization              {^Utilization\s*:\s*([0-9.]+)}
    checklist,grep,fp_design_summary             {^Design\s*:}
    checklist,metric,fp_timing_estimate          {^Setup WNS\s*:\s*(-?[0-9.]+(?:[eE][-+]?[0-9]+)?)}
    checklist,metric,macro_spacing               {^Macro spacing violations\s*:\s*(\d+)}
    checklist,metric,macro_orientation           {^Macro orientation violations\s*:\s*(\d+)}
    checklist,metric,io_placement_legality       {^IO placement violations\s*:\s*(\d+)}
}

# ┌─ Inputs consumed per stage ─────────────────────────────────────────────────┐
set fp(required_inputs,init_design1)  "work/FP/netlist1/netlist work/FP/sdc1/sdc work/FP/upf1/upf"
set fp(required_inputs,floorplan1)    "work/FP/init_design1/outputs/init_design.odb"
set fp(required_inputs,powerplan1)    "work/FP/floorplan1/outputs/floorplan.odb"
set fp(required_inputs,export_data1)  "work/FP/powerplan1/outputs/powerplan.odb"
set fp(required_inputs,release_data1) "work/FP/export_data1/outputs/final.def"

# ┌─ Mandatory outputs (relative to work/FP/<node>/outputs/) ──────────────────┐
set fp(mandatory_outputs,init_design1)  {init_design.odb}
set fp(mandatory_outputs,floorplan1)    {floorplan.odb floorplan.def}
set fp(mandatory_outputs,powerplan1)    {powerplan.odb powerplan.def}
set fp(mandatory_outputs,export_data1)  {final.def final.odb final.v final.sdc}
set fp(mandatory_outputs,release_data1) {release.manifest}
