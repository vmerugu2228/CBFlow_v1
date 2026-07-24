#!/usr/bin/env tclsh
# =============================================================================
# CBflow Technology Configuration — GlobalFoundries 28SLP-E (28nm SLP Enhanced)
# PURE DATA — no if/else, no source, no exit, no logic
# Engine (generate_setup.tcl) handles validation, sourcing, and assembly
# =============================================================================

# ── Technology Identity ──
set tech(node)                   "28nm"
set tech(process)                "GF 28SLP-E"
set tech(foundry)                "GlobalFoundries"
set tech(tracks_available)       "7T 9T"
set tech(metal_stacks_available) "8M 9M 10M"

# ── Track Patterns (for library filename matching) ──
set tech(track_pattern,7T) "*sc7*"
set tech(track_pattern,9T) "*sc9*"

# ─────────────────────────────────────────────────────────────────────────────
# Physical Verification Runsets — foundry-provided SVRF / IC Validator decks
# Empty defaults; populate with foundry paths for site-wide use, or override
# per-run via user_config's pv(input,rule_deck_*) or pv(<stage>,runset).
# ─────────────────────────────────────────────────────────────────────────────
set tech(rules,drc)                               ""
set tech(rules,lvs)                               ""
set tech(rules,erc)                               ""
set tech(rules,perc)                              ""
set tech(rules,perc_ldl)                          ""
set tech(rules,fill)                              ""
set tech(rules,multi_patterning)                  ""
set tech(rules,xor)                               ""
set tech(rules,antenna)                           ""
set tech(spice,stdcell)                           ""

# ── VT Variant Patterns ──
set tech(vt_variants_available) {rvt lvt ulvt hvt}
set tech(vt_pattern,lvt)  "*lvt*"
set tech(vt_pattern,ulvt)  "*ulvt*"
set tech(vt_pattern,hvt)  "*hvt*"
set tech(vt_pattern,rvt)  "*rvt*"

# ── Tech LEF (per metal stack × track) ──
set tech(8M,7T,lef_tech)                          "$project(lib_root)/Back_End/lef/gf28slpe_8M_7t_tech.lef"
set tech(8M,9T,lef_tech)                          "$project(lib_root)/Back_End/lef/gf28slpe_8M_9t_tech.lef"
set tech(9M,7T,lef_tech)                          "$project(lib_root)/Back_End/lef/gf28slpe_9M_7t_tech.lef"
set tech(9M,9T,lef_tech)                          "$project(lib_root)/Back_End/lef/gf28slpe_9M_9t_tech.lef"
set tech(10M,7T,lef_tech)                         "$project(lib_root)/Back_End/lef/gf28slpe_10M_7t_tech.lef"
set tech(10M,9T,lef_tech)                         "$project(lib_root)/Back_End/lef/gf28slpe_10M_9t_tech.lef"

# ─────────────────────────────────────────────────────────────────────────────
# Metal Stack: 8M
# ─────────────────────────────────────────────────────────────────────────────

# Routing & Layers
set tech(8M,metal_count)                          8
set tech(8M,metal_layers)                         {M1 M2 M3 M4 M5 M6 M7 M8}
set tech(8M,min_routing_layer)                    "M2"
set tech(8M,max_routing_layer)                    "M7"
set tech(8M,clock_routing_layer_min)              "M4"
set tech(8M,clock_routing_layer_max)              "M8"

# Power Grid
set tech(8M,pg_strap_layers)                      "M7 M8"

# Via & Metal Fill
set tech(8M,via_layers)                           {VIA1 VIA2 VIA3 VIA4 VIA5 VIA6 VIA7}
set tech(8M,metal_fill_min_density)               20.0
set tech(8M,metal_fill_max_density)               80.0

