#!/usr/bin/env tclsh
# =============================================================================
# CBflow Tech Config — SkyWater SKY130 (open PDK, sky130A)
# =============================================================================
# Foundry data for the open-source PD stack (vendor "opensource": Yosys,
# OpenROAD, OpenSTA, Magic, Netgen, KLayout). Same key schema as the
# commercial nodes, plus a handful of open-flow keys at the bottom.
#
# Paths are anchored on $project(lib_root) = the sky130A PDK directory
# (e.g. ~/eda/pdks/sky130A, copied from the CBflow tool container — see
# global/bin/cbflow-oss). Library .lib/.lef/.gds come from the library-
# manager tag (lib_config.tcl), generated with:
#   cbflow flow library-manager generate --tech skywater_130nm --tag OSS0 \
#       --lib-root $project(lib_root)/libs.ref/sky130_fd_sc_hd
# PDK version (ciel): see $project(lib_root)/CIEL_VERSION
# =============================================================================

# ── Identity ──────────────────────────────────────────────────────────────
set tech(node)                   "130nm"
set tech(process)                "SkyWater SKY130"
set tech(foundry)                "SkyWater"
set tech(pdk)                    "sky130A"
set tech(tracks_available)       "hd"
set tech(metal_stacks_available) "5M"
set tech(process_corners)        "ss tt ff"
# Manufacturing grid (µm) — the tech LEF's MANUFACTURINGGRID; GDS stream-out
# snaps its min-area patches to it.
set tech(manufacturing_grid)     0.005

# ── VT: sky130_fd_sc_hd is a single-VT library ────────────────────────────
set tech(vt_variants_available) {svt}
set tech(vt_pattern,svt)        "*"

# ── Library naming (consumed by library-manager) ──────────────────────────
# Track = library family: sky130_fd_sc_hd.lef / sky130_fd_sc_hd__<pvt>.lib
# ([._] keeps sky130_fd_sc_hdll out).
set tech(track_pattern,hd)      {*sky130_fd_sc_hd[._]*}
# sky130 lib names put temperature before voltage: __ss_n40C_1v60.lib.
# Normalised by library-manager to ss_1p60v_m40c.
set tech(lib_corner_regex)      {__(?P<corner>ss|tt|ff)_(?P<temp>n?\d+C)_(?P<voltage>\d+v\d+)(?:\.lib)?$}
# Packaging duplicates: every .lib also ships gzipped; ccsnoise variants
# carry the same corner as the plain lib.
set tech(lib_exclude)           {*.gz *_ccsnoise.lib}

# ── Signoff decks (open-source tools) ─────────────────────────────────────
set tech(rules,drc)              "$project(lib_root)/libs.tech/magic/sky130A.tech"
set tech(rules,lvs)              "$project(lib_root)/libs.tech/netgen/sky130A_setup.tcl"
set tech(rules,erc)              ""
set tech(rules,perc)             ""
set tech(rules,perc_ldl)         ""
set tech(rules,fill)             ""
set tech(rules,multi_patterning) ""
set tech(rules,xor)              ""
set tech(rules,antenna)          ""
set tech(spice,stdcell)          "$project(lib_root)/libs.ref/sky130_fd_sc_hd/spice/sky130_fd_sc_hd.spice"

# ── Tech LEF (per stack × track) ──────────────────────────────────────────
set tech(5M,hd,lef_tech)         "$project(lib_root)/libs.ref/sky130_fd_sc_hd/techlef/sky130_fd_sc_hd__nom.tlef"
set tech(5M,hd,tech_file)        "$project(lib_root)/libs.ref/sky130_fd_sc_hd/techlef/sky130_fd_sc_hd__nom.tlef"

# ── RC extraction (OpenRCX rule decks per RC corner) ──────────────────────
set tech(rc_corners_available)   {rc_max rc_min rc_typ}

