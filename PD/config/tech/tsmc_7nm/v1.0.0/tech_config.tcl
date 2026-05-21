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
# SECTION 2: ACTIVE TRACK
# Source: project(track_variant) — mandatory, set in project_config.tcl
# ═══════════════════════════════════════════════════════════════════════════════

if {![info exists project(track_variant)] || $project(track_variant) eq ""} {
    puts "ERROR: project(track_variant) not set. Define it in your project_config.tcl"
    puts "       Technology: $tech(process) | Available tracks: $tech(tracks_available)"
    exit 1
}
if {[lsearch -exact $tech(tracks_available) $project(track_variant)] == -1} {
    puts "ERROR: Invalid track '$project(track_variant)' for $tech(process)"
    puts "       Available tracks: $tech(tracks_available)"
    exit 1
}
set tech(track) $project(track_variant)
puts "INFO: $tech(process) active track: $tech(track)"

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 3: LIBRARY ROOT PATHS
# ═══════════════════════════════════════════════════════════════════════════════

set tech(lib_root) "/tmp/test_libs/tsmc_7nm"
set _R "$tech(lib_root)"

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 4: NDM LIBRARIES
# Categorized: stdcell (per track) + memory/io/analog/hierarchical (shared)
# Command files read: tech($tech(track),ndm)
# ═══════════════════════════════════════════════════════════════════════════════

# ── Stdcell NDMs per track (only these change with track) ──
set tech(6T,ndm,stdcell) [list \
    "$_R/Back_End/ndm/tcbn07bwp6tsvt.ndm" \
    "$_R/Back_End/ndm/tcbn07bwp6tlvt.ndm" \
    "$_R/Back_End/ndm/tcbn07bwp6tulvt.ndm" \
    "$_R/Back_End/ndm/tcbn07bwp6thvt.ndm" \
]
set tech(7.5T,ndm,stdcell) [list \
    "$_R/Back_End/ndm/tcbn07bwp7p5tsvt.ndm" \
    "$_R/Back_End/ndm/tcbn07bwp7p5tlvt.ndm" \
    "$_R/Back_End/ndm/tcbn07bwp7p5tulvt.ndm" \
    "$_R/Back_End/ndm/tcbn07bwp7p5thvt.ndm" \
]
set tech(9T,ndm,stdcell) [list \
    "$_R/Back_End/ndm/tcbn07bwp9tsvt.ndm" \
    "$_R/Back_End/ndm/tcbn07bwp9tlvt.ndm" \
    "$_R/Back_End/ndm/tcbn07bwp9tulvt.ndm" \
    "$_R/Back_End/ndm/tcbn07bwp9thvt.ndm" \
]

# ── Shared NDMs (same for all tracks — define once) ──
set tech(ndm,memory)       [list "$_R/Back_End/ndm/ts1n07_memory.ndm"]
set tech(ndm,io)           [list "$_R/Back_End/ndm/tpbn07v_io.ndm"]
set tech(ndm,analog)       [list]

# ── Auto-build combined NDM list per track ──
foreach _t $tech(tracks_available) {
    set tech(${_t},ndm) [concat $tech(${_t},ndm,stdcell) $tech(ndm,memory) $tech(ndm,io) $tech(ndm,analog)]
}

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 4b: DB FILES (for Synopsys synthesis)
# Categorized: stdcell (per track) + memory/io (shared)
# Cadence Genus reads: tech($tech(track),db)
# ═══════════════════════════════════════════════════════════════════════════════

