#!/usr/bin/env tclsh
# =============================================================================
# CBflow Technology Configuration — GlobalFoundries 22FDX (22nm FD-SOI)
# PURE DATA — no if/else, no source, no exit, no logic
# Engine (generate_setup.tcl) handles validation, sourcing, and assembly
# =============================================================================

# ── Technology Identity ──
set tech(node)                   "22nm"
set tech(process)                "GF 22FDX"
set tech(foundry)                "GlobalFoundries"
set tech(tracks_available)       "9T 7.5T 8T"
set tech(metal_stacks_available) "8M 9M 10M 11M"

# ─────────────────────────────────────────────────────────────────────────────
# Physical Verification Runsets — foundry-provided SVRF / IC Validator decks
# Empty defaults; populate with foundry paths for site-wide use, or override
# per-run via user_config's pv(input,rule_deck_*) or pv(<stage>,runset).
#
# Consumed by:
#   Calibre (SVRF)  — pv(input,rule_deck_*) chain, no direct tech read
#   ICV     (RSL)   — falls back to tech(rules,*) when pv() unset
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
# SPICE model deck used by nettran (v2lvs / Verilog-to-SPICE) for hierarchical
# LVS. Empty = fabricate empty subckts; populate for real LVS sign-off.
set tech(spice,stdcell)                           ""

# ── VT Variant Patterns ──
set tech(vt_variants_available) {svt lvt ulvt hvt}
set tech(vt_pattern,svt)  "*svt*"
set tech(vt_pattern,lvt)  "*lvt*"
set tech(vt_pattern,ulvt)  "*ulvt*"
set tech(vt_pattern,hvt)  "*hvt*"

# ── Tech LEF (per metal stack × track) ──
set tech(8M,9T,lef_tech)                          "$project(lib_root)/Back_End/lef/gf22nm_8M_9t_tech.lef"
set tech(8M,7.5T,lef_tech)                        "$project(lib_root)/Back_End/lef/gf22nm_8M_7p5t_tech.lef"
set tech(8M,8T,lef_tech)                          "$project(lib_root)/Back_End/lef/gf22nm_8M_8t_tech.lef"
set tech(9M,9T,lef_tech)                          "$project(lib_root)/Back_End/lef/gf22nm_9M_9t_tech.lef"
set tech(9M,7.5T,lef_tech)                        "$project(lib_root)/Back_End/lef/gf22nm_9M_7p5t_tech.lef"
set tech(9M,8T,lef_tech)                          "$project(lib_root)/Back_End/lef/gf22nm_9M_8t_tech.lef"
set tech(10M,9T,lef_tech)                         "$project(lib_root)/Back_End/lef/gf22nm_10M_9t_tech.lef"
set tech(10M,7.5T,lef_tech)                       "$project(lib_root)/Back_End/lef/gf22nm_10M_7p5t_tech.lef"
set tech(10M,8T,lef_tech)                         "$project(lib_root)/Back_End/lef/gf22nm_10M_8t_tech.lef"
set tech(11M,9T,lef_tech)                         "$project(lib_root)/Back_End/lef/gf22nm_11M_9t_tech.lef"
set tech(11M,7.5T,lef_tech)                       "$project(lib_root)/Back_End/lef/gf22nm_11M_7p5t_tech.lef"
set tech(11M,8T,lef_tech)                         "$project(lib_root)/Back_End/lef/gf22nm_11M_8t_tech.lef"

# ─────────────────────────────────────────────────────────────────────────────
# Metal Stack: 8M
# ─────────────────────────────────────────────────────────────────────────────

# Routing & Layers
set tech(8M,metal_count)                          8
set tech(8M,metal_layers)                         {M1 M2 M3 M4 M5 M6 M7 M8}
set tech(8M,metal_stack_full)                     "1P8M_2Mx_3Cx_1Jx_2Qx_LB"
# 8M tech files — same .tf across tracks (foundry ships one per stack)
set tech(8M,9T,tech_file)                    "$project(lib_root)/Back_End/tech/gf22naphlogl24uhf116a_8M_2Mx_3Cx_1Jx_2Qx_LB.tf"
set tech(8M,7.5T,tech_file)                    "$project(lib_root)/Back_End/tech/gf22naphlogl24uhf116a_8M_2Mx_3Cx_1Jx_2Qx_LB.tf"
set tech(8M,8T,tech_file)                    "$project(lib_root)/Back_End/tech/gf22naphlogl24uhf116a_8M_2Mx_3Cx_1Jx_2Qx_LB.tf"
set tech(8M,min_routing_layer)                    "M2"
set tech(8M,max_routing_layer)                    "M7"
set tech(8M,clock_routing_layer_min)              "M3"
set tech(8M,clock_routing_layer_max)              "M5"

