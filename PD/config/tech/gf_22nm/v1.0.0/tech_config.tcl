#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow Technology Configuration — GlobalFoundries 22FDX (22nm FD-SOI)
# ALL track heights (9T, 7.5T, 8T) in ONE file — flow picks via tech(track)
# ═══════════════════════════════════════════════════════════════════════════════

set _tech_dir [file dirname [file normalize [info script]]]

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 1: TECHNOLOGY IDENTITY
# ═══════════════════════════════════════════════════════════════════════════════

set tech(node)        "22nm"
set tech(process)     "GF 22FDX"
set tech(foundry)     "GlobalFoundries"
set tech(metal_stack) "11M"
set tech(tracks_available) "9T 7.5T 8T"

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 2: ACTIVE TRACK RESOLUTION
# Priority: flow(track_variant) → project(track_variant) → env → default "9T"
# ═══════════════════════════════════════════════════════════════════════════════

set tech(track) "9T"
if {[info exists flow(track_variant)] && $flow(track_variant) ne ""} {
    set tech(track) $flow(track_variant)
} elseif {[info exists project(track_variant)] && $project(track_variant) ne ""} {
    set tech(track) $project(track_variant)
} elseif {[info exists ::env(CBFLOW_TRACK_VARIANT)] && $::env(CBFLOW_TRACK_VARIANT) ne ""} {
    set tech(track) $::env(CBFLOW_TRACK_VARIANT)
}
puts "INFO: GF 22FDX active track: $tech(track)"

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 3: LIBRARY ROOT PATHS
# ═══════════════════════════════════════════════════════════════════════════════

set tech(lib_root) "/tmp/test_libs/gf_22nm"
set _R "$tech(lib_root)"

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 4: NDM LIBRARIES (per track — ALL Vt flavors + memory + IO)
# Command files read: tech($tech(track),ndm)
# ═══════════════════════════════════════════════════════════════════════════════

set tech(9T,ndm) [list \
    "$_R/Back_End/ndm/tcbn22cllbwp9tsvt.ndm" \
    "$_R/Back_End/ndm/tcbn22cllbwp9tlvt.ndm" \
    "$_R/Back_End/ndm/tcbn22cllbwp9tulvt.ndm" \
    "$_R/Back_End/ndm/tcbn22cllbwp9thvt.ndm" \
    "$_R/Back_End/ndm/ts6n22cllhdlvt_memory.ndm" \
    "$_R/Back_End/ndm/tphn22v_io.ndm" \
]

set tech(7.5T,ndm) [list \
    "$_R/Back_End/ndm/tcbn22cllbwp7p5tsvt.ndm" \
    "$_R/Back_End/ndm/tcbn22cllbwp7p5tlvt.ndm" \
    "$_R/Back_End/ndm/tcbn22cllbwp7p5tulvt.ndm" \
    "$_R/Back_End/ndm/tcbn22cllbwp7p5thvt.ndm" \
    "$_R/Back_End/ndm/ts6n22cllhdlvt_memory.ndm" \
    "$_R/Back_End/ndm/tphn22v_io.ndm" \
]

set tech(8T,ndm) [list \
    "$_R/Back_End/ndm/tcbn22cllbwp8tsvt.ndm" \
    "$_R/Back_End/ndm/tcbn22cllbwp8tlvt.ndm" \
    "$_R/Back_End/ndm/tcbn22cllbwp8tulvt.ndm" \
    "$_R/Back_End/ndm/tcbn22cllbwp8thvt.ndm" \
    "$_R/Back_End/ndm/ts6n22cllhdlvt_memory.ndm" \
    "$_R/Back_End/ndm/tphn22v_io.ndm" \
]

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 4b: DB FILES (per track — for Synopsys DC/Genus synthesis)
# Cadence Genus reads: tech($tech(track),db)
# ═══════════════════════════════════════════════════════════════════════════════

