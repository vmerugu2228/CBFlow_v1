#!/usr/bin/env tclsh
# ==============================================================================
# FP powerplan — Cadence Innovus
# Description: Power grid creation — rings, straps, mesh, rail routing,
#              global net connections, and PG verification
# ==============================================================================

# ── Bootstrap ─────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "FP"
set STAGE_NAME "powerplan"
set NODE_NAME "powerplan1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

handle_info "Starting CBflow FP powerplan stage for Innovus"

# ==============================================================================
# flow_proc: load_design
# Description: Restore design from floorplan stage
# ==============================================================================
flow_proc load_design {
    global run_dir flow

    set _db "$run_dir/work/FP/floorplan1/outputs/floorplan.enc.dat"
    if {![file exists $_db]} {
        handle_error "Floorplan database not found: $_db"
        return
    }
    handle_info "Restoring design: $_db"
    restoreDesign $_db $flow(design_name)
    handle_info "Design restored: $flow(design_name)"
}

# ==============================================================================
# flow_proc: activate_node_scenarios
# Description: Activate MMMC scenarios for this node (deactivate rest)
# ==============================================================================
flow_proc activate_node_scenarios {
    global mmmc STAGE_NAME

    if {![info exists mmmc($STAGE_NAME)]} {
        handle_info "No node-specific scenarios for $STAGE_NAME — all views remain active"
        return
    }

    handle_info "Activating scenarios for: $STAGE_NAME"
    array set _nd $mmmc($STAGE_NAME)
    set _setup [expr {[info exists _nd(setup)] ? $_nd(setup) : {}}]
    set _hold  [expr {[info exists _nd(hold)]  ? $_nd(hold)  : {}}]

    handle_info "  Setup: $_setup"
    handle_info "  Hold:  $_hold"

    set_analysis_view -setup {} -hold {}
    set_analysis_view -setup $_setup -hold $_hold
}

# ==============================================================================
# Mandatory config variables — error if not set
# ==============================================================================

foreach _req {fp(power,vdd_net) fp(power,vss_net) fp(power,vdd_pin) fp(power,vss_pin)} {
    if {![info exists $_req] || [set $_req] eq ""} {
        handle_error "$_req is not set. Define in user_config or FP tool config."
        return -code error "$_req is not set. Define in user_config or FP tool config."
    }
}

set PG_VDD $fp(power,vdd_net)
set PG_VSS $fp(power,vss_net)

# ==============================================================================
# flow_proc: connect_global_nets
# Description: Connect VDD/VSS to all instances before PG creation
# ==============================================================================
flow_proc connect_global_nets {
    global fp PG_VDD PG_VSS

    handle_info "Connecting global power nets: $PG_VDD / $PG_VSS"

    # Primary power/ground pin connections
    globalNetConnect $PG_VDD -type pgpin -pin $fp(power,vdd_pin) -inst * -override
    globalNetConnect $PG_VSS -type pgpin -pin $fp(power,vss_pin) -inst * -override

    # Tie-high/tie-low connections
    if {[info exists fp(power,tie_high_pin)] && $fp(power,tie_high_pin) ne ""} {
        handle_info "  Tie-high: $fp(power,tie_high_pin) -> $PG_VDD"
        globalNetConnect $PG_VDD -type tiehi -pin $fp(power,tie_high_pin) -inst * -override
    }
    if {[info exists fp(power,tie_low_pin)] && $fp(power,tie_low_pin) ne ""} {
        handle_info "  Tie-low: $fp(power,tie_low_pin) -> $PG_VSS"
        globalNetConnect $PG_VSS -type tielo -pin $fp(power,tie_low_pin) -inst * -override
    }

    # Additional power domains (multi-voltage)
    if {[info exists fp(power,additional_nets)]} {
        foreach {net pin} $fp(power,additional_nets) {
            handle_info "  Additional: $net -> $pin"
            globalNetConnect $net -type pgpin -pin $pin -inst * -override
        }
    }

    handle_info "Global net connections completed"
}

