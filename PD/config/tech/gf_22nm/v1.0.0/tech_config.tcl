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
set tech(tracks_available) "9T 7.5T 8T"

# ── Metal Stack Options ──────────────────────────────────────────────────
# Each metal stack defines: layer count, layer types, tech file, TLU+/QRC
# Naming: <process>_<total_metals>M_<thick>Mx_<inter>Cx_<junc>Jx_<thin>Qx_<bump>
set tech(metal_stacks_available) {
    gf22naphlogl24uhf116a_10M_2Mx_5Cx_1Jx_2Qx_LB
    gf22naphlogl24uhf116a_11M_2Mx_6Cx_1Jx_2Qx_LB
    gf22naphlogl24uhf116a_8M_2Mx_3Cx_1Jx_2Qx_LB
    gf22naphlogl24uhf116a_9M_2Mx_4Cx_1Jx_2Qx_LB
}

# Active metal stack — set from project config, validated below
if {[info exists project(metal_stack)] && $project(metal_stack) ne ""} {
    set tech(metal_stack) $project(metal_stack)
} else {
    set tech(metal_stack) "gf22naphlogl24uhf116a_11M_2Mx_6Cx_1Jx_2Qx_LB"
}

# Validate metal stack
if {[lsearch $tech(metal_stacks_available) $tech(metal_stack)] < 0} {
    puts "ERROR: Invalid metal_stack '$tech(metal_stack)'"
    puts "ERROR: Available: $tech(metal_stacks_available)"
    error "Invalid metal stack configuration"
}

# ── Load per-metal-stack configuration ────────────────────────────────────
# Sources: metal_stack/<stack_name>.tcl
set _ms_file "$_tech_dir/metal_stack/$tech(metal_stack).tcl"
if {[file exists $_ms_file]} {
    source $_ms_file
} else {
    puts "WARNING: Metal stack config not found: $_ms_file — using defaults"
    # Defaults for the 11M stack
    set tech(metal_stack_label) "11M"
    set tech(metal_count) 11
    set tech(metal_layers) {M1 M2 M3 M4 M5 M6 M7 M8 M9 M10 M11}
}

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

set tech(lib_root) "/tmp/test_libs/gf_22nm"
set _R "$tech(lib_root)"

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 4: NDM LIBRARIES
# Categorized: stdcell (per track) + memory/io/analog/hierarchical (shared)
# Command files read: tech($tech(track),ndm)
# ═══════════════════════════════════════════════════════════════════════════════

# ── Stdcell NDMs per track (only these change with track) ──
set tech(9T,ndm,stdcell) [list \
    "$_R/Back_End/ndm/tcbn22cllbwp9tsvt.ndm" \
    "$_R/Back_End/ndm/tcbn22cllbwp9tlvt.ndm" \
    "$_R/Back_End/ndm/tcbn22cllbwp9tulvt.ndm" \
    "$_R/Back_End/ndm/tcbn22cllbwp9thvt.ndm" \
]
set tech(7.5T,ndm,stdcell) [list \
    "$_R/Back_End/ndm/tcbn22cllbwp7p5tsvt.ndm" \
    "$_R/Back_End/ndm/tcbn22cllbwp7p5tlvt.ndm" \
    "$_R/Back_End/ndm/tcbn22cllbwp7p5tulvt.ndm" \
    "$_R/Back_End/ndm/tcbn22cllbwp7p5thvt.ndm" \
]
set tech(8T,ndm,stdcell) [list \
    "$_R/Back_End/ndm/tcbn22cllbwp8tsvt.ndm" \
    "$_R/Back_End/ndm/tcbn22cllbwp8tlvt.ndm" \
    "$_R/Back_End/ndm/tcbn22cllbwp8tulvt.ndm" \
    "$_R/Back_End/ndm/tcbn22cllbwp8thvt.ndm" \
]