set tech(9T,db) [list \
    "$_R/Front_End/timing/stdcell/tcbn22cllbwp9tsvttt0p80v25c.db" \
    "$_R/Front_End/timing/stdcell/tcbn22cllbwp9tlvttt0p80v25c.db" \
    "$_R/Front_End/timing/stdcell/tcbn22cllbwp9tulvttt0p80v25c.db" \
    "$_R/Front_End/timing/stdcell/tcbn22cllbwp9thvttt0p80v25c.db" \
    "$_R/Front_End/timing/memory/ts6n22cllhdlvttt0p80v25c.db" \
    "$_R/Front_End/timing/io/tphn22v_tt0p80v25c.db" \
]

set tech(7.5T,db) [list \
    "$_R/Front_End/timing/stdcell/tcbn22cllbwp7p5tsvttt0p80v25c.db" \
    "$_R/Front_End/timing/stdcell/tcbn22cllbwp7p5tlvttt0p80v25c.db" \
    "$_R/Front_End/timing/stdcell/tcbn22cllbwp7p5tulvttt0p80v25c.db" \
    "$_R/Front_End/timing/stdcell/tcbn22cllbwp7p5thvttt0p80v25c.db" \
    "$_R/Front_End/timing/memory/ts6n22cllhdlvttt0p80v25c.db" \
    "$_R/Front_End/timing/io/tphn22v_tt0p80v25c.db" \
]

set tech(8T,db) [list \
    "$_R/Front_End/timing/stdcell/tcbn22cllbwp8tsvttt0p80v25c.db" \
    "$_R/Front_End/timing/stdcell/tcbn22cllbwp8tlvttt0p80v25c.db" \
    "$_R/Front_End/timing/stdcell/tcbn22cllbwp8tulvttt0p80v25c.db" \
    "$_R/Front_End/timing/stdcell/tcbn22cllbwp8thvttt0p80v25c.db" \
    "$_R/Front_End/timing/memory/ts6n22cllhdlvttt0p80v25c.db" \
    "$_R/Front_End/timing/io/tphn22v_tt0p80v25c.db" \
]

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 4c: NOMINAL .LIB FILES (per track — for Cadence Innovus/Tempus)
# Cadence tools read: tech($tech(track),lib_nom)
# These are the TT nominal .lib files used for library setup (not MMMC corners)
# ═══════════════════════════════════════════════════════════════════════════════

set tech(9T,lib_nom) [list \
    "$_R/Front_End/timing/stdcell/tcbn22cllbwp9tsvttt0p80v25c_ccs.lib" \
    "$_R/Front_End/timing/stdcell/tcbn22cllbwp9tlvttt0p80v25c_ccs.lib" \
    "$_R/Front_End/timing/stdcell/tcbn22cllbwp9tulvttt0p80v25c_ccs.lib" \
    "$_R/Front_End/timing/stdcell/tcbn22cllbwp9thvttt0p80v25c_ccs.lib" \
    "$_R/Front_End/timing/memory/ts6n22cllhdlvttt0p80v25c.lib" \
    "$_R/Front_End/timing/io/tphn22v_tt0p80v25c.lib" \
]

set tech(7.5T,lib_nom) [list \
    "$_R/Front_End/timing/stdcell/tcbn22cllbwp7p5tsvttt0p80v25c_ccs.lib" \
    "$_R/Front_End/timing/stdcell/tcbn22cllbwp7p5tlvttt0p80v25c_ccs.lib" \
    "$_R/Front_End/timing/stdcell/tcbn22cllbwp7p5tulvttt0p80v25c_ccs.lib" \
    "$_R/Front_End/timing/stdcell/tcbn22cllbwp7p5thvttt0p80v25c_ccs.lib" \
    "$_R/Front_End/timing/memory/ts6n22cllhdlvttt0p80v25c.lib" \
    "$_R/Front_End/timing/io/tphn22v_tt0p80v25c.lib" \
]

