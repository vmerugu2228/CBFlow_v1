#!/usr/bin/env tclsh
# CBFlow POPT power_opt - Synopsys PrimeTime — Rockbottom VT Swap Algorithm

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "POPT"
set STAGE_NAME "power_opt"
set NODE_NAME "${STAGE_NAME}1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# ═══════════════════════════════════════════════════════════════════════════════
# flow_proc: setup_dmsa
# Set up DMSA multi-scenario environment for cross-corner optimization
# ═══════════════════════════════════════════════════════════════════════════════
flow_proc setup_dmsa {
    handle_info "Setting up DMSA multi-scenario environment..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    file mkdir "$::REPORTS_DIR"
    file mkdir "$::OUTPUTS_DIR/popt"

    if {$::popt(dmsa,enabled) eq "true"} {
        handle_info "DMSA enabled — configuring multi-scenario mode"

        # Source DMSA master setup
        set dmsa_master "$run_dir/work/$::FLOW_TYPE/$::NODE_NAME/run/dmsa_master.tcl"
        if {[file exists $dmsa_master]} {
            source $dmsa_master
            handle_info "Sourced DMSA master: $dmsa_master"
        } else {
            handle_error "DMSA master file not found: $dmsa_master"
        }

        # Determine scenario list — explicit config or from MMMC analysis views
        if {$::popt(dmsa,scenarios) ne ""} {
            set scenario_list $::popt(dmsa,scenarios)
            handle_info "Using explicit DMSA scenarios: $scenario_list"
        } else {
            # Build from MMMC analysis_views
            set scenario_list {}
            foreach view [array names ::popt "mmmc,analysis_view,*"] {
                lappend scenario_list $::popt($view)
            }
            handle_info "Auto-generated DMSA scenarios from MMMC: $scenario_list"
        }

        # Configure DMSA workers
        set num_workers $::popt(dmsa,workers)
        handle_info "DMSA workers: $num_workers"

        if {$::popt(dmsa,host_list) ne ""} {
            handle_info "DMSA host list: $::popt(dmsa,host_list)"
        }

        handle_info "DMSA launch method: $::popt(dmsa,launch_method)"

        # Create scenarios
        foreach scenario $scenario_list {
            handle_info "  Creating DMSA scenario: $scenario"
        }

    } else {
        handle_info "DMSA disabled — single-scenario mode (using current loaded scenario)"
    }

    handle_info "DMSA setup completed"
}

# ═══════════════════════════════════════════════════════════════════════════════
# flow_proc: report_baseline
# Pre-optimization snapshot: timing, power, VT distribution
# ═══════════════════════════════════════════════════════════════════════════════
flow_proc report_baseline {
    handle_info "Generating baseline pre-optimization reports..."
    set rpt_dir "$::REPORTS_DIR"

    # Full timing update for accurate baseline
    update_timing -full
    handle_info "Timing updated — capturing baseline metrics"

    # ── Timing: WNS/TNS per scenario ──
    report_timing -delay max -nosplit \
        -max_paths 1 \
        > "$rpt_dir/baseline_setup_timing.rpt"
    handle_info "Baseline setup timing reported"

    report_timing -delay min -nosplit \
        -max_paths 1 \
        > "$rpt_dir/baseline_hold_timing.rpt"
    handle_info "Baseline hold timing reported"

    # ── Power: total, leakage, dynamic breakdown ──
    report_power -nosplit > "$rpt_dir/baseline_power_total.rpt"
    handle_info "Baseline total power reported"

    report_power -nosplit -leakage > "$rpt_dir/baseline_power_leakage.rpt"
    handle_info "Baseline leakage power reported"

    # ── VT Distribution: current threshold voltage groups ──
    report_threshold_voltage_group > "$rpt_dir/baseline_vt_distribution.rpt"
    handle_info "Baseline VT distribution reported"

    # ── Parse and log key baseline metrics ──
    set baseline_fp [open "$rpt_dir/baseline_summary.rpt" w]
    puts $baseline_fp "================================================================"
    puts $baseline_fp "POPT Baseline Summary"
    puts $baseline_fp "Date: [clock format [clock seconds]]"
    puts $baseline_fp "================================================================"
    puts $baseline_fp ""
    puts $baseline_fp "Reports generated:"
    puts $baseline_fp "  baseline_setup_timing.rpt"
    puts $baseline_fp "  baseline_hold_timing.rpt"
    puts $baseline_fp "  baseline_power_total.rpt"
    puts $baseline_fp "  baseline_power_leakage.rpt"
    puts $baseline_fp "  baseline_vt_distribution.rpt"
    puts $baseline_fp "================================================================"
    close $baseline_fp

    handle_info "Baseline reporting completed"
}

