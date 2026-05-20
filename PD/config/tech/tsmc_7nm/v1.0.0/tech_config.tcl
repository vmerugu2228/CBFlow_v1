#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow Technology Configuration — TSMC N7 (7nm FinFET)
# ALL track heights (6T, 7.5T, 9T) in ONE file — flow picks via tech(track)
# ═══════════════════════════════════════════════════════════════════════════════

set _tech_dir [file dirname [file normalize [info script]]]

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 1: TECHNOLOGY IDENTITY
# ═══════════════════════════════════════════════════════════════════════════════

set tech(node)        "7nm"
set tech(process)     "TSMC N7"
set tech(foundry)     "TSMC"
set tech(metal_stack) "12M"
set tech(tracks_available) "6T 7.5T 9T"

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 2: ACTIVE TRACK RESOLUTION
# ═══════════════════════════════════════════════════════════════════════════════

set tech(track) "7.5T"
if {[info exists flow(track_variant)] && $flow(track_variant) ne ""} {
    set tech(track) $flow(track_variant)
} elseif {[info exists project(track_variant)] && $project(track_variant) ne ""} {
    set tech(track) $project(track_variant)
} elseif {[info exists ::env(CBFLOW_TRACK_VARIANT)] && $::env(CBFLOW_TRACK_VARIANT) ne ""} {
    set tech(track) $::env(CBFLOW_TRACK_VARIANT)
}
puts "INFO: TSMC N7 active track: $tech(track)"

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 3: LIBRARY ROOT PATHS
# ═══════════════════════════════════════════════════════════════════════════════

set tech(lib_root) "/tmp/test_libs/tsmc_7nm"
set _R "$tech(lib_root)"

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 4: NDM LIBRARIES (per track)
# ═══════════════════════════════════════════════════════════════════════════════

set tech(6T,ndm) [list \
    "$_R/Back_End/ndm/tcbn07bwp6tsvt.ndm" \
    "$_R/Back_End/ndm/tcbn07bwp6tlvt.ndm" \
    "$_R/Back_End/ndm/tcbn07bwp6tulvt.ndm" \
    "$_R/Back_End/ndm/tcbn07bwp6thvt.ndm" \
    "$_R/Back_End/ndm/ts1n07_memory.ndm" \
    "$_R/Back_End/ndm/tpbn07v_io.ndm" \
]

set tech(7.5T,ndm) [list \
    "$_R/Back_End/ndm/tcbn07bwp7p5tsvt.ndm" \
    "$_R/Back_End/ndm/tcbn07bwp7p5tlvt.ndm" \
    "$_R/Back_End/ndm/tcbn07bwp7p5tulvt.ndm" \
    "$_R/Back_End/ndm/tcbn07bwp7p5thvt.ndm" \
    "$_R/Back_End/ndm/ts1n07_memory.ndm" \
    "$_R/Back_End/ndm/tpbn07v_io.ndm" \
]

set tech(9T,ndm) [list \
    "$_R/Back_End/ndm/tcbn07bwp9tsvt.ndm" \
    "$_R/Back_End/ndm/tcbn07bwp9tlvt.ndm" \
    "$_R/Back_End/ndm/tcbn07bwp9tulvt.ndm" \
    "$_R/Back_End/ndm/tcbn07bwp9thvt.ndm" \
    "$_R/Back_End/ndm/ts1n07_memory.ndm" \
    "$_R/Back_End/ndm/tpbn07v_io.ndm" \
]

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 4b: DB FILES (per track — for Synopsys DC/Genus)
# ═══════════════════════════════════════════════════════════════════════════════

set tech(6T,db) [list \
    "$_R/Front_End/timing/stdcell/tcbn07bwp6tsvttt0p80v25c.db" \
    "$_R/Front_End/timing/stdcell/tcbn07bwp6tlvttt0p80v25c.db" \
    "$_R/Front_End/timing/stdcell/tcbn07bwp6tulvttt0p80v25c.db" \
    "$_R/Front_End/timing/stdcell/tcbn07bwp6thvttt0p80v25c.db" \
    "$_R/Front_End/timing/memory/ts1n07tt0p80v25c.db" \
    "$_R/Front_End/timing/io/tpbn07v_tt0p80v25c.db" \
]