# ── Stdcell DBs per track ──
set tech(6T,db,stdcell) [list \
    "$_R/Front_End/timing/stdcell/tcbn07bwp6tsvttt0p80v25c.db" \
    "$_R/Front_End/timing/stdcell/tcbn07bwp6tlvttt0p80v25c.db" \
    "$_R/Front_End/timing/stdcell/tcbn07bwp6tulvttt0p80v25c.db" \
    "$_R/Front_End/timing/stdcell/tcbn07bwp6thvttt0p80v25c.db" \
]
set tech(7.5T,db,stdcell) [list \
    "$_R/Front_End/timing/stdcell/tcbn07bwp7p5tsvttt0p80v25c.db" \
    "$_R/Front_End/timing/stdcell/tcbn07bwp7p5tlvttt0p80v25c.db" \
    "$_R/Front_End/timing/stdcell/tcbn07bwp7p5tulvttt0p80v25c.db" \
    "$_R/Front_End/timing/stdcell/tcbn07bwp7p5thvttt0p80v25c.db" \
]
set tech(9T,db,stdcell) [list \
    "$_R/Front_End/timing/stdcell/tcbn07bwp9tsvttt0p80v25c.db" \
    "$_R/Front_End/timing/stdcell/tcbn07bwp9tlvttt0p80v25c.db" \
    "$_R/Front_End/timing/stdcell/tcbn07bwp9tulvttt0p80v25c.db" \
    "$_R/Front_End/timing/stdcell/tcbn07bwp9thvttt0p80v25c.db" \
]

# ── Shared DBs ──
set tech(db,memory) [list "$_R/Front_End/timing/memory/ts1n07tt0p80v25c.db"]
set tech(db,io)     [list "$_R/Front_End/timing/io/tpbn07v_tt0p80v25c.db"]

# ── Auto-build combined DB list per track ──
foreach _t $tech(tracks_available) {
    set tech(${_t},db) [concat $tech(${_t},db,stdcell) $tech(db,memory) $tech(db,io)]
}

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 4c: NOMINAL .LIB FILES (for Cadence Innovus/Tempus)
# Categorized: stdcell (per track) + memory/io (shared)
# Cadence tools read: tech($tech(track),lib_nom)
# ═══════════════════════════════════════════════════════════════════════════════

# ── Stdcell nominal libs per track ──
set tech(6T,lib_nom,stdcell) [list \
    "$_R/Front_End/timing/stdcell/tcbn07bwp6tsvttt0p80v25c_ccs.lib" \
    "$_R/Front_End/timing/stdcell/tcbn07bwp6tlvttt0p80v25c_ccs.lib" \
    "$_R/Front_End/timing/stdcell/tcbn07bwp6tulvttt0p80v25c_ccs.lib" \
    "$_R/Front_End/timing/stdcell/tcbn07bwp6thvttt0p80v25c_ccs.lib" \
]
set tech(7.5T,lib_nom,stdcell) [list \
    "$_R/Front_End/timing/stdcell/tcbn07bwp7p5tsvttt0p80v25c_ccs.lib" \
    "$_R/Front_End/timing/stdcell/tcbn07bwp7p5tlvttt0p80v25c_ccs.lib" \
    "$_R/Front_End/timing/stdcell/tcbn07bwp7p5tulvttt0p80v25c_ccs.lib" \
    "$_R/Front_End/timing/stdcell/tcbn07bwp7p5thvttt0p80v25c_ccs.lib" \
]
set tech(9T,lib_nom,stdcell) [list \
    "$_R/Front_End/timing/stdcell/tcbn07bwp9tsvttt0p80v25c_ccs.lib" \
    "$_R/Front_End/timing/stdcell/tcbn07bwp9tlvttt0p80v25c_ccs.lib" \
    "$_R/Front_End/timing/stdcell/tcbn07bwp9tulvttt0p80v25c_ccs.lib" \
    "$_R/Front_End/timing/stdcell/tcbn07bwp9thvttt0p80v25c_ccs.lib" \
]

# ── Shared nominal libs ──
set tech(lib_nom,memory) [list "$_R/Front_End/timing/memory/ts1n07tt0p80v25c.lib"]
set tech(lib_nom,io)     [list "$_R/Front_End/timing/io/tpbn07v_tt0p80v25c.lib"]

# ── Auto-build combined nominal lib list per track ──
foreach _t $tech(tracks_available) {
    set tech(${_t},lib_nom) [concat $tech(${_t},lib_nom,stdcell) $tech(lib_nom,memory) $tech(lib_nom,io)]
}

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 5: LEF FILES
# Categorized: stdcell (per track) + memory/io (shared)
# Command files read: tech($tech(track),lef)
# ═══════════════════════════════════════════════════════════════════════════════

set tech(lef_tech) "$_R/Back_End/lef/tsmc7nm_tech.lef"

