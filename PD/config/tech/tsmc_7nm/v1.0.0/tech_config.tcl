#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow Technology Configuration — TSMC N7 (7nm FinFET)
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
set tech(node)            "7nm"
set tech(process)         "TSMC"
set tech(variant)         "N7"
set tech(foundry)         "TSMC"
set tech(metal_stack_name) "12M"
set tech(revision)        "v1.0"

# ═══════════════════════════════════════════════════════════════════════════════
# LIBRARY PATHS
# ═══════════════════════════════════════════════════════════════════════════════
set tech(library,root_path)    "/tmp/test_libs/tsmc_7nm"
set tech(library,stdcell_path) "$tech(library,root_path)/Front_End/timing/stdcell"
set tech(library,memory_path)  "$tech(library,root_path)/Front_End/timing/memory"
set tech(library,io_path)      "$tech(library,root_path)/Front_End/timing/io"

# Cell library prefixes (TSMC N7 naming)
set _STDCELL "tcbn7ffcllbwp7t"
set _MEMORY  "ts1n7ffcllsblvtc256x64m4s"
set _IO      "tpbn7v"

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
set tech(lef,technology)      "$tech(library,root_path)/Back_End/lef/tsmc7nm_tech.lef"
set tech(lef,standard_cells)  "$tech(library,root_path)/Back_End/lef/stdcell/${_STDCELL}.lef"
set tech(lef,macros)          "$tech(library,root_path)/Back_End/lef/memory/${_MEMORY}.lef"
set tech(lef,io_pads)         "$tech(library,root_path)/Back_End/lef/io/${_IO}.lef"

# ═══════════════════════════════════════════════════════════════════════════════
# DB FILES (fallback)
# ═══════════════════════════════════════════════════════════════════════════════
set tech(db,standard_cells) "$tech(library,root_path)/Front_End/timing/stdcell/${_STDCELL}tt0p75v25c.db"
set tech(db,memory)         "$tech(library,root_path)/Front_End/timing/memory/${_MEMORY}tt0p75v25c.db"
set tech(db,io_pads)        "$tech(library,root_path)/Front_End/timing/io/${_IO}_tt0p75v25c.db"

# ═══════════════════════════════════════════════════════════════════════════════
# TLU+ PARASITIC EXTRACTION
# ═══════════════════════════════════════════════════════════════════════════════
set tech(tluplus,max) "$tech(library,root_path)/Back_End/rcx/tsmc7nm_1p12m_Cmax.tluplus"
set tech(tluplus,min) "$tech(library,root_path)/Back_End/rcx/tsmc7nm_1p12m_Cmin.tluplus"
set tech(tluplus,map) "$tech(library,root_path)/Back_End/rcx/tsmc7nm_tf_itf_tluplus.map"

# Legacy single-corner timing libs (nominal TT)
set tech(lib,timing) "$tech(library,stdcell_path)/${_STDCELL}tt0p75v25c_ccs.lib"
set tech(lib,power)  "$tech(library,stdcell_path)/${_STDCELL}tt0p75v25c_power.lib"
set tech(lib,ccs)    "$tech(library,stdcell_path)/${_STDCELL}tt0p75v25c_ccs.lib"

# ═══════════════════════════════════════════════════════════════════════════════
# LIBRARY SETS — Aligned with MMMC analysis_views lib_set_ref
# TSMC N7 nominal: 0.75V, low: 0.65V, high: 0.80V
# ═══════════════════════════════════════════════════════════════════════════════

# SS Corner — Setup Critical
set library_sets(ss_0650v_125c,description) "SS 0.65V 125C — worst setup"
set library_sets(ss_0650v_125c,corner)      "ss"
set library_sets(ss_0650v_125c,voltage)     "0.65"
set library_sets(ss_0650v_125c,temperature) "125"
set library_sets(ss_0650v_125c,timing)      "$tech(library,stdcell_path)/${_STDCELL}ss0p65v125c_ccs.lib $tech(library,memory_path)/${_MEMORY}ss0p65v125c_ccs.lib $tech(library,io_path)/${_IO}_ss0p65v125c_ccs.lib"
set library_sets(ss_0650v_125c,power)       "$tech(library,stdcell_path)/${_STDCELL}ss0p65v125c_power.lib"

set library_sets(ss_0750v_125c,description) "SS 0.75V 125C"
set library_sets(ss_0750v_125c,corner)      "ss"
set library_sets(ss_0750v_125c,voltage)     "0.75"
set library_sets(ss_0750v_125c,temperature) "125"
set library_sets(ss_0750v_125c,timing)      "$tech(library,stdcell_path)/${_STDCELL}ss0p75v125c_ccs.lib $tech(library,memory_path)/${_MEMORY}ss0p75v125c_ccs.lib $tech(library,io_path)/${_IO}_ss0p75v125c_ccs.lib"
set library_sets(ss_0750v_125c,power)       "$tech(library,stdcell_path)/${_STDCELL}ss0p75v125c_power.lib"

