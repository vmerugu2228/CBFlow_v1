#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow Technology Configuration — GlobalFoundries 22FDX (22nm FD-SOI)
# ═══════════════════════════════════════════════════════════════════════════════

# ── Path Resolution ───────────────────────────────────────────────────────────
set _tech_dir [file dirname [file normalize [info script]]]

# ── Technology Info ───────────────────────────────────────────────────────────
set tech(node)        "22nm"
set tech(process)     "GF"
set tech(variant)     "FDX"
set tech(foundry)     "GlobalFoundries"
set tech(metal_stack_name) "11M"
set tech(revision)    "v1.0"

# ═══════════════════════════════════════════════════════════════════════════════
# LIBRARY PATHS
# ═══════════════════════════════════════════════════════════════════════════════
set tech(library,root_path)    "/tmp/test_libs/gf_22nm"
set tech(library,stdcell_path) "$tech(library,root_path)/Front_End/timing/stdcell"
set tech(library,memory_path)  "$tech(library,root_path)/Front_End/timing/memory"
set tech(library,io_path)      "$tech(library,root_path)/Front_End/timing/io"

# Cell library prefixes (GF 22FDX naming)
set _STDCELL "tcbn22cllbwp7t"
set _MEMORY  "ts6n22cllhdlvt512x8m4sw"
set _IO      "tphn22v"

# ═══════════════════════════════════════════════════════════════════════════════
# NDM LIBRARIES (Fusion Compiler — preferred)
# ═══════════════════════════════════════════════════════════════════════════════
set tech(ndm,standard_cells) "$tech(library,root_path)/Back_End/ndm/stdcell/${_STDCELL}.ndm"
set tech(ndm,memory)         "$tech(library,root_path)/Back_End/ndm/memory/${_MEMORY}.ndm"
set tech(ndm,io_pads)        "$tech(library,root_path)/Back_End/ndm/io/${_IO}.ndm"
set tech(ndm,parasitic_tech) ""
set tech(ndm,tech_lib)       ""
set tech(ndm,sub_blocks)     {}
set tech(ndm,additional)     {}

# ═══════════════════════════════════════════════════════════════════════════════
# LEF FILES (Physical — fallback when NDM unavailable)
# ═══════════════════════════════════════════════════════════════════════════════
set tech(lef,technology)      "$tech(library,root_path)/Back_End/lef/gf22nm_tech.lef"
set tech(lef,standard_cells)  "$tech(library,root_path)/Back_End/lef/stdcell/${_STDCELL}.lef"
set tech(lef,macros)          "$tech(library,root_path)/Back_End/lef/memory/${_MEMORY}.lef"
set tech(lef,io_pads)         "$tech(library,root_path)/Back_End/lef/io/${_IO}.lef"

# ═══════════════════════════════════════════════════════════════════════════════
# DB FILES (Synopsys .db — fallback for fusion library creation)
# ═══════════════════════════════════════════════════════════════════════════════
set tech(db,standard_cells) "$tech(library,root_path)/Front_End/timing/stdcell/${_STDCELL}tt0p80v25c.db"
set tech(db,memory)         "$tech(library,root_path)/Front_End/timing/memory/${_MEMORY}tt0p80v25c.db"
set tech(db,io_pads)        "$tech(library,root_path)/Front_End/timing/io/${_IO}_tt0p80v25c.db"

# ═══════════════════════════════════════════════════════════════════════════════
# TLU+ PARASITIC EXTRACTION
# ═══════════════════════════════════════════════════════════════════════════════
set tech(tluplus,max) "$tech(library,root_path)/Back_End/rcx/gf22nm_1p11m_Cmax.tluplus"
set tech(tluplus,min) "$tech(library,root_path)/Back_End/rcx/gf22nm_1p11m_Cmin.tluplus"
set tech(tluplus,map) "$tech(library,root_path)/Back_End/rcx/gf22nm_tf_itf_tluplus.map"

# Legacy single-corner timing libs (nominal TT)
set tech(lib,timing) "$tech(library,stdcell_path)/${_STDCELL}tt0p80v25c_ccs.lib"
set tech(lib,power)  "$tech(library,stdcell_path)/${_STDCELL}tt0p80v25c_power.lib"
set tech(lib,ccs)    "$tech(library,stdcell_path)/${_STDCELL}tt0p80v25c_ccs.lib"

