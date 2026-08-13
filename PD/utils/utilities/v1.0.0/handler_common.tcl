#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow — Shared Handler Utilities
# Common procedures used by ALL subnode handlers to eliminate duplication.
# Source this at the top of every handler instead of copy-pasting 200 lines.
# ═══════════════════════════════════════════════════════════════════════════════

# ── Parse handler arguments ──────────────────────────────────────────────────
# Returns: subnode_name, run_dir, node_name
# Usage: lassign [handler_parse_args $argv $argc] subnode_name run_dir node_name
proc handler_parse_args {argv argc} {
    if {$argc < 1} {
        puts "ERROR: Missing subnode argument"
        puts "Usage: tclsh <handler>.tcl <subnode_name> \[run_dir\] \[node_name\]"
        exit 1
    }
    set subnode_name [lindex $argv 0]
    set run_dir [expr {$argc > 1 ? [lindex $argv 1] : [pwd]}]
    set node_name [expr {$argc > 2 ? [lindex $argv 2] : ""}]
    return [list $subnode_name $run_dir $node_name]
}

# ── Load standard configs for a handler ──────────────────────────────────────
# Sources: .run.cbflow.tcl, error_utils, flow_config, node_config, user_config, tool_launch_config
proc handler_load_configs {run_dir flow_type} {
    # Source everything at global scope (uplevel #0) so variables are accessible
    # Why: TCL 'source' inside a proc creates local variables. Config files
    # set global arrays (flow, synth, pnr, etc.) that must be in global scope.

    # Run environment (mandatory)
    if {[file exists "$run_dir/.run.cbflow.tcl"]} {
        uplevel #0 [list source "$run_dir/.run.cbflow.tcl"]
    } else {
        puts "ERROR: Cannot find .run.cbflow.tcl in $run_dir"
        exit 1
    }

    # Error utilities
    if {[info exists ::env(SCRIPTS_ROOT)] && [info exists ::env(UTILITIES_VERSION)]} {
        set _eu "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/error_utils.tcl"
        if {[file exists $_eu]} { uplevel #0 [list source $_eu] }
    }

    # Flow config
    if {[info exists ::env(CONFIG_ROOT)] && [info exists ::env(FLOW_CONFIG_VERSION)]} {
        set _fc "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/flow_config.tcl"
        if {[file exists $_fc]} { uplevel #0 [list source $_fc] }

        # Node config
        set _nc "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/node_configs/${flow_type}_config.tcl"
        if {[file exists $_nc]} { uplevel #0 [list source $_nc] }
    }

    # User config (overrides all)
    if {[file exists "$run_dir/setup/user_config.tcl"]} {
        uplevel #0 [list source "$run_dir/setup/user_config.tcl"]
    }

    # Tool launch config (module load, tool shell, bsub, xterm)
    if {[info exists ::env(CONFIG_ROOT)] && [info exists ::env(FLOW_CONFIG_VERSION)]} {
        set _lc "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/tool_launch_config.tcl"
        if {[file exists $_lc]} { uplevel #0 [list source $_lc] }
    }
}

# ── Detect test mode ─────────────────────────────────────────────────────────
proc handler_is_test_mode {} {
    if {[info exists ::flow(test_mode)] && $::flow(test_mode) eq "true"} {
        return true
    }
    return false
}

# ── Setup subnode: create directories + generate config ──────────────────────
proc handler_setup {run_dir flow_type node_name} {
    file mkdir "$run_dir/work/$flow_type/$node_name/run"
    file mkdir "$run_dir/work/$flow_type/$node_name/setup"

    # Generate config.tcl + setup.tcl via config cascade
    if {[info exists ::env(GENERATION_VERSION)] && $::env(GENERATION_VERSION) ne ""} {
        set _gen "$::env(FLOW_DIR)/utils/generation/$::env(GENERATION_VERSION)/generate_setup.tcl"
        if {[file exists $_gen]} {
            catch {exec tclsh $_gen $flow_type $node_name ${node_name}_default $run_dir}
        }
    }
}

# ── Finish subnode: create timestamp file ─────────────────────────────────────
proc handler_finish {run_dir flow_type node_name stage_name} {
    set finish_file "$run_dir/work/$flow_type/$node_name/run/${stage_name}_finish.timestamp"
    file mkdir [file dirname $finish_file]
    set fh [open $finish_file "w"]
    puts $fh "Completed: [clock format [clock seconds]]"
    close $fh
}

# ── Validate subnode: basic validation ────────────────────────────────────────
proc handler_validate {run_dir flow_type node_name stage_name test_mode} {
    if {$test_mode} {
        puts "INFO: \[TEST MODE\] Validation skipped"
    } else {
        puts "INFO: $stage_name validation passed"
    }
}

# ── Timestamp helper (used by inputs handlers for *_info.tcl stamps) ─────────
proc handler_ts {} {
    if {[catch {clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}} _ts]} {
        return "epoch [clock seconds]"
    }
    return $_ts
}

# ── Standard 4-subnode dispatch (setup / run / validate / finish) ────────────
# Collapses the identical switch block that ~117 subnode handlers open-code.
# Each handler now supplies only its stage_name, resolved cmd_file, tool_name,
# and (optionally) a tool_suffix that triggers a local symlink at
#   $run_dir/work/$flow_type/$node_name/run/${node_name}.${tool_suffix}.tcl
# during `setup` — used by PNR-style handlers so `run` reads a canonical local
# path even when the source cmd file lives in $FLOW_DIR/cmds/.
# For handlers with no symlink pattern, pass an empty tool_suffix.
proc handler_dispatch {subnode_name run_dir flow_type node_name stage_name
                      cmd_file test_mode tool_name {tool_suffix ""}} {
    switch $subnode_name {
        "setup" {
            puts "INFO: $stage_name setup..."
            handler_setup $run_dir $flow_type $node_name
            if {$tool_suffix ne "" && [file exists $cmd_file]} {
                set _local "$run_dir/work/$flow_type/$node_name/run/${node_name}.${tool_suffix}.tcl"
                catch {file delete $_local}
                if {[catch {file link -symbolic $_local $cmd_file} _err]} {
                    puts "WARN: symlink failed ($_err); falling back to copy"
                    file copy -force $cmd_file $_local
                } else {
                    puts "INFO: Command file (symlink → $cmd_file): $_local"
                }
            }
            puts "INFO: $stage_name setup completed"
        }
        "run" {
            puts "INFO: $stage_name run..."
            set _actual $cmd_file
            if {$tool_suffix ne ""} {
                set _local "$run_dir/work/$flow_type/$node_name/run/${node_name}.${tool_suffix}.tcl"
                if {[file exists $_local]} { set _actual $_local }
            }
            handler_run $run_dir $flow_type $node_name $stage_name $_actual $test_mode $tool_name
        }
        "validate" {
            puts "INFO: $stage_name validate..."
            handler_validate $run_dir $flow_type $node_name $stage_name $test_mode
            puts "INFO: $stage_name validate completed"
        }
        "finish" {
            puts "INFO: $stage_name finish..."
            handler_finish $run_dir $flow_type $node_name $stage_name
            puts "INFO: $stage_name finish completed"
        }
        default {
            puts "ERROR: Unknown subnode: '$subnode_name' (stage=$stage_name flow=$flow_type)"
            puts "       Expected one of: setup, run, validate, finish"
            exit 1
        }
    }
}

# ── Inputs dispatch (setup / <input_type> / validate / finish) ───────────────
# The inputs stage has a different shape: each subnode corresponds to an input
# TYPE (netlist, sdc, def, library, upf, spef, ...) rather than a lifecycle
# phase. This proc handles the boilerplate that ~20 inputs handlers currently
# re-implement identically — mkdir per input type, write a *_info.tcl stamp,
# no-op validate/finish stamps.
#
# `input_types` is the flow's list of input types. For real (non-test) runs,
# resolve_flow_inputs from resolve_inputs.tcl runs in setup and materializes
# the actual files — the *_info.tcl stamps are metadata for the dashboard.
proc handler_dispatch_inputs {subnode_name run_dir flow_type node_name
                              input_types test_mode} {
    set stage_name "inputs"
    set node_dir "$run_dir/work/$flow_type/$node_name"

    switch $subnode_name {
        "setup" {
            puts "INFO: $flow_type $stage_name setup..."
            file mkdir $node_dir
            foreach _itype $input_types {
                file mkdir "$node_dir/$_itype"
            }
            # Generate config.tcl + setup.tcl via config cascade (same as
            # handler_setup; inlined here because inputs stage has a different
            # directory shape and doesn't need the standard work/setup dirs).
            if {[info exists ::env(GENERATION_VERSION)] && $::env(GENERATION_VERSION) ne ""} {
                set _gen "$::env(FLOW_DIR)/utils/generation/$::env(GENERATION_VERSION)/generate_setup.tcl"
                if {[file exists $_gen]} {
                    catch {exec tclsh $_gen $flow_type $node_name ${node_name}_default $run_dir}
                }
            }
            puts "INFO: $flow_type $stage_name setup completed"
        }
        "validate" {
            puts "INFO: $flow_type $stage_name validate..."
            if {$test_mode} {
                puts "INFO: \[TEST MODE\] Validation skipped"
            } else {
                puts "INFO: $flow_type inputs validation passed"
            }
            puts "INFO: $flow_type $stage_name validate completed"
        }
        "finish" {
            puts "INFO: $flow_type $stage_name finish..."
            set _finish_file "$node_dir/finish/finish_info.tcl"
            file mkdir [file dirname $_finish_file]
            set _fh [open $_finish_file "w"]
            puts $_fh "set finish_info(timestamp) \"[handler_ts]\""
            close $_fh
            puts "INFO: $flow_type $stage_name finish completed"
        }
        default {
            if {[lsearch -exact $input_types $subnode_name] < 0} {
                puts "ERROR: Unknown subnode: '$subnode_name' (flow=$flow_type stage=$stage_name)"
                puts "       Expected: setup, validate, finish, or one of: $input_types"
                exit 1
            }
            puts "INFO: $flow_type $stage_name $subnode_name..."

            # ── Stage every resolved source for this input subnode ──────
            # The subnode name (netlist/sdc/def/upf/library) maps to one or
            # more Tcl vars set by the user_config or resolve_flow_inputs:
            #   pnr(input,netlist)          — flat, direct
            #   pnr(input,sdc_func_file)    — flat, suffixed
            #   pnr(input,sdc,func)         — comma-nested
            # We stage every matching source into work/<FLOW>/inputs/<subnode>/
            # so the run has a visible, auditable copy AND downstream tools
            # can find inputs at a stable local path. Fail loudly if a
            # declared source is missing on a real run (test_mode creates
            # stubs so downstream fake-outputs still work).
            set _sub_dir "$node_dir/$subnode_name"
            file mkdir $_sub_dir
            set _flow_lower [string tolower $flow_type]
            set _sources [list]                ;# {key1 path1 key2 path2 ...}
            if {[array exists ::$_flow_lower]} {
                foreach _k [array names ::$_flow_lower] {
                    if {[regexp "^input,${subnode_name}(_.*)?\$" $_k] ||
                        [regexp "^input,${subnode_name}," $_k]} {
                        set _val [set ::${_flow_lower}($_k)]
                        if {$_val ne ""} { lappend _sources $_k $_val }
                    }
                }
            }

            set _staged [list]      ;# {key path key path ...} — real files
            set _stubbed [list]     ;# {key path key path ...} — test_mode stubs
            set _missing [list]     ;# {key path key path ...} — declared, not on disk
            foreach {_key _src} $_sources {
                set _dst "$_sub_dir/[file tail $_src]"
                if {[file exists $_src]} {
                    # Prefer symlink — cheap, preserves provenance and
                    # avoids duplicating large gates/spef/gds files.
                    # Fall back to copy on filesystems that don't support
                    # symlinks (rare NFS mounts, some Windows shares).
                    if {[catch {
                        file delete -force $_dst
                        file link -symbolic $_dst $_src
                    } _e]} {
                        file copy -force $_src $_dst
                    }
                    lappend _staged $_key $_dst
                    puts "INFO:   staged $_key -> [file tail $_src]"
                } elseif {$test_mode} {
                    set _sh [open $_dst "w"]
                    puts $_sh "// TEST_MODE stub for ${_flow_lower}($_key)"
                    close $_sh
                    lappend _stubbed $_key $_dst
                    puts "INFO:   \[TEST MODE\] stub $_key -> [file tail $_src]"
                } else {
                    lappend _missing $_key $_src
                    puts "ERROR:  missing input source for ${_flow_lower}($_key): $_src"
                }
            }

            # ── Write the info stamp (audit trail for dashboard) ────────
            set _info_file "$_sub_dir/${subnode_name}_info.tcl"
            set _fh [open $_info_file "w"]
            puts $_fh "set ${subnode_name}_info(timestamp) \"[handler_ts]\""
            set _n_staged  [expr {[llength $_staged]  / 2}]
            set _n_stubbed [expr {[llength $_stubbed] / 2}]
            set _n_missing [expr {[llength $_missing] / 2}]
            puts $_fh "set ${subnode_name}_info(staged_count)  $_n_staged"
            puts $_fh "set ${subnode_name}_info(stubbed_count) $_n_stubbed"
            puts $_fh "set ${subnode_name}_info(missing_count) $_n_missing"
            foreach {_k _d} $_staged  { puts $_fh "set ${subnode_name}_info(staged,$_k) \"$_d\"" }
            foreach {_k _d} $_stubbed { puts $_fh "set ${subnode_name}_info(stubbed,$_k) \"$_d\"" }
            foreach {_k _s} $_missing { puts $_fh "set ${subnode_name}_info(missing,$_k) \"$_s\"" }

            if {$_n_missing > 0} {
                puts $_fh "set ${subnode_name}_info(status) \"MISSING\""
                close $_fh
                puts "ERROR: $flow_type $stage_name $subnode_name FAILED — $_n_missing source(s) missing"
                exit 1
            }
            if {$_n_staged == 0 && $_n_stubbed == 0} {
                # No sources declared for this subnode — legitimate for
                # some flows (e.g. PNR without UPF). Don't fail, but say so.
                puts $_fh "set ${subnode_name}_info(status) \"NO_SOURCE\""
                close $_fh
                puts "INFO: $flow_type $stage_name $subnode_name — no sources declared, skipped"
                return
            }
            # STAGED  = at least one real source found (regardless of test_mode)
            # TEST_STUB = only stubs (all sources were missing but test_mode
            #             is on, so we fabricated placeholders)
            set _status [expr {$_n_staged > 0 ? {STAGED} : {TEST_STUB}}]
            puts $_fh "set ${subnode_name}_info(status) \"$_status\""
            close $_fh
            set _total [expr {$_n_staged + $_n_stubbed}]
            puts "INFO: $flow_type $stage_name $subnode_name completed ($_total file(s): $_n_staged staged, $_n_stubbed stubbed) → $_status"
        }
    }
}

# ── Resolve upstream inputs (from_run / release_tag / direct paths) ──────────
# Sources resolve_inputs.tcl and invokes resolve_flow_inputs. Safe to call
# multiple times: the underlying proc checks for a persisted resolved_inputs.tcl
# and skips re-resolution if present.
proc handler_resolve_inputs {flow_type run_dir} {
    if {![info exists ::env(SCRIPTS_ROOT)] || ![info exists ::env(UTILITIES_VERSION)]} {
        return
    }
    set _lib "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/resolve_inputs.tcl"
    if {[file exists $_lib]} {
        uplevel #0 [list source $_lib]
        uplevel #0 [list ::CBFlow::InputResolve::resolve_flow_inputs $flow_type $run_dir]
    }
}