set tech(8T,lib_nom) [list \
    "$_R/Front_End/timing/stdcell/tcbn22cllbwp8tsvttt0p80v25c_ccs.lib" \
    "$_R/Front_End/timing/stdcell/tcbn22cllbwp8tlvttt0p80v25c_ccs.lib" \
    "$_R/Front_End/timing/stdcell/tcbn22cllbwp8tulvttt0p80v25c_ccs.lib" \
    "$_R/Front_End/timing/stdcell/tcbn22cllbwp8thvttt0p80v25c_ccs.lib" \
    "$_R/Front_End/timing/memory/ts6n22cllhdlvttt0p80v25c.lib" \
    "$_R/Front_End/timing/io/tphn22v_tt0p80v25c.lib" \
]

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 5: LEF FILES (per track — ALL Vt flavors + memory + IO)
# Command files read: tech($tech(track),lef)
# ═══════════════════════════════════════════════════════════════════════════════

set tech(lef_tech) "$_R/Back_End/lef/gf22nm_tech.lef"

set tech(9T,lef) [list \
    "$_R/Back_End/lef/tcbn22cllbwp9tsvt.lef" \
    "$_R/Back_End/lef/tcbn22cllbwp9tlvt.lef" \
    "$_R/Back_End/lef/tcbn22cllbwp9tulvt.lef" \
    "$_R/Back_End/lef/tcbn22cllbwp9thvt.lef" \
    "$_R/Back_End/lef/ts6n22cllhdlvt_memory.lef" \
    "$_R/Back_End/lef/tphn22v_io.lef" \
]

set tech(7.5T,lef) [list \
    "$_R/Back_End/lef/tcbn22cllbwp7p5tsvt.lef" \
    "$_R/Back_End/lef/tcbn22cllbwp7p5tlvt.lef" \
    "$_R/Back_End/lef/tcbn22cllbwp7p5tulvt.lef" \
    "$_R/Back_End/lef/tcbn22cllbwp7p5thvt.lef" \
    "$_R/Back_End/lef/ts6n22cllhdlvt_memory.lef" \
    "$_R/Back_End/lef/tphn22v_io.lef" \
]

set tech(8T,lef) [list \
    "$_R/Back_End/lef/tcbn22cllbwp8tsvt.lef" \
    "$_R/Back_End/lef/tcbn22cllbwp8tlvt.lef" \
    "$_R/Back_End/lef/tcbn22cllbwp8tulvt.lef" \
    "$_R/Back_End/lef/tcbn22cllbwp8thvt.lef" \
    "$_R/Back_End/lef/ts6n22cllhdlvt_memory.lef" \
    "$_R/Back_End/lef/tphn22v_io.lef" \
]

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 6: PARASITIC EXTRACTION (shared — same for all tracks)
# ═══════════════════════════════════════════════════════════════════════════════

set tech(tluplus_max) "$_R/Back_End/rcx/gf22nm_1p11m_Cmax.tluplus"
set tech(tluplus_min) "$_R/Back_End/rcx/gf22nm_1p11m_Cmin.tluplus"
set tech(tluplus_map) "$_R/Back_End/rcx/gf22nm_tf_itf_tluplus.map"

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 7: PHYSICAL CELLS (per track — site, fillers, CTS, tap, endcap)
# Command files read: tech($tech(track),site), tech($tech(track),fillers), etc.
# ═══════════════════════════════════════════════════════════════════════════════

# ── 9T Physical ──
set tech(9T,site)        "GF22FDX_SC9T"
set tech(9T,cell_height) "0.810"
set tech(9T,site_width)  "0.114"
set tech(9T,fillers)     "GF22FDX_SC9T_SVT_FILL1 GF22FDX_SC9T_SVT_FILL2 GF22FDX_SC9T_SVT_FILL4 GF22FDX_SC9T_SVT_FILL8 GF22FDX_SC9T_SVT_FILL16 GF22FDX_SC9T_SVT_FILL32"
set tech(9T,well_tap)    "GF22FDX_SC9T_SVT_FILLTIE1"
set tech(9T,endcap)      "GF22FDX_SC9T_SVT_ENDCAP1"
set tech(9T,decap)       "GF22FDX_SC9T_SVT_DCAP4 GF22FDX_SC9T_SVT_DCAP8"
set tech(9T,cts_cells)   "tcbn22cllbwp9tsvt_CKBUF4 tcbn22cllbwp9tsvt_CKBUF8 tcbn22cllbwp9tsvt_CKBUF16 tcbn22cllbwp9tsvt_CKINV4 tcbn22cllbwp9tsvt_CKINV8"
set tech(9T,dont_use)    "*D0BWP9T* *OPTHOLD* *DEL*"