# ── Shared NDMs (same for all tracks — define once) ──
set tech(ndm,memory)       [list "$_R/Back_End/ndm/ts6n22cllhdlvt_memory.ndm"]
set tech(ndm,io)           [list "$_R/Back_End/ndm/tphn22v_io.ndm"]
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
set tech(9T,db,stdcell) [list \
    "$_R/Front_End/timing/stdcell/tcbn22cllbwp9tsvttt0p80v25c.db" \
    "$_R/Front_End/timing/stdcell/tcbn22cllbwp9tlvttt0p80v25c.db" \
    "$_R/Front_End/timing/stdcell/tcbn22cllbwp9tulvttt0p80v25c.db" \
    "$_R/Front_End/timing/stdcell/tcbn22cllbwp9thvttt0p80v25c.db" \
]
set tech(7.5T,db,stdcell) [list \
    "$_R/Front_End/timing/stdcell/tcbn22cllbwp7p5tsvttt0p80v25c.db" \
    "$_R/Front_End/timing/stdcell/tcbn22cllbwp7p5tlvttt0p80v25c.db" \
    "$_R/Front_End/timing/stdcell/tcbn22cllbwp7p5tulvttt0p80v25c.db" \
    "$_R/Front_End/timing/stdcell/tcbn22cllbwp7p5thvttt0p80v25c.db" \
]
set tech(8T,db,stdcell) [list \
    "$_R/Front_End/timing/stdcell/tcbn22cllbwp8tsvttt0p80v25c.db" \
    "$_R/Front_End/timing/stdcell/tcbn22cllbwp8tlvttt0p80v25c.db" \
    "$_R/Front_End/timing/stdcell/tcbn22cllbwp8tulvttt0p80v25c.db" \
    "$_R/Front_End/timing/stdcell/tcbn22cllbwp8thvttt0p80v25c.db" \
]

# ── Shared DBs ──
set tech(db,memory) [list "$_R/Front_End/timing/memory/ts6n22cllhdlvttt0p80v25c.db"]
set tech(db,io)     [list "$_R/Front_End/timing/io/tphn22v_tt0p80v25c.db"]

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
set tech(9T,lib_nom,stdcell) [list \
    "$_R/Front_End/timing/stdcell/tcbn22cllbwp9tsvttt0p80v25c_ccs.lib" \
    "$_R/Front_End/timing/stdcell/tcbn22cllbwp9tlvttt0p80v25c_ccs.lib" \
    "$_R/Front_End/timing/stdcell/tcbn22cllbwp9tulvttt0p80v25c_ccs.lib" \
    "$_R/Front_End/timing/stdcell/tcbn22cllbwp9thvttt0p80v25c_ccs.lib" \
]
set tech(7.5T,lib_nom,stdcell) [list \
    "$_R/Front_End/timing/stdcell/tcbn22cllbwp7p5tsvttt0p80v25c_ccs.lib" \
    "$_R/Front_End/timing/stdcell/tcbn22cllbwp7p5tlvttt0p80v25c_ccs.lib" \
    "$_R/Front_End/timing/stdcell/tcbn22cllbwp7p5tulvttt0p80v25c_ccs.lib" \
    "$_R/Front_End/timing/stdcell/tcbn22cllbwp7p5thvttt0p80v25c_ccs.lib" \
]
set tech(8T,lib_nom,stdcell) [list \
    "$_R/Front_End/timing/stdcell/tcbn22cllbwp8tsvttt0p80v25c_ccs.lib" \
    "$_R/Front_End/timing/stdcell/tcbn22cllbwp8tlvttt0p80v25c_ccs.lib" \
    "$_R/Front_End/timing/stdcell/tcbn22cllbwp8tulvttt0p80v25c_ccs.lib" \
    "$_R/Front_End/timing/stdcell/tcbn22cllbwp8thvttt0p80v25c_ccs.lib" \
]

# ── Shared nominal libs ──
set tech(lib_nom,memory) [list "$_R/Front_End/timing/memory/ts6n22cllhdlvttt0p80v25c.lib"]
set tech(lib_nom,io)     [list "$_R/Front_End/timing/io/tphn22v_tt0p80v25c.lib"]

