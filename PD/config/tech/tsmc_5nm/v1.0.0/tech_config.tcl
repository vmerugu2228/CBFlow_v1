#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow Technology Configuration — TSMC N5 (5nm FinFET)
# ═══════════════════════════════════════════════════════════════════════════════

# ── Path Resolution ───────────────────────────────────────────────────────────
set _tech_dir [file dirname [file normalize [info script]]]

if {[info exists ::env(FLOW_DIR)]} {
    set project_root_resolved $::env(FLOW_DIR)
} elseif {[info exists ::env(CBFLOW_CORE_DIR)]} {
    set project_root_resolved $::env(CBFLOW_CORE_DIR)
} else {
    puts "ERROR: FLOW_DIR or CBFLOW_CORE_DIR not set. Source your cbflow environment first."
}

# ── Technology Info ───────────────────────────────────────────────────────────
set tech(node)            "5nm"
set tech(process)         "TSMC"
set tech(variant)         "N5"
set tech(foundry)         "TSMC"
set tech(metal_stack_name) "13M"
set tech(revision)        "v1.0"

# ═══════════════════════════════════════════════════════════════════════════════
# LIBRARY PATHS
# ═══════════════════════════════════════════════════════════════════════════════
set tech(library,root_path)    "/tmp/test_libs/tsmc_5nm"
set tech(library,stdcell_path) "$tech(library,root_path)/Front_End/timing/stdcell"
set tech(library,memory_path)  "$tech(library,root_path)/Front_End/timing/memory"
set tech(library,io_path)      "$tech(library,root_path)/Front_End/timing/io"

# Cell library prefixes (TSMC N5 naming)
set _STDCELL "tcbn5ffcllbwp5t"
set _MEMORY  "ts1n5ffcllsblvtc256x64m4s"
set _IO      "tpbn5v"

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
# LEF FILES
# ═══════════════════════════════════════════════════════════════════════════════
set tech(lef,technology)      "$tech(library,root_path)/Back_End/lef/tsmc5nm_tech.lef"
set tech(lef,standard_cells)  "$tech(library,root_path)/Back_End/lef/stdcell/${_STDCELL}.lef"
set tech(lef,macros)          "$tech(library,root_path)/Back_End/lef/memory/${_MEMORY}.lef"
set tech(lef,io_pads)         "$tech(library,root_path)/Back_End/lef/io/${_IO}.lef"

# ═══════════════════════════════════════════════════════════════════════════════
# DB FILES (fallback)
# ═══════════════════════════════════════════════════════════════════════════════
set tech(db,standard_cells) "$tech(library,root_path)/Front_End/timing/stdcell/${_STDCELL}tt0p70v25c.db"
set tech(db,memory)         "$tech(library,root_path)/Front_End/timing/memory/${_MEMORY}tt0p70v25c.db"
set tech(db,io_pads)        "$tech(library,root_path)/Front_End/timing/io/${_IO}_tt0p70v25c.db"

# ═══════════════════════════════════════════════════════════════════════════════
# TLU+ PARASITIC EXTRACTION
# ═══════════════════════════════════════════════════════════════════════════════
set tech(tluplus,max) "$tech(library,root_path)/Back_End/rcx/tsmc5nm_1p13m_Cmax.tluplus"
set tech(tluplus,min) "$tech(library,root_path)/Back_End/rcx/tsmc5nm_1p13m_Cmin.tluplus"
set tech(tluplus,map) "$tech(library,root_path)/Back_End/rcx/tsmc5nm_tf_itf_tluplus.map"

# Legacy single-corner timing libs (nominal TT)
set tech(lib,timing) "$tech(library,stdcell_path)/${_STDCELL}tt0p70v25c_ccs.lib"
set tech(lib,power)  "$tech(library,stdcell_path)/${_STDCELL}tt0p70v25c_power.lib"
set tech(lib,ccs)    "$tech(library,stdcell_path)/${_STDCELL}tt0p70v25c_ccs.lib"