# ── 7.5T Physical ──
set tech(7.5T,site)        "GF22FDX_SC7P5T"
set tech(7.5T,cell_height) "0.675"
set tech(7.5T,site_width)  "0.116"
set tech(7.5T,fillers)     "GF22FDX_SC7P5T_SVT_FILL1 GF22FDX_SC7P5T_SVT_FILL2 GF22FDX_SC7P5T_SVT_FILL4 GF22FDX_SC7P5T_SVT_FILL8"
set tech(7.5T,well_tap)    "GF22FDX_SC7P5T_SVT_FILLTIE1"
set tech(7.5T,endcap)      "GF22FDX_SC7P5T_SVT_ENDCAP1"
set tech(7.5T,decap)       "GF22FDX_SC7P5T_SVT_DCAP4 GF22FDX_SC7P5T_SVT_DCAP8"
set tech(7.5T,cts_cells)   "tcbn22cllbwp7p5tsvt_CKBUF4 tcbn22cllbwp7p5tsvt_CKBUF8 tcbn22cllbwp7p5tsvt_CKINV4 tcbn22cllbwp7p5tsvt_CKINV8"
set tech(7.5T,dont_use)    "*D0BWP7P5T* *OPTHOLD* *DEL*"

# ── 8T Physical ──
set tech(8T,site)        "GF22FDX_SC8T"
set tech(8T,cell_height) "0.720"
set tech(8T,site_width)  "0.114"
set tech(8T,fillers)     "GF22FDX_SC8T_SVT_FILL1 GF22FDX_SC8T_SVT_FILL2 GF22FDX_SC8T_SVT_FILL4 GF22FDX_SC8T_SVT_FILL8"
set tech(8T,well_tap)    "GF22FDX_SC8T_SVT_FILLTIE1"
set tech(8T,endcap)      "GF22FDX_SC8T_SVT_ENDCAP1"
set tech(8T,decap)       "GF22FDX_SC8T_SVT_DCAP4 GF22FDX_SC8T_SVT_DCAP8"
set tech(8T,cts_cells)   "tcbn22cllbwp8tsvt_CKBUF4 tcbn22cllbwp8tsvt_CKBUF8 tcbn22cllbwp8tsvt_CKINV4 tcbn22cllbwp8tsvt_CKINV8"
set tech(8T,dont_use)    "*D0BWP8T* *OPTHOLD* *DEL*"

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 8: LIBRARY SETS PER TRACK + PER PVT CORNER
# Each set: ALL Vt flavors (SVT+LVT+ULVT+HVT) + memory + IO
# MMMC reads: tech($tech(track),lib,<corner>,timing)
# ═══════════════════════════════════════════════════════════════════════════════

set _T "$_R/Front_End/timing"

# ┌──────────────────────────────────────────────────────────────────────────┐
# │  9T LIBRARY SETS                                                        │
# └──────────────────────────────────────────────────────────────────────────┘

# SS corners (setup-critical)
set tech(9T,lib,ss_0p76v_150c,timing) [list \
    "$_T/stdcell/tcbn22cllbwp9tsvtss0p76v150c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp9tlvtss0p76v150c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp9tulvtss0p76v150c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp9thvtss0p76v150c_ccs.lib" \
    "$_T/memory/ts6n22cllhdlvtss0p76v150c.lib" \
    "$_T/io/tphn22v_ss0p76v150c.lib" \
]
set tech(9T,lib,ss_0p76v_150c,power) [list \
    "$_T/stdcell/tcbn22cllbwp9tsvtss0p76v150c_power.lib" \
    "$_T/stdcell/tcbn22cllbwp9tlvtss0p76v150c_power.lib" \
    "$_T/stdcell/tcbn22cllbwp9tulvtss0p76v150c_power.lib" \
    "$_T/stdcell/tcbn22cllbwp9thvtss0p76v150c_power.lib" \
]

