#!/usr/bin/env tclsh
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║    RTL_SPEC Flow Configuration — block spec to design collateral            ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# The front of spec-to-GDS. One block spec (YAML, CBflow spec schema v1) with
# its register description (SystemRDL, or an XLS register sheet) is checked
# and turned into the collateral every later flow consumes:
#   IP-XACT component (IEEE 1685-2014: ports, bus interfaces, memory map,
#   file sets), the register block RTL + UVM register model + C header + HTML
#   (PeakRDL), SDC and UPF, the RTL filelist (generated register block + the
#   designer's RTL), and the verification plan (XLS, from the spec's features).
# The RTL top is checked against the spec's ports.
#
# Released as SPEC_EXIT: rtl/ (sources + <d>.f), spec/, sdc/, upf/, data/ —
# RTL_LINT / SYNTH / DV read it by tag.
#
# Supported tools:
#   · rtlcheck (vendor opensource — spec_tool.py, PeakRDL, sv2v, yosys, lxml)

array set rtl_spec {
    stages {spec1 spec_check1 gen_regs1 gen_ipxact1 gen_collateral1 release_data1}

    dependencies,spec1           {}
    dependencies,spec_check1     {spec1}
    dependencies,gen_regs1       {spec_check1}
    dependencies,gen_ipxact1     {gen_regs1}
    dependencies,gen_collateral1 {gen_ipxact1}
    dependencies,release_data1   {gen_collateral1}
}

set _spec_exec_stages {spec_check1 gen_regs1 gen_ipxact1 gen_collateral1 release_data1}
foreach _s $_spec_exec_stages {
    set rtl_spec(subnodes,$_s) {setup run validate finish}
    set rtl_spec(subnode_dependencies,${_s},setup)    {}
    set rtl_spec(subnode_dependencies,${_s},run)      {setup}
    set rtl_spec(subnode_dependencies,${_s},validate) {run}
    set rtl_spec(subnode_dependencies,${_s},finish)   {validate}
    foreach _sub {setup run validate finish} {
        set rtl_spec(subnode_work_dirs,${_s},${_sub}) "work/${_s}/${_sub}"
    }
}

array set rtl_spec {
    stage_types,spec1            "inputs"
    stage_types,spec_check1      "execution"
    stage_types,gen_regs1        "execution"
    stage_types,gen_ipxact1      "execution"
    stage_types,gen_collateral1  "execution"
    stage_types,release_data1    "release_data"

    node_types,spec1             "inputs"
    node_types,spec_check1       "spec_check"
    node_types,gen_regs1         "gen_regs"
    node_types,gen_ipxact1       "gen_ipxact"
    node_types,gen_collateral1   "gen_collateral"
    node_types,release_data1     "release_data"

    node_descriptions,spec1           "Block spec (YAML)"
    node_descriptions,spec_check1     "Spec schema + consistency check; register source -> SystemRDL"
    node_descriptions,gen_regs1       "Register block RTL, UVM RAL, C header, IP-XACT memory map, HTML (PeakRDL)"
    node_descriptions,gen_ipxact1     "IP-XACT 1685-2014 component (schema-validated)"
    node_descriptions,gen_collateral1 "SDC, UPF, RTL filelist, vPlan; RTL ports vs spec"
    node_descriptions,release_data1   "Release the spec collateral (SPEC_EXIT)"

    mmmc,enabled            false

    runtime,timeout,spec1            10
    runtime,timeout,spec_check1      10
    runtime,timeout,gen_regs1        20
    runtime,timeout,gen_ipxact1      10
    runtime,timeout,gen_collateral1  20
    runtime,timeout,release_data1    10

    mandatory_input_groups {
        spec_inputs {rtl_spec(input,spec)}
    }
    mandatory_user_inputs {
        rtl_spec(input,spec)
    }

    output,report_dir   "reports/rtl_spec"
    output,results_dir  "results/rtl_spec"
    output,work_dir     "work/RTL_SPEC"

    supported_tools {rtlcheck}
    default_tool    "rtlcheck"
}

set _node_config_dir [file dirname [info script]]
set _tool_name [expr {[info exists rtl_spec(tool,name)] ? $rtl_spec(tool,name) : $rtl_spec(default_tool)}]
set _tool_config "$_node_config_dir/RTL_SPEC_${_tool_name}_config.tcl"
if {[file exists $_tool_config]} { source $_tool_config } else {
    puts "ERROR: Tool config not found: $_tool_config"
    puts "       Supported tools: $rtl_spec(supported_tools)"
    exit 1
}

set rtl_spec(merge_handoff_stage)   release_data1
set rtl_spec(merge_parallel_stages) {release_data1}