# Power Grid
set tech(8M,pg_strap_layers)                      "M7 M8"
set tech(8M,pg_strap_secondary)                   "M5 M6"
set tech(8M,pg_ring_layer_h)                      "M8"
set tech(8M,pg_ring_layer_v)                      "M7"

# Via & Metal Fill
set tech(8M,via_layers)                           {VIA1 VIA2 VIA3 VIA4 VIA5 VIA6 VIA7}
set tech(8M,metal_fill_min_density)               20.0
set tech(8M,metal_fill_max_density)               80.0

# Parasitic Extraction
set tech(8M,tluplus_map)                          "$project(lib_root)/Back_End/rcx/gf22nm_tf_itf_tluplus.map"
set tech(rcx,8M,rc_max,tluplus)                   "$project(lib_root)/Back_End/rcx/gf22nm_1p8m_Cmax.tluplus"
set tech(rcx,8M,rc_max,nxtgrd)                    "$project(lib_root)/Back_End/rcx/gf22nm_1p8m_Cmax.nxtgrd"
set tech(rcx,8M,rc_max,qrc)                       "$project(lib_root)/Back_End/rcx/gf22nm_1p8m_Cmax.qrcTechFile"
set tech(rcx,8M,rc_typ,tluplus)                   "$project(lib_root)/Back_End/rcx/gf22nm_1p8m_Ctyp.tluplus"
set tech(rcx,8M,rc_typ,nxtgrd)                    "$project(lib_root)/Back_End/rcx/gf22nm_1p8m_Ctyp.nxtgrd"
set tech(rcx,8M,rc_typ,qrc)                       "$project(lib_root)/Back_End/rcx/gf22nm_1p8m_Ctyp.qrcTechFile"
set tech(rcx,8M,rc_min,tluplus)                   "$project(lib_root)/Back_End/rcx/gf22nm_1p8m_Cmin.tluplus"
set tech(rcx,8M,rc_min,nxtgrd)                    "$project(lib_root)/Back_End/rcx/gf22nm_1p8m_Cmin.nxtgrd"
set tech(rcx,8M,rc_min,qrc)                       "$project(lib_root)/Back_End/rcx/gf22nm_1p8m_Cmin.qrcTechFile"
set tech(rcx,8M,rc_max_cworst,tluplus)            "$project(lib_root)/Back_End/rcx/gf22nm_1p8m_Cmax.tluplus"
set tech(rcx,8M,rc_max_cworst,nxtgrd)             "$project(lib_root)/Back_End/rcx/gf22nm_1p8m_Cmax.nxtgrd"
set tech(rcx,8M,rc_max_cworst,qrc)                "$project(lib_root)/Back_End/rcx/gf22nm_1p8m_Cmax.qrcTechFile"

# Signoff & DRC
set tech(8M,gds_layer_map_file)                   "$project(lib_root)/Back_End/layermap/gf22nm_8m_layermap.map"
set tech(8M,antenna_rule_file)                    "$project(lib_root)/Back_End/antenna/gf22nm_8m_antenna.rules"
set tech(8M,signal_em_constraint_file)            ""
set tech(8M,stream_files_for_merge)               ""

# ─────────────────────────────────────────────────────────────────────────────
# Metal Stack: 9M
# ─────────────────────────────────────────────────────────────────────────────

# Routing & Layers
set tech(9M,metal_count)                          9
set tech(9M,metal_layers)                         {M1 M2 M3 M4 M5 M6 M7 M8 M9}
set tech(9M,metal_stack_full)                     "1P9M_2Mx_4Cx_1Jx_2Qx_LB"
# 9M tech files — same .tf across tracks (foundry ships one per stack)
set tech(9M,9T,tech_file)                    "$project(lib_root)/Back_End/tech/gf22naphlogl24uhf116a_9M_2Mx_4Cx_1Jx_2Qx_LB.tf"
set tech(9M,7.5T,tech_file)                    "$project(lib_root)/Back_End/tech/gf22naphlogl24uhf116a_9M_2Mx_4Cx_1Jx_2Qx_LB.tf"
set tech(9M,8T,tech_file)                    "$project(lib_root)/Back_End/tech/gf22naphlogl24uhf116a_9M_2Mx_4Cx_1Jx_2Qx_LB.tf"
set tech(9M,min_routing_layer)                    "M2"
set tech(9M,max_routing_layer)                    "M8"
set tech(9M,clock_routing_layer_min)              "M3"
set tech(9M,clock_routing_layer_max)              "M6"

