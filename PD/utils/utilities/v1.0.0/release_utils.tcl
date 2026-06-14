#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow Release Utilities
# Standardized release procedures used by all release_data nodes.
# Provides: directory setup, file copy, validation, manifest, release notes.
#
# Usage: source $FLOW_DIR/utils/utilities/$UTILITIES_VERSION/release_utils.tcl
#        (sourced by release_data_*.tcl after standard header)
# ═══════════════════════════════════════════════════════════════════════════════

namespace eval ::CBFlow::Release {

# ── Variables ────────────────────────────────────────────────────────────────
variable release_dir ""
variable release_tag ""
variable release_phase ""
variable flow_type ""
variable design_name ""
variable run_dir ""
variable release_files_copied {}
variable release_errors {}

# ── Initialize Release ──────────────────────────────────────────────────────
# Release path structure: $release_path/$phase/$block_name/$release_tag
# Example: /proj/phoenix/releases/P2/cpu_core/v1.0.2
#
# All variables are MANDATORY — no fallbacks. Must be set in project_config.tcl
# or environment before release_data node runs.
#
# Required:
#   project(release,path)       — from project_config.tcl (e.g. /proj/phoenix/releases)
#   project(release,phase)      — P0/P1/P2/P3 (or CBFLOW_RELEASE_PHASE env)
#   project(release,block_name) — block name (or derived from design_name)
#   CBFLOW_RELEASE_TAG          — release tag (or CBFLOW_RELEASE_VERSION env)
proc init {args_flow_type args_design_name args_run_dir {args_phase "P0"}} {
    variable release_dir release_tag release_phase flow_type design_name run_dir

    set flow_type $args_flow_type
    set design_name $args_design_name
    set run_dir $args_run_dir
    set release_phase $args_phase

    global project flow

    # Detect test_mode — relaxed validation, uses placeholder values for
    # mandatory release vars so the test suite can exercise the full release
    # path without requiring per-project release config.
    set _test_mode [expr {[info exists flow(test_mode)] && $flow(test_mode) eq "true"}]

    # ── Release tag (MANDATORY in real runs; placeholder in test_mode) ───────
    if {[info exists project(release,tag)] && $project(release,tag) ne ""} {
        set release_tag $project(release,tag)
    } elseif {$_test_mode} {
        set release_tag "test_release_tag"
        ::handle_info "test_mode: using placeholder release_tag=$release_tag"
    } else {
        error "ERROR: project(release,tag) must be set in project_config.tcl for release"
    }

    # ── Release phase (MANDATORY in real runs; defaults to args_phase in test) ─
    if {[info exists project(release,phase)] && $project(release,phase) ne ""} {
        set release_phase $project(release,phase)
    } elseif {$_test_mode} {
        # already set from args_phase above
    } else {
        error "ERROR: project(release,phase) must be set in project_config.tcl for release"
    }

    # ── Block name (MANDATORY — from project_config or design_name) ──────────
    set block_name ""
    if {[info exists project(release,block_name)] && $project(release,block_name) ne ""} {
        set block_name $project(release,block_name)
    } elseif {$design_name ne ""} {
        set block_name $design_name
    } elseif {$_test_mode} {
        set block_name "test_block"
    } else {
        error "ERROR: project(release,block_name) or design_name must be set for release"
    }

    # ── Release base path (MANDATORY in real runs; test uses run_dir/release) ─
    if {[info exists project(release,path)] && $project(release,path) ne ""} {
        set release_base $project(release,path)
    } elseif {$_test_mode} {
        set release_base "$run_dir/release"
        ::handle_info "test_mode: using placeholder release_base=$release_base"
    } else {
        error "ERROR: project(release,path) must be set in project_config.tcl for release"
    }

    # ── Assemble: $release_path/$phase/$block_name/$release_tag ──────────────
    set release_dir "$release_base/$release_phase/$block_name/$release_tag"

    # Create directory structure from project config or defaults
    set subdirs {reports data netlist def gds spef sdc upf db docs}
    if {[info exists project(release,structure)]} {
        set subdirs $project(release,structure)
    }
    foreach subdir $subdirs {
        file mkdir "$release_dir/$subdir"
    }

    handle_info "Release initialized:"
    handle_info "  Flow:       $flow_type"
    handle_info "  Phase:      $release_phase"
    handle_info "  Block:      $block_name"
    handle_info "  Tag:        $release_tag"
    handle_info "  Release dir: $release_dir"
    return $release_dir
}

# ── Copy File to Release ────────────────────────────────────────────────────
proc copy_file {src_path dest_subdir dest_name} {
    variable release_dir release_files_copied release_errors

    set src [_resolve_path $src_path]
    set dest "$release_dir/$dest_subdir/$dest_name"

    if {[file exists $src]} {
        file mkdir [file dirname $dest]
        file copy -force $src $dest
        lappend release_files_copied $dest
        return 1
    } else {
        handle_warning "Release file not found: $src"
        lappend release_errors "MISSING: $src_path"
        return 0
    }
}

# ── Copy Glob Pattern ───────────────────────────────────────────────────────
proc copy_glob {src_pattern dest_subdir} {
    variable release_dir release_files_copied

    set count 0
    foreach src [glob -nocomplain $src_pattern] {
        set dest "$release_dir/$dest_subdir/[file tail $src]"
        file mkdir [file dirname $dest]
        file copy -force $src $dest
        lappend release_files_copied $dest
        incr count
    }
    return $count
}

# ── Validate Mandatory Files ────────────────────────────────────────────────
proc validate_mandatory_files {} {
    variable release_dir release_phase flow_type run_dir release_errors

    # Defensive defaults — if init() wasn't called or namespace var binding
    # didn't propagate, fall back so we don't crash on `$release_phase`.
    if {![info exists release_phase] || $release_phase eq ""} {
        set release_phase "P0"
    }
    if {![info exists flow_type] || $flow_type eq ""} {
        set flow_type "UNKNOWN"
    }
    if {![info exists release_dir]} { set release_dir "" }
    if {![info exists run_dir]} { set run_dir "" }
    if {![info exists release_errors]} { set release_errors {} }

    # Source release_config.tcl if not already loaded
    if {![info exists ::release_exit_files]} {
        set release_config "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/release_config.tcl"
        if {[file exists $release_config]} {
            source $release_config
        } else {
            handle_warning "release_config.tcl not found: $release_config"
            return 1
        }
    }

    # Get required files for this flow/phase
    set required_files {}
    if {[info commands get_release_exit_files] ne ""} {
        # Try milestone-specific first, then phase-only
        foreach milestone {BTO MTO PRO_EXIT CTS_EXIT PLACE_EXIT FP_EXIT} {
            set files [get_release_exit_files $flow_type $milestone $release_phase]
            if {[llength $files] > 0} {
                set required_files $files
                handle_info "Validating against: ${flow_type},${milestone},${release_phase} ([llength $files] required files)"
                break
            }
        }
        # Fallback: try flow,phase
        if {[llength $required_files] == 0} {
            set files [get_release_exit_files $flow_type "" $release_phase]
            if {[llength $files] > 0} {
                set required_files $files
                handle_info "Validating against: ${flow_type},${release_phase} ([llength $files] required files)"
            }
        }
    }

    if {[llength $required_files] == 0} {
        handle_info "No mandatory file list defined for $flow_type phase $release_phase"
        return 1
    }

    # Check each required file
    set missing {}
    set present 0
    foreach f $required_files {
        # Substitute ${design_name}
        set f_resolved [regsub -all {\$\{design_name\}} $f $::CBFlow::Release::design_name]
        set full_path "$run_dir/$f_resolved"
        if {[file exists $full_path]} {
            incr present
        } else {
            lappend missing $f_resolved
            lappend release_errors "MANDATORY MISSING: $f_resolved"
        }
    }

    set total [llength $required_files]
    handle_info "Mandatory file check: $present/$total present"
    if {[llength $missing] > 0} {
        handle_warning "Missing mandatory files ($release_phase):"
        foreach m $missing {
            handle_warning "  - $m"
        }
        return 0
    }
    return 1
}

# ── Generate Release Manifest ───────────────────────────────────────────────
proc generate_manifest {} {
    variable release_dir release_tag release_phase flow_type design_name run_dir
    variable release_files_copied release_errors

    set manifest_file "$release_dir/MANIFEST.json"
    set fd [open $manifest_file "w"]

    puts $fd "\{"
    puts $fd "  \"flow\": \"$flow_type\","
    puts $fd "  \"design\": \"$design_name\","
    puts $fd "  \"release_tag\": \"$release_tag\","
    puts $fd "  \"release_phase\": \"$release_phase\","
    puts $fd "  \"timestamp\": \"[clock format [clock seconds] -format {%Y-%m-%dT%H:%M:%S}]\","
    puts $fd "  \"user\": \"$::env(USER)\","
    puts $fd "  \"run_dir\": \"$run_dir\","
    puts $fd "  \"files\": \["

    set count 0
    foreach f [lsort $release_files_copied] {
        incr count
        set rel_path [string range $f [expr {[string length $release_dir] + 1}] end]
        set comma [expr {$count < [llength $release_files_copied] ? "," : ""}]
        puts $fd "    \"$rel_path\"$comma"
    }
    puts $fd "  \],"
    puts $fd "  \"total_files\": $count,"
    puts $fd "  \"errors\": [llength $release_errors]"
    puts $fd "\}"
    close $fd

    handle_info "Manifest generated: $manifest_file ($count files)"
    return $manifest_file
}

# ── Generate Release Notes ──────────────────────────────────────────────────
proc generate_release_notes {{notes ""}} {
    variable release_dir release_tag release_phase flow_type design_name run_dir
    variable release_files_copied release_errors

    set notes_file "$release_dir/RELEASE_NOTES.md"
    set fd [open $notes_file "w"]

    puts $fd "# Release Notes: $flow_type"
    puts $fd ""
    puts $fd "| Field | Value |"
    puts $fd "|-------|-------|"
    puts $fd "| Flow | $flow_type |"
    puts $fd "| Design | $design_name |"
    puts $fd "| Release Tag | $release_tag |"
    puts $fd "| Phase | $release_phase |"
    puts $fd "| Date | [clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}] |"
    puts $fd "| User | $::env(USER) |"
    puts $fd "| Run | [file tail $run_dir] |"
    puts $fd ""

    if {$notes ne ""} {
        puts $fd "## Notes"
        puts $fd "$notes"
        puts $fd ""
    }

    puts $fd "## Deliverables ($release_phase)"
    puts $fd ""
    puts $fd "| # | File | Size |"
    puts $fd "|---|------|------|"
    set i 0
    foreach f [lsort $release_files_copied] {
        incr i
        set rel_path [string range $f [expr {[string length $release_dir] + 1}] end]
        set size "N/A"
        catch { set size "[expr {[file size $f] / 1024}] KB" }
        puts $fd "| $i | $rel_path | $size |"
    }

    if {[llength $release_errors] > 0} {
        puts $fd ""
        puts $fd "## Issues"
        puts $fd ""
        foreach err $release_errors {
            puts $fd "- $err"
        }
    }

    puts $fd ""
    puts $fd "---"
    puts $fd "*Generated by CBflow Release Utilities*"
    close $fd

    handle_info "Release notes generated: $notes_file"
    return $notes_file
}

# ── Create Release Complete Stamp ───────────────────────────────────────────
proc stamp_complete {} {
    variable release_dir release_tag release_phase flow_type release_files_copied release_errors

    set stamp_file "$release_dir/RELEASE_COMPLETE"
    set fd [open $stamp_file "w"]
    puts $fd "FLOW=$flow_type"
    puts $fd "PHASE=$release_phase"
    puts $fd "TAG=$release_tag"
    puts $fd "FILES=[llength $release_files_copied]"
    puts $fd "ERRORS=[llength $release_errors]"
    puts $fd "STATUS=[expr {[llength $release_errors] == 0 ? {PASS} : {FAIL}}]"
    puts $fd "TIMESTAMP=[clock format [clock seconds]]"
    close $fd

    if {[llength $release_errors] == 0} {
        handle_info "RELEASE COMPLETE: $flow_type ($release_phase) — [llength $release_files_copied] files, 0 errors"
    } else {
        handle_warning "RELEASE INCOMPLETE: $flow_type ($release_phase) — [llength $release_files_copied] files, [llength $release_errors] errors"
    }
}

# ── Summary Report ──────────────────────────────────────────────────────────
proc summary {} {
    variable release_dir release_tag release_phase flow_type release_files_copied release_errors

    handle_info "═══════════════════════════════════════════════════════════"
    handle_info " Release Summary: $flow_type"
    handle_info "═══════════════════════════════════════════════════════════"
    handle_info "  Tag:         $release_tag"
    handle_info "  Phase:       $release_phase"
    handle_info "  Directory:   $release_dir"
    handle_info "  Files:       [llength $release_files_copied]"
    handle_info "  Errors:      [llength $release_errors]"
    handle_info "  Status:      [expr {[llength $release_errors] == 0 ? {PASS} : {FAIL}}]"
    handle_info "═══════════════════════════════════════════════════════════"
}

# ── Internal: Resolve relative path ─────────────────────────────────────────
proc _resolve_path {path} {
    variable run_dir
    if {[file pathtype $path] eq "absolute"} { return $path }
    return "$run_dir/$path"
}

}  ;# end namespace ::CBFlow::Release