# Parasitic Extraction
set tech(8M,tluplus_map)                          "$project(lib_root)/Back_End/rcx/gf28slpe_tf_itf_tluplus.map"
set tech(rcx,8M,rc_max,tluplus)                   "$project(lib_root)/Back_End/rcx/gf28slpe_1p8m_Cmax.tluplus"
set tech(rcx,8M,rc_max,nxtgrd)                    "$project(lib_root)/Back_End/rcx/gf28slpe_1p8m_Cmax.nxtgrd"
set tech(rcx,8M,rc_max,qrc)                       "$project(lib_root)/Back_End/rcx/gf28slpe_1p8m_Cmax.qrcTechFile"
set tech(rcx,8M,rc_typ,tluplus)                   "$project(lib_root)/Back_End/rcx/gf28slpe_1p8m_Ctyp.tluplus"
set tech(rcx,8M,rc_typ,nxtgrd)                    "$project(lib_root)/Back_End/rcx/gf28slpe_1p8m_Ctyp.nxtgrd"
set tech(rcx,8M,rc_typ,qrc)                       "$project(lib_root)/Back_End/rcx/gf28slpe_1p8m_Ctyp.qrcTechFile"
set tech(rcx,8M,rc_min,tluplus)                   "$project(lib_root)/Back_End/rcx/gf28slpe_1p8m_Cmin.tluplus"
set tech(rcx,8M,rc_min,nxtgrd)                    "$project(lib_root)/Back_End/rcx/gf28slpe_1p8m_Cmin.nxtgrd"
set tech(rcx,8M,rc_min,qrc)                       "$project(lib_root)/Back_End/rcx/gf28slpe_1p8m_Cmin.qrcTechFile"
set tech(rcx,8M,rc_max_cworst,tluplus)            "$project(lib_root)/Back_End/rcx/gf28slpe_1p8m_Cmax.tluplus"
set tech(rcx,8M,rc_max_cworst,nxtgrd)             "$project(lib_root)/Back_End/rcx/gf28slpe_1p8m_Cmax.nxtgrd"
set tech(rcx,8M,rc_max_cworst,qrc)                "$project(lib_root)/Back_End/rcx/gf28slpe_1p8m_Cmax.qrcTechFile"

# Signoff & DRC
set tech(8M,gds_layer_map_file)                   "$project(lib_root)/Back_End/layermap/gf28slpe_8m_layermap.map"
set tech(8M,antenna_rule_file)                    "$project(lib_root)/Back_End/antenna/gf28slpe_8m_antenna.rules"
set tech(8M,signal_em_constraint_file)            ""
set tech(8M,stream_files_for_merge)               ""

# ─────────────────────────────────────────────────────────────────────────────
# Metal Stack: 9M
# ─────────────────────────────────────────────────────────────────────────────

# Routing & Layers
set tech(9M,metal_count)                          9
set tech(9M,metal_layers)                         {M1 M2 M3 M4 M5 M6 M7 M8 M9}
set tech(9M,min_routing_layer)                    "M2"
set tech(9M,max_routing_layer)                    "M8"
set tech(9M,clock_routing_layer_min)              "M4"
set tech(9M,clock_routing_layer_max)              "M8"

# Power Grid
set tech(9M,pg_strap_layers)                      "M8 M9"

# Via & Metal Fill
set tech(9M,via_layers)                           {VIA1 VIA2 VIA3 VIA4 VIA5 VIA6 VIA7 VIA8}
set tech(9M,metal_fill_min_density)               20.0
set tech(9M,metal_fill_max_density)               80.0

