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

set tech(lib_root) "/tmp/test_libs/tsmc_5nm"
set _R "$tech(lib_root)"

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 4: NDM LIBRARIES
# Categorized: stdcell (per track) + memory/io/analog/hierarchical (shared)
# Command files read: tech($tech(track),ndm)
# ═══════════════════════════════════════════════════════════════════════════════

# ── Stdcell NDMs per track (only these change with track) ──
set tech(5T,ndm,stdcell) [list \
    "$_R/Back_End/ndm/tcbn05bwp5tsvt.ndm" \
    "$_R/Back_End/ndm/tcbn05bwp5tlvt.ndm" \
    "$_R/Back_End/ndm/tcbn05bwp5tulvt.ndm" \
    "$_R/Back_End/ndm/tcbn05bwp5thvt.ndm" \
]
set tech(6T,ndm,stdcell) [list \
    "$_R/Back_End/ndm/tcbn05bwp6tsvt.ndm" \
    "$_R/Back_End/ndm/tcbn05bwp6tlvt.ndm" \
    "$_R/Back_End/ndm/tcbn05bwp6tulvt.ndm" \
    "$_R/Back_End/ndm/tcbn05bwp6thvt.ndm" \
]
set tech(7T,ndm,stdcell) [list \
    "$_R/Back_End/ndm/tcbn05bwp7tsvt.ndm" \
    "$_R/Back_End/ndm/tcbn05bwp7tlvt.ndm" \
    "$_R/Back_End/ndm/tcbn05bwp7tulvt.ndm" \
    "$_R/Back_End/ndm/tcbn05bwp7thvt.ndm" \
]

# ── Shared NDMs (same for all tracks — define once) ──
set tech(ndm,memory)       [list "$_R/Back_End/ndm/ts1n05_memory.ndm"]
set tech(ndm,io)           [list "$_R/Back_End/ndm/tpbn05v_io.ndm"]
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
set tech(5T,db,stdcell) [list \
    "$_R/Front_End/timing/stdcell/tcbn05bwp5tsvttt0p70v25c.db" \
    "$_R/Front_End/timing/stdcell/tcbn05bwp5tlvttt0p70v25c.db" \
    "$_R/Front_End/timing/stdcell/tcbn05bwp5tulvttt0p70v25c.db" \
    "$_R/Front_End/timing/stdcell/tcbn05bwp5thvttt0p70v25c.db" \
]
set tech(6T,db,stdcell) [list \
    "$_R/Front_End/timing/stdcell/tcbn05bwp6tsvttt0p70v25c.db" \
    "$_R/Front_End/timing/stdcell/tcbn05bwp6tlvttt0p70v25c.db" \
    "$_R/Front_End/timing/stdcell/tcbn05bwp6tulvttt0p70v25c.db" \
    "$_R/Front_End/timing/stdcell/tcbn05bwp6thvttt0p70v25c.db" \
]
set tech(7T,db,stdcell) [list \
    "$_R/Front_End/timing/stdcell/tcbn05bwp7tsvttt0p70v25c.db" \
    "$_R/Front_End/timing/stdcell/tcbn05bwp7tlvttt0p70v25c.db" \
    "$_R/Front_End/timing/stdcell/tcbn05bwp7tulvttt0p70v25c.db" \
    "$_R/Front_End/timing/stdcell/tcbn05bwp7thvttt0p70v25c.db" \
]