# Views every library of a library-tag category must have —
# `library-manager check --lib_tag <TAG>` reports the matrix. lib = timing
# per corner the project's MMMC uses (mmmc_view_definition.tcl library sets),
# spef = per MMMC RC corner. stdcell rows are track x VT (gds / cdl / verilog:
# the tag, else tech(<track>,<view>_stdcell) — the PDK); memory / io / ip /
# analog rows are each macro; block rows are each hard block of the tag.
set tech(required_views,stdcell) {lef lib gds cdl verilog}
set tech(required_views,memory)  {lef gds cdl verilog lib}
set tech(required_views,io)      {lef gds cdl verilog lib}
set tech(required_views,ip)      {lef gds cdl verilog lib}
set tech(required_views,analog)  {lef gds cdl verilog lib}
set tech(required_views,block)   {lef gds netlist lvs_netlist cdl def sdc lib spef}
set tech(rcx_formats)            {openrcx tlef}
# OpenRCX deck: OpenROAD-flow-scripts' calibrated sky130 rules
# (flow/platforms/sky130hs/rcx_patterns.rules, installed beside the PDK in
# <pdks>/orfs_sky130hd/). The PDK's librelane decks
# (libs.tech/librelane/rules.openrcx.sky130A.<c>.spef_extractor) give NO
# capacitance with the image's OpenROAD (26Q4): every corner extracted the same
# ground caps and zero coupling (12.7 pF vs 27.4 pF on gcd P3) — only R applied.
# One calibrated corner; rc_max / rc_min scale it with adjust_rc factors taken
# from the librelane decks' own corner ratios (cap tables max/nom 1.19, min/nom
# 0.81; extracted R max/nom 1.094, min/nom 0.906).
set tech(rcx,5M,rc_typ,openrcx)  "$project(lib_root)/../orfs_sky130hd/rcx_patterns.rules"
set tech(rcx,5M,rc_min,openrcx)  "$project(lib_root)/../orfs_sky130hd/rcx_patterns.rules"
set tech(rcx,5M,rc_max,openrcx)  "$project(lib_root)/../orfs_sky130hd/rcx_patterns.rules"
set tech(rcx,5M,rc_min,openrcx_adjust) {res 0.906 cc 0.81 gndc 0.81}
set tech(rcx,5M,rc_max,openrcx_adjust) {res 1.094 cc 1.19 gndc 1.19}
# Corner tech LEFs carry the matching per-layer RC for placement-time estimates.
set tech(rcx,5M,rc_typ,tlef)     "$project(lib_root)/libs.ref/sky130_fd_sc_hd/techlef/sky130_fd_sc_hd__nom.tlef"
set tech(rcx,5M,rc_min,tlef)     "$project(lib_root)/libs.ref/sky130_fd_sc_hd/techlef/sky130_fd_sc_hd__min.tlef"
set tech(rcx,5M,rc_max,tlef)     "$project(lib_root)/libs.ref/sky130_fd_sc_hd/techlef/sky130_fd_sc_hd__max.tlef"

# ── Layer map / antenna ───────────────────────────────────────────────────
set tech(5M,gds_layer_map_file)  "$project(lib_root)/libs.tech/klayout/tech/sky130A.map"
set tech(5M,antenna_rule_file)   ""

# ── Metal stack: li1 + met1..met5 ─────────────────────────────────────────
set tech(5M,metal_count)             5
set tech(5M,metal_layers)            {li1 met1 met2 met3 met4 met5}
set tech(5M,metal_stack_full)        "sky130 li1+5M"
set tech(5M,min_routing_layer)       "met1"
set tech(5M,max_routing_layer)       "met5"
set tech(5M,clock_routing_layer_min) "met3"
set tech(5M,clock_routing_layer_max) "met5"
set tech(5M,pg_strap_layers)         "met4 met5"
set tech(5M,pg_strap_secondary)      ""
set tech(5M,pg_ring_layer_h)         "met5"
set tech(5M,pg_ring_layer_v)         "met4"
set tech(5M,via_layers)              {mcon via via2 via3 via4}
set tech(5M,metal_fill_min_density)  0.0
set tech(5M,metal_fill_max_density)  0.0
set tech(5M,signal_em_constraint_file) ""
set tech(5M,stream_files_for_merge)    "$project(lib_root)/libs.ref/sky130_fd_sc_hd/gds/sky130_fd_sc_hd.gds"
# Routing tracks (OpenROAD make_tracks): layer dir offset pitch
set tech(5M,tracks_file)             "$project(lib_root)/libs.tech/librelane/sky130_fd_sc_hd/tracks.info"
# Layers used for wire-RC estimates before extraction
set tech(5M,wire_rc_signal_layer)    "met2"
set tech(5M,wire_rc_clock_layer)     "met5"
# PDN (OpenROAD pdngen): followpin rails on met1, straps met4 (V) /
# met5 (H) as {layer width pitch offset} in µm — block-level pitch so a
# small die still gets several straps.
set tech(5M,pdn_rail_layer)          "met1"
set tech(5M,pdn_rail_width)          "0.48"
set tech(5M,pdn_strap_v)             {met4 1.6 27.14 13.57}
set tech(5M,pdn_strap_h)             {met5 1.6 27.2 13.6}