# Power Grid
set tech(9M,pg_strap_layers)                      "M8 M9"
set tech(9M,pg_strap_secondary)                   "M6 M7"
set tech(9M,pg_ring_layer_h)                      "M8"
set tech(9M,pg_ring_layer_v)                      "M9"

# Via & Metal Fill
set tech(9M,via_layers)                           {VIA1 VIA2 VIA3 VIA4 VIA5 VIA6 VIA7 VIA8}
set tech(9M,metal_fill_min_density)               20.0
set tech(9M,metal_fill_max_density)               80.0

# Parasitic Extraction
set tech(9M,tluplus_map)                          "$project(lib_root)/Back_End/rcx/gf22nm_tf_itf_tluplus.map"
set tech(rcx,9M,rc_max,tluplus)                   "$project(lib_root)/Back_End/rcx/gf22nm_1p9m_Cmax.tluplus"
set tech(rcx,9M,rc_max,nxtgrd)                    "$project(lib_root)/Back_End/rcx/gf22nm_1p9m_Cmax.nxtgrd"
set tech(rcx,9M,rc_max,qrc)                       "$project(lib_root)/Back_End/rcx/gf22nm_1p9m_Cmax.qrcTechFile"
set tech(rcx,9M,rc_typ,tluplus)                   "$project(lib_root)/Back_End/rcx/gf22nm_1p9m_Ctyp.tluplus"
set tech(rcx,9M,rc_typ,nxtgrd)                    "$project(lib_root)/Back_End/rcx/gf22nm_1p9m_Ctyp.nxtgrd"
set tech(rcx,9M,rc_typ,qrc)                       "$project(lib_root)/Back_End/rcx/gf22nm_1p9m_Ctyp.qrcTechFile"
set tech(rcx,9M,rc_min,tluplus)                   "$project(lib_root)/Back_End/rcx/gf22nm_1p9m_Cmin.tluplus"
set tech(rcx,9M,rc_min,nxtgrd)                    "$project(lib_root)/Back_End/rcx/gf22nm_1p9m_Cmin.nxtgrd"
set tech(rcx,9M,rc_min,qrc)                       "$project(lib_root)/Back_End/rcx/gf22nm_1p9m_Cmin.qrcTechFile"
set tech(rcx,9M,rc_max_cworst,tluplus)            "$project(lib_root)/Back_End/rcx/gf22nm_1p9m_Cmax.tluplus"
set tech(rcx,9M,rc_max_cworst,nxtgrd)             "$project(lib_root)/Back_End/rcx/gf22nm_1p9m_Cmax.nxtgrd"
set tech(rcx,9M,rc_max_cworst,qrc)                "$project(lib_root)/Back_End/rcx/gf22nm_1p9m_Cmax.qrcTechFile"

# Signoff & DRC
set tech(9M,gds_layer_map_file)                   "$project(lib_root)/Back_End/layermap/gf22nm_9m_layermap.map"
set tech(9M,antenna_rule_file)                    "$project(lib_root)/Back_End/antenna/gf22nm_9m_antenna.rules"
set tech(9M,signal_em_constraint_file)            ""
set tech(9M,stream_files_for_merge)               ""

# ─────────────────────────────────────────────────────────────────────────────
# Metal Stack: 10M
# ─────────────────────────────────────────────────────────────────────────────

# Routing & Layers
set tech(10M,metal_count)                         10
set tech(10M,metal_layers)                        {M1 M2 M3 M4 M5 M6 M7 M8 M9 M10}
set tech(10M,metal_stack_full)                    "1P10M_2Mx_5Cx_1Jx_2Qx_LB"
# 10M tech files — same .tf across tracks (foundry ships one per stack)
set tech(10M,9T,tech_file)                    "$project(lib_root)/Back_End/tech/gf22naphlogl24uhf116a_10M_2Mx_5Cx_1Jx_2Qx_LB.tf"
set tech(10M,7.5T,tech_file)                    "$project(lib_root)/Back_End/tech/gf22naphlogl24uhf116a_10M_2Mx_5Cx_1Jx_2Qx_LB.tf"
set tech(10M,8T,tech_file)                    "$project(lib_root)/Back_End/tech/gf22naphlogl24uhf116a_10M_2Mx_5Cx_1Jx_2Qx_LB.tf"
set tech(10M,min_routing_layer)                   "M2"
set tech(10M,max_routing_layer)                   "M9"
set tech(10M,clock_routing_layer_min)             "M4"
set tech(10M,clock_routing_layer_max)             "M7"