# TT Corner — Nominal
set library_sets(tt_0750v_25c,description)  "TT 0.75V 25C — nominal"
set library_sets(tt_0750v_25c,corner)       "tt"
set library_sets(tt_0750v_25c,voltage)      "0.75"
set library_sets(tt_0750v_25c,temperature)  "25"
set library_sets(tt_0750v_25c,timing)       "$tech(library,stdcell_path)/${_STDCELL}tt0p75v25c_ccs.lib $tech(library,memory_path)/${_MEMORY}tt0p75v25c_ccs.lib $tech(library,io_path)/${_IO}_tt0p75v25c_ccs.lib"
set library_sets(tt_0750v_25c,power)        "$tech(library,stdcell_path)/${_STDCELL}tt0p75v25c_power.lib"

# FF Corner — Hold Critical
set library_sets(ff_0800v_m40c,description) "FF 0.80V -40C — worst hold"
set library_sets(ff_0800v_m40c,corner)      "ff"
set library_sets(ff_0800v_m40c,voltage)     "0.80"
set library_sets(ff_0800v_m40c,temperature) "-40"
set library_sets(ff_0800v_m40c,timing)      "$tech(library,stdcell_path)/${_STDCELL}ff0p80vm40c_ccs.lib $tech(library,memory_path)/${_MEMORY}ff0p80vm40c_ccs.lib $tech(library,io_path)/${_IO}_ff0p80vm40c_ccs.lib"
set library_sets(ff_0800v_m40c,power)       "$tech(library,stdcell_path)/${_STDCELL}ff0p80vm40c_power.lib"

set library_sets(ff_0800v_25c,description)  "FF 0.80V 25C"
set library_sets(ff_0800v_25c,corner)       "ff"
set library_sets(ff_0800v_25c,voltage)      "0.80"
set library_sets(ff_0800v_25c,temperature)  "25"
set library_sets(ff_0800v_25c,timing)       "$tech(library,stdcell_path)/${_STDCELL}ff0p80v25c_ccs.lib $tech(library,memory_path)/${_MEMORY}ff0p80v25c_ccs.lib $tech(library,io_path)/${_IO}_ff0p80v25c_ccs.lib"
set library_sets(ff_0800v_25c,power)        "$tech(library,stdcell_path)/${_STDCELL}ff0p80v25c_power.lib"

# ═══════════════════════════════════════════════════════════════════════════════
# TECHNOLOGY SCRIPTS (alongside this file)
# ═══════════════════════════════════════════════════════════════════════════════
set tech(tech_setup_script)     "$_tech_dir/tech_setup.tcl"
set tech(lib_cell_purpose_file) "$_tech_dir/set_lib_cell_purpose.tcl"
set tech(cts_ndr_file)          "$_tech_dir/cts_ndr.tcl"
set tech(tech_file)             ""

# ═══════════════════════════════════════════════════════════════════════════════
# CELL RESTRICTIONS
# ═══════════════════════════════════════════════════════════════════════════════
# TSMC N7 7T standard cell naming: tcbn7ffcllbwp7t<VT><CELL>
set tech(dont_use_cells) {
    "*/DELLN*" "*/DEL0*" "*/ANTENNA*" "*/DCAP*X1"
}
set tech(tie_lib_cells)       "*/TIEH* */TIEL*"
set tech(hold_fix_lib_cells)  "*/BUFFD1BWP7T* */BUFFD2BWP7T* */DEL*"
set tech(cts_lib_cells)       "*/CKBD* */CKND* */CKG*"
set tech(cts_only_lib_cells)  "*/CKBD* */CKND*"

# ═══════════════════════════════════════════════════════════════════════════════
# CTS NDR CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════════
set tech(cts_ndr,root_rule)     "rm_2w2s"
set tech(cts_ndr,internal_rule) "rm_2w2s"
set tech(cts_ndr,leaf_rule)     ""
set tech(cts_ndr,min_layer)     "M3"
set tech(cts_ndr,max_layer)     "M7"
set tech(via_ladder_file)       ""

# OCV
set tech(ocv,derate_file) ""

# ═══════════════════════════════════════════════════════════════════════════════
# DESIGN RULES (TSMC N7 7T)
# ═══════════════════════════════════════════════════════════════════════════════
set tech(dr,min_width)   "0.028"
set tech(dr,min_spacing) "0.036"
set tech(dr,via_size)    "0.032"
set tech(dr,track_pitch) "0.048"
set tech(dr,m1_pitch)    "0.036"
set tech(dr,site_width)  "0.054"
set tech(dr,site_height) "0.336"

# Metal stack (TSMC N7 12M)
set tech(metal_stack) {
    {M1  horizontal 0.036}
    {M2  vertical   0.036}
    {M3  horizontal 0.048}
    {M4  vertical   0.048}
    {M5  horizontal 0.048}
    {M6  vertical   0.048}
    {M7  horizontal 0.048}
    {M8  vertical   0.048}
    {M9  horizontal 0.080}
    {M10 vertical   0.080}
    {M11 horizontal 0.720}
    {M12 vertical   0.720}
}

