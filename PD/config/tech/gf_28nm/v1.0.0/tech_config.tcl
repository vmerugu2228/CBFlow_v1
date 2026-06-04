#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow Technology Configuration — GlobalFoundries 28SLP-E (28nm SLP Enhanced)
# PURE DATA — no if/else, no source, no exit, no logic
# Engine (generate_setup.tcl) handles validation, sourcing, and assembly
# ═══════════════════════════════════════════════════════════════════════════════

# ── Technology Identity ──
set tech(node)        "28nm"
set tech(process)     "GF 28SLP-E"
set tech(foundry)     "GlobalFoundries"
set tech(tracks_available) "7T 9T"

# ── Track Patterns (for library filename matching) ──
set tech(track_pattern,7T) "*sc7*"
set tech(track_pattern,9T) "*sc9*"

# ── VT Variant Patterns ──
set tech(vt_variants_available) {rvt lvt ulvt hvt}
set tech(vt_pattern,rvt)  "*rvt*"
set tech(vt_pattern,lvt)  "*lvt*"
set tech(vt_pattern,ulvt) "*ulvt*"
set tech(vt_pattern,hvt)  "*hvt*"

# ── LEF Tech File ──
set tech(lef_tech) "$project(lib_root)/Back_End/lef/gf28slpe_tech.lef"

# ── Parasitic Extraction (per RC corner) ──
# Paths use project(lib_root) — set in project_config
# Metal count suffix resolved per metal_stack config (set by engine before this file)
set tech(tluplus_map) "$project(lib_root)/Back_End/rcx/gf28slpe_tf_itf_tluplus.map"

set tech(rcx,rc_max,tluplus)   "$project(lib_root)/Back_End/rcx/gf28slpe_1p${tech(metal_count)}m_Cmax.tluplus"
set tech(rcx,rc_max,nxtgrd)    "$project(lib_root)/Back_End/rcx/gf28slpe_1p${tech(metal_count)}m_Cmax.nxtgrd"
set tech(rcx,rc_max,qrc)       "$project(lib_root)/Back_End/rcx/gf28slpe_1p${tech(metal_count)}m_Cmax.qrcTechFile"

set tech(rcx,rc_typ,tluplus)   "$project(lib_root)/Back_End/rcx/gf28slpe_1p${tech(metal_count)}m_Ctyp.tluplus"
set tech(rcx,rc_typ,nxtgrd)    "$project(lib_root)/Back_End/rcx/gf28slpe_1p${tech(metal_count)}m_Ctyp.nxtgrd"
set tech(rcx,rc_typ,qrc)       "$project(lib_root)/Back_End/rcx/gf28slpe_1p${tech(metal_count)}m_Ctyp.qrcTechFile"

set tech(rcx,rc_min,tluplus)   "$project(lib_root)/Back_End/rcx/gf28slpe_1p${tech(metal_count)}m_Cmin.tluplus"
set tech(rcx,rc_min,nxtgrd)    "$project(lib_root)/Back_End/rcx/gf28slpe_1p${tech(metal_count)}m_Cmin.nxtgrd"
set tech(rcx,rc_min,qrc)       "$project(lib_root)/Back_End/rcx/gf28slpe_1p${tech(metal_count)}m_Cmin.qrcTechFile"

set tech(rcx,rc_max_cworst,tluplus) "$project(lib_root)/Back_End/rcx/gf28slpe_1p${tech(metal_count)}m_Cmax.tluplus"
set tech(rcx,rc_max_cworst,nxtgrd)  "$project(lib_root)/Back_End/rcx/gf28slpe_1p${tech(metal_count)}m_Cmax.nxtgrd"
set tech(rcx,rc_max_cworst,qrc)     "$project(lib_root)/Back_End/rcx/gf28slpe_1p${tech(metal_count)}m_Cmax.qrcTechFile"