# Power Grid
set tech(10M,pg_strap_layers)                     "M9 M10"
set tech(10M,pg_strap_secondary)                  "M7 M8"
set tech(10M,pg_ring_layer_h)                     "M10"
set tech(10M,pg_ring_layer_v)                     "M9"

# Via & Metal Fill
set tech(10M,via_layers)                          {VIA1 VIA2 VIA3 VIA4 VIA5 VIA6 VIA7 VIA8 VIA9}
set tech(10M,metal_fill_min_density)              20.0
set tech(10M,metal_fill_max_density)              80.0

# Parasitic Extraction
set tech(10M,tluplus_map)                         "$project(lib_root)/Back_End/rcx/gf22nm_tf_itf_tluplus.map"
set tech(rcx,10M,rc_max,tluplus)                  "$project(lib_root)/Back_End/rcx/gf22nm_1p10m_Cmax.tluplus"
set tech(rcx,10M,rc_max,nxtgrd)                   "$project(lib_root)/Back_End/rcx/gf22nm_1p10m_Cmax.nxtgrd"
set tech(rcx,10M,rc_max,qrc)                      "$project(lib_root)/Back_End/rcx/gf22nm_1p10m_Cmax.qrcTechFile"
set tech(rcx,10M,rc_typ,tluplus)                  "$project(lib_root)/Back_End/rcx/gf22nm_1p10m_Ctyp.tluplus"
set tech(rcx,10M,rc_typ,nxtgrd)                   "$project(lib_root)/Back_End/rcx/gf22nm_1p10m_Ctyp.nxtgrd"
set tech(rcx,10M,rc_typ,qrc)                      "$project(lib_root)/Back_End/rcx/gf22nm_1p10m_Ctyp.qrcTechFile"
set tech(rcx,10M,rc_min,tluplus)                  "$project(lib_root)/Back_End/rcx/gf22nm_1p10m_Cmin.tluplus"
set tech(rcx,10M,rc_min,nxtgrd)                   "$project(lib_root)/Back_End/rcx/gf22nm_1p10m_Cmin.nxtgrd"
set tech(rcx,10M,rc_min,qrc)                      "$project(lib_root)/Back_End/rcx/gf22nm_1p10m_Cmin.qrcTechFile"
set tech(rcx,10M,rc_max_cworst,tluplus)           "$project(lib_root)/Back_End/rcx/gf22nm_1p10m_Cmax.tluplus"
set tech(rcx,10M,rc_max_cworst,nxtgrd)            "$project(lib_root)/Back_End/rcx/gf22nm_1p10m_Cmax.nxtgrd"
set tech(rcx,10M,rc_max_cworst,qrc)               "$project(lib_root)/Back_End/rcx/gf22nm_1p10m_Cmax.qrcTechFile"

# Signoff & DRC
set tech(10M,gds_layer_map_file)                  "$project(lib_root)/Back_End/layermap/gf22nm_10m_layermap.map"
set tech(10M,antenna_rule_file)                   "$project(lib_root)/Back_End/antenna/gf22nm_10m_antenna.rules"
set tech(10M,signal_em_constraint_file)           ""
set tech(10M,stream_files_for_merge)              ""

# ─────────────────────────────────────────────────────────────────────────────
# Metal Stack: 11M
# ─────────────────────────────────────────────────────────────────────────────