# ═══════════════════════════════════════════════════════════════════════════════
# LIBRARY SETS — Aligned with MMMC analysis_views lib_set_ref
# TSMC N5 nominal: 0.70V, low: 0.60V, high: 0.75V
# ═══════════════════════════════════════════════════════════════════════════════

# SS Corner — Setup Critical
set library_sets(ss_0600v_125c,description) "SS 0.60V 125C — worst setup"
set library_sets(ss_0600v_125c,corner)      "ss"
set library_sets(ss_0600v_125c,voltage)     "0.60"
set library_sets(ss_0600v_125c,temperature) "125"
set library_sets(ss_0600v_125c,timing)      "$tech(library,stdcell_path)/${_STDCELL}ss0p60v125c_ccs.lib $tech(library,memory_path)/${_MEMORY}ss0p60v125c_ccs.lib $tech(library,io_path)/${_IO}_ss0p60v125c_ccs.lib"
set library_sets(ss_0600v_125c,power)       "$tech(library,stdcell_path)/${_STDCELL}ss0p60v125c_power.lib"

set library_sets(ss_0600v_m40c,description) "SS 0.60V -40C"
set library_sets(ss_0600v_m40c,corner)      "ss"
set library_sets(ss_0600v_m40c,voltage)     "0.60"
set library_sets(ss_0600v_m40c,temperature) "-40"
set library_sets(ss_0600v_m40c,timing)      "$tech(library,stdcell_path)/${_STDCELL}ss0p60vm40c_ccs.lib $tech(library,memory_path)/${_MEMORY}ss0p60vm40c_ccs.lib $tech(library,io_path)/${_IO}_ss0p60vm40c_ccs.lib"
set library_sets(ss_0600v_m40c,power)       "$tech(library,stdcell_path)/${_STDCELL}ss0p60vm40c_power.lib"

set library_sets(ss_0700v_125c,description) "SS 0.70V 125C"
set library_sets(ss_0700v_125c,corner)      "ss"
set library_sets(ss_0700v_125c,voltage)     "0.70"
set library_sets(ss_0700v_125c,temperature) "125"
set library_sets(ss_0700v_125c,timing)      "$tech(library,stdcell_path)/${_STDCELL}ss0p70v125c_ccs.lib $tech(library,memory_path)/${_MEMORY}ss0p70v125c_ccs.lib $tech(library,io_path)/${_IO}_ss0p70v125c_ccs.lib"
set library_sets(ss_0700v_125c,power)       "$tech(library,stdcell_path)/${_STDCELL}ss0p70v125c_power.lib"

set library_sets(ss_0700v_m40c,description) "SS 0.70V -40C"
set library_sets(ss_0700v_m40c,corner)      "ss"
set library_sets(ss_0700v_m40c,voltage)     "0.70"
set library_sets(ss_0700v_m40c,temperature) "-40"
set library_sets(ss_0700v_m40c,timing)      "$tech(library,stdcell_path)/${_STDCELL}ss0p70vm40c_ccs.lib $tech(library,memory_path)/${_MEMORY}ss0p70vm40c_ccs.lib $tech(library,io_path)/${_IO}_ss0p70vm40c_ccs.lib"
set library_sets(ss_0700v_m40c,power)       "$tech(library,stdcell_path)/${_STDCELL}ss0p70vm40c_power.lib"

# TT Corner — Nominal
set library_sets(tt_0700v_25c,description)  "TT 0.70V 25C — nominal"
set library_sets(tt_0700v_25c,corner)       "tt"
set library_sets(tt_0700v_25c,voltage)      "0.70"
set library_sets(tt_0700v_25c,temperature)  "25"
set library_sets(tt_0700v_25c,timing)       "$tech(library,stdcell_path)/${_STDCELL}tt0p70v25c_ccs.lib $tech(library,memory_path)/${_MEMORY}tt0p70v25c_ccs.lib $tech(library,io_path)/${_IO}_tt0p70v25c_ccs.lib"
set library_sets(tt_0700v_25c,power)        "$tech(library,stdcell_path)/${_STDCELL}tt0p70v25c_power.lib"