# ── Stdcell LEFs per track ──
set tech(6T,lef,stdcell) [list \
    "$_R/Back_End/lef/tcbn07bwp6tsvt.lef" \
    "$_R/Back_End/lef/tcbn07bwp6tlvt.lef" \
    "$_R/Back_End/lef/tcbn07bwp6tulvt.lef" \
    "$_R/Back_End/lef/tcbn07bwp6thvt.lef" \
]
set tech(7.5T,lef,stdcell) [list \
    "$_R/Back_End/lef/tcbn07bwp7p5tsvt.lef" \
    "$_R/Back_End/lef/tcbn07bwp7p5tlvt.lef" \
    "$_R/Back_End/lef/tcbn07bwp7p5tulvt.lef" \
    "$_R/Back_End/lef/tcbn07bwp7p5thvt.lef" \
]
set tech(9T,lef,stdcell) [list \
    "$_R/Back_End/lef/tcbn07bwp9tsvt.lef" \
    "$_R/Back_End/lef/tcbn07bwp9tlvt.lef" \
    "$_R/Back_End/lef/tcbn07bwp9tulvt.lef" \
    "$_R/Back_End/lef/tcbn07bwp9thvt.lef" \
]

# ── Shared LEFs ──
set tech(lef,memory) [list "$_R/Back_End/lef/ts1n07_memory.lef"]
set tech(lef,io)     [list "$_R/Back_End/lef/tpbn07v_io.lef"]

# ── Auto-build combined LEF list per track ──
foreach _t $tech(tracks_available) {
    set tech(${_t},lef) [concat $tech(${_t},lef,stdcell) $tech(lef,memory) $tech(lef,io)]
}

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 6: PARASITIC EXTRACTION (shared — same for all tracks)
# Synopsys (FC/StarRC): TLU+ and nxtgrd
# Cadence (Innovus/Quantus): QRC tech file
# ═══════════════════════════════════════════════════════════════════════════════

# ── Shared (all RC corners) ──
set tech(tluplus_map) "$_R/Back_End/rcx/tsmc7nm_tf_itf_tluplus.map"

# ── Per RC corner: Synopsys TLU+, nxtgrd, Cadence QRC ──
set tech(rcx,rc_max,tluplus)   "$_R/Back_End/rcx/tsmc7nm_1p12m_Cmax.tluplus"
set tech(rcx,rc_max,nxtgrd)    "$_R/Back_End/rcx/tsmc7nm_1p12m_Cmax.nxtgrd"
set tech(rcx,rc_max,qrc)       "$_R/Back_End/rcx/tsmc7nm_1p12m_Cmax.qrcTechFile"

set tech(rcx,rc_typ,tluplus)   "$_R/Back_End/rcx/tsmc7nm_1p12m_Ctyp.tluplus"
set tech(rcx,rc_typ,nxtgrd)    "$_R/Back_End/rcx/tsmc7nm_1p12m_Ctyp.nxtgrd"
set tech(rcx,rc_typ,qrc)       "$_R/Back_End/rcx/tsmc7nm_1p12m_Ctyp.qrcTechFile"

set tech(rcx,rc_min,tluplus)   "$_R/Back_End/rcx/tsmc7nm_1p12m_Cmin.tluplus"
set tech(rcx,rc_min,nxtgrd)    "$_R/Back_End/rcx/tsmc7nm_1p12m_Cmin.nxtgrd"
set tech(rcx,rc_min,qrc)       "$_R/Back_End/rcx/tsmc7nm_1p12m_Cmin.qrcTechFile"

set tech(rcx,rc_max_cworst,tluplus) "$_R/Back_End/rcx/tsmc7nm_1p12m_Cmax.tluplus"
set tech(rcx,rc_max_cworst,nxtgrd)  "$_R/Back_End/rcx/tsmc7nm_1p12m_Cmax.nxtgrd"
set tech(rcx,rc_max_cworst,qrc)     "$_R/Back_End/rcx/tsmc7nm_1p12m_Cmax.qrcTechFile"

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 7: PHYSICAL CELLS (per track — site, fillers, CTS, tap, endcap)
# Command files read: tech($tech(track),site), tech($tech(track),fillers), etc.
# ═══════════════════════════════════════════════════════════════════════════════