set tech(7.5T,db) [list \
    "$_R/Front_End/timing/stdcell/tcbn07bwp7p5tsvttt0p80v25c.db" \
    "$_R/Front_End/timing/stdcell/tcbn07bwp7p5tlvttt0p80v25c.db" \
    "$_R/Front_End/timing/stdcell/tcbn07bwp7p5tulvttt0p80v25c.db" \
    "$_R/Front_End/timing/stdcell/tcbn07bwp7p5thvttt0p80v25c.db" \
    "$_R/Front_End/timing/memory/ts1n07tt0p80v25c.db" \
    "$_R/Front_End/timing/io/tpbn07v_tt0p80v25c.db" \
]

set tech(9T,db) [list \
    "$_R/Front_End/timing/stdcell/tcbn07bwp9tsvttt0p80v25c.db" \
    "$_R/Front_End/timing/stdcell/tcbn07bwp9tlvttt0p80v25c.db" \
    "$_R/Front_End/timing/stdcell/tcbn07bwp9tulvttt0p80v25c.db" \
    "$_R/Front_End/timing/stdcell/tcbn07bwp9thvttt0p80v25c.db" \
    "$_R/Front_End/timing/memory/ts1n07tt0p80v25c.db" \
    "$_R/Front_End/timing/io/tpbn07v_tt0p80v25c.db" \
]

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 4c: NOMINAL .LIB FILES (per track — for Cadence Innovus/Tempus)
# ═══════════════════════════════════════════════════════════════════════════════

set tech(6T,lib_nom) [list \
    "$_R/Front_End/timing/stdcell/tcbn07bwp6tsvttt0p80v25c_ccs.lib" \
    "$_R/Front_End/timing/stdcell/tcbn07bwp6tlvttt0p80v25c_ccs.lib" \
    "$_R/Front_End/timing/stdcell/tcbn07bwp6tulvttt0p80v25c_ccs.lib" \
    "$_R/Front_End/timing/stdcell/tcbn07bwp6thvttt0p80v25c_ccs.lib" \
    "$_R/Front_End/timing/memory/ts1n07tt0p80v25c.lib" \
    "$_R/Front_End/timing/io/tpbn07v_tt0p80v25c.lib" \
]

set tech(7.5T,lib_nom) [list \
    "$_R/Front_End/timing/stdcell/tcbn07bwp7p5tsvttt0p80v25c_ccs.lib" \
    "$_R/Front_End/timing/stdcell/tcbn07bwp7p5tlvttt0p80v25c_ccs.lib" \
    "$_R/Front_End/timing/stdcell/tcbn07bwp7p5tulvttt0p80v25c_ccs.lib" \
    "$_R/Front_End/timing/stdcell/tcbn07bwp7p5thvttt0p80v25c_ccs.lib" \
    "$_R/Front_End/timing/memory/ts1n07tt0p80v25c.lib" \
    "$_R/Front_End/timing/io/tpbn07v_tt0p80v25c.lib" \
]

set tech(9T,lib_nom) [list \
    "$_R/Front_End/timing/stdcell/tcbn07bwp9tsvttt0p80v25c_ccs.lib" \
    "$_R/Front_End/timing/stdcell/tcbn07bwp9tlvttt0p80v25c_ccs.lib" \
    "$_R/Front_End/timing/stdcell/tcbn07bwp9tulvttt0p80v25c_ccs.lib" \
    "$_R/Front_End/timing/stdcell/tcbn07bwp9thvttt0p80v25c_ccs.lib" \
    "$_R/Front_End/timing/memory/ts1n07tt0p80v25c.lib" \
    "$_R/Front_End/timing/io/tpbn07v_tt0p80v25c.lib" \
]

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 5: LEF FILES (per track)
# ═══════════════════════════════════════════════════════════════════════════════

set tech(lef_tech) "$_R/Back_End/lef/tsmc7nm_tech.lef"

set tech(6T,lef) [list \
    "$_R/Back_End/lef/tcbn07bwp6tsvt.lef" \
    "$_R/Back_End/lef/tcbn07bwp6tlvt.lef" \
    "$_R/Back_End/lef/tcbn07bwp6tulvt.lef" \
    "$_R/Back_End/lef/tcbn07bwp6thvt.lef" \
    "$_R/Back_End/lef/ts1n07_memory.lef" \
    "$_R/Back_End/lef/tpbn07v_io.lef" \
]

