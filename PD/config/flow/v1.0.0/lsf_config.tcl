#!/usr/bin/env tclsh
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                          CBFlow LSF Management Configuration                  ║
# ║                    Intelligent Resource Allocation System                    ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# Description: LSF queue + per-stage resource configuration
# Version: 1.0.0
# Author: CBFlow LSF Management System
# Date: 2025-10-08
#
# Features:
# - LSF queue definitions (XS, S, M, L, XL, ultra)
# - Dynamic queue creation policies
# - Node-specific resource allocation strategies

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                           NAMESPACE DEFINITION                              │
# └─────────────────────────────────────────────────────────────────────────────┘

namespace eval ::CBFlow::LSF {
    variable version "1.0.0"
    variable config_date "2025-10-08"
    variable debug_mode false
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                        LSF QUEUE DEFINITIONS                               │
# └─────────────────────────────────────────────────────────────────────────────┘

# Main LSF queue configuration array
# Per-key sets — `#` comments work natively here. (Inside an
# `array set` literal, Tcl treats `#` as data and silently
# corrupts every key after the comment line; that bug used to
# lose lsf(queue_types,L,*).)
    # Default queue type when no flow_mapping exists for a stage
    set lsf(default_queue_type) "M"

    # ═══════════════════════════════════════════════════════════════════════════
    # CORE LSF QUEUE TYPES
    # ═══════════════════════════════════════════════════════════════════════════

    # Extra Small Queue - Interactive viewing, gvim, large text file browsing
    set lsf(queue_types,XS,memory) "4GB"
    set lsf(queue_types,XS,cpu) "2"
    set lsf(queue_types,XS,runtime_limit) "1:00"
    set lsf(queue_types,XS,description) "Extra small jobs - gvim sessions, large text file viewing, interactive log browsing"
    set lsf(queue_types,XS,priority) "60"
    set lsf(queue_types,XS,cost_factor) "0.5"
    set lsf(queue_types,XS,typical_nodes) "gvim text_view log_browse interactive_edit"
    set lsf(queue_types,XS,max_concurrent) "30"

    # Small Queue - Light workloads, fast turnaround
    set lsf(queue_types,S,memory) "16GB"
    set lsf(queue_types,S,cpu) "4"
    set lsf(queue_types,S,runtime_limit) "8:00"
    set lsf(queue_types,S,description) "Small jobs - synthesis inputs, validation, quick checks"
    set lsf(queue_types,S,priority) "50"
    set lsf(queue_types,S,cost_factor) "1.0"
    set lsf(queue_types,S,typical_nodes) "inputs validate setup finish"
    set lsf(queue_types,S,max_concurrent) "20"

    # Medium Queue - Standard workloads, balanced resources
    set lsf(queue_types,M,memory) "64GB"
    set lsf(queue_types,M,cpu) "8"
    set lsf(queue_types,M,runtime_limit) "24:00"
    set lsf(queue_types,M,description) "Medium jobs - synthesis, floorplan, basic PNR stages"
    set lsf(queue_types,M,priority) "40"
    set lsf(queue_types,M,cost_factor) "2.0"
    set lsf(queue_types,M,typical_nodes) "synthesis floorplan powerplan cts"
    set lsf(queue_types,M,max_concurrent) "15"

    # Large Queue - Heavy workloads, high memory requirements
    set lsf(queue_types,L,memory) "128GB"
    set lsf(queue_types,L,cpu) "8"
    set lsf(queue_types,L,runtime_limit) "48:00"
    set lsf(queue_types,L,description) "Large jobs - placement, routing, timing optimization"
    set lsf(queue_types,L,priority) "30"
    set lsf(queue_types,L,cost_factor) "4.0"
    set lsf(queue_types,L,typical_nodes) "placement route route_opt signoff"
    set lsf(queue_types,L,max_concurrent) "10"

    # Extra Large Queue - Very heavy workloads, complex designs
    set lsf(queue_types,XL,memory) "256GB"
    set lsf(queue_types,XL,cpu) "8"
    set lsf(queue_types,XL,runtime_limit) "96:00"
    set lsf(queue_types,XL,description) "Extra large jobs - full chip integration, complex hierarchical flows"
    set lsf(queue_types,XL,priority) "20"
    set lsf(queue_types,XL,cost_factor) "8.0"
    set lsf(queue_types,XL,typical_nodes) "hierarchical_integration full_chip_route eco_optimization"
    set lsf(queue_types,XL,max_concurrent) "5"