# ==============================================================================
# flow_proc: create_power_rings
# Description: Core boundary rings + optional macro rings
# ==============================================================================
flow_proc create_power_rings {
    global fp tech PG_VDD PG_VSS

    handle_info "Creating power rings..."

    # Ring layers — from tech config (metal stack provides these)
    if {![info exists fp(power,ring_layer_h)] || ![info exists fp(power,ring_layer_v)]} {
        handle_error "fp(power,ring_layer_h) and fp(power,ring_layer_v) must be set"
        handle_error "Typically top two thick metals, e.g., M10 (H) and M9 (V)"
        return
    }

    set layer_h $fp(power,ring_layer_h)
    set layer_v $fp(power,ring_layer_v)

    # Ring dimensions — must be defined in config
    if {![info exists fp(power,ring_width)]} {
        handle_error "fp(power,ring_width) must be set"
        return
    }

    set ring_width   $fp(power,ring_width)
    set ring_spacing [expr {[info exists fp(power,ring_spacing)] ? $fp(power,ring_spacing) : $ring_width}]
    set ring_offset  [expr {[info exists fp(power,ring_offset)]  ? $fp(power,ring_offset)  : $ring_spacing}]

    handle_info "  Layers: H=$layer_h V=$layer_v"
    handle_info "  Width=${ring_width}um Spacing=${ring_spacing}um Offset=${ring_offset}um"

    # Core rings
    addRing \
        -nets [list $PG_VDD $PG_VSS] \
        -type core_rings \
        -layer [list $layer_h $layer_v] \
        -width $ring_width \
        -spacing $ring_spacing \
        -offset $ring_offset \
        -follow core \
        -jog_distance 0.5 \
        -threshold 0.5

    # Macro rings
    if {[info exists fp(power,macro_rings)] && $fp(power,macro_rings) eq "true"} {
        set mr_width   [expr {[info exists fp(power,macro_ring_width)]   ? $fp(power,macro_ring_width)   : [expr {$ring_width * 0.5}]}]
        set mr_spacing [expr {[info exists fp(power,macro_ring_spacing)] ? $fp(power,macro_ring_spacing) : [expr {$mr_width * 0.5}]}]
        set mr_offset  [expr {[info exists fp(power,macro_ring_offset)]  ? $fp(power,macro_ring_offset)  : $mr_spacing}]

        handle_info "  Macro rings: width=${mr_width}um spacing=${mr_spacing}um"

        addRing \
            -nets [list $PG_VDD $PG_VSS] \
            -type block_rings \
            -layer [list $layer_h $layer_v] \
            -width $mr_width \
            -spacing $mr_spacing \
            -offset $mr_offset \
            -around each_block
    }

    handle_info "Power rings created"
}

# ==============================================================================
# flow_proc: create_power_straps
# Description: Multi-layer power mesh using addStripe
#   Config: fp(power,straps) — list of per-layer strap specifications
#   Each spec: {layer <L> width <W> spacing <S> pitch <P> direction <H|V>}
# ==============================================================================
flow_proc create_power_straps {
    global fp tech PG_VDD PG_VSS

    handle_info "Creating power straps..."

    if {![info exists fp(power,straps)]} {
        handle_error "fp(power,straps) not defined — no power mesh will be created"
        handle_error "Define in user_config, e.g.:"
        handle_error "  set fp(power,straps) {"
        handle_error "    {layer M10 width 3.2 spacing 1.6 pitch 30.0 direction horizontal}"
        handle_error "    {layer M9  width 3.2 spacing 1.6 pitch 30.0 direction vertical}"
        handle_error "  }"
        return
    }

    foreach strap_spec $fp(power,straps) {
        array set s $strap_spec

        # Validate required keys
        foreach _k {layer width spacing pitch direction} {
            if {![info exists s($_k)]} {
                handle_error "Power strap spec missing '$_k': $strap_spec"
                return
            }
        }

        handle_info "  $s(layer): width=$s(width)um spacing=$s(spacing)um pitch=$s(pitch)um dir=$s(direction)"

        set stripe_cmd [list addStripe \
            -nets [list $PG_VDD $PG_VSS] \
            -layer $s(layer) \
            -width $s(width) \
            -spacing $s(spacing) \
            -set_to_set_distance $s(pitch) \
            -direction $s(direction)]

        # Optional: start offset
        if {[info exists s(start_offset)]} {
            lappend stripe_cmd -start_offset $s(start_offset)
        } else {
            lappend stripe_cmd -start_from left
        }

        # Optional: number of sets
        if {[info exists s(number_of_sets)]} {
            lappend stripe_cmd -number_of_sets $s(number_of_sets)
        }

        # Optional: over specific area
        if {[info exists s(area)]} {
            lappend stripe_cmd -area $s(area)
        }

        # Optional: snap to grid
        lappend stripe_cmd -snap_wire_center_to_grid grid

        eval $stripe_cmd
        array unset s
    }

    handle_info "Power straps created"
}

# ==============================================================================
# flow_proc: route_secondary_pg
# Description: Standard cell rail routing (M1 followpin) + block pin connections
# ==============================================================================
flow_proc route_secondary_pg {
    global fp tech PG_VDD PG_VSS

    handle_info "Routing standard cell PG rails and block pin connections..."

    # Standard cell followpin routing (M1 rails)
    sroute \
        -connect {blockPin padPin corePin floatingStripe} \
        -layerChangeRange [list $fp(power,sroute_bottom_layer) $fp(power,sroute_top_layer)] \
        -blockPinTarget nearestTarget \
        -padPinPortConnect allPort \
        -corePinTarget firstAfterRowEnd \
        -crossoverViaLayerRange [list $fp(power,sroute_bottom_layer) $fp(power,sroute_top_layer)] \
        -nets [list $PG_VDD $PG_VSS] \
        -allowJogging 1 \
        -allowLayerChange 1 \
        -targetViaLayerRange [list $fp(power,sroute_bottom_layer) $fp(power,sroute_top_layer)]

    handle_info "Secondary PG routing completed"
}

