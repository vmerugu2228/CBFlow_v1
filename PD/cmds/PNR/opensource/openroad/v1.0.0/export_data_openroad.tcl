#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow PNR — export_data (opensource / tclsh -> klayout)
# GDS: KLayout reads the signoff DEF with the tech layer map, then
# merges the standard-cell GDS and every child block's released GDS.
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "PNR"
set STAGE_NAME "export_data"
set NODE_NAME [expr {[info exists ::env(CBFLOW_NODE_NAME)] && $::env(CBFLOW_NODE_NAME) ne "" ? $::env(CBFLOW_NODE_NAME) : "export_data1"}]

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_utils.tcl"

set design_name [oss_get flow design_name]
set blocks      [hier_children $design_name]

if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

flow_proc stream_out {
    global design_name blocks flow
    set _def [oss_node_output [oss_chain_node signoff] final.def]
    set _lefs [list [oss_ms "[oss_track],lef_tech"]]
    foreach _l [oss_trk lef] { lappend _lefs $_l }
    set _gds [list [oss_trk gds_stdcell]]
    foreach _b $blocks {
        set _v [hier_block_views $_b]
        lappend _lefs [dict get $_v lef]
        lappend _gds  [dict get $_v gds]
    }
    set _out [oss_stage_out final.gds]
    set _py "$::WORK_DIR/def2gds.py"
    set _fh [open $_py w]
    puts $_fh "import pya, sys"
    puts $_fh "opts = pya.LoadLayoutOptions()"
    puts $_fh "cfg = opts.lefdef_config"
    puts $_fh "cfg.map_file = '[oss_get tech klayout,def_layer_map]'"
    puts $_fh "cfg.lef_files = \[[join [lmap _l $_lefs {format "'%s'" $_l}] {, }]\]"
    # 2 = never draw LEF geometry: every macro (std cell or child block) is an
    # empty cell filled from its GDS. (1 draws LEF geometry — child-block OBS
    # blankets shorted the child for LVS.)
    puts $_fh "cfg.macro_resolution_mode = 2"
    puts $_fh "cfg.read_lef_with_def = False"
    puts $_fh "ly = pya.Layout()"
    puts $_fh "ly.read('$_def', opts)"
    foreach _g $_gds { puts $_fh "ly.read('$_g')" }
    puts $_fh "top = ly.cell('$design_name')"
    puts $_fh "out = pya.Layout(); out.dbu = ly.dbu"
    puts $_fh "out.create_cell('$design_name').copy_tree(top)"
    puts $_fh "empty = sorted(c.name for c in out.each_cell() if c.is_empty() and c.name != '$design_name')"
    puts $_fh "if empty:"
    puts $_fh "    print('ERROR: cells without GDS geometry: ' + ' '.join(empty)); sys.exit(1)"
    # Min-area repair: the detailed router leaves via-pair pads (M2M3+M3M4
    # 0.23 um apart) below the layer AREA rule on sky130 while reporting them
    # clean. Grow each undersized top-level polygon along its long axis to
    # the minimum, on the manufacturing grid. PV DRC/LVS verify the result.
    puts $_fh "import math"
    puts $_fh "fixes = \[\]"
    # Empty list = repair off (violations stay in the layout, PV reports them).
    if {![info exists ::pnr(oss,export,min_area_layers)]} { error "pnr(oss,export,min_area_layers) is not set" }
    foreach {_gl _gd _amin} $::pnr(oss,export,min_area_layers) {
        puts $_fh "li = out.layer($_gl, $_gd); amin = int($_amin * 1e6); grid = 5"
        puts $_fh "allm = pya.Region(out.top_cell().begin_shapes_rec(li)).merged()"
        puts $_fh "for p in allm.each():"
        puts $_fh "    if p.area() >= amin: continue"
        puts $_fh "    b = p.bbox(); w, h = b.width(), b.height()"
        puts $_fh "    if w >= h:"
        puts $_fh "        need = int(math.ceil((amin / h - w) / 2.0 / grid)) * grid + grid"
        puts $_fh "        nb = pya.Box(b.left - need, b.bottom, b.right + need, b.top)"
        puts $_fh "    else:"
        puts $_fh "        need = int(math.ceil((amin / w - h) / 2.0 / grid)) * grid + grid"
        puts $_fh "        nb = pya.Box(b.left, b.bottom - need, b.right, b.top + need)"
        puts $_fh "    out.top_cell().shapes(li).insert(nb)"
        puts $_fh "    fixes.append('$_gl/$_gd %.4f um2 at (%.3f,%.3f) -> %.4f um2' % (p.area()/1e6, b.left/1000.0, b.bottom/1000.0, nb.area()/1e6))"
    }
    puts $_fh "open('$::REPORTS_DIR/export_min_area_fixes.rpt', 'w').write('min-area patches (GDS only, not in DEF): %d\\n' % len(fixes) + '\\n'.join(fixes) + '\\n')"
    puts $_fh "print('min-area patches: %d' % len(fixes))"
    puts $_fh "out.write('$_out')"
    puts $_fh "print('GDS written: $_out cells=%d' % out.cells())"
    close $_fh
    if {[is_true $flow(test_mode)]} {
        puts "  TEST_CMD: klayout -zz -r $_py"
    } else {
        set _log "$::REPORTS_DIR/export_data_klayout.log"
        if {[catch {exec klayout -zz -r $_py >& $_log} _err]} {
            error "KLayout DEF->GDS failed (see $_log): $_err"
        }
        handle_info [exec tail -1 $_log]
        # Routed-layout image for SmartGrid (release images/) — reporting only
        set _png [oss_stage_out layout.png]
        set _ipy "$::WORK_DIR/run/layout_image.py"
        set _fh [open $_ipy w]
        puts $_fh "import pya"
        puts $_fh "lv = pya.LayoutView()"
        puts $_fh "lv.set_config('background-color', '#ffffff')"
        puts $_fh "lv.load_layout('$_out', True)"
        puts $_fh "lv.max_hier()"
        puts $_fh "lv.zoom_fit()"
        puts $_fh "lv.save_image('$_png', 1600, 1600)"
        puts $_fh "print('layout image: $_png')"
        close $_fh
        if {[catch {exec klayout -zz -r $_ipy >& "$::REPORTS_DIR/layout_image.log"} _err]} {
            handle_warning "layout image not written (see $::REPORTS_DIR/layout_image.log)"
        }
    }
}

flow_exec_all
exit
