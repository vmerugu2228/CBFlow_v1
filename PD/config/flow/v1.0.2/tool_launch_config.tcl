#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow Tool Launch Configuration
# Module load commands, tool shells, LSF bsub settings, XTerm settings
# Sourced by subnode handlers for tool execution
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

# Wrapper shell
set lsf(tool_wrapper_shell) "/bin/csh -f"

# LSF bsub defaults
set lsf(bsub,command)       "bsub"
set lsf(bsub,project)       "RD"
set lsf(bsub,queue)         "normal_rhel8"
set lsf(bsub,affinity)      "affinity\[core(1):cpubind=socket:membind=localonly\]"

# XTerm settings
set lsf(xterm,enabled)      "true"
set lsf(xterm,command)      "xterm"
set lsf(xterm,geometry)     "200x50"

# ── LSF Queue Type Resources ─────────────────────────────────────────────────
# Queue types define resource tiers; flow_mapping maps stages to queue types.
# (Duplicated from lsf_config.tcl which uses array set and cannot be sourced by handlers)
set lsf(queue_types,S,memory)         "8GB"
set lsf(queue_types,S,cpu)            "4"
set lsf(queue_types,S,runtime_limit)  "2:00"
set lsf(queue_types,M,memory)         "16GB"
set lsf(queue_types,M,cpu)            "8"
set lsf(queue_types,M,runtime_limit)  "4:00"
set lsf(queue_types,L,memory)         "32GB"
set lsf(queue_types,L,cpu)            "16"
set lsf(queue_types,L,runtime_limit)  "8:00"
set lsf(queue_types,XL,memory)        "64GB"
set lsf(queue_types,XL,cpu)           "32"
set lsf(queue_types,XL,runtime_limit) "12:00"
set lsf(queue_types,ultra,memory)         "128GB"
set lsf(queue_types,ultra,cpu)            "64"
set lsf(queue_types,ultra,runtime_limit)  "24:00"

# ── Flow-to-Queue Type Mappings ──────────────────────────────────────────────
# SYNTH_PNR
set lsf(flow_mapping,SYNTH_PNR,init_design)  "S"
set lsf(flow_mapping,SYNTH_PNR,synthesis)     "M"
set lsf(flow_mapping,SYNTH_PNR,place)         "L"
set lsf(flow_mapping,SYNTH_PNR,cts)           "L"
set lsf(flow_mapping,SYNTH_PNR,cts_opt)       "L"
set lsf(flow_mapping,SYNTH_PNR,route)         "XL"
set lsf(flow_mapping,SYNTH_PNR,pro)           "L"
set lsf(flow_mapping,SYNTH_PNR,signoff)       "M"
set lsf(flow_mapping,SYNTH_PNR,export_data)   "S"
set lsf(flow_mapping,SYNTH_PNR,release_data)  "S"
# PNR
set lsf(flow_mapping,PNR,place)         "L"
set lsf(flow_mapping,PNR,cts)           "L"
set lsf(flow_mapping,PNR,cts_opt)       "L"
set lsf(flow_mapping,PNR,route)         "XL"
set lsf(flow_mapping,PNR,pro)           "L"
set lsf(flow_mapping,PNR,signoff)       "L"
set lsf(flow_mapping,PNR,export_data)   "M"
set lsf(flow_mapping,PNR,release_data)  "S"
# STA
set lsf(flow_mapping,STA,extraction)    "L"
set lsf(flow_mapping,STA,timing)        "L"
set lsf(flow_mapping,STA,reporting)     "M"
set lsf(flow_mapping,STA,export_data)   "S"
set lsf(flow_mapping,STA,release_data)  "S"
# SYNTH
set lsf(flow_mapping,SYNTH,synthesis)   "M"
set lsf(flow_mapping,SYNTH,export_data) "S"
set lsf(flow_mapping,SYNTH,release_data) "S"
# ECO
set lsf(flow_mapping,ECO,eco)           "L"
set lsf(flow_mapping,ECO,export_db)     "M"
# EMIR
set lsf(flow_mapping,EMIR,power_analysis)    "L"
set lsf(flow_mapping,EMIR,ir_drop)           "L"
set lsf(flow_mapping,EMIR,thermal_analysis)  "XL"
