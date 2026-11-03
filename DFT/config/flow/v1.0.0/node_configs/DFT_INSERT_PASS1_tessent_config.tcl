#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# DFT_INSERT_PASS1 — Mentor Tessent Tool Configuration
# Sourced from DFT_INSERT_PASS1_config.tcl when tool=tessent
# Pass 1: Core DFT (MBIST + BSCAN) at block level.
# ═══════════════════════════════════════════════════════════════════════════════

# ┌─ Tessent Tool Settings ────────────────────────────────────────────────────┐
array set dft_insert_pass1 {
    tool,vendor   "mentor"
    tool,name     "tessent"
    tool,version  "v1.0.0"
    tool,args     "-shell -logfile tessent.log"
    tool,context  "patterns -scan"
}

# ┌─ TAP configuration knobs ─────────────────────────────────────────────────┐
# TAP pin names (TCK/TMS/TDI/TDO/TRST) and controller shape. Block-level
# overrides come from the user's dft_spec input file.
array set dft_insert_pass1 {
    tap,tck_pin        "TCK"
    tap,tms_pin        "TMS"
    tap,tdi_pin        "TDI"
    tap,tdo_pin        "TDO"
    tap,trst_pin       "TRST_N"
    tap,ir_width       8
    tap,instructions   {IDCODE BYPASS EXTEST SAMPLE PRELOAD HIGHZ}
}

# ┌─ BSCAN configuration knobs ───────────────────────────────────────────────┐
# Boundary-scan is only emitted when the block has a padring. The handler
# consults project(dft,has_padring,<block>) at runtime.
array set dft_insert_pass1 {
    bscan,enabled              "auto"
    bscan,cell_template        "BC_1"
    bscan,bypass_register      true
}

# ┌─ MBIST configuration knobs ───────────────────────────────────────────────┐
# Most MBIST data is in the MasterConfig overlay (project_dft_config.tcl):
# memory grouping, bbox models, clocks, async-reset, static-ports, etc.
# These knobs are tool-level defaults that apply when the MasterConfig
# doesn't override.
array set dft_insert_pass1 {
    mbist,controller_type      "smart_serial"
    mbist,wrap_memories        true
    mbist,bist_clock_domain    "tessent_clk"
    mbist,test_modes           {prod_test diag_test}
    mbist,retention_test       true
    mbist,parallel_retention   true
    mbist,bap_enabled          true
    mbist,controller_count     "auto"
}

# ┌─ Test-point insertion ────────────────────────────────────────────────────┐
array set dft_insert_pass1 {
    tpi,enabled                true
    tpi,mode                   "auto"
    tpi,coverage_target        99.0
}

# ┌─ DRC check knobs ─────────────────────────────────────────────────────────┐
# Any new DRC violation introduced by TPI (drc2 count > drc1 count) fails the
# stage. threshold=0 means strict (no new violations allowed).
array set dft_insert_pass1 {
    drc,level                  "strict"
    drc,new_violation_threshold 0
    drc,waiver_file            ""
}

# ┌─ Pattern generation (MBIST) ──────────────────────────────────────────────┐
array set dft_insert_pass1 {
    vgen,memory_test           true
    vgen,retention_test        true
    vgen,parallel_retention    true
    vgen,pattern_names         {MemoryBist_P1 MemoryBist_ParallelRetentionTest_P1}
}

# ┌─ Simulation prep ─────────────────────────────────────────────────────────┐
# Writes simulation_data_dictionary + ICLNetwork files for downstream VCS/Questa.
# The actual simulation runs in GLS_SCAN_MBIST (separate flow).
array set dft_insert_pass1 {
    sim,write_data_dictionary  true
    sim,write_icl_network      true
}

# ┌─ Design-import script generation ─────────────────────────────────────────┐
# When ON, Tessent writes a downstream re-import script so synthesis can
# consume the inserted RTL. Maps to spreadsheet $WRITE_DESIGN_IMPORT_SCRIPT.
array set dft_insert_pass1 {
    write_design_import_script "ON"
}
