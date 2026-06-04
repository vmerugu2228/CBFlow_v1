#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow Technology Configuration — GlobalFoundries 22FDX (22nm FD-SOI)
# PURE DATA — no if/else, no source, no exit, no logic
# Engine (generate_setup.tcl) handles validation, sourcing, and assembly
# ═══════════════════════════════════════════════════════════════════════════════

# ── Technology Identity ──
set tech(node)        "22nm"
set tech(process)     "GF 22FDX"
set tech(foundry)     "GlobalFoundries"
set tech(tracks_available) "9T 7.5T 8T"

# ── VT Variant Patterns ──
set tech(vt_variants_available) {svt lvt ulvt hvt}
set tech(vt_pattern,svt)  "*svt*"
set tech(vt_pattern,lvt)  "*lvt*"
set tech(vt_pattern,ulvt) "*ulvt*"
set tech(vt_pattern,hvt)  "*hvt*"

# ── LEF Tech File ──
set tech(lef_tech) "$project(lib_root)/Back_End/lef/gf22nm_tech.lef"

# ── Parasitic Extraction (per RC corner) ──
# Paths use project(lib_root) — set in project_config
# Metal count suffix resolved per metal_stack config (set by engine before this file)
set tech(tluplus_map) "$project(lib_root)/Back_End/rcx/gf22nm_tf_itf_tluplus.map"

set tech(rcx,rc_max,tluplus)   "$project(lib_root)/Back_End/rcx/gf22nm_1p${tech(metal_count)}m_Cmax.tluplus"
set tech(rcx,rc_max,nxtgrd)    "$project(lib_root)/Back_End/rcx/gf22nm_1p${tech(metal_count)}m_Cmax.nxtgrd"
set tech(rcx,rc_max,qrc)       "$project(lib_root)/Back_End/rcx/gf22nm_1p${tech(metal_count)}m_Cmax.qrcTechFile"

set tech(rcx,rc_typ,tluplus)   "$project(lib_root)/Back_End/rcx/gf22nm_1p${tech(metal_count)}m_Ctyp.tluplus"
set tech(rcx,rc_typ,nxtgrd)    "$project(lib_root)/Back_End/rcx/gf22nm_1p${tech(metal_count)}m_Ctyp.nxtgrd"
set tech(rcx,rc_typ,qrc)       "$project(lib_root)/Back_End/rcx/gf22nm_1p${tech(metal_count)}m_Ctyp.qrcTechFile"

set tech(rcx,rc_min,tluplus)   "$project(lib_root)/Back_End/rcx/gf22nm_1p${tech(metal_count)}m_Cmin.tluplus"
set tech(rcx,rc_min,nxtgrd)    "$project(lib_root)/Back_End/rcx/gf22nm_1p${tech(metal_count)}m_Cmin.nxtgrd"
set tech(rcx,rc_min,qrc)       "$project(lib_root)/Back_End/rcx/gf22nm_1p${tech(metal_count)}m_Cmin.qrcTechFile"

set tech(rcx,rc_max_cworst,tluplus) "$project(lib_root)/Back_End/rcx/gf22nm_1p${tech(metal_count)}m_Cmax.tluplus"
set tech(rcx,rc_max_cworst,nxtgrd)  "$project(lib_root)/Back_End/rcx/gf22nm_1p${tech(metal_count)}m_Cmax.nxtgrd"
set tech(rcx,rc_max_cworst,qrc)     "$project(lib_root)/Back_End/rcx/gf22nm_1p${tech(metal_count)}m_Cmax.qrcTechFile"

# ── Physical Cells: 9T ──
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

# ── Physical Cells: 7.5T ──
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

# ── Physical Cells: 8T ──
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

# ── Body Bias (GF 22FDX specific — FD-SOI) ──
set tech(body_bias,fbb_voltage) "0.8"
set tech(body_bias,rbb_voltage) "-0.3"
set tech(body_bias,enabled) "true"

# ── Signoff, DRC & GDS ──
set tech(gds_layer_map_file)        "$project(lib_root)/Back_End/layermap/gf22nm_layermap.map"
set tech(antenna_rule_file)         "$project(lib_root)/Back_End/antenna/gf22nm_antenna.rules"
set tech(lib_cell_purpose_file)     ""
set tech(filler_sidefile)           ""
set tech(signal_em_constraint_file) ""
set tech(signal_em_constraint_format) "sigem"
set tech(stream_files_for_merge)    ""
