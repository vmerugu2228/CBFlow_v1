#!/usr/bin/env tclsh
# =============================================================================
# CBflow Project Configuration — bumblebee
# DFT OVERLAY (design-for-test side: workarea, release, DFT tooling)
#
# Sourced after global/config/project/<proj>/project_config.tcl, in parallel
# with PD/config/project/<proj>/project_pd_config.tcl. Keys are additive on
# project(...) — a DFT-only sparse-checkout clone needs this file to resolve
# workarea_path + release,path (both of which also live in the PD overlay).
#
# Keep this overlay narrow — only the cross-domain operator-facing keys that
# a DFT engineer actually needs. PD-specific keys (lib_root, lsf,*,
# default_tools PNR/STA/..., validation waivers) live exclusively in
# project_pd_config.tcl.
# =============================================================================

if {[info exists ::env(PROJECT_ROOT)]} {
    set ROOT_DIR $::env(PROJECT_ROOT)
} elseif {[info exists cbflow(root)]} {
    set ROOT_DIR [file dirname $cbflow(root)]
} else {
    set ROOT_DIR [file dirname [file dirname [file dirname [file dirname [file normalize [info script]]]]]]
}
set project(root_dir) $ROOT_DIR

set project(workarea_path) "/Users/vmerugu/projects/CBflow_clone/workarea"

# Library root + tech selection — DFT (ATPG, SCAN_INSERT, GLS_SCAN_MBIST)
# needs library views for scan chain analysis + pattern simulation.
# tech_config.tcl references $project(lib_root) at source-time, so this
# MUST be set before the tech cascade runs. Keep in sync with the PD +
# DV overlays so the full-tree clone sees consistent values.
set project(lib_root) "/tmp/test_libs/gf_22nm"
set project(track_variant) "9T"
set project(metal_stack) "11M"
set project(lib_config_tag) "LIB01"

set project(race,db_path) "/Users/vmerugu/projects/CBflow_clone/.race_area"

set project(release,path) "/Users/vmerugu/projects/CBflow_clone/test_releases"
set project(release,phase) "LC1"
set project(release,block_name) ""
set project(release,active_tag) "DFT_INSERT_PASS1"
set project(release,expiry_date) "2027-06-30"

set project(dashboard,developed_by) "SmartSoC CAD · Varun Reddy Merugu"

# =============================================================================
# DFT MasterConfig — seeded from DFT_FLOW_Dependencies_Input_Output.xlsx
# (sheet "MBIST Config Dependencies"). This block mirrors the spreadsheet's
# `$VAR` schema; the Tessent Pass1 handlers consume these keys to generate
# the Tessent TCL preamble.
#
#   spreadsheet $VAR                 →  project(dft,<key>)
#   -------------------------------     ----------------------------------
#   $PROJECT_NAME                       project(name)             (already set)
#   $SOC_STRUCTURE                      project(dft,soc_structure)
#   $DESIGN_STAGE                       project(dft,design_stage,default)
#   $DESIGN_TYPE_@<blk>                 project(dft,design_type,<block>)
#   $DESIGN_ID_@<blk>                   project(dft,design_id,<block>)
#   $RTL_FILES                          project(dft,rtl_files,<block>)
#   $BBOX_MODELS_@<blk>                 project(dft,bbox_models,<block>)
#   $LIBRARY_FILELISTS                  project(dft,mbist_libs,{masis,compiler})
#   $TCD_MEMORY_PATH                    project(dft,tcd_memory_path)
#   $CLOCKS                             project(dft,clocks,<block>)
#   $ASYNC_RESET / @<blk>               project(dft,async_reset,<default|block>)
#   $MBIST_TOOL                         project(dft,mbist_tool)
#   $INCLUDE_MEMORY_TEST_@<blk>         project(dft,include_memory_test,<block>)
#   $MBIST_COMMON_CONSTRAINTS           project(dft,mbist_common_constraints)
#   $MBIST_MEMORY_GROUPING_CONFIG_FILE  project(dft,mbist_grouping_file,<block>)
#   $MBIST_DEF_FILES                    project(dft,mbist_def_files)
#   $MBIST_MEMORY_STATIC_PORTS          project(dft,mbist_static_ports)
#   $ENCRYPTED_RTL                      project(dft,encrypted_rtl)
#   $ENCRYPTION_KEY_FILE                project(dft,encryption_key_file)
#   $WRITE_DESIGN_IMPORT_SCRIPT         project(dft,write_design_import_script)
# =============================================================================