# Routing layer constraints
set tech(routing,min_layer)    "M2"
set tech(routing,max_layer)    "M10"
set tech(routing,clock_min)    "M3"
set tech(routing,clock_max)    "M7"
set tech(routing,power_layers) "M11 M12"

set tech(routing_layer_direction_offset) {
    {M1  horizontal 0.0}
    {M2  vertical   0.0}
    {M3  horizontal 0.0}
    {M4  vertical   0.0}
    {M5  horizontal 0.0}
    {M6  vertical   0.0}
    {M7  horizontal 0.0}
    {M8  vertical   0.0}
}
set tech(site_default)  "tsmc7t"
set tech(site_symmetry) "Y"

# ═══════════════════════════════════════════════════════════════════════════════
# STANDARD CELL NAMES (TSMC N7 7T)
# ═══════════════════════════════════════════════════════════════════════════════
set tech(cells,site)       "tsmc7t"
set tech(cells,height)     "0.336"
set tech(cells,min_width)  "0.054"
set tech(cells,power_pins) "VDD VSS"

# Physical cells
set tech(cells,well_tap)   "TAPCELLBWP7T"
set tech(cells,tie_high)   "TIEHBWP7T"
set tech(cells,tie_low)    "TIELBWP7T"
set tech(cells,filler)     "FILL1BWP7T FILL2BWP7T FILL3BWP7T FILL4BWP7T FILL8BWP7T FILL16BWP7T FILL32BWP7T FILL64BWP7T"
set tech(cells,decap)      "DCAP4BWP7T DCAP8BWP7T DCAP16BWP7T"
set tech(cells,endcap)     "ENDCAPBWP7T"
set tech(cells,antenna)    "ANTENNABWP7T"

# Logic cells
set tech(cells,buf)        "BUFFD1BWP7T BUFFD2BWP7T BUFFD4BWP7T BUFFD8BWP7T BUFFD16BWP7T"
set tech(cells,inv)        "INVD1BWP7T INVD2BWP7T INVD4BWP7T INVD8BWP7T"
set tech(cells,delay)      "DEL1BWP7T DEL2BWP7T DEL4BWP7T"

# Clock cells
set tech(cells,clk_buf)    "CKBD2BWP7T CKBD4BWP7T CKBD8BWP7T CKBD12BWP7T CKBD16BWP7T CKBD20BWP7T"
set tech(cells,clk_inv)    "CKND2BWP7T CKND4BWP7T CKND8BWP7T CKND12BWP7T CKND16BWP7T"
set tech(cells,icg)        "CKLNQD1BWP7T CKLNQD2BWP7T CKLNQD4BWP7T"
set tech(cells,clk_gate)   "CKLHQD1BWP7T CKLHQD2BWP7T"

# Voltage threshold variants
set tech(vt_types)   "ULVT LVT SVT HVT"
set tech(vt_default) "SVT"

# ═══════════════════════════════════════════════════════════════════════════════
# MULTI-TRACK LIBRARY SUPPORT
# ═══════════════════════════════════════════════════════════════════════════════
set tech(track,available_variants) {7T 7.5T 6T}
set tech(track,default_variant)    "7T"

if {![info exists tech(track,active_variant)]} {
    set tech(track,active_variant) $tech(track,default_variant)
}

array set track_variants {
    "7T" {
        cell_height     "0.336"
        site_height     "0.336"
        site_width      "0.054"
        track_pitch     "0.048"
        stdcell_prefix  "tcbn7ffcllbwp7t"
        site_name       "tsmc7t"
        filler_cells    "FILL1BWP7T FILL2BWP7T FILL3BWP7T FILL4BWP7T FILL8BWP7T FILL16BWP7T FILL32BWP7T FILL64BWP7T"
        well_tap        "TAPCELLBWP7T"
        description     "TSMC N7 7-Track Standard Performance"
    }
    "7.5T" {
        cell_height     "0.360"
        site_height     "0.360"
        site_width      "0.054"
        track_pitch     "0.048"
        stdcell_prefix  "tcbn7ffcllbwp7p5t"
        site_name       "tsmc7p5t"
        filler_cells    "FILL1BWP7P5T FILL2BWP7P5T FILL4BWP7P5T FILL8BWP7P5T FILL16BWP7P5T"
        well_tap        "TAPCELLBWP7P5T"
        description     "TSMC N7 7.5-Track High Density"
    }
    "6T" {
        cell_height     "0.288"
        site_height     "0.288"
        site_width      "0.054"
        track_pitch     "0.048"
        stdcell_prefix  "tcbn7ffcllbwp6t"
        site_name       "tsmc6t"
        filler_cells    "FILL1BWP6T FILL2BWP6T FILL4BWP6T FILL8BWP6T"
        well_tap        "TAPCELLBWP6T"
        description     "TSMC N7 6-Track Ultra High Density"
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
