#!/usr/bin/env tclsh
# PNR init_design - Cadence Innovus

# -- Bootstrap -----------------------------------------------------------------
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "PNR"
set STAGE_NAME "init_design"
set NODE_NAME "init_design1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# ==============================================================================
# flow_proc: setup_libraries
# Innovus-RM: read_lib / read_lef -- Liberty timing libraries and LEF
#             physical libraries from tech() array
# ==============================================================================
flow_proc setup_libraries {
    handle_info "Setting up libraries..."
    global pnr tech flow
    apply_vt_dont_use

    # ── LEF files (track-aware) ────────────────────────────────────────────────
    set lef_files [list]
    set _trk [expr {[info exists tech(track)] ? $tech(track) : ""}]

    # Technology LEF (must be first — shared across tracks)
    if {[info exists tech(lef,technology)] && $tech(lef,technology) ne ""} {
        if {[file exists $tech(lef,technology)]} {
            lappend lef_files $tech(lef,technology)
        } else {
            handle_warning "Technology LEF not found: $tech(lef,technology)"
        }
    }

    # Track-categorized LEF list (new format — ALL cells per track)
    if {$_trk ne "" && [info exists tech(${_trk},lef)]} {
        foreach lef $tech(${_trk},lef) {
            if {$lef ne "" && [file exists $lef]} { lappend lef_files $lef }
        }
        handle_info "LEF libraries from track ${_trk}: [llength $tech(${_trk},lef)] libs"
    } else {
        # Backward compat — old category-based format
        if {[info exists tech(lef,standard_cells)] && $tech(lef,standard_cells) ne ""} {
            foreach lef $tech(lef,standard_cells) {
                if {$lef ne "" && [file exists $lef]} { lappend lef_files $lef }
            }
        }
        if {[info exists tech(lef,macros)] && $tech(lef,macros) ne ""} {
            foreach lef $tech(lef,macros) {
                if {$lef ne "" && [file exists $lef]} { lappend lef_files $lef }
            }
        }
        if {[info exists tech(lef,memory)] && $tech(lef,memory) ne ""} {
            foreach lef $tech(lef,memory) {
                if {$lef ne "" && [file exists $lef]} { lappend lef_files $lef }
            }
        }
        if {[info exists tech(lef,io_pads)] && $tech(lef,io_pads) ne ""} {
            foreach lef $tech(lef,io_pads) {
                if {$lef ne "" && [file exists $lef]} { lappend lef_files $lef }
            }
        }
    }

    if {[llength $lef_files] > 0} {
        handle_info "Reading [llength $lef_files] LEF files..."
        foreach lef $lef_files {
            handle_info "  LEF: [file tail $lef]"
            read_lef $lef
        }
    } else {
        handle_warning "No LEF files found — check tech(<track>,lef) in tech_config.tcl"
    }

    # ── Liberty timing libraries (track-aware) ────────────────────────────────
    set lib_files [list]

    # Track-categorized nominal lib list (new format)
    if {$_trk ne "" && [info exists tech(${_trk},lib_nom)]} {
        foreach lib $tech(${_trk},lib_nom) {
            if {$lib ne "" && [file exists $lib]} { lappend lib_files $lib }
        }
        handle_info "Liberty libraries from track ${_trk}: [llength $tech(${_trk},lib_nom)] libs"
    } else {
        # Backward compat — old category-based format
        if {[info exists tech(lib,timing)] && $tech(lib,timing) ne ""} {
            foreach lib $tech(lib,timing) {
                if {$lib ne "" && [file exists $lib]} { lappend lib_files $lib }
            }
        }
        if {[info exists tech(lib,memory)] && $tech(lib,memory) ne ""} {
            foreach lib $tech(lib,memory) {
                if {$lib ne "" && [file exists $lib]} { lappend lib_files $lib }
            }
        }
        if {[info exists tech(lib,io_pads)] && $tech(lib,io_pads) ne ""} {
            foreach lib $tech(lib,io_pads) {
                if {$lib ne "" && [file exists $lib]} { lappend lib_files $lib }
            }
        }
    }

    if {[llength $lib_files] > 0} {
        handle_info "Reading [llength $lib_files] Liberty libraries..."
        foreach lib $lib_files {
            handle_info "  LIB: [file tail $lib]"
            read_lib $lib
        }
    }

    handle_info "Library setup completed"
}