set tech(7.5T,lef) [list \
    "$_R/Back_End/lef/tcbn07bwp7p5tsvt.lef" \
    "$_R/Back_End/lef/tcbn07bwp7p5tlvt.lef" \
    "$_R/Back_End/lef/tcbn07bwp7p5tulvt.lef" \
    "$_R/Back_End/lef/tcbn07bwp7p5thvt.lef" \
    "$_R/Back_End/lef/ts1n07_memory.lef" \
    "$_R/Back_End/lef/tpbn07v_io.lef" \
]

set tech(9T,lef) [list \
    "$_R/Back_End/lef/tcbn07bwp9tsvt.lef" \
    "$_R/Back_End/lef/tcbn07bwp9tlvt.lef" \
    "$_R/Back_End/lef/tcbn07bwp9tulvt.lef" \
    "$_R/Back_End/lef/tcbn07bwp9thvt.lef" \
    "$_R/Back_End/lef/ts1n07_memory.lef" \
    "$_R/Back_End/lef/tpbn07v_io.lef" \
]

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 6: PARASITIC EXTRACTION (shared)
# ═══════════════════════════════════════════════════════════════════════════════

set tech(tluplus_max) "$_R/Back_End/rcx/tsmc7nm_1p12m_Cmax.tluplus"
set tech(tluplus_min) "$_R/Back_End/rcx/tsmc7nm_1p12m_Cmin.tluplus"
set tech(tluplus_map) "$_R/Back_End/rcx/tsmc7nm_tf_itf_tluplus.map"

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 7: PHYSICAL CELLS (per track)
# ═══════════════════════════════════════════════════════════════════════════════

set tech(6T,site)        "TSMC_N7_SC6T"
set tech(6T,cell_height) "0.270"
set tech(6T,site_width)  "0.054"
set tech(6T,fillers)     "TSMC_N7_SC6T_FILL1 TSMC_N7_SC6T_FILL2 TSMC_N7_SC6T_FILL4 TSMC_N7_SC6T_FILL8"
set tech(6T,well_tap)    "TSMC_N7_SC6T_FILLTIE1"
set tech(6T,endcap)      "TSMC_N7_SC6T_ENDCAP1"
set tech(6T,decap)       "TSMC_N7_SC6T_DCAP4 TSMC_N7_SC6T_DCAP8"
set tech(6T,cts_cells)   "tcbn07bwp6tsvt_CKBUF4 tcbn07bwp6tsvt_CKBUF8 tcbn07bwp6tsvt_CKINV4"
set tech(6T,dont_use)    "*D0BWP6T* *OPTHOLD* *DEL*"

set tech(7.5T,site)        "TSMC_N7_SC7P5T"
set tech(7.5T,cell_height) "0.338"
set tech(7.5T,site_width)  "0.054"
set tech(7.5T,fillers)     "TSMC_N7_SC7P5T_FILL1 TSMC_N7_SC7P5T_FILL2 TSMC_N7_SC7P5T_FILL4 TSMC_N7_SC7P5T_FILL8"
set tech(7.5T,well_tap)    "TSMC_N7_SC7P5T_FILLTIE1"
set tech(7.5T,endcap)      "TSMC_N7_SC7P5T_ENDCAP1"
set tech(7.5T,decap)       "TSMC_N7_SC7P5T_DCAP4 TSMC_N7_SC7P5T_DCAP8"
set tech(7.5T,cts_cells)   "tcbn07bwp7p5tsvt_CKBUF4 tcbn07bwp7p5tsvt_CKBUF8 tcbn07bwp7p5tsvt_CKINV4"
set tech(7.5T,dont_use)    "*D0BWP7P5T* *OPTHOLD* *DEL*"

set tech(9T,site)        "TSMC_N7_SC9T"
set tech(9T,cell_height) "0.405"
set tech(9T,site_width)  "0.054"
set tech(9T,fillers)     "TSMC_N7_SC9T_FILL1 TSMC_N7_SC9T_FILL2 TSMC_N7_SC9T_FILL4 TSMC_N7_SC9T_FILL8 TSMC_N7_SC9T_FILL16"
set tech(9T,well_tap)    "TSMC_N7_SC9T_FILLTIE1"
set tech(9T,endcap)      "TSMC_N7_SC9T_ENDCAP1"
set tech(9T,decap)       "TSMC_N7_SC9T_DCAP4 TSMC_N7_SC9T_DCAP8"
set tech(9T,cts_cells)   "tcbn07bwp9tsvt_CKBUF4 tcbn07bwp9tsvt_CKBUF8 tcbn07bwp9tsvt_CKINV4"
set tech(9T,dont_use)    "*D0BWP9T* *OPTHOLD* *DEL*"

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 8: LIBRARY SETS — 7.5T (default track, representative corners)
# ═══════════════════════════════════════════════════════════════════════════════