# ═══════════════════════════════════════════════════════════════════════════════
# LIBRARY SETS — Aligned with MMMC analysis_views lib_set_ref
# Naming: <corner>_<voltage>v_<temp>c (e.g., ss_0800v_150c)
# ═══════════════════════════════════════════════════════════════════════════════

# SS Corner (Slow-Slow) — Setup Critical
set library_sets(ss_0760v_150c,description) "SS 0.76V 150C — worst setup"
set library_sets(ss_0760v_150c,corner)      "ss"
set library_sets(ss_0760v_150c,voltage)     "0.76"
set library_sets(ss_0760v_150c,temperature) "150"
set library_sets(ss_0760v_150c,timing)      "$tech(library,stdcell_path)/${_STDCELL}ss0p76v150c_ccs.lib $tech(library,memory_path)/${_MEMORY}ss0p76v150c_ccs.lib $tech(library,io_path)/${_IO}_ss0p76v150c_ccs.lib"
set library_sets(ss_0760v_150c,power)       "$tech(library,stdcell_path)/${_STDCELL}ss0p76v150c_power.lib $tech(library,memory_path)/${_MEMORY}ss0p76v150c_power.lib"

set library_sets(ss_0760v_25c,description)  "SS 0.76V 25C"
set library_sets(ss_0760v_25c,corner)       "ss"
set library_sets(ss_0760v_25c,voltage)      "0.76"
set library_sets(ss_0760v_25c,temperature)  "25"
set library_sets(ss_0760v_25c,timing)       "$tech(library,stdcell_path)/${_STDCELL}ss0p76v25c_ccs.lib $tech(library,memory_path)/${_MEMORY}ss0p76v25c_ccs.lib $tech(library,io_path)/${_IO}_ss0p76v25c_ccs.lib"
set library_sets(ss_0760v_25c,power)        "$tech(library,stdcell_path)/${_STDCELL}ss0p76v25c_power.lib $tech(library,memory_path)/${_MEMORY}ss0p76v25c_power.lib"

set library_sets(ss_0760v_m40c,description) "SS 0.76V -40C"
set library_sets(ss_0760v_m40c,corner)      "ss"
set library_sets(ss_0760v_m40c,voltage)     "0.76"
set library_sets(ss_0760v_m40c,temperature) "-40"
set library_sets(ss_0760v_m40c,timing)      "$tech(library,stdcell_path)/${_STDCELL}ss0p76vm40c_ccs.lib $tech(library,memory_path)/${_MEMORY}ss0p76vm40c_ccs.lib $tech(library,io_path)/${_IO}_ss0p76vm40c_ccs.lib"
set library_sets(ss_0760v_m40c,power)       "$tech(library,stdcell_path)/${_STDCELL}ss0p76vm40c_power.lib $tech(library,memory_path)/${_MEMORY}ss0p76vm40c_power.lib"

set library_sets(ss_0800v_150c,description) "SS 0.80V 150C"
set library_sets(ss_0800v_150c,corner)      "ss"
set library_sets(ss_0800v_150c,voltage)     "0.80"
set library_sets(ss_0800v_150c,temperature) "150"
set library_sets(ss_0800v_150c,timing)      "$tech(library,stdcell_path)/${_STDCELL}ss0p80v150c_ccs.lib $tech(library,memory_path)/${_MEMORY}ss0p80v150c_ccs.lib $tech(library,io_path)/${_IO}_ss0p80v150c_ccs.lib"
set library_sets(ss_0800v_150c,power)       "$tech(library,stdcell_path)/${_STDCELL}ss0p80v150c_power.lib $tech(library,memory_path)/${_MEMORY}ss0p80v150c_power.lib"

set library_sets(ss_0800v_25c,description)  "SS 0.80V 25C"
set library_sets(ss_0800v_25c,corner)       "ss"
set library_sets(ss_0800v_25c,voltage)      "0.80"
set library_sets(ss_0800v_25c,temperature)  "25"
set library_sets(ss_0800v_25c,timing)       "$tech(library,stdcell_path)/${_STDCELL}ss0p80v25c_ccs.lib $tech(library,memory_path)/${_MEMORY}ss0p80v25c_ccs.lib $tech(library,io_path)/${_IO}_ss0p80v25c_ccs.lib"
set library_sets(ss_0800v_25c,power)        "$tech(library,stdcell_path)/${_STDCELL}ss0p80v25c_power.lib $tech(library,memory_path)/${_MEMORY}ss0p80v25c_power.lib"

