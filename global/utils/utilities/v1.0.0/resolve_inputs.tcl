#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow — Input Resolution Utility
# Resolves downstream flow inputs from upstream run manifests or release tags.
#
# Priority: from_run (manifest) > release_tag > explicit paths (user_config)
#
# Usage:
#   source resolve_inputs.tcl
#   resolve_flow_inputs $flow_type $run_dir
# ═══════════════════════════════════════════════════════════════════════════════

namespace eval ::CBFlow::InputResolve {

    # Map: downstream flow input variable → manifest key
    variable handshake_map
    array set handshake_map {
        STA,netlist         "netlist,pt"
        STA,sdc_func_file   "sdc,func"
        STA,def_file        "def"

        LEC,netlist_revised "netlist,logic"
        LEC,netlist_golden  "netlist,logic"

        CLP,netlist         "netlist,vc_lp"
        CLP,upf_file        "upf"
        CLP,reference_netlist "netlist,vc_lp"

        PV,gds              "gds"
        PV,netlist           "netlist,lvs"
        PV,def_file         "def"

        EMIR,netlist        "netlist,logic"
        EMIR,def_file       "def"
        EMIR,spef           "spef"
        EMIR,gds            "gds"

        POPT,netlist        "netlist,pt"
        POPT,sdc            "sdc"
        POPT,spef           "spef"

        ECO,netlist         "netlist,logic"
        ECO,def_file        "def"
    }

    # Auto-generate STA per-mode SDC handshake entries from operating_modes
    if {[array exists ::operating_modes]} {
        foreach _mode [array names ::operating_modes] {
            set handshake_map(STA,sdc,$_mode) "sdc,$_mode"
        }
    }

    proc resolve_flow_inputs {flow_type run_dir} {
        set arr [string tolower $flow_type]

        # Check if already resolved (persisted file exists from setup subnode)
        set resolved_file "$run_dir/setup/resolved_inputs.tcl"
        if {[file exists $resolved_file]} {
            source $resolved_file
            puts "INFO: Loaded resolved inputs from $resolved_file"
            return 0
        }

        set resolved_vars [list]

        # ── Priority 1: from_run (read upstream manifest) ──
        if {[info exists ::${arr}(input,from_run)]} {
            set upstream_run [set ::${arr}(input,from_run)]
            if {$upstream_run ne "" && [file isdir $upstream_run]} {
                set count [resolve_from_run $flow_type $arr $upstream_run resolved_vars]
                if {$count > 0} {
                    puts "INFO: Resolved $count inputs from upstream run: $upstream_run"
                    _persist_resolved $resolved_file $resolved_vars
                    return $count
                }
            }
        }

        # ── Priority 2: release_tag ──
        # Two forms supported:
        #   (a) Generic — one tag drives every input for this flow:
        #         set sta(input,release_tag) "P0_BTO"
        #   (b) Per-input — each input type can pull from its own tag:
        #         set sta(input,netlist_release_tag) "P0_BTO"
        #         set sta(input,sdc_release_tag)     "P1_STA"
        #         set sta(input,def_release_tag)     "P0_BTO"
        # The per-input form was the documented pattern in
        # release_utils.tcl but resolve_flow_inputs only checked the
        # generic form — leaving fixtures like uc_STA_release_tag.tcl
        # with NO_SOURCE from the input handler. Both forms are handled
        # here now.
        set _total_from_tag 0

        if {[info exists ::${arr}(input,release_tag)]} {
            set tag [set ::${arr}(input,release_tag)]
            if {$tag ne ""} {
                set _total_from_tag [expr {$_total_from_tag +
                    [resolve_from_tag $flow_type $arr $tag $run_dir resolved_vars]}]
            }
        }

        # Per-input: enumerate every ${arr}(input,<TYPE>_release_tag) key and
        # resolve just that one input from the named tag. This lets a single
        # flow mix-and-match tags across inputs.
        foreach _k [array names ::$arr "input,*_release_tag"] {
            regexp {input,(.+)_release_tag$} $_k -> _input_type
            set _tag [set ::${arr}($_k)]
            if {$_tag eq ""} continue
            # If already resolved (either by (a) or an explicit user_config
            # path), don't clobber.
            if {[info exists ::${arr}(input,${_input_type})] && \
                [set ::${arr}(input,${_input_type})] ne ""} continue
            set _n [resolve_single_from_tag $flow_type $arr $_input_type \
                                            $_tag $run_dir resolved_vars]
            set _total_from_tag [expr {$_total_from_tag + $_n}]
        }

        if {$_total_from_tag > 0} {
            puts "INFO: Resolved $_total_from_tag inputs from release_tag markers"
            _persist_resolved $resolved_file $resolved_vars
            return $_total_from_tag
        }

        # ── Priority 3: explicit paths already in user_config — no action ──
        return 0
    }