set library_sets(tt_0700v_125c,description) "TT 0.70V 125C — nominal hot"
set library_sets(tt_0700v_125c,corner)      "tt"
set library_sets(tt_0700v_125c,voltage)     "0.70"
set library_sets(tt_0700v_125c,temperature) "125"
set library_sets(tt_0700v_125c,timing)      "$tech(library,stdcell_path)/${_STDCELL}tt0p70v125c_ccs.lib $tech(library,memory_path)/${_MEMORY}tt0p70v125c_ccs.lib $tech(library,io_path)/${_IO}_tt0p70v125c_ccs.lib"
set library_sets(tt_0700v_125c,power)       "$tech(library,stdcell_path)/${_STDCELL}tt0p70v125c_power.lib"

set library_sets(tt_0700v_m40c,description) "TT 0.70V -40C — nominal cold"
set library_sets(tt_0700v_m40c,corner)      "tt"
set library_sets(tt_0700v_m40c,voltage)     "0.70"
set library_sets(tt_0700v_m40c,temperature) "-40"
set library_sets(tt_0700v_m40c,timing)      "$tech(library,stdcell_path)/${_STDCELL}tt0p70vm40c_ccs.lib $tech(library,memory_path)/${_MEMORY}tt0p70vm40c_ccs.lib $tech(library,io_path)/${_IO}_tt0p70vm40c_ccs.lib"
set library_sets(tt_0700v_m40c,power)       "$tech(library,stdcell_path)/${_STDCELL}tt0p70vm40c_power.lib"

# FF Corner — Hold Critical
set library_sets(ff_0750v_m40c,description) "FF 0.75V -40C — worst hold"
set library_sets(ff_0750v_m40c,corner)      "ff"
set library_sets(ff_0750v_m40c,voltage)     "0.75"
set library_sets(ff_0750v_m40c,temperature) "-40"
set library_sets(ff_0750v_m40c,timing)      "$tech(library,stdcell_path)/${_STDCELL}ff0p75vm40c_ccs.lib $tech(library,memory_path)/${_MEMORY}ff0p75vm40c_ccs.lib $tech(library,io_path)/${_IO}_ff0p75vm40c_ccs.lib"
set library_sets(ff_0750v_m40c,power)       "$tech(library,stdcell_path)/${_STDCELL}ff0p75vm40c_power.lib"

set library_sets(ff_0750v_25c,description)  "FF 0.75V 25C"
set library_sets(ff_0750v_25c,corner)       "ff"
set library_sets(ff_0750v_25c,voltage)      "0.75"
set library_sets(ff_0750v_25c,temperature)  "25"
set library_sets(ff_0750v_25c,timing)       "$tech(library,stdcell_path)/${_STDCELL}ff0p75v25c_ccs.lib $tech(library,memory_path)/${_MEMORY}ff0p75v25c_ccs.lib $tech(library,io_path)/${_IO}_ff0p75v25c_ccs.lib"
set library_sets(ff_0750v_25c,power)        "$tech(library,stdcell_path)/${_STDCELL}ff0p75v25c_power.lib"

set library_sets(ff_0750v_125c,description) "FF 0.75V 125C"
set library_sets(ff_0750v_125c,corner)      "ff"
set library_sets(ff_0750v_125c,voltage)     "0.75"
set library_sets(ff_0750v_125c,temperature) "125"
set library_sets(ff_0750v_125c,timing)      "$tech(library,stdcell_path)/${_STDCELL}ff0p75v125c_ccs.lib $tech(library,memory_path)/${_MEMORY}ff0p75v125c_ccs.lib $tech(library,io_path)/${_IO}_ff0p75v125c_ccs.lib"
set library_sets(ff_0750v_125c,power)       "$tech(library,stdcell_path)/${_STDCELL}ff0p75v125c_power.lib"

