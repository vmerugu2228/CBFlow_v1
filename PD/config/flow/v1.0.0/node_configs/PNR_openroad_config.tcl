#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# PNR — Open-source tool configuration (OpenROAD + KLayout)
# Sourced from PNR_config.tcl when pnr(tool,name) = openroad.
# Inputs: the SYNTH release (netlist + SDC + UPF) — pnr(input,release_tag) —
# and the FP release (floorplan DEF) — pnr(input,def_file_release_tag).
# Command files: PD/cmds/PNR/opensource/openroad/v1.0.0/
# Tools run inside the CBflow tool container (global/bin/cbflow-oss).
# ═══════════════════════════════════════════════════════════════════════════════

array set pnr {
    tool,vendor   "opensource"
    tool,name     "openroad"
    tool,version  "v1.0.0"
    tool,args     ""
}

# ┌─ Stage list: floorplan DEF from the FP flow; libraries from the lib tag ──┐
array set pnr {
    stages {netlist1 sdc1 def1 upf1 init_design1 place1 cts1 cts_opt1 route1 pro1 signoff1 export_data1 release_data1}
    dependencies,init_design1 {netlist1 sdc1 def1 upf1}

    mandatory_user_inputs {
        pnr(input,netlist)
        pnr(input,sdc_func_file)
        pnr(input,def_file)
        pnr(input,upf_file)
    }
    mandatory_input_groups {
        netlist_inputs {pnr(input,netlist)}
        sdc_inputs {pnr(input,sdc_release_tag) pnr(input,sdc_release_dir) pnr(input,sdc_func_file)}
        def_inputs {pnr(input,def_file)}
        upf_inputs {pnr(input,upf_file)}
    }
}
unset -nocomplain pnr(critical_files,place1)

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

