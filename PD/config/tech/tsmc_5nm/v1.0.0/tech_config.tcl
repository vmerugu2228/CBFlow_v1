#!/usr/bin/env tclsh
# =============================================================================
# CBflow Technology Configuration — TSMC N5 (5nm FinFET)
# PURE DATA — no if/else, no source, no exit, no logic
# Engine (generate_setup.tcl) handles validation, sourcing, and assembly
# =============================================================================

# ── Technology Identity ──
set tech(node)                   "5nm"
set tech(process)                "TSMC N5"
set tech(foundry)                "TSMC"
set tech(tracks_available)       "5T 6T 7T"
set tech(metal_stacks_available) "13M"

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
set tech(13M,5T,lef_tech)                         "$project(lib_root)/Back_End/lef/tsmc5nm_13M_5t_tech.lef"
set tech(13M,6T,lef_tech)                         "$project(lib_root)/Back_End/lef/tsmc5nm_13M_6t_tech.lef"
set tech(13M,7T,lef_tech)                         "$project(lib_root)/Back_End/lef/tsmc5nm_13M_7t_tech.lef"

# ─────────────────────────────────────────────────────────────────────────────
# Metal Stack: 13M
# ─────────────────────────────────────────────────────────────────────────────

# Routing & Layers
set tech(13M,metal_count)                         13
set tech(13M,metal_layers)                        {M1 M2 M3 M4 M5 M6 M7 M8 M9 M10 M11 M12 M13}
set tech(13M,metal_stack_full)                    "1P13M_2Mx_4Cx_2Kx_2Bx_1Jx_2Qx"
set tech(13M,min_routing_layer)                   "M2"
set tech(13M,max_routing_layer)                   "M12"
set tech(13M,clock_routing_layer_min)             "M6"
set tech(13M,clock_routing_layer_max)             "M10"

# Power Grid
set tech(13M,pg_strap_layers)                     "M12 M13"
set tech(13M,pg_strap_secondary)                  "M10 M11"
set tech(13M,pg_ring_layer_h)                     "M12"
set tech(13M,pg_ring_layer_v)                     "M13"

# Via & Metal Fill
set tech(13M,via_layers)                          {VIA1 VIA2 VIA3 VIA4 VIA5 VIA6 VIA7 VIA8 VIA9 VIA10 VIA11 VIA12}
set tech(13M,metal_fill_min_density)              20.0
set tech(13M,metal_fill_max_density)              80.0

# Parasitic Extraction
set tech(13M,tluplus_map)                         "$project(lib_root)/Back_End/rcx/tsmc5nm_tf_itf_tluplus.map"
set tech(rcx,13M,rc_max,tluplus)                  "$project(lib_root)/Back_End/rcx/tsmc5nm_1p13m_Cmax.tluplus"
set tech(rcx,13M,rc_max,nxtgrd)                   "$project(lib_root)/Back_End/rcx/tsmc5nm_1p13m_Cmax.nxtgrd"
set tech(rcx,13M,rc_max,qrc)                      "$project(lib_root)/Back_End/rcx/tsmc5nm_1p13m_Cmax.qrcTechFile"
set tech(rcx,13M,rc_typ,tluplus)                  "$project(lib_root)/Back_End/rcx/tsmc5nm_1p13m_Ctyp.tluplus"
set tech(rcx,13M,rc_typ,nxtgrd)                   "$project(lib_root)/Back_End/rcx/tsmc5nm_1p13m_Ctyp.nxtgrd"
set tech(rcx,13M,rc_typ,qrc)                      "$project(lib_root)/Back_End/rcx/tsmc5nm_1p13m_Ctyp.qrcTechFile"
set tech(rcx,13M,rc_min,tluplus)                  "$project(lib_root)/Back_End/rcx/tsmc5nm_1p13m_Cmin.tluplus"
set tech(rcx,13M,rc_min,nxtgrd)                   "$project(lib_root)/Back_End/rcx/tsmc5nm_1p13m_Cmin.nxtgrd"
set tech(rcx,13M,rc_min,qrc)                      "$project(lib_root)/Back_End/rcx/tsmc5nm_1p13m_Cmin.qrcTechFile"
set tech(rcx,13M,rc_max_cworst,tluplus)           "$project(lib_root)/Back_End/rcx/tsmc5nm_1p13m_Cmax.tluplus"
set tech(rcx,13M,rc_max_cworst,nxtgrd)            "$project(lib_root)/Back_End/rcx/tsmc5nm_1p13m_Cmax.nxtgrd"
set tech(rcx,13M,rc_max_cworst,qrc)               "$project(lib_root)/Back_End/rcx/tsmc5nm_1p13m_Cmax.qrcTechFile"