# ── Shared DBs ──
set tech(db,memory) [list "$_R/Front_End/timing/memory/ts1n05tt0p70v25c.db"]
set tech(db,io)     [list "$_R/Front_End/timing/io/tpbn05v_tt0p70v25c.db"]

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
set tech(5T,lib_nom,stdcell) [list \
    "$_R/Front_End/timing/stdcell/tcbn05bwp5tsvttt0p70v25c_ccs.lib" \
    "$_R/Front_End/timing/stdcell/tcbn05bwp5tlvttt0p70v25c_ccs.lib" \
    "$_R/Front_End/timing/stdcell/tcbn05bwp5tulvttt0p70v25c_ccs.lib" \
    "$_R/Front_End/timing/stdcell/tcbn05bwp5thvttt0p70v25c_ccs.lib" \
]
set tech(6T,lib_nom,stdcell) [list \
    "$_R/Front_End/timing/stdcell/tcbn05bwp6tsvttt0p70v25c_ccs.lib" \
    "$_R/Front_End/timing/stdcell/tcbn05bwp6tlvttt0p70v25c_ccs.lib" \
    "$_R/Front_End/timing/stdcell/tcbn05bwp6tulvttt0p70v25c_ccs.lib" \
    "$_R/Front_End/timing/stdcell/tcbn05bwp6thvttt0p70v25c_ccs.lib" \
]
set tech(7T,lib_nom,stdcell) [list \
    "$_R/Front_End/timing/stdcell/tcbn05bwp7tsvttt0p70v25c_ccs.lib" \
    "$_R/Front_End/timing/stdcell/tcbn05bwp7tlvttt0p70v25c_ccs.lib" \
    "$_R/Front_End/timing/stdcell/tcbn05bwp7tulvttt0p70v25c_ccs.lib" \
    "$_R/Front_End/timing/stdcell/tcbn05bwp7thvttt0p70v25c_ccs.lib" \
]

# ── Shared nominal libs ──
set tech(lib_nom,memory) [list "$_R/Front_End/timing/memory/ts1n05tt0p70v25c.lib"]
set tech(lib_nom,io)     [list "$_R/Front_End/timing/io/tpbn05v_tt0p70v25c.lib"]

# ── Auto-build combined nominal lib list per track ──
foreach _t $tech(tracks_available) {
    set tech(${_t},lib_nom) [concat $tech(${_t},lib_nom,stdcell) $tech(lib_nom,memory) $tech(lib_nom,io)]
}

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 5: LEF FILES
# Categorized: stdcell (per track) + memory/io (shared)
# Command files read: tech($tech(track),lef)
# ═══════════════════════════════════════════════════════════════════════════════

set tech(lef_tech) "$_R/Back_End/lef/tsmc5nm_tech.lef"

# ── Stdcell LEFs per track ──
set tech(5T,lef,stdcell) [list \
    "$_R/Back_End/lef/tcbn05bwp5tsvt.lef" \
    "$_R/Back_End/lef/tcbn05bwp5tlvt.lef" \
    "$_R/Back_End/lef/tcbn05bwp5tulvt.lef" \
    "$_R/Back_End/lef/tcbn05bwp5thvt.lef" \
]
set tech(6T,lef,stdcell) [list \
    "$_R/Back_End/lef/tcbn05bwp6tsvt.lef" \
    "$_R/Back_End/lef/tcbn05bwp6tlvt.lef" \
    "$_R/Back_End/lef/tcbn05bwp6tulvt.lef" \
    "$_R/Back_End/lef/tcbn05bwp6thvt.lef" \
]
set tech(7T,lef,stdcell) [list \
    "$_R/Back_End/lef/tcbn05bwp7tsvt.lef" \
    "$_R/Back_End/lef/tcbn05bwp7tlvt.lef" \
    "$_R/Back_End/lef/tcbn05bwp7tulvt.lef" \
    "$_R/Back_End/lef/tcbn05bwp7thvt.lef" \
]

# ── Shared LEFs ──
set tech(lef,memory) [list "$_R/Back_End/lef/ts1n05_memory.lef"]
set tech(lef,io)     [list "$_R/Back_End/lef/tpbn05v_io.lef"]

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
set tech(tluplus_map) "$_R/Back_End/rcx/tsmc5nm_tf_itf_tluplus.map"