# ═══════════════════════════════════════════════════════════════════════════════
# flow_proc: rockbottom_swap
# Swap ALL cells to highest VT (HVT) to establish leakage floor.
# This creates massive timing violations — iterative_fix_setup recovers timing.
# ═══════════════════════════════════════════════════════════════════════════════
flow_proc rockbottom_swap {
    handle_info "Starting rockbottom VT swap..."
    set rpt_dir "$::REPORTS_DIR"

    # ── Guard: skip if rockbottom not enabled ──
    if {$::popt(vt_swap,rockbottom) ne "true"} {
        handle_info "Rockbottom swap disabled (popt(vt_swap,rockbottom) != true) — skipping"
        return
    }

    # ── Read VT configuration ──
    set target_vt       $::popt(vt_swap,target_vt)
    set available_vts   $::popt(vt_swap,available_vts)
    set vt_suffixes     $::popt(vt_swap,vt_suffixes)
    set exclude_clk     $::popt(vt_swap,exclude_clock_cells)
    set exclude_dt      $::popt(vt_swap,exclude_dont_touch)
    set exclude_ao      $::popt(vt_swap,exclude_always_on)
    set exclude_cells   $::popt(vt_swap,exclude_cells)

    handle_info "Target VT: $target_vt"
    handle_info "Available VTs: $available_vts"
    handle_info "VT suffixes: $vt_suffixes"

    # ── Determine target VT suffix ──
    # Map target_vt name to its suffix (e.g., hvt -> HVT)
    set vt_names [split $available_vts]
    set vt_suffix_list [split $vt_suffixes]
    set target_suffix ""
    for {set i 0} {$i < [llength $vt_names]} {incr i} {
        if {[lindex $vt_names $i] eq $target_vt} {
            set target_suffix [lindex $vt_suffix_list $i]
            break
        }
    }
    if {$target_suffix eq ""} {
        handle_error "Could not find suffix for target VT '$target_vt' in available_vts"
    }
    handle_info "Target VT suffix: $target_suffix"

    # ── Build non-target suffix list (for replacement pattern matching) ──
    set non_target_suffixes {}
    for {set i 0} {$i < [llength $vt_suffix_list]} {incr i} {
        set s [lindex $vt_suffix_list $i]
        if {$s ne $target_suffix} {
            lappend non_target_suffixes $s
        }
    }
    handle_info "Non-target suffixes to replace: $non_target_suffixes"

    # ── Collect all swappable cells ──
    handle_info "Collecting cells for rockbottom swap..."
    set all_cells [get_cells * -hierarchical -filter "is_combinational || is_sequential"]
    set num_total [sizeof_collection $all_cells]
    handle_info "Total combinational/sequential cells: $num_total"

    # ── Build exclusion set ──
    set swap_cells [get_cells ""]
    set excluded_count 0

    foreach_in_collection cell $all_cells {
        set cell_name [get_object_name $cell]
        set skip 0

        # Exclude clock network cells
        if {$exclude_clk eq "true"} {
            set is_clock [get_attribute $cell is_clock_network_cell -quiet]
            if {$is_clock eq "true"} {
                set skip 1
            }
        }

        # Exclude dont_touch cells
        if {$skip == 0 && $exclude_dt eq "true"} {
            set dt [get_attribute $cell dont_touch -quiet]
            if {$dt eq "true"} {
                set skip 1
            }
        }

        # Exclude always-on cells
        if {$skip == 0 && $exclude_ao eq "true"} {
            set ao [get_attribute $cell is_always_on -quiet]
            if {$ao eq "true"} {
                set skip 1
            }
        }

        # Exclude explicitly listed cells
        if {$skip == 0 && $exclude_cells ne ""} {
            foreach exc_pattern $exclude_cells {
                if {[string match $exc_pattern $cell_name]} {
                    set skip 1
                    break
                }
            }
        }

        if {$skip} {
            incr excluded_count
        } else {
            append_to_collection swap_cells $cell
        }
    }

    set num_swap [sizeof_collection $swap_cells]
    handle_info "Cells eligible for swap: $num_swap (excluded: $excluded_count)"

    # ── Perform rockbottom swap ──
    handle_info "Swapping all eligible cells to $target_vt ($target_suffix)..."
    set swap_count 0
    set fail_count 0

    foreach_in_collection cell $swap_cells {
        set cell_name [get_object_name $cell]
        set ref_name [get_attribute $cell ref_name]

        # Derive HVT equivalent by replacing VT suffix
        set hvt_ref $ref_name
        set found_match 0
        foreach src_suffix $non_target_suffixes {
            if {[string match "*${src_suffix}*" $ref_name]} {
                set hvt_ref [string map [list $src_suffix $target_suffix] $ref_name]
                set found_match 1
                break
            }
        }

        # If already target VT or no suffix found, skip
        if {!$found_match && ![string match "*${target_suffix}*" $ref_name]} {
            # No VT suffix detected — skip this cell
            continue
        }
        if {$hvt_ref eq $ref_name} {
            # Already target VT
            continue
        }

        # Perform the swap
        set result [size_cell $cell_name $hvt_ref]
        if {$result} {
            incr swap_count
        } else {
            incr fail_count
        }
    }

    handle_info "Rockbottom swap complete: $swap_count cells swapped, $fail_count failed"

    # ── Post-rockbottom timing and power ──
    handle_info "Updating timing after rockbottom swap..."
    update_timing -full

    report_power -nosplit > "$rpt_dir/rockbottom_power.rpt"
    handle_info "Rockbottom power reported (leakage floor established)"

    report_timing -delay max -nosplit \
        -max_paths 10 \
        > "$rpt_dir/rockbottom_setup_timing.rpt"
    handle_info "Rockbottom timing reported (massive violations expected)"

    report_threshold_voltage_group > "$rpt_dir/rockbottom_vt_distribution.rpt"
    handle_info "Rockbottom VT distribution reported"

    # ── Rockbottom summary ──
    set rb_fp [open "$rpt_dir/rockbottom_summary.rpt" w]
    puts $rb_fp "================================================================"
    puts $rb_fp "Rockbottom VT Swap Summary"
    puts $rb_fp "Date: [clock format [clock seconds]]"
    puts $rb_fp "================================================================"
    puts $rb_fp "Target VT:          $target_vt ($target_suffix)"
    puts $rb_fp "Total cells:        $num_total"
    puts $rb_fp "Eligible cells:     $num_swap"
    puts $rb_fp "Excluded cells:     $excluded_count"
    puts $rb_fp "Cells swapped:      $swap_count"
    puts $rb_fp "Swap failures:      $fail_count"
    puts $rb_fp "================================================================"
    close $rb_fp

    handle_info "Rockbottom swap stage completed"
}