# Signoff & DRC
set tech(13M,gds_layer_map_file)                  "$project(lib_root)/Back_End/layermap/tsmc5nm_13m_layermap.map"
set tech(13M,antenna_rule_file)                   "$project(lib_root)/Back_End/antenna/tsmc5nm_13m_antenna.rules"
set tech(13M,signal_em_constraint_file)           ""
set tech(13M,stream_files_for_merge)              ""

# ── Physical Cells: 5T ──
set tech(5T,cell_height)                          "0.216"
set tech(5T,clock_buffers)                        "tcbn05bwp5tsvt_CKBUF4 tcbn05bwp5tsvt_CKBUF8"
set tech(5T,clock_inverters)                      "tcbn05bwp5tsvt_CKINV4 tcbn05bwp5tsvt_CKINV8"
set tech(5T,decap)                                "TSMC_N5_SC5T_DCAP4 TSMC_N5_SC5T_DCAP8"
set tech(5T,delay_cells)                          "tcbn05bwp5tsvt_DEL1 tcbn05bwp5tsvt_DEL2 tcbn05bwp5tsvt_DEL4"
set tech(5T,dont_use)                             "*D0BWP5T* *OPTHOLD* *DEL*"
set tech(5T,endcap)                               "TSMC_N5_SC5T_ENDCAP1"
set tech(5T,fillers)                              "TSMC_N5_SC5T_FILL1 TSMC_N5_SC5T_FILL2 TSMC_N5_SC5T_FILL4 TSMC_N5_SC5T_FILL8"
set tech(5T,hold_buffers)                         "tcbn05bwp5tsvt_BUFFD1 tcbn05bwp5tsvt_BUFFD2 tcbn05bwp5tsvt_BUFFD4"
set tech(5T,icg_cells)                            "tcbn05bwp5tsvt_CKLNQD1 tcbn05bwp5tsvt_CKLNQD2 tcbn05bwp5tsvt_CKLNQD4"
set tech(5T,isolation)                            "tcbn05bwp5tsvt_ISOLAND1 tcbn05bwp5tsvt_ISOLOR1 tcbn05bwp5tsvt_ISOLAND2 tcbn05bwp5tsvt_ISOLOR2"
set tech(5T,level_shifter)                        "tcbn05bwp5tsvt_LSDOWN1 tcbn05bwp5tsvt_LSUP1 tcbn05bwp5tsvt_LSDOWN2 tcbn05bwp5tsvt_LSUP2"
set tech(5T,power_switch)                         "tcbn05bwp5tsvt_HDRDWN1 tcbn05bwp5tsvt_HDRDWN2 tcbn05bwp5tsvt_HDRDWN4"
set tech(5T,site)                                 "TSMC_N5_SC5T"
set tech(5T,site_width)                           "0.051"
set tech(5T,tie_cells)                            "tcbn05bwp5tsvt_TIEHI tcbn05bwp5tsvt_TIELO"
set tech(5T,well_tap)                             "TSMC_N5_SC5T_FILLTIE1"