# ── 6T Physical ──
set tech(6T,site)           "TSMC_N7_SC6T"
set tech(6T,cell_height)    "0.270"
set tech(6T,site_width)     "0.054"
set tech(6T,fillers)        "TSMC_N7_SC6T_FILL1 TSMC_N7_SC6T_FILL2 TSMC_N7_SC6T_FILL4 TSMC_N7_SC6T_FILL8"
set tech(6T,well_tap)       "TSMC_N7_SC6T_FILLTIE1"
set tech(6T,endcap)         "TSMC_N7_SC6T_ENDCAP1"
set tech(6T,decap)          "TSMC_N7_SC6T_DCAP4 TSMC_N7_SC6T_DCAP8"
set tech(6T,clock_buffers)  "tcbn07bwp6tsvt_CKBUF4 tcbn07bwp6tsvt_CKBUF8"
set tech(6T,clock_inverters) "tcbn07bwp6tsvt_CKINV4"
set tech(6T,hold_buffers)   "tcbn07bwp6tsvt_BUFFD1 tcbn07bwp6tsvt_BUFFD2 tcbn07bwp6tsvt_BUFFD4"
set tech(6T,delay_cells)    "tcbn07bwp6tsvt_DEL1 tcbn07bwp6tsvt_DEL2 tcbn07bwp6tsvt_DEL4"
set tech(6T,icg_cells)      "tcbn07bwp6tsvt_CKLNQD1 tcbn07bwp6tsvt_CKLNQD2 tcbn07bwp6tsvt_CKLNQD4"
set tech(6T,power_switch)   "tcbn07bwp6tsvt_HDRDWN1 tcbn07bwp6tsvt_HDRDWN2 tcbn07bwp6tsvt_HDRDWN4"
set tech(6T,isolation)      "tcbn07bwp6tsvt_ISOLAND1 tcbn07bwp6tsvt_ISOLOR1 tcbn07bwp6tsvt_ISOLAND2 tcbn07bwp6tsvt_ISOLOR2"
set tech(6T,level_shifter)  "tcbn07bwp6tsvt_LSDOWN1 tcbn07bwp6tsvt_LSUP1 tcbn07bwp6tsvt_LSDOWN2 tcbn07bwp6tsvt_LSUP2"
set tech(6T,tie_cells)      "tcbn07bwp6tsvt_TIEHI tcbn07bwp6tsvt_TIELO"
set tech(6T,dont_use)       "*D0BWP6T* *OPTHOLD* *DEL*"

# ── 7.5T Physical ──
set tech(7.5T,site)           "TSMC_N7_SC7P5T"
set tech(7.5T,cell_height)    "0.338"
set tech(7.5T,site_width)     "0.054"
set tech(7.5T,fillers)        "TSMC_N7_SC7P5T_FILL1 TSMC_N7_SC7P5T_FILL2 TSMC_N7_SC7P5T_FILL4 TSMC_N7_SC7P5T_FILL8"
set tech(7.5T,well_tap)       "TSMC_N7_SC7P5T_FILLTIE1"
set tech(7.5T,endcap)         "TSMC_N7_SC7P5T_ENDCAP1"
set tech(7.5T,decap)          "TSMC_N7_SC7P5T_DCAP4 TSMC_N7_SC7P5T_DCAP8"
set tech(7.5T,clock_buffers)  "tcbn07bwp7p5tsvt_CKBUF4 tcbn07bwp7p5tsvt_CKBUF8"
set tech(7.5T,clock_inverters) "tcbn07bwp7p5tsvt_CKINV4"
set tech(7.5T,hold_buffers)   "tcbn07bwp7p5tsvt_BUFFD1 tcbn07bwp7p5tsvt_BUFFD2 tcbn07bwp7p5tsvt_BUFFD4"
set tech(7.5T,delay_cells)    "tcbn07bwp7p5tsvt_DEL1 tcbn07bwp7p5tsvt_DEL2 tcbn07bwp7p5tsvt_DEL4"
set tech(7.5T,icg_cells)      "tcbn07bwp7p5tsvt_CKLNQD1 tcbn07bwp7p5tsvt_CKLNQD2 tcbn07bwp7p5tsvt_CKLNQD4"
set tech(7.5T,power_switch)   "tcbn07bwp7p5tsvt_HDRDWN1 tcbn07bwp7p5tsvt_HDRDWN2 tcbn07bwp7p5tsvt_HDRDWN4"
set tech(7.5T,isolation)      "tcbn07bwp7p5tsvt_ISOLAND1 tcbn07bwp7p5tsvt_ISOLOR1 tcbn07bwp7p5tsvt_ISOLAND2 tcbn07bwp7p5tsvt_ISOLOR2"
set tech(7.5T,level_shifter)  "tcbn07bwp7p5tsvt_LSDOWN1 tcbn07bwp7p5tsvt_LSUP1 tcbn07bwp7p5tsvt_LSDOWN2 tcbn07bwp7p5tsvt_LSUP2"
set tech(7.5T,tie_cells)      "tcbn07bwp7p5tsvt_TIEHI tcbn07bwp7p5tsvt_TIELO"
set tech(7.5T,dont_use)       "*D0BWP7P5T* *OPTHOLD* *DEL*"