# ── Auto-build combined nominal lib list per track ──
foreach _t $tech(tracks_available) {
    set tech(${_t},lib_nom) [concat $tech(${_t},lib_nom,stdcell) $tech(lib_nom,memory) $tech(lib_nom,io)]
}

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 5: LEF FILES
# Categorized: stdcell (per track) + memory/io (shared)
# Command files read: tech($tech(track),lef)
# ═══════════════════════════════════════════════════════════════════════════════

set tech(lef_tech) "$_R/Back_End/lef/gf22nm_tech.lef"

# ── Stdcell LEFs per track ──
set tech(9T,lef,stdcell) [list \
    "$_R/Back_End/lef/tcbn22cllbwp9tsvt.lef" \
    "$_R/Back_End/lef/tcbn22cllbwp9tlvt.lef" \
    "$_R/Back_End/lef/tcbn22cllbwp9tulvt.lef" \
    "$_R/Back_End/lef/tcbn22cllbwp9thvt.lef" \
]
set tech(7.5T,lef,stdcell) [list \
    "$_R/Back_End/lef/tcbn22cllbwp7p5tsvt.lef" \
    "$_R/Back_End/lef/tcbn22cllbwp7p5tlvt.lef" \
    "$_R/Back_End/lef/tcbn22cllbwp7p5tulvt.lef" \
    "$_R/Back_End/lef/tcbn22cllbwp7p5thvt.lef" \
]
set tech(8T,lef,stdcell) [list \
    "$_R/Back_End/lef/tcbn22cllbwp8tsvt.lef" \
    "$_R/Back_End/lef/tcbn22cllbwp8tlvt.lef" \
    "$_R/Back_End/lef/tcbn22cllbwp8tulvt.lef" \
    "$_R/Back_End/lef/tcbn22cllbwp8thvt.lef" \
]

# ── Shared LEFs ──
set tech(lef,memory) [list "$_R/Back_End/lef/ts6n22cllhdlvt_memory.lef"]
set tech(lef,io)     [list "$_R/Back_End/lef/tphn22v_io.lef"]

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
set tech(tluplus_map) "$_R/Back_End/rcx/gf22nm_tf_itf_tluplus.map"

# ── Per RC corner: Synopsys TLU+, nxtgrd, Cadence QRC ──
# Parasitic files are metal-stack-specific (1p11m, 1p10m, etc.)
set _ms_label "1p${tech(metal_count)}m"

set tech(rcx,rc_max,tluplus)   "$_R/Back_End/rcx/gf22nm_${_ms_label}_Cmax.tluplus"
set tech(rcx,rc_max,nxtgrd)    "$_R/Back_End/rcx/gf22nm_${_ms_label}_Cmax.nxtgrd"
set tech(rcx,rc_max,qrc)       "$_R/Back_End/rcx/gf22nm_${_ms_label}_Cmax.qrcTechFile"

set tech(rcx,rc_typ,tluplus)   "$_R/Back_End/rcx/gf22nm_${_ms_label}_Ctyp.tluplus"
set tech(rcx,rc_typ,nxtgrd)    "$_R/Back_End/rcx/gf22nm_${_ms_label}_Ctyp.nxtgrd"
set tech(rcx,rc_typ,qrc)       "$_R/Back_End/rcx/gf22nm_${_ms_label}_Ctyp.qrcTechFile"

set tech(rcx,rc_min,tluplus)   "$_R/Back_End/rcx/gf22nm_${_ms_label}_Cmin.tluplus"
set tech(rcx,rc_min,nxtgrd)    "$_R/Back_End/rcx/gf22nm_${_ms_label}_Cmin.nxtgrd"
set tech(rcx,rc_min,qrc)       "$_R/Back_End/rcx/gf22nm_${_ms_label}_Cmin.qrcTechFile"