# Parasitic Extraction
set tech(9M,tluplus_map)                          "$project(lib_root)/Back_End/rcx/gf28slpe_tf_itf_tluplus.map"
set tech(rcx,9M,rc_max,tluplus)                   "$project(lib_root)/Back_End/rcx/gf28slpe_1p9m_Cmax.tluplus"
set tech(rcx,9M,rc_max,nxtgrd)                    "$project(lib_root)/Back_End/rcx/gf28slpe_1p9m_Cmax.nxtgrd"
set tech(rcx,9M,rc_max,qrc)                       "$project(lib_root)/Back_End/rcx/gf28slpe_1p9m_Cmax.qrcTechFile"
set tech(rcx,9M,rc_typ,tluplus)                   "$project(lib_root)/Back_End/rcx/gf28slpe_1p9m_Ctyp.tluplus"
set tech(rcx,9M,rc_typ,nxtgrd)                    "$project(lib_root)/Back_End/rcx/gf28slpe_1p9m_Ctyp.nxtgrd"
set tech(rcx,9M,rc_typ,qrc)                       "$project(lib_root)/Back_End/rcx/gf28slpe_1p9m_Ctyp.qrcTechFile"
set tech(rcx,9M,rc_min,tluplus)                   "$project(lib_root)/Back_End/rcx/gf28slpe_1p9m_Cmin.tluplus"
set tech(rcx,9M,rc_min,nxtgrd)                    "$project(lib_root)/Back_End/rcx/gf28slpe_1p9m_Cmin.nxtgrd"
set tech(rcx,9M,rc_min,qrc)                       "$project(lib_root)/Back_End/rcx/gf28slpe_1p9m_Cmin.qrcTechFile"
set tech(rcx,9M,rc_max_cworst,tluplus)            "$project(lib_root)/Back_End/rcx/gf28slpe_1p9m_Cmax.tluplus"
set tech(rcx,9M,rc_max_cworst,nxtgrd)             "$project(lib_root)/Back_End/rcx/gf28slpe_1p9m_Cmax.nxtgrd"
set tech(rcx,9M,rc_max_cworst,qrc)                "$project(lib_root)/Back_End/rcx/gf28slpe_1p9m_Cmax.qrcTechFile"

# Signoff & DRC
set tech(9M,gds_layer_map_file)                   "$project(lib_root)/Back_End/layermap/gf28slpe_9m_layermap.map"
set tech(9M,antenna_rule_file)                    "$project(lib_root)/Back_End/antenna/gf28slpe_9m_antenna.rules"
set tech(9M,signal_em_constraint_file)            ""
set tech(9M,stream_files_for_merge)               ""

# ─────────────────────────────────────────────────────────────────────────────
# Metal Stack: 10M
# ─────────────────────────────────────────────────────────────────────────────

# Routing & Layers
set tech(10M,metal_count)                         10
set tech(10M,metal_layers)                        {M1 M2 M3 M4 M5 M6 M7 M8 M9 M10}
set tech(10M,min_routing_layer)                   "M2"
set tech(10M,max_routing_layer)                   "M9"
set tech(10M,clock_routing_layer_min)             "M4"
set tech(10M,clock_routing_layer_max)             "M8"

# Power Grid
set tech(10M,pg_strap_layers)                     "M9 M10"

# Via & Metal Fill
set tech(10M,via_layers)                          {VIA1 VIA2 VIA3 VIA4 VIA5 VIA6 VIA7 VIA8 VIA9}
set tech(10M,metal_fill_min_density)              20.0
set tech(10M,metal_fill_max_density)              80.0

