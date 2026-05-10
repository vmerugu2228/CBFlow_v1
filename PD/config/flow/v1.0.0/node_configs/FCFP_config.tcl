#!/usr/bin/env tclsh
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║             FCFP - HIERARCHICAL DESIGN PLANNING FLOW CONFIGURATION          ║
# ║                    FC-RM Y-2026.03 DP Hier Aligned                          ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# Maps to FC-RM rm_fc_dp_hier_scripts/:
#   init_dp → commit_blocks → init_compile → create_floorplan → shaping →
#   placement → create_power → clock_trunk → place_pins → top_compile →
#   timing_budget → write_data
#
# Usage: source config/flow/v1.0.0/node_configs/FCFP_config.tcl

# ┌─ Flow Stage Definitions ──────────────────────────────────────────────┐
array set fcfp {
    stages {inputs1 init_design1 commit_blocks1 init_compile1 create_floorplan1 shaping1 placement1 create_power1 place_pins1 top_compile1 timing_budget1 export_data1 release_data1}

    subnodes,inputs1           {setup netlist sdc def upf library validate finish}
    subnodes,init_design1      {setup run validate finish}
    subnodes,commit_blocks1    {setup run validate finish}
    subnodes,init_compile1     {setup run validate finish}
    subnodes,create_floorplan1 {setup run validate finish}
    subnodes,shaping1          {setup run validate finish}
    subnodes,placement1        {setup run validate finish}
    subnodes,create_power1     {setup run validate finish}
    subnodes,place_pins1       {setup run validate finish}
    subnodes,top_compile1      {setup run validate finish}
    subnodes,timing_budget1    {setup run validate finish}
    subnodes,export_data1      {setup run validate finish}
    subnodes,release_data1     {setup run validate finish}
}

# ┌─ Stage Dependencies ────────────────────────────────────────────────────┐
array set fcfp {
    dependencies,inputs1           {}
    dependencies,init_design1      {inputs1}
    dependencies,commit_blocks1    {init_design1}
    dependencies,init_compile1     {commit_blocks1}
    dependencies,create_floorplan1 {init_compile1}
    dependencies,shaping1          {create_floorplan1}
    dependencies,placement1        {shaping1}
    dependencies,create_power1     {placement1}
    dependencies,place_pins1       {create_power1}
    dependencies,top_compile1      {place_pins1}
    dependencies,timing_budget1    {top_compile1}
    dependencies,export_data1      {timing_budget1}
    dependencies,release_data1     {export_data1}
}

# ┌─ Subnode Dependencies ──────────────────────────────────────────────────┐
array set fcfp {
    subnode_dependencies,inputs1,setup {}
    subnode_dependencies,inputs1,netlist {setup}
    subnode_dependencies,inputs1,sdc {setup}
    subnode_dependencies,inputs1,def {setup}
    subnode_dependencies,inputs1,upf {setup}
    subnode_dependencies,inputs1,library {setup}
    subnode_dependencies,inputs1,validate {netlist sdc def upf library}
    subnode_dependencies,inputs1,finish {validate}

    subnode_dependencies,init_design1,setup {}
    subnode_dependencies,init_design1,run {setup}
    subnode_dependencies,init_design1,validate {run}
    subnode_dependencies,init_design1,finish {validate}

    subnode_dependencies,commit_blocks1,setup {}
    subnode_dependencies,commit_blocks1,run {setup}
    subnode_dependencies,commit_blocks1,validate {run}
    subnode_dependencies,commit_blocks1,finish {validate}

    subnode_dependencies,init_compile1,setup {}
    subnode_dependencies,init_compile1,run {setup}
    subnode_dependencies,init_compile1,validate {run}
    subnode_dependencies,init_compile1,finish {validate}

    subnode_dependencies,create_floorplan1,setup {}
    subnode_dependencies,create_floorplan1,run {setup}
    subnode_dependencies,create_floorplan1,validate {run}
    subnode_dependencies,create_floorplan1,finish {validate}

    subnode_dependencies,shaping1,setup {}
    subnode_dependencies,shaping1,run {setup}
    subnode_dependencies,shaping1,validate {run}
    subnode_dependencies,shaping1,finish {validate}

    subnode_dependencies,placement1,setup {}
    subnode_dependencies,placement1,run {setup}
    subnode_dependencies,placement1,validate {run}
    subnode_dependencies,placement1,finish {validate}

    subnode_dependencies,create_power1,setup {}
    subnode_dependencies,create_power1,run {setup}
    subnode_dependencies,create_power1,validate {run}
    subnode_dependencies,create_power1,finish {validate}

    subnode_dependencies,place_pins1,setup {}
    subnode_dependencies,place_pins1,run {setup}
    subnode_dependencies,place_pins1,validate {run}
    subnode_dependencies,place_pins1,finish {validate}

    subnode_dependencies,top_compile1,setup {}
    subnode_dependencies,top_compile1,run {setup}
    subnode_dependencies,top_compile1,validate {run}
    subnode_dependencies,top_compile1,finish {validate}

    subnode_dependencies,timing_budget1,setup {}
    subnode_dependencies,timing_budget1,run {setup}
    subnode_dependencies,timing_budget1,validate {run}
    subnode_dependencies,timing_budget1,finish {validate}

    subnode_dependencies,export_data1,setup {}
    subnode_dependencies,export_data1,run {setup}
    subnode_dependencies,export_data1,validate {run}
    subnode_dependencies,export_data1,finish {validate}

    subnode_dependencies,release_data1,setup {}
    subnode_dependencies,release_data1,run {setup}
    subnode_dependencies,release_data1,validate {run}
    subnode_dependencies,release_data1,finish {validate}
}

