#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow Technology Configuration — TSMC N5 (5nm FinFET)
# ALL track heights (5T, 6T, 7T) in ONE file — flow picks via tech(track)
# ═══════════════════════════════════════════════════════════════════════════════

set _tech_dir [file dirname [file normalize [info script]]]

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 1: TECHNOLOGY IDENTITY
# ═══════════════════════════════════════════════════════════════════════════════

set tech(node)        "5nm"
set tech(process)     "TSMC N5"
set tech(foundry)     "TSMC"
set tech(metal_stack) "13M"
set tech(tracks_available) "5T 6T 7T"

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 2: ACTIVE TRACK RESOLUTION
# ═══════════════════════════════════════════════════════════════════════════════

set tech(track) "5T"
if {[info exists flow(track_variant)] && $flow(track_variant) ne ""} {
    set tech(track) $flow(track_variant)
} elseif {[info exists project(track_variant)] && $project(track_variant) ne ""} {
    set tech(track) $project(track_variant)
} elseif {[info exists ::env(CBFLOW_TRACK_VARIANT)] && $::env(CBFLOW_TRACK_VARIANT) ne ""} {
    set tech(track) $::env(CBFLOW_TRACK_VARIANT)
}
puts "INFO: TSMC N5 active track: $tech(track)"

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 3: LIBRARY ROOT PATHS
# ═══════════════════════════════════════════════════════════════════════════════

set tech(lib_root) "/tmp/test_libs/tsmc_5nm"
set _R "$tech(lib_root)"

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 4: NDM LIBRARIES (per track — ALL Vt flavors + memory + IO)
# ═══════════════════════════════════════════════════════════════════════════════

set tech(5T,ndm) [list \
    "$_R/Back_End/ndm/tcbn05bwp5tsvt.ndm" \
    "$_R/Back_End/ndm/tcbn05bwp5tlvt.ndm" \
    "$_R/Back_End/ndm/tcbn05bwp5tulvt.ndm" \
    "$_R/Back_End/ndm/tcbn05bwp5thvt.ndm" \
    "$_R/Back_End/ndm/ts1n05_memory.ndm" \
    "$_R/Back_End/ndm/tpbn05v_io.ndm" \
]

set tech(6T,ndm) [list \
    "$_R/Back_End/ndm/tcbn05bwp6tsvt.ndm" \
    "$_R/Back_End/ndm/tcbn05bwp6tlvt.ndm" \
    "$_R/Back_End/ndm/tcbn05bwp6tulvt.ndm" \
    "$_R/Back_End/ndm/tcbn05bwp6thvt.ndm" \
    "$_R/Back_End/ndm/ts1n05_memory.ndm" \
    "$_R/Back_End/ndm/tpbn05v_io.ndm" \
]

set tech(7T,ndm) [list \
    "$_R/Back_End/ndm/tcbn05bwp7tsvt.ndm" \
    "$_R/Back_End/ndm/tcbn05bwp7tlvt.ndm" \
    "$_R/Back_End/ndm/tcbn05bwp7tulvt.ndm" \
    "$_R/Back_End/ndm/tcbn05bwp7thvt.ndm" \
    "$_R/Back_End/ndm/ts1n05_memory.ndm" \
    "$_R/Back_End/ndm/tpbn05v_io.ndm" \
]

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 5: LEF FILES (per track)
# ═══════════════════════════════════════════════════════════════════════════════

set tech(lef_tech) "$_R/Back_End/lef/tsmc5nm_tech.lef"

set tech(5T,lef) [list \
    "$_R/Back_End/lef/tcbn05bwp5tsvt.lef" \
    "$_R/Back_End/lef/tcbn05bwp5tlvt.lef" \
    "$_R/Back_End/lef/tcbn05bwp5tulvt.lef" \
    "$_R/Back_End/lef/tcbn05bwp5thvt.lef" \
    "$_R/Back_End/lef/ts1n05_memory.lef" \
    "$_R/Back_End/lef/tpbn05v_io.lef" \
]