set tech(rcx,rc_max_cworst,tluplus) "$_R/Back_End/rcx/gf22nm_${_ms_label}_Cmax.tluplus"
set tech(rcx,rc_max_cworst,nxtgrd)  "$_R/Back_End/rcx/gf22nm_${_ms_label}_Cmax.nxtgrd"
set tech(rcx,rc_max_cworst,qrc)     "$_R/Back_End/rcx/gf22nm_${_ms_label}_Cmax.qrcTechFile"

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 7: PHYSICAL CELLS (per track — site, fillers, CTS, tap, endcap)
# Command files read: tech($tech(track),site), tech($tech(track),fillers), etc.
# ═══════════════════════════════════════════════════════════════════════════════

# ── 9T Physical ──
set tech(9T,site)           "GF22FDX_SC9T"
set tech(9T,cell_height)    "0.810"
set tech(9T,site_width)     "0.114"
set tech(9T,fillers)        "GF22FDX_SC9T_SVT_FILL1 GF22FDX_SC9T_SVT_FILL2 GF22FDX_SC9T_SVT_FILL4 GF22FDX_SC9T_SVT_FILL8 GF22FDX_SC9T_SVT_FILL16 GF22FDX_SC9T_SVT_FILL32"
set tech(9T,well_tap)       "GF22FDX_SC9T_SVT_FILLTIE1"
set tech(9T,endcap)         "GF22FDX_SC9T_SVT_ENDCAP1"
set tech(9T,decap)          "GF22FDX_SC9T_SVT_DCAP4 GF22FDX_SC9T_SVT_DCAP8"
set tech(9T,clock_buffers)  "tcbn22cllbwp9tsvt_CKBUF4 tcbn22cllbwp9tsvt_CKBUF8 tcbn22cllbwp9tsvt_CKBUF16"
set tech(9T,clock_inverters) "tcbn22cllbwp9tsvt_CKINV4 tcbn22cllbwp9tsvt_CKINV8"
set tech(9T,hold_buffers)   "tcbn22cllbwp9tsvt_BUFFD1 tcbn22cllbwp9tsvt_BUFFD2 tcbn22cllbwp9tsvt_BUFFD4"
set tech(9T,delay_cells)    "tcbn22cllbwp9tsvt_DEL1 tcbn22cllbwp9tsvt_DEL2 tcbn22cllbwp9tsvt_DEL4"
set tech(9T,icg_cells)      "tcbn22cllbwp9tsvt_CKLNQD1 tcbn22cllbwp9tsvt_CKLNQD2 tcbn22cllbwp9tsvt_CKLNQD4 tcbn22cllbwp9tsvt_CKLNQD8"
set tech(9T,power_switch)   "tcbn22cllbwp9tsvt_HDRDWN1 tcbn22cllbwp9tsvt_HDRDWN2 tcbn22cllbwp9tsvt_HDRDWN4 tcbn22cllbwp9tsvt_HDRDWN8"
set tech(9T,isolation)      "tcbn22cllbwp9tsvt_ISOLAND1 tcbn22cllbwp9tsvt_ISOLOR1 tcbn22cllbwp9tsvt_ISOLAND2 tcbn22cllbwp9tsvt_ISOLOR2"
set tech(9T,level_shifter)  "tcbn22cllbwp9tsvt_LSDOWN1 tcbn22cllbwp9tsvt_LSUP1 tcbn22cllbwp9tsvt_LSDOWN2 tcbn22cllbwp9tsvt_LSUP2"
set tech(9T,tie_cells)      "tcbn22cllbwp9tsvt_TIEHI tcbn22cllbwp9tsvt_TIELO"
set tech(9T,dont_use)       "*D0BWP9T* *OPTHOLD* *DEL*"