# ── 9T Physical ──
set tech(9T,site)           "TSMC_N7_SC9T"
set tech(9T,cell_height)    "0.405"
set tech(9T,site_width)     "0.054"
set tech(9T,fillers)        "TSMC_N7_SC9T_FILL1 TSMC_N7_SC9T_FILL2 TSMC_N7_SC9T_FILL4 TSMC_N7_SC9T_FILL8 TSMC_N7_SC9T_FILL16"
set tech(9T,well_tap)       "TSMC_N7_SC9T_FILLTIE1"
set tech(9T,endcap)         "TSMC_N7_SC9T_ENDCAP1"
set tech(9T,decap)          "TSMC_N7_SC9T_DCAP4 TSMC_N7_SC9T_DCAP8"
set tech(9T,clock_buffers)  "tcbn07bwp9tsvt_CKBUF4 tcbn07bwp9tsvt_CKBUF8"
set tech(9T,clock_inverters) "tcbn07bwp9tsvt_CKINV4"
set tech(9T,hold_buffers)   "tcbn07bwp9tsvt_BUFFD1 tcbn07bwp9tsvt_BUFFD2 tcbn07bwp9tsvt_BUFFD4"
set tech(9T,delay_cells)    "tcbn07bwp9tsvt_DEL1 tcbn07bwp9tsvt_DEL2 tcbn07bwp9tsvt_DEL4"
set tech(9T,icg_cells)      "tcbn07bwp9tsvt_CKLNQD1 tcbn07bwp9tsvt_CKLNQD2 tcbn07bwp9tsvt_CKLNQD4"
set tech(9T,power_switch)   "tcbn07bwp9tsvt_HDRDWN1 tcbn07bwp9tsvt_HDRDWN2 tcbn07bwp9tsvt_HDRDWN4"
set tech(9T,isolation)      "tcbn07bwp9tsvt_ISOLAND1 tcbn07bwp9tsvt_ISOLOR1 tcbn07bwp9tsvt_ISOLAND2 tcbn07bwp9tsvt_ISOLOR2"
set tech(9T,level_shifter)  "tcbn07bwp9tsvt_LSDOWN1 tcbn07bwp9tsvt_LSUP1 tcbn07bwp9tsvt_LSDOWN2 tcbn07bwp9tsvt_LSUP2"
set tech(9T,tie_cells)      "tcbn07bwp9tsvt_TIEHI tcbn07bwp9tsvt_TIELO"
set tech(9T,dont_use)       "*D0BWP9T* *OPTHOLD* *DEL*"

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 8: LIBRARY SETS PER TRACK + PER PVT CORNER
# Categorized: stdcell timing (per track) + shared memory/io timing
# MMMC reads: tech($tech(track),lib,<corner>,timing)
# ═══════════════════════════════════════════════════════════════════════════════

set _T "$_R/Front_End/timing"

# ── Available corners ──
set tech(corners) {ss_0p72v_125c tt_0p80v_25c ff_0p88v_m40c}