# ═══════════════════════════════════════════════════════════════════════════════
# INPUT RESOLUTION — Resolve upstream release files for downstream flows
#
# All configuration comes from user_config.tcl and project_config.tcl.
# NO environment variable lookups — everything is in TCL arrays.
#
# User sets in user_config.tcl (one of two modes):
#
#   Mode 1 — Release tag (auto-resolves file from release directory):
#     set pnr(input,netlist_release_tag) "v1.0.2"
#     → resolves to: project(release,path)/project(release,phase)/
#                     project(release,block_name)/v1.0.2/netlist/${design_name}.v
#
#   Mode 2 — Direct path (existing behavior):
#     set pnr(input,netlist) "/full/path/to/netlist.v"
#
# Release tag takes priority. Direct path used if no release_tag is set.
#
# Required in project_config.tcl:
#   project(release,path)       — base release path (e.g. /proj/phoenix/releases)
#   project(release,phase)      — design phase (P0/P1/P2/P3)
#   project(release,block_name) — block name (e.g. cpu_core)
# ═══════════════════════════════════════════════════════════════════════════════

namespace eval ::CBFlow::InputResolve {

# ── Resolve a single input file ─────────────────────────────────────────────
proc resolve {flow_array_name input_type upstream_flow subdir filename} {
    upvar #0 $flow_array_name fa
    global project

    set tag_key  "input,${input_type}_release_tag"
    set dir_key  "input,${input_type}"

    # ── Mode 1: Release tag from user_config ─────────────────────────────
    if {[info exists fa($tag_key)] && $fa($tag_key) ne ""} {
        set tag $fa($tag_key)

        # All from project_config — no env vars
        if {![info exists project(release,path)] || $project(release,path) eq ""} {
            error "ERROR: project(release,path) not set in project_config.tcl. Required to resolve release_tag '$tag'"
        }
        if {![info exists project(release,phase)] || $project(release,phase) eq ""} {
            error "ERROR: project(release,phase) not set in project_config.tcl. Required to resolve release_tag '$tag'"
        }

        set release_base $project(release,path)
        set phase $project(release,phase)

        # Block name: user_config per-input override > project_config > design_name
        set block ""
        if {[info exists fa(input,${input_type}_release_block)] && $fa(input,${input_type}_release_block) ne ""} {
            set block $fa(input,${input_type}_release_block)
        } elseif {[info exists project(release,block_name)] && $project(release,block_name) ne ""} {
            set block $project(release,block_name)
        } elseif {[info exists fa(design_name)] && $fa(design_name) ne ""} {
            set block $fa(design_name)
        } else {
            global flow
            if {[info exists flow(design_name)]} { set block $flow(design_name) }
        }
        if {$block eq ""} {
            error "ERROR: Cannot resolve block_name. Set project(release,block_name) in project_config.tcl"
        }

        # Assemble: $release_path/$phase/$block/$tag/$subdir/$filename
        set resolved "$release_base/$phase/$block/$tag/$subdir/$filename"

        if {[file exists $resolved]} {
            handle_info "Input resolved (release_tag=$tag): $input_type → $resolved"
            return $resolved
        } else {
            handle_warning "Release file not found: $resolved"
            handle_warning "  release_path=$release_base phase=$phase block=$block tag=$tag"
            error "ERROR: Input '$input_type' not found in release '$tag': $resolved"
        }
    }

    # ── Mode 2: Direct file path from user_config ────────────────────────
    if {[info exists fa($dir_key)] && $fa($dir_key) ne ""} {
        set direct $fa($dir_key)
        if {[file exists $direct]} {
            handle_info "Input resolved (direct): $input_type → $direct"
            return $direct
        } else {
            error "ERROR: Input file not found: $direct"
        }
    }

    # ── Neither set ──────────────────────────────────────────────────────
    error "ERROR: Input '$input_type' not configured in user_config.tcl. Set ${flow_array_name}($tag_key) or ${flow_array_name}($dir_key)"
}

# ── Resolve optional (returns empty string if not configured) ────────────────
proc resolve_optional {flow_array_name input_type upstream_flow subdir filename} {
    if {[catch {set result [resolve $flow_array_name $input_type $upstream_flow $subdir $filename]} err]} {
        return ""
    }
    return $result
}

# ── Validate release tag (check RELEASE_COMPLETE stamp) ──────────────────────
proc validate_release_tag {tag} {
    global project

    if {![info exists project(release,path)] || $project(release,path) eq ""} { return 0 }
    if {![info exists project(release,phase)] || $project(release,phase) eq ""} { return 0 }
    if {![info exists project(release,block_name)] || $project(release,block_name) eq ""} { return 0 }

    set release_dir "$project(release,path)/$project(release,phase)/$project(release,block_name)/$tag"
    set stamp "$release_dir/RELEASE_COMPLETE"

    if {[file exists $stamp]} {
        set fd [open $stamp r]
        set content [read $fd]
        close $fd
        if {[string match "*STATUS=PASS*" $content]} {
            handle_info "Release tag '$tag' validated: PASS at $release_dir"
            return 1
        } else {
            handle_warning "Release tag '$tag' exists but status is not PASS"
            return 0
        }
    }

    handle_warning "Release tag '$tag' not found at: $release_dir"
    return 0
}

# ── List available files in a release ────────────────────────────────────────
proc list_release_files {tag {subdir ""}} {
    global project

    if {![info exists project(release,path)]} { return {} }
    if {![info exists project(release,phase)]} { return {} }
    if {![info exists project(release,block_name)]} { return {} }

    set search_dir "$project(release,path)/$project(release,phase)/$project(release,block_name)/$tag"
    if {$subdir ne ""} { set search_dir "$search_dir/$subdir" }

    if {![file isdirectory $search_dir]} { return {} }
    return [glob -nocomplain -directory $search_dir *]
}

}  ;# end namespace ::CBFlow::InputResolve

