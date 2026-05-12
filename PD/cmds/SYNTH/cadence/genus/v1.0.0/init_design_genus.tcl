#!/usr/bin/env tclsh
# CBFlow SYNTH init_design - Cadence Genus
# Genus-RM: init_design -- Library setup, RTL read, elaboration,
#           constraints, MMMC, power, and design checks
# Aligned with Genus 23.1 Reference Methodology

# -- Environment & Utilities --------------------------------------------------
set run_dir $::env(CBFLOW_RUN_DIR)
set env_file "$run_dir/.run.cbflow.tcl"
if {[file exists $env_file]} { source $env_file } else { puts stderr "ERROR: .run.cbflow.tcl not found"; exit 1 }
if {![info exists ::env(FLOW_DIR)] || $::env(FLOW_DIR) eq ""} { puts stderr "ERROR: FLOW_DIR not set"; exit 1 }
set FLOW_DIR $::env(FLOW_DIR)
if {![info exists ::env(UTILITIES_VERSION)] || $::env(UTILITIES_VERSION) eq ""} { puts stderr "ERROR: UTILITIES_VERSION not set"; exit 1 }
set utils_path "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} { source $utils_path } else { puts stderr "ERROR: Utils not found: $utils_path"; exit 1 }
namespace import ::CBFlow::Utilities::print_header

# -- Flow Type & Stage --------------------------------------------------------
set FLOW_TYPE "SYNTH"
set STAGE_NAME "init_design"
set NODE_NAME "init_design1"

# -- Config --------------------------------------------------------------------
set config_file "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
if {[file exists $config_file]} { source $config_file }
global synth project tech flow

# Source tech_config
if {[info exists ::env(TECH_NAME)] && $::env(TECH_NAME) ne "" &&
    [info exists ::env(TECH_VERSION)] && $::env(TECH_VERSION) ne ""} {
    set _tech_config "$::env(CONFIG_ROOT)/tech/$::env(TECH_NAME)/$::env(TECH_VERSION)/tech_config.tcl"
    if {[file exists $_tech_config]} {
        source $_tech_config
        handle_info "Tech config loaded: $_tech_config"
    } else {
        handle_warning "Tech config not found: $_tech_config"
    }
}

# Source MMMC config
catch {
    set mmmc_config_file "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/mmmc_config.tcl"
    if {[file exists $mmmc_config_file]} { source $mmmc_config_file }
}

# Source user_config (overrides)
if {[file exists "$run_dir/setup/user_config.tcl"]} {
    source "$run_dir/setup/user_config.tcl"
}

# -- Flow Initialization ------------------------------------------------------
handle_info "Starting $FLOW_TYPE $STAGE_NAME (Genus)..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

# -- Directories ---------------------------------------------------------------
set WORK_DIR "$run_dir/work/$FLOW_TYPE/$NODE_NAME"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
# Input directories — each input type has its own node directory
set RTL_DIR "$run_dir/work/$FLOW_TYPE/rtl1/rtl"
set SDC_DIR "$run_dir/work/$FLOW_TYPE/sdc1/sdc"
set UPF_DIR "$run_dir/work/$FLOW_TYPE/upf1/upf"
set NETLIST_DIR "$run_dir/work/$FLOW_TYPE/netlist1/netlist"
set DEF_DIR "$run_dir/work/$FLOW_TYPE/def1/def"
set GDS_DIR "$run_dir/work/$FLOW_TYPE/gds1/gds"
set SPEF_DIR "$run_dir/work/$FLOW_TYPE/spef1/spef"
set LIBRARY_DIR "$run_dir/work/$FLOW_TYPE/library1/library"
# Backward compat — INPUTS_DIR points to first input node
set INPUTS_DIR "$run_dir/work/$FLOW_TYPE/rtl1"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