# TT Corner (Typical) — Nominal
set library_sets(tt_0800v_150c,description) "TT 0.80V 150C — nominal hot"
set library_sets(tt_0800v_150c,corner)      "tt"
set library_sets(tt_0800v_150c,voltage)     "0.80"
set library_sets(tt_0800v_150c,temperature) "150"
set library_sets(tt_0800v_150c,timing)      "$tech(library,stdcell_path)/${_STDCELL}tt0p80v150c_ccs.lib $tech(library,memory_path)/${_MEMORY}tt0p80v150c_ccs.lib $tech(library,io_path)/${_IO}_tt0p80v150c_ccs.lib"
set library_sets(tt_0800v_150c,power)       "$tech(library,stdcell_path)/${_STDCELL}tt0p80v150c_power.lib $tech(library,memory_path)/${_MEMORY}tt0p80v150c_power.lib"

set library_sets(tt_0800v_25c,description)  "TT 0.80V 25C — nominal"
set library_sets(tt_0800v_25c,corner)       "tt"
set library_sets(tt_0800v_25c,voltage)      "0.80"
set library_sets(tt_0800v_25c,temperature)  "25"
set library_sets(tt_0800v_25c,timing)       "$tech(library,stdcell_path)/${_STDCELL}tt0p80v25c_ccs.lib $tech(library,memory_path)/${_MEMORY}tt0p80v25c_ccs.lib $tech(library,io_path)/${_IO}_tt0p80v25c_ccs.lib"
set library_sets(tt_0800v_25c,power)        "$tech(library,stdcell_path)/${_STDCELL}tt0p80v25c_power.lib $tech(library,memory_path)/${_MEMORY}tt0p80v25c_power.lib"

set library_sets(tt_0800v_m40c,description) "TT 0.80V -40C — nominal cold"
set library_sets(tt_0800v_m40c,corner)      "tt"
set library_sets(tt_0800v_m40c,voltage)     "0.80"
set library_sets(tt_0800v_m40c,temperature) "-40"
set library_sets(tt_0800v_m40c,timing)      "$tech(library,stdcell_path)/${_STDCELL}tt0p80vm40c_ccs.lib $tech(library,memory_path)/${_MEMORY}tt0p80vm40c_ccs.lib $tech(library,io_path)/${_IO}_tt0p80vm40c_ccs.lib"
set library_sets(tt_0800v_m40c,power)       "$tech(library,stdcell_path)/${_STDCELL}tt0p80vm40c_power.lib $tech(library,memory_path)/${_MEMORY}tt0p80vm40c_power.lib"

# FF Corner (Fast-Fast) — Hold Critical
set library_sets(ff_0800v_m40c,description) "FF 0.80V -40C"
set library_sets(ff_0800v_m40c,corner)      "ff"
set library_sets(ff_0800v_m40c,voltage)     "0.80"
set library_sets(ff_0800v_m40c,temperature) "-40"
set library_sets(ff_0800v_m40c,timing)      "$tech(library,stdcell_path)/${_STDCELL}ff0p80vm40c_ccs.lib $tech(library,memory_path)/${_MEMORY}ff0p80vm40c_ccs.lib $tech(library,io_path)/${_IO}_ff0p80vm40c_ccs.lib"
set library_sets(ff_0800v_m40c,power)       "$tech(library,stdcell_path)/${_STDCELL}ff0p80vm40c_power.lib $tech(library,memory_path)/${_MEMORY}ff0p80vm40c_power.lib"

set library_sets(ff_0840v_150c,description) "FF 0.84V 150C"
set library_sets(ff_0840v_150c,corner)      "ff"
set library_sets(ff_0840v_150c,voltage)     "0.84"
set library_sets(ff_0840v_150c,temperature) "150"
set library_sets(ff_0840v_150c,timing)      "$tech(library,stdcell_path)/${_STDCELL}ff0p84v150c_ccs.lib $tech(library,memory_path)/${_MEMORY}ff0p84v150c_ccs.lib $tech(library,io_path)/${_IO}_ff0p84v150c_ccs.lib"
set library_sets(ff_0840v_150c,power)       "$tech(library,stdcell_path)/${_STDCELL}ff0p84v150c_power.lib $tech(library,memory_path)/${_MEMORY}ff0p84v150c_power.lib"