# Parasitic Extraction
set tech(10M,tluplus_map)                         "$project(lib_root)/Back_End/rcx/gf28slpe_tf_itf_tluplus.map"
set tech(rcx,10M,rc_max,tluplus)                  "$project(lib_root)/Back_End/rcx/gf28slpe_1p10m_Cmax.tluplus"
set tech(rcx,10M,rc_max,nxtgrd)                   "$project(lib_root)/Back_End/rcx/gf28slpe_1p10m_Cmax.nxtgrd"
set tech(rcx,10M,rc_max,qrc)                      "$project(lib_root)/Back_End/rcx/gf28slpe_1p10m_Cmax.qrcTechFile"
set tech(rcx,10M,rc_typ,tluplus)                  "$project(lib_root)/Back_End/rcx/gf28slpe_1p10m_Ctyp.tluplus"
set tech(rcx,10M,rc_typ,nxtgrd)                   "$project(lib_root)/Back_End/rcx/gf28slpe_1p10m_Ctyp.nxtgrd"
set tech(rcx,10M,rc_typ,qrc)                      "$project(lib_root)/Back_End/rcx/gf28slpe_1p10m_Ctyp.qrcTechFile"
set tech(rcx,10M,rc_min,tluplus)                  "$project(lib_root)/Back_End/rcx/gf28slpe_1p10m_Cmin.tluplus"
set tech(rcx,10M,rc_min,nxtgrd)                   "$project(lib_root)/Back_End/rcx/gf28slpe_1p10m_Cmin.nxtgrd"
set tech(rcx,10M,rc_min,qrc)                      "$project(lib_root)/Back_End/rcx/gf28slpe_1p10m_Cmin.qrcTechFile"
set tech(rcx,10M,rc_max_cworst,tluplus)           "$project(lib_root)/Back_End/rcx/gf28slpe_1p10m_Cmax.tluplus"
set tech(rcx,10M,rc_max_cworst,nxtgrd)            "$project(lib_root)/Back_End/rcx/gf28slpe_1p10m_Cmax.nxtgrd"
set tech(rcx,10M,rc_max_cworst,qrc)               "$project(lib_root)/Back_End/rcx/gf28slpe_1p10m_Cmax.qrcTechFile"

# Signoff & DRC
set tech(10M,gds_layer_map_file)                  "$project(lib_root)/Back_End/layermap/gf28slpe_10m_layermap.map"
set tech(10M,antenna_rule_file)                   "$project(lib_root)/Back_End/antenna/gf28slpe_10m_antenna.rules"
set tech(10M,signal_em_constraint_file)           ""
set tech(10M,stream_files_for_merge)              ""

# ── Physical Cells: 7T ──
set tech(7T,cell_height)                          "1.008"
set tech(7T,clock_buffers)                        "sc7mcz_28slpe_base_rvt_c30_CKBUF4 sc7mcz_28slpe_base_rvt_c30_CKBUF8 sc7mcz_28slpe_base_rvt_c30_CKBUF16"
set tech(7T,clock_inverters)                      "sc7mcz_28slpe_base_rvt_c30_CKINV4 sc7mcz_28slpe_base_rvt_c30_CKINV8"
set tech(7T,decap)                                "sc7mcz_28slpe_base_rvt_c30_DCAP4 sc7mcz_28slpe_base_rvt_c30_DCAP8"
set tech(7T,delay_cells)                          "sc7mcz_28slpe_base_rvt_c30_DEL1 sc7mcz_28slpe_base_rvt_c30_DEL2"
set tech(7T,dont_use)                             "*D0BWP7T* *OPTHOLD* *DEL*"
set tech(7T,endcap)                               "sc7mcz_28slpe_base_rvt_c30_ENDCAP1"
set tech(7T,fillers)                              "sc7mcz_28slpe_base_rvt_c30_FILL1 sc7mcz_28slpe_base_rvt_c30_FILL2 sc7mcz_28slpe_base_rvt_c30_FILL4 sc7mcz_28slpe_base_rvt_c30_FILL8"
set tech(7T,hold_buffers)                         "sc7mcz_28slpe_base_rvt_c30_BUFFD1 sc7mcz_28slpe_base_rvt_c30_BUFFD2 sc7mcz_28slpe_base_rvt_c30_BUFFD4"
set tech(7T,icg_cells)                            "sc7mcz_28slpe_base_rvt_c30_CKLNQD1 sc7mcz_28slpe_base_rvt_c30_CKLNQD2 sc7mcz_28slpe_base_rvt_c30_CKLNQD4"
set tech(7T,isolation)                            "sc7mcz_28slpe_base_rvt_c30_ISOLAND1 sc7mcz_28slpe_base_rvt_c30_ISOLOR1"
set tech(7T,level_shifter)                        "sc7mcz_28slpe_base_rvt_c30_LSDOWN1 sc7mcz_28slpe_base_rvt_c30_LSUP1"
set tech(7T,power_switch)                         "sc7mcz_28slpe_base_rvt_c30_HDRDWN1 sc7mcz_28slpe_base_rvt_c30_HDRDWN2"
set tech(7T,site)                                 "GF28SLPE_SC7T"
set tech(7T,site_width)                           "0.140"
set tech(7T,tie_cells)                            "sc7mcz_28slpe_base_rvt_c30_TIEHI sc7mcz_28slpe_base_rvt_c30_TIELO"
set tech(7T,well_tap)                             "sc7mcz_28slpe_base_rvt_c30_FILLTIE1"