# ==============================================================================
# flow_proc: read_design
# Innovus-RM: read_verilog (gate-level netlist from synthesis),
#             set_top_module, init_design
# ==============================================================================
flow_proc read_design {
    handle_info "Reading design netlist..."
    global pnr project flow

    set design_name [expr {[info exists pnr(common,design_name)] ? $pnr(common,design_name) : $flow(design_name)}]
    set top_module [expr {[info exists project(top_module)] ? $project(top_module) : $design_name}]

    # Read gate-level netlist from synthesis output
    set netlist_file ""
    if {[info exists pnr(input,netlist)] && $pnr(input,netlist) ne ""} {
        set netlist_file $pnr(input,netlist)
    } elseif {[info exists pnr(common,input_netlist)] && $pnr(common,input_netlist) ne ""} {
        set netlist_file $pnr(common,input_netlist)
    } else {
        set netlist_file "$::NETLIST_DIR/${design_name}.v"
        if {![file exists $netlist_file]} {
            set netlist_file "$::NETLIST_DIR/${design_name}.vg"
        }
    }

    if {$netlist_file ne "" && [file exists $netlist_file]} {
        handle_info "Reading netlist: $netlist_file"
        read_verilog $netlist_file
    } else {
        handle_error "Netlist not found: $netlist_file -- set pnr(input,netlist)"
        return -code error "Missing netlist"
    }

    # Set top module
    handle_info "Setting top module: $top_module"
    set_top_module $top_module

    handle_info "Design read: $design_name (top=$top_module)"
}

# ==============================================================================
# flow_proc: load_constraints
# Innovus-RM: read_sdc -- timing constraints from synthesis
# ==============================================================================
flow_proc load_constraints {
    handle_info "Loading timing constraints..."
    global pnr flow

    set design_name [expr {[info exists pnr(common,design_name)] ? $pnr(common,design_name) : $flow(design_name)}]

    # SDC constraints
    set sdc_file ""
    if {[info exists pnr(input,sdc)] && $pnr(input,sdc) ne ""} {
        set sdc_file $pnr(input,sdc)
    } elseif {[info exists pnr(input,sdc_file)] && $pnr(input,sdc_file) ne ""} {
        set sdc_file $pnr(input,sdc_file)
    } else {
        set sdc_file "$::SDC_DIR/${design_name}.sdc"
        if {![file exists $sdc_file]} {
            # Try constraints directory
            set sdc_files [glob -nocomplain "$::SDC_DIR/*.sdc"]
            if {[llength $sdc_files] > 0} {
                set sdc_file [lindex $sdc_files 0]
            }
        }
    }

    if {$sdc_file ne "" && [file exists $sdc_file]} {
        handle_info "Reading SDC: $sdc_file"
        read_sdc $sdc_file
    } else {
        handle_warning "No SDC file found -- PNR will run without timing constraints"
    }

    # Additional SDC files
    if {[info exists pnr(input,additional_sdc)] && [llength $pnr(input,additional_sdc)] > 0} {
        foreach sdc $pnr(input,additional_sdc) {
            if {[file exists $sdc]} {
                handle_info "Reading additional SDC: $sdc"
                read_sdc -addConstraint $sdc
            }
        }
    }

    handle_info "Constraints loaded"
}