# ==============================================================================
# flow_proc: add_pg_vias
# Description: Insert vias at power grid intersections for connectivity
# ==============================================================================
flow_proc add_pg_vias {
    global fp tech PG_VDD PG_VSS

    handle_info "Adding PG vias at strap intersections..."

    # Via stacking at ring/strap intersections
    if {[info exists fp(power,add_vias)] && $fp(power,add_vias) eq "true"} {
        set bottom_layer [expr {[info exists fp(power,via_bottom_layer)] ? $fp(power,via_bottom_layer) : $fp(power,sroute_bottom_layer)}]
        set top_layer    [expr {[info exists fp(power,via_top_layer)]    ? $fp(power,via_top_layer)    : $fp(power,sroute_top_layer)}]

        addVia \
            -nets [list $PG_VDD $PG_VSS] \
            -layerRange [list $bottom_layer $top_layer] \
            -allNet

        handle_info "PG vias added ($bottom_layer to $top_layer)"
    } else {
        handle_info "PG via insertion skipped (fp(power,add_vias) not set to true)"
    }
}

# ==============================================================================
# flow_proc: verify_power
# Description: Check PG connectivity, DRC, and IR drop
# ==============================================================================
flow_proc verify_power {
    global fp tech PG_VDD PG_VSS

    handle_info "Verifying power grid..."
    set errors 0

    # 1. PG connectivity check
    handle_info "  Checking PG connectivity..."
    if {[catch {
        verifyConnectivity \
            -type all \
            -noAntenna \
            -report $::REPORTS_DIR/pg_connectivity.rpt
    } result]} {
        handle_warning "PG connectivity issue: $result"
        incr errors
    }

    # 2. PG net geometry check
    handle_info "  Checking PG net geometry..."
    if {[catch {
        verify_pg_net \
            -net [list $PG_VDD $PG_VSS] \
            -report $::REPORTS_DIR/pg_net_verify.rpt
    } result]} {
        handle_warning "PG net geometry issue: $result"
        incr errors
    }

    # 3. Early IR drop estimate (optional)
    if {[info exists fp(power,analyze_ir)] && $fp(power,analyze_ir) eq "true"} {
        handle_info "  Running early IR drop analysis..."
        if {[catch {
            if {![info exists fp(power,ir_drop_limit)]} {
                handle_error "fp(power,ir_drop_limit) not set — required when fp(power,analyze_ir) is true"
                return
            }
            set ir_limit $fp(power,ir_drop_limit)
            analyzeIR \
                -net $PG_VDD \
                -limit $ir_limit \
                -report $::REPORTS_DIR/ir_drop_vdd.rpt
            analyzeIR \
                -net $PG_VSS \
                -limit $ir_limit \
                -report $::REPORTS_DIR/ir_drop_vss.rpt
        } result]} {
            handle_warning "IR drop analysis: $result"
        }
    }

    if {$errors > 0} {
        handle_warning "Power verification completed with $errors issue(s) — review reports"
    } else {
        handle_info "Power grid verification passed"
    }
}

# ==============================================================================
# flow_proc: generate_reports
# Description: Power grid summary reports
# ==============================================================================
flow_proc generate_reports {
    global fp PG_VDD PG_VSS

    handle_info "Generating powerplan reports..."

    if {[catch {report_power_domain > $::REPORTS_DIR/power_domain.rpt}]} {
        handle_warning "Could not generate power domain report"
    }

    if {[catch {reportPGDensity > $::REPORTS_DIR/pg_density.rpt}]} {
        handle_warning "Could not generate PG density report"
    }

    # Power grid summary
    if {[catch {
        reportNetStat $PG_VDD > $::REPORTS_DIR/pg_net_stat_vdd.rpt
        reportNetStat $PG_VSS > $::REPORTS_DIR/pg_net_stat_vss.rpt
    }]} {
        handle_warning "Could not generate PG net stat reports"
    }

    handle_info "Powerplan reports generated in $::REPORTS_DIR/"
}

# ==============================================================================
# MAIN EXECUTION
# ==============================================================================

handle_info "================================================================"
handle_info "CBflow FP Powerplan — Innovus"
handle_info "  VDD=$PG_VDD  VSS=$PG_VSS"
handle_info "================================================================"

# ==============================================================================
# flow_proc: save_design
# Description: Save database to outputs/ for next stage
# ==============================================================================
flow_proc save_design {
    set _outputs "$::WORK_DIR/outputs"
    file mkdir $_outputs

    saveDesign "$_outputs/powerplan.enc"
    handle_info "Design saved: $_outputs/powerplan.enc"
}

# Execute flow steps in sequence
flow_exec_all

handle_info "CBflow FP powerplan completed successfully"