# ── 7.5T Physical ──
set tech(7.5T,site)           "GF22FDX_SC7P5T"
set tech(7.5T,cell_height)    "0.675"
set tech(7.5T,site_width)     "0.116"
set tech(7.5T,fillers)        "GF22FDX_SC7P5T_SVT_FILL1 GF22FDX_SC7P5T_SVT_FILL2 GF22FDX_SC7P5T_SVT_FILL4 GF22FDX_SC7P5T_SVT_FILL8"
set tech(7.5T,well_tap)       "GF22FDX_SC7P5T_SVT_FILLTIE1"
set tech(7.5T,endcap)         "GF22FDX_SC7P5T_SVT_ENDCAP1"
set tech(7.5T,decap)          "GF22FDX_SC7P5T_SVT_DCAP4 GF22FDX_SC7P5T_SVT_DCAP8"
set tech(7.5T,clock_buffers)  "tcbn22cllbwp7p5tsvt_CKBUF4 tcbn22cllbwp7p5tsvt_CKBUF8"
set tech(7.5T,clock_inverters) "tcbn22cllbwp7p5tsvt_CKINV4 tcbn22cllbwp7p5tsvt_CKINV8"
set tech(7.5T,hold_buffers)   "tcbn22cllbwp7p5tsvt_BUFFD1 tcbn22cllbwp7p5tsvt_BUFFD2 tcbn22cllbwp7p5tsvt_BUFFD4"
set tech(7.5T,delay_cells)    "tcbn22cllbwp7p5tsvt_DEL1 tcbn22cllbwp7p5tsvt_DEL2 tcbn22cllbwp7p5tsvt_DEL4"
set tech(7.5T,icg_cells)      "tcbn22cllbwp7p5tsvt_CKLNQD1 tcbn22cllbwp7p5tsvt_CKLNQD2 tcbn22cllbwp7p5tsvt_CKLNQD4"
set tech(7.5T,power_switch)   "tcbn22cllbwp7p5tsvt_HDRDWN1 tcbn22cllbwp7p5tsvt_HDRDWN2 tcbn22cllbwp7p5tsvt_HDRDWN4"
set tech(7.5T,isolation)      "tcbn22cllbwp7p5tsvt_ISOLAND1 tcbn22cllbwp7p5tsvt_ISOLOR1 tcbn22cllbwp7p5tsvt_ISOLAND2 tcbn22cllbwp7p5tsvt_ISOLOR2"
set tech(7.5T,level_shifter)  "tcbn22cllbwp7p5tsvt_LSDOWN1 tcbn22cllbwp7p5tsvt_LSUP1 tcbn22cllbwp7p5tsvt_LSDOWN2 tcbn22cllbwp7p5tsvt_LSUP2"
set tech(7.5T,tie_cells)      "tcbn22cllbwp7p5tsvt_TIEHI tcbn22cllbwp7p5tsvt_TIELO"
set tech(7.5T,dont_use)       "*D0BWP7P5T* *OPTHOLD* *DEL*"

# ── 8T Physical ──
set tech(8T,site)           "GF22FDX_SC8T"
set tech(8T,cell_height)    "0.720"
set tech(8T,site_width)     "0.114"
set tech(8T,fillers)        "GF22FDX_SC8T_SVT_FILL1 GF22FDX_SC8T_SVT_FILL2 GF22FDX_SC8T_SVT_FILL4 GF22FDX_SC8T_SVT_FILL8"
set tech(8T,well_tap)       "GF22FDX_SC8T_SVT_FILLTIE1"
set tech(8T,endcap)         "GF22FDX_SC8T_SVT_ENDCAP1"
set tech(8T,decap)          "GF22FDX_SC8T_SVT_DCAP4 GF22FDX_SC8T_SVT_DCAP8"
set tech(8T,clock_buffers)  "tcbn22cllbwp8tsvt_CKBUF4 tcbn22cllbwp8tsvt_CKBUF8"
set tech(8T,clock_inverters) "tcbn22cllbwp8tsvt_CKINV4 tcbn22cllbwp8tsvt_CKINV8"
set tech(8T,hold_buffers)   "tcbn22cllbwp8tsvt_BUFFD1 tcbn22cllbwp8tsvt_BUFFD2 tcbn22cllbwp8tsvt_BUFFD4"
set tech(8T,delay_cells)    "tcbn22cllbwp8tsvt_DEL1 tcbn22cllbwp8tsvt_DEL2 tcbn22cllbwp8tsvt_DEL4"
set tech(8T,icg_cells)      "tcbn22cllbwp8tsvt_CKLNQD1 tcbn22cllbwp8tsvt_CKLNQD2 tcbn22cllbwp8tsvt_CKLNQD4"
set tech(8T,power_switch)   "tcbn22cllbwp8tsvt_HDRDWN1 tcbn22cllbwp8tsvt_HDRDWN2 tcbn22cllbwp8tsvt_HDRDWN4"
set tech(8T,isolation)      "tcbn22cllbwp8tsvt_ISOLAND1 tcbn22cllbwp8tsvt_ISOLOR1 tcbn22cllbwp8tsvt_ISOLAND2 tcbn22cllbwp8tsvt_ISOLOR2"
set tech(8T,level_shifter)  "tcbn22cllbwp8tsvt_LSDOWN1 tcbn22cllbwp8tsvt_LSUP1 tcbn22cllbwp8tsvt_LSDOWN2 tcbn22cllbwp8tsvt_LSUP2"
set tech(8T,tie_cells)      "tcbn22cllbwp8tsvt_TIEHI tcbn22cllbwp8tsvt_TIELO"
set tech(8T,dont_use)       "*D0BWP8T* *OPTHOLD* *DEL*"

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 8: LIBRARY SETS PER TRACK + PER PVT CORNER
# Categorized: stdcell timing (per track) + shared memory/io timing
# MMMC reads: tech($tech(track),lib,<corner>,timing)
# ═══════════════════════════════════════════════════════════════════════════════

