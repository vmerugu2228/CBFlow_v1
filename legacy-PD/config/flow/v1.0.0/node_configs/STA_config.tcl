#!/usr/bin/env tclsh
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║              STA Flow Configuration (Tool-Independent)                      ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# Common stages, dependencies, subnodes — same for all tools (PT, Tempus).
# Tool-specific settings sourced from STA_<tool>_config.tcl

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        STAGES & DEPENDENCIES                                ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# array set sta { … } expanded to per-key `set` statements so `#` comments work natively (Tcl treats `#` as data inside `array set` literals).
    set sta(stages) {netlist1 sdc1 def1 library1 extraction1 timing1 merge_reports1 release_data1}

    set sta(dependencies,netlist1) {}
    set sta(dependencies,sdc1) {}
    set sta(dependencies,def1) {}
    set sta(dependencies,library1) {}
    set sta(dependencies,extraction1) {netlist1 sdc1 def1 library1}
    set sta(dependencies,timing1) {extraction1}
    set sta(dependencies,merge_reports1) {timing1}
    set sta(dependencies,release_data1) {merge_reports1}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        SUBNODES & WORK DIRS                                 ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# Dynamic subnodes for extraction and timing (per-scenario parallelism)
# array set sta { … } expanded to per-key `set` statements so `#` comments work natively (Tcl treats `#` as data inside `array set` literals).
    set sta(subnodes,extraction1) {dynamic}
    set sta(subnodes,timing1) {dynamic}

    set sta(subnode_dependencies,extraction1,dynamic) {}
    set sta(subnode_dependencies,timing1,dynamic) {}