    proc _persist_resolved {filepath vars_list} {
        # Write resolved variables to file so all subnodes can source it
        file mkdir [file dirname $filepath]
        set fh [open $filepath "w"]
        puts $fh "# Resolved inputs — auto-generated by resolve_flow_inputs"
        puts $fh "# Generated: [clock format [clock seconds]]"
        puts $fh ""
        foreach {varname value} $vars_list {
            puts $fh "set $varname \"$value\""
        }
        close $fh
        puts "INFO: Persisted resolved inputs to $filepath"
    }

    proc resolve_from_run {flow_type arr upstream_run {vars_var ""}} {
        variable handshake_map
        if {$vars_var ne ""} { upvar 1 $vars_var resolved_vars }

        # Search for output_manifest.tcl in upstream run
        set manifest_paths [list]
        foreach d [glob -nocomplain "$upstream_run/work/*/"] {
            foreach m [glob -nocomplain "${d}export_data*/results/output_manifest.tcl" \
                                        "${d}release_data*/results/output_manifest.tcl"] {
                lappend manifest_paths $m
            }
        }

        if {[llength $manifest_paths] == 0} {
            puts "WARNING: No output_manifest.tcl found in $upstream_run"
            return 0
        }

        set manifest_file [lindex [lsort -decreasing $manifest_paths] 0]
        puts "INFO: Reading upstream manifest: $manifest_file"

        if {[catch {source $manifest_file} err]} {
            puts "WARNING: Failed to read manifest: $err"
            return 0
        }

        set count 0
        set flow_upper [string toupper $flow_type]
        # Loop variables renamed with `_` prefix to avoid shadowing: in TCL
        # foreach loop vars persist after the loop, so a later proc call that
        # uses `hkey` as a local would see the loop's last-iter value if
        # `hkey` was never reset. Prefix convention signals "scoped-to-loop".
        foreach {_hkey _mkey} [array get handshake_map] {
            set parts [split $_hkey ","]
            if {[lindex $parts 0] ne $flow_upper} continue
            set hinput [lindex $parts 1]

            if {[info exists manifest($_mkey)] && $manifest($_mkey) ne ""} {
                set fpath $manifest($_mkey)
                if {[file exists $fpath]} {
                    if {![info exists ::${arr}(input,${hinput})] || [set ::${arr}(input,${hinput})] eq ""} {
                        set ::${arr}(input,${hinput}) $fpath
                        puts "INFO:   ${arr}(input,${hinput}) = $fpath"
                        if {$vars_var ne ""} {
                            lappend resolved_vars "${arr}(input,${hinput})" $fpath
                        }
                        incr count
                    }
                }
            }
        }
        return $count
    }