# Routing & Layers
set tech(11M,metal_count)                         11
set tech(11M,metal_layers)                        {M1 M2 M3 M4 M5 M6 M7 M8 M9 M10 M11}
set tech(11M,metal_stack_full)                    "1P11M_2Mx_6Cx_1Jx_2Qx_LB"
# 11M tech files — same .tf across tracks (foundry ships one per stack)
set tech(11M,9T,tech_file)                    "$project(lib_root)/Back_End/tech/gf22naphlogl24uhf116a_11M_2Mx_6Cx_1Jx_2Qx_LB.tf"
set tech(11M,7.5T,tech_file)                    "$project(lib_root)/Back_End/tech/gf22naphlogl24uhf116a_11M_2Mx_6Cx_1Jx_2Qx_LB.tf"
set tech(11M,8T,tech_file)                    "$project(lib_root)/Back_End/tech/gf22naphlogl24uhf116a_11M_2Mx_6Cx_1Jx_2Qx_LB.tf"
set tech(11M,min_routing_layer)                   "M2"
set tech(11M,max_routing_layer)                   "M10"
set tech(11M,clock_routing_layer_min)             "M4"
set tech(11M,clock_routing_layer_max)             "M8"

# Power Grid
set tech(11M,pg_strap_layers)                     "M10 M11"
set tech(11M,pg_strap_secondary)                  "M8 M9"
set tech(11M,pg_ring_layer_h)                     "M10"
set tech(11M,pg_ring_layer_v)                     "M11"

# Via & Metal Fill
set tech(11M,via_layers)                          {VIA1 VIA2 VIA3 VIA4 VIA5 VIA6 VIA7 VIA8 VIA9 VIA10}
set tech(11M,metal_fill_min_density)              20.0
set tech(11M,metal_fill_max_density)              80.0

# Parasitic Extraction
set tech(11M,tluplus_map)                         "$project(lib_root)/Back_End/rcx/gf22nm_tf_itf_tluplus.map"
set tech(rcx,11M,rc_max,tluplus)                  "$project(lib_root)/Back_End/rcx/gf22nm_1p11m_Cmax.tluplus"
set tech(rcx,11M,rc_max,nxtgrd)                   "$project(lib_root)/Back_End/rcx/gf22nm_1p11m_Cmax.nxtgrd"
set tech(rcx,11M,rc_max,qrc)                      "$project(lib_root)/Back_End/rcx/gf22nm_1p11m_Cmax.qrcTechFile"
set tech(rcx,11M,rc_typ,tluplus)                  "$project(lib_root)/Back_End/rcx/gf22nm_1p11m_Ctyp.tluplus"
set tech(rcx,11M,rc_typ,nxtgrd)                   "$project(lib_root)/Back_End/rcx/gf22nm_1p11m_Ctyp.nxtgrd"
set tech(rcx,11M,rc_typ,qrc)                      "$project(lib_root)/Back_End/rcx/gf22nm_1p11m_Ctyp.qrcTechFile"
set tech(rcx,11M,rc_min,tluplus)                  "$project(lib_root)/Back_End/rcx/gf22nm_1p11m_Cmin.tluplus"
set tech(rcx,11M,rc_min,nxtgrd)                   "$project(lib_root)/Back_End/rcx/gf22nm_1p11m_Cmin.nxtgrd"
set tech(rcx,11M,rc_min,qrc)                      "$project(lib_root)/Back_End/rcx/gf22nm_1p11m_Cmin.qrcTechFile"
set tech(rcx,11M,rc_max_cworst,tluplus)           "$project(lib_root)/Back_End/rcx/gf22nm_1p11m_Cmax.tluplus"
set tech(rcx,11M,rc_max_cworst,nxtgrd)            "$project(lib_root)/Back_End/rcx/gf22nm_1p11m_Cmax.nxtgrd"
set tech(rcx,11M,rc_max_cworst,qrc)               "$project(lib_root)/Back_End/rcx/gf22nm_1p11m_Cmax.qrcTechFile"

# Signoff & DRC
set tech(11M,gds_layer_map_file)                  "$project(lib_root)/Back_End/layermap/gf22nm_11m_layermap.map"
set tech(11M,antenna_rule_file)                   "$project(lib_root)/Back_End/antenna/gf22nm_11m_antenna.rules"
set tech(11M,signal_em_constraint_file)           ""
set tech(11M,stream_files_for_merge)              ""