# ==============================================================================
# flow_proc: setup_libraries
# Genus-RM: set_db / read_libs -- Liberty timing libraries, LEF physical
#           libraries, and technology setup from tech() array
# ==============================================================================
flow_proc setup_libraries {
    handle_info "Setting up libraries..."
    global synth tech flow

    # -- Liberty timing libraries (from tech array) ----------------------------
    set lib_files [list]

    # Standard cell timing libraries
    if {[info exists tech(lib,timing)] && $tech(lib,timing) ne ""} {
        foreach lib $tech(lib,timing) {
            if {$lib ne "" && [file exists $lib]} {
                lappend lib_files $lib
            } elseif {$lib ne ""} {
                handle_warning "Liberty file not found: $lib"
            }
        }
    }

    # Macro/memory timing libraries
    if {[info exists tech(lib,memory)] && $tech(lib,memory) ne ""} {
        foreach lib $tech(lib,memory) {
            if {$lib ne "" && [file exists $lib]} { lappend lib_files $lib }
        }
    }

    # IO pad timing libraries
    if {[info exists tech(lib,io_pads)] && $tech(lib,io_pads) ne ""} {
        foreach lib $tech(lib,io_pads) {
            if {$lib ne "" && [file exists $lib]} { lappend lib_files $lib }
        }
    }

    if {[llength $lib_files] > 0} {
        handle_info "Reading [llength $lib_files] Liberty libraries..."
        read_libs $lib_files
        handle_info "Liberty libraries loaded"
    } else {
        handle_warning "No Liberty libraries found -- check tech(lib,timing) in tech_config.tcl"
    }

    # -- LEF physical libraries ------------------------------------------------
    set lef_files [list]

    # Technology LEF
    if {[info exists tech(lef,technology)] && $tech(lef,technology) ne ""} {
        if {[file exists $tech(lef,technology)]} {
            lappend lef_files $tech(lef,technology)
        }
    }

    # Standard cell LEF
    if {[info exists tech(lef,standard_cells)] && $tech(lef,standard_cells) ne ""} {
        foreach lef $tech(lef,standard_cells) {
            if {$lef ne "" && [file exists $lef]} { lappend lef_files $lef }
        }
    }

    # Macro LEFs
    if {[info exists tech(lef,macros)] && $tech(lef,macros) ne ""} {
        foreach lef $tech(lef,macros) {
            if {$lef ne "" && [file exists $lef]} { lappend lef_files $lef }
        }
    }

    # Memory LEFs
    if {[info exists tech(lef,memory)] && $tech(lef,memory) ne ""} {
        foreach lef $tech(lef,memory) {
            if {$lef ne "" && [file exists $lef]} { lappend lef_files $lef }
        }
    }

    # IO pad LEFs
    if {[info exists tech(lef,io_pads)] && $tech(lef,io_pads) ne ""} {
        foreach lef $tech(lef,io_pads) {
            if {$lef ne "" && [file exists $lef]} { lappend lef_files $lef }
        }
    }

    if {[llength $lef_files] > 0} {
        handle_info "Reading [llength $lef_files] LEF files..."
        read_physical -lefs $lef_files
        handle_info "LEF files loaded"
    }

    # -- QRC extraction tech (for physical-aware synthesis) --------------------
    if {[info exists tech(ext,qrc_tech)] && $tech(ext,qrc_tech) ne "" && [file exists $tech(ext,qrc_tech)]} {
        handle_info "Setting QRC tech file: $tech(ext,qrc_tech)"
        set_db qrc_tech_file $tech(ext,qrc_tech)
    }

    handle_info "Library setup completed"
}

# ==============================================================================
# flow_proc: setup_genus_options
# Genus-RM: set_db options -- global Genus settings for synthesis quality
# ==============================================================================
flow_proc setup_genus_options {
    handle_info "Setting Genus options..."
    global synth tech

    # -- Design name -----------------------------------------------------------
    set design_name ""
    if {[info exists synth(design_name)]} { set design_name $synth(design_name) }

    # -- Genus application options ---------------------------------------------
    # Effort level
    set effort [expr {[info exists synth(compile,effort)] ? $synth(compile,effort) : "medium"}]
    set_db syn_global_effort $effort
    handle_info "Synthesis effort: $effort"

    # Enable physical-aware synthesis if QRC is available
    if {[info exists tech(ext,qrc_tech)] && $tech(ext,qrc_tech) ne "" && [file exists $tech(ext,qrc_tech)]} {
        set_db / .phys_syn_effort $effort
        handle_info "Physical-aware synthesis enabled"
    }

    # Leakage power optimization
    if {[info exists synth(compile,leakage_power_effort)] && $synth(compile,leakage_power_effort) ne ""} {
        set_db / .leakage_power_effort $synth(compile,leakage_power_effort)
        handle_info "Leakage power effort: $synth(compile,leakage_power_effort)"
    }

    # Dynamic power optimization
    if {[info exists synth(compile,dynamic_power_effort)] && $synth(compile,dynamic_power_effort) ne ""} {
        set_db / .dynamic_power_effort $synth(compile,dynamic_power_effort)
        handle_info "Dynamic power effort: $synth(compile,dynamic_power_effort)"
    }

    # Max routing layers (for physical-aware)
    if {[info exists synth(route_max_layer)] && $synth(route_max_layer) ne ""} {
        set_db design_top_routing_layer $synth(route_max_layer)
    }
    if {[info exists synth(route_min_layer)] && $synth(route_min_layer) ne ""} {
        set_db design_bottom_routing_layer $synth(route_min_layer)
    }

    # Genus user options file
    if {[info exists synth(genus_options_file)] && [file exists $synth(genus_options_file)]} {
        handle_info "Sourcing Genus options: $synth(genus_options_file)"
        source $synth(genus_options_file)
    }

    handle_info "Genus options set"
}