set library_sets(ff_0840v_25c,description)  "FF 0.84V 25C"
set library_sets(ff_0840v_25c,corner)       "ff"
set library_sets(ff_0840v_25c,voltage)      "0.84"
set library_sets(ff_0840v_25c,temperature)  "25"
set library_sets(ff_0840v_25c,timing)       "$tech(library,stdcell_path)/${_STDCELL}ff0p84v25c_ccs.lib $tech(library,memory_path)/${_MEMORY}ff0p84v25c_ccs.lib $tech(library,io_path)/${_IO}_ff0p84v25c_ccs.lib"
set library_sets(ff_0840v_25c,power)        "$tech(library,stdcell_path)/${_STDCELL}ff0p84v25c_power.lib $tech(library,memory_path)/${_MEMORY}ff0p84v25c_power.lib"

set library_sets(ff_0840v_m40c,description) "FF 0.84V -40C — worst hold"
set library_sets(ff_0840v_m40c,corner)      "ff"
set library_sets(ff_0840v_m40c,voltage)     "0.84"
set library_sets(ff_0840v_m40c,temperature) "-40"
set library_sets(ff_0840v_m40c,timing)      "$tech(library,stdcell_path)/${_STDCELL}ff0p84vm40c_ccs.lib $tech(library,memory_path)/${_MEMORY}ff0p84vm40c_ccs.lib $tech(library,io_path)/${_IO}_ff0p84vm40c_ccs.lib"
set library_sets(ff_0840v_m40c,power)       "$tech(library,stdcell_path)/${_STDCELL}ff0p84vm40c_power.lib $tech(library,memory_path)/${_MEMORY}ff0p84vm40c_power.lib"

# ═══════════════════════════════════════════════════════════════════════════════
# TECHNOLOGY SCRIPTS (alongside this file)
# ═══════════════════════════════════════════════════════════════════════════════
set tech(tech_setup_script)     "$_tech_dir/tech_setup.tcl"
set tech(lib_cell_purpose_file) "$_tech_dir/set_lib_cell_purpose.tcl"
set tech(cts_ndr_file)          "$_tech_dir/cts_ndr.tcl"

# Tech file (.tf) — routing rules and layer definitions
set tech(tech_file) ""

# ═══════════════════════════════════════════════════════════════════════════════
# CELL RESTRICTIONS (used by set_lib_cell_purpose.tcl)
# ═══════════════════════════════════════════════════════════════════════════════
set tech(dont_use_cells) {
    "*/GF22FDX_SC9T_*_DELLN*"
    "*/GF22FDX_SC9T_*_DEL0*"
    "*/GF22FDX_SC9T_*_ANTENNA*"
    "*/GF22FDX_SC9T_*_DCAP*X1"
}
set tech(tie_lib_cells)       "*/GF22FDX_SC9T_*_TIEH* */GF22FDX_SC9T_*_TIEL*"
set tech(hold_fix_lib_cells)  "*/GF22FDX_SC9T_*_BUFX1 */GF22FDX_SC9T_*_BUFX2 */GF22FDX_SC9T_*_DLYB*"
set tech(cts_lib_cells)       "*/GF22FDX_SC9T_*_CKBUF* */GF22FDX_SC9T_*_CKINV* */GF22FDX_SC9T_*_CKND* */GF22FDX_SC9T_*_SDFF*"
set tech(cts_only_lib_cells)  "*/GF22FDX_SC9T_*_CKBUF* */GF22FDX_SC9T_*_CKINV*"

# ═══════════════════════════════════════════════════════════════════════════════
# CTS NDR CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════════
set tech(cts_ndr,root_rule)     "rm_2w2s"
set tech(cts_ndr,internal_rule) "rm_2w2s"
set tech(cts_ndr,leaf_rule)     ""
set tech(cts_ndr,min_layer)     "M3"
set tech(cts_ndr,max_layer)     "M7"
set tech(via_ladder_file)       ""

# ═══════════════════════════════════════════════════════════════════════════════
# ON-CHIP VARIATION (OCV)
# ═══════════════════════════════════════════════════════════════════════════════
set tech(ocv,derate_file) ""