set _T "$_R/Front_End/timing"

# ── Available corners ──
set tech(corners) {ss_0p76v_150c ss_0p76v_25c ss_0p76v_m40c ss_0p80v_150c ss_0p80v_25c tt_0p80v_25c tt_0p80v_150c tt_0p80v_m40c ff_0p84v_m40c ff_0p84v_25c ff_0p84v_150c ff_0p80v_m40c}

# ── Shared timing libraries per corner (memory + IO — same for all tracks) ──
set tech(lib,ss_0p76v_150c,timing,memory)  [list "$_T/memory/ts6n22cllhdlvtss0p76v150c.lib"]
set tech(lib,ss_0p76v_150c,timing,io)      [list "$_T/io/tphn22v_ss0p76v150c.lib"]
set tech(lib,ss_0p76v_25c,timing,memory)   [list "$_T/memory/ts6n22cllhdlvtss0p76v25c.lib"]
set tech(lib,ss_0p76v_25c,timing,io)       [list "$_T/io/tphn22v_ss0p76v25c.lib"]
set tech(lib,ss_0p76v_m40c,timing,memory)  [list "$_T/memory/ts6n22cllhdlvtss0p76vm40c.lib"]
set tech(lib,ss_0p76v_m40c,timing,io)      [list "$_T/io/tphn22v_ss0p76vm40c.lib"]
set tech(lib,ss_0p80v_150c,timing,memory)  [list "$_T/memory/ts6n22cllhdlvtss0p80v150c.lib"]
set tech(lib,ss_0p80v_150c,timing,io)      [list "$_T/io/tphn22v_ss0p80v150c.lib"]
set tech(lib,ss_0p80v_25c,timing,memory)   [list "$_T/memory/ts6n22cllhdlvtss0p80v25c.lib"]
set tech(lib,ss_0p80v_25c,timing,io)       [list "$_T/io/tphn22v_ss0p80v25c.lib"]
set tech(lib,tt_0p80v_25c,timing,memory)   [list "$_T/memory/ts6n22cllhdlvttt0p80v25c.lib"]
set tech(lib,tt_0p80v_25c,timing,io)       [list "$_T/io/tphn22v_tt0p80v25c.lib"]
set tech(lib,tt_0p80v_150c,timing,memory)  [list "$_T/memory/ts6n22cllhdlvttt0p80v150c.lib"]
set tech(lib,tt_0p80v_150c,timing,io)      [list "$_T/io/tphn22v_tt0p80v150c.lib"]
set tech(lib,tt_0p80v_m40c,timing,memory)  [list "$_T/memory/ts6n22cllhdlvttt0p80vm40c.lib"]
set tech(lib,tt_0p80v_m40c,timing,io)      [list "$_T/io/tphn22v_tt0p80vm40c.lib"]
set tech(lib,ff_0p84v_m40c,timing,memory)  [list "$_T/memory/ts6n22cllhdlvtff0p84vm40c.lib"]
set tech(lib,ff_0p84v_m40c,timing,io)      [list "$_T/io/tphn22v_ff0p84vm40c.lib"]
set tech(lib,ff_0p84v_25c,timing,memory)   [list "$_T/memory/ts6n22cllhdlvtff0p84v25c.lib"]
set tech(lib,ff_0p84v_25c,timing,io)       [list "$_T/io/tphn22v_ff0p84v25c.lib"]
set tech(lib,ff_0p84v_150c,timing,memory)  [list "$_T/memory/ts6n22cllhdlvtff0p84v150c.lib"]
set tech(lib,ff_0p84v_150c,timing,io)      [list "$_T/io/tphn22v_ff0p84v150c.lib"]
set tech(lib,ff_0p80v_m40c,timing,memory)  [list "$_T/memory/ts6n22cllhdlvtff0p80vm40c.lib"]
set tech(lib,ff_0p80v_m40c,timing,io)      [list "$_T/io/tphn22v_ff0p80vm40c.lib"]