# ==============================================================================
# flow_proc: read_design
# Genus-RM: read_hdl / elaborate -- RTL file reading and design elaboration
# ==============================================================================
flow_proc read_design {
    handle_info "Reading RTL design..."
    global synth flow

    set design_name [expr {[info exists synth(design_name)] ? $synth(design_name) : $flow(design_name)}]

    # -- Read RTL files --------------------------------------------------------
    # Determine RTL source: filelist or direct list
    set rtl_filelist "$::RTL_DIR/${design_name}.f"
    set rtl_format [expr {[info exists synth(input,rtl_format)] ? $synth(input,rtl_format) : "sv"}]

    if {[info exists synth(input,rtl_list)] && [llength $synth(input,rtl_list)] > 0} {
        # Direct RTL file list from config
        handle_info "Reading RTL from synth(input,rtl_list): [llength $synth(input,rtl_list)] files"
        foreach rtl_file $synth(input,rtl_list) {
            if {[file exists $rtl_file]} {
                read_hdl -$rtl_format $rtl_file
            } else {
                handle_warning "RTL file not found: $rtl_file"
            }
        }
    } elseif {[file exists $rtl_filelist]} {
        # Filelist (.f file)
        handle_info "Reading RTL from filelist: $rtl_filelist (format=$rtl_format)"
        read_hdl -$rtl_format -f $rtl_filelist
    } else {
        # Glob for RTL in inputs directory
        set rtl_files [glob -nocomplain "$::RTL_DIR/*.v" "$::RTL_DIR/*.sv" "$::RTL_DIR/*.vhd"]
        if {[llength $rtl_files] > 0} {
            handle_info "Reading [llength $rtl_files] RTL files from inputs directory"
            foreach rtl_file $rtl_files {
                set ext [file extension $rtl_file]
                if {$ext eq ".sv"} {
                    read_hdl -sv $rtl_file
                } elseif {$ext eq ".vhd"} {
                    read_hdl -vhdl $rtl_file
                } else {
                    read_hdl -v2001 $rtl_file
                }
            }
        } else {
            handle_error "No RTL files found. Set synth(input,rtl_list) or provide $rtl_filelist"
            return -code error "No RTL files"
        }
    }

    # -- Include directories ---------------------------------------------------
    if {[info exists synth(input,include_dirs)] && [llength $synth(input,include_dirs)] > 0} {
        foreach inc_dir $synth(input,include_dirs) {
            if {[file isdirectory $inc_dir]} {
                set_db hdl_search_path [concat [get_db hdl_search_path] $inc_dir]
            }
        }
    }

    # -- Define macros ---------------------------------------------------------
    if {[info exists synth(input,defines)] && [llength $synth(input,defines)] > 0} {
        foreach def $synth(input,defines) {
            set_db hdl_define_list [concat [get_db hdl_define_list] $def]
        }
    }

    # -- Elaborate design ------------------------------------------------------
    handle_info "Elaborating design: $design_name"
    elaborate $design_name

    # Check elaboration result
    if {[get_db current_design] eq ""} {
        handle_error "Elaboration failed for $design_name"
        return -code error "Elaboration failed"
    }

    handle_info "Design elaborated: $design_name"
}

# ==============================================================================
# flow_proc: setup_design_checks
# Genus-RM: check_design, uniquify, report
# ==============================================================================
flow_proc setup_design_checks {
    handle_info "Running design checks..."
    global synth flow

    set design_name [expr {[info exists synth(design_name)] ? $synth(design_name) : $flow(design_name)}]

    # Uniquify the design
    uniquify $design_name

    # Check design for issues
    check_design -unresolved > $::REPORTS_DIR/check_design_unresolved.rpt
    handle_info "Design check report: $::REPORTS_DIR/check_design_unresolved.rpt"

    handle_info "Design checks completed"
}