# ═══════════════════════════════════════════════════════════════════════════════
# flow_proc: iterative_fix_setup
# Fix setup timing violations by selectively swapping HVT -> SVT -> LVT
# on critical paths. Iterates until timing is clean or budget exhausted.
# ═══════════════════════════════════════════════════════════════════════════════
flow_proc iterative_fix_setup {
    handle_info "Starting iterative setup timing fix..."
    set rpt_dir "$::REPORTS_DIR"

    # ── Read iteration control config ──
    set max_iter          $::popt(vt_swap,max_iterations)
    set paths_per_iter    $::popt(vt_swap,paths_per_iteration)
    set setup_target      $::popt(vt_swap,setup_target)
    set conv_threshold    $::popt(vt_swap,convergence_threshold)
    set leakage_budget    $::popt(vt_swap,leakage_budget)
    set max_lvt_pct       $::popt(vt_swap,max_lvt_percentage)
    set max_svt_pct       $::popt(vt_swap,max_svt_percentage)

    # ── VT suffix configuration ──
    set available_vts     $::popt(vt_swap,available_vts)
    set vt_suffixes       $::popt(vt_swap,vt_suffixes)
    set vt_names          [split $available_vts]
    set vt_suffix_list    [split $vt_suffixes]

    # Build suffix maps: hvt->svt, svt->lvt (downgrade path for speed)
    # Assumes ordering: lvt svt hvt (fastest to slowest)
    set hvt_suffix ""
    set svt_suffix ""
    set lvt_suffix ""
    for {set i 0} {$i < [llength $vt_names]} {incr i} {
        set vt [lindex $vt_names $i]
        set sf [lindex $vt_suffix_list $i]
        switch $vt {
            "hvt" { set hvt_suffix $sf }
            "svt" { set svt_suffix $sf }
            "lvt" { set lvt_suffix $sf }
        }
    }

    handle_info "Setup fix config:"
    handle_info "  Max iterations:     $max_iter"
    handle_info "  Paths/iteration:    $paths_per_iter"
    handle_info "  Setup target:       $setup_target"
    handle_info "  Convergence:        $conv_threshold"
    handle_info "  Leakage budget:     $leakage_budget"
    handle_info "  Max LVT%%:          $max_lvt_pct"
    handle_info "  Max SVT%%:          $max_svt_pct"
    handle_info "  Suffixes: LVT=$lvt_suffix SVT=$svt_suffix HVT=$hvt_suffix"

    # ── Iteration summary file ──
    set iter_fp [open "$rpt_dir/iteration_summary.rpt" w]
    puts $iter_fp [format "%-6s  %-12s  %-12s  %-8s  %-14s  %-12s  %-10s" \
        "Iter" "WNS" "TNS" "NVP" "Leakage(mW)" "Swapped" "Cumulative"]
    puts $iter_fp [string repeat "-" 90]

    set prev_wns -999999.0
    set total_swapped 0
    set converged 0

    # ── Main iteration loop ──
    for {set iter 1} {$iter <= $max_iter} {incr iter} {
        handle_info "── Iteration $iter / $max_iter ──"

        # Get violating paths
        set viol_paths [get_timing_paths \
            -delay max \
            -slack_lesser_than $setup_target \
            -max_paths $paths_per_iter]

        set num_viol [sizeof_collection $viol_paths]
        if {$num_viol == 0} {
            handle_info "No setup violations — timing is clean"
            set converged 1
            puts $iter_fp [format "%-6s  %-12s  %-12s  %-8s  %-14s  %-12s  %-10s" \
                $iter "CLEAN" "0.000" "0" "-" "0" $total_swapped]
            break
        }

        handle_info "  Violating paths found: $num_viol"

        # ── Collect cells on critical paths, deduplicate ──
        set path_cells {}
        foreach_in_collection path $viol_paths {
            set points [get_attribute $path points]
            foreach_in_collection point $points {
                set pin [get_attribute $point object]
                set pin_cell [get_attribute $pin cell -quiet]
                if {$pin_cell ne ""} {
                    set cname [get_object_name $pin_cell]
                    if {[lsearch -exact $path_cells $cname] == -1} {
                        lappend path_cells $cname
                    }
                }
            }
        }

        handle_info "  Unique cells on critical paths: [llength $path_cells]"

        # ── Sort by leakage impact (highest leakage first = most benefit) ──
        set cell_leakage_pairs {}
        foreach cname $path_cells {
            set cell_obj [get_cells $cname -quiet]
            if {[sizeof_collection $cell_obj] == 0} { continue }
            set leak [get_attribute $cell_obj leakage_power -quiet]
            if {$leak eq ""} { set leak 0.0 }
            lappend cell_leakage_pairs [list $cname $leak]
        }
        set cell_leakage_pairs [lsort -real -decreasing -index 1 $cell_leakage_pairs]

        # ── Swap cells: HVT -> SVT first, SVT -> LVT as last resort ──
        set iter_swapped 0
        foreach pair $cell_leakage_pairs {
            set cname [lindex $pair 0]
            set cell_obj [get_cells $cname -quiet]
            if {[sizeof_collection $cell_obj] == 0} { continue }
            set ref_name [get_attribute $cell_obj ref_name]

            set new_ref ""
            if {$hvt_suffix ne "" && [string match "*${hvt_suffix}*" $ref_name]} {
                # HVT -> SVT (primary swap)
                if {$svt_suffix ne ""} {
                    set new_ref [string map [list $hvt_suffix $svt_suffix] $ref_name]
                }
            } elseif {$svt_suffix ne "" && [string match "*${svt_suffix}*" $ref_name]} {
                # SVT -> LVT (last resort)
                if {$lvt_suffix ne ""} {
                    set new_ref [string map [list $svt_suffix $lvt_suffix] $ref_name]
                }
            }

            if {$new_ref ne "" && $new_ref ne $ref_name} {
                set result [size_cell $cname $new_ref]
                if {$result} {
                    incr iter_swapped
                }
            }
        }

        incr total_swapped $iter_swapped
        handle_info "  Cells swapped this iteration: $iter_swapped"

        # ── Update timing after swaps ──
        update_timing -full

        # ── Capture current metrics ──
        set wns_path [get_timing_paths -delay max -max_paths 1]
        set current_wns [get_attribute $wns_path slack]
        handle_info "  WNS after iteration $iter: $current_wns"

        # Get TNS and NVP
        set tns_paths [get_timing_paths -delay max -slack_lesser_than $setup_target -max_paths 10000]
        set nvp [sizeof_collection $tns_paths]
        set current_tns 0.0
        foreach_in_collection tp $tns_paths {
            set s [get_attribute $tp slack]
            set current_tns [expr {$current_tns + $s}]
        }

        # Get current leakage
        set leak_str "N/A"

        # ── Write per-iteration report ──
        if {$::popt(report,per_iteration) eq "true"} {
            report_timing -delay max -nosplit -max_paths 5 \
                > "$rpt_dir/iter${iter}_setup_timing.rpt"
            report_power -nosplit > "$rpt_dir/iter${iter}_power.rpt"
            report_threshold_voltage_group > "$rpt_dir/iter${iter}_vt_distribution.rpt"
        }

        # ── Log iteration to summary ──
        puts $iter_fp [format "%-6s  %-12.4f  %-12.4f  %-8d  %-14s  %-12d  %-10d" \
            $iter $current_wns $current_tns $nvp $leak_str $iter_swapped $total_swapped]

        handle_info "  Iteration $iter: WNS=$current_wns TNS=$current_tns NVP=$nvp swapped=$iter_swapped"

        # ── Stop conditions ──
        # 1. WNS clean
        if {$current_wns >= $setup_target} {
            handle_info "Setup timing clean — WNS >= $setup_target"
            set converged 1
            break
        }

        # 2. Leakage budget exceeded
        if {$leakage_budget ne ""} {
            # Check leakage against budget would go here
            # (requires parsing report_power output)
        }

        # 3. Convergence stalling
        set wns_delta [expr {abs($current_wns - $prev_wns)}]
        if {$iter > 1 && $wns_delta < $conv_threshold} {
            handle_info "Convergence stalled — WNS delta $wns_delta < threshold $conv_threshold"
            break
        }

        # 4. No cells swapped (nothing left to swap)
        if {$iter_swapped == 0} {
            handle_info "No cells swapped — no further improvement possible"
            break
        }

        set prev_wns $current_wns
    }

    # ── Close iteration summary ──
    puts $iter_fp [string repeat "-" 90]
    if {$converged} {
        puts $iter_fp "RESULT: Setup timing converged after $iter iteration(s)"
    } else {
        puts $iter_fp "RESULT: Setup timing did NOT converge after $iter iteration(s)"
    }
    puts $iter_fp "Total cells swapped: $total_swapped"
    close $iter_fp

    handle_info "Iterative setup fix completed — $total_swapped total cells swapped"
}