# ── Per RC corner: Synopsys TLU+, nxtgrd, Cadence QRC ──
set tech(rcx,rc_max,tluplus)   "$_R/Back_End/rcx/tsmc5nm_1p13m_Cmax.tluplus"
set tech(rcx,rc_max,nxtgrd)    "$_R/Back_End/rcx/tsmc5nm_1p13m_Cmax.nxtgrd"
set tech(rcx,rc_max,qrc)       "$_R/Back_End/rcx/tsmc5nm_1p13m_Cmax.qrcTechFile"

set tech(rcx,rc_typ,tluplus)   "$_R/Back_End/rcx/tsmc5nm_1p13m_Ctyp.tluplus"
set tech(rcx,rc_typ,nxtgrd)    "$_R/Back_End/rcx/tsmc5nm_1p13m_Ctyp.nxtgrd"
set tech(rcx,rc_typ,qrc)       "$_R/Back_End/rcx/tsmc5nm_1p13m_Ctyp.qrcTechFile"

set tech(rcx,rc_min,tluplus)   "$_R/Back_End/rcx/tsmc5nm_1p13m_Cmin.tluplus"
set tech(rcx,rc_min,nxtgrd)    "$_R/Back_End/rcx/tsmc5nm_1p13m_Cmin.nxtgrd"
set tech(rcx,rc_min,qrc)       "$_R/Back_End/rcx/tsmc5nm_1p13m_Cmin.qrcTechFile"

set tech(rcx,rc_max_cworst,tluplus) "$_R/Back_End/rcx/tsmc5nm_1p13m_Cmax.tluplus"
set tech(rcx,rc_max_cworst,nxtgrd)  "$_R/Back_End/rcx/tsmc5nm_1p13m_Cmax.nxtgrd"
set tech(rcx,rc_max_cworst,qrc)     "$_R/Back_End/rcx/tsmc5nm_1p13m_Cmax.qrcTechFile"

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 7: PHYSICAL CELLS (per track — site, fillers, CTS, tap, endcap)
# Command files read: tech($tech(track),site), tech($tech(track),fillers), etc.
# ═══════════════════════════════════════════════════════════════════════════════

# ── 5T Physical ──
set tech(5T,site)           "TSMC_N5_SC5T"
set tech(5T,cell_height)    "0.216"
set tech(5T,site_width)     "0.051"
set tech(5T,fillers)        "TSMC_N5_SC5T_FILL1 TSMC_N5_SC5T_FILL2 TSMC_N5_SC5T_FILL4 TSMC_N5_SC5T_FILL8"
set tech(5T,well_tap)       "TSMC_N5_SC5T_FILLTIE1"
set tech(5T,endcap)         "TSMC_N5_SC5T_ENDCAP1"
set tech(5T,decap)          "TSMC_N5_SC5T_DCAP4 TSMC_N5_SC5T_DCAP8"
set tech(5T,clock_buffers)  "tcbn05bwp5tsvt_CKBUF4 tcbn05bwp5tsvt_CKBUF8"
set tech(5T,clock_inverters) "tcbn05bwp5tsvt_CKINV4 tcbn05bwp5tsvt_CKINV8"
set tech(5T,hold_buffers)   "tcbn05bwp5tsvt_BUFFD1 tcbn05bwp5tsvt_BUFFD2 tcbn05bwp5tsvt_BUFFD4"
set tech(5T,delay_cells)    "tcbn05bwp5tsvt_DEL1 tcbn05bwp5tsvt_DEL2 tcbn05bwp5tsvt_DEL4"
set tech(5T,icg_cells)      "tcbn05bwp5tsvt_CKLNQD1 tcbn05bwp5tsvt_CKLNQD2 tcbn05bwp5tsvt_CKLNQD4"
set tech(5T,power_switch)   "tcbn05bwp5tsvt_HDRDWN1 tcbn05bwp5tsvt_HDRDWN2 tcbn05bwp5tsvt_HDRDWN4"
set tech(5T,isolation)      "tcbn05bwp5tsvt_ISOLAND1 tcbn05bwp5tsvt_ISOLOR1 tcbn05bwp5tsvt_ISOLAND2 tcbn05bwp5tsvt_ISOLOR2"
set tech(5T,level_shifter)  "tcbn05bwp5tsvt_LSDOWN1 tcbn05bwp5tsvt_LSUP1 tcbn05bwp5tsvt_LSDOWN2 tcbn05bwp5tsvt_LSUP2"
set tech(5T,tie_cells)      "tcbn05bwp5tsvt_TIEHI tcbn05bwp5tsvt_TIELO"
set tech(5T,dont_use)       "*D0BWP5T* *OPTHOLD* *DEL*"

