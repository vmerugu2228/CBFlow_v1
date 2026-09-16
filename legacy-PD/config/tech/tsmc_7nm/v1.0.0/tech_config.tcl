#!/usr/bin/env tclsh
# =============================================================================
# CBflow Technology Configuration — TSMC N7 (7nm FinFET)
# PURE DATA — no if/else, no source, no exit, no logic
# Engine (generate_setup.tcl) handles validation, sourcing, and assembly
# =============================================================================

# ── Technology Identity ──
set tech(node)                   "7nm"
set tech(process)                "TSMC N7"
set tech(foundry)                "TSMC"
set tech(tracks_available)       "6T 7.5T 9T"
set tech(metal_stacks_available) "12M"

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
set tech(vt_variants_available) {svt lvt ulvt hvt}
set tech(vt_pattern,svt)  "*svt*"
set tech(vt_pattern,lvt)  "*lvt*"
set tech(vt_pattern,ulvt)  "*ulvt*"
set tech(vt_pattern,hvt)  "*hvt*"

# ── Tech LEF (per metal stack × track) ──
set tech(12M,6T,lef_tech)                         "$project(lib_root)/Back_End/lef/tsmc7nm_12M_6t_tech.lef"
set tech(12M,7.5T,lef_tech)                       "$project(lib_root)/Back_End/lef/tsmc7nm_12M_7p5t_tech.lef"
set tech(12M,9T,lef_tech)                         "$project(lib_root)/Back_End/lef/tsmc7nm_12M_9t_tech.lef"

# ─────────────────────────────────────────────────────────────────────────────
# Metal Stack: 12M
# ─────────────────────────────────────────────────────────────────────────────

# Routing & Layers
set tech(12M,metal_count)                         12
set tech(12M,metal_layers)                        {M1 M2 M3 M4 M5 M6 M7 M8 M9 M10 M11 M12}
set tech(12M,metal_stack_full)                    "1P12M_2Mx_4Cx_2Kx_2Bx_1Jx_1Qx"
set tech(12M,min_routing_layer)                   "M2"
set tech(12M,max_routing_layer)                   "M11"
set tech(12M,clock_routing_layer_min)             "M5"
set tech(12M,clock_routing_layer_max)             "M9"

# Power Grid
set tech(12M,pg_strap_layers)                     "M11 M12"
set tech(12M,pg_strap_secondary)                  "M9 M10"
set tech(12M,pg_ring_layer_h)                     "M12"
set tech(12M,pg_ring_layer_v)                     "M11"

# Via & Metal Fill
set tech(12M,via_layers)                          {VIA1 VIA2 VIA3 VIA4 VIA5 VIA6 VIA7 VIA8 VIA9 VIA10 VIA11}
set tech(12M,metal_fill_min_density)              20.0
set tech(12M,metal_fill_max_density)              80.0

# Parasitic Extraction
set tech(12M,tluplus_map)                         "$project(lib_root)/Back_End/rcx/tsmc7nm_tf_itf_tluplus.map"
set tech(rcx,12M,rc_max,tluplus)                  "$project(lib_root)/Back_End/rcx/tsmc7nm_1p12m_Cmax.tluplus"
set tech(rcx,12M,rc_max,nxtgrd)                   "$project(lib_root)/Back_End/rcx/tsmc7nm_1p12m_Cmax.nxtgrd"
set tech(rcx,12M,rc_max,qrc)                      "$project(lib_root)/Back_End/rcx/tsmc7nm_1p12m_Cmax.qrcTechFile"
set tech(rcx,12M,rc_typ,tluplus)                  "$project(lib_root)/Back_End/rcx/tsmc7nm_1p12m_Ctyp.tluplus"
set tech(rcx,12M,rc_typ,nxtgrd)                   "$project(lib_root)/Back_End/rcx/tsmc7nm_1p12m_Ctyp.nxtgrd"
set tech(rcx,12M,rc_typ,qrc)                      "$project(lib_root)/Back_End/rcx/tsmc7nm_1p12m_Ctyp.qrcTechFile"
set tech(rcx,12M,rc_min,tluplus)                  "$project(lib_root)/Back_End/rcx/tsmc7nm_1p12m_Cmin.tluplus"
set tech(rcx,12M,rc_min,nxtgrd)                   "$project(lib_root)/Back_End/rcx/tsmc7nm_1p12m_Cmin.nxtgrd"
set tech(rcx,12M,rc_min,qrc)                      "$project(lib_root)/Back_End/rcx/tsmc7nm_1p12m_Cmin.qrcTechFile"
set tech(rcx,12M,rc_max_cworst,tluplus)           "$project(lib_root)/Back_End/rcx/tsmc7nm_1p12m_Cmax.tluplus"
set tech(rcx,12M,rc_max_cworst,nxtgrd)            "$project(lib_root)/Back_End/rcx/tsmc7nm_1p12m_Cmax.nxtgrd"
set tech(rcx,12M,rc_max_cworst,qrc)               "$project(lib_root)/Back_End/rcx/tsmc7nm_1p12m_Cmax.qrcTechFile"