# ── Hierarchy ────────────────────────────────────────────────────────────────
set project(dft,soc_structure,top)    "chip_top"
set project(dft,soc_structure,blocks) {processor_core gps_baseband}

# ── Design stage + per-block type ─────────────────────────────────────────────
set project(dft,design_stage,default)              "alpha"
set project(dft,design_type,default)               "RTL"
set project(dft,design_type,chip_top)              "SYNTH"
set project(dft,design_type,processor_core)        "RTL"
set project(dft,design_type,gps_baseband)          "RTL"

# ── Design IDs (per-block tag used for TSDB output subdirs) ───────────────────
set project(dft,design_id,chip_top)                "gate"
set project(dft,design_id,processor_core)          "rtl1"
set project(dft,design_id,gps_baseband)            "rtl1"

# ── RTL filelists per block ───────────────────────────────────────────────────
# Form 1: explicit list of files
# Form 2: single-item list containing "-f <filelist>" — the handler expands it
set project(dft,rtl_files,chip_top) {
    top/rtl/chip_top.v
    top/rtl/rds_process.v
    top/rtl/noncore_blocks/pll.v
    top/rtl/noncore_blocks/pad8_io_macro.v
    top/rtl/noncore_blocks/iopad_sel.v
    top/rtl/noncore_blocks/iopad.v
}
set project(dft,rtl_files,processor_core) {
    "-f wrapped_cores/processor_core/1.insert_mbist/rtl_file_list"
}
set project(dft,rtl_files,gps_baseband) {
    "-f wrapped_cores/gps_baseband/rtl/gps_baseband.fl"
}

# ── Blackbox models per block ─────────────────────────────────────────────────
# {instances} is a list of instance paths to blackbox; {modules} is a list of
# module names. Pass1 handler emits `set_system_mode setup; add_black_box ...`.
set project(dft,bbox_models,processor_core,instances) {}
set project(dft,bbox_models,processor_core,modules)   {SYNC_1RW_8Kx16}
set project(dft,bbox_models,gps_baseband,instances)   {}
set project(dft,bbox_models,gps_baseband,modules)     {}
set project(dft,bbox_models,chip_top,instances)       {}
set project(dft,bbox_models,chip_top,modules)         {}

# ── Memory + MBIST library filelists ──────────────────────────────────────────
set project(dft,mbist_libs,masis)    {library/memories/SYNC_1RW_8Kx16.tcd_memory}
set project(dft,mbist_libs,compiler) {library/memories/SYNC_1RW_8Kx16.v}
set project(dft,tcd_memory_path)     "library/memories"

# ── Clocks per block ──────────────────────────────────────────────────────────
set project(dft,clocks,chip_top)        {REF_CLK INCLK TEST_CLOCK_top}
set project(dft,clocks,processor_core)  {dco_clk inclk lfxt_clk taclk test_clock_u}
set project(dft,clocks,gps_baseband)    {clk test_clock_w}

# ── Async reset ───────────────────────────────────────────────────────────────
set project(dft,async_reset,default)         "RESET_N"
set project(dft,async_reset,gps_baseband)    "hw_rstn"
set project(dft,async_reset,processor_core)  "reset_n"

# ── MBIST tool + per-block enable ─────────────────────────────────────────────
set project(dft,mbist_tool) "tessent"

set project(dft,include_memory_test,chip_top)        "OFF"
set project(dft,include_memory_test,processor_core)  "ON"
set project(dft,include_memory_test,gps_baseband)    "OFF"

# ── MBIST constraints + grouping ──────────────────────────────────────────────
# mbist_common_constraints is a list of {pin value} pairs applied during BIST
# setup (e.g. hold RESET_N high so controller doesn't trip).
set project(dft,mbist_common_constraints) {
    {RESET_N 1}
}
set project(dft,mbist_grouping_file,processor_core) \
    "library/memories/SYNC_1RW_8Kx16.tcd_memory"

set project(dft,mbist_def_files)        ""
set project(dft,mbist_static_ports)     ""

# ── RTL encryption ────────────────────────────────────────────────────────────
set project(dft,encrypted_rtl)          "no"
set project(dft,encryption_key_file)    ""

# ── Downstream import script generation ───────────────────────────────────────
# When ON, Tessent emits a re-import script so synthesis can consume the
# DFT-inserted RTL. Maps to spreadsheet $WRITE_DESIGN_IMPORT_SCRIPT.
set project(dft,write_design_import_script) "ON"
