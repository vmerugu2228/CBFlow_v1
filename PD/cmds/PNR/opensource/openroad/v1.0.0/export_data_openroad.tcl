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
set NODE_NAME [cbflow_node_name]

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_utils.tcl"

set design_name [oss_get flow design_name]
set blocks      [hier_children $design_name]

if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

# Load: the source stage's deliverables into outputs/ + the views KLayout
# merges (tech + track LEFs, standard-cell GDS, every child block's LEF /
# GDS). Source = the nearest non-bypassed implementation node upstream
# (oss_source_node): signoff on the normal trunk; place when cts..signoff are
# bypassed, when this node is rewired onto place (cbflow run set-dep), or for
# an export node added under place (add-node). Signoff's deliverables are
# copied; an earlier stage's are written from its database (OpenROAD).
flow_proc load_design {
    global blocks
    set ::export_src [oss_source_node [oss_get pnr oss,release,source_stages]]
    set _st [oss_node_type $::export_src]
    set _out "$::WORK_DIR/outputs"
    file mkdir $_out
    if {$_st eq "signoff"} {
        set _so "[cbflow_node_dir $::export_src]/outputs"
        foreach _f {final.def final.v final.lvs.v final.lef final.cdl final.sdc final.odb} {
            file copy -force [oss_node_output $::export_src $_f] "$_out/$_f"
        }
        foreach _lib [glob -nocomplain "$_so/final__*.lib"] { file copy -force $_lib $_out }
    } else {
        set _scr "$::WORK_DIR/run/deliverables_${::export_src}.tcl"
        set _fh [open $_scr w]
        puts $_fh "read_db [oss_prev_odb $::export_src]"
        foreach _c [oss_deliverable_cmds $_out $blocks] { puts $_fh $_c }
        puts $_fh "exit"
        close $_fh
        oss_exec_tool openroad $_scr "$::REPORTS_DIR/export_deliverables.log"
        file copy -force [oss_sdc_file] "$_out/final.sdc"
    }
    set _fh [open "$_out/export.source" w]
    puts $_fh "source_node $::export_src\nsource_type $_st"
    close $_fh
    handle_info "export source: $::export_src ($_st)"
    set ::export_def "$_out/final.def"
    lassign [oss_export_views $blocks] ::export_lefs ::export_gds
}

# DEF -> GDS recipe (<node>/def2gds.py): DEF over the LEFs, every macro
# filled from its GDS, min-area repair. KLayout runs it in save_design.
flow_proc stream_out {
    global design_name
    oss_def2gds_script "$::WORK_DIR/def2gds.py" $design_name $::export_def \
        $::export_lefs $::export_gds [oss_stage_out final.gds] pnr
}

# Save: KLayout streams the layout -> outputs/final.gds
flow_proc save_design {
    global flow
    # KLayout batch command inside the tool container (this stage runs there).
    set _klayout [oss_get pnr oss,export,klayout_batch]
    set _py "$::WORK_DIR/def2gds.py"
    if {[is_true $flow(test_mode)]} {
        puts "  TEST_CMD: $_klayout $_py"
    } else {
        set _log "$::REPORTS_DIR/export_data_klayout.log"
        if {[catch {exec {*}$_klayout $_py >& $_log} _err]} {
            error "KLayout DEF->GDS failed (see $_log): $_err"
        }
        handle_info [exec tail -1 $_log]
    }
}

# Report: routed-layout image for SmartGrid (release images/) — reporting
# only. Rendered from the GDS save_design wrote, so it runs after it.
flow_proc report {
    global flow
    if {![is_true $flow(test_mode)]} {
        set _klayout [oss_get pnr oss,export,klayout_batch]
        set _out [oss_stage_out final.gds]
        set _png [oss_stage_out [oss_get pnr oss,export,layout_image,file]]
        set _ipy "$::WORK_DIR/run/layout_image.py"
        set _fh [open $_ipy w]
        puts $_fh "import pya"
        puts $_fh "lv = pya.LayoutView()"
        puts $_fh "lv.set_config('background-color', '[oss_get pnr oss,export,layout_image,background]')"
        puts $_fh "lv.load_layout('$_out', True)"
        puts $_fh "lv.max_hier()"
        puts $_fh "lv.zoom_fit()"
        set _px [oss_get pnr oss,export,layout_image,size]
        puts $_fh "lv.save_image('$_png', $_px, $_px)"
        puts $_fh "print('layout image: $_png')"
        close $_fh
        if {[catch {exec {*}$_klayout $_ipy >& "$::REPORTS_DIR/layout_image.log"} _err]} {
            handle_warning "layout image not written (see $::REPORTS_DIR/layout_image.log)"
        }
    }
}

flow_exec_all
exit