# ── Physical Cells: 7T ──
set tech(7T,site)           "GF28SLPE_SC7T"
set tech(7T,cell_height)    "1.008"
set tech(7T,site_width)     "0.140"
set tech(7T,fillers)        "sc7mcz_28slpe_base_rvt_c30_FILL1 sc7mcz_28slpe_base_rvt_c30_FILL2 sc7mcz_28slpe_base_rvt_c30_FILL4 sc7mcz_28slpe_base_rvt_c30_FILL8"
set tech(7T,well_tap)       "sc7mcz_28slpe_base_rvt_c30_FILLTIE1"
set tech(7T,endcap)         "sc7mcz_28slpe_base_rvt_c30_ENDCAP1"
set tech(7T,decap)          "sc7mcz_28slpe_base_rvt_c30_DCAP4 sc7mcz_28slpe_base_rvt_c30_DCAP8"
set tech(7T,clock_buffers)  "sc7mcz_28slpe_base_rvt_c30_CKBUF4 sc7mcz_28slpe_base_rvt_c30_CKBUF8 sc7mcz_28slpe_base_rvt_c30_CKBUF16"
set tech(7T,clock_inverters) "sc7mcz_28slpe_base_rvt_c30_CKINV4 sc7mcz_28slpe_base_rvt_c30_CKINV8"
set tech(7T,hold_buffers)   "sc7mcz_28slpe_base_rvt_c30_BUFFD1 sc7mcz_28slpe_base_rvt_c30_BUFFD2 sc7mcz_28slpe_base_rvt_c30_BUFFD4"
set tech(7T,delay_cells)    "sc7mcz_28slpe_base_rvt_c30_DEL1 sc7mcz_28slpe_base_rvt_c30_DEL2"
set tech(7T,icg_cells)      "sc7mcz_28slpe_base_rvt_c30_CKLNQD1 sc7mcz_28slpe_base_rvt_c30_CKLNQD2 sc7mcz_28slpe_base_rvt_c30_CKLNQD4"
set tech(7T,power_switch)   "sc7mcz_28slpe_base_rvt_c30_HDRDWN1 sc7mcz_28slpe_base_rvt_c30_HDRDWN2"
set tech(7T,isolation)      "sc7mcz_28slpe_base_rvt_c30_ISOLAND1 sc7mcz_28slpe_base_rvt_c30_ISOLOR1"
set tech(7T,level_shifter)  "sc7mcz_28slpe_base_rvt_c30_LSDOWN1 sc7mcz_28slpe_base_rvt_c30_LSUP1"
set tech(7T,tie_cells)      "sc7mcz_28slpe_base_rvt_c30_TIEHI sc7mcz_28slpe_base_rvt_c30_TIELO"
set tech(7T,dont_use)       "*D0BWP7T* *OPTHOLD* *DEL*"

# ── Physical Cells: 9T ──
set tech(9T,site)           "GF28SLPE_SC9T"
set tech(9T,cell_height)    "1.296"
set tech(9T,site_width)     "0.140"
set tech(9T,fillers)        "sc9mcz_28slpe_base_rvt_c30_FILL1 sc9mcz_28slpe_base_rvt_c30_FILL2 sc9mcz_28slpe_base_rvt_c30_FILL4 sc9mcz_28slpe_base_rvt_c30_FILL8"
set tech(9T,well_tap)       "sc9mcz_28slpe_base_rvt_c30_FILLTIE1"
set tech(9T,endcap)         "sc9mcz_28slpe_base_rvt_c30_ENDCAP1"
set tech(9T,decap)          "sc9mcz_28slpe_base_rvt_c30_DCAP4 sc9mcz_28slpe_base_rvt_c30_DCAP8"
set tech(9T,clock_buffers)  "sc9mcz_28slpe_base_rvt_c30_CKBUF4 sc9mcz_28slpe_base_rvt_c30_CKBUF8 sc9mcz_28slpe_base_rvt_c30_CKBUF16"
set tech(9T,clock_inverters) "sc9mcz_28slpe_base_rvt_c30_CKINV4 sc9mcz_28slpe_base_rvt_c30_CKINV8"
set tech(9T,hold_buffers)   "sc9mcz_28slpe_base_rvt_c30_BUFFD1 sc9mcz_28slpe_base_rvt_c30_BUFFD2 sc9mcz_28slpe_base_rvt_c30_BUFFD4"
set tech(9T,delay_cells)    "sc9mcz_28slpe_base_rvt_c30_DEL1 sc9mcz_28slpe_base_rvt_c30_DEL2"
set tech(9T,icg_cells)      "sc9mcz_28slpe_base_rvt_c30_CKLNQD1 sc9mcz_28slpe_base_rvt_c30_CKLNQD2 sc9mcz_28slpe_base_rvt_c30_CKLNQD4"
set tech(9T,power_switch)   "sc9mcz_28slpe_base_rvt_c30_HDRDWN1 sc9mcz_28slpe_base_rvt_c30_HDRDWN2"
set tech(9T,isolation)      "sc9mcz_28slpe_base_rvt_c30_ISOLAND1 sc9mcz_28slpe_base_rvt_c30_ISOLOR1"
set tech(9T,level_shifter)  "sc9mcz_28slpe_base_rvt_c30_LSDOWN1 sc9mcz_28slpe_base_rvt_c30_LSUP1"
set tech(9T,tie_cells)      "sc9mcz_28slpe_base_rvt_c30_TIEHI sc9mcz_28slpe_base_rvt_c30_TIELO"
set tech(9T,dont_use)       "*D0BWP9T* *OPTHOLD* *DEL*"

# ── Signoff, DRC & GDS ──
set tech(gds_layer_map_file)        "$project(lib_root)/Back_End/layermap/gf28slpe_layermap.map"
set tech(antenna_rule_file)         "$project(lib_root)/Back_End/antenna/gf28slpe_antenna.rules"
set tech(lib_cell_purpose_file)     ""
set tech(filler_sidefile)           ""
set tech(signal_em_constraint_file) ""
set tech(signal_em_constraint_format) "sigem"
set tech(stream_files_for_merge)    ""