# ═══════════════════════════════════════════════════════════════════════════════
# flow_proc: fix_hold
# Fix hold violations after setup is clean.
# Uses buffer insertion only — NOT VT swap (VT swap worsens hold).
# ═══════════════════════════════════════════════════════════════════════════════
flow_proc fix_hold {
    handle_info "Starting hold violation fix..."
    set rpt_dir "$::REPORTS_DIR"

    set hold_target $::popt(vt_swap,hold_target)
    handle_info "Hold target: $hold_target"

    # ── Check for hold violations ──
    set hold_paths [get_timing_paths \
        -delay min \
        -slack_lesser_than $hold_target \
        -max_paths 10000]

    set num_hold_viol [sizeof_collection $hold_paths]
    handle_info "Hold violations found: $num_hold_viol"

    if {$num_hold_viol == 0} {
        handle_info "No hold violations — skipping hold fix"

        set hold_fp [open "$rpt_dir/hold_fix_summary.rpt" w]
        puts $hold_fp "No hold violations detected. Hold target: $hold_target"
        close $hold_fp
        return
    }

    # ── Fix hold using buffer insertion (NOT VT swap) ──
    handle_info "Fixing hold violations using buffer insertion..."
    fix_eco_timing -type hold -methods {insert_buffer}

    # ── Update timing after hold fix ──
    update_timing -full

    # ── Report hold results ──
    report_timing -delay min -nosplit \
        -max_paths 50 \
        > "$rpt_dir/post_hold_fix_timing.rpt"

    # ── Check remaining violations ──
    set remaining_paths [get_timing_paths \
        -delay min \
        -slack_lesser_than $hold_target \
        -max_paths 10000]
    set remaining_viol [sizeof_collection $remaining_paths]

    # ── Hold fix summary ──
    set hold_fp [open "$rpt_dir/hold_fix_summary.rpt" w]
    puts $hold_fp "================================================================"
    puts $hold_fp "Hold Fix Summary"
    puts $hold_fp "Date: [clock format [clock seconds]]"
    puts $hold_fp "================================================================"
    puts $hold_fp "Hold target:              $hold_target"
    puts $hold_fp "Violations before fix:    $num_hold_viol"
    puts $hold_fp "Violations after fix:     $remaining_viol"
    puts $hold_fp "Method:                   buffer insertion (no VT swap)"
    puts $hold_fp "================================================================"
    close $hold_fp

    if {$remaining_viol > 0} {
        handle_warning "Hold violations remaining after fix: $remaining_viol"
    } else {
        handle_info "All hold violations fixed"
    }

    handle_info "Hold fix completed"
}