# ═══════════════════════════════════════════════════════════════════════════════
# DESIGN RULES (GF 22FDX 9T)
# ═══════════════════════════════════════════════════════════════════════════════
set tech(dr,min_width)   "0.064"
set tech(dr,min_spacing) "0.064"
set tech(dr,via_size)    "0.050"
set tech(dr,track_pitch) "0.090"
set tech(dr,m1_pitch)    "0.064"
set tech(dr,site_width)  "0.114"
set tech(dr,site_height) "0.810"

# Metal stack (GF 22FDX 11M: 1P11M)
set tech(metal_stack) {
    {M1  horizontal 0.064}
    {M2  vertical   0.064}
    {M3  horizontal 0.090}
    {M4  vertical   0.090}
    {M5  horizontal 0.090}
    {M6  vertical   0.090}
    {M7  horizontal 0.090}
    {M8  vertical   0.180}
    {M9  horizontal 0.180}
    {M10 vertical   0.720}
    {M11 horizontal 0.720}
}

# Routing layer constraints
set tech(routing,min_layer)    "M2"
set tech(routing,max_layer)    "M9"
set tech(routing,clock_min)    "M3"
set tech(routing,clock_max)    "M7"
set tech(routing,power_layers) "M10 M11"

# Tech setup variables (used by tech_setup.tcl)
set tech(routing_layer_direction_offset) {
    {M1  horizontal 0.0}
    {M2  vertical   0.0}
    {M3  horizontal 0.0}
    {M4  vertical   0.0}
    {M5  horizontal 0.0}
    {M6  vertical   0.0}
    {M7  horizontal 0.0}
}
set tech(site_default)  "GF22FDX_SC9T"
set tech(site_symmetry) "Y"

# ═══════════════════════════════════════════════════════════════════════════════
# STANDARD CELL NAMES (GF 22FDX 9T SVT)
# ═══════════════════════════════════════════════════════════════════════════════
set tech(cells,site)       "GF22FDX_SC9T"
set tech(cells,height)     "0.810"
set tech(cells,min_width)  "0.114"
set tech(cells,power_pins) "VDD VSS"

# Physical cells
set tech(cells,well_tap)   "GF22FDX_SC9T_SVT_FILLTIE1 GF22FDX_SC9T_SVT_FILLTIE2"
set tech(cells,tie_high)   "GF22FDX_SC9T_SVT_TIEH"
set tech(cells,tie_low)    "GF22FDX_SC9T_SVT_TIEL"
set tech(cells,filler)     "GF22FDX_SC9T_SVT_FILL1 GF22FDX_SC9T_SVT_FILL2 GF22FDX_SC9T_SVT_FILL4 GF22FDX_SC9T_SVT_FILL8 GF22FDX_SC9T_SVT_FILL16 GF22FDX_SC9T_SVT_FILL32"
set tech(cells,decap)      "GF22FDX_SC9T_SVT_DCAP4 GF22FDX_SC9T_SVT_DCAP8 GF22FDX_SC9T_SVT_DCAP16"
set tech(cells,endcap)     "GF22FDX_SC9T_SVT_ENDCAP"
set tech(cells,antenna)    "GF22FDX_SC9T_SVT_ANTENNAX1"

# Logic cells
set tech(cells,buf)        "GF22FDX_SC9T_SVT_BUFX1 GF22FDX_SC9T_SVT_BUFX2 GF22FDX_SC9T_SVT_BUFX4 GF22FDX_SC9T_SVT_BUFX8 GF22FDX_SC9T_SVT_BUFX16"
set tech(cells,inv)        "GF22FDX_SC9T_SVT_INVX1 GF22FDX_SC9T_SVT_INVX2 GF22FDX_SC9T_SVT_INVX4 GF22FDX_SC9T_SVT_INVX8"
set tech(cells,delay)      "GF22FDX_SC9T_SVT_DLYB1X1 GF22FDX_SC9T_SVT_DLYB2X1 GF22FDX_SC9T_SVT_DLYB4X1"

