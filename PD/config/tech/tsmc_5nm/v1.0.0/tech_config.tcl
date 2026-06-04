#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow Technology Configuration — TSMC N5 (5nm FinFET)
# PURE DATA — no if/else, no source, no exit, no logic
# Engine (generate_setup.tcl) handles validation, sourcing, and assembly
# ═══════════════════════════════════════════════════════════════════════════════

# ── Technology Identity ──
set tech(node)        "5nm"
set tech(process)     "TSMC N5"
set tech(foundry)     "TSMC"
set tech(tracks_available) "5T 6T 7T"

# ── VT Variant Patterns ──
set tech(vt_variants_available) {svt lvt ulvt hvt}
set tech(vt_pattern,svt)  "*svt*"
set tech(vt_pattern,lvt)  "*lvt*"
set tech(vt_pattern,ulvt) "*ulvt*"
set tech(vt_pattern,hvt)  "*hvt*"

# ── LEF Tech File ──
# ── Tech LEF per track ──
set tech(5T,lef_tech) "$project(lib_root)/Back_End/lef/tsmc5nm_5t_tech.lef"
set tech(6T,lef_tech) "$project(lib_root)/Back_End/lef/tsmc5nm_6t_tech.lef"
set tech(7T,lef_tech) "$project(lib_root)/Back_End/lef/tsmc5nm_7t_tech.lef"

# ── Parasitic Extraction (per RC corner) ──
# Paths use project(lib_root) — set in project_config
# Metal count suffix resolved per metal_stack config (set by engine before this file)
set tech(tluplus_map) "$project(lib_root)/Back_End/rcx/tsmc5nm_tf_itf_tluplus.map"

set tech(rcx,rc_max,tluplus)   "$project(lib_root)/Back_End/rcx/tsmc5nm_1p${tech(metal_count)}m_Cmax.tluplus"
set tech(rcx,rc_max,nxtgrd)    "$project(lib_root)/Back_End/rcx/tsmc5nm_1p${tech(metal_count)}m_Cmax.nxtgrd"
set tech(rcx,rc_max,qrc)       "$project(lib_root)/Back_End/rcx/tsmc5nm_1p${tech(metal_count)}m_Cmax.qrcTechFile"

set tech(rcx,rc_typ,tluplus)   "$project(lib_root)/Back_End/rcx/tsmc5nm_1p${tech(metal_count)}m_Ctyp.tluplus"
set tech(rcx,rc_typ,nxtgrd)    "$project(lib_root)/Back_End/rcx/tsmc5nm_1p${tech(metal_count)}m_Ctyp.nxtgrd"
set tech(rcx,rc_typ,qrc)       "$project(lib_root)/Back_End/rcx/tsmc5nm_1p${tech(metal_count)}m_Ctyp.qrcTechFile"

set tech(rcx,rc_min,tluplus)   "$project(lib_root)/Back_End/rcx/tsmc5nm_1p${tech(metal_count)}m_Cmin.tluplus"
set tech(rcx,rc_min,nxtgrd)    "$project(lib_root)/Back_End/rcx/tsmc5nm_1p${tech(metal_count)}m_Cmin.nxtgrd"
set tech(rcx,rc_min,qrc)       "$project(lib_root)/Back_End/rcx/tsmc5nm_1p${tech(metal_count)}m_Cmin.qrcTechFile"

set tech(rcx,rc_max_cworst,tluplus) "$project(lib_root)/Back_End/rcx/tsmc5nm_1p${tech(metal_count)}m_Cmax.tluplus"
set tech(rcx,rc_max_cworst,nxtgrd)  "$project(lib_root)/Back_End/rcx/tsmc5nm_1p${tech(metal_count)}m_Cmax.nxtgrd"
set tech(rcx,rc_max_cworst,qrc)     "$project(lib_root)/Back_End/rcx/tsmc5nm_1p${tech(metal_count)}m_Cmax.qrcTechFile"

# ── Physical Cells: 5T ──
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

# ── Physical Cells: 6T ──
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

# ── Physical Cells: 7T ──
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

# ── Signoff, DRC & GDS ──
set tech(gds_layer_map_file)        "$project(lib_root)/Back_End/layermap/tsmc5nm_layermap.map"
set tech(antenna_rule_file)         "$project(lib_root)/Back_End/antenna/tsmc5nm_antenna.rules"
set tech(lib_cell_purpose_file)     ""
set tech(filler_sidefile)           ""
set tech(signal_em_constraint_file) ""
set tech(signal_em_constraint_format) "sigem"
set tech(stream_files_for_merge)    ""
