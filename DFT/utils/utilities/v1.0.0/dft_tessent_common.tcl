#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# DFT Tessent — shared TCL helpers
#
# Sourced by Pass1/Pass2/Pass3 handler command files (e.g. mbist_cfg1_tessent.tcl)
# AFTER the standard config.tcl + setup.tcl load. Provides utilities to
# translate project(dft,...) MasterConfig keys into Tessent TCL fragments.
#
# The MasterConfig schema is seeded in
# `<CBFLOW_DFT_DIR>/config/project/<proj>/v1.0.0/<proj>_dft_config.tcl` and
# documented against the owner spreadsheet
# `DFT_FLOW_Dependencies_Input_Output.xlsx` sheet "MBIST Config Dependencies".
# ═══════════════════════════════════════════════════════════════════════════════

# ─────────────────────────────────────────────────────────────────────────────
# dft_tessent_block_name --
#   Return the block/design name for this run.
#   Preference: run-time block > design_name > "unknown".
# ─────────────────────────────────────────────────────────────────────────────
proc dft_tessent_block_name {} {
    if {[info exists ::flow(block)]        && $::flow(block)        ne ""} { return $::flow(block) }
    if {[info exists ::flow(design_name)]  && $::flow(design_name)  ne ""} { return $::flow(design_name) }
    if {[info exists ::project(block)]     && $::project(block)     ne ""} { return $::project(block) }
    if {[info exists ::project(top_module)] && $::project(top_module) ne ""} { return $::project(top_module) }
    return "unknown"
}

# ─────────────────────────────────────────────────────────────────────────────
# dft_tessent_project_get key ?default?
#   Fetch project(dft,$key) with fallback. Covers both scalar + list values.
# ─────────────────────────────────────────────────────────────────────────────
proc dft_tessent_project_get {key {default ""}} {
    if {[info exists ::project(dft,$key)]} { return $::project(dft,$key) }
    return $default
}

# ─────────────────────────────────────────────────────────────────────────────
# dft_tessent_block_get block key ?default?
#   Fetch project(dft,<key>,<block>) with fallback to project(dft,<key>,default)
#   and finally the supplied default.
# ─────────────────────────────────────────────────────────────────────────────
proc dft_tessent_block_get {block key {default ""}} {
    if {[info exists ::project(dft,$key,$block)]}  { return $::project(dft,$key,$block) }
    if {[info exists ::project(dft,$key,default)]} { return $::project(dft,$key,default) }
    return $default
}

# ─────────────────────────────────────────────────────────────────────────────
# dft_tessent_resolve_rtl_filelist block
#   Return a {command-list} of TCL commands that read the RTL for `block`.
#   Handles both forms declared in project(dft,rtl_files,<block>):
#     Form A: {file1.v file2.v …}         → `read_verilog file1.v file2.v …`
#     Form B: {"-f some_filelist"}         → `read_verilog -f some_filelist`
# ─────────────────────────────────────────────────────────────────────────────
proc dft_tessent_resolve_rtl_filelist {block} {
    set files [dft_tessent_block_get $block "rtl_files" {}]
    if {$files eq ""} { return "" }

    # If the single element starts with "-f ", pass through as a filelist arg.
    if {[llength $files] == 1 && [string match "-f*" [lindex $files 0]]} {
        return "read_verilog [lindex $files 0]"
    }
    return "read_verilog $files"
}

# ─────────────────────────────────────────────────────────────────────────────
# dft_tessent_check_bbox_models block
#   Validate `project(dft,bbox_models,<block>,{instances,modules})` shape.
#   Returns a list of errors (empty = OK). Called by handlers before
#   emitting `add_black_box` directives.
# ─────────────────────────────────────────────────────────────────────────────
proc dft_tessent_check_bbox_models {block} {
    set errs [list]
    set inst_key "project(dft,bbox_models,$block,instances)"
    set mod_key  "project(dft,bbox_models,$block,modules)"
    foreach key [list $inst_key $mod_key] {
        # Not required — empty is valid (block has no blackboxes).
        if {![info exists ::$key]} { continue }
        set val [set ::$key]
        if {[catch {llength $val}]} {
            lappend errs "malformed list value for $key: $val"
        }
    }
    return $errs
}

# ─────────────────────────────────────────────────────────────────────────────
# dft_tessent_emit_master_preamble block fh
#   Write the MasterConfig preamble to filehandle $fh — the leading
#   set-of-globals + context + library-reads that every Pass1 stage
#   wants before issuing its own commands.
# ─────────────────────────────────────────────────────────────────────────────
proc dft_tessent_emit_master_preamble {block fh} {
    puts $fh "# ─── CBflow DFT MasterConfig preamble ───"
    puts $fh "# Generated from project(dft,...) overlay."
    puts $fh ""
    puts $fh "set BLOCK           $block"
    puts $fh "set DESIGN_STAGE    [dft_tessent_block_get $block design_stage [dft_tessent_project_get design_stage,default alpha]]"
    puts $fh "set DESIGN_TYPE     [dft_tessent_block_get $block design_type  [dft_tessent_project_get design_type,default RTL]]"
    puts $fh "set DESIGN_ID       [dft_tessent_block_get $block design_id    rtl1]"
    puts $fh "set MBIST_TOOL      [dft_tessent_project_get mbist_tool tessent]"
    puts $fh "set TCD_MEMORY_PATH [dft_tessent_project_get tcd_memory_path library/memories]"
    puts $fh "set ASYNC_RESET     [dft_tessent_block_get $block async_reset [dft_tessent_project_get async_reset,default RESET_N]]"
    puts $fh "set INCLUDE_MEMTEST [dft_tessent_block_get $block include_memory_test OFF]"
    set clks [dft_tessent_block_get $block clocks {}]
    if {$clks ne ""} {
        puts $fh "set CLOCKS          [list $clks]"
    } else {
        puts $fh "set CLOCKS          [list]"
    }
    puts $fh ""
}

# ─────────────────────────────────────────────────────────────────────────────
# dft_tessent_emit_memory_libs fh
#   Emit `read_cell_library` + `read_verilog` directives for memory models.
#   Reads project(dft,mbist_libs,{masis,compiler}).
# ─────────────────────────────────────────────────────────────────────────────
proc dft_tessent_emit_memory_libs {fh} {
    set masis    [dft_tessent_project_get mbist_libs,masis    {}]
    set compiler [dft_tessent_project_get mbist_libs,compiler {}]
    foreach f $masis {
        puts $fh "read_cell_library $f"
    }
    foreach f $compiler {
        puts $fh "read_verilog $f"
    }
}