# Signoff & DRC
set tech(12M,gds_layer_map_file)                  "$project(lib_root)/Back_End/layermap/tsmc7nm_12m_layermap.map"
set tech(12M,antenna_rule_file)                   "$project(lib_root)/Back_End/antenna/tsmc7nm_12m_antenna.rules"
set tech(12M,signal_em_constraint_file)           ""
set tech(12M,stream_files_for_merge)              ""

# ── Physical Cells: 6T ──
set tech(6T,cell_height)                          "0.270"
set tech(6T,clock_buffers)                        "tcbn07bwp6tsvt_CKBUF4 tcbn07bwp6tsvt_CKBUF8"
set tech(6T,clock_inverters)                      "tcbn07bwp6tsvt_CKINV4"
set tech(6T,decap)                                "TSMC_N7_SC6T_DCAP4 TSMC_N7_SC6T_DCAP8"
set tech(6T,delay_cells)                          "tcbn07bwp6tsvt_DEL1 tcbn07bwp6tsvt_DEL2 tcbn07bwp6tsvt_DEL4"
set tech(6T,dont_use)                             "*D0BWP6T* *OPTHOLD* *DEL*"
set tech(6T,endcap)                               "TSMC_N7_SC6T_ENDCAP1"
set tech(6T,fillers)                              "TSMC_N7_SC6T_FILL1 TSMC_N7_SC6T_FILL2 TSMC_N7_SC6T_FILL4 TSMC_N7_SC6T_FILL8"
set tech(6T,hold_buffers)                         "tcbn07bwp6tsvt_BUFFD1 tcbn07bwp6tsvt_BUFFD2 tcbn07bwp6tsvt_BUFFD4"
set tech(6T,icg_cells)                            "tcbn07bwp6tsvt_CKLNQD1 tcbn07bwp6tsvt_CKLNQD2 tcbn07bwp6tsvt_CKLNQD4"
set tech(6T,isolation)                            "tcbn07bwp6tsvt_ISOLAND1 tcbn07bwp6tsvt_ISOLOR1 tcbn07bwp6tsvt_ISOLAND2 tcbn07bwp6tsvt_ISOLOR2"
set tech(6T,level_shifter)                        "tcbn07bwp6tsvt_LSDOWN1 tcbn07bwp6tsvt_LSUP1 tcbn07bwp6tsvt_LSDOWN2 tcbn07bwp6tsvt_LSUP2"
set tech(6T,power_switch)                         "tcbn07bwp6tsvt_HDRDWN1 tcbn07bwp6tsvt_HDRDWN2 tcbn07bwp6tsvt_HDRDWN4"
set tech(6T,site)                                 "TSMC_N7_SC6T"
set tech(6T,site_width)                           "0.054"
set tech(6T,tie_cells)                            "tcbn07bwp6tsvt_TIEHI tcbn07bwp6tsvt_TIELO"
set tech(6T,well_tap)                             "TSMC_N7_SC6T_FILLTIE1"