set _T "$_R/Front_End/timing"

# SS corners
set tech(7.5T,lib,ss_0p72v_125c,timing) [list \
    "$_T/stdcell/tcbn07bwp7p5tsvtss0p72v125c_ccs.lib" \
    "$_T/stdcell/tcbn07bwp7p5tlvtss0p72v125c_ccs.lib" \
    "$_T/stdcell/tcbn07bwp7p5tulvtss0p72v125c_ccs.lib" \
    "$_T/stdcell/tcbn07bwp7p5thvtss0p72v125c_ccs.lib" \
    "$_T/memory/ts1n07ss0p72v125c.lib" \
    "$_T/io/tpbn07v_ss0p72v125c.lib" \
]
set tech(7.5T,lib,ss_0p72v_125c,power) [list \
    "$_T/stdcell/tcbn07bwp7p5tsvtss0p72v125c_power.lib" \
    "$_T/stdcell/tcbn07bwp7p5tlvtss0p72v125c_power.lib" \
]

# TT corners
set tech(7.5T,lib,tt_0p80v_25c,timing) [list \
    "$_T/stdcell/tcbn07bwp7p5tsvttt0p80v25c_ccs.lib" \
    "$_T/stdcell/tcbn07bwp7p5tlvttt0p80v25c_ccs.lib" \
    "$_T/stdcell/tcbn07bwp7p5tulvttt0p80v25c_ccs.lib" \
    "$_T/stdcell/tcbn07bwp7p5thvttt0p80v25c_ccs.lib" \
    "$_T/memory/ts1n07tt0p80v25c.lib" \
    "$_T/io/tpbn07v_tt0p80v25c.lib" \
]
set tech(7.5T,lib,tt_0p80v_25c,power) [list \
    "$_T/stdcell/tcbn07bwp7p5tsvttt0p80v25c_power.lib" \
    "$_T/stdcell/tcbn07bwp7p5tlvttt0p80v25c_power.lib" \
]

# FF corners
set tech(7.5T,lib,ff_0p88v_m40c,timing) [list \
    "$_T/stdcell/tcbn07bwp7p5tsvtff0p88vm40c_ccs.lib" \
    "$_T/stdcell/tcbn07bwp7p5tlvtff0p88vm40c_ccs.lib" \
    "$_T/stdcell/tcbn07bwp7p5tulvtff0p88vm40c_ccs.lib" \
    "$_T/stdcell/tcbn07bwp7p5thvtff0p88vm40c_ccs.lib" \
    "$_T/memory/ts1n07ff0p88vm40c.lib" \
    "$_T/io/tpbn07v_ff0p88vm40c.lib" \
]
set tech(7.5T,lib,ff_0p88v_m40c,power) [list \
    "$_T/stdcell/tcbn07bwp7p5tsvtff0p88vm40c_power.lib" \
    "$_T/stdcell/tcbn07bwp7p5tlvtff0p88vm40c_power.lib" \
]

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 9: DESIGN RULES & ROUTING (shared)
# ═══════════════════════════════════════════════════════════════════════════════

set tech(min_routing_layer) "M1"
set tech(max_routing_layer) "M11"
set tech(clock_routing_layer_min) "M4"
set tech(clock_routing_layer_max) "M9"

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 10: BACKWARD COMPATIBILITY
# ═══════════════════════════════════════════════════════════════════════════════

set _trk $tech(track)
if {[info exists tech(${_trk},ndm)] && [llength $tech(${_trk},ndm)] > 0} {
    set tech(ndm,standard_cells) [lindex $tech(${_trk},ndm) 0]
}
if {[info exists tech(${_trk},lef)] && [llength $tech(${_trk},lef)] > 0} {
    set tech(lef,standard_cells) [lindex $tech(${_trk},lef) 0]
}
set tech(library,root_path)    $tech(lib_root)
set tech(library,stdcell_path) "$tech(lib_root)/Front_End/timing/stdcell"
set tech(library,memory_path)  "$tech(lib_root)/Front_End/timing/memory"
set tech(library,io_path)      "$tech(lib_root)/Front_End/timing/io"

puts "INFO: TSMC N7 tech config loaded — track=$tech(track), metal=$tech(metal_stack), libs=[llength $tech(${_trk},ndm)] NDMs"
