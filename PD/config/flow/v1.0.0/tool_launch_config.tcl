#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow Tool Launch Configuration
#
# Purpose: Stage-to-tier mappings and tool shell/module settings.
# Sourced by subnode handlers for tool execution.
#
# NOTE: Queue tier definitions (memory, CPU, runtime) are in lsf_config.tcl.
#       Do NOT duplicate tier definitions here.
#       This file only maps stages to tiers and defines tool launch commands.
# ═══════════════════════════════════════════════════════════════════════════════

# ┌─ Tool Shell Commands ────────────────────────────────────────────────────┐
set lsf(tool_shell,fc)          "fc_shell"
set lsf(tool_shell,pt)          "pt_shell"
set lsf(tool_shell,fm)          "fm_shell"
set lsf(tool_shell,formality)   "fm_shell"
set lsf(tool_shell,vc_lp)       "vc_lp_shell"
set lsf(tool_shell,icv)         "icv"
set lsf(tool_shell,redhawk)     "redhawk"
set lsf(tool_shell,genus)       "genus"
set lsf(tool_shell,innovus)     "innovus"
set lsf(tool_shell,tempus)      "tempus"
set lsf(tool_shell,voltus)      "voltus"
set lsf(tool_shell,calibre)     "calibre"
set lsf(tool_shell,conformal_lp) "conformal_lp"

# ┌─ Wrapper Shell ──────────────────────────────────────────────────────────┐
set lsf(tool_wrapper_shell)     "/bin/csh -f"

# ┌─ Flow-to-Tier Stage Mappings ───────────────────────────────────────────┐
# Maps each stage to a queue tier defined in lsf_config.tcl (XS/S/M/L/XL/ultra).
# Only stages that differ from the default tier (M) need entries here.

# SYNTH_PNR
set lsf(flow_mapping,synth_pnr,init_design)  "S"
set lsf(flow_mapping,synth_pnr,synthesis)     "M"
set lsf(flow_mapping,synth_pnr,place)         "L"
set lsf(flow_mapping,synth_pnr,cts)           "L"
set lsf(flow_mapping,synth_pnr,cts_opt)       "L"
set lsf(flow_mapping,synth_pnr,route)         "XL"
set lsf(flow_mapping,synth_pnr,pro)           "L"
set lsf(flow_mapping,synth_pnr,signoff)       "M"
set lsf(flow_mapping,synth_pnr,export_data)   "S"
set lsf(flow_mapping,synth_pnr,release_data)  "S"

# PNR
set lsf(flow_mapping,pnr,init_design)  "S"
set lsf(flow_mapping,pnr,place)        "L"
set lsf(flow_mapping,pnr,cts)          "L"
set lsf(flow_mapping,pnr,cts_opt)      "L"
set lsf(flow_mapping,pnr,route)        "XL"
set lsf(flow_mapping,pnr,pro)          "L"
set lsf(flow_mapping,pnr,signoff)      "L"
set lsf(flow_mapping,pnr,export_data)  "M"
set lsf(flow_mapping,pnr,release_data) "S"

# SYNTH
set lsf(flow_mapping,synth,init_design)  "S"
set lsf(flow_mapping,synth,synthesis)    "M"
set lsf(flow_mapping,synth,export_data)  "S"
set lsf(flow_mapping,synth,release_data) "S"

# FP
set lsf(flow_mapping,fp,init_design)    "S"
set lsf(flow_mapping,fp,import_design)  "M"
set lsf(flow_mapping,fp,floorplan)      "M"
set lsf(flow_mapping,fp,powerplan)      "L"
set lsf(flow_mapping,fp,post_floorplan) "M"
set lsf(flow_mapping,fp,place_pins)     "M"
set lsf(flow_mapping,fp,export_data)    "S"
set lsf(flow_mapping,fp,release_data)   "S"

# FCFP
set lsf(flow_mapping,fcfp,init_design)      "S"
set lsf(flow_mapping,fcfp,commit_blocks)     "M"
set lsf(flow_mapping,fcfp,init_compile)      "M"
set lsf(flow_mapping,fcfp,create_floorplan)  "L"
set lsf(flow_mapping,fcfp,shaping)           "M"
set lsf(flow_mapping,fcfp,placement)         "L"
set lsf(flow_mapping,fcfp,create_power)      "L"
set lsf(flow_mapping,fcfp,place_pins)        "M"
set lsf(flow_mapping,fcfp,top_compile)       "L"
set lsf(flow_mapping,fcfp,timing_budget)     "M"
set lsf(flow_mapping,fcfp,export_data)       "S"
set lsf(flow_mapping,fcfp,release_data)      "S"

# STA
set lsf(flow_mapping,sta,extraction)    "L"
set lsf(flow_mapping,sta,timing)        "L"
set lsf(flow_mapping,sta,reporting)     "M"
set lsf(flow_mapping,sta,release_data)  "S"

# PV
set lsf(flow_mapping,pv,fill)          "L"
set lsf(flow_mapping,pv,drc)           "L"
set lsf(flow_mapping,pv,lvs)           "L"
set lsf(flow_mapping,pv,erc)           "M"
set lsf(flow_mapping,pv,perc)          "M"
set lsf(flow_mapping,pv,xor)           "M"
set lsf(flow_mapping,pv,merge_data)    "S"
set lsf(flow_mapping,pv,release_data)  "S"

# LEC
set lsf(flow_mapping,lec,setup)    "M"
set lsf(flow_mapping,lec,compare)  "M"
set lsf(flow_mapping,lec,analyze)  "S"

# CLP
set lsf(flow_mapping,clp,clp)           "M"
set lsf(flow_mapping,clp,release_data)  "S"

# ECO
set lsf(flow_mapping,eco,eco)        "L"
set lsf(flow_mapping,eco,export_db)  "M"

# EMIR
set lsf(flow_mapping,emir,power_analysis)    "L"
set lsf(flow_mapping,emir,ir_drop)           "L"
set lsf(flow_mapping,emir,thermal_analysis)  "XL"

# POPT
set lsf(flow_mapping,popt,merge_timing)  "M"
set lsf(flow_mapping,popt,power_opt)     "L"
set lsf(flow_mapping,popt,post_merge)    "M"
set lsf(flow_mapping,popt,release_data)  "S"