# ── Physical Cells: 9T ──
set tech(9T,cell_height)                          "0.810"
set tech(9T,clock_buffers)                        "tcbn22cllbwp9tsvt_CKBUF4 tcbn22cllbwp9tsvt_CKBUF8 tcbn22cllbwp9tsvt_CKBUF16"
set tech(9T,clock_inverters)                      "tcbn22cllbwp9tsvt_CKINV4 tcbn22cllbwp9tsvt_CKINV8"
set tech(9T,decap)                                "GF22FDX_SC9T_SVT_DCAP4 GF22FDX_SC9T_SVT_DCAP8"
set tech(9T,delay_cells)                          "tcbn22cllbwp9tsvt_DEL1 tcbn22cllbwp9tsvt_DEL2 tcbn22cllbwp9tsvt_DEL4"
set tech(9T,dont_use)                             "*D0BWP9T* *OPTHOLD* *DEL*"
set tech(9T,endcap)                               "GF22FDX_SC9T_SVT_ENDCAP1"
set tech(9T,fillers)                              "GF22FDX_SC9T_SVT_FILL1 GF22FDX_SC9T_SVT_FILL2 GF22FDX_SC9T_SVT_FILL4 GF22FDX_SC9T_SVT_FILL8 GF22FDX_SC9T_SVT_FILL16 GF22FDX_SC9T_SVT_FILL32"
set tech(9T,hold_buffers)                         "tcbn22cllbwp9tsvt_BUFFD1 tcbn22cllbwp9tsvt_BUFFD2 tcbn22cllbwp9tsvt_BUFFD4"
set tech(9T,icg_cells)                            "tcbn22cllbwp9tsvt_CKLNQD1 tcbn22cllbwp9tsvt_CKLNQD2 tcbn22cllbwp9tsvt_CKLNQD4 tcbn22cllbwp9tsvt_CKLNQD8"
set tech(9T,isolation)                            "tcbn22cllbwp9tsvt_ISOLAND1 tcbn22cllbwp9tsvt_ISOLOR1 tcbn22cllbwp9tsvt_ISOLAND2 tcbn22cllbwp9tsvt_ISOLOR2"
set tech(9T,level_shifter)                        "tcbn22cllbwp9tsvt_LSDOWN1 tcbn22cllbwp9tsvt_LSUP1 tcbn22cllbwp9tsvt_LSDOWN2 tcbn22cllbwp9tsvt_LSUP2"
set tech(9T,power_switch)                         "tcbn22cllbwp9tsvt_HDRDWN1 tcbn22cllbwp9tsvt_HDRDWN2 tcbn22cllbwp9tsvt_HDRDWN4 tcbn22cllbwp9tsvt_HDRDWN8"
set tech(9T,site)                                 "GF22FDX_SC9T"
set tech(9T,site_width)                           "0.114"
set tech(9T,tie_cells)                            "tcbn22cllbwp9tsvt_TIEHI tcbn22cllbwp9tsvt_TIELO"
set tech(9T,well_tap)                             "GF22FDX_SC9T_SVT_FILLTIE1"

# ── Physical Cells: 7.5T ──
set tech(7.5T,cell_height)                        "0.675"
set tech(7.5T,clock_buffers)                      "tcbn22cllbwp7p5tsvt_CKBUF4 tcbn22cllbwp7p5tsvt_CKBUF8"
set tech(7.5T,clock_inverters)                    "tcbn22cllbwp7p5tsvt_CKINV4 tcbn22cllbwp7p5tsvt_CKINV8"
set tech(7.5T,decap)                              "GF22FDX_SC7P5T_SVT_DCAP4 GF22FDX_SC7P5T_SVT_DCAP8"
set tech(7.5T,delay_cells)                        "tcbn22cllbwp7p5tsvt_DEL1 tcbn22cllbwp7p5tsvt_DEL2 tcbn22cllbwp7p5tsvt_DEL4"
set tech(7.5T,dont_use)                           "*D0BWP7P5T* *OPTHOLD* *DEL*"
set tech(7.5T,endcap)                             "GF22FDX_SC7P5T_SVT_ENDCAP1"
set tech(7.5T,fillers)                            "GF22FDX_SC7P5T_SVT_FILL1 GF22FDX_SC7P5T_SVT_FILL2 GF22FDX_SC7P5T_SVT_FILL4 GF22FDX_SC7P5T_SVT_FILL8"
set tech(7.5T,hold_buffers)                       "tcbn22cllbwp7p5tsvt_BUFFD1 tcbn22cllbwp7p5tsvt_BUFFD2 tcbn22cllbwp7p5tsvt_BUFFD4"
set tech(7.5T,icg_cells)                          "tcbn22cllbwp7p5tsvt_CKLNQD1 tcbn22cllbwp7p5tsvt_CKLNQD2 tcbn22cllbwp7p5tsvt_CKLNQD4"
set tech(7.5T,isolation)                          "tcbn22cllbwp7p5tsvt_ISOLAND1 tcbn22cllbwp7p5tsvt_ISOLOR1 tcbn22cllbwp7p5tsvt_ISOLAND2 tcbn22cllbwp7p5tsvt_ISOLOR2"
set tech(7.5T,level_shifter)                      "tcbn22cllbwp7p5tsvt_LSDOWN1 tcbn22cllbwp7p5tsvt_LSUP1 tcbn22cllbwp7p5tsvt_LSDOWN2 tcbn22cllbwp7p5tsvt_LSUP2"
set tech(7.5T,power_switch)                       "tcbn22cllbwp7p5tsvt_HDRDWN1 tcbn22cllbwp7p5tsvt_HDRDWN2 tcbn22cllbwp7p5tsvt_HDRDWN4"
set tech(7.5T,site)                               "GF22FDX_SC7P5T"
set tech(7.5T,site_width)                         "0.116"
set tech(7.5T,tie_cells)                          "tcbn22cllbwp7p5tsvt_TIEHI tcbn22cllbwp7p5tsvt_TIELO"
set tech(7.5T,well_tap)                           "GF22FDX_SC7P5T_SVT_FILLTIE1"