# ── 6T Physical ──
set tech(6T,site)           "TSMC_N5_SC6T"
set tech(6T,cell_height)    "0.270"
set tech(6T,site_width)     "0.051"
set tech(6T,fillers)        "TSMC_N5_SC6T_FILL1 TSMC_N5_SC6T_FILL2 TSMC_N5_SC6T_FILL4 TSMC_N5_SC6T_FILL8"
set tech(6T,well_tap)       "TSMC_N5_SC6T_FILLTIE1"
set tech(6T,endcap)         "TSMC_N5_SC6T_ENDCAP1"
set tech(6T,decap)          "TSMC_N5_SC6T_DCAP4 TSMC_N5_SC6T_DCAP8"
set tech(6T,clock_buffers)  "tcbn05bwp6tsvt_CKBUF4 tcbn05bwp6tsvt_CKBUF8"
set tech(6T,clock_inverters) "tcbn05bwp6tsvt_CKINV4 tcbn05bwp6tsvt_CKINV8"
set tech(6T,hold_buffers)   "tcbn05bwp6tsvt_BUFFD1 tcbn05bwp6tsvt_BUFFD2 tcbn05bwp6tsvt_BUFFD4"
set tech(6T,delay_cells)    "tcbn05bwp6tsvt_DEL1 tcbn05bwp6tsvt_DEL2 tcbn05bwp6tsvt_DEL4"
set tech(6T,icg_cells)      "tcbn05bwp6tsvt_CKLNQD1 tcbn05bwp6tsvt_CKLNQD2 tcbn05bwp6tsvt_CKLNQD4"
set tech(6T,power_switch)   "tcbn05bwp6tsvt_HDRDWN1 tcbn05bwp6tsvt_HDRDWN2 tcbn05bwp6tsvt_HDRDWN4"
set tech(6T,isolation)      "tcbn05bwp6tsvt_ISOLAND1 tcbn05bwp6tsvt_ISOLOR1 tcbn05bwp6tsvt_ISOLAND2 tcbn05bwp6tsvt_ISOLOR2"
set tech(6T,level_shifter)  "tcbn05bwp6tsvt_LSDOWN1 tcbn05bwp6tsvt_LSUP1 tcbn05bwp6tsvt_LSDOWN2 tcbn05bwp6tsvt_LSUP2"
set tech(6T,tie_cells)      "tcbn05bwp6tsvt_TIEHI tcbn05bwp6tsvt_TIELO"
set tech(6T,dont_use)       "*D0BWP6T* *OPTHOLD* *DEL*"