# ┌──────────────────────────────────────────────────────────────────────────┐
# │  9T STDCELL STDCELL TIMING LIBS PER CORNER                             │
# └──────────────────────────────────────────────────────────────────────────┘

# SS corners (setup-critical)
set tech(9T,lib,ss_0p76v_150c,timing,stdcell) [list \
    "$_T/stdcell/tcbn22cllbwp9tsvtss0p76v150c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp9tlvtss0p76v150c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp9tulvtss0p76v150c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp9thvtss0p76v150c_ccs.lib" \
]

set tech(9T,lib,ss_0p76v_25c,timing,stdcell) [list \
    "$_T/stdcell/tcbn22cllbwp9tsvtss0p76v25c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp9tlvtss0p76v25c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp9tulvtss0p76v25c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp9thvtss0p76v25c_ccs.lib" \
]

set tech(9T,lib,ss_0p76v_m40c,timing,stdcell) [list \
    "$_T/stdcell/tcbn22cllbwp9tsvtss0p76vm40c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp9tlvtss0p76vm40c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp9tulvtss0p76vm40c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp9thvtss0p76vm40c_ccs.lib" \
]

set tech(9T,lib,ss_0p80v_150c,timing,stdcell) [list \
    "$_T/stdcell/tcbn22cllbwp9tsvtss0p80v150c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp9tlvtss0p80v150c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp9tulvtss0p80v150c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp9thvtss0p80v150c_ccs.lib" \
]

set tech(9T,lib,ss_0p80v_25c,timing,stdcell) [list \
    "$_T/stdcell/tcbn22cllbwp9tsvtss0p80v25c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp9tlvtss0p80v25c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp9tulvtss0p80v25c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp9thvtss0p80v25c_ccs.lib" \
]

# TT corners (nominal)
set tech(9T,lib,tt_0p80v_25c,timing,stdcell) [list \
    "$_T/stdcell/tcbn22cllbwp9tsvttt0p80v25c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp9tlvttt0p80v25c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp9tulvttt0p80v25c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp9thvttt0p80v25c_ccs.lib" \
]

set tech(9T,lib,tt_0p80v_150c,timing,stdcell) [list \
    "$_T/stdcell/tcbn22cllbwp9tsvttt0p80v150c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp9tlvttt0p80v150c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp9tulvttt0p80v150c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp9thvttt0p80v150c_ccs.lib" \
]

set tech(9T,lib,tt_0p80v_m40c,timing,stdcell) [list \
    "$_T/stdcell/tcbn22cllbwp9tsvttt0p80vm40c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp9tlvttt0p80vm40c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp9tulvttt0p80vm40c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp9thvttt0p80vm40c_ccs.lib" \
]

