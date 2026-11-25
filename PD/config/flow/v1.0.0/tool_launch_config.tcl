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
# PD discipline (Synopsys, Cadence, Mentor)
set lsf(tool_shell,fc)           "fc_shell"
set lsf(tool_shell,pt)           "pt_shell"
set lsf(tool_shell,fm)           "fm_shell"
set lsf(tool_shell,formality)    "fm_shell"
set lsf(tool_shell,vc_lp)        "vc_lp_shell"
set lsf(tool_shell,icv)          "icv"
set lsf(tool_shell,redhawk)      "redhawk"
set lsf(tool_shell,genus)        "genus"
set lsf(tool_shell,innovus)      "innovus"
set lsf(tool_shell,tempus)       "tempus"
set lsf(tool_shell,voltus)       "voltus"
set lsf(tool_shell,calibre)      "calibre"
set lsf(tool_shell,conformal_lp) "conformal_lp"
set lsf(tool_shell,conformal)    "conformal"
set lsf(tool_shell,joules)       "joules"
# DFT discipline (Mentor Tessent, Synopsys DFT/TestMAX/VCS, Mentor Questa)
set lsf(tool_shell,tessent)      "tessent"
set lsf(tool_shell,dft_compiler) "dc_shell"
set lsf(tool_shell,testmax)      "tmax"
set lsf(tool_shell,vcs)          "vcs"
set lsf(tool_shell,questa)       "vsim"

# Open-source stack (vendor "opensource"): container tool shells, image and
# tools dir — shared with the other disciplines (global/config/flow).
set _flow_cfg_dir [file dirname [file normalize [info script]]]   ;# <root>/PD/config/flow/<ver>
source [file join [file dirname [file dirname [file dirname [file dirname $_flow_cfg_dir]]]] \
    global config flow [file tail $_flow_cfg_dir] oss_launch_config.tcl]
unset _flow_cfg_dir

# ┌─ Tool Short Names (dashboard DAG node labels "<node> [FC]") ─────────────┐
# Tools without an entry are labelled with their full name.
set lsf(tool_short,fc)           "FC"
set lsf(tool_short,pt)           "PT"
set lsf(tool_short,fm)           "FM"
set lsf(tool_short,formality)    "FM"
set lsf(tool_short,icv)          "ICV"
set lsf(tool_short,redhawk)      "RH"
set lsf(tool_short,vc_lp)        "VLP"
set lsf(tool_short,genus)        "GEN"
set lsf(tool_short,innovus)      "INV"
set lsf(tool_short,tempus)       "TMP"
set lsf(tool_short,voltus)       "VLT"
set lsf(tool_short,calibre)      "CAL"
set lsf(tool_short,conformal_lp) "CLP"

# ┌─ Wrapper Shell ──────────────────────────────────────────────────────────┐
set lsf(tool_wrapper_shell)     "/bin/csh -f"