# ── Physical Cells: 7.5T ──
set tech(7.5T,cell_height)                        "0.338"
set tech(7.5T,clock_buffers)                      "tcbn07bwp7p5tsvt_CKBUF4 tcbn07bwp7p5tsvt_CKBUF8"
set tech(7.5T,clock_inverters)                    "tcbn07bwp7p5tsvt_CKINV4"
set tech(7.5T,decap)                              "TSMC_N7_SC7P5T_DCAP4 TSMC_N7_SC7P5T_DCAP8"
set tech(7.5T,delay_cells)                        "tcbn07bwp7p5tsvt_DEL1 tcbn07bwp7p5tsvt_DEL2 tcbn07bwp7p5tsvt_DEL4"
set tech(7.5T,dont_use)                           "*D0BWP7P5T* *OPTHOLD* *DEL*"
set tech(7.5T,endcap)                             "TSMC_N7_SC7P5T_ENDCAP1"
set tech(7.5T,fillers)                            "TSMC_N7_SC7P5T_FILL1 TSMC_N7_SC7P5T_FILL2 TSMC_N7_SC7P5T_FILL4 TSMC_N7_SC7P5T_FILL8"
set tech(7.5T,hold_buffers)                       "tcbn07bwp7p5tsvt_BUFFD1 tcbn07bwp7p5tsvt_BUFFD2 tcbn07bwp7p5tsvt_BUFFD4"
set tech(7.5T,icg_cells)                          "tcbn07bwp7p5tsvt_CKLNQD1 tcbn07bwp7p5tsvt_CKLNQD2 tcbn07bwp7p5tsvt_CKLNQD4"
set tech(7.5T,isolation)                          "tcbn07bwp7p5tsvt_ISOLAND1 tcbn07bwp7p5tsvt_ISOLOR1 tcbn07bwp7p5tsvt_ISOLAND2 tcbn07bwp7p5tsvt_ISOLOR2"
set tech(7.5T,level_shifter)                      "tcbn07bwp7p5tsvt_LSDOWN1 tcbn07bwp7p5tsvt_LSUP1 tcbn07bwp7p5tsvt_LSDOWN2 tcbn07bwp7p5tsvt_LSUP2"
set tech(7.5T,power_switch)                       "tcbn07bwp7p5tsvt_HDRDWN1 tcbn07bwp7p5tsvt_HDRDWN2 tcbn07bwp7p5tsvt_HDRDWN4"
set tech(7.5T,site)                               "TSMC_N7_SC7P5T"
set tech(7.5T,site_width)                         "0.054"
set tech(7.5T,tie_cells)                          "tcbn07bwp7p5tsvt_TIEHI tcbn07bwp7p5tsvt_TIELO"
set tech(7.5T,well_tap)                           "TSMC_N7_SC7P5T_FILLTIE1"

# ── Physical Cells: 9T ──
set tech(9T,cell_height)                          "0.405"
set tech(9T,clock_buffers)                        "tcbn07bwp9tsvt_CKBUF4 tcbn07bwp9tsvt_CKBUF8"
set tech(9T,clock_inverters)                      "tcbn07bwp9tsvt_CKINV4"
set tech(9T,decap)                                "TSMC_N7_SC9T_DCAP4 TSMC_N7_SC9T_DCAP8"
set tech(9T,delay_cells)                          "tcbn07bwp9tsvt_DEL1 tcbn07bwp9tsvt_DEL2 tcbn07bwp9tsvt_DEL4"
set tech(9T,dont_use)                             "*D0BWP9T* *OPTHOLD* *DEL*"
set tech(9T,endcap)                               "TSMC_N7_SC9T_ENDCAP1"
set tech(9T,fillers)                              "TSMC_N7_SC9T_FILL1 TSMC_N7_SC9T_FILL2 TSMC_N7_SC9T_FILL4 TSMC_N7_SC9T_FILL8 TSMC_N7_SC9T_FILL16"
set tech(9T,hold_buffers)                         "tcbn07bwp9tsvt_BUFFD1 tcbn07bwp9tsvt_BUFFD2 tcbn07bwp9tsvt_BUFFD4"
set tech(9T,icg_cells)                            "tcbn07bwp9tsvt_CKLNQD1 tcbn07bwp9tsvt_CKLNQD2 tcbn07bwp9tsvt_CKLNQD4"
set tech(9T,isolation)                            "tcbn07bwp9tsvt_ISOLAND1 tcbn07bwp9tsvt_ISOLOR1 tcbn07bwp9tsvt_ISOLAND2 tcbn07bwp9tsvt_ISOLOR2"
set tech(9T,level_shifter)                        "tcbn07bwp9tsvt_LSDOWN1 tcbn07bwp9tsvt_LSUP1 tcbn07bwp9tsvt_LSDOWN2 tcbn07bwp9tsvt_LSUP2"
set tech(9T,power_switch)                         "tcbn07bwp9tsvt_HDRDWN1 tcbn07bwp9tsvt_HDRDWN2 tcbn07bwp9tsvt_HDRDWN4"
set tech(9T,site)                                 "TSMC_N7_SC9T"
set tech(9T,site_width)                           "0.054"
set tech(9T,tie_cells)                            "tcbn07bwp9tsvt_TIEHI tcbn07bwp9tsvt_TIELO"
set tech(9T,well_tap)                             "TSMC_N7_SC9T_FILLTIE1"

# ── Common Signoff ──
set tech(lib_cell_purpose_file)                   ""
set tech(filler_sidefile)                         ""
set tech(signal_em_constraint_format)             "sigem"