# ==============================================================================
# flow_proc: setup_mmmc
# Innovus-RM: MMMC setup -- create analysis views, library sets, timing
#             conditions, delay corners, constraint modes
# ==============================================================================
flow_proc setup_mmmc {
    handle_info "Setting up MMMC scenarios..."
    global pnr tech
    global analysis_views library_sets

    # User MMMC setup file (Innovus MMMC TCL)
    if {[info exists pnr(common,mmmc_setup_file)] && [file exists $pnr(common,mmmc_setup_file)]} {
        handle_info "Sourcing MMMC setup: $pnr(common,mmmc_setup_file)"
        source $pnr(common,mmmc_setup_file)
        handle_info "MMMC setup completed from user script"
        return
    }

    # Innovus MMMC file (generated or user-provided)
    if {[info exists pnr(mmmc,file)] && [file exists $pnr(mmmc,file)]} {
        handle_info "Sourcing Innovus MMMC file: $pnr(mmmc,file)"
        source $pnr(mmmc,file)
        handle_info "MMMC loaded from mmmc file"
        return
    }

    # Auto-create from CBflow mmmc_config analysis_views
    if {[info exists analysis_views] && [array size analysis_views] > 0} {
        handle_info "Creating MMMC from mmmc_config: [array size analysis_views] views"

        # Create library sets
        set _lib_sets_created {}
        foreach scenario [lsort [array names analysis_views]] {
            array set _v $analysis_views($scenario)
            set lib_ref [expr {[info exists _v(lib_set_ref)] ? $_v(lib_set_ref) : ""}]
            if {$lib_ref ne "" && $lib_ref ni $_lib_sets_created} {
                set _timing_libs {}
                if {[info exists library_sets(${lib_ref},timing)]} {
                    set _timing_libs $library_sets(${lib_ref},timing)
                }
                if {[llength $_timing_libs] > 0} {
                    create_library_set -name $lib_ref -timing $_timing_libs
                    handle_info "  Library set: $lib_ref ([llength $_timing_libs] libs)"
                }
                lappend _lib_sets_created $lib_ref
            }
            array unset _v
        }

        # Create timing conditions, delay corners, constraint modes, analysis views
        foreach scenario [lsort [array names analysis_views]] {
            array set _v $analysis_views($scenario)
            set _corner $_v(corner)
            set _mode $_v(mode)
            set _lib_ref [expr {[info exists _v(lib_set_ref)] ? $_v(lib_set_ref) : ""}]

            # RC corner
            set _rc_corner "${_corner}_rc"
            catch {
                set rc_cmd "create_rc_corner -name $_rc_corner"
                if {[info exists tech(ext,qrc_tech)] && [file exists $tech(ext,qrc_tech)]} {
                    lappend rc_cmd -qrc_tech $tech(ext,qrc_tech)
                }
                if {[info exists _v(temperature)] && $_v(temperature) ne ""} {
                    lappend rc_cmd -T $_v(temperature)
                }
                eval $rc_cmd
            }

            # Delay corner
            set _delay_corner "${_corner}_delay"
            catch {
                create_delay_corner -name $_delay_corner \
                    -library_set $_lib_ref \
                    -rc_corner $_rc_corner
            }

            # Constraint mode
            set _constraint_mode "${_mode}_constraint"
            catch {
                set _sdc_file [expr {[info exists _v(constraint_file)] ? $_v(constraint_file) : ""}]
                set _sdc_path "$::SDC_DIR/$_sdc_file"
                if {$_sdc_file ne "" && [file exists $_sdc_path]} {
                    create_constraint_mode -name $_constraint_mode \
                        -sdc_files $_sdc_path
                } else {
                    create_constraint_mode -name $_constraint_mode
                }
            }

            # Analysis view
            catch {
                create_analysis_view -name $scenario \
                    -constraint_mode $_constraint_mode \
                    -delay_corner $_delay_corner
                handle_info "  Analysis view: $scenario (corner=$_corner, mode=$_mode)"
            }

            array unset _v
        }

        # Set active analysis views
        set _setup_views {}
        set _hold_views {}
        foreach scenario [lsort [array names analysis_views]] {
            array set _v $analysis_views($scenario)
            if {[info exists _v(type)] && $_v(type) eq "hold"} {
                lappend _hold_views $scenario
            } else {
                lappend _setup_views $scenario
            }
            array unset _v
        }
        if {[llength $_setup_views] > 0 || [llength $_hold_views] > 0} {
            set set_views_cmd "set_analysis_view"
            if {[llength $_setup_views] > 0} {
                lappend set_views_cmd -setup $_setup_views
            }
            if {[llength $_hold_views] > 0} {
                lappend set_views_cmd -hold $_hold_views
            }
            eval $set_views_cmd
        }

        handle_info "MMMC: [llength $_lib_sets_created] library sets, [array size analysis_views] views"
    } else {
        handle_info "No MMMC analysis_views defined -- single corner mode"
    }

    handle_info "MMMC setup completed"
}

