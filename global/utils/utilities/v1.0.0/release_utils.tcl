#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow Release Utilities
# Standardized release procedures used by all release_data nodes.
# Provides: directory setup, file copy, validation, manifest, release notes.
#
# Usage: source $FLOW_DIR/global/utils/utilities/$UTILITIES_VERSION/release_utils.tcl
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
variable release_exit ""          ;# exit name when the tag defaulted to it

# ── Initialize Release ──────────────────────────────────────────────────────
# Release path structure: $release_path/$phase/$block_name/$flow_type/$release_tag
# Example: /proj/phoenix/releases/P2/cpu_core/v1.0.2
#
# All variables are MANDATORY — no fallbacks. Must be set in project_config.tcl
# or environment before release_data node runs.
#
# Required:
#   project(release,path)       — from project_config.tcl (e.g. /proj/phoenix/releases)
#   release phase               — the run's phase (cbflow_run_phase)
#   project(release,block_name) — block name (or derived from design_name)
#   CBFLOW_RELEASE_TAG          — release tag (or CBFLOW_RELEASE_VERSION env)
# ── Default release tag = the flow's exit for the phase ────────────────────
# The flow's exit is <flow>(smartgrid,milestone) (tool overlay, e.g. FP ->
# FP_EXIT, PNR -> BTO). When the phase does not have that exit
# (project(phase_exits)), the latest earlier exit it has is used — PNR in a
# phase with only {FP_EXIT PRO_EXIT} releases as PRO_EXIT. Order comes from
# MILESTONE_ORDER (release_config.tcl). Errors when any of these is missing.
proc default_exit_tag {flow_type phase} {
    global project MILESTONE_ORDER
    set _arr [string tolower $flow_type]
    upvar #0 $_arr _fa
    # Signoff flows (STA, PV, LEC…) release the exit they verify: the tag of
    # the input named by <flow>(release,exit_from), e.g. sta(input,release_tag).
    if {[info exists _fa(release,exit_from)] && $_fa(release,exit_from) ne ""} {
        set _k $_fa(release,exit_from)
        if {![info exists _fa($_k)] || $_fa($_k) eq ""} {
            error "ERROR: ${_arr}(release,exit_from) names ${_arr}($_k), which is not set"
        }
        return $_fa($_k)
    }
    if {![info exists _fa(smartgrid,milestone)] || $_fa(smartgrid,milestone) eq ""} {
        error "ERROR: project(release,tag) is not set and ${_arr}(smartgrid,milestone) (the flow's exit) is not configured — set one of them"
    }
    set _target $_fa(smartgrid,milestone)
    # An exit outside the PD milestone order (DFT: SCAN_INSERT_EXIT,
    # ATPG_PREPD_EXIT, ATPG_POSTPD_EXIT) is not part of a phase's PD exit
    # sequence: it releases under its own name.
    load_release_config
    if {[lsearch -exact $MILESTONE_ORDER $_target] < 0} { return $_target }
    if {![info exists project(phase_exits)]} {
        error "ERROR: project(phase_exits) is not set in the project config — needed for the default release tag"
    }
    if {![dict exists $project(phase_exits) $phase]} {
        error "ERROR: project(phase_exits) has no entry for phase $phase"
    }
    return [phase_exit_at_or_before $_target $phase]
}