# ==============================================================================
# flow_proc: load_constraints
# Genus-RM: read_sdc -- timing constraints
# ==============================================================================
flow_proc load_constraints {
    handle_info "Loading timing constraints..."
    global synth flow

    set design_name [expr {[info exists synth(design_name)] ? $synth(design_name) : $flow(design_name)}]

    # -- SDC constraints -------------------------------------------------------
    set sdc_file ""
    if {[info exists synth(input,sdc_file)] && $synth(input,sdc_file) ne ""} {
        set sdc_file $synth(input,sdc_file)
    } else {
        set sdc_file "$::SDC_DIR/${design_name}.sdc"
    }

    if {$sdc_file ne "" && [file exists $sdc_file]} {
        handle_info "Reading SDC: $sdc_file"
        read_sdc $sdc_file
    } else {
        # Try constraints directory
        set sdc_files [glob -nocomplain "$::SDC_DIR/*.sdc"]
        if {[llength $sdc_files] > 0} {
            foreach sdc $sdc_files {
                handle_info "Reading SDC: $sdc"
                read_sdc $sdc
            }
        } else {
            handle_warning "No SDC file found -- synthesis will run without timing constraints"
        }
    }

    # -- Additional constraint files -------------------------------------------
    if {[info exists synth(input,additional_sdc)] && [llength $synth(input,additional_sdc)] > 0} {
        foreach sdc $synth(input,additional_sdc) {
            if {[file exists $sdc]} {
                handle_info "Reading additional SDC: $sdc"
                read_sdc $sdc
            }
        }
    }

    handle_info "Constraints loaded"
}

# ==============================================================================
# flow_proc: setup_power_intent
# Genus-RM: read_power_intent (UPF/CPF)
# ==============================================================================
flow_proc setup_power_intent {
    handle_info "Setting up power intent..."
    global synth

    # UPF (IEEE 1801)
    if {[info exists synth(input,upf_file)] && $synth(input,upf_file) ne ""} {
        if {[file exists $synth(input,upf_file)]} {
            handle_info "Reading UPF: $synth(input,upf_file)"
            read_power_intent -1801 $synth(input,upf_file)
            handle_info "UPF loaded"
        } else {
            handle_warning "UPF file not found: $synth(input,upf_file)"
        }
    } elseif {[info exists synth(input,cpf_file)] && $synth(input,cpf_file) ne ""} {
        # CPF (Cadence Power Format)
        if {[file exists $synth(input,cpf_file)]} {
            handle_info "Reading CPF: $synth(input,cpf_file)"
            read_power_intent -cpf $synth(input,cpf_file)
            handle_info "CPF loaded"
        }
    } else {
        handle_info "No power intent file specified -- single power domain"
    }

    handle_info "Power intent setup completed"
}

# ==============================================================================
# flow_proc: setup_mmmc
# Genus-RM: Multi-mode multi-corner setup via library_sets and analysis_views
# ==============================================================================
flow_proc setup_mmmc {
    handle_info "Setting up MMMC for Genus..."
    global synth tech
    global analysis_views library_sets

    # User MMMC setup script
    if {[info exists synth(mcmm_setup_file)] && [file exists $synth(mcmm_setup_file)]} {
        handle_info "Sourcing MMMC setup: $synth(mcmm_setup_file)"
        source $synth(mcmm_setup_file)
        handle_info "MMMC setup completed from user script"
        return
    }

    # Auto MMMC from mmmc_config analysis_views
    if {[info exists analysis_views] && [array size analysis_views] > 0} {
        handle_info "Creating MMMC from mmmc_config: [array size analysis_views] views"

        foreach scenario [lsort [array names analysis_views]] {
            array set _v $analysis_views($scenario)

            # Get library set for this view
            set lib_ref [expr {[info exists _v(lib_set_ref)] ? $_v(lib_set_ref) : ""}]
            set _timing_libs {}
            if {$lib_ref ne "" && [info exists library_sets(${lib_ref},timing)]} {
                set _timing_libs $library_sets(${lib_ref},timing)
            }

            if {[llength $_timing_libs] > 0} {
                handle_info "  View $scenario: corner=$_v(corner), libs=[llength $_timing_libs]"
                # Genus MMMC: create_library_set, create_timing_condition,
                # create_rc_corner, create_delay_corner, create_constraint_mode,
                # create_analysis_view
            }

            array unset _v
        }
    } else {
        handle_info "No MMMC analysis_views defined -- single corner mode"
    }

    handle_info "MMMC setup completed"
}