    # Resolve exactly one input type from a release tag. Used when the
    # user_config declares a per-input marker like
    # `sta(input,netlist_release_tag) "P0_BTO"` — only netlist should be
    # pulled from that tag, not every input.
    proc resolve_single_from_tag {flow_type arr input_type tag run_dir {vars_var ""}} {
        if {$vars_var ne ""} { upvar 1 $vars_var _out_vars }
        variable handshake_map

        # release_config.tcl is always needed for the `flow_input_handshake`
        # array (per-flow → per-input handshake definitions). Source it
        # unconditionally at global scope. project(release,path) — set by
        # project_pd_config — takes precedence for the release base path;
        # otherwise fall back to release(base_dir) which the sourced file
        # populates from FLOW_DIR/test_releases.
        set release_base ""
        if {[info exists ::env(CONFIG_ROOT)] && [info exists ::env(FLOW_CONFIG_VERSION)]} {
            set rc_path "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/release_config.tcl"
            if {[file exists $rc_path]} {
                if {[catch { uplevel #0 [list source $rc_path] } _src_err]} {
                    puts stderr "WARNING: release_config.tcl parse error at $rc_path: $_src_err"
                    puts stderr "         release_tag inputs will not resolve for this stage."
                }
            }
        }
        if {[info exists ::project(release,path)] && $::project(release,path) ne ""} {
            set release_base $::project(release,path)
        } elseif {[info exists ::release(base_dir)] && $::release(base_dir) ne ""} {
            set release_base $::release(base_dir)
        }
        if {$release_base eq ""} {
            puts "WARNING: Cannot resolve release_tag for ${arr}(input,${input_type}) — release(base_dir) not set"
            return 0
        }

        set design_name ""
        if {[info exists ::flow(design_name)]} { set design_name $::flow(design_name) }

        set flow_upper [string toupper $flow_type]
        set hkey "${flow_upper},${input_type}"
        if {![info exists ::flow_input_handshake($hkey)]} {
            puts "WARNING: No handshake entry for $hkey — cannot resolve ${arr}(input,${input_type}) from tag $tag"
            return 0
        }
        set hval $::flow_input_handshake($hkey)
        set src_category [lindex $hval 1]
        set src_pattern [lindex $hval 2]
        set filename [string map [list \${design_name} $design_name] $src_pattern]
        set fpath [file join $release_base $tag $src_category $filename]

        if {[file exists $fpath]} {
            set ::${arr}(input,${input_type}) $fpath
            puts "INFO:   ${arr}(input,${input_type}) = $fpath (tag=$tag)"
            if {$vars_var ne ""} {
                lappend _out_vars "${arr}(input,${input_type})" $fpath
            }
            return 1
        }
        # For test_mode + non-existent files, still populate the key so
        # the input handler stages a stub instead of reporting NO_SOURCE.
        # Real-mode runs will fail loudly via `handler_missing` downstream.
        if {[info exists ::flow(test_mode)] && [is_true $::flow(test_mode)]} {
            set ::${arr}(input,${input_type}) $fpath
            puts "INFO:   ${arr}(input,${input_type}) = $fpath (tag=$tag, test_mode)"
            if {$vars_var ne ""} {
                lappend _out_vars "${arr}(input,${input_type})" $fpath
            }
            return 1
        }
        puts "WARNING: Release file not found: $fpath"
        return 0
    }

    proc resolve_from_tag {flow_type arr tag run_dir {vars_var ""}} {
        # `vars_var`: optional caller-scope var name to receive the
        # resolved key/value pairs (parity with resolve_from_run). Prior
        # signature had 4 args but resolve_flow_inputs called it with 5
        # → 'wrong # args' crash on every release-tag-based resolution.
        if {$vars_var ne ""} { upvar 1 $vars_var _out_vars }
        variable handshake_map

        # Load release_config for base_dir and flow_input_handshake
        set release_base ""
        if {[info exists ::env(CONFIG_ROOT)] && [info exists ::env(FLOW_CONFIG_VERSION)]} {
            set rc_path "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/release_config.tcl"
            if {[file exists $rc_path]} {
                if {[catch { source $rc_path } _rc_err]} {
                    puts stderr "WARNING: release_config.tcl parse error during input resolution: $_rc_err"
                    puts stderr "         release_tag inputs will not resolve for this stage."
                }
                if {[info exists ::release(base_dir)]} { set release_base $::release(base_dir) }
            }
        }
        if {$release_base eq ""} {
            puts "WARNING: Cannot resolve release tag — release(base_dir) not set"
            return 0
        }

        set design_name ""
        if {[info exists ::flow(design_name)]} { set design_name $::flow(design_name) }

        set count 0
        set flow_upper [string toupper $flow_type]
        if {[array exists ::flow_input_handshake]} {
            foreach {_hkey _hval} [array get ::flow_input_handshake] {
                set parts [split $_hkey ","]
                if {[lindex $parts 0] ne $flow_upper} continue
                set hinput [lindex $parts 1]

                set src_category [lindex $_hval 1]
                set src_pattern [lindex $_hval 2]
                set filename [string map [list \${design_name} $design_name] $src_pattern]
                set fpath [file join $release_base $tag $src_category $filename]

                if {[file exists $fpath]} {
                    if {![info exists ::${arr}(input,${hinput})] || [set ::${arr}(input,${hinput})] eq ""} {
                        set ::${arr}(input,${hinput}) $fpath
                        puts "INFO:   ${arr}(input,${hinput}) = $fpath (tag=$tag)"
                        if {$vars_var ne ""} {
                            lappend _out_vars "${arr}(input,${hinput})" $fpath
                        }
                        incr count
                    }
                }
            }
        }
        return $count
    }

    # Generate output manifest for export_data/release_data validate subnodes.
    # Scans wherever the flow actually writes: outputs/, results/<flow>/, work/<flow>/export_data/
    proc generate_output_manifest {flow_type node_name run_dir} {
        set design_name ""
        if {[info exists ::flow(design_name)]} { set design_name $::flow(design_name) }
        set flow_lower [string tolower $flow_type]

        set results_dir "$run_dir/work/$flow_type/$node_name/results"
        file mkdir $results_dir
        set manifest_file "$results_dir/output_manifest.tcl"

        # Directories to scan (in priority order — first match wins per key)
        set search_dirs [list \
            "$run_dir/outputs" \
            "$run_dir/results/$flow_lower" \
            "$run_dir/results/$flow_type" \
            "$run_dir/work/$flow_type/$node_name/run" \
        ]

        # Build manifest in memory, then atomic_write at the end.
        # Pre-fix: open-w + 60-line foreach-of-globbing meant any
        # intermediate throw (stale NFS mount, glob race on deletion)
        # left output_manifest.tcl partial. Downstream flows source it
        # via `sta(input,from_run)` and silently set zero SDCs → STA
        # signs off against no timing constraints with WNS=inf.
        set manifest_body ""
        append manifest_body "# Output Manifest — $flow_type $node_name\n"
        append manifest_body "# Generated: [clock format [clock seconds]]\n"
        append manifest_body "# Design: $design_name\n"
        append manifest_body "\n"

        set count 0
        array set found {}

        # File patterns to search for: {suffix manifest_key}
        set patterns {
            ".v"              "netlist,logic"
            ".pt.v"           "netlist,pt"
            ".fm.v"           "netlist,fm"
            ".lvs.v"          "netlist,lvs"
            ".vc_lp.v"        "netlist,vc_lp"
            ".dc.v"           "netlist,dc"
            ".gds"            "gds"
            ".def"            "def"
            ".lef"            "lef"
            ".sdc"            "sdc"
            ".upf"            "upf"
            ".spef"           "spef"
            "_wscript"        "wscript"
            "_wscript_for_pt" "wscript_for_pt"
            "_routing_constraints" "routing_constraints"
            "_floorplan"      "floorplan"
            ".saif.ptpx.map"  "saif_ptpx_map"
            ".saif.fc.map"    "saif_fc_map"
        }

        foreach {suffix key} $patterns {
            if {[info exists found($key)]} continue
            foreach dir $search_dirs {
                if {![file isdir $dir]} continue
                # Direct match: <dir>/<design><suffix>
                set f "$dir/${design_name}${suffix}"
                if {[file exists $f]} {
                    append manifest_body "set manifest($key) \"$f\"\n"
                    set found($key) 1
                    incr count
                    break
                }
                # Subdirectory match: <dir>/netlist/<design><suffix>, <dir>/def/<design><suffix>, etc.
                foreach sub [glob -nocomplain -types d "$dir/*/"] {
                    set f2 "$sub${design_name}${suffix}"
                    if {[file exists $f2]} {
                        append manifest_body "set manifest($key) \"$f2\"\n"
                        set found($key) 1
                        incr count
                        break
                    }
                }
                if {[info exists found($key)]} break
                # Glob fallback for the suffix
                set matches [glob -nocomplain "$dir/${design_name}*${suffix}" "$dir/*/${design_name}*${suffix}"]
                if {[llength $matches] > 0} {
                    append manifest_body "set manifest($key) \"[lindex $matches 0]\"\n"
                    set found($key) 1
                    incr count
                    break
                }
            }
        }

        append manifest_body "\n"
        append manifest_body "set manifest(flow) \"$flow_type\"\n"
        append manifest_body "set manifest(node) \"$node_name\"\n"
        append manifest_body "set manifest(design) \"$design_name\"\n"
        append manifest_body "set manifest(run_dir) \"$run_dir\"\n"
        append manifest_body "set manifest(timestamp) \"[clock format [clock seconds]]\"\n"
        append manifest_body "set manifest(file_count) $count\n"
        atomic_write $manifest_file $manifest_body

        puts "INFO: Output manifest: $manifest_file ($count files)"
        return $count
    }

    namespace export resolve_flow_inputs resolve_from_run generate_output_manifest
}

namespace import ::CBFlow::InputResolve::resolve_flow_inputs
namespace import ::CBFlow::InputResolve::resolve_from_run
namespace import ::CBFlow::InputResolve::generate_output_manifest