# ── Shared timing libraries per corner (memory + IO — same for all tracks) ──
set tech(lib,ss_0p72v_125c,timing,memory)  [list "$_T/memory/ts1n07ss0p72v125c.lib"]
set tech(lib,ss_0p72v_125c,timing,io)      [list "$_T/io/tpbn07v_ss0p72v125c.lib"]
set tech(lib,tt_0p80v_25c,timing,memory)   [list "$_T/memory/ts1n07tt0p80v25c.lib"]
set tech(lib,tt_0p80v_25c,timing,io)       [list "$_T/io/tpbn07v_tt0p80v25c.lib"]
set tech(lib,ff_0p88v_m40c,timing,memory)  [list "$_T/memory/ts1n07ff0p88vm40c.lib"]
set tech(lib,ff_0p88v_m40c,timing,io)      [list "$_T/io/tpbn07v_ff0p88vm40c.lib"]

# ┌──────────────────────────────────────────────────────────────────────────┐
# │  6T STDCELL STDCELL TIMING LIBS PER CORNER                             │
# └──────────────────────────────────────────────────────────────────────────┘

# SS corners (setup-critical)
set tech(6T,lib,ss_0p72v_125c,timing,stdcell) [list \
    "$_T/stdcell/tcbn07bwp6tsvtss0p72v125c_ccs.lib" \
    "$_T/stdcell/tcbn07bwp6tlvtss0p72v125c_ccs.lib" \
    "$_T/stdcell/tcbn07bwp6tulvtss0p72v125c_ccs.lib" \
    "$_T/stdcell/tcbn07bwp6thvtss0p72v125c_ccs.lib" \
]

# TT corners (nominal)
set tech(6T,lib,tt_0p80v_25c,timing,stdcell) [list \
    "$_T/stdcell/tcbn07bwp6tsvttt0p80v25c_ccs.lib" \
    "$_T/stdcell/tcbn07bwp6tlvttt0p80v25c_ccs.lib" \
    "$_T/stdcell/tcbn07bwp6tulvttt0p80v25c_ccs.lib" \
    "$_T/stdcell/tcbn07bwp6thvttt0p80v25c_ccs.lib" \
]

# FF corners (hold-critical)
set tech(6T,lib,ff_0p88v_m40c,timing,stdcell) [list \
    "$_T/stdcell/tcbn07bwp6tsvtff0p88vm40c_ccs.lib" \
    "$_T/stdcell/tcbn07bwp6tlvtff0p88vm40c_ccs.lib" \
    "$_T/stdcell/tcbn07bwp6tulvtff0p88vm40c_ccs.lib" \
    "$_T/stdcell/tcbn07bwp6thvtff0p88vm40c_ccs.lib" \
]

# ┌──────────────────────────────────────────────────────────────────────────┐
# │  7.5T STDCELL STDCELL TIMING LIBS PER CORNER                           │
# └──────────────────────────────────────────────────────────────────────────┘

# SS corners (setup-critical)
set tech(7.5T,lib,ss_0p72v_125c,timing,stdcell) [list \
    "$_T/stdcell/tcbn07bwp7p5tsvtss0p72v125c_ccs.lib" \
    "$_T/stdcell/tcbn07bwp7p5tlvtss0p72v125c_ccs.lib" \
    "$_T/stdcell/tcbn07bwp7p5tulvtss0p72v125c_ccs.lib" \
    "$_T/stdcell/tcbn07bwp7p5thvtss0p72v125c_ccs.lib" \
]

# TT corners (nominal)
set tech(7.5T,lib,tt_0p80v_25c,timing,stdcell) [list \
    "$_T/stdcell/tcbn07bwp7p5tsvttt0p80v25c_ccs.lib" \
    "$_T/stdcell/tcbn07bwp7p5tlvttt0p80v25c_ccs.lib" \
    "$_T/stdcell/tcbn07bwp7p5tulvttt0p80v25c_ccs.lib" \
    "$_T/stdcell/tcbn07bwp7p5thvttt0p80v25c_ccs.lib" \
]

# FF corners (hold-critical)
set tech(7.5T,lib,ff_0p88v_m40c,timing,stdcell) [list \
    "$_T/stdcell/tcbn07bwp7p5tsvtff0p88vm40c_ccs.lib" \
    "$_T/stdcell/tcbn07bwp7p5tlvtff0p88vm40c_ccs.lib" \
    "$_T/stdcell/tcbn07bwp7p5tulvtff0p88vm40c_ccs.lib" \
    "$_T/stdcell/tcbn07bwp7p5thvtff0p88vm40c_ccs.lib" \
]