# ┌─ Placement (OpenROAD) — floorplan knobs live in FP_openroad_config.tcl ───┐
# Default; set per block in user_config: pnr(oss,place,density).
array set pnr {
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
# oss,export,klayout_batch: KLayout batch command (run inside the tool
# container — export_data is an oss_tclsh stage) + the script to run.
# oss,export,layout_image,*: routed-layout PNG written next to final.gds
# (reporting only); oss,release,layout_image,*: its release dir / name
# (SmartGrid reads images/routing_layout.png).
set pnr(oss,export,klayout_batch)          {klayout -zz -r}
set pnr(oss,export,layout_image,file)       "layout.png"
set pnr(oss,export,layout_image,size)       1600
set pnr(oss,export,layout_image,background) "#ffffff"
set pnr(oss,release,layout_image,dir)       "images"
set pnr(oss,release,layout_image,file)      "routing_layout.png"

# ┌─ Reports / release ────────────────────────────────────────────────────────┐
# oss,qor_file_suffix: per-stage QoR metrics file reports/<stage><suffix>
# (oss_write_qor). oss,release,report_stages: stage types whose reports/
# land in the release under reports/<node>/.
array set pnr {
    oss,qor_file_suffix       "_qor.tcl"
    oss,release,report_stages {init_design place cts cts_opt route pro signoff}
}

# ┌─ SmartGrid ────────────────────────────────────────────────────────────────┐
# Exit milestone a PNR release fills in SmartGrid (MILESTONE_STAGE_MAPPING:
# BTO = after signoff). Published by `cbflow run all` when the run passes
# and the project's SmartGrid daemon is running.
array set pnr {
    smartgrid,milestone "BTO"
}

# ┌─ Exit checklist data (this tool) ─────────────────────────────────────────┐
# Read by `cbflow flow checklist` and at SmartGrid publish: which node holds
# each exit's reports and how to read each check's value from
# reports/checklist_metrics.rpt (written by oss_checklist_metrics). Check
# names, operators and thresholds stay in global/config/exit/.
array set pnr {
    checklist,exit_node,FP_EXIT      init_design1
    checklist,exit_node,PLACE_EXIT   place1
    checklist,exit_node,CTS_EXIT     cts_opt1
    checklist,exit_node,PRO_EXIT     pro1
    checklist,exit_node,BTO          signoff1
    checklist,exit_node,MTO          signoff1
    checklist,report               "work/PNR/${exit_node}/reports/checklist_metrics.rpt"
    checklist,mandatory_files,PRO_EXIT "work/PNR/${exit_node}/outputs/pro.odb work/PNR/${exit_node}/reports/checklist_metrics.rpt"
    checklist,grep,fp_qor                        {^Setup WNS\s*:}
    checklist,metric,fp_utilization              {^Utilization\s*:\s*([0-9.]+)}
    checklist,grep,fp_design_summary             {^Design\s*:}
    checklist,metric,fp_timing_estimate          {^Setup WNS\s*:\s*(-?[0-9.]+(?:[eE][-+]?[0-9]+)?)}
    checklist,metric,macro_spacing               {^Macro spacing violations\s*:\s*(\d+)}
    checklist,metric,macro_orientation           {^Macro orientation violations\s*:\s*(\d+)}
    checklist,metric,io_placement_legality       {^IO placement violations\s*:\s*(\d+)}
    checklist,grep,pro_qor                       {^Setup WNS\s*:}
    checklist,metric,pro_setup_timing            {^Setup WNS\s*:\s*(-?[0-9.]+(?:[eE][-+]?[0-9]+)?)}
    checklist,metric,pro_hold_timing             {^Hold WNS\s*:\s*(-?[0-9.]+(?:[eE][-+]?[0-9]+)?)}
    checklist,metric,pro_routing                 {^Routing opens\+shorts\s*:\s*(\d+)}
    checklist,metric,setup_wns                   {^Setup WNS\s*:\s*(-?[0-9.]+(?:[eE][-+]?[0-9]+)?)}
    checklist,metric,setup_tns                   {^Setup TNS\s*:\s*(-?[0-9.]+(?:[eE][-+]?[0-9]+)?)}
    checklist,metric,hold_wns                    {^Hold WNS\s*:\s*(-?[0-9.]+(?:[eE][-+]?[0-9]+)?)}
    checklist,metric,hold_tns                    {^Hold TNS\s*:\s*(-?[0-9.]+(?:[eE][-+]?[0-9]+)?)}
    checklist,metric,illegal_cells               {^Illegal cells\s*:\s*(\d+)}
    checklist,metric,cell_density                {^Utilization\s*:\s*([0-9.]+)}
    checklist,metric,clock_skew                  {^Clock skew ps\s*:\s*(-?[0-9.]+(?:[eE][-+]?[0-9]+)?)}
    checklist,metric,clock_insertion_delay       {^Clock insertion delay ps\s*:\s*(-?[0-9.]+(?:[eE][-+]?[0-9]+)?)}
    checklist,metric,routing_completion          {^Routing completion\s*:\s*([0-9.]+)}
    checklist,metric,opens                       {^Open nets\s*:\s*(\d+)}
    checklist,metric,shorts                      {^Shorts\s*:\s*(\d+)}
    checklist,metric,congestion_h                {^Overflow pct\s*:\s*([0-9.]+)}
    checklist,metric,congestion_v                {^Overflow pct\s*:\s*([0-9.]+)}
    checklist,metric,max_fanout_violations       {^Max fanout violations\s*:\s*(\d+)}
    checklist,metric,max_cap_violations          {^Max cap violations\s*:\s*(\d+)}
    checklist,metric,max_tran_violations         {^Max slew violations\s*:\s*(\d+)}
    checklist,metric,drc_total                   {^DRC violations\s*:\s*(\d+)}
}

# ┌─ Runtime (minutes) — large blocks route longer than the FC defaults ───────┐
array set pnr {
    runtime,timeout,place1     240
    runtime,timeout,route1     600
    runtime,timeout,pro1       240
    runtime,timeout,signoff1   240
}

# ┌─ Inputs consumed per stage ─────────────────────────────────────────────────┐
set pnr(required_inputs,init_design1)  "work/PNR/def1/def work/PNR/sdc1/sdc work/PNR/upf1/upf"
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

# ┌─ Path groups (timing by group: report + WNS / TNS per corner) ─────────────┐
# NAME {from to} — from / to: all_registers | all_inputs | all_outputs.
# report_paths: paths per <stage>_<setup|hold>_<group>_<corner>.rpt.
set pnr(oss,path_groups) {
    R2R {all_registers all_registers}
    I2R {all_inputs    all_registers}
    R2O {all_registers all_outputs}
    I2O {all_inputs    all_outputs}
}
set pnr(oss,path_groups,report_paths) 10