set tech(6T,lef) [list \
    "$_R/Back_End/lef/tcbn05bwp6tsvt.lef" \
    "$_R/Back_End/lef/tcbn05bwp6tlvt.lef" \
    "$_R/Back_End/lef/tcbn05bwp6tulvt.lef" \
    "$_R/Back_End/lef/tcbn05bwp6thvt.lef" \
    "$_R/Back_End/lef/ts1n05_memory.lef" \
    "$_R/Back_End/lef/tpbn05v_io.lef" \
]

set tech(7T,lef) [list \
    "$_R/Back_End/lef/tcbn05bwp7tsvt.lef" \
    "$_R/Back_End/lef/tcbn05bwp7tlvt.lef" \
    "$_R/Back_End/lef/tcbn05bwp7tulvt.lef" \
    "$_R/Back_End/lef/tcbn05bwp7thvt.lef" \
    "$_R/Back_End/lef/ts1n05_memory.lef" \
    "$_R/Back_End/lef/tpbn05v_io.lef" \
]

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 6: PARASITIC EXTRACTION (shared)
# ═══════════════════════════════════════════════════════════════════════════════

set tech(tluplus_max) "$_R/Back_End/rcx/tsmc5nm_1p13m_Cmax.tluplus"
set tech(tluplus_min) "$_R/Back_End/rcx/tsmc5nm_1p13m_Cmin.tluplus"
set tech(tluplus_map) "$_R/Back_End/rcx/tsmc5nm_tf_itf_tluplus.map"

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 7: PHYSICAL CELLS (per track)
# ═══════════════════════════════════════════════════════════════════════════════

set tech(5T,site)        "TSMC_N5_SC5T"
set tech(5T,cell_height) "0.216"
set tech(5T,site_width)  "0.051"
set tech(5T,fillers)     "TSMC_N5_SC5T_FILL1 TSMC_N5_SC5T_FILL2 TSMC_N5_SC5T_FILL4 TSMC_N5_SC5T_FILL8"
set tech(5T,well_tap)    "TSMC_N5_SC5T_FILLTIE1"
set tech(5T,endcap)      "TSMC_N5_SC5T_ENDCAP1"
set tech(5T,decap)       "TSMC_N5_SC5T_DCAP4 TSMC_N5_SC5T_DCAP8"
set tech(5T,cts_cells)   "tcbn05bwp5tsvt_CKBUF4 tcbn05bwp5tsvt_CKBUF8 tcbn05bwp5tsvt_CKINV4 tcbn05bwp5tsvt_CKINV8"
set tech(5T,dont_use)    "*D0BWP5T* *OPTHOLD* *DEL*"

set tech(6T,site)        "TSMC_N5_SC6T"
set tech(6T,cell_height) "0.270"
set tech(6T,site_width)  "0.051"
set tech(6T,fillers)     "TSMC_N5_SC6T_FILL1 TSMC_N5_SC6T_FILL2 TSMC_N5_SC6T_FILL4 TSMC_N5_SC6T_FILL8"
set tech(6T,well_tap)    "TSMC_N5_SC6T_FILLTIE1"
set tech(6T,endcap)      "TSMC_N5_SC6T_ENDCAP1"
set tech(6T,decap)       "TSMC_N5_SC6T_DCAP4 TSMC_N5_SC6T_DCAP8"
set tech(6T,cts_cells)   "tcbn05bwp6tsvt_CKBUF4 tcbn05bwp6tsvt_CKBUF8 tcbn05bwp6tsvt_CKINV4 tcbn05bwp6tsvt_CKINV8"
set tech(6T,dont_use)    "*D0BWP6T* *OPTHOLD* *DEL*"

