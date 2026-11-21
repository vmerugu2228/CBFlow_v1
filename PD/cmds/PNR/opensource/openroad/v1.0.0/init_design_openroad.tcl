#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow PNR — init_design (opensource / openroad)
# Load the SYNTH-released netlist + SDC, floorplan (+ hard-macro placement for
# child blocks), tracks, IO pins, well taps, power intent (UPF), power grid.
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "PNR"
set STAGE_NAME "init_design"
set NODE_NAME [expr {[info exists ::env(CBFLOW_NODE_NAME)] && $::env(CBFLOW_NODE_NAME) ne "" ? $::env(CBFLOW_NODE_NAME) : "init_design1"}]

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_utils.tcl"

set design_name [oss_get flow design_name]
set blocks      [hier_children $design_name]

if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

flow_proc load_netlist {
    global design_name blocks
    set_thread_count [oss_get pnr oss,threads]
    oss_read_lefs $blocks
    oss_read_corners $::NODE_NAME $blocks
    read_verilog [lindex [glob -nocomplain "$::NETLIST_DIR/${design_name}.v" "$::NETLIST_DIR/*.v"] 0]
    link_design $design_name
    read_sdc [oss_sdc_file]
    set_dont_use [oss_trk dont_use_pnr]
}

flow_proc floorplan {
    global pnr
    set _site [oss_trk site]
    set _die  $pnr(oss,fp,die_area)
    if {$_die ne ""} {
        set _m [oss_get pnr oss,fp,core_margin]
        lassign $_die _x0 _y0 _x1 _y1
        initialize_floorplan -site $_site -die_area $_die \
            -core_area [list [expr {$_x0 + $_m}] [expr {$_y0 + $_m}] [expr {$_x1 - $_m}] [expr {$_y1 - $_m}]]
    } else {
        initialize_floorplan -site $_site \
            -utilization  [oss_get pnr oss,fp,core_utilization] \
            -aspect_ratio [oss_get pnr oss,fp,aspect_ratio] \
            -core_space   [oss_get pnr oss,fp,core_margin]
    }
    oss_make_tracks
}

flow_proc place_macros {
    global blocks pnr
    if {[llength $blocks] > 0} {
        set _halo [oss_get pnr oss,macro,halo]
        # Explicit placement wins: pnr(oss,macro,placement) {inst x y orient ...}
        if {$pnr(oss,macro,placement) ne ""} {
            foreach {_inst _x _y _o} $pnr(oss,macro,placement) {
                place_macro -macro_name $_inst -location [list $_x $_y] -orientation $_o
            }
        } else {
            rtl_macro_placer -halo_width $_halo -halo_height $_halo
        }
        # Children that export horizontal-strap pins (DL2) must sit on the rail
        # cycle pitch so their straps abut ours with the same net order.
        set _pitch [oss_rail_pitch]
        set _dbu [[ord::get_db_tech] getDbUnitsPerMicron]
        foreach _b $blocks {
            if {[llength [hier_children $_b]] == 0} continue
            foreach _inst [oss_block_insts $_b] {
                set _i [[ord::get_db_block] findInst $_inst]
                set _x [expr {[lindex [$_i getLocation] 0] / double($_dbu)}]
                set _y [expr {[lindex [$_i getLocation] 1] / double($_dbu)}]
                set _ys [expr {round($_y / $_pitch) * $_pitch}]
                if {abs($_ys - $_y) > 1e-6} {
                    handle_info "  $_inst y $_y -> $_ys (rail pitch $_pitch)"
                    place_macro -macro_name $_inst -location [list $_x $_ys] -orientation [$_i getOrient]
                }
            }
        }
        set _fh [open "$::REPORTS_DIR/place_macros.rpt" w]
        foreach _b $blocks {
            foreach _inst [oss_block_insts $_b] {
                set _i [[ord::get_db_block] findInst $_inst]
                set _bb [$_i getBBox]
                puts $_fh [format "%-20s %-14s origin (%.3f, %.3f) %s  bbox (%.3f %.3f %.3f %.3f)" $_inst $_b \
                    [expr {[lindex [$_i getLocation] 0] / double($_dbu)}] [expr {[lindex [$_i getLocation] 1] / double($_dbu)}] \
                    [$_i getOrient] [expr {[$_bb xMin] / double($_dbu)}] [expr {[$_bb yMin] / double($_dbu)}] \
                    [expr {[$_bb xMax] / double($_dbu)}] [expr {[$_bb yMax] / double($_dbu)}]]
            }
        }
        close $_fh
    }
}

flow_proc pins_and_taps {
    global pnr blocks
    place_pins -hor_layers [oss_get pnr oss,pins,hor_layer] \
               -ver_layers [oss_get pnr oss,pins,ver_layer]
    set _halo [oss_get pnr oss,macro,halo]
    tapcell -distance [oss_trk well_tap_distance] \
            -tapcell_master [oss_trk well_tap] -endcap_master [oss_trk endcap] \
            -halo_width_x $_halo -halo_width_y $_halo
}

flow_proc power_grid {
    global design_name blocks
    oss_apply_upf $design_name
    set _p [oss_pdn $design_name $blocks]
    handle_info "PDN: [dict get $_p position] pins=[dict get $_p pins] rails=[dict get $_p rails]"
    oss_check_power
}

flow_proc save {
    write_db [oss_stage_out init_design.odb]
}

flow_exec_all
exit