set tech(9T,lib,ss_0p76v_25c,timing) [list \
    "$_T/stdcell/tcbn22cllbwp9tsvtss0p76v25c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp9tlvtss0p76v25c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp9tulvtss0p76v25c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp9thvtss0p76v25c_ccs.lib" \
    "$_T/memory/ts6n22cllhdlvtss0p76v25c.lib" \
    "$_T/io/tphn22v_ss0p76v25c.lib" \
]
set tech(9T,lib,ss_0p76v_25c,power) [list \
    "$_T/stdcell/tcbn22cllbwp9tsvtss0p76v25c_power.lib" \
    "$_T/stdcell/tcbn22cllbwp9tlvtss0p76v25c_power.lib" \
]

set tech(9T,lib,ss_0p76v_m40c,timing) [list \
    "$_T/stdcell/tcbn22cllbwp9tsvtss0p76vm40c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp9tlvtss0p76vm40c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp9tulvtss0p76vm40c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp9thvtss0p76vm40c_ccs.lib" \
    "$_T/memory/ts6n22cllhdlvtss0p76vm40c.lib" \
    "$_T/io/tphn22v_ss0p76vm40c.lib" \
]
set tech(9T,lib,ss_0p76v_m40c,power) [list \
    "$_T/stdcell/tcbn22cllbwp9tsvtss0p76vm40c_power.lib" \
    "$_T/stdcell/tcbn22cllbwp9tlvtss0p76vm40c_power.lib" \
]

set tech(9T,lib,ss_0p80v_150c,timing) [list \
    "$_T/stdcell/tcbn22cllbwp9tsvtss0p80v150c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp9tlvtss0p80v150c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp9tulvtss0p80v150c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp9thvtss0p80v150c_ccs.lib" \
    "$_T/memory/ts6n22cllhdlvtss0p80v150c.lib" \
    "$_T/io/tphn22v_ss0p80v150c.lib" \
]
set tech(9T,lib,ss_0p80v_150c,power) [list \
    "$_T/stdcell/tcbn22cllbwp9tsvtss0p80v150c_power.lib" \
    "$_T/stdcell/tcbn22cllbwp9tlvtss0p80v150c_power.lib" \
]

set tech(9T,lib,ss_0p80v_25c,timing) [list \
    "$_T/stdcell/tcbn22cllbwp9tsvtss0p80v25c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp9tlvtss0p80v25c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp9tulvtss0p80v25c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp9thvtss0p80v25c_ccs.lib" \
    "$_T/memory/ts6n22cllhdlvtss0p80v25c.lib" \
    "$_T/io/tphn22v_ss0p80v25c.lib" \
]
set tech(9T,lib,ss_0p80v_25c,power) [list \
    "$_T/stdcell/tcbn22cllbwp9tsvtss0p80v25c_power.lib" \
    "$_T/stdcell/tcbn22cllbwp9tlvtss0p80v25c_power.lib" \
]

# TT corners (nominal)
set tech(9T,lib,tt_0p80v_25c,timing) [list \
    "$_T/stdcell/tcbn22cllbwp9tsvttt0p80v25c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp9tlvttt0p80v25c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp9tulvttt0p80v25c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp9thvttt0p80v25c_ccs.lib" \
    "$_T/memory/ts6n22cllhdlvttt0p80v25c.lib" \
    "$_T/io/tphn22v_tt0p80v25c.lib" \
]
set tech(9T,lib,tt_0p80v_25c,power) [list \
    "$_T/stdcell/tcbn22cllbwp9tsvttt0p80v25c_power.lib" \
    "$_T/stdcell/tcbn22cllbwp9tlvttt0p80v25c_power.lib" \
]