# ── 7T Physical ──
set tech(7T,site)           "TSMC_N5_SC7T"
set tech(7T,cell_height)    "0.324"
set tech(7T,site_width)     "0.051"
set tech(7T,fillers)        "TSMC_N5_SC7T_FILL1 TSMC_N5_SC7T_FILL2 TSMC_N5_SC7T_FILL4 TSMC_N5_SC7T_FILL8"
set tech(7T,well_tap)       "TSMC_N5_SC7T_FILLTIE1"
set tech(7T,endcap)         "TSMC_N5_SC7T_ENDCAP1"
set tech(7T,decap)          "TSMC_N5_SC7T_DCAP4 TSMC_N5_SC7T_DCAP8"
set tech(7T,clock_buffers)  "tcbn05bwp7tsvt_CKBUF4 tcbn05bwp7tsvt_CKBUF8"
set tech(7T,clock_inverters) "tcbn05bwp7tsvt_CKINV4 tcbn05bwp7tsvt_CKINV8"
set tech(7T,hold_buffers)   "tcbn05bwp7tsvt_BUFFD1 tcbn05bwp7tsvt_BUFFD2 tcbn05bwp7tsvt_BUFFD4"
set tech(7T,delay_cells)    "tcbn05bwp7tsvt_DEL1 tcbn05bwp7tsvt_DEL2 tcbn05bwp7tsvt_DEL4"
set tech(7T,icg_cells)      "tcbn05bwp7tsvt_CKLNQD1 tcbn05bwp7tsvt_CKLNQD2 tcbn05bwp7tsvt_CKLNQD4"
set tech(7T,power_switch)   "tcbn05bwp7tsvt_HDRDWN1 tcbn05bwp7tsvt_HDRDWN2 tcbn05bwp7tsvt_HDRDWN4"
set tech(7T,isolation)      "tcbn05bwp7tsvt_ISOLAND1 tcbn05bwp7tsvt_ISOLOR1 tcbn05bwp7tsvt_ISOLAND2 tcbn05bwp7tsvt_ISOLOR2"
set tech(7T,level_shifter)  "tcbn05bwp7tsvt_LSDOWN1 tcbn05bwp7tsvt_LSUP1 tcbn05bwp7tsvt_LSDOWN2 tcbn05bwp7tsvt_LSUP2"
set tech(7T,tie_cells)      "tcbn05bwp7tsvt_TIEHI tcbn05bwp7tsvt_TIELO"
set tech(7T,dont_use)       "*D0BWP7T* *OPTHOLD* *DEL*"

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 8: LIBRARY SETS PER TRACK + PER PVT CORNER
# Categorized: stdcell timing (per track) + shared memory/io timing
# MMMC reads: tech($tech(track),lib,<corner>,timing)
# ═══════════════════════════════════════════════════════════════════════════════

set _T "$_R/Front_End/timing"

# ── Available corners ──
set tech(corners) {ss_0p60v_125c ss_0p60v_m40c ss_0p70v_125c ss_0p70v_m40c tt_0p70v_25c tt_0p70v_125c tt_0p70v_m40c ff_0p75v_m40c ff_0p75v_25c ff_0p75v_125c}

# ── Shared timing libraries per corner (memory + IO — same for all tracks) ──
set tech(lib,ss_0p60v_125c,timing,memory)  [list "$_T/memory/ts1n05ss0p60v125c.lib"]
set tech(lib,ss_0p60v_125c,timing,io)      [list "$_T/io/tpbn05v_ss0p60v125c.lib"]
set tech(lib,ss_0p60v_m40c,timing,memory)  [list "$_T/memory/ts1n05ss0p60vm40c.lib"]
set tech(lib,ss_0p60v_m40c,timing,io)      [list "$_T/io/tpbn05v_ss0p60vm40c.lib"]
set tech(lib,ss_0p70v_125c,timing,memory)  [list "$_T/memory/ts1n05ss0p70v125c.lib"]
set tech(lib,ss_0p70v_125c,timing,io)      [list "$_T/io/tpbn05v_ss0p70v125c.lib"]
set tech(lib,ss_0p70v_m40c,timing,memory)  [list "$_T/memory/ts1n05ss0p70vm40c.lib"]
set tech(lib,ss_0p70v_m40c,timing,io)      [list "$_T/io/tpbn05v_ss0p70vm40c.lib"]
set tech(lib,tt_0p70v_25c,timing,memory)   [list "$_T/memory/ts1n05tt0p70v25c.lib"]
set tech(lib,tt_0p70v_25c,timing,io)       [list "$_T/io/tpbn05v_tt0p70v25c.lib"]
set tech(lib,tt_0p70v_125c,timing,memory)  [list "$_T/memory/ts1n05tt0p70v125c.lib"]
set tech(lib,tt_0p70v_125c,timing,io)      [list "$_T/io/tpbn05v_tt0p70v125c.lib"]
set tech(lib,tt_0p70v_m40c,timing,memory)  [list "$_T/memory/ts1n05tt0p70vm40c.lib"]
set tech(lib,tt_0p70v_m40c,timing,io)      [list "$_T/io/tpbn05v_tt0p70vm40c.lib"]
set tech(lib,ff_0p75v_m40c,timing,memory)  [list "$_T/memory/ts1n05ff0p75vm40c.lib"]
set tech(lib,ff_0p75v_m40c,timing,io)      [list "$_T/io/tpbn05v_ff0p75vm40c.lib"]
set tech(lib,ff_0p75v_25c,timing,memory)   [list "$_T/memory/ts1n05ff0p75v25c.lib"]
set tech(lib,ff_0p75v_25c,timing,io)       [list "$_T/io/tpbn05v_ff0p75v25c.lib"]
set tech(lib,ff_0p75v_125c,timing,memory)  [list "$_T/memory/ts1n05ff0p75v125c.lib"]
set tech(lib,ff_0p75v_125c,timing,io)      [list "$_T/io/tpbn05v_ff0p75v125c.lib"]