# ── Physical cells: sky130_fd_sc_hd (track "hd") ──────────────────────────
set tech(hd,cell_height)     "2.72"
set tech(hd,site)            "unithd"
set tech(hd,site_width)      "0.46"
set tech(hd,clock_buffers)   "sky130_fd_sc_hd__clkbuf_4 sky130_fd_sc_hd__clkbuf_8 sky130_fd_sc_hd__clkbuf_16"
set tech(hd,clock_root_buffer) "sky130_fd_sc_hd__clkbuf_16"
set tech(hd,clock_inverters) "sky130_fd_sc_hd__clkinv_4 sky130_fd_sc_hd__clkinv_8"
set tech(hd,decap)           "sky130_fd_sc_hd__decap_3 sky130_fd_sc_hd__decap_4 sky130_fd_sc_hd__decap_6 sky130_fd_sc_hd__decap_8 sky130_fd_sc_hd__decap_12"
set tech(hd,delay_cells)     "sky130_fd_sc_hd__dlygate4sd1_1 sky130_fd_sc_hd__dlygate4sd2_1 sky130_fd_sc_hd__dlygate4sd3_1"
# Synthesis exclusions (from the PDK's synth_excluded.cells)
set tech(hd,dont_use)        "sky130_fd_sc_hd__clkbuf* sky130_fd_sc_hd__clkinv* sky130_fd_sc_hd__clkinvlp* sky130_fd_sc_hd__clkdlybuf* sky130_fd_sc_hd__dlygate* sky130_fd_sc_hd__dlymetal* sky130_fd_sc_hd__tap* sky130_fd_sc_hd__decap* sky130_fd_sc_hd__fill* sky130_fd_sc_hd__diode* sky130_fd_sc_hd__lpflow_* sky130_fd_sc_hd__macro_sparecell sky130_fd_sc_hd__probe* sky130_fd_sc_hd__s*"
# Placement/route exclusions (from the PDK's pnr_excluded.cells)
set tech(hd,dont_use_pnr)    "sky130_fd_sc_hd__lpflow_* sky130_fd_sc_hd__probe*"
set tech(hd,endcap)          "sky130_fd_sc_hd__decap_3"
set tech(hd,fillers)         "sky130_fd_sc_hd__fill_1 sky130_fd_sc_hd__fill_2 sky130_fd_sc_hd__fill_4 sky130_fd_sc_hd__fill_8"
set tech(hd,hold_buffers)    "sky130_fd_sc_hd__dlygate4sd3_1 sky130_fd_sc_hd__buf_1 sky130_fd_sc_hd__buf_2"
# ── Memory macros (library tag category memory) ──────────────────────────
# Timing lib per standard-cell lib set: <lib set> -> the memory corner key of
# the tag (tech(lib,<corner>,timing,memory)). Every lib set a design times
# must be listed. The sky130 SRAM macros ship one corner (TT 1.8 V 25 C):
# STA times them there at every scenario (PVT mismatch flagged in STA).
set tech(memory,power_pins)  "vccd1"
set tech(memory,ground_pins) "vssd1"
set tech(memory,lib_set_map) {
    ff_1p56v_m40c  tt_1p8v_25c
    ff_1p65v_100c  tt_1p8v_25c
    ff_1p65v_m40c  tt_1p8v_25c
    ff_1p76v_m40c  tt_1p8v_25c
    ff_1p95v_100c  tt_1p8v_25c
    ff_1p95v_m40c  tt_1p8v_25c
    ss_1p28v_m40c  tt_1p8v_25c
    ss_1p35v_m40c  tt_1p8v_25c
    ss_1p40v_100c  tt_1p8v_25c
    ss_1p40v_m40c  tt_1p8v_25c
    ss_1p44v_m40c  tt_1p8v_25c
    ss_1p60v_100c  tt_1p8v_25c
    ss_1p60v_m40c  tt_1p8v_25c
    ss_1p76v_m40c  tt_1p8v_25c
    tt_1p80v_100c  tt_1p8v_25c
    tt_1p80v_25c   tt_1p8v_25c
}