set tech(9T,lib,tt_0p80v_150c,timing) [list \
    "$_T/stdcell/tcbn22cllbwp9tsvttt0p80v150c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp9tlvttt0p80v150c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp9tulvttt0p80v150c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp9thvttt0p80v150c_ccs.lib" \
    "$_T/memory/ts6n22cllhdlvttt0p80v150c.lib" \
    "$_T/io/tphn22v_tt0p80v150c.lib" \
]
set tech(9T,lib,tt_0p80v_150c,power) [list \
    "$_T/stdcell/tcbn22cllbwp9tsvttt0p80v150c_power.lib" \
    "$_T/stdcell/tcbn22cllbwp9tlvttt0p80v150c_power.lib" \
]

set tech(9T,lib,tt_0p80v_m40c,timing) [list \
    "$_T/stdcell/tcbn22cllbwp9tsvttt0p80vm40c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp9tlvttt0p80vm40c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp9tulvttt0p80vm40c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp9thvttt0p80vm40c_ccs.lib" \
    "$_T/memory/ts6n22cllhdlvttt0p80vm40c.lib" \
    "$_T/io/tphn22v_tt0p80vm40c.lib" \
]
set tech(9T,lib,tt_0p80v_m40c,power) [list \
    "$_T/stdcell/tcbn22cllbwp9tsvttt0p80vm40c_power.lib" \
    "$_T/stdcell/tcbn22cllbwp9tlvttt0p80vm40c_power.lib" \
]

# FF corners (hold-critical)
set tech(9T,lib,ff_0p84v_m40c,timing) [list \
    "$_T/stdcell/tcbn22cllbwp9tsvtff0p84vm40c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp9tlvtff0p84vm40c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp9tulvtff0p84vm40c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp9thvtff0p84vm40c_ccs.lib" \
    "$_T/memory/ts6n22cllhdlvtff0p84vm40c.lib" \
    "$_T/io/tphn22v_ff0p84vm40c.lib" \
]
set tech(9T,lib,ff_0p84v_m40c,power) [list \
    "$_T/stdcell/tcbn22cllbwp9tsvtff0p84vm40c_power.lib" \
    "$_T/stdcell/tcbn22cllbwp9tlvtff0p84vm40c_power.lib" \
]

set tech(9T,lib,ff_0p84v_25c,timing) [list \
    "$_T/stdcell/tcbn22cllbwp9tsvtff0p84v25c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp9tlvtff0p84v25c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp9tulvtff0p84v25c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp9thvtff0p84v25c_ccs.lib" \
    "$_T/memory/ts6n22cllhdlvtff0p84v25c.lib" \
    "$_T/io/tphn22v_ff0p84v25c.lib" \
]
set tech(9T,lib,ff_0p84v_25c,power) [list \
    "$_T/stdcell/tcbn22cllbwp9tsvtff0p84v25c_power.lib" \
    "$_T/stdcell/tcbn22cllbwp9tlvtff0p84v25c_power.lib" \
]

set tech(9T,lib,ff_0p84v_150c,timing) [list \
    "$_T/stdcell/tcbn22cllbwp9tsvtff0p84v150c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp9tlvtff0p84v150c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp9tulvtff0p84v150c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp9thvtff0p84v150c_ccs.lib" \
    "$_T/memory/ts6n22cllhdlvtff0p84v150c.lib" \
    "$_T/io/tphn22v_ff0p84v150c.lib" \
]
set tech(9T,lib,ff_0p84v_150c,power) [list \
    "$_T/stdcell/tcbn22cllbwp9tsvtff0p84v150c_power.lib" \
    "$_T/stdcell/tcbn22cllbwp9tlvtff0p84v150c_power.lib" \
]