# ═══════════════════════════════════════════════════════════════════════════════
# TECHNOLOGY SCRIPTS (alongside this file if they exist)
# ═══════════════════════════════════════════════════════════════════════════════
set tech(tech_setup_script)     "$_tech_dir/tech_setup.tcl"
set tech(lib_cell_purpose_file) "$_tech_dir/set_lib_cell_purpose.tcl"
set tech(cts_ndr_file)          "$_tech_dir/cts_ndr.tcl"
set tech(tech_file)             ""

# ═══════════════════════════════════════════════════════════════════════════════
# CELL RESTRICTIONS
# ═══════════════════════════════════════════════════════════════════════════════
# TSMC N5 5T standard cell naming: tcbn5ffcllbwp5t<VT><CELL>
set tech(dont_use_cells) {
    "*/DELLN*" "*/DEL0*" "*/ANTENNA*" "*/DCAP*X1"
}
set tech(tie_lib_cells)       "*/TIEH* */TIEL*"
set tech(hold_fix_lib_cells)  "*/BUFFD1BWP5T* */BUFFD2BWP5T* */DEL*"
set tech(cts_lib_cells)       "*/CKBD* */CKND* */CKG*"
set tech(cts_only_lib_cells)  "*/CKBD* */CKND*"

# ═══════════════════════════════════════════════════════════════════════════════
# CTS NDR CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════════
set tech(cts_ndr,root_rule)     "rm_2w2s"
set tech(cts_ndr,internal_rule) "rm_2w2s"
set tech(cts_ndr,leaf_rule)     ""
set tech(cts_ndr,min_layer)     "M4"
set tech(cts_ndr,max_layer)     "M8"
set tech(via_ladder_file)       ""

# OCV
set tech(ocv,derate_file) ""

# ═══════════════════════════════════════════════════════════════════════════════
# DESIGN RULES (TSMC N5 5T)
# ═══════════════════════════════════════════════════════════════════════════════
set tech(dr,min_width)   "0.022"
set tech(dr,min_spacing) "0.026"
set tech(dr,via_size)    "0.026"
set tech(dr,track_pitch) "0.028"
set tech(dr,m1_pitch)    "0.028"
set tech(dr,site_width)  "0.051"
set tech(dr,site_height) "0.140"

# Metal stack (TSMC N5 13M: 1P13M_2Xa1Xb1Xc1Xe1Ya1Yb5Y2Yy2R)
set tech(metal_stack) {
    {M1  horizontal 0.028}
    {M2  vertical   0.028}
    {M3  horizontal 0.028}
    {M4  vertical   0.028}
    {M5  horizontal 0.036}
    {M6  vertical   0.036}
    {M7  horizontal 0.036}
    {M8  vertical   0.036}
    {M9  horizontal 0.048}
    {M10 vertical   0.048}
    {M11 horizontal 0.080}
    {M12 vertical   0.720}
    {M13 horizontal 0.720}
}

# Routing layer constraints
set tech(routing,min_layer)    "M2"
set tech(routing,max_layer)    "M11"
set tech(routing,clock_min)    "M4"
set tech(routing,clock_max)    "M8"
set tech(routing,power_layers) "M12 M13"

set tech(routing_layer_direction_offset) {
    {M1  horizontal 0.0}
    {M2  vertical   0.0}
    {M3  horizontal 0.0}
    {M4  vertical   0.0}
    {M5  horizontal 0.0}
    {M6  vertical   0.0}
    {M7  horizontal 0.0}
    {M8  vertical   0.0}
    {M9  horizontal 0.0}
    {M10 vertical   0.0}
}
set tech(site_default)  "tsmc5t"
set tech(site_symmetry) "Y"

# ═══════════════════════════════════════════════════════════════════════════════
# STANDARD CELL NAMES (TSMC N5 5T)
# ═══════════════════════════════════════════════════════════════════════════════
set tech(cells,site)       "tsmc5t"
set tech(cells,height)     "0.140"
set tech(cells,min_width)  "0.051"
set tech(cells,power_pins) "VDD VSS"