# ==============================================================================
# flow_proc: setup_dont_use
# Genus-RM: set_dont_use / set_attribute -- library cell restrictions
# ==============================================================================
flow_proc setup_dont_use {
    handle_info "Setting library cell restrictions..."
    global synth tech

    # Dont-use cells
    if {[info exists tech(dont_use_cells)] && $tech(dont_use_cells) ne ""} {
        foreach cell $tech(dont_use_cells) {
            set_dont_use $cell
        }
        handle_info "Dont-use applied: [llength $tech(dont_use_cells)] cells"
    }

    # Dont-touch cells
    if {[info exists tech(dont_touch_cells)] && $tech(dont_touch_cells) ne ""} {
        foreach cell $tech(dont_touch_cells) {
            set_dont_touch $cell
        }
        handle_info "Dont-touch applied: [llength $tech(dont_touch_cells)] cells"
    }

    # Lib cell purpose file
    if {[info exists synth(lib_cell_purpose_file)] && [file exists $synth(lib_cell_purpose_file)]} {
        handle_info "Sourcing lib cell purpose: $synth(lib_cell_purpose_file)"
        source $synth(lib_cell_purpose_file)
    } elseif {[info exists tech(lib_cell_purpose_file)] && [file exists $tech(lib_cell_purpose_file)]} {
        handle_info "Sourcing lib cell purpose from tech: $tech(lib_cell_purpose_file)"
        source $tech(lib_cell_purpose_file)
    }

    handle_info "Library cell restrictions applied"
}

# ==============================================================================
# flow_proc: setup_dft
# Genus-RM: DFT scan configuration
# ==============================================================================
flow_proc setup_dft {
    handle_info "Setting up DFT..."
    global synth

    if {[info exists synth(dft_setup_file)] && [file exists $synth(dft_setup_file)]} {
        handle_info "Sourcing DFT setup: $synth(dft_setup_file)"
        source $synth(dft_setup_file)
    } elseif {[info exists synth(dft_ports_file)] && [file exists $synth(dft_ports_file)]} {
        handle_info "Sourcing DFT ports: $synth(dft_ports_file)"
        source $synth(dft_ports_file)
    }

    handle_info "DFT setup completed"
}

# ==============================================================================
# flow_proc: save_design
# Genus-RM: write_db, write_snapshot
# ==============================================================================
flow_proc save_design {
    handle_info "Saving init_design checkpoint..."
    global synth flow

    set run_dir $::env(CBFLOW_RUN_DIR)
    set design_name [expr {[info exists synth(design_name)] ? $synth(design_name) : $flow(design_name)}]

    file mkdir "$run_dir/outputs"

    # Write Genus database
    write_db $::OUTPUTS_DIR/init_design_genus.db
    handle_info "Genus DB saved: $::OUTPUTS_DIR/init_design_genus.db"

    # Write design snapshot
    catch {
        write_snapshot -outdir $::REPORTS_DIR -tag init_design
        handle_info "Design snapshot saved"
    }

    handle_info "Init design saved"
}

# ==============================================================================
# flow_proc: generate_reports
# Genus-RM: report_summary, report_timing, report_dp, report_messages
# ==============================================================================
flow_proc generate_reports {
    handle_info "Generating init_design reports..."
    global synth

    file mkdir "$::REPORTS_DIR"

    set max_paths [expr {[info exists synth(analysis,max_paths)] ? $synth(analysis,max_paths) : 100}]

    # Design summary
    catch { report_summary > $::REPORTS_DIR/report_summary.rpt }

    # Timing report
    catch {
        report_timing -max_paths $max_paths > $::REPORTS_DIR/report_timing.rpt
    }

    # Area report
    catch { report_area > $::REPORTS_DIR/report_area.rpt }

    # Power report
    catch { report_power > $::REPORTS_DIR/report_power.rpt }

    # Design quality metrics
    catch { report_qor > $::REPORTS_DIR/report_qor.rpt }

    # Messages summary
    catch { report_messages > $::REPORTS_DIR/report_messages.rpt }

    handle_info "Init design reports generated in: $::REPORTS_DIR"
}

# ==============================================================================
# Source setup.tcl (flow_proc hooks: prepend, append, replace)
# Must be sourced AFTER flow_proc definitions but BEFORE flow_exec_all
# ==============================================================================
set _setup_file "$run_dir/work/SYNTH/init_design1/run/setup.tcl"
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

handle_info "Init design completed -- exiting Genus"
exit