# ┌──────────────────────────────────────────────────────────────────────────┐
# │  5T STDCELL STDCELL TIMING LIBS PER CORNER                             │
# └──────────────────────────────────────────────────────────────────────────┘

# SS corners (setup-critical)
set tech(5T,lib,ss_0p60v_125c,timing,stdcell) [list \
    "$_T/stdcell/tcbn05bwp5tsvtss0p60v125c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp5tlvtss0p60v125c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp5tulvtss0p60v125c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp5thvtss0p60v125c_ccs.lib" \
]

set tech(5T,lib,ss_0p60v_m40c,timing,stdcell) [list \
    "$_T/stdcell/tcbn05bwp5tsvtss0p60vm40c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp5tlvtss0p60vm40c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp5tulvtss0p60vm40c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp5thvtss0p60vm40c_ccs.lib" \
]

set tech(5T,lib,ss_0p70v_125c,timing,stdcell) [list \
    "$_T/stdcell/tcbn05bwp5tsvtss0p70v125c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp5tlvtss0p70v125c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp5tulvtss0p70v125c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp5thvtss0p70v125c_ccs.lib" \
]

set tech(5T,lib,ss_0p70v_m40c,timing,stdcell) [list \
    "$_T/stdcell/tcbn05bwp5tsvtss0p70vm40c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp5tlvtss0p70vm40c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp5tulvtss0p70vm40c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp5thvtss0p70vm40c_ccs.lib" \
]

# TT corners (nominal)
set tech(5T,lib,tt_0p70v_25c,timing,stdcell) [list \
    "$_T/stdcell/tcbn05bwp5tsvttt0p70v25c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp5tlvttt0p70v25c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp5tulvttt0p70v25c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp5thvttt0p70v25c_ccs.lib" \
]

set tech(5T,lib,tt_0p70v_125c,timing,stdcell) [list \
    "$_T/stdcell/tcbn05bwp5tsvttt0p70v125c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp5tlvttt0p70v125c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp5tulvttt0p70v125c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp5thvttt0p70v125c_ccs.lib" \
]

set tech(5T,lib,tt_0p70v_m40c,timing,stdcell) [list \
    "$_T/stdcell/tcbn05bwp5tsvttt0p70vm40c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp5tlvttt0p70vm40c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp5tulvttt0p70vm40c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp5thvttt0p70vm40c_ccs.lib" \
]

# FF corners (hold-critical)
set tech(5T,lib,ff_0p75v_m40c,timing,stdcell) [list \
    "$_T/stdcell/tcbn05bwp5tsvtff0p75vm40c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp5tlvtff0p75vm40c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp5tulvtff0p75vm40c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp5thvtff0p75vm40c_ccs.lib" \
]