# ┌──────────────────────────────────────────────────────────────────────────┐
# │  9T STDCELL STDCELL TIMING LIBS PER CORNER                             │
# └──────────────────────────────────────────────────────────────────────────┘

# SS corners (setup-critical)
set tech(9T,lib,ss_0p72v_125c,timing,stdcell) [list \
    "$_T/stdcell/tcbn07bwp9tsvtss0p72v125c_ccs.lib" \
    "$_T/stdcell/tcbn07bwp9tlvtss0p72v125c_ccs.lib" \
    "$_T/stdcell/tcbn07bwp9tulvtss0p72v125c_ccs.lib" \
    "$_T/stdcell/tcbn07bwp9thvtss0p72v125c_ccs.lib" \
]

# TT corners (nominal)
set tech(9T,lib,tt_0p80v_25c,timing,stdcell) [list \
    "$_T/stdcell/tcbn07bwp9tsvttt0p80v25c_ccs.lib" \
    "$_T/stdcell/tcbn07bwp9tlvttt0p80v25c_ccs.lib" \
    "$_T/stdcell/tcbn07bwp9tulvttt0p80v25c_ccs.lib" \
    "$_T/stdcell/tcbn07bwp9thvttt0p80v25c_ccs.lib" \
]

# FF corners (hold-critical)
set tech(9T,lib,ff_0p88v_m40c,timing,stdcell) [list \
    "$_T/stdcell/tcbn07bwp9tsvtff0p88vm40c_ccs.lib" \
    "$_T/stdcell/tcbn07bwp9tlvtff0p88vm40c_ccs.lib" \
    "$_T/stdcell/tcbn07bwp9tulvtff0p88vm40c_ccs.lib" \
    "$_T/stdcell/tcbn07bwp9thvtff0p88vm40c_ccs.lib" \
]

# ┌──────────────────────────────────────────────────────────────────────────┐
# │  AUTO-BUILD COMBINED TIMING LISTS PER TRACK + CORNER                   │
# └──────────────────────────────────────────────────────────────────────────┘

foreach _t $tech(tracks_available) {
    foreach _c $tech(corners) {
        if {[info exists tech(${_t},lib,${_c},timing,stdcell)]} {
            set tech(${_t},lib,${_c},timing) [concat \
                $tech(${_t},lib,${_c},timing,stdcell) \
                $tech(lib,${_c},timing,memory) \
                $tech(lib,${_c},timing,io) \
            ]
        }
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 9: DESIGN RULES & ROUTING (shared — same for all tracks)
# ═══════════════════════════════════════════════════════════════════════════════

set tech(min_routing_layer) "M1"
set tech(max_routing_layer) "M11"
set tech(clock_routing_layer_min) "M4"
set tech(clock_routing_layer_max) "M9"

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 10: SIGNOFF, DRC & GDS
# ═══════════════════════════════════════════════════════════════════════════════

set tech(gds_layer_map_file)        "$_R/Back_End/layermap/tsmc7nm_layermap.map"
set tech(antenna_rule_file)         "$_R/Back_End/antenna/tsmc7nm_antenna.rules"
set tech(lib_cell_purpose_file)     ""
set tech(filler_sidefile)           ""
set tech(signal_em_constraint_file) ""
set tech(signal_em_constraint_format) "sigem"
set tech(stream_files_for_merge)    ""

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

# Alias: tech(lef,technology) → tech(lef_tech) (12 command files reference this)
set tech(lef,technology) $tech(lef_tech)

# Alias: tech(lib,timing) → nominal lib list for active track (STA/LEC command files)
if {[info exists tech(${_trk},lib_nom)]} {
    set tech(lib,timing) $tech(${_trk},lib_nom)
}

# Alias: tech(decap_cells) → track-specific decap (signoff command files)
if {[info exists tech(${_trk},decap)]} {
    set tech(decap_cells) $tech(${_trk},decap)
}

puts "INFO: $tech(process) tech config loaded — track=$tech(track), metal=$tech(metal_stack), libs=[llength $tech(${_trk},ndm)] NDMs"