# ── Physical Cells: 8T ──
set tech(8T,cell_height)                          "0.720"
set tech(8T,clock_buffers)                        "tcbn22cllbwp8tsvt_CKBUF4 tcbn22cllbwp8tsvt_CKBUF8"
set tech(8T,clock_inverters)                      "tcbn22cllbwp8tsvt_CKINV4 tcbn22cllbwp8tsvt_CKINV8"
set tech(8T,decap)                                "GF22FDX_SC8T_SVT_DCAP4 GF22FDX_SC8T_SVT_DCAP8"
set tech(8T,delay_cells)                          "tcbn22cllbwp8tsvt_DEL1 tcbn22cllbwp8tsvt_DEL2 tcbn22cllbwp8tsvt_DEL4"
set tech(8T,dont_use)                             "*D0BWP8T* *OPTHOLD* *DEL*"
set tech(8T,endcap)                               "GF22FDX_SC8T_SVT_ENDCAP1"
set tech(8T,fillers)                              "GF22FDX_SC8T_SVT_FILL1 GF22FDX_SC8T_SVT_FILL2 GF22FDX_SC8T_SVT_FILL4 GF22FDX_SC8T_SVT_FILL8"
set tech(8T,hold_buffers)                         "tcbn22cllbwp8tsvt_BUFFD1 tcbn22cllbwp8tsvt_BUFFD2 tcbn22cllbwp8tsvt_BUFFD4"
set tech(8T,icg_cells)                            "tcbn22cllbwp8tsvt_CKLNQD1 tcbn22cllbwp8tsvt_CKLNQD2 tcbn22cllbwp8tsvt_CKLNQD4"
set tech(8T,isolation)                            "tcbn22cllbwp8tsvt_ISOLAND1 tcbn22cllbwp8tsvt_ISOLOR1 tcbn22cllbwp8tsvt_ISOLAND2 tcbn22cllbwp8tsvt_ISOLOR2"
set tech(8T,level_shifter)                        "tcbn22cllbwp8tsvt_LSDOWN1 tcbn22cllbwp8tsvt_LSUP1 tcbn22cllbwp8tsvt_LSDOWN2 tcbn22cllbwp8tsvt_LSUP2"
set tech(8T,power_switch)                         "tcbn22cllbwp8tsvt_HDRDWN1 tcbn22cllbwp8tsvt_HDRDWN2 tcbn22cllbwp8tsvt_HDRDWN4"
set tech(8T,site)                                 "GF22FDX_SC8T"
set tech(8T,site_width)                           "0.114"
set tech(8T,tie_cells)                            "tcbn22cllbwp8tsvt_TIEHI tcbn22cllbwp8tsvt_TIELO"
set tech(8T,well_tap)                             "GF22FDX_SC8T_SVT_FILLTIE1"

# ── Body Bias (GF 22FDX specific — FD-SOI) ──
set tech(body_bias,fbb_voltage)                   "0.8"
set tech(body_bias,rbb_voltage)                   "-0.3"
set tech(body_bias,enabled)                       "true"

# ── Common Signoff ──
set tech(lib_cell_purpose_file)                   ""
set tech(filler_sidefile)                         ""
set tech(signal_em_constraint_format)             "sigem"