set tech(hd,icg_cells)       "sky130_fd_sc_hd__dlclkp_1 sky130_fd_sc_hd__dlclkp_2 sky130_fd_sc_hd__dlclkp_4"
# Clock-gating cell synthesis inserts: <cell>/<enable>/<clock>/<gated clock>
# [/<test enable>] — the scan ICG when DFT is on (test enable -> scan enable)
set tech(hd,icg_cell)        "sky130_fd_sc_hd__dlclkp_1/GATE/CLK/GCLK"
set tech(hd,icg_scan_cell)   "sky130_fd_sc_hd__sdlclkp_1/GATE/CLK/GCLK/SCE"
set tech(hd,isolation)       ""
set tech(hd,level_shifter)   ""
set tech(hd,power_switch)    ""
set tech(hd,tie_cells)       "sky130_fd_sc_hd__conb_1"
set tech(hd,tie_hi)          "sky130_fd_sc_hd__conb_1/HI"
set tech(hd,tie_lo)          "sky130_fd_sc_hd__conb_1/LO"
set tech(hd,well_tap)        "sky130_fd_sc_hd__tapvpwrvgnd_1"
set tech(hd,well_tap_distance) 14
set tech(hd,driving_cell)    "sky130_fd_sc_hd__inv_2"
# Buffer for netlist buffering (yosys insbuf): <cell>/<in pin>/<out pin>
set tech(hd,buffer_cell)     "sky130_fd_sc_hd__buf_2/A/X"
set tech(hd,diode_cell)      "sky130_fd_sc_hd__diode_2"
set tech(hd,power_pins)      "VPWR VPB"
set tech(hd,ground_pins)     "VGND VNB"
set tech(hd,gds_stdcell)     "$project(lib_root)/libs.ref/sky130_fd_sc_hd/gds/sky130_fd_sc_hd.gds"
set tech(hd,cdl_stdcell)     "$project(lib_root)/libs.ref/sky130_fd_sc_hd/cdl/sky130_fd_sc_hd.cdl"
set tech(hd,verilog_stdcell) "$project(lib_root)/libs.ref/sky130_fd_sc_hd/verilog/sky130_fd_sc_hd.v"
# UDPs the cell models instantiate (gate-level simulation: GLS / scan patterns)
set tech(hd,verilog_primitives) "$project(lib_root)/libs.ref/sky130_fd_sc_hd/verilog/primitives.v"
# Yosys tech-mapping helpers shipped with the PDK
set tech(hd,yosys_latch_map) "$project(lib_root)/libs.tech/librelane/sky130_fd_sc_hd/latch_map.v"
set tech(hd,yosys_tribuf_map) "$project(lib_root)/libs.tech/librelane/sky130_fd_sc_hd/tribuff_map.v"

# ── Body bias: not used ───────────────────────────────────────────────────
set tech(body_bias,enabled)     "false"

set tech(lib_cell_purpose_file)       ""
set tech(filler_sidefile)             ""
set tech(signal_em_constraint_format) ""

# ── Open-flow tool decks (vendor "opensource") ────────────────────────────
set tech(pdk_root)              [file dirname $project(lib_root)]
set tech(magic,techfile)        "$project(lib_root)/libs.tech/magic/sky130A.tech"
set tech(magic,rcfile)          "$project(lib_root)/libs.tech/magic/sky130A.magicrc"
set tech(netgen,setup)          "$project(lib_root)/libs.tech/netgen/sky130A_setup.tcl"
set tech(klayout,lyt)           "$project(lib_root)/libs.tech/klayout/tech/sky130A.lyt"
set tech(klayout,lyp)           "$project(lib_root)/libs.tech/klayout/tech/sky130A.lyp"
set tech(klayout,def_layer_map) "$project(lib_root)/libs.tech/klayout/tech/sky130A.map"
set tech(klayout,drc)           "$project(lib_root)/libs.tech/klayout/drc/sky130A_mr.drc"