# ==============================================================================
# flow_proc: run_init_design
# Innovus-RM: init_design command -- initializes the design in Innovus
# ==============================================================================
flow_proc run_init_design {
    handle_info "Running Innovus init_design..."
    global pnr project tech flow

    set design_name [expr {[info exists pnr(common,design_name)] ? $pnr(common,design_name) : $flow(design_name)}]

    # Set power/ground nets
    set pwr_net [expr {[info exists pnr(common,power_net)] ? $pnr(common,power_net) : "VDD"}]
    set gnd_net [expr {[info exists pnr(common,ground_net)] ? $pnr(common,ground_net) : "VSS"}]
    set init_pwr_net $pwr_net
    set init_gnd_net $gnd_net

    handle_info "Power net: $pwr_net, Ground net: $gnd_net"

    # Run init_design
    init_design
    handle_info "init_design completed"

    # Connect global nets
    catch {
        globalNetConnect $pwr_net -type pgpin -pin $pwr_net -inst * -override
        globalNetConnect $gnd_net -type pgpin -pin $gnd_net -inst * -override
        handle_info "Global nets connected: $pwr_net / $gnd_net"
    }

    handle_info "Innovus init_design completed"
}

# ==============================================================================
# flow_proc: load_floorplan
# Innovus-RM: read_def / loadFPlan -- floorplan from FP flow output or DEF
# ==============================================================================
flow_proc load_floorplan {
    handle_info "Loading floorplan..."
    global pnr

    # Floorplan DEF
    if {[info exists pnr(input,def_file)] && $pnr(input,def_file) ne ""} {
        if {[file exists $pnr(input,def_file)]} {
            handle_info "Reading DEF floorplan: $pnr(input,def_file)"
            defIn $pnr(input,def_file)
        } else {
            handle_warning "DEF file not found: $pnr(input,def_file)"
        }
    } elseif {[info exists pnr(input,fp_tcl)] && $pnr(input,fp_tcl) ne "" && [file exists $pnr(input,fp_tcl)]} {
        handle_info "Sourcing floorplan TCL: $pnr(input,fp_tcl)"
        source $pnr(input,fp_tcl)
    } elseif {[info exists pnr(input,fplan_file)] && [file exists $pnr(input,fplan_file)]} {
        handle_info "Loading floorplan: $pnr(input,fplan_file)"
        loadFPlan $pnr(input,fplan_file)
    } else {
        handle_info "No floorplan specified -- will use auto-floorplan"
    }

    # Scan DEF
    if {[info exists pnr(input,scan_def)] && $pnr(input,scan_def) ne ""} {
        if {[file exists $pnr(input,scan_def)]} {
            handle_info "Reading scan DEF: $pnr(input,scan_def)"
            defIn $pnr(input,scan_def)
        }
    }

    handle_info "Floorplan loaded"
}

# ==============================================================================
# flow_proc: setup_parasitics
# Innovus-RM: setExtractRCMode / QRC tech file for parasitics
# ==============================================================================
flow_proc setup_parasitics {
    handle_info "Setting up parasitic technology..."
    global tech

    # QRC tech file
    if {[info exists tech(ext,qrc_tech)] && $tech(ext,qrc_tech) ne "" && [file exists $tech(ext,qrc_tech)]} {
        handle_info "Setting QRC tech file: $tech(ext,qrc_tech)"
        setExtractRCMode -engine postRoute -effortLevel medium
        set_db extract_rc_engine_cmd {-qrc_tech_file $tech(ext,qrc_tech)}
    }

    # Cap tables (legacy)
    if {[info exists tech(captable,typical)] && [file exists $tech(captable,typical)]} {
        handle_info "Setting cap table: $tech(captable,typical)"
        setExtractRCMode -engine preRoute
        set_db design_process_node [expr {[info exists tech(node)] ? $tech(node) : ""}]
    }

    handle_info "Parasitic technology setup completed"
}

# ==============================================================================
# flow_proc: setup_dont_use
# Innovus-RM: setDontUse -- library cell restrictions
# ==============================================================================
flow_proc setup_dont_use {
    handle_info "Setting library cell restrictions..."
    global pnr tech

    # Dont-use cells
    if {[info exists tech(dont_use_cells)] && $tech(dont_use_cells) ne ""} {
        foreach cell $tech(dont_use_cells) {
            setDontUse $cell true
        }
        handle_info "Dont-use applied: [llength $tech(dont_use_cells)] cells"
    }

    # Lib cell purpose file
    if {[info exists pnr(common,lib_cell_purpose_file)] && [file exists $pnr(common,lib_cell_purpose_file)]} {
        handle_info "Sourcing lib cell purpose: $pnr(common,lib_cell_purpose_file)"
        source $pnr(common,lib_cell_purpose_file)
    } elseif {[info exists tech(lib_cell_purpose_file)] && [file exists $tech(lib_cell_purpose_file)]} {
        handle_info "Sourcing lib cell purpose from tech: $tech(lib_cell_purpose_file)"
        source $tech(lib_cell_purpose_file)
    }

    handle_info "Library cell restrictions applied"
}