# ── Physical Cells: 9T ──
set tech(9T,cell_height)                          "1.296"
set tech(9T,clock_buffers)                        "sc9mcz_28slpe_base_rvt_c30_CKBUF4 sc9mcz_28slpe_base_rvt_c30_CKBUF8 sc9mcz_28slpe_base_rvt_c30_CKBUF16"
set tech(9T,clock_inverters)                      "sc9mcz_28slpe_base_rvt_c30_CKINV4 sc9mcz_28slpe_base_rvt_c30_CKINV8"
set tech(9T,decap)                                "sc9mcz_28slpe_base_rvt_c30_DCAP4 sc9mcz_28slpe_base_rvt_c30_DCAP8"
set tech(9T,delay_cells)                          "sc9mcz_28slpe_base_rvt_c30_DEL1 sc9mcz_28slpe_base_rvt_c30_DEL2"
set tech(9T,dont_use)                             "*D0BWP9T* *OPTHOLD* *DEL*"
set tech(9T,endcap)                               "sc9mcz_28slpe_base_rvt_c30_ENDCAP1"
set tech(9T,fillers)                              "sc9mcz_28slpe_base_rvt_c30_FILL1 sc9mcz_28slpe_base_rvt_c30_FILL2 sc9mcz_28slpe_base_rvt_c30_FILL4 sc9mcz_28slpe_base_rvt_c30_FILL8"
set tech(9T,hold_buffers)                         "sc9mcz_28slpe_base_rvt_c30_BUFFD1 sc9mcz_28slpe_base_rvt_c30_BUFFD2 sc9mcz_28slpe_base_rvt_c30_BUFFD4"
set tech(9T,icg_cells)                            "sc9mcz_28slpe_base_rvt_c30_CKLNQD1 sc9mcz_28slpe_base_rvt_c30_CKLNQD2 sc9mcz_28slpe_base_rvt_c30_CKLNQD4"
set tech(9T,isolation)                            "sc9mcz_28slpe_base_rvt_c30_ISOLAND1 sc9mcz_28slpe_base_rvt_c30_ISOLOR1"
set tech(9T,level_shifter)                        "sc9mcz_28slpe_base_rvt_c30_LSDOWN1 sc9mcz_28slpe_base_rvt_c30_LSUP1"
set tech(9T,power_switch)                         "sc9mcz_28slpe_base_rvt_c30_HDRDWN1 sc9mcz_28slpe_base_rvt_c30_HDRDWN2"
set tech(9T,site)                                 "GF28SLPE_SC9T"
set tech(9T,site_width)                           "0.140"
set tech(9T,tie_cells)                            "sc9mcz_28slpe_base_rvt_c30_TIEHI sc9mcz_28slpe_base_rvt_c30_TIELO"
set tech(9T,well_tap)                             "sc9mcz_28slpe_base_rvt_c30_FILLTIE1"

# ── Common Signoff ──
set tech(lib_cell_purpose_file)                   ""
set tech(filler_sidefile)                         ""
set tech(signal_em_constraint_format)             "sigem"