# ┌─ Interactive Sessions (cbflow run interactive) ──────────────────────────┐
# Read by global/utils/commands/run_cmd.py cmd_interactive. `<…>,default`
# applies to every tool without its own entry.
#
# Launch with a node to load:  <tool_shell> <load_flags> "<load_script>"
set lsf(interactive,load_flags,default) "-f"
set lsf(interactive,load_flags,fc)      "-gui -f"
set lsf(interactive,load_flags,fm)      "-gui -f"
set lsf(interactive,load_flags,innovus) "-init"
# Launch without a node:       <tool_shell> <empty_flags>
set lsf(interactive,empty_flags,default) ""
set lsf(interactive,empty_flags,fc)      "-gui"
set lsf(interactive,empty_flags,fm)      "-gui"
# GUI binary that replaces the tool shell for a session without a node
set lsf(tool_gui_shell,icv)     "icv -vue"
set lsf(tool_gui_shell,calibre) "calibredrv"
# Restore script appended to the generated load script. Tcl, kept verbatim.
# The load script sets these before it: cbflow_flow_type cbflow_tool
# cbflow_run_dir cbflow_load_node cbflow_parent_stage cbflow_scenario ("" for
# a stage) cbflow_node_base cbflow_work_dir (work/<FLOW>/<parent_stage>)
# cbflow_session_name cbflow_design_name cbflow_notiming (0|1).
# OpenROAD (open-source PNR / FP, and their oss_tclsh export / release nodes):
# load the node's database + timing views (oss_load_node)
set lsf(interactive,restore,openroad) {
set FLOW_TYPE $cbflow_flow_type
set NODE_NAME $cbflow_parent_stage
set run_dir $cbflow_run_dir
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_utils.tcl"
set design_name [oss_get flow design_name]
set blocks [hier_children $design_name]
if {[catch {oss_load_node $NODE_NAME $blocks} _odb]} {
    puts "WARNING: $NODE_NAME not loaded: $_odb"
} else {
    puts ""
    puts "═══════════════════════════════════════════════════"
    puts "  CBflow Interactive — $NODE_NAME loaded ($_odb)"
    puts "  Timing views: [oss_node_views [oss_view_node $NODE_NAME]]"
    puts "  Session: INTERACTIVE/$cbflow_session_name"
    puts "═══════════════════════════════════════════════════"
}
}
set lsf(interactive,restore,oss_tclsh) $lsf(interactive,restore,openroad)
set lsf(interactive,restore,fc) {
set nlib_path [file join $cbflow_work_dir ${cbflow_load_node}.nlib]
set nlib_alt  [file join $cbflow_run_dir work $cbflow_flow_type $cbflow_load_node ${cbflow_load_node}.nlib]
if {[file exists $nlib_path]} {
    open_lib $nlib_path
    puts "INFO: Loaded design library: $nlib_path"
} elseif {[file exists $nlib_alt]} {
    open_lib $nlib_alt
    puts "INFO: Loaded design library: $nlib_alt"
} else {
    puts "WARNING: No .nlib found for $cbflow_load_node"
    puts "  Searched: $nlib_path"
    puts "  Searched: $nlib_alt"
    puts "  Starting empty session"
}
puts ""
puts "═══════════════════════════════════════════════════"
puts "  CBflow Interactive — $cbflow_load_node loaded"
puts "  Run directory: $cbflow_run_dir"
puts "  Session: INTERACTIVE/$cbflow_session_name"
puts "═══════════════════════════════════════════════════"
}
set lsf(interactive,restore,pt) {
set session_dir [file join $cbflow_work_dir run]
if {$cbflow_scenario ne ""} {
    set ctx_file [file join $session_dir ${cbflow_scenario}_context.tcl]
    if {[file exists $ctx_file]} {
        source $ctx_file
        puts "INFO: Loaded scenario context: $ctx_file"
    } else {
        puts "WARNING: Scenario context not found: $ctx_file"
    }
    set exact_session [file join $session_dir ${cbflow_load_node}.session]
    if {[file exists $exact_session]} {
        restore_session $exact_session
        puts "INFO: Restored scenario session: $exact_session"
    } else {
        puts "WARNING: No session for scenario $cbflow_scenario"
        puts "  Expected: $exact_session"
        puts "  Starting empty session — context globals are still set"
    }
} else {
    set session_files [glob -nocomplain "$session_dir/*.session"]
    if {[llength $session_files] > 0} {
        puts "INFO: Available sessions in $cbflow_parent_stage:"
        foreach _s $session_files { puts "    [file tail $_s]" }
        set ss [lindex $session_files 0]
        restore_session $ss
        puts "INFO: Restored session: $ss"
        puts "INFO: To load a specific scenario, re-run with:"
        puts "      cbflow run interactive --node ${cbflow_parent_stage}_<scenario>"
    } else {
        set db_files [glob -nocomplain "$session_dir/*.db"]
        if {[llength $db_files] > 0} {
            read_db [lindex $db_files end]
            puts "INFO: Loaded timing DB"
        } else {
            puts "WARNING: No saved session found for $cbflow_load_node"
            puts "  Starting empty session — use read_verilog, read_sdc, etc."
        }
    }
}
puts ""
puts "═══════════════════════════════════════════════════"
puts "  CBflow Interactive — $cbflow_load_node (PrimeTime)"
if {$cbflow_scenario ne ""} { puts "  Stage: $cbflow_parent_stage  Scenario: $cbflow_scenario" }
puts "  Run directory: $cbflow_run_dir"
puts "═══════════════════════════════════════════════════"
}
set lsf(interactive,restore,innovus) {
set _db [file join $cbflow_work_dir outputs ${cbflow_node_base}.enc.dat]
if {[file exists $_db]} {
    if {$cbflow_notiming} {
        restoreDesign -noTiming $_db $cbflow_design_name
        puts "INFO: Restored design: $_db ($cbflow_design_name)  \[noTiming\]"
    } else {
        restoreDesign $_db $cbflow_design_name
        puts "INFO: Restored design: $_db ($cbflow_design_name)"
    }
} else {
    puts "WARNING: No .enc.dat found: $_db"
    puts "  Run the flow first or check outputs/ directory"
}
puts ""
puts "═══════════════════════════════════════════════════"
puts "  CBflow Interactive — $cbflow_load_node ($cbflow_tool)"
puts "  Design: $cbflow_design_name"
puts "  Run directory: $cbflow_run_dir"
puts "  Session: INTERACTIVE/$cbflow_session_name"
puts "═══════════════════════════════════════════════════"
}
set lsf(interactive,restore,tempus) {
set session_dir [file join $cbflow_work_dir run]
if {$cbflow_scenario ne ""} {
    set ctx_file [file join $session_dir ${cbflow_scenario}_context.tcl]
    if {[file exists $ctx_file]} {
        source $ctx_file
        puts "INFO: Loaded scenario context: $ctx_file"
    }
    set exact_db [file join $session_dir ${cbflow_load_node}.db]
    if {[file exists $exact_db]} {
        read_db $exact_db
        puts "INFO: Loaded scenario DB: $exact_db"
    } else {
        puts "WARNING: No DB for scenario $cbflow_scenario"
        puts "  Expected: $exact_db"
    }
} else {
    set db_files [glob -nocomplain "$session_dir/*.db"]
    if {[llength $db_files] > 0} {
        read_db [lindex $db_files end]
        puts "INFO: Loaded timing DB"
    } else {
        puts "WARNING: No saved session found for $cbflow_load_node"
    }
}
}
set lsf(interactive,restore,default) {
puts "INFO: Interactive session for $cbflow_load_node ($cbflow_tool)"
puts "  Work dir: $cbflow_work_dir"
}

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
set lsf(flow_mapping,pv,nettran)          "S"
set lsf(flow_mapping,pv,merge_gds)        "M"
set lsf(flow_mapping,pv,fill_merge_gds)   "M"
set lsf(flow_mapping,pv,decomp)           "L"
set lsf(flow_mapping,pv,decomp_merge_gds) "M"
set lsf(flow_mapping,pv,drc)              "L"
set lsf(flow_mapping,pv,lvs)              "L"
set lsf(flow_mapping,pv,perc)             "M"
set lsf(flow_mapping,pv,perc_ldl)         "M"
set lsf(flow_mapping,pv,xor)              "M"
set lsf(flow_mapping,pv,merge_data)       "S"
set lsf(flow_mapping,pv,release_data)     "S"

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