    # Ultra Queue - Massive workloads, extreme requirements
    set lsf(queue_types,ultra,memory) "512GB"
    set lsf(queue_types,ultra,cpu) "16"
    set lsf(queue_types,ultra,runtime_limit) "168:00"
    set lsf(queue_types,ultra,description) "Ultra large jobs - full chip signoff, massive designs"
    set lsf(queue_types,ultra,priority) "10"
    set lsf(queue_types,ultra,cost_factor) "16.0"
    set lsf(queue_types,ultra,typical_nodes) "full_chip_signoff massive_eco final_integration"
    set lsf(queue_types,ultra,max_concurrent) "2"

    # ═══════════════════════════════════════════════════════════════════════════
    # QUEUE MANAGEMENT POLICIES
    # ═══════════════════════════════════════════════════════════════════════════

    # Interactive session settings
    set lsf(interactive,queue) "M"
    set lsf(interactive,memory) "40GB"
    set lsf(interactive,cpu) "4"
    set lsf(interactive,runtime_limit) "6:00"

    # Available queue types list
    set lsf(available_queues) "XS S M L XL ultra"
    set lsf(default_queue) "M"
    set lsf(emergency_queue) "ultra"

    # Queue selection strategies
    # selection_strategy options: static, load_balanced
    set lsf(selection_strategy) "load_balanced"
    # fallback_strategy options: next_larger, best_available, fail
    set lsf(fallback_strategy) "next_larger"

    # Resource scaling policies — `;#` trailing comments are NOT supported
    # inside an `array set` literal (Tcl treats them as data, corrupting every
    # key after the offending line). Use leading `#` comments only.
    set lsf(auto_scaling_enabled) "true"
    # scale up when utilization > 80%
    set lsf(scale_up_threshold) "0.8"
    # scale down when utilization < 30%
    set lsf(scale_down_threshold) "0.3"
    # 5 minutes between scaling operations
    set lsf(scaling_cooldown) "300"

    # ═══════════════════════════════════════════════════════════════════════════
    # FLOW-SPECIFIC QUEUE MAPPINGS
    # ═══════════════════════════════════════════════════════════════════════════

    # SYNTH (stages: rtl1 sdc1 upf1 init_design1 synthesis1 export_data1 release_data1)
    set lsf(flow_mapping,SYNTH,rtl) "XS"
    set lsf(flow_mapping,SYNTH,sdc) "XS"
    set lsf(flow_mapping,SYNTH,upf) "XS"
    set lsf(flow_mapping,SYNTH,init_design) "S"
    set lsf(flow_mapping,SYNTH,synthesis) "M"
    set lsf(flow_mapping,SYNTH,export_data) "S"
    set lsf(flow_mapping,SYNTH,release_data) "XS"

    # SYNTH_PNR (stages: rtl1 sdc1 upf1 init_design1 synthesis1 place1 cts1 cts_opt1 route1 pro1 signoff1 export_data1 release_data1)
    set lsf(flow_mapping,SYNTH_PNR,rtl) "XS"
    set lsf(flow_mapping,SYNTH_PNR,sdc) "XS"
    set lsf(flow_mapping,SYNTH_PNR,upf) "XS"
    set lsf(flow_mapping,SYNTH_PNR,init_design) "S"
    set lsf(flow_mapping,SYNTH_PNR,synthesis) "M"
    set lsf(flow_mapping,SYNTH_PNR,place) "L"
    set lsf(flow_mapping,SYNTH_PNR,cts) "L"
    set lsf(flow_mapping,SYNTH_PNR,cts_opt) "L"
    set lsf(flow_mapping,SYNTH_PNR,route) "XL"
    set lsf(flow_mapping,SYNTH_PNR,pro) "L"
    set lsf(flow_mapping,SYNTH_PNR,signoff) "M"
    set lsf(flow_mapping,SYNTH_PNR,export_data) "S"
    set lsf(flow_mapping,SYNTH_PNR,release_data) "XS"

    # PNR (stages: netlist1 sdc1 def1 upf1 init_design1 place1 cts1 cts_opt1 route1 pro1 signoff1 export_data1 release_data1)
    set lsf(flow_mapping,PNR,netlist) "XS"
    set lsf(flow_mapping,PNR,sdc) "XS"
    set lsf(flow_mapping,PNR,def) "XS"
    set lsf(flow_mapping,PNR,upf) "XS"
    set lsf(flow_mapping,PNR,init_design) "S"
    set lsf(flow_mapping,PNR,place) "L"
    set lsf(flow_mapping,PNR,cts) "L"
    set lsf(flow_mapping,PNR,cts_opt) "L"
    set lsf(flow_mapping,PNR,route) "XL"
    set lsf(flow_mapping,PNR,pro) "L"
    set lsf(flow_mapping,PNR,signoff) "L"
    set lsf(flow_mapping,PNR,export_data) "M"
    set lsf(flow_mapping,PNR,release_data) "XS"