# Clock cells
set tech(cells,clk_buf)    "GF22FDX_SC9T_SVT_CKBUFX2 GF22FDX_SC9T_SVT_CKBUFX4 GF22FDX_SC9T_SVT_CKBUFX8 GF22FDX_SC9T_SVT_CKBUFX16 GF22FDX_SC9T_SVT_CKBUFX20"
set tech(cells,clk_inv)    "GF22FDX_SC9T_SVT_CKINVX2 GF22FDX_SC9T_SVT_CKINVX4 GF22FDX_SC9T_SVT_CKINVX8 GF22FDX_SC9T_SVT_CKINVX16"
set tech(cells,icg)        "GF22FDX_SC9T_SVT_ICGX1 GF22FDX_SC9T_SVT_ICGX2 GF22FDX_SC9T_SVT_ICGX4"
set tech(cells,clk_gate)   "GF22FDX_SC9T_SVT_TLATNCAX2 GF22FDX_SC9T_SVT_TLATNCAX4"

# Voltage threshold variants
set tech(vt_types)   "ULVT LVT SVT HVT"
set tech(vt_default) "SVT"

# ═══════════════════════════════════════════════════════════════════════════════
# MULTI-TRACK LIBRARY SUPPORT
# ═══════════════════════════════════════════════════════════════════════════════
set tech(track,available_variants) {9T 7.5T 8T}
set tech(track,default_variant)    "9T"

if {![info exists tech(track,active_variant)]} {
    set tech(track,active_variant) $tech(track,default_variant)
}

array set track_variants {
    "9T" {
        cell_height     "0.810"
        site_height     "0.810"
        site_width      "0.114"
        track_pitch     "0.090"
        stdcell_prefix  "GF22FDX_SC9T"
        site_name       "GF22FDX_SC9T"
        filler_cells    "GF22FDX_SC9T_SVT_FILL1 GF22FDX_SC9T_SVT_FILL2 GF22FDX_SC9T_SVT_FILL4 GF22FDX_SC9T_SVT_FILL8 GF22FDX_SC9T_SVT_FILL16 GF22FDX_SC9T_SVT_FILL32"
        well_tap        "GF22FDX_SC9T_SVT_FILLTIE1"
        description     "GF 22FDX 9-Track High Performance"
    }
    "7.5T" {
        cell_height     "0.675"
        site_height     "0.675"
        site_width      "0.116"
        track_pitch     "0.090"
        stdcell_prefix  "GF22FDX_SC7P5T"
        site_name       "GF22FDX_SC7P5T"
        filler_cells    "GF22FDX_SC7P5T_SVT_FILL1 GF22FDX_SC7P5T_SVT_FILL2 GF22FDX_SC7P5T_SVT_FILL4 GF22FDX_SC7P5T_SVT_FILL8"
        well_tap        "GF22FDX_SC7P5T_SVT_FILLTIE1"
        description     "GF 22FDX 7.5-Track Ultra Low Power"
    }
    "8T" {
        cell_height     "0.720"
        site_height     "0.720"
        site_width      "0.114"
        track_pitch     "0.090"
        stdcell_prefix  "GF22FDX_SC8T"
        site_name       "GF22FDX_SC8T"
        filler_cells    "GF22FDX_SC8T_SVT_FILL1 GF22FDX_SC8T_SVT_FILL2 GF22FDX_SC8T_SVT_FILL4 GF22FDX_SC8T_SVT_FILL8"
        well_tap        "GF22FDX_SC8T_SVT_FILLTIE1"
        description     "GF 22FDX 8-Track Low Power with Body Bias"
    }
}

# ── Track Resolution ──────────────────────────────────────────────────────────
proc resolve_track_variant {} {
    global tech track_variants
    set variant $tech(track,active_variant)
    if {![info exists track_variants($variant)]} {
        puts "WARNING: Track variant '$variant' not found. Using default."
        set variant $tech(track,default_variant)
        set tech(track,active_variant) $variant
    }
    array set vinfo $track_variants($variant)
    set tech(cells,height)         $vinfo(cell_height)
    set tech(cells,site)           $vinfo(site_name)
    set tech(cells,filler)         $vinfo(filler_cells)
    set tech(cells,well_tap)       $vinfo(well_tap)
    set tech(track,cell_height)    $vinfo(cell_height)
    set tech(track,stdcell_prefix) $vinfo(stdcell_prefix)
    set tech(track,description)    $vinfo(description)
    puts "INFO: Track variant: $variant ($vinfo(description))"
}

catch {resolve_track_variant}