set tech(7T,site)        "TSMC_N5_SC7T"
set tech(7T,cell_height) "0.324"
set tech(7T,site_width)  "0.051"
set tech(7T,fillers)     "TSMC_N5_SC7T_FILL1 TSMC_N5_SC7T_FILL2 TSMC_N5_SC7T_FILL4 TSMC_N5_SC7T_FILL8"
set tech(7T,well_tap)    "TSMC_N5_SC7T_FILLTIE1"
set tech(7T,endcap)      "TSMC_N5_SC7T_ENDCAP1"
set tech(7T,decap)       "TSMC_N5_SC7T_DCAP4 TSMC_N5_SC7T_DCAP8"
set tech(7T,cts_cells)   "tcbn05bwp7tsvt_CKBUF4 tcbn05bwp7tsvt_CKBUF8 tcbn05bwp7tsvt_CKINV4 tcbn05bwp7tsvt_CKINV8"
set tech(7T,dont_use)    "*D0BWP7T* *OPTHOLD* *DEL*"

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 8: LIBRARY SETS PER TRACK + PER PVT CORNER
# ═══════════════════════════════════════════════════════════════════════════════

set _T "$_R/Front_End/timing"

# ── 5T LIBRARY SETS ──

set tech(5T,lib,ss_0p60v_125c,timing) [list \
    "$_T/stdcell/tcbn05bwp5tsvtss0p60v125c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp5tlvtss0p60v125c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp5tulvtss0p60v125c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp5thvtss0p60v125c_ccs.lib" \
    "$_T/memory/ts1n05ss0p60v125c.lib" \
    "$_T/io/tpbn05v_ss0p60v125c.lib" \
]
set tech(5T,lib,ss_0p60v_125c,power) [list \
    "$_T/stdcell/tcbn05bwp5tsvtss0p60v125c_power.lib" \
    "$_T/stdcell/tcbn05bwp5tlvtss0p60v125c_power.lib" \
]

set tech(5T,lib,ss_0p60v_m40c,timing) [list \
    "$_T/stdcell/tcbn05bwp5tsvtss0p60vm40c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp5tlvtss0p60vm40c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp5tulvtss0p60vm40c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp5thvtss0p60vm40c_ccs.lib" \
    "$_T/memory/ts1n05ss0p60vm40c.lib" \
    "$_T/io/tpbn05v_ss0p60vm40c.lib" \
]
set tech(5T,lib,ss_0p60v_m40c,power) [list \
    "$_T/stdcell/tcbn05bwp5tsvtss0p60vm40c_power.lib" \
    "$_T/stdcell/tcbn05bwp5tlvtss0p60vm40c_power.lib" \
]

set tech(5T,lib,ss_0p70v_125c,timing) [list \
    "$_T/stdcell/tcbn05bwp5tsvtss0p70v125c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp5tlvtss0p70v125c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp5tulvtss0p70v125c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp5thvtss0p70v125c_ccs.lib" \
    "$_T/memory/ts1n05ss0p70v125c.lib" \
    "$_T/io/tpbn05v_ss0p70v125c.lib" \
]
set tech(5T,lib,ss_0p70v_125c,power) [list \
    "$_T/stdcell/tcbn05bwp5tsvtss0p70v125c_power.lib" \
    "$_T/stdcell/tcbn05bwp5tlvtss0p70v125c_power.lib" \
]

set tech(5T,lib,ss_0p70v_m40c,timing) [list \
    "$_T/stdcell/tcbn05bwp5tsvtss0p70vm40c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp5tlvtss0p70vm40c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp5tulvtss0p70vm40c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp5thvtss0p70vm40c_ccs.lib" \
    "$_T/memory/ts1n05ss0p70vm40c.lib" \
    "$_T/io/tpbn05v_ss0p70vm40c.lib" \
]
set tech(5T,lib,ss_0p70v_m40c,power) [list \
    "$_T/stdcell/tcbn05bwp5tsvtss0p70vm40c_power.lib" \
    "$_T/stdcell/tcbn05bwp5tlvtss0p70vm40c_power.lib" \
]

set tech(5T,lib,tt_0p70v_25c,timing) [list \
    "$_T/stdcell/tcbn05bwp5tsvttt0p70v25c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp5tlvttt0p70v25c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp5tulvttt0p70v25c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp5thvttt0p70v25c_ccs.lib" \
    "$_T/memory/ts1n05tt0p70v25c.lib" \
    "$_T/io/tpbn05v_tt0p70v25c.lib" \
]
set tech(5T,lib,tt_0p70v_25c,power) [list \
    "$_T/stdcell/tcbn05bwp5tsvttt0p70v25c_power.lib" \
    "$_T/stdcell/tcbn05bwp5tlvttt0p70v25c_power.lib" \
]