set tech(9T,lib,ff_0p80v_m40c,timing) [list \
    "$_T/stdcell/tcbn22cllbwp9tsvtff0p80vm40c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp9tlvtff0p80vm40c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp9tulvtff0p80vm40c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp9thvtff0p80vm40c_ccs.lib" \
    "$_T/memory/ts6n22cllhdlvtff0p80vm40c.lib" \
    "$_T/io/tphn22v_ff0p80vm40c.lib" \
]
set tech(9T,lib,ff_0p80v_m40c,power) [list \
    "$_T/stdcell/tcbn22cllbwp9tsvtff0p80vm40c_power.lib" \
    "$_T/stdcell/tcbn22cllbwp9tlvtff0p80vm40c_power.lib" \
]

# ┌──────────────────────────────────────────────────────────────────────────┐
# │  7.5T LIBRARY SETS (same corners, different cell prefix)                │
# └──────────────────────────────────────────────────────────────────────────┘

# SS corners
set tech(7.5T,lib,ss_0p76v_150c,timing) [list \
    "$_T/stdcell/tcbn22cllbwp7p5tsvtss0p76v150c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp7p5tlvtss0p76v150c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp7p5tulvtss0p76v150c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp7p5thvtss0p76v150c_ccs.lib" \
    "$_T/memory/ts6n22cllhdlvtss0p76v150c.lib" \
    "$_T/io/tphn22v_ss0p76v150c.lib" \
]
set tech(7.5T,lib,ss_0p76v_150c,power) [list \
    "$_T/stdcell/tcbn22cllbwp7p5tsvtss0p76v150c_power.lib" \
    "$_T/stdcell/tcbn22cllbwp7p5tlvtss0p76v150c_power.lib" \
]

# TT corners
set tech(7.5T,lib,tt_0p80v_25c,timing) [list \
    "$_T/stdcell/tcbn22cllbwp7p5tsvttt0p80v25c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp7p5tlvttt0p80v25c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp7p5tulvttt0p80v25c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp7p5thvttt0p80v25c_ccs.lib" \
    "$_T/memory/ts6n22cllhdlvttt0p80v25c.lib" \
    "$_T/io/tphn22v_tt0p80v25c.lib" \
]
set tech(7.5T,lib,tt_0p80v_25c,power) [list \
    "$_T/stdcell/tcbn22cllbwp7p5tsvttt0p80v25c_power.lib" \
    "$_T/stdcell/tcbn22cllbwp7p5tlvttt0p80v25c_power.lib" \
]

# FF corners
set tech(7.5T,lib,ff_0p84v_m40c,timing) [list \
    "$_T/stdcell/tcbn22cllbwp7p5tsvtff0p84vm40c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp7p5tlvtff0p84vm40c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp7p5tulvtff0p84vm40c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp7p5thvtff0p84vm40c_ccs.lib" \
    "$_T/memory/ts6n22cllhdlvtff0p84vm40c.lib" \
    "$_T/io/tphn22v_ff0p84vm40c.lib" \
]
set tech(7.5T,lib,ff_0p84v_m40c,power) [list \
    "$_T/stdcell/tcbn22cllbwp7p5tsvtff0p84vm40c_power.lib" \
    "$_T/stdcell/tcbn22cllbwp7p5tlvtff0p84vm40c_power.lib" \
]

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 9: DESIGN RULES & ROUTING (shared — same for all tracks)
# ═══════════════════════════════════════════════════════════════════════════════

set tech(min_routing_layer) "M2"
set tech(max_routing_layer) "M10"
set tech(clock_routing_layer_min) "M4"
set tech(clock_routing_layer_max) "M8"

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 10: BODY BIAS (GF 22FDX specific — FD-SOI advantage)
# ═══════════════════════════════════════════════════════════════════════════════

set tech(body_bias,fbb_voltage) "0.8"
set tech(body_bias,rbb_voltage) "-0.3"
set tech(body_bias,enabled) "true"

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 11: BACKWARD COMPATIBILITY — old variable names → new
# Remove this section after all command files are updated
# ═══════════════════════════════════════════════════════════════════════════════

set _trk $tech(track)
# Old-style single vars that some command files may still reference
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

puts "INFO: GF 22FDX tech config loaded — track=$tech(track), metal=$tech(metal_stack), libs=[llength $tech(${_trk},ndm)] NDMs"