    # FP (stages: netlist1 sdc1 def1 upf1 library1 init_design1 floorplan1 powerplan1 export_data1 release_data1)
    # FP execution nodes: 8 hours (S queue)
    set lsf(flow_mapping,FP,netlist) "XS"
    set lsf(flow_mapping,FP,sdc) "XS"
    set lsf(flow_mapping,FP,def) "XS"
    set lsf(flow_mapping,FP,upf) "XS"
    set lsf(flow_mapping,FP,library) "XS"
    set lsf(flow_mapping,FP,init_design) "S"
    set lsf(flow_mapping,FP,floorplan) "S"
    set lsf(flow_mapping,FP,powerplan) "S"
    set lsf(flow_mapping,FP,export_data) "S"
    set lsf(flow_mapping,FP,release_data) "XS"

    # FCFP (stages: netlist1 sdc1 def1 upf1 library1 init_design1 commit_blocks1 init_compile1 create_floorplan1 shaping1 placement1 create_power1 place_pins1 top_compile1 timing_budget1 export_data1 release_data1)
    set lsf(flow_mapping,FCFP,netlist) "XS"
    set lsf(flow_mapping,FCFP,sdc) "XS"
    set lsf(flow_mapping,FCFP,def) "XS"
    set lsf(flow_mapping,FCFP,upf) "XS"
    set lsf(flow_mapping,FCFP,library) "XS"
    set lsf(flow_mapping,FCFP,init_design) "S"
    set lsf(flow_mapping,FCFP,commit_blocks) "M"
    set lsf(flow_mapping,FCFP,init_compile) "M"
    set lsf(flow_mapping,FCFP,create_floorplan) "L"
    set lsf(flow_mapping,FCFP,shaping) "L"
    set lsf(flow_mapping,FCFP,placement) "L"
    set lsf(flow_mapping,FCFP,create_power) "L"
    set lsf(flow_mapping,FCFP,place_pins) "M"
    set lsf(flow_mapping,FCFP,top_compile) "L"
    set lsf(flow_mapping,FCFP,timing_budget) "M"
    set lsf(flow_mapping,FCFP,export_data) "S"
    set lsf(flow_mapping,FCFP,release_data) "XS"

    # STA (stages: netlist1 sdc1 spef1 library1 extraction1 timing1 merge_reports1 release_data1)
    set lsf(flow_mapping,STA,netlist) "XS"
    set lsf(flow_mapping,STA,sdc) "XS"
    set lsf(flow_mapping,STA,spef) "XS"
    set lsf(flow_mapping,STA,library) "XS"
    set lsf(flow_mapping,STA,extraction) "L"
    set lsf(flow_mapping,STA,timing) "L"
    set lsf(flow_mapping,STA,reporting) "M"
    set lsf(flow_mapping,STA,release_data) "XS"

    # LEC (stages: netlist_golden1 netlist_revised1 constraints1 compare1 release_data1)
    set lsf(flow_mapping,LEC,netlist_golden) "XS"
    set lsf(flow_mapping,LEC,netlist_revised) "XS"
    set lsf(flow_mapping,LEC,constraints) "XS"
    set lsf(flow_mapping,LEC,compare) "M"
    set lsf(flow_mapping,LEC,release_data) "XS"

    # CLP (stages: netlist1 upf1 power_spec1 clp1 release_data1)
    set lsf(flow_mapping,CLP,netlist) "XS"
    set lsf(flow_mapping,CLP,upf) "XS"
    set lsf(flow_mapping,CLP,power_spec) "XS"
    set lsf(flow_mapping,CLP,clp) "M"
    set lsf(flow_mapping,CLP,release_data) "XS"

    # PV (stages: netlist1 def1 gds1 fill1 drc1 lvs1 perc1 erc1 xor1 merge_data1 release_data1)
    set lsf(flow_mapping,PV,netlist) "XS"
    set lsf(flow_mapping,PV,def) "XS"
    set lsf(flow_mapping,PV,gds) "XS"
    set lsf(flow_mapping,PV,fill) "L"
    set lsf(flow_mapping,PV,drc) "L"
    set lsf(flow_mapping,PV,lvs) "L"
    set lsf(flow_mapping,PV,perc) "M"
    set lsf(flow_mapping,PV,erc) "M"
    set lsf(flow_mapping,PV,xor) "M"
    set lsf(flow_mapping,PV,merge_data) "S"
    set lsf(flow_mapping,PV,release_data) "XS"