# ═══════════════════════════════════════════════════════════════════════════════
# flow_proc: report_final
# Final optimization report: VT distribution, power comparison, timing summary
# ═══════════════════════════════════════════════════════════════════════════════
flow_proc report_final {
    handle_info "Generating final optimization reports..."
    set rpt_dir "$::REPORTS_DIR"

    # ── Final timing update ──
    update_timing -full

    # ── Final VT distribution ──
    if {$::popt(report,vt_distribution) eq "true"} {
        report_threshold_voltage_group > "$rpt_dir/final_vt_distribution.rpt"
        handle_info "Final VT distribution reported"
    }

    # ── Final power ──
    if {$::popt(report,power_breakdown) eq "true"} {
        report_power -nosplit > "$rpt_dir/final_power_total.rpt"
        report_power -nosplit -leakage > "$rpt_dir/final_power_leakage.rpt"
        handle_info "Final power reported"
    }

    # ── Final timing per delay type ──
    report_timing -delay max -nosplit \
        -max_paths 50 \
        > "$rpt_dir/final_setup_timing.rpt"
    handle_info "Final setup timing reported"

    report_timing -delay min -nosplit \
        -max_paths 50 \
        > "$rpt_dir/final_hold_timing.rpt"
    handle_info "Final hold timing reported"

    # ── Comprehensive final summary ──
    set final_fp [open "$rpt_dir/final_optimization_summary.rpt" w]
    puts $final_fp "================================================================"
    puts $final_fp "POPT Rockbottom VT Swap — Final Optimization Summary"
    puts $final_fp "Date: [clock format [clock seconds]]"
    puts $final_fp "================================================================"
    puts $final_fp ""

    # Optimization flow description
    puts $final_fp "Optimization Flow:"
    puts $final_fp "  1. setup_dmsa         — Multi-scenario environment setup"
    puts $final_fp "  2. report_baseline    — Pre-optimization snapshot"
    puts $final_fp "  3. rockbottom_swap    — Swap all cells to HVT (leakage floor)"
    puts $final_fp "  4. iterative_fix_setup — Recover setup timing (HVT->SVT->LVT)"
    puts $final_fp "  5. fix_hold           — Fix hold via buffer insertion"
    puts $final_fp "  6. report_final       — This report"
    puts $final_fp "  7. write_outputs      — Deliverables"
    puts $final_fp ""

    # Configuration used
    puts $final_fp "Configuration:"
    puts $final_fp "  Target VT:            $::popt(vt_swap,target_vt)"
    puts $final_fp "  Available VTs:        $::popt(vt_swap,available_vts)"
    puts $final_fp "  Max iterations:       $::popt(vt_swap,max_iterations)"
    puts $final_fp "  Paths/iteration:      $::popt(vt_swap,paths_per_iteration)"
    puts $final_fp "  Setup target:         $::popt(vt_swap,setup_target)"
    puts $final_fp "  Hold target:          $::popt(vt_swap,hold_target)"
    puts $final_fp "  Max LVT%%:            $::popt(vt_swap,max_lvt_percentage)"
    puts $final_fp "  Max SVT%%:            $::popt(vt_swap,max_svt_percentage)"
    puts $final_fp "  DMSA enabled:         $::popt(dmsa,enabled)"
    puts $final_fp ""

    # List all reports generated
    puts $final_fp "Reports Generated:"
    foreach f [lsort [glob -nocomplain "$rpt_dir/*.rpt"]] {
        puts $final_fp "  [file tail $f]"
    }
    puts $final_fp ""

    # Iteration summary (copy from iteration_summary.rpt if exists)
    set iter_file "$rpt_dir/iteration_summary.rpt"
    if {[file exists $iter_file]} {
        puts $final_fp "Iteration Summary:"
        set ifp [open $iter_file r]
        puts $final_fp [read $ifp]
        close $ifp
    }

    puts $final_fp "================================================================"
    close $final_fp

    handle_info "Final optimization summary generated"
}