# Execution stages with standard 4-subnode pattern
set _sta_exec_stages {merge_reports1 release_data1}
foreach _s $_sta_exec_stages {
    set sta(subnodes,$_s) {setup run validate finish}
    set sta(subnode_dependencies,${_s},setup)    {}
    set sta(subnode_dependencies,${_s},run)      {setup}
    set sta(subnode_dependencies,${_s},validate) {run}
    set sta(subnode_dependencies,${_s},finish)   {validate}
    foreach _sub {setup run validate finish} {
        set sta(subnode_work_dirs,${_s},${_sub}) "work/${_s}/${_sub}"
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        NODE TYPES & STAGE TYPES                             ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# array set sta { … } expanded to per-key `set` statements so `#` comments work natively (Tcl treats `#` as data inside `array set` literals).
    set sta(stage_types,netlist1) "inputs"
    set sta(stage_types,sdc1) "inputs"
    set sta(stage_types,def1) "inputs"
    set sta(stage_types,library1) "inputs"
    set sta(stage_types,extraction1) "execution"
    set sta(stage_types,timing1) "execution"
    set sta(stage_types,merge_reports1) "execution"
    set sta(stage_types,release_data1) "release_data"

    set sta(node_types,netlist1) "inputs"
    set sta(node_types,sdc1) "inputs"
    set sta(node_types,def1) "inputs"
    set sta(node_types,library1) "inputs"
    set sta(node_types,extraction1) "extraction"
    set sta(node_types,timing1) "timing"
    set sta(node_types,merge_reports1) "merge_reports"
    set sta(node_types,release_data1) "release_data"

    set sta(node_descriptions,netlist1) "Gate-level netlist input"
    set sta(node_descriptions,sdc1) "SDC timing constraints input"
    set sta(node_descriptions,def1) "DEF physical design input (for extraction)"
    set sta(node_descriptions,library1) "Technology library input"
    set sta(node_descriptions,extraction1) "Per-RC-corner parasitic extraction (dynamic: rc_max, rc_typ, rc_min run in parallel)"
    set sta(node_descriptions,timing1) "Dynamic per-scenario timing analysis - each scenario runs setup+hold (parallelizable via make -j)"
    set sta(node_descriptions,merge_reports1) "Cross-corner aggregation - worst-case analysis, MMMC timing summary (4 subnodes)"
    set sta(node_descriptions,release_data1) "Package and release final timing sign-off deliverables (4 subnodes)"

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        MMMC & RUNTIME                                       ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# array set sta { … } expanded to per-key `set` statements so `#` comments work natively (Tcl treats `#` as data inside `array set` literals).
    set sta(mmmc,enabled) true
    set sta(mmmc,enabled_stages) {extraction1 timing1 merge_reports1}
    set sta(mmmc,default_scenario_set) "signoff"
    set sta(mmmc,scenario_set) "signoff"
    set sta(mmmc,dynamic_scenarios) true
    set sta(mmmc,parallel_scenarios) true

    set sta(runtime,timeout,netlist1) 10
    set sta(runtime,timeout,sdc1) 10
    set sta(runtime,timeout,def1) 10
    set sta(runtime,timeout,library1) 10
    set sta(runtime,timeout,extraction1) 30
    set sta(runtime,timeout,timing1) 60
    set sta(runtime,timeout,merge_reports1) 20
    set sta(runtime,timeout,release_data1) 10

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        INPUTS & OUTPUTS                                     ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# array set sta { … } expanded to per-key `set` statements so `#` comments work natively (Tcl treats `#` as data inside `array set` literals).
    set sta(critical_files,extraction1) {sta(input,netlist)}
    set sta(critical_files,timing1) {sta(input,netlist) sta(input,def_file)}
    set sta(critical_files,merge_reports1) {}
    set sta(critical_files,release_data1) {}

    set sta(mandatory_outputs,extraction1) {results/extraction/parasitic.spef}
    set sta(mandatory_outputs,timing1) {}
    set sta(mandatory_outputs,merge_reports1) {reports/sta/mmmc_timing_summary.rpt}

    set sta(mandatory_input_groups) {
        set sta(netlist_inputs) {sta(input,netlist)}
        set sta(def_inputs) {sta(input,def_file)}
    }

    set sta(mandatory_user_inputs) {
        sta(input,netlist)
        sta(input,sdc,func)
    }

    # SDC per mode — resolved from operating_modes constraint_file
    # User provides per-mode SDC files:
    #   sta(input,sdc,func) "/path/to/${design_name}_func.sdc"
    #   sta(input,sdc,test) "/path/to/${design_name}_test.sdc"
    # Or single file that covers all modes:
    #   sta(input,sdc_func_file) "/path/to/func.sdc"

    set sta(mmmc_reports,base) {mmmc_timing mmmc_scenarios}
    set sta(mmmc_reports,timing1) {mmmc_hold_timing mmmc_hold_violations}
    set sta(mmmc_reports,merge_reports1) {mmmc_final_summary mmmc_cross_corner}

    set sta(merge_parallel_stages) {release_data1}

    set sta(output,report_dir) "reports/sta"
    set sta(output,results_dir) "results/sta"
    set sta(output,work_dir) "work/STA"

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        RELEASE CONFIGURATION                                ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# array set sta { … } expanded to per-key `set` statements so `#` comments work natively (Tcl treats `#` as data inside `array set` literals).
    set sta(release_types,timing,description) "MMMC timing analysis reports, SPEF, and SDF"
    set sta(release_types,timing,files) {
        "reports/sta/mmmc_timing_summary.rpt"       "reports/final_mmmc_timing.rpt"
        "reports/sta/mmmc_hold_summary.rpt"         "reports/hold_timing_summary.rpt"
        "results/extraction/parasitic.spef"         "spef/final_parasitic.spef"
        "outputs/${design_name}.sdf"                "sdf/${design_name}.sdf"
    }

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        COMMON ANALYSIS CONTROL                              ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# array set sta { … } expanded to per-key `set` statements so `#` comments work natively (Tcl treats `#` as data inside `array set` literals).
    set sta(reporting,top_violations) 50
    set sta(reporting,include_input_pins) true
    set sta(reporting,include_nets) true
    set sta(reporting,report_format) "rpt"

    set sta(sdf,enabled) false
    set sta(sdf,timing_type) "max_min"

# NOTE: When sta(sdf,enabled) is set to true in user_config:
#   - SDF files generated during timing stage per scenario
#   - SDF files included in release deliverables
#   - Output: outputs/${design_name}_<scenario>.sdf

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        SUPPORTED TOOLS & TOOL CONFIG                        ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# array set sta { … } expanded to per-key `set` statements so `#` comments work natively (Tcl treats `#` as data inside `array set` literals).
    set sta(supported_tools) {pt tempus}
    set sta(default_tool) "pt"

# Source tool-specific configuration
# Tool is set via: user_config sta(tool,name) or defaults to sta(default_tool)
set _node_config_dir [file dirname [info script]]
set _tool_name [expr {[info exists sta(tool,name)] ? $sta(tool,name) : $sta(default_tool)}]

set _tool_config "$_node_config_dir/STA_${_tool_name}_config.tcl"
if {[file exists $_tool_config]} {
    source $_tool_config
} else {
    puts "ERROR: Tool config not found: $_tool_config"
    puts "       Supported tools: $sta(supported_tools)"
    exit 1
}