# ==============================================================================
# flow_proc: setup_power_intent
# Innovus-RM: read_power_intent (UPF/CPF), commit_power_intent
# ==============================================================================
flow_proc setup_power_intent {
    handle_info "Setting up power intent..."
    global pnr

    # UPF (IEEE 1801)
    if {[info exists pnr(input,upf_file)] && $pnr(input,upf_file) ne ""} {
        if {[file exists $pnr(input,upf_file)]} {
            handle_info "Reading UPF: $pnr(input,upf_file)"
            read_power_intent -1801 $pnr(input,upf_file)

            # Supplemental UPF
            if {[info exists pnr(input,upf_supplemental)] && [file exists $pnr(input,upf_supplemental)]} {
                handle_info "Reading supplemental UPF: $pnr(input,upf_supplemental)"
                read_power_intent -1801 $pnr(input,upf_supplemental)
            }

            handle_info "Committing power intent..."
            commit_power_intent
        } else {
            handle_warning "UPF file not found: $pnr(input,upf_file)"
        }
    } elseif {[info exists pnr(input,cpf_file)] && $pnr(input,cpf_file) ne ""} {
        if {[file exists $pnr(input,cpf_file)]} {
            handle_info "Reading CPF: $pnr(input,cpf_file)"
            read_power_intent -cpf $pnr(input,cpf_file)
            commit_power_intent
        }
    } else {
        handle_info "No power intent file specified -- single power domain"
    }

    handle_info "Power intent setup completed"
}

# ==============================================================================
# flow_proc: save_design
# Innovus-RM: saveDesign -- save Innovus database checkpoint
# ==============================================================================
flow_proc save_design {
    handle_info "Saving init_design checkpoint..."
    global pnr flow

    set run_dir $::env(CBFLOW_RUN_DIR)
    set design_name [expr {[info exists pnr(common,design_name)] ? $pnr(common,design_name) : $flow(design_name)}]

    file mkdir "$run_dir/outputs"

    # Save Innovus design database
    set _outputs "$::WORK_DIR/outputs"
    file mkdir $_outputs
    saveDesign "$_outputs/init_design.enc"
    handle_info "Design saved: $_outputs/init_design.enc"

    # Write DEF for downstream consumption
    catch {
        defOut "$run_dir/outputs/init_design.def.gz"
        handle_info "DEF written: $run_dir/outputs/init_design.def.gz"
    }

    handle_info "Init design saved"
}

# ==============================================================================
# flow_proc: generate_reports
# Innovus-RM: report_design, timeDesign, report_area, report_power
# ==============================================================================
flow_proc generate_reports {
    handle_info "Generating init_design reports..."
    global pnr

    file mkdir "$::REPORTS_DIR"

    set max_paths [expr {[info exists pnr(analysis,max_paths)] ? $pnr(analysis,max_paths) : 100}]

    # Design summary
    catch { report_design -outfile "$::REPORTS_DIR/design_summary.rpt" }

    # Pre-place timing
    catch { timeDesign -prePlace -outDir "$::REPORTS_DIR" -prefix init_design }

    # Area report
    catch { report_area -outfile "$::REPORTS_DIR/report_area.rpt" }

    # Power report
    catch { report_power -outfile "$::REPORTS_DIR/report_power.rpt" }

    # Timing report
    catch {
        report_timing -max_paths $max_paths -nworst 1 \
            -outfile "$::REPORTS_DIR/report_timing.rpt"
    }

    # Design checks
    catch { checkDesign -all -outfile "$::REPORTS_DIR/check_design.rpt" }

    handle_info "Init design reports generated in: $::REPORTS_DIR"
}


# ==============================================================================
# Execute all flow_procs in definition order
# ==============================================================================
flow_exec_all

handle_info "Init design completed -- exiting Innovus"
exit