# Physical cells
set tech(cells,well_tap)   "TAPCELLBWP5T"
set tech(cells,tie_high)   "TIEHBWP5T"
set tech(cells,tie_low)    "TIELBWP5T"
set tech(cells,filler)     "FILL1BWP5T FILL2BWP5T FILL3BWP5T FILL4BWP5T FILL8BWP5T FILL16BWP5T FILL32BWP5T FILL64BWP5T"
set tech(cells,decap)      "DCAP4BWP5T DCAP8BWP5T DCAP16BWP5T DCAP32BWP5T"
set tech(cells,endcap)     "ENDCAPBWP5T"
set tech(cells,antenna)    "ANTENNABWP5T"

# Logic cells
set tech(cells,buf)        "BUFFD1BWP5T BUFFD2BWP5T BUFFD4BWP5T BUFFD8BWP5T BUFFD12BWP5T BUFFD16BWP5T BUFFD20BWP5T"
set tech(cells,inv)        "INVD1BWP5T INVD2BWP5T INVD4BWP5T INVD8BWP5T INVD12BWP5T INVD16BWP5T"
set tech(cells,delay)      "DEL025BWP5T DEL050BWP5T DEL100BWP5T DEL200BWP5T"

# Clock cells
set tech(cells,clk_buf)    "CKBD2BWP5T CKBD4BWP5T CKBD8BWP5T CKBD12BWP5T CKBD16BWP5T CKBD20BWP5T CKBD24BWP5T"
set tech(cells,clk_inv)    "CKND2BWP5T CKND4BWP5T CKND8BWP5T CKND12BWP5T CKND16BWP5T CKND20BWP5T"
set tech(cells,icg)        "CKLNQD1BWP5T CKLNQD2BWP5T CKLNQD4BWP5T CKLNQD8BWP5T"
set tech(cells,clk_gate)   "CKLHQD1BWP5T CKLHQD2BWP5T CKLHQD4BWP5T"

# Voltage threshold variants
set tech(vt_types)   "ULVT LVT SVT HVT UHVT"
set tech(vt_default) "SVT"

# ═══════════════════════════════════════════════════════════════════════════════
# MULTI-TRACK LIBRARY SUPPORT
# ═══════════════════════════════════════════════════════════════════════════════
set tech(track,available_variants) {5T 6T 7T}
set tech(track,default_variant)    "5T"

if {![info exists tech(track,active_variant)]} {
    set tech(track,active_variant) $tech(track,default_variant)
}

array set track_variants {
    "5T" {
        cell_height     "0.140"
        site_height     "0.140"
        site_width      "0.051"
        track_pitch     "0.028"
        stdcell_prefix  "tcbn5ffcllbwp5t"
        site_name       "tsmc5t"
        filler_cells    "FILL1BWP5T FILL2BWP5T FILL3BWP5T FILL4BWP5T FILL8BWP5T FILL16BWP5T FILL32BWP5T FILL64BWP5T"
        well_tap        "TAPCELLBWP5T"
        description     "TSMC N5 5-Track Ultra High Density"
    }
    "6T" {
        cell_height     "0.168"
        site_height     "0.168"
        site_width      "0.051"
        track_pitch     "0.028"
        stdcell_prefix  "tcbn5ffcllbwp6t"
        site_name       "tsmc5n6t"
        filler_cells    "FILL1BWP6T5 FILL2BWP6T5 FILL4BWP6T5 FILL8BWP6T5 FILL16BWP6T5"
        well_tap        "TAPCELLBWP6T5"
        description     "TSMC N5 6-Track High Density"
    }
    "7T" {
        cell_height     "0.196"
        site_height     "0.196"
        site_width      "0.051"
        track_pitch     "0.028"
        stdcell_prefix  "tcbn5ffcllbwp7t"
        site_name       "tsmc5n7t"
        filler_cells    "FILL1BWP7T5 FILL2BWP7T5 FILL4BWP7T5 FILL8BWP7T5 FILL16BWP7T5"
        well_tap        "TAPCELLBWP7T5"
        description     "TSMC N5 7-Track Standard Performance"
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