    # EMIR (stages: netlist1 def1 spef1 library1 power_analysis1 ir_drop1 thermal_analysis1)
    set lsf(flow_mapping,EMIR,netlist) "XS"
    set lsf(flow_mapping,EMIR,def) "XS"
    set lsf(flow_mapping,EMIR,spef) "XS"
    set lsf(flow_mapping,EMIR,library) "XS"
    set lsf(flow_mapping,EMIR,power_analysis) "L"
    set lsf(flow_mapping,EMIR,ir_drop) "L"
    set lsf(flow_mapping,EMIR,thermal_analysis) "XL"

    # ECO (stages: netlist1 def1 sdc1 library1 eco1 export_db1)
    set lsf(flow_mapping,ECO,netlist) "XS"
    set lsf(flow_mapping,ECO,def) "XS"
    set lsf(flow_mapping,ECO,sdc) "XS"
    set lsf(flow_mapping,ECO,library) "XS"
    set lsf(flow_mapping,ECO,eco) "L"
    set lsf(flow_mapping,ECO,export_db) "M"

    # POPT (stages: netlist1 sdc1 upf1 merge_timing1 power_opt1 post_merge1 release_data1)
    set lsf(flow_mapping,POPT,netlist) "XS"
    set lsf(flow_mapping,POPT,sdc) "XS"
    set lsf(flow_mapping,POPT,upf) "XS"
    set lsf(flow_mapping,POPT,merge_timing) "M"
    set lsf(flow_mapping,POPT,power_opt) "L"
    set lsf(flow_mapping,POPT,post_merge) "M"
    set lsf(flow_mapping,POPT,release_data) "XS"

    # ═══════════════════════════════════════════════════════════════════════════
    # LSF COMMANDS
    # ═══════════════════════════════════════════════════════════════════════════

    set lsf(lsf_cmd,submit) "bsub"
    set lsf(lsf_cmd,query) "bjobs"
    set lsf(lsf_cmd,kill) "bkill"
    set lsf(lsf_cmd,queues) "bqueues"
    set lsf(lsf_cmd,hosts) "bhosts"

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                     LSF UTILITY PROCEDURES                                 │
# └─────────────────────────────────────────────────────────────────────────────┘

proc get_lsf_queue_info {queue_type} {
    global lsf
    if {![info exists lsf(queue_types,$queue_type,memory)]} { return {} }
    return [list \
        memory $lsf(queue_types,$queue_type,memory) \
        cpu $lsf(queue_types,$queue_type,cpu) \
        runtime_limit $lsf(queue_types,$queue_type,runtime_limit) \
    ]
}

proc get_lsf_recommended_queue {flow_type stage_name} {
    global lsf
    set key "flow_mapping,${flow_type},${stage_name}"
    if {[info exists lsf($key)]} { return $lsf($key) }
    return $lsf(default_queue)
}

# ═══════════════════════════════════════════════════════════════════════════════
# TOOL LAUNCH CONFIGURATION
# (Outside array set — values with spaces need individual set statements)
# ═══════════════════════════════════════════════════════════════════════════════

# Module load commands per tool
set lsf(module,fc)          "module load synopsysFusionCompiler/2025.06-SP2"
set lsf(module,pt)          "module load synopsysPrimeTime/2025.06"
set lsf(module,fm)          "module load synopsysFormality/2025.06"
set lsf(module,vc_lp)       "module load synopsysVCLP/2025.06"
set lsf(module,icv)         "module load synopsysICV/2025.06"
set lsf(module,redhawk)     "module load synopsysRedHawk/2025.06"
set lsf(module,genus)       "module load cadenceGenus/23.1"
set lsf(module,innovus)     "module load cadenceInnovus/23.1"
set lsf(module,tempus)      "module load cadenceTempus/23.1"

# tool_shell,* and tool_wrapper_shell live in tool_launch_config.tcl —
# not duplicated here. Sourcing this file after tool_launch_config used to
# silently override the 9 overlapping entries, masking the DFT/Mentor tools
# that only existed in tool_launch_config. Single source of truth wins.

# LSF bsub settings
# `bsub,command` is the binary `submit_job` execs — overridable per site so
# wrappers (e.g. `bsub_wrap`, `lsfsub`, `qsub`) can replace it without
# touching the engine. launch_utils.tcl errors loudly if this is unset.
set lsf(bsub,command)       "bsub"
set lsf(bsub,project)       "RD"
set lsf(bsub,queue)         "normal_rhel8"
set lsf(bsub,affinity)      "affinity\[core(1):cpubind=socket:membind=localonly\]"

# XTerm settings (xterm enable/disable controlled by flow(use_xterm) in flow_config)
set lsf(xterm,command)       "xterm"
set lsf(xterm,geometry)      "200x50"