# ┌─ Tool Configuration ────────────────────────────────────────────────────┐
array set fcfp {
    tool,vendor "synopsys"
    tool,name "fc"
    tool,version "v1.0.0"
    tool,args "-batch -no_gui"
    supported_tools {fc innovus}
    default_tool "fc"
}

# ┌─ Runtime Settings ───────────────────────────────────────────────────────┐
array set fcfp {
    runtime,timeout,inputs1           25
    runtime,timeout,init_design1      30
    runtime,timeout,commit_blocks1    30
    runtime,timeout,init_compile1     90
    runtime,timeout,create_floorplan1 60
    runtime,timeout,shaping1          45
    runtime,timeout,placement1        60
    runtime,timeout,create_power1     60
    runtime,timeout,place_pins1       30
    runtime,timeout,top_compile1      90
    runtime,timeout,timing_budget1    45
    runtime,timeout,export_data1      20
    runtime,timeout,release_data1     15
}

# ┌─ Stage Type Mappings and Descriptions ───────────────────────────────────┐
array set fcfp {
    stage_types,inputs1           "inputs"
    stage_types,init_design1      "execution"
    stage_types,commit_blocks1    "execution"
    stage_types,init_compile1     "execution"
    stage_types,create_floorplan1 "execution"
    stage_types,shaping1          "execution"
    stage_types,placement1        "execution"
    stage_types,create_power1     "execution"
    stage_types,place_pins1       "execution"
    stage_types,top_compile1      "execution"
    stage_types,timing_budget1    "execution"
    stage_types,export_data1      "export_data"
    stage_types,release_data1     "release_data"

    node_types,inputs1           "inputs"
    node_types,init_design1      "init_design"
    node_types,commit_blocks1    "commit_blocks"
    node_types,init_compile1     "init_compile"
    node_types,create_floorplan1 "create_floorplan"
    node_types,shaping1          "shaping"
    node_types,placement1        "placement"
    node_types,create_power1     "create_power"
    node_types,place_pins1       "place_pins"
    node_types,top_compile1      "top_compile"
    node_types,timing_budget1    "timing_budget"
    node_types,export_data1      "export_data"
    node_types,release_data1     "release_data"

    node_descriptions,inputs1           "Input file validation and preparation"
    node_descriptions,init_design1      "Hier DP init: create_lib, read RTL/netlist, UPF, SDC (FC-RM init_dp)"
    node_descriptions,commit_blocks1    "Commit block references, split constraints (FC-RM commit_blocks)"
    node_descriptions,init_compile1     "Initial hierarchical compile for area estimation (FC-RM init_compile)"
    node_descriptions,create_floorplan1 "Initialize floorplan, macro placement, boundary/tap cells (FC-RM create_floorplan)"
    node_descriptions,shaping1          "Shape hierarchical block outlines and channels (FC-RM shaping)"
    node_descriptions,placement1        "Hierarchical block and macro placement (FC-RM placement)"
    node_descriptions,create_power1     "Power network synthesis and PG routing (FC-RM create_power)"
    node_descriptions,place_pins1       "Pin placement and legalization (FC-RM place_pins)"
    node_descriptions,top_compile1      "Top-level compile and optimization (FC-RM top_compile)"
    node_descriptions,timing_budget1    "Timing budget creation and distribution (FC-RM timing_budget)"
    node_descriptions,export_data1      "Export hierarchical design data"
    node_descriptions,release_data1     "Release FCFP deliverables"
}