set tech(5T,lib,ff_0p75v_25c,timing,stdcell) [list \
    "$_T/stdcell/tcbn05bwp5tsvtff0p75v25c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp5tlvtff0p75v25c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp5tulvtff0p75v25c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp5thvtff0p75v25c_ccs.lib" \
]

set tech(5T,lib,ff_0p75v_125c,timing,stdcell) [list \
    "$_T/stdcell/tcbn05bwp5tsvtff0p75v125c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp5tlvtff0p75v125c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp5tulvtff0p75v125c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp5thvtff0p75v125c_ccs.lib" \
]

# ┌──────────────────────────────────────────────────────────────────────────┐
# │  6T STDCELL STDCELL TIMING LIBS PER CORNER                             │
# └──────────────────────────────────────────────────────────────────────────┘

# SS corners (setup-critical)
set tech(6T,lib,ss_0p60v_125c,timing,stdcell) [list \
    "$_T/stdcell/tcbn05bwp6tsvtss0p60v125c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp6tlvtss0p60v125c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp6tulvtss0p60v125c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp6thvtss0p60v125c_ccs.lib" \
]

set tech(6T,lib,ss_0p60v_m40c,timing,stdcell) [list \
    "$_T/stdcell/tcbn05bwp6tsvtss0p60vm40c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp6tlvtss0p60vm40c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp6tulvtss0p60vm40c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp6thvtss0p60vm40c_ccs.lib" \
]

set tech(6T,lib,ss_0p70v_125c,timing,stdcell) [list \
    "$_T/stdcell/tcbn05bwp6tsvtss0p70v125c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp6tlvtss0p70v125c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp6tulvtss0p70v125c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp6thvtss0p70v125c_ccs.lib" \
]

set tech(6T,lib,ss_0p70v_m40c,timing,stdcell) [list \
    "$_T/stdcell/tcbn05bwp6tsvtss0p70vm40c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp6tlvtss0p70vm40c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp6tulvtss0p70vm40c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp6thvtss0p70vm40c_ccs.lib" \
]

# TT corners (nominal)
set tech(6T,lib,tt_0p70v_25c,timing,stdcell) [list \
    "$_T/stdcell/tcbn05bwp6tsvttt0p70v25c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp6tlvttt0p70v25c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp6tulvttt0p70v25c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp6thvttt0p70v25c_ccs.lib" \
]

set tech(6T,lib,tt_0p70v_125c,timing,stdcell) [list \
    "$_T/stdcell/tcbn05bwp6tsvttt0p70v125c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp6tlvttt0p70v125c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp6tulvttt0p70v125c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp6thvttt0p70v125c_ccs.lib" \
]

set tech(6T,lib,tt_0p70v_m40c,timing,stdcell) [list \
    "$_T/stdcell/tcbn05bwp6tsvttt0p70vm40c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp6tlvttt0p70vm40c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp6tulvttt0p70vm40c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp6thvttt0p70vm40c_ccs.lib" \
]

# FF corners (hold-critical)
set tech(6T,lib,ff_0p75v_m40c,timing,stdcell) [list \
    "$_T/stdcell/tcbn05bwp6tsvtff0p75vm40c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp6tlvtff0p75vm40c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp6tulvtff0p75vm40c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp6thvtff0p75vm40c_ccs.lib" \
]

set tech(6T,lib,ff_0p75v_25c,timing,stdcell) [list \
    "$_T/stdcell/tcbn05bwp6tsvtff0p75v25c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp6tlvtff0p75v25c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp6tulvtff0p75v25c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp6thvtff0p75v25c_ccs.lib" \
]

set tech(6T,lib,ff_0p75v_125c,timing,stdcell) [list \
    "$_T/stdcell/tcbn05bwp6tsvtff0p75v125c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp6tlvtff0p75v125c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp6tulvtff0p75v125c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp6thvtff0p75v125c_ccs.lib" \
]

# ┌──────────────────────────────────────────────────────────────────────────┐
# │  7T STDCELL STDCELL TIMING LIBS PER CORNER                             │
# └──────────────────────────────────────────────────────────────────────────┘