# ── Physical Cells: 6T ──
set tech(6T,cell_height)                          "0.270"
set tech(6T,clock_buffers)                        "tcbn05bwp6tsvt_CKBUF4 tcbn05bwp6tsvt_CKBUF8"
set tech(6T,clock_inverters)                      "tcbn05bwp6tsvt_CKINV4 tcbn05bwp6tsvt_CKINV8"
set tech(6T,decap)                                "TSMC_N5_SC6T_DCAP4 TSMC_N5_SC6T_DCAP8"
set tech(6T,delay_cells)                          "tcbn05bwp6tsvt_DEL1 tcbn05bwp6tsvt_DEL2 tcbn05bwp6tsvt_DEL4"
set tech(6T,dont_use)                             "*D0BWP6T* *OPTHOLD* *DEL*"
set tech(6T,endcap)                               "TSMC_N5_SC6T_ENDCAP1"
set tech(6T,fillers)                              "TSMC_N5_SC6T_FILL1 TSMC_N5_SC6T_FILL2 TSMC_N5_SC6T_FILL4 TSMC_N5_SC6T_FILL8"
set tech(6T,hold_buffers)                         "tcbn05bwp6tsvt_BUFFD1 tcbn05bwp6tsvt_BUFFD2 tcbn05bwp6tsvt_BUFFD4"
set tech(6T,icg_cells)                            "tcbn05bwp6tsvt_CKLNQD1 tcbn05bwp6tsvt_CKLNQD2 tcbn05bwp6tsvt_CKLNQD4"
set tech(6T,isolation)                            "tcbn05bwp6tsvt_ISOLAND1 tcbn05bwp6tsvt_ISOLOR1 tcbn05bwp6tsvt_ISOLAND2 tcbn05bwp6tsvt_ISOLOR2"
set tech(6T,level_shifter)                        "tcbn05bwp6tsvt_LSDOWN1 tcbn05bwp6tsvt_LSUP1 tcbn05bwp6tsvt_LSDOWN2 tcbn05bwp6tsvt_LSUP2"
set tech(6T,power_switch)                         "tcbn05bwp6tsvt_HDRDWN1 tcbn05bwp6tsvt_HDRDWN2 tcbn05bwp6tsvt_HDRDWN4"
set tech(6T,site)                                 "TSMC_N5_SC6T"
set tech(6T,site_width)                           "0.051"
set tech(6T,tie_cells)                            "tcbn05bwp6tsvt_TIEHI tcbn05bwp6tsvt_TIELO"
set tech(6T,well_tap)                             "TSMC_N5_SC6T_FILLTIE1"

# ── Physical Cells: 7T ──
set tech(7T,cell_height)                          "0.324"
set tech(7T,clock_buffers)                        "tcbn05bwp7tsvt_CKBUF4 tcbn05bwp7tsvt_CKBUF8"
set tech(7T,clock_inverters)                      "tcbn05bwp7tsvt_CKINV4 tcbn05bwp7tsvt_CKINV8"
set tech(7T,decap)                                "TSMC_N5_SC7T_DCAP4 TSMC_N5_SC7T_DCAP8"
set tech(7T,delay_cells)                          "tcbn05bwp7tsvt_DEL1 tcbn05bwp7tsvt_DEL2 tcbn05bwp7tsvt_DEL4"
set tech(7T,dont_use)                             "*D0BWP7T* *OPTHOLD* *DEL*"
set tech(7T,endcap)                               "TSMC_N5_SC7T_ENDCAP1"
set tech(7T,fillers)                              "TSMC_N5_SC7T_FILL1 TSMC_N5_SC7T_FILL2 TSMC_N5_SC7T_FILL4 TSMC_N5_SC7T_FILL8"
set tech(7T,hold_buffers)                         "tcbn05bwp7tsvt_BUFFD1 tcbn05bwp7tsvt_BUFFD2 tcbn05bwp7tsvt_BUFFD4"
set tech(7T,icg_cells)                            "tcbn05bwp7tsvt_CKLNQD1 tcbn05bwp7tsvt_CKLNQD2 tcbn05bwp7tsvt_CKLNQD4"
set tech(7T,isolation)                            "tcbn05bwp7tsvt_ISOLAND1 tcbn05bwp7tsvt_ISOLOR1 tcbn05bwp7tsvt_ISOLAND2 tcbn05bwp7tsvt_ISOLOR2"
set tech(7T,level_shifter)                        "tcbn05bwp7tsvt_LSDOWN1 tcbn05bwp7tsvt_LSUP1 tcbn05bwp7tsvt_LSDOWN2 tcbn05bwp7tsvt_LSUP2"
set tech(7T,power_switch)                         "tcbn05bwp7tsvt_HDRDWN1 tcbn05bwp7tsvt_HDRDWN2 tcbn05bwp7tsvt_HDRDWN4"
set tech(7T,site)                                 "TSMC_N5_SC7T"
set tech(7T,site_width)                           "0.051"
set tech(7T,tie_cells)                            "tcbn05bwp7tsvt_TIEHI tcbn05bwp7tsvt_TIELO"
set tech(7T,well_tap)                             "TSMC_N5_SC7T_FILLTIE1"

# ── Common Signoff ──
set tech(lib_cell_purpose_file)                   ""
set tech(filler_sidefile)                         ""
set tech(signal_em_constraint_format)             "sigem"