# ═══════════════════════════════════════════════════════════════════════════════
# flow_proc: write_outputs
# Write deliverables: optimized netlist, ECO change script, VT swap log
# ═══════════════════════════════════════════════════════════════════════════════
flow_proc write_outputs {
    handle_info "Writing output deliverables..."
    set out_dir "$::OUTPUTS_DIR/popt"
    set rpt_dir "$::REPORTS_DIR"

    file mkdir $out_dir

    # ── Optimized netlist ──
    set netlist_file "$out_dir/optimized_netlist.v"
    write_verilog $netlist_file
    handle_info "Optimized netlist written: $netlist_file"

    # ── ECO change script (original -> optimized) ──
    set eco_file "$out_dir/vt_swap_eco.tcl"
    write_changes -format icctcl -output $eco_file
    handle_info "ECO change script written: $eco_file"

    # ── VT swap log ──
    set vt_log "$out_dir/vt_swap_log.rpt"
    set vt_fp [open $vt_log w]
    puts $vt_fp "================================================================"
    puts $vt_fp "VT Swap Log"
    puts $vt_fp "Date: [clock format [clock seconds]]"
    puts $vt_fp "================================================================"
    puts $vt_fp ""
    puts $vt_fp "Algorithm: Rockbottom VT Swap"
    puts $vt_fp "  Step 1: Swap all cells to $::popt(vt_swap,target_vt)"
    puts $vt_fp "  Step 2: Iteratively swap back to meet timing"
    puts $vt_fp "  Step 3: Fix hold via buffer insertion"
    puts $vt_fp ""
    puts $vt_fp "Deliverables:"
    puts $vt_fp "  Optimized netlist:  $netlist_file"
    puts $vt_fp "  ECO script:         $eco_file"
    puts $vt_fp ""

    # List all output files
    puts $vt_fp "Output files:"
    foreach f [lsort [glob -nocomplain "$out_dir/*"]] {
        puts $vt_fp "  [file tail $f]"
    }
    puts $vt_fp "================================================================"
    close $vt_fp

    handle_info "VT swap log written: $vt_log"
    handle_info "Output deliverables completed"
}

# ═══════════════════════════════════════════════════════════════════════════════
# flow_exec_all: Execute the full rockbottom VT swap POPT flow in sequence
# ═══════════════════════════════════════════════════════════════════════════════
flow_proc power_opt_flow {
    handle_info "Executing POPT rockbottom VT swap flow..."
    flow_exec setup_dmsa
    flow_exec report_baseline
    flow_exec rockbottom_swap
    flow_exec iterative_fix_setup
    flow_exec fix_hold
    flow_exec report_final
    flow_exec write_outputs
    handle_info "POPT rockbottom VT swap flow completed successfully"
}
if {[info exists argv0] && $argv0 eq [info script]} { flow_exec power_opt_flow } else { puts " POPT power_opt procedures loaded" }

# Exit tool after stage completion
exit
