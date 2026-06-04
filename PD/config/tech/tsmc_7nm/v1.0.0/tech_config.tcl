#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow Technology Configuration — TSMC N7 (7nm FinFET)
# PURE DATA — no if/else, no source, no exit, no logic
# Engine (generate_setup.tcl) handles validation, sourcing, and assembly
# ═══════════════════════════════════════════════════════════════════════════════

# ── Technology Identity ──
set tech(node)        "7nm"
set tech(process)     "TSMC N7"
set tech(foundry)     "TSMC"
set tech(tracks_available) "6T 7.5T 9T"

# ── VT Variant Patterns ──
set tech(vt_variants_available) {svt lvt ulvt hvt}
set tech(vt_pattern,svt)  "*svt*"
set tech(vt_pattern,lvt)  "*lvt*"
set tech(vt_pattern,ulvt) "*ulvt*"
set tech(vt_pattern,hvt)  "*hvt*"

# ── LEF Tech File ──
# ── Tech LEF per track ──
set tech(6T,lef_tech) "$project(lib_root)/Back_End/lef/tsmc7nm_6t_tech.lef"
set tech(7.5T,lef_tech) "$project(lib_root)/Back_End/lef/tsmc7nm_7p5t_tech.lef"
set tech(9T,lef_tech) "$project(lib_root)/Back_End/lef/tsmc7nm_9t_tech.lef"

# ── Parasitic Extraction (per RC corner) ──
# Paths use project(lib_root) — set in project_config
# Metal count suffix resolved per metal_stack config (set by engine before this file)
set tech(tluplus_map) "$project(lib_root)/Back_End/rcx/tsmc7nm_tf_itf_tluplus.map"

set tech(rcx,rc_max,tluplus)   "$project(lib_root)/Back_End/rcx/tsmc7nm_1p${tech(metal_count)}m_Cmax.tluplus"
set tech(rcx,rc_max,nxtgrd)    "$project(lib_root)/Back_End/rcx/tsmc7nm_1p${tech(metal_count)}m_Cmax.nxtgrd"
set tech(rcx,rc_max,qrc)       "$project(lib_root)/Back_End/rcx/tsmc7nm_1p${tech(metal_count)}m_Cmax.qrcTechFile"

set tech(rcx,rc_typ,tluplus)   "$project(lib_root)/Back_End/rcx/tsmc7nm_1p${tech(metal_count)}m_Ctyp.tluplus"
set tech(rcx,rc_typ,nxtgrd)    "$project(lib_root)/Back_End/rcx/tsmc7nm_1p${tech(metal_count)}m_Ctyp.nxtgrd"
set tech(rcx,rc_typ,qrc)       "$project(lib_root)/Back_End/rcx/tsmc7nm_1p${tech(metal_count)}m_Ctyp.qrcTechFile"

set tech(rcx,rc_min,tluplus)   "$project(lib_root)/Back_End/rcx/tsmc7nm_1p${tech(metal_count)}m_Cmin.tluplus"
set tech(rcx,rc_min,nxtgrd)    "$project(lib_root)/Back_End/rcx/tsmc7nm_1p${tech(metal_count)}m_Cmin.nxtgrd"
set tech(rcx,rc_min,qrc)       "$project(lib_root)/Back_End/rcx/tsmc7nm_1p${tech(metal_count)}m_Cmin.qrcTechFile"

set tech(rcx,rc_max_cworst,tluplus) "$project(lib_root)/Back_End/rcx/tsmc7nm_1p${tech(metal_count)}m_Cmax.tluplus"
set tech(rcx,rc_max_cworst,nxtgrd)  "$project(lib_root)/Back_End/rcx/tsmc7nm_1p${tech(metal_count)}m_Cmax.nxtgrd"
set tech(rcx,rc_max_cworst,qrc)     "$project(lib_root)/Back_End/rcx/tsmc7nm_1p${tech(metal_count)}m_Cmax.qrcTechFile"

# ── Physical Cells: 6T ──
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

# ── Physical Cells: 7.5T ──
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

# ── Physical Cells: 9T ──
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

# ── Signoff, DRC & GDS ──
set tech(gds_layer_map_file)        "$project(lib_root)/Back_End/layermap/tsmc7nm_layermap.map"
set tech(antenna_rule_file)         "$project(lib_root)/Back_End/antenna/tsmc7nm_antenna.rules"
set tech(lib_cell_purpose_file)     ""
set tech(filler_sidefile)           ""
set tech(signal_em_constraint_file) ""
set tech(signal_em_constraint_format) "sigem"
set tech(stream_files_for_merge)    ""