set tech(5T,lib,tt_0p70v_125c,timing) [list \
    "$_T/stdcell/tcbn05bwp5tsvttt0p70v125c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp5tlvttt0p70v125c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp5tulvttt0p70v125c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp5thvttt0p70v125c_ccs.lib" \
    "$_T/memory/ts1n05tt0p70v125c.lib" \
    "$_T/io/tpbn05v_tt0p70v125c.lib" \
]
set tech(5T,lib,tt_0p70v_125c,power) [list \
    "$_T/stdcell/tcbn05bwp5tsvttt0p70v125c_power.lib" \
    "$_T/stdcell/tcbn05bwp5tlvttt0p70v125c_power.lib" \
]

set tech(5T,lib,tt_0p70v_m40c,timing) [list \
    "$_T/stdcell/tcbn05bwp5tsvttt0p70vm40c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp5tlvttt0p70vm40c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp5tulvttt0p70vm40c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp5thvttt0p70vm40c_ccs.lib" \
    "$_T/memory/ts1n05tt0p70vm40c.lib" \
    "$_T/io/tpbn05v_tt0p70vm40c.lib" \
]
set tech(5T,lib,tt_0p70v_m40c,power) [list \
    "$_T/stdcell/tcbn05bwp5tsvttt0p70vm40c_power.lib" \
    "$_T/stdcell/tcbn05bwp5tlvttt0p70vm40c_power.lib" \
]

set tech(5T,lib,ff_0p75v_m40c,timing) [list \
    "$_T/stdcell/tcbn05bwp5tsvtff0p75vm40c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp5tlvtff0p75vm40c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp5tulvtff0p75vm40c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp5thvtff0p75vm40c_ccs.lib" \
    "$_T/memory/ts1n05ff0p75vm40c.lib" \
    "$_T/io/tpbn05v_ff0p75vm40c.lib" \
]
set tech(5T,lib,ff_0p75v_m40c,power) [list \
    "$_T/stdcell/tcbn05bwp5tsvtff0p75vm40c_power.lib" \
    "$_T/stdcell/tcbn05bwp5tlvtff0p75vm40c_power.lib" \
]

set tech(5T,lib,ff_0p75v_25c,timing) [list \
    "$_T/stdcell/tcbn05bwp5tsvtff0p75v25c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp5tlvtff0p75v25c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp5tulvtff0p75v25c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp5thvtff0p75v25c_ccs.lib" \
    "$_T/memory/ts1n05ff0p75v25c.lib" \
    "$_T/io/tpbn05v_ff0p75v25c.lib" \
]
set tech(5T,lib,ff_0p75v_25c,power) [list \
    "$_T/stdcell/tcbn05bwp5tsvtff0p75v25c_power.lib" \
    "$_T/stdcell/tcbn05bwp5tlvtff0p75v25c_power.lib" \
]

set tech(5T,lib,ff_0p75v_125c,timing) [list \
    "$_T/stdcell/tcbn05bwp5tsvtff0p75v125c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp5tlvtff0p75v125c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp5tulvtff0p75v125c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp5thvtff0p75v125c_ccs.lib" \
    "$_T/memory/ts1n05ff0p75v125c.lib" \
    "$_T/io/tpbn05v_ff0p75v125c.lib" \
]
set tech(5T,lib,ff_0p75v_125c,power) [list \
    "$_T/stdcell/tcbn05bwp5tsvtff0p75v125c_power.lib" \
    "$_T/stdcell/tcbn05bwp5tlvtff0p75v125c_power.lib" \
]

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 9: DESIGN RULES & ROUTING (shared)
# ═══════════════════════════════════════════════════════════════════════════════

set tech(min_routing_layer) "M1"
set tech(max_routing_layer) "M12"
set tech(clock_routing_layer_min) "M4"
set tech(clock_routing_layer_max) "M10"

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

puts "INFO: TSMC N5 tech config loaded — track=$tech(track), metal=$tech(metal_stack), libs=[llength $tech(${_trk},ndm)] NDMs"
