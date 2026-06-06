#!/usr/bin/env tclsh
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                          CBFlow LSF Management Configuration                  ║
# ║                    Intelligent Resource Allocation System                    ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# Description: Comprehensive LSF configuration with ML-based resource optimization
# Version: 1.0.0
# Author: CBFlow LSF Management System
# Date: 2025-10-08
#
# Features:
# - Intelligent LSF queue definitions (XS, S, M, L, XL, ultra)
# - ML analytics configuration for resource optimization
# - Dynamic queue creation policies
# - Cost optimization and performance tuning
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
array set lsf {
    # Default queue type when no flow_mapping exists for a stage
    default_queue_type "M"

    # ═══════════════════════════════════════════════════════════════════════════
    # CORE LSF QUEUE TYPES
    # ═══════════════════════════════════════════════════════════════════════════

    # Extra Small Queue - Interactive viewing, gvim, large text file browsing
    queue_types,XS,memory "4GB"
    queue_types,XS,cpu "2"
    queue_types,XS,runtime_limit "1:00"
    queue_types,XS,description "Extra small jobs - gvim sessions, large text file viewing, interactive log browsing"
    queue_types,XS,priority "60"
    queue_types,XS,cost_factor "0.5"
    queue_types,XS,typical_nodes "gvim text_view log_browse interactive_edit"
    queue_types,XS,max_concurrent "30"

    # Small Queue - Light workloads, fast turnaround
    queue_types,S,memory "8GB"
    queue_types,S,cpu "4"
    queue_types,S,runtime_limit "2:00"
    queue_types,S,description "Small jobs - synthesis inputs, validation, quick checks"
    queue_types,S,priority "50"
    queue_types,S,cost_factor "1.0"
    queue_types,S,typical_nodes "inputs validate setup finish"
    queue_types,S,max_concurrent "20"

    # Medium Queue - Standard workloads, balanced resources
    queue_types,M,memory "40GB"
    queue_types,M,cpu "8"
    queue_types,M,runtime_limit "8:00"
    queue_types,M,description "Medium jobs - synthesis, floorplan, basic PNR stages"
    queue_types,M,priority "40"
    queue_types,M,cost_factor "2.0"
    queue_types,M,typical_nodes "synthesis floorplan powerplan cts"
    queue_types,M,max_concurrent "15"

    # Large Queue - Heavy workloads, high memory requirements
    queue_types,L,memory "120GB"
    queue_types,L,cpu "8"
    queue_types,L,runtime_limit "48:00"
    queue_types,L,description "Large jobs - placement, routing, timing optimization"
    queue_types,L,priority "30"
    queue_types,L,cost_factor "4.0"
    queue_types,L,typical_nodes "placement route route_opt signoff"
    queue_types,L,max_concurrent "10"

    # Extra Large Queue - Very heavy workloads, complex designs
    queue_types,XL,memory "256GB"
    queue_types,XL,cpu "8"
    queue_types,XL,runtime_limit "96:00"
    queue_types,XL,description "Extra large jobs - full chip integration, complex hierarchical flows"
    queue_types,XL,priority "20"
    queue_types,XL,cost_factor "8.0"
    queue_types,XL,typical_nodes "hierarchical_integration full_chip_route eco_optimization"
    queue_types,XL,max_concurrent "5"

    # Ultra Queue - Massive workloads, extreme requirements
    queue_types,ultra,memory "512GB"
    queue_types,ultra,cpu "16"
    queue_types,ultra,runtime_limit "168:00"
    queue_types,ultra,description "Ultra large jobs - full chip signoff, massive designs"
    queue_types,ultra,priority "10"
    queue_types,ultra,cost_factor "16.0"
    queue_types,ultra,typical_nodes "full_chip_signoff massive_eco final_integration"
    queue_types,ultra,max_concurrent "2"

    # ═══════════════════════════════════════════════════════════════════════════
    # QUEUE MANAGEMENT POLICIES
    # ═══════════════════════════════════════════════════════════════════════════

    # Interactive session settings
    interactive,queue "M"
    interactive,memory "40GB"
    interactive,cpu "4"

    # Available queue types list
    available_queues "XS S M L XL ultra"
    default_queue "M"
    emergency_queue "ultra"

    # Queue selection strategies
    selection_strategy "ml_optimized"  ; # Options: static, load_balanced, ml_optimized, cost_optimized
    fallback_strategy "next_larger"    ; # Options: next_larger, best_available, fail

    # Resource scaling policies
    auto_scaling_enabled "true"
    scale_up_threshold "0.8"          ; # Scale up when utilization > 80%
    scale_down_threshold "0.3"        ; # Scale down when utilization < 30%
    scaling_cooldown "300"             ; # 5 minutes between scaling operations

    # ═══════════════════════════════════════════════════════════════════════════
    # FLOW-SPECIFIC QUEUE MAPPINGS
    # ═══════════════════════════════════════════════════════════════════════════

    # SYNTH (stages: rtl1 sdc1 upf1 init_design1 synthesis1 export_data1 release_data1)
    flow_mapping,SYNTH,rtl           "XS"
    flow_mapping,SYNTH,sdc           "XS"
    flow_mapping,SYNTH,upf           "XS"
    flow_mapping,SYNTH,init_design   "S"
    flow_mapping,SYNTH,synthesis     "M"
    flow_mapping,SYNTH,export_data   "S"
    flow_mapping,SYNTH,release_data  "XS"

    # SYNTH_PNR (stages: rtl1 sdc1 upf1 init_design1 synthesis1 place1 cts1 cts_opt1 route1 pro1 signoff1 export_data1 release_data1)
    flow_mapping,SYNTH_PNR,rtl           "XS"
    flow_mapping,SYNTH_PNR,sdc           "XS"
    flow_mapping,SYNTH_PNR,upf           "XS"
    flow_mapping,SYNTH_PNR,init_design   "S"
    flow_mapping,SYNTH_PNR,synthesis     "M"
    flow_mapping,SYNTH_PNR,place         "L"
    flow_mapping,SYNTH_PNR,cts           "L"
    flow_mapping,SYNTH_PNR,cts_opt       "L"
    flow_mapping,SYNTH_PNR,route         "XL"
    flow_mapping,SYNTH_PNR,pro           "L"
    flow_mapping,SYNTH_PNR,signoff       "M"
    flow_mapping,SYNTH_PNR,export_data   "S"
    flow_mapping,SYNTH_PNR,release_data  "XS"

    # PNR (stages: netlist1 sdc1 def1 upf1 init_design1 place1 cts1 cts_opt1 route1 pro1 signoff1 export_data1 release_data1)
    flow_mapping,PNR,netlist       "XS"
    flow_mapping,PNR,sdc           "XS"
    flow_mapping,PNR,def           "XS"
    flow_mapping,PNR,upf           "XS"
    flow_mapping,PNR,init_design   "S"
    flow_mapping,PNR,place         "L"
    flow_mapping,PNR,cts           "L"
    flow_mapping,PNR,cts_opt       "L"
    flow_mapping,PNR,route         "XL"
    flow_mapping,PNR,pro           "L"
    flow_mapping,PNR,signoff       "L"
    flow_mapping,PNR,export_data   "M"
    flow_mapping,PNR,release_data  "XS"

    # FP (stages: netlist1 sdc1 def1 upf1 library1 init_design1 import_design1 floorplan1 powerplan1 place_pins1 export_data1 release_data1)
    flow_mapping,FP,netlist          "XS"
    flow_mapping,FP,sdc              "XS"
    flow_mapping,FP,def              "XS"
    flow_mapping,FP,upf              "XS"
    flow_mapping,FP,library          "XS"
    flow_mapping,FP,init_design      "S"
    flow_mapping,FP,import_design    "M"
    flow_mapping,FP,floorplan        "M"
    flow_mapping,FP,powerplan        "L"
    flow_mapping,FP,place_pins       "M"
    flow_mapping,FP,export_data      "S"
    flow_mapping,FP,release_data     "XS"

    # FCFP (stages: netlist1 sdc1 def1 upf1 library1 init_design1 commit_blocks1 init_compile1 create_floorplan1 shaping1 placement1 create_power1 place_pins1 top_compile1 timing_budget1 export_data1 release_data1)
    flow_mapping,FCFP,netlist            "XS"
    flow_mapping,FCFP,sdc               "XS"
    flow_mapping,FCFP,def               "XS"
    flow_mapping,FCFP,upf               "XS"
    flow_mapping,FCFP,library           "XS"
    flow_mapping,FCFP,init_design       "S"
    flow_mapping,FCFP,commit_blocks     "M"
    flow_mapping,FCFP,init_compile      "M"
    flow_mapping,FCFP,create_floorplan  "L"
    flow_mapping,FCFP,shaping           "L"
    flow_mapping,FCFP,placement         "L"
    flow_mapping,FCFP,create_power      "L"
    flow_mapping,FCFP,place_pins        "M"
    flow_mapping,FCFP,top_compile       "L"
    flow_mapping,FCFP,timing_budget     "M"
    flow_mapping,FCFP,export_data       "S"
    flow_mapping,FCFP,release_data      "XS"

    # STA (stages: netlist1 sdc1 spef1 library1 extraction1 timing1 reporting1 release_data1)
    flow_mapping,STA,netlist       "XS"
    flow_mapping,STA,sdc           "XS"
    flow_mapping,STA,spef          "XS"
    flow_mapping,STA,library       "XS"
    flow_mapping,STA,extraction    "L"
    flow_mapping,STA,timing        "L"
    flow_mapping,STA,reporting     "M"
    flow_mapping,STA,release_data  "XS"

    # LEC (stages: netlist_golden1 netlist_revised1 constraints1 compare1 release_data1)
    flow_mapping,LEC,netlist_golden   "XS"
    flow_mapping,LEC,netlist_revised  "XS"
    flow_mapping,LEC,constraints      "XS"
    flow_mapping,LEC,compare          "M"
    flow_mapping,LEC,release_data     "XS"

    # CLP (stages: netlist1 upf1 power_spec1 clp1 release_data1)
    flow_mapping,CLP,netlist       "XS"
    flow_mapping,CLP,upf           "XS"
    flow_mapping,CLP,power_spec    "XS"
    flow_mapping,CLP,clp           "M"
    flow_mapping,CLP,release_data  "XS"

    # PV (stages: netlist1 def1 gds1 fill1 drc1 lvs1 perc1 erc1 xor1 merge_data1 release_data1)
    flow_mapping,PV,netlist       "XS"
    flow_mapping,PV,def           "XS"
    flow_mapping,PV,gds           "XS"
    flow_mapping,PV,fill          "L"
    flow_mapping,PV,drc           "L"
    flow_mapping,PV,lvs           "L"
    flow_mapping,PV,perc          "M"
    flow_mapping,PV,erc           "M"
    flow_mapping,PV,xor           "M"
    flow_mapping,PV,merge_data    "S"
    flow_mapping,PV,release_data  "XS"

    # EMIR (stages: netlist1 def1 spef1 library1 power_analysis1 ir_drop1 thermal_analysis1)
    flow_mapping,EMIR,netlist            "XS"
    flow_mapping,EMIR,def               "XS"
    flow_mapping,EMIR,spef              "XS"
    flow_mapping,EMIR,library           "XS"
    flow_mapping,EMIR,power_analysis    "L"
    flow_mapping,EMIR,ir_drop           "L"
    flow_mapping,EMIR,thermal_analysis  "XL"

    # ECO (stages: netlist1 def1 sdc1 library1 eco1 export_db1)
    flow_mapping,ECO,netlist     "XS"
    flow_mapping,ECO,def         "XS"
    flow_mapping,ECO,sdc         "XS"
    flow_mapping,ECO,library     "XS"
    flow_mapping,ECO,eco         "L"
    flow_mapping,ECO,export_db   "M"

    # POPT (stages: netlist1 sdc1 upf1 merge_timing1 power_opt1 post_merge1 release_data1)
    flow_mapping,POPT,netlist        "XS"
    flow_mapping,POPT,sdc            "XS"
    flow_mapping,POPT,upf            "XS"
    flow_mapping,POPT,merge_timing   "M"
    flow_mapping,POPT,power_opt      "L"
    flow_mapping,POPT,post_merge     "M"
    flow_mapping,POPT,release_data   "XS"

    # ═══════════════════════════════════════════════════════════════════════════
    # LSF COMMANDS
    # ═══════════════════════════════════════════════════════════════════════════

    lsf_cmd,submit   "bsub"
    lsf_cmd,query    "bjobs"
    lsf_cmd,kill     "bkill"
    lsf_cmd,queues   "bqueues"
    lsf_cmd,hosts    "bhosts"
}

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

# Tool shell commands
set lsf(tool_shell,fc)      "fc_shell"
set lsf(tool_shell,pt)      "pt_shell"
set lsf(tool_shell,fm)      "fm_shell"
set lsf(tool_shell,vc_lp)   "vc_lp_shell"
set lsf(tool_shell,icv)     "icv"
set lsf(tool_shell,redhawk) "redhawk"
set lsf(tool_shell,genus)   "genus"
set lsf(tool_shell,innovus) "innovus"
set lsf(tool_shell,tempus)  "tempus"

# Wrapper shell (for module load compatibility)
set lsf(tool_wrapper_shell) "/bin/csh -f"

# LSF bsub settings
set lsf(bsub,project)       "RD"
set lsf(bsub,queue)         "normal_rhel8"
set lsf(bsub,affinity)      "affinity\[core(1):cpubind=socket:membind=localonly\]"

# XTerm settings (xterm enable/disable controlled by flow(use_xterm) in flow_config)
set lsf(xterm,command)       "xterm"
set lsf(xterm,geometry)      "200x50"
