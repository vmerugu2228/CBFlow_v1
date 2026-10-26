#!/usr/bin/env tclsh
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║              PNR Flow Configuration (Tool-Independent)                      ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# Common stages, dependencies, subnodes — same for all tools (FC, Innovus).
# Tool-specific settings sourced from PNR_<tool>_config.tcl

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        STAGES & DEPENDENCIES                                ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set pnr {
    stages {netlist1 sdc1 def1 upf1 init_design1 place1 cts1 cts_opt1 route1 pro1 signoff1 export_data1 release_data1}

    merge_entry_stage     netlist1
    merge_handoff_stage   export_data1
    merge_parallel_stages {release_data1}

    dependencies,netlist1          {}
    dependencies,sdc1              {}
    dependencies,def1              {}
    dependencies,upf1              {}
    dependencies,init_design1      {netlist1 sdc1 def1 upf1}
    dependencies,place1            {init_design1}
    dependencies,cts1              {place1}
    dependencies,cts_opt1          {cts1}
    dependencies,route1            {cts_opt1}
    dependencies,pro1              {route1}
    dependencies,signoff1          {pro1}
    dependencies,export_data1      {signoff1}
    dependencies,release_data1     {export_data1}
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        SUBNODES & WORK DIRS                                 ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# All execution stages share the same subnode pattern
set _pnr_exec_stages {init_design1 place1 cts1 cts_opt1 route1 pro1 signoff1 export_data1 release_data1}
foreach _s $_pnr_exec_stages {
    set pnr(subnodes,$_s) {setup run validate finish}
    set pnr(subnode_dependencies,${_s},setup)    {}
    set pnr(subnode_dependencies,${_s},run)      {setup}
    set pnr(subnode_dependencies,${_s},validate) {run}
    set pnr(subnode_dependencies,${_s},finish)   {validate}
    foreach _sub {setup run validate finish} {
        set pnr(subnode_work_dirs,${_s},${_sub}) "work/${_s}/${_sub}"
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        NODE TYPES & STAGE TYPES                             ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set pnr {
    node_types,netlist1       "inputs"
    node_types,sdc1           "inputs"
    node_types,def1           "inputs"
    node_types,upf1           "inputs"
    node_types,init_design1   "init_design"
    node_types,place1         "place"
    node_types,cts1           "cts"
    node_types,cts_opt1       "cts_opt"
    node_types,route1         "route"
    node_types,pro1           "pro"
    node_types,signoff1       "signoff"
    node_types,export_data1   "export_data"
    node_types,release_data1  "release_data"

    stage_types,netlist1      "inputs"
    stage_types,sdc1          "inputs"
    stage_types,def1          "inputs"
    stage_types,upf1          "inputs"
    stage_types,init_design1  "execution"
    stage_types,place1        "execution"
    stage_types,cts1          "execution"
    stage_types,cts_opt1      "execution"
    stage_types,route1        "execution"
    stage_types,pro1          "execution"
    stage_types,signoff1      "execution"
    stage_types,export_data1  "export_data"
    stage_types,release_data1 "release_data"

    node_descriptions,netlist1       "Gate-level netlist input"
    node_descriptions,sdc1           "SDC timing constraints input"
    node_descriptions,def1           "DEF floorplan input"
    node_descriptions,upf1           "UPF power intent input"
    node_descriptions,init_design1   "Design library creation, floorplan loading, technology setup (4 subnodes: setup, run, validate, finish)"
    node_descriptions,place1         "Standard cell placement (4 subnodes: setup, run, validate, finish)"
    node_descriptions,cts1           "Clock tree synthesis (4 subnodes: setup, run, validate, finish)"
    node_descriptions,cts_opt1       "Clock tree optimization (4 subnodes: setup, run, validate, finish)"
    node_descriptions,route1         "Global and detailed routing (4 subnodes: setup, run, validate, finish)"
    node_descriptions,pro1           "Post-route optimization (4 subnodes: setup, run, validate, finish)"
    node_descriptions,signoff1       "Final design sign-off (4 subnodes: setup, run, validate, finish)"
    node_descriptions,export_data1   "Export PNR database (4 subnodes: setup, run, validate, finish)"
    node_descriptions,release_data1  "Release PNR deliverables (4 subnodes: setup, run, validate, finish)"
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        MMMC & RUNTIME                                       ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set pnr {
    mmmc,enabled_stages       {cts1 route1 pro1 signoff1}
    parallel_stages           {place1 cts1}

    mmmc_reports,base             {mmmc_timing mmmc_scenarios}
    mmmc_reports,base_files       {mmmc_setup}
    mmmc_reports,route1           {mmmc_power}
    mmmc_reports,pro1             {mmmc_power mmmc_crosstalk}
    mmmc_reports,signoff1         {mmmc_power mmmc_crosstalk mmmc_final_summary mmmc_noise mmmc_si}

    runtime,timeout,netlist1         10
    runtime,timeout,sdc1             10
    runtime,timeout,def1             10
    runtime,timeout,upf1             10
    runtime,timeout,init_design1     30
    runtime,timeout,place1           180
    runtime,timeout,cts1             60
    runtime,timeout,cts_opt1         45
    runtime,timeout,route1           240
    runtime,timeout,pro1             90
    runtime,timeout,signoff1         30
    runtime,timeout,export_data1     25
    runtime,timeout,release_data1    20
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        INPUTS & OUTPUTS                                     ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set pnr {
    subnode_input_types,netlist1,netlist "netlist_inputs"
    subnode_input_types,sdc1,sdc "sdc_inputs"
    subnode_input_types,def1,def "def_inputs"
    subnode_input_types,upf1,upf "upf_inputs"

    mandatory_input_groups {
        netlist_inputs {pnr(input,netlist)}
        sdc_inputs {pnr(input,sdc_release_tag) pnr(input,sdc_release_dir) pnr(input,sdc_func_file)}
        def_inputs {pnr(input,def_file)}
    }

    mandatory_user_inputs {
        pnr(input,netlist)
        pnr(input,sdc_func_file)
        pnr(input,def_file)
    }

    chip_type "flat"

    output,netlist_dir         "results/pnr"
    output,report_dir          "reports/pnr"
    output,work_dir            "work/PNR"
    output,gds_file            "results/pnr/final.gds"
    output,final_netlist       "results/pnr/final.v"
    output,final_def           "results/pnr/final.def"
    output,final_spef          "results/pnr/final.spef"
    output,write_gds           true
    output,write_oasis         false
    output,block_labeling      true
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        FILE REQUIREMENTS & RELEASE                          ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set pnr {
    critical_files,place1     {pnr(input,netlist) pnr(input,sdc_func_file) pnr(input,def_file)}
    critical_files,cts1       {pnr(input,netlist) pnr(input,sdc_func_file)}
    critical_files,route1     {pnr(input,netlist) pnr(input,def_file)}

    mandatory_outputs,place1    {results/place1/place.enc results/place1/place.rpt}
    mandatory_outputs,cts1      {results/cts1/cts.enc results/cts1/cts.rpt}
    mandatory_outputs,route1    {results/route1/route.enc results/route1/route.rpt}
    mandatory_outputs,signoff1  {results/gds/final.gds results/netlist/final.v results/def/final.def}

    optional_files,place1     {pnr(place,scripts)}

    release_types,signoff1,description "PNR signoff deliverables for tapeout"
    release_types,signoff1,files {
        "results/gds/final.gds" "gds/final_layout.gds"
        "results/netlist/final.v" "netlist/final_netlist.v"
        "results/def/final.def" "def/final_design.def"
        "results/spef/final.spef" "spef/final_parasitic.spef"
        "results/timing/final_timing.rpt" "reports/final_timing.rpt"
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        SUPPORTED TOOLS & TOOL CONFIG                        ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set pnr {
    supported_tools {fc innovus}
    default_tool    "fc"
}

# Source tool-specific configuration
# Tool is set via: user_config pnr(tool,name) or defaults to pnr(default_tool)
set _node_config_dir [file dirname [info script]]
set _tool_name [expr {[info exists pnr(tool,name)] ? $pnr(tool,name) : $pnr(default_tool)}]

set _tool_config "$_node_config_dir/PNR_${_tool_name}_config.tcl"
if {[file exists $_tool_config]} {
    source $_tool_config
} else {
    puts "ERROR: Tool config not found: $_tool_config"
    puts "       Supported tools: $pnr(supported_tools)"
    exit 1
}