# PD release_config.tcl (MILESTONE_ORDER / MILESTONE_STAGE_MAPPING) on demand
proc load_release_config {} {
    global MILESTONE_ORDER
    if {![info exists MILESTONE_ORDER]} {
        set _rc "$::env(FLOW_DIR)/PD/config/flow/$::env(FLOW_CONFIG_VERSION)/release_config.tcl"
        if {[file exists $_rc]} { uplevel #0 [list source $_rc] }
    }
    if {![info exists MILESTONE_ORDER]} {
        error "ERROR: MILESTONE_ORDER is not set (PD release_config.tcl)"
    }
}

# <target> when the phase has it (project(phase_exits)), else the latest
# earlier exit of MILESTONE_ORDER the phase has.
proc phase_exit_at_or_before {target phase} {
    global project MILESTONE_ORDER
    if {![info exists project(phase_exits)]} {
        error "ERROR: project(phase_exits) is not set in the project config"
    }
    if {![dict exists $project(phase_exits) $phase]} {
        error "ERROR: project(phase_exits) has no entry for phase $phase"
    }
    set _have [dict get $project(phase_exits) $phase]
    if {[lsearch -exact $_have $target] >= 0} { return $target }
    load_release_config
    set _idx [lsearch -exact $MILESTONE_ORDER $target]
    if {$_idx < 0} { error "ERROR: $target is not in MILESTONE_ORDER ($MILESTONE_ORDER)" }
    for {set i [expr {$_idx - 1}]} {$i >= 0} {incr i -1} {
        set _e [lindex $MILESTONE_ORDER $i]
        if {[lsearch -exact $_have $_e] >= 0} { return $_e }
    }
    error "ERROR: phase $phase has no exit at or before $target (project(phase_exits): $_have)"
}

# Exit released from a source stage: the milestone MILESTONE_STAGE_MAPPING
# maps to <stage> (place -> PLACE_EXIT, cts_opt -> CTS_EXIT, pro -> PRO_EXIT,
# signoff -> BTO / MTO: the flow's <flow>(smartgrid,milestone) when it is one
# of them), then the phase's exit at or before it. A stage no exit maps to
# (cts, route) cannot be released.
proc release_exit_for_stage {flow_type stage phase} {
    global MILESTONE_ORDER MILESTONE_STAGE_MAPPING
    load_release_config
    set _cands {}
    foreach _m $MILESTONE_ORDER {
        if {[info exists MILESTONE_STAGE_MAPPING($_m)] && $MILESTONE_STAGE_MAPPING($_m) eq $stage} { lappend _cands $_m }
    }
    if {![llength $_cands]} {
        error "ERROR: no exit maps to stage '$stage' (MILESTONE_STAGE_MAPPING) — release from a stage that has one (place, cts_opt, pro, signoff)"
    }
    upvar #0 [string tolower $flow_type] _fa
    set _target [lindex $_cands 0]
    if {[info exists _fa(smartgrid,milestone)] && $_fa(smartgrid,milestone) in $_cands} { set _target $_fa(smartgrid,milestone) }
    return [phase_exit_at_or_before $_target $phase]
}

proc exit_name {} { variable release_exit; return $release_exit }

# Exit-order gate: every exit before <exit> in the phase's exit plan must
# already be released for <block> (a
# <base>/<phase>/<block>/<FLOW>/<earlier exit>/RELEASE_COMPLETE of any flow).
# The plan is project(phase_exits) (PD) or, for an exit of another discipline,
# the project(phase_exits,<DISC>) list that holds it — disciplines are ordered
# independently.
proc check_exit_order {base phase block exit} {
    global project
    if {![info exists project(phase_exits)] || ![dict exists $project(phase_exits) $phase]} {
        error "ERROR: project(phase_exits) has no entry for phase $phase — cannot check the exit order"
    }
    set _exits [dict get $project(phase_exits) $phase]
    if {[lsearch -exact $_exits $exit] < 0} {
        set _exits {}
        foreach _k [array names project phase_exits,*] {
            if {[dict exists $project($_k) $phase] && [lsearch -exact [dict get $project($_k) $phase] $exit] >= 0} {
                set _exits [dict get $project($_k) $phase]
            }
        }
    }
    set _i [lsearch -exact $_exits $exit]
    if {$_i < 0} return
    set _missing {}
    foreach _e [lrange $_exits 0 [expr {$_i - 1}]] {
        if {![llength [glob -nocomplain -directory "$base/$phase/$block" -- "*/$_e/RELEASE_COMPLETE"]]} {
            lappend _missing $_e
        }
    }
    if {[llength $_missing]} {
        error "ERROR: exit order — $block $phase cannot release $exit before [join $_missing {, }] (release in order: [join $_exits { -> }]; nothing under $base/$phase/$block/<FLOW>/[lindex $_missing 0])"
    }
    ::handle_info "exit order OK: [join [lrange $_exits 0 $_i] { -> }] for $block $phase"
}

proc init {args_flow_type args_design_name args_run_dir args_phase {args_exit ""}} {
    variable release_dir; variable release_tag; variable release_phase; variable flow_type; variable design_name; variable run_dir

    set flow_type $args_flow_type
    set design_name $args_design_name
    set run_dir $args_run_dir
    set release_phase $args_phase

    global project flow

    # Detect test_mode — relaxed validation, uses placeholder values for
    # mandatory release vars so the test suite can exercise the full release
    # path without requiring per-project release config.
    set _test_mode [expr {[info exists flow(test_mode)] && [is_true $flow(test_mode)]}]

    # ── Release tag: project(release,tag) when set, else the exit name ───────
    # (args_exit: the exit the caller releases — e.g. its source stage's —
    # else default_exit_tag); test_mode uses a placeholder.
    variable release_exit; set release_exit $args_exit
    if {[info exists project(release,tag)] && $project(release,tag) ne ""} {
        set release_tag $project(release,tag)
    } elseif {$_test_mode} {
        set release_tag "test_release_tag"
        ::handle_info "test_mode: using placeholder release_tag=$release_tag"
    } else {
        if {$release_exit eq ""} { set release_exit [default_exit_tag $flow_type [::cbflow_run_phase]] }
        set release_tag $release_exit
        ::handle_info "release tag = exit name: $release_tag (project(release,tag) not set)"
    }

    # ── Release phase: always the run's phase (CBFLOW_PROJECT_PHASE) ─────────
    set release_phase [::cbflow_run_phase]

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

    # ── Assemble: $release_path/$phase/$block_name/$flow_type/$release_tag ───
    # Every flow releases each exit under its own FLOW dir, so PNR/PRO_EXIT,
    # STA/PRO_EXIT, PV/PRO_EXIT … sit side by side and never overwrite.
    set release_dir "$release_base/$release_phase/$block_name/$flow_type/$release_tag"
    # Exits release in phase order (project(phase_exits)): an implementation
    # flow releasing exit X needs every earlier exit of the phase released for
    # this block (any flow's <exit>/RELEASE_COMPLETE). Signoff flows release
    # the exit they verify (<flow>(release,exit_from)) — not gated here.
    upvar #0 [string tolower $flow_type] _fa
    if {!$_test_mode && $release_exit ne "" && ![info exists _fa(release,exit_from)]} {
        check_exit_order $release_base $release_phase $block_name $release_exit
    }
    # Versioned release: every release (first or re-release / override) is a
    # new version <FLOW>/.versions/<tag>/v<n>; <FLOW>/<tag> is the "current"
    # symlink to one version, moved to the new one when it stamps PASS
    # (stamp_complete) — readers keep reading <FLOW>/<tag>. The version's data
    # sits on a release disk (project(release,disks)) chosen by size.
    # Release lock (cbflow flow release lock): no release of a locked exit
    _check_release_lock $release_base $release_phase $block_name $flow_type $release_tag
    # Roles / access: releasing this exit needs a role on the project (core.access)
    if {!$_test_mode} { cbflow_can_or_error "release.exit:$release_tag" $block_name $flow_type }
    variable release_logical; variable release_version
    set release_logical $release_dir
    set _vroot [file join [file dirname $release_logical] .versions $release_tag]
    if {[file isdirectory $release_logical] && [file type $release_logical] ne "link"} {
        # legacy unversioned release -> v1
        file mkdir $_vroot
        file rename $release_logical [file join $_vroot v1]
        ::handle_info "Moved unversioned release $release_logical -> .versions/$release_tag/v1"
    }
    if {$_test_mode} {
        # test mode: stub data — one version, replaced each run and current at
        # once (test-mode handlers may not reach stamp_complete)
        set release_version "v1"
        set release_dir [file join $_vroot $release_version]
        file delete -force $release_dir
        file mkdir $_vroot
        _place_version $release_base $release_phase $block_name $flow_type $release_tag $release_dir $_test_mode
        _set_current
    } else {
        set _n 0
        foreach _v [glob -nocomplain -directory $_vroot -tails v*] {
            if {[regexp {^v(\d+)$} $_v -> _k] && $_k > $_n} { set _n $_k }
        }
        set release_version "v[incr _n]"
        set release_dir [file join $_vroot $release_version]
        file mkdir $_vroot
        _place_version $release_base $release_phase $block_name $flow_type $release_tag $release_dir $_test_mode
    }

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
    variable release_dir; variable release_files_copied; variable release_errors

    set src [_resolve_path $src_path]
    set dest "$release_dir/$dest_subdir/$dest_name"

    if {[file exists $src]} {
        # A release holds real files: dereference staged-input symlinks.
        while {[file type $src] eq "link"} {
            set src [file normalize [file join [file dirname $src] [file readlink $src]]]
        }
        _reserve_space $src
        file mkdir [file dirname $dest]
        file delete -force $dest
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
    variable release_dir; variable release_files_copied

    set count 0
    foreach src [glob -nocomplain $src_pattern] {
        set dest "$release_dir/$dest_subdir/[file tail $src]"
        while {[file type $src] eq "link"} {
            set src [file normalize [file join [file dirname $src] [file readlink $src]]]
        }
        _reserve_space $src
        file mkdir [file dirname $dest]
        file delete -force $dest
        file copy -force $src $dest
        lappend release_files_copied $dest
        incr count
    }
    return $count
}

# ── Validate Mandatory Files ────────────────────────────────────────────────
proc validate_mandatory_files {} {
    variable release_dir; variable release_phase; variable flow_type; variable run_dir; variable release_errors

    # Required state: init() must have run and populated these namespace
    # vars. The old `release_phase "P0"` + `flow_type "UNKNOWN"` fallbacks
    # silently misread any project with a non-P0 phase scheme and shunted
    # unknown-flow releases into the wrong tree. Fail loud instead.
    if {![info exists release_phase] || $release_phase eq ""} {
        error "release_utils::validate_mandatory_files: release_phase not set — call ::CBFlow::Release::init first (release_phase is the run's phase, cbflow_run_phase)"
    }
    if {![info exists flow_type] || $flow_type eq ""} {
        error "release_utils::validate_mandatory_files: flow_type not set — call ::CBFlow::Release::init first"
    }
    if {![info exists release_dir]} { set release_dir "" }
    if {![info exists run_dir]} { set run_dir "" }
    if {![info exists release_errors]} { set release_errors {} }

    # Source release_config.tcl if not already loaded
    if {![info exists ::release_exit_files]} {
        set release_config "$::env(FLOW_DIR)/PD/config/flow/$::env(FLOW_CONFIG_VERSION)/release_config.tcl"
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
        # Try milestone-specific first (this release's exit, else the latest
        # exit in MILESTONE_ORDER that has files), then phase-only
        variable release_exit
        if {$release_exit ne ""} {
            set _order [list $release_exit]
        } elseif {[info exists ::MILESTONE_ORDER]} {
            set _order [lreverse $::MILESTONE_ORDER]
        } else {
            error "ERROR: MILESTONE_ORDER is not set (PD release_config.tcl)"
        }
        foreach milestone $_order {
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

# ── Collect upstream `_release_tag` keys for sign-off traceability ──────────
proc _collect_upstream_tags {} {
    # Walk the known flow arrays for keys of the form
    # `<flow>(input,release_tag)` / `<flow>(input,<name>_release_tag)` — the tags THIS run was
    # built against. Scoped to real flow arrays (synth, pnr, …, rtl_lint,
    # upf_check, …) rather than every global so a stray debug array like
    # `test_fixtures(input,foo_release_tag)` can't pollute the provenance.
    set _known_flows [list \
        synth pnr synth_pnr fp fcfp sta lec clp pv emir popt eco \
        dft_insert_pass1 dft_insert_pass2 dft_insert_pass3 \
        scan_insert atpg gls_func gls_scan_mbist \
        spec_ramp planning tb_setup m1_exec m2_exec m3_exec m4_exec \
        eco_exec dv_signoff \
        rtl_lint rtl_cdc rtl_rdc upf_check]
    set tags [list]
    foreach _arr $_known_flows {
        if {![array exists ::$_arr]} continue
        foreach _k [array names ::$_arr] {
            if {[regexp {^input,([a-zA-Z0-9_]+_)?release_tag$} $_k]} {
                set _v [set ::${_arr}($_k)]
                if {$_v ne "" && [lsearch -exact $tags $_v] < 0} {
                    lappend tags $_v
                }
            }
        }
    }
    return $tags
}

# ── JSON string escape ──────────────────────────────────────────────────────
proc _json_escape {s} {
    # Escape the two characters that break JSON string literals. Order
    # matters: backslash FIRST so the subsequent `\"` injection isn't
    # itself backslash-escaped. Covers `v1\path` (Windows-like tags) and
    # `v"beta"` (someone's stray-quote tag).
    set s [string map {\\ \\\\ \" \\\"} $s]
    return $s
}

# ── Count sign-off violations from the standard RTL/UPF CSV format ──────────
proc _count_violations {run_dir flow_type} {
    # Looks for reports/<flow_lower>/violations_final.csv (RTL/UPF-check
    # shape) and counts rows with fatal/error/warn severities. Returns a
    # 3-tuple dict. Discipline-free: returns zero when CSV absent.
    # Skips the first line (header row) — pre-fix a header like
    # "severity,fatal,count" lowercased + string-matched "*,fatal,*"
    # and inflated the fatal count by 1 before counting any real row.
    set counts [dict create fatal 0 error 0 warn 0]
    set flow_lower [string tolower $flow_type]
    set csv "$run_dir/reports/${flow_lower}/violations_final.csv"
    if {![file exists $csv]} { return $counts }
    if {[catch {open $csv r} _fp]} { return $counts }
    set _line_num 0
    while {[gets $_fp _line] >= 0} {
        incr _line_num
        if {$_line_num == 1} continue   ;# skip header
        set lower [string tolower $_line]
        if {[string match "*,fatal,*" $lower] || [string match "fatal,*" $lower]} {
            dict incr counts fatal
        } elseif {[string match "*,error,*" $lower] || [string match "error,*" $lower]} {
            dict incr counts error
        } elseif {[string match "*,warn,*" $lower] || [string match "warning,*" $lower]} {
            dict incr counts warn
        }
    }
    close $_fp
    return $counts
}

# ── Generate Release Manifest ───────────────────────────────────────────────
proc generate_manifest {} {
    variable release_dir; variable release_tag; variable release_phase; variable flow_type; variable design_name; variable run_dir
    variable release_files_copied; variable release_errors

    set manifest_file "$release_dir/MANIFEST.json"
    set fd [open $manifest_file "w"]

    # Sign-off provenance — upstream tags consumed by this run, source SHA
    # (optional, from env), and violation counts from the standard
    # violations_final.csv shape. Downstream consumers read this to chain
    # releases ("Pass3 built against RTL_SIGNOFF_v2 which had 0 fatal, 0 error").
    set _upstream_tags [_collect_upstream_tags]
    set _source_sha ""
    if {[info exists ::env(GIT_SHA)]} { set _source_sha $::env(GIT_SHA) }
    set _viol [_count_violations $run_dir $flow_type]

    # Every string field below runs through _json_escape so a tag or
    # path containing a backslash / double-quote can't produce malformed
    # JSON. `run_dir` especially — users set workarea paths with spaces +
    # special chars which pass through here.
    puts $fd "\{"
    puts $fd "  \"flow\": \"[_json_escape $flow_type]\","
    puts $fd "  \"design\": \"[_json_escape $design_name]\","
    puts $fd "  \"release_tag\": \"[_json_escape $release_tag]\","
    puts $fd "  \"release_phase\": \"[_json_escape $release_phase]\","
    puts $fd "  \"timestamp\": \"[clock format [clock seconds] -format {%Y-%m-%dT%H:%M:%S}]\","
    puts $fd "  \"user\": \"[_json_escape $::env(USER)]\","
    puts $fd "  \"run_dir\": \"[_json_escape $run_dir]\","
    variable release_version
    if {[info exists release_version]} {
        puts $fd "  \"version\": \"[_json_escape $release_version]\","
        set _st [expr {[file type $release_dir] eq "link" ? [file readlink $release_dir] : [file normalize $release_dir]}]
        puts $fd "  \"storage\": \"[_json_escape $_st]\","
    }
    puts $fd "  \"signoff_status\": \{"
    # upstream_tags JSON array
    set _tags_json ""
    set _n [llength $_upstream_tags]
    for {set _i 0} {$_i < $_n} {incr _i} {
        append _tags_json "\"[_json_escape [lindex $_upstream_tags $_i]]\""
        if {$_i + 1 < $_n} { append _tags_json ", " }
    }
    puts $fd "    \"upstream_tags\": \[$_tags_json\],"
    puts $fd "    \"source_sha\": \"[_json_escape $_source_sha]\","
    puts $fd "    \"violation_counts\": \{"
    puts $fd "      \"fatal\": [dict get $_viol fatal],"
    puts $fd "      \"error\": [dict get $_viol error],"
    puts $fd "      \"warn\":  [dict get $_viol warn]"
    puts $fd "    \}"
    puts $fd "  \},"
    puts $fd "  \"files\": \["

    set count 0
    foreach f [lsort $release_files_copied] {
        incr count
        set rel_path [string range $f [expr {[string length $release_dir] + 1}] end]
        set comma [expr {$count < [llength $release_files_copied] ? "," : ""}]
        puts $fd "    \"[_json_escape $rel_path]\"$comma"
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
    variable release_dir; variable release_tag; variable release_phase; variable flow_type; variable design_name; variable run_dir
    variable release_files_copied; variable release_errors

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
    variable release_dir; variable release_tag; variable release_phase; variable flow_type; variable release_files_copied; variable release_errors

    set stamp_file "$release_dir/RELEASE_COMPLETE"
    # Atomic write: pre-fix, open-w + puts + close was non-atomic. Kill
    # between first `puts` and the STATUS=PASS line left RELEASE_COMPLETE
    # present but with no STATUS=PASS; validate_release_tag then flagged
    # the release as !PASS forever (manual retry sees stamp exists and
    # skips re-stamping — permanently poisoned release).
    set stamp_content ""
    append stamp_content "FLOW=$flow_type\n"
    append stamp_content "PHASE=$release_phase\n"
    append stamp_content "TAG=$release_tag\n"
    append stamp_content "FILES=[llength $release_files_copied]\n"
    append stamp_content "ERRORS=[llength $release_errors]\n"
    append stamp_content "STATUS=[expr {[llength $release_errors] == 0 ? {PASS} : {FAIL}}]\n"
    append stamp_content "TIMESTAMP=[clock format [clock seconds]]\n"
    atomic_write $stamp_file $stamp_content
    _version_log [expr {[llength $release_errors] == 0 ? {PASS} : {FAIL}}]
    # The new version becomes current only when it passed; a failed release
    # leaves the previous current version in place.
    if {[llength $release_errors] == 0} { _set_current }

    if {[llength $release_errors] == 0} {
        handle_info "RELEASE COMPLETE: $flow_type ($release_phase) — [llength $release_files_copied] files, 0 errors"
    } else {
        handle_warning "RELEASE INCOMPLETE: $flow_type ($release_phase) — [llength $release_files_copied] files, [llength $release_errors] errors"
    }
}

# ── Release locks ───────────────────────────────────────────────────────────
# <release>/<phase>/<block>/RELEASE_LOCKS (cbflow flow release lock): one line
# per locked exit — EXIT <tab> FLOWS (* | F1,F2) <tab> USER <tab> TIME <tab> REASON.
# A lock on exit X refuses releasing X, X_ECO<n>, X_v<n> from the flows it names
# — e.g. a block's BTO taken into its parent must not change under it.
proc _check_release_lock {base phase block flow tag} {
    set _f [file join $base $phase $block RELEASE_LOCKS]
    if {![file exists $_f]} return
    if {![regexp {^(.*)_(?:ECO|v)\d+$} $tag -> _fam]} { set _fam $tag }
    set _fh [open $_f]; set _lines [split [read $_fh] \n]; close $_fh
    foreach _l $_lines {
        if {$_l eq "" || [string index $_l 0] eq "#"} continue
        lassign [split $_l \t] _x _flows _user _time _reason
        if {$_x ne $_fam} continue
        if {$_flows ne "*" && [lsearch -exact [split $_flows ,] $flow] < 0} continue
        error "ERROR: release of $phase/$block $flow $tag refused — exit $_x is LOCKED by $_user ($_time): $_reason\n       unlock: cbflow flow release unlock --project <p> --phase $phase --block $block --exit $_x --reason <why>"
    }
}

# ── Versions / release disks ────────────────────────────────────────────────
# flow(release,<key>) from the run's config, else from the global
# flow_registry.tcl (read in a child interpreter — the run's flow() array is
# not touched). Errors when neither has it.
proc _release_key {key} {
    if {[info exists ::flow(release,$key)]} { return $::flow(release,$key) }
    set _reg [file join $::env(FLOW_DIR) global config flow $::env(FLOW_CONFIG_VERSION) flow_registry.tcl]
    set _i [interp create]
    set _v ""
    if {[catch {
        $_i eval [list source $_reg]
        set _v [$_i eval [list set flow(release,$key)]]
    } _e]} {
        interp delete $_i
        error "ERROR: flow(release,$key) is not set (global flow_registry.tcl: $_reg) — $_e"
    }
    interp delete $_i
    return $_v
}

# Available KB on the filesystem of path (nearest existing ancestor).
proc _df_avail_kb {path} {
    while {![file exists $path] && [file dirname $path] ne $path} { set path [file dirname $path] }
    set _out [exec df -Pk $path]
    return [lindex [lindex [split [string trim $_out] \n] end] 3]
}

proc _du_kb {path} {
    if {![file exists $path]} { return 0 }
    if {[catch {exec du -skL $path} _o]} { return 0 }
    return [lindex $_o 0]
}

# Size estimate (KB): max(newest previous release of this flow for the block,
# the run's work/<FLOW>/*/outputs) x flow(release,size_margin).
proc _estimate_kb {base phase block flow} {
    variable run_dir
    set _prev 0; set _pt 0
    foreach _rc [glob -nocomplain [file join $base $phase $block $flow * RELEASE_COMPLETE]] {
        if {[file mtime $_rc] > $_pt} { set _pt [file mtime $_rc]; set _prev [_du_kb [file dirname $_rc]] }
    }
    set _outs 0
    foreach _o [glob -nocomplain -types d [file join $run_dir work $flow * outputs]] {
        incr _outs [_du_kb $_o]
    }
    set _m [_release_key size_margin]
    return [expr {int(($_prev > $_outs ? $_prev : $_outs) * $_m)}]
}

# Create the version dir: on the base (no project(release,disks)), else on the
# release disk that fits estimate + flow(release,disk_min_free_gb) — policy
# flow(release,disk_policy): sticky (the disk holding most of the block's
# versions) | most_free. The version dir is then a symlink to
# <disk>/<phase>/<block>/<FLOW>/<tag>/v<n>. Errors when no disk fits.
proc _place_version {base phase block flow tag vdir test_mode} {
    global project
    variable disk_budget_kb; variable release_disk
    set _disks [expr {[info exists project(release,disks)] ? $project(release,disks) : {}}]
    if {$test_mode && ![llength $_disks]} {
        file mkdir $vdir
        set disk_budget_kb -1; set release_disk $base
        return
    }
    set _reserve [expr {int([_release_key disk_min_free_gb] * 1048576)}]
    set _need [_estimate_kb $base $phase $block $flow]
    if {![llength $_disks]} {
        set _free [_df_avail_kb $base]
        if {$_free - $_need < $_reserve} {
            error "ERROR: release disk $base: [format %.1f [expr {$_free/1048576.0}]] GB free, release needs ~[format %.2f [expr {$_need/1048576.0}]] GB + [_release_key disk_min_free_gb] GB reserve (flow(release,disk_min_free_gb)) — free space or add project(release,disks)"
        }
        file mkdir $vdir
        set disk_budget_kb [expr {$_free - $_reserve}]; set release_disk $base
        ::handle_info "Release disk $base: [format %.1f [expr {$_free/1048576.0}]] GB free, estimate [format %.2f [expr {$_need/1048576.0}]] GB"
        return
    }
    set _policy [_release_key disk_policy]
    set _best ""; set _bkey ""; set _report {}
    foreach _d $_disks {
        if {![file isdirectory $_d] || ![file writable $_d]} {
            lappend _report "$_d: not a writable directory"
            continue
        }
        set _free [_df_avail_kb $_d]
        lappend _report "$_d: [format %.1f [expr {$_free/1048576.0}]] GB free"
        if {$_free - $_need < $_reserve} continue
        set _held [llength [glob -nocomplain -types d [file join $_d $phase $block * * v*]]]
        set _key [expr {$_policy eq "sticky" ? [list $_held $_free] : [list $_free 0]}]
        if {$_best eq "" || [lindex $_key 0] > [lindex $_bkey 0] ||
            ([lindex $_key 0] == [lindex $_bkey 0] && [lindex $_key 1] > [lindex $_bkey 1])} {
            set _best $_d; set _bkey $_key; set _bfree $_free
        }
    }
    if {$_best eq ""} {
        error "ERROR: no release disk fits ~[format %.2f [expr {$_need/1048576.0}]] GB + [_release_key disk_min_free_gb] GB reserve: [join $_report {; }]"
    }
    set _phys [file join $_best $phase $block $flow $tag [file tail $vdir]]
    file mkdir $_phys
    exec ln -sfn $_phys $vdir
    set disk_budget_kb [expr {$_bfree - $_reserve}]; set release_disk $_best
    ::handle_info "Release disk ($_policy): $_best — [join $_report {; }]; estimate [format %.2f [expr {$_need/1048576.0}]] GB"
}

# Per-file guard: the release must not fill its disk past the reserve. The
# budget from _place_version is spent per file; df is re-read only when it
# runs out (others may have freed / used space).
proc _reserve_space {src} {
    variable disk_budget_kb; variable release_dir
    if {![info exists disk_budget_kb] || $disk_budget_kb < 0} return
    set _kb [expr {([file size $src] + 1023) / 1024}]
    if {$_kb > $disk_budget_kb} {
        set disk_budget_kb [expr {[_df_avail_kb $release_dir] - int([_release_key disk_min_free_gb] * 1048576)}]
        if {$_kb > $disk_budget_kb} {
            error "ERROR: release disk full — [file tail $src] needs [expr {$_kb/1024}] MB, [expr {max(0,$disk_budget_kb)/1024}] MB left above the reserve ($release_dir)"
        }
    }
    set disk_budget_kb [expr {$disk_budget_kb - $_kb}]
}

# <FLOW>/<tag> -> .versions/<tag>/v<n> (relative link; ln -sfn replaces it)
proc _set_current {} {
    variable release_logical; variable release_version; variable release_tag
    if {![info exists release_logical]} return
    if {[file exists $release_logical] && [file type $release_logical] ne "link"} {
        error "ERROR: $release_logical is a directory, not the current-version link"
    }
    exec ln -sfn [file join .versions $release_tag $release_version] $release_logical
    ::handle_info "Current: $release_logical -> $release_version"
}

# .versions/<tag>/HISTORY.log: <time> <user> release v<n> PASS|FAIL <disk>
proc _version_log {status} {
    variable release_logical; variable release_version; variable release_tag; variable release_disk
    if {![info exists release_logical]} return
    set _f [file join [file dirname $release_logical] .versions $release_tag HISTORY.log]
    set _fh [open $_f a]
    puts $_fh [join [list [clock format [clock seconds] -format {%Y-%m-%dT%H:%M:%S}] $::env(USER) release \
                         $release_version $status [expr {[info exists release_disk] ? $release_disk : ""}]] \t]
    close $_fh
}

# ── Summary Report ──────────────────────────────────────────────────────────
proc summary {} {
    variable release_dir; variable release_tag; variable release_phase; variable flow_type; variable release_files_copied; variable release_errors

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
        if {[catch {::cbflow_run_phase}]} {
            error "ERROR: the run's phase (CBFLOW_PROJECT_PHASE) is not set. Required to resolve release_tag '$tag'"
        }

        set release_base $project(release,path)
        set phase [::cbflow_run_phase]

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
    if {[catch {::cbflow_run_phase}]} { return 0 }
    if {![info exists project(release,block_name)] || $project(release,block_name) eq ""} { return 0 }

    set release_dir "$project(release,path)/[::cbflow_run_phase]/$project(release,block_name)/$tag"
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
    if {[catch {::cbflow_run_phase}]} { return {} }
    if {![info exists project(release,block_name)]} { return {} }

    set search_dir "$project(release,path)/[::cbflow_run_phase]/$project(release,block_name)/$tag"
    if {$subdir ne ""} { set search_dir "$search_dir/$subdir" }

    if {![file isdirectory $search_dir]} { return {} }
    return [glob -nocomplain -directory $search_dir *]
}

}  ;# end namespace ::CBFlow::InputResolve