# FF corners (hold-critical)
set tech(9T,lib,ff_0p84v_m40c,timing,stdcell) [list \
    "$_T/stdcell/tcbn22cllbwp9tsvtff0p84vm40c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp9tlvtff0p84vm40c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp9tulvtff0p84vm40c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp9thvtff0p84vm40c_ccs.lib" \
]

set tech(9T,lib,ff_0p84v_25c,timing,stdcell) [list \
    "$_T/stdcell/tcbn22cllbwp9tsvtff0p84v25c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp9tlvtff0p84v25c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp9tulvtff0p84v25c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp9thvtff0p84v25c_ccs.lib" \
]

set tech(9T,lib,ff_0p84v_150c,timing,stdcell) [list \
    "$_T/stdcell/tcbn22cllbwp9tsvtff0p84v150c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp9tlvtff0p84v150c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp9tulvtff0p84v150c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp9thvtff0p84v150c_ccs.lib" \
]

set tech(9T,lib,ff_0p80v_m40c,timing,stdcell) [list \
    "$_T/stdcell/tcbn22cllbwp9tsvtff0p80vm40c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp9tlvtff0p80vm40c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp9tulvtff0p80vm40c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp9thvtff0p80vm40c_ccs.lib" \
]

# ┌──────────────────────────────────────────────────────────────────────────┐
# │  7.5T STDCELL STDCELL TIMING LIBS PER CORNER                           │
# └──────────────────────────────────────────────────────────────────────────┘

set tech(7.5T,lib,ss_0p76v_150c,timing,stdcell) [list \
    "$_T/stdcell/tcbn22cllbwp7p5tsvtss0p76v150c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp7p5tlvtss0p76v150c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp7p5tulvtss0p76v150c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp7p5thvtss0p76v150c_ccs.lib" \
]

set tech(7.5T,lib,tt_0p80v_25c,timing,stdcell) [list \
    "$_T/stdcell/tcbn22cllbwp7p5tsvttt0p80v25c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp7p5tlvttt0p80v25c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp7p5tulvttt0p80v25c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp7p5thvttt0p80v25c_ccs.lib" \
]

set tech(7.5T,lib,ff_0p84v_m40c,timing,stdcell) [list \
    "$_T/stdcell/tcbn22cllbwp7p5tsvtff0p84vm40c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp7p5tlvtff0p84vm40c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp7p5tulvtff0p84vm40c_ccs.lib" \
    "$_T/stdcell/tcbn22cllbwp7p5thvtff0p84vm40c_ccs.lib" \
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

# Routing layers — derived from metal stack config (can be overridden in project/user config)
if {![info exists tech(min_routing_layer)]}    { set tech(min_routing_layer)    "M2" }
if {![info exists tech(max_routing_layer)]}    { set tech(max_routing_layer)    [lindex $tech(metal_layers) end-1] }
if {![info exists tech(clock_routing_layer_min)]} { set tech(clock_routing_layer_min) "M4" }
if {![info exists tech(clock_routing_layer_max)]} { set tech(clock_routing_layer_max) "M8" }

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 10: BODY BIAS (GF 22FDX specific — FD-SOI advantage)
# ═══════════════════════════════════════════════════════════════════════════════

set tech(body_bias,fbb_voltage) "0.8"
set tech(body_bias,rbb_voltage) "-0.3"
set tech(body_bias,enabled) "true"

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 11: SIGNOFF, DRC & GDS
# ═══════════════════════════════════════════════════════════════════════════════

set tech(gds_layer_map_file)        "$_R/Back_End/layermap/gf22nm_layermap.map"
set tech(antenna_rule_file)         "$_R/Back_End/antenna/gf22nm_antenna.rules"
set tech(lib_cell_purpose_file)     ""
set tech(filler_sidefile)           ""
set tech(signal_em_constraint_file) ""
set tech(signal_em_constraint_format) "sigem"
set tech(stream_files_for_merge)    ""

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 12: BACKWARD COMPATIBILITY — old variable names → new
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

puts "INFO: $tech(process) tech config loaded — track=$tech(track), metal_stack=$tech(metal_stack) (${tech(metal_count)}M), libs=[llength $tech(${_trk},ndm)] NDMs"