# ┌─ FC-RM Init DP Control ────────────────────────────────────────────────┐
array set fcfp {
    design_style            "hier"
    physical_hierarchy_level "top"
    output,block_labeling   true
}

# ┌─ FC-RM Commit Blocks Control ─────────────────────────────────────────┐
array set fcfp {
    sub_block_refs          {}
    sub_block_libraries     {}
}

# ┌─ FC-RM Init Compile Control ──────────────────────────────────────────┐
array set fcfp {
    compile,qor_metric      "timing"
    compile,qor_mode        "balanced"
    compile,reduced_effort  true
    compile,stage           "logic_opto"
}

# ┌─ FC-RM Create Floorplan Control ──────────────────────────────────────┐
array set fcfp {
    floorplan,die_width         ""
    floorplan,die_height        ""
    floorplan,core_utilization  0.65
    floorplan,core_aspect_ratio 1.0
    floorplan,macro_placement   true
    floorplan,macro_spacing     "5.0"
    floorplan,boundary_cells    true
    floorplan,tap_cells         true
    floorplan,place_pins        true
}

# ┌─ FC-RM Shaping Control ───────────────────────────────────────────────┐
array set fcfp {
    shaping,style               "channel"
    shaping,min_channel_width   ""
    shaping,target_utilization  ""
}

# ┌─ FC-RM Placement Control ─────────────────────────────────────────────┐
array set fcfp {
    placement,congestion_driven true
    placement,timing_driven     true
    placement,push_down_rows    true
}

# ┌─ FC-RM Create Power Control ──────────────────────────────────────────┐
array set fcfp {
    power,net_names             "VDD VSS"
    power,ring_width            "3.0"
    power,ring_spacing          "1.0"
    power,strap_width           "1.0"
    power,strap_pitch           "20.0"
    power,mesh_layers           "M8 M9 M10"
    powerplan,pns_file          ""
    powerplan,stdcell_placement true
}

# ┌─ FC-RM Place Pins Control ────────────────────────────────────────────┐
array set fcfp {
    place_pins,legalize         true
    place_pins,constraint_file  ""
    place_pins,fix_ports        true
}

# ┌─ FC-RM Top Compile Control ───────────────────────────────────────────┐
array set fcfp {
    top_compile,from_stage      "logic_opto"
    top_compile,to_stage        "logic_opto"
}

# ┌─ FC-RM Timing Budget Control ─────────────────────────────────────────┐
array set fcfp {
    timing_budget,estimate_timing  true
    timing_budget,distribute       true
}

# ┌─ Output Control ──────────────────────────────────────────────────────┐
array set fcfp {
    output,write_def            true
    output,write_floorplan      true
    output,report_dir           "reports/fcfp"
    output,results_dir          "results/fcfp"
    output,work_dir             "work/FCFP"
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                              INITIALIZATION                                 ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

if {![info exists ::fcfp_config_loaded]} {
    puts "INFO: FCFP configuration loaded successfully - [llength $fcfp(stages)] stages"
    set ::fcfp_config_loaded true
}

# ┌─ Release Configuration ────────────────────────────────────────────────────┐
array set fcfp {
    release_types,floorplan,description "FCFP hierarchical floorplan deliverables"
    release_types,floorplan,files {
        "work/FCFP/export_data1/reports/report_qor.rpt"  "reports/fcfp_qor.rpt"
        "work/FCFP/placement1/reports/report_timing.max.rpt" "reports/fcfp_timing.rpt"
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# END OF FCFP CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════════
