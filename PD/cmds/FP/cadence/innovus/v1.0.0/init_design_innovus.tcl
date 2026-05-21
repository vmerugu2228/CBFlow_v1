#!/usr/bin/env tclsh
# FP init_design - Cadence Innovus

# -- Bootstrap -----------------------------------------------------------------
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "FP"
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
    global fp tech flow

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
# Innovus-RM: read_verilog (gate-level netlist), set_top_module
# ==============================================================================
flow_proc read_design {
    handle_info "Reading design netlist..."
    global fp project flow

    set design_name [expr {[info exists fp(common,design_name)] ? $fp(common,design_name) : $flow(design_name)}]
    set top_module [expr {[info exists project(top_module)] ? $project(top_module) : $design_name}]

    # Read gate-level netlist from synthesis output
    set netlist_file ""
    if {[info exists fp(input,netlist)] && $fp(input,netlist) ne ""} {
        set netlist_file $fp(input,netlist)
    } elseif {[info exists fp(common,input_netlist)] && $fp(common,input_netlist) ne ""} {
        set netlist_file $fp(common,input_netlist)
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
        handle_error "Netlist not found: $netlist_file -- set fp(input,netlist)"
        return -code error "Missing netlist"
    }

    # Set top module
    handle_info "Setting top module: $top_module"
    set_top_module $top_module

    handle_info "Design read: $design_name (top=$top_module)"
}

# ==============================================================================
# flow_proc: load_constraints
# Innovus-RM: read_sdc -- timing constraints
# ==============================================================================
flow_proc load_constraints {
    handle_info "Loading timing constraints..."
    global fp flow

    set design_name [expr {[info exists fp(common,design_name)] ? $fp(common,design_name) : $flow(design_name)}]

    # SDC constraints
    set sdc_file ""
    if {[info exists fp(input,sdc_file)] && $fp(input,sdc_file) ne ""} {
        set sdc_file $fp(input,sdc_file)
    } elseif {[info exists fp(common,input_sdc)] && $fp(common,input_sdc) ne ""} {
        set sdc_file [lindex $fp(common,input_sdc) 0]
    } else {
        set sdc_file "$::SDC_DIR/${design_name}.sdc"
    }

    if {$sdc_file ne "" && [file exists $sdc_file]} {
        handle_info "Reading SDC: $sdc_file"
        read_sdc $sdc_file
    } else {
        handle_warning "No SDC file found -- FP will run without timing constraints"
    }

    handle_info "Constraints loaded"
}

# ==============================================================================
# flow_proc: setup_mmmc
# Innovus-RM: MMMC setup -- library sets, delay corners, constraint modes,
#             analysis views
# ==============================================================================
flow_proc setup_mmmc {
    handle_info "Setting up MMMC scenarios..."
    global fp tech
    global analysis_views library_sets

    # User MMMC setup file
    if {[info exists fp(common,mmmc_setup_file)] && [file exists $fp(common,mmmc_setup_file)]} {
        handle_info "Sourcing MMMC setup: $fp(common,mmmc_setup_file)"
        source $fp(common,mmmc_setup_file)
        handle_info "MMMC setup completed from user script"
        return
    }

    # Innovus MMMC file
    if {[info exists fp(mmmc,file)] && [file exists $fp(mmmc,file)]} {
        handle_info "Sourcing Innovus MMMC file: $fp(mmmc,file)"
        source $fp(mmmc,file)
        handle_info "MMMC loaded from mmmc file"
        return
    }

    # Auto-create from CBflow mmmc_config
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

        # Create corners, constraint modes, and analysis views
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
    global fp project tech flow

    set design_name [expr {[info exists fp(common,design_name)] ? $fp(common,design_name) : $flow(design_name)}]

    # Set power/ground nets
    set pwr_net [expr {[info exists fp(common,power_net)] ? $fp(common,power_net) : "VDD"}]
    set gnd_net [expr {[info exists fp(common,ground_net)] ? $fp(common,ground_net) : "VSS"}]
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
# flow_proc: setup_parasitics
# Innovus-RM: QRC tech file for parasitics extraction
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
    }

    handle_info "Parasitic technology setup completed"
}

# ==============================================================================
# flow_proc: setup_power_intent
# Innovus-RM: read_power_intent (UPF/CPF), commit_power_intent
# ==============================================================================
flow_proc setup_power_intent {
    handle_info "Setting up power intent..."
    global fp

    if {[info exists fp(input,upf_file)] && $fp(input,upf_file) ne ""} {
        if {[file exists $fp(input,upf_file)]} {
            handle_info "Reading UPF: $fp(input,upf_file)"
            read_power_intent -1801 $fp(input,upf_file)

            if {[info exists fp(common,input_upf_supplemental)] && [file exists $fp(common,input_upf_supplemental)]} {
                handle_info "Reading supplemental UPF: $fp(common,input_upf_supplemental)"
                read_power_intent -1801 $fp(common,input_upf_supplemental)
            }

            handle_info "Committing power intent..."
            commit_power_intent
        } else {
            handle_warning "UPF file not found: $fp(input,upf_file)"
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
    global fp flow

    set run_dir $::env(CBFLOW_RUN_DIR)
    set design_name [expr {[info exists fp(common,design_name)] ? $fp(common,design_name) : $flow(design_name)}]

    file mkdir "$run_dir/outputs"

    # Save Innovus design database
    set checkpoint_dir "$::WORK_DIR/checkpoints"
    file mkdir $checkpoint_dir
    saveDesign "${checkpoint_dir}/init_design.enc"
    handle_info "Design saved: ${checkpoint_dir}/init_design.enc"

    # Write DEF for downstream consumption
    catch {
        defOut "$run_dir/outputs/init_design.def.gz"
        handle_info "DEF written: $run_dir/outputs/init_design.def.gz"
    }

    handle_info "Init design saved"
}

# ==============================================================================
# flow_proc: generate_reports
# Innovus-RM: report_design, timeDesign, report_area, checkDesign
# ==============================================================================
flow_proc generate_reports {
    handle_info "Generating init_design reports..."
    global fp

    file mkdir "$::REPORTS_DIR"

    set max_paths [expr {[info exists fp(analysis,max_paths)] ? $fp(analysis,max_paths) : 100}]

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
# Source setup.tcl (flow_proc hooks: prepend, append, replace)
# Must be sourced AFTER flow_proc definitions but BEFORE flow_exec_all
# ==============================================================================
set _setup_file "$run_dir/work/FP/init_design1/run/setup.tcl"
if {[file exists $_setup_file]} {
    handle_info "Sourcing setup hooks: $_setup_file"
    source $_setup_file
}
# Also source user override directly if present
set _override_file "$run_dir/setup/override_setup.tcl"
if {[file exists $_override_file]} {
    handle_info "Sourcing user override: $_override_file"
    source $_override_file
}
set _stage_override "$run_dir/setup/override_setup.init_design.tcl"
if {[file exists $_stage_override]} {
    handle_info "Sourcing stage override: $_stage_override"
    source $_stage_override
}

# ==============================================================================
# Execute all flow_procs in definition order
# ==============================================================================
flow_exec_all

handle_info "Init design completed -- exiting Innovus"
exit