# SS corners (setup-critical)
set tech(7T,lib,ss_0p60v_125c,timing,stdcell) [list \
    "$_T/stdcell/tcbn05bwp7tsvtss0p60v125c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp7tlvtss0p60v125c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp7tulvtss0p60v125c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp7thvtss0p60v125c_ccs.lib" \
]

set tech(7T,lib,ss_0p60v_m40c,timing,stdcell) [list \
    "$_T/stdcell/tcbn05bwp7tsvtss0p60vm40c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp7tlvtss0p60vm40c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp7tulvtss0p60vm40c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp7thvtss0p60vm40c_ccs.lib" \
]

set tech(7T,lib,ss_0p70v_125c,timing,stdcell) [list \
    "$_T/stdcell/tcbn05bwp7tsvtss0p70v125c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp7tlvtss0p70v125c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp7tulvtss0p70v125c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp7thvtss0p70v125c_ccs.lib" \
]

set tech(7T,lib,ss_0p70v_m40c,timing,stdcell) [list \
    "$_T/stdcell/tcbn05bwp7tsvtss0p70vm40c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp7tlvtss0p70vm40c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp7tulvtss0p70vm40c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp7thvtss0p70vm40c_ccs.lib" \
]

# TT corners (nominal)
set tech(7T,lib,tt_0p70v_25c,timing,stdcell) [list \
    "$_T/stdcell/tcbn05bwp7tsvttt0p70v25c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp7tlvttt0p70v25c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp7tulvttt0p70v25c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp7thvttt0p70v25c_ccs.lib" \
]

set tech(7T,lib,tt_0p70v_125c,timing,stdcell) [list \
    "$_T/stdcell/tcbn05bwp7tsvttt0p70v125c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp7tlvttt0p70v125c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp7tulvttt0p70v125c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp7thvttt0p70v125c_ccs.lib" \
]

set tech(7T,lib,tt_0p70v_m40c,timing,stdcell) [list \
    "$_T/stdcell/tcbn05bwp7tsvttt0p70vm40c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp7tlvttt0p70vm40c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp7tulvttt0p70vm40c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp7thvttt0p70vm40c_ccs.lib" \
]

# FF corners (hold-critical)
set tech(7T,lib,ff_0p75v_m40c,timing,stdcell) [list \
    "$_T/stdcell/tcbn05bwp7tsvtff0p75vm40c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp7tlvtff0p75vm40c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp7tulvtff0p75vm40c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp7thvtff0p75vm40c_ccs.lib" \
]

set tech(7T,lib,ff_0p75v_25c,timing,stdcell) [list \
    "$_T/stdcell/tcbn05bwp7tsvtff0p75v25c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp7tlvtff0p75v25c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp7tulvtff0p75v25c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp7thvtff0p75v25c_ccs.lib" \
]

set tech(7T,lib,ff_0p75v_125c,timing,stdcell) [list \
    "$_T/stdcell/tcbn05bwp7tsvtff0p75v125c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp7tlvtff0p75v125c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp7tulvtff0p75v125c_ccs.lib" \
    "$_T/stdcell/tcbn05bwp7thvtff0p75v125c_ccs.lib" \
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
set tech(max_routing_layer) "M12"
set tech(clock_routing_layer_min) "M4"
set tech(clock_routing_layer_max) "M10"

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 10: SIGNOFF, DRC & GDS
# ═══════════════════════════════════════════════════════════════════════════════

set tech(gds_layer_map_file)        "$_R/Back_End/layermap/tsmc5nm_layermap.map"
set tech(antenna_rule_file)         "$_R/Back_End/antenna/tsmc5nm_antenna.rules"
set tech(lib_cell_purpose_file)     ""
set tech(filler_sidefile)           ""
set tech(signal_em_constraint_file) ""
set tech(signal_em_constraint_format) "sigem"
set tech(stream_files_for_merge)    ""

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 11: BACKWARD COMPATIBILITY — old variable names -> new
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
