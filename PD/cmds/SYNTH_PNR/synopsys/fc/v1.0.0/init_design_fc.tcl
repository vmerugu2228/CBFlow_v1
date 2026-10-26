#!/usr/bin/env tclsh
# CBFlow SYNTH_PNR init_design - Synopsys Fusion Compiler
# FC-RM: init_design.tcl -- Design library creation, technology setup,
#         constraints, MCMM, OCV, power, and QoR strategy
# Aligned with FC-RM Y-2026.03

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "SYNTH_PNR"
set STAGE_NAME "init_design"
set NODE_NAME "init_design1"

# ── Config (full cascade: project → tech → flow → node → mmmc → tool → user) ─
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"

# ── Directories ──────────────────────────────────────────────────────────────
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# ── Design name (single source of truth) ─────────────────────────────────────
set ::design_name [expr {$synth_pnr(common,design_name) ne "" ? $synth_pnr(common,design_name) : $flow(design_name)}]

# ==============================================================================
# flow_proc: create_design_library
# FC-RM: create_lib with technology file, NDM reference libraries, and
#         optional on-the-fly fusion library creation from LEF+DB
# All library/technology info comes from tech() array (tech_config.tcl)
# ==============================================================================
flow_proc create_design_library {
    handle_info "Creating design library..."
    global flow project synth_pnr tech

    set run_dir $::env(CBFLOW_RUN_DIR)
    file mkdir "$run_dir/work/SYNTH_PNR/init_design1/run"

    # BUG FIX #6 (init): Use .nlib extension (not _lib) — FC uses .nlib format
    set lib_name "${::design_name}.nlib"

    # BUG FIX #4: Remove .nlib safely — handle .nfs lock files from NFS
    if {[file exists $lib_name]} {
        handle_info "Removing existing library: $lib_name"
        # Kill any .nfs lock files first (NFS stale handles)
        catch {
            foreach nfs_file [glob -nocomplain ${lib_name}/.nfs*] {
                catch { file delete -force $nfs_file }
            }
        }
        if {[catch {file delete -force $lib_name} err]} {
            handle_warning "Could not delete $lib_name: $err"
            handle_warning "Trying rename workaround..."
            set backup_name "${lib_name}.bak.[clock seconds]"
            catch { file rename -force $lib_name $backup_name }
        }
    }

    # ── Build reference library list (track-aware) ─────────────────────────────
    # Reads tech($track,ndm) list from tech_config — contains ALL Vt + memory + IO
    set ref_libs [list]
    set _trk $tech(track)

    # Priority 1: Track-categorized NDM list (new format)
    if {$_trk ne "" && $tech(${_trk},ndm) ne ""} {
        set ref_libs $tech(${_trk},ndm)
        handle_info "NDM libraries from track ${_trk}: [llength $ref_libs] libs"
    }

    # Priority 2: Backward compat — old single-file format
    if {[llength $ref_libs] == 0} {
        if {[info exists tech(ndm,standard_cells)] && $tech(ndm,standard_cells) ne ""} {
            lappend ref_libs $tech(ndm,standard_cells)
        }
        if {[info exists tech(ndm,memory)] && $tech(ndm,memory) ne ""} {
            lappend ref_libs $tech(ndm,memory)
        }
        if {[info exists tech(ndm,io_pads)] && $tech(ndm,io_pads) ne ""} {
            lappend ref_libs $tech(ndm,io_pads)
        }
    }

    # Sub-block NDMs — hierarchical designs (validated from project config)
    if {$flow(run_type) eq "hier" && [info exists project(block_list)] && [llength $project(block_list)] > 0} {
        foreach _block $project(block_list) {
            if {![info exists project(${_block},ndm)] || $project(${_block},ndm) eq ""} {
                handle_error "Missing NDM for sub-block '$_block'. Set project(${_block},ndm) in project_config."
                return
            }
            lappend ref_libs $project(${_block},ndm)
        }
        handle_info "Hierarchical: [llength $project(block_list)] sub-block NDMs added"
    }

    # ── On-the-fly fusion library creation (LEF + DB — when no NDM available) ─
    set fusion_lef_list [list]
    set fusion_db_list [list]

    if {[llength $ref_libs] == 0} {
        handle_info "No NDM libraries — creating fusion libs from LEF+DB..."

        # Track-categorized LEF list
        if {$_trk ne "" && $tech(${_trk},lef) ne ""} {
            set fusion_lef_list $tech(${_trk},lef)
        } else {
            if {[info exists tech(lef,standard_cells)] && $tech(lef,standard_cells) ne ""} { lappend fusion_lef_list $tech(lef,standard_cells) }
            if {[info exists tech(lef,macros)] && $tech(lef,macros) ne ""}         { lappend fusion_lef_list $tech(lef,macros) }
            if {[info exists tech(lef,io_pads)] && $tech(lef,io_pads) ne ""}        { lappend fusion_lef_list $tech(lef,io_pads) }
        }

        # Track-categorized DB list
        if {$_trk ne "" && $tech(${_trk},db) ne ""} {
            set fusion_db_list $tech(${_trk},db)
        } else {
            if {[info exists tech(db,standard_cells)] && $tech(db,standard_cells) ne ""}  { lappend fusion_db_list $tech(db,standard_cells) }
            if {[info exists tech(db,memory)] && $tech(db,memory) ne ""}          { lappend fusion_db_list $tech(db,memory) }
            if {[info exists tech(db,io_pads)] && $tech(db,io_pads) ne ""}         { lappend fusion_db_list $tech(db,io_pads) }
        }

        if {[llength $fusion_lef_list] > 0 && [llength $fusion_db_list] > 0} {
            handle_info "Creating fusion reference libraries from LEF+DB..."
            set fusion_dir "$run_dir/work/SYNTH_PNR/init_design1/fusion_libs"
            file mkdir $fusion_dir
            create_fusion_reference_library \
                -output_directory $fusion_dir \
                -lef_files $fusion_lef_list \
                -db_files $fusion_db_list
            foreach lib [glob -nocomplain -type d ${fusion_dir}/*] {
                lappend ref_libs $lib
            }
            handle_info "Fusion reference libraries created"
        } elseif {[llength $fusion_lef_list] > 0} {
            handle_warning "LEF files found but no timing DB — set tech(db,*) in tech_config.tcl"
            set ref_libs $fusion_lef_list
        }
    }

    # ── Technology file (from tech array) ─────────────────────────────────────
    set tech_file [expr {[info exists tech($project(metal_stack),$tech(track),tech_file)] ? $tech($project(metal_stack),$tech(track),tech_file) : ""}]
    set tech_lib  [expr {[info exists tech(ndm,tech_lib)] ? $tech(ndm,tech_lib) : ""}]

    # Parasitic tech library
    set parasitic_tech_lib [expr {[info exists tech(ndm,parasitic_tech)] ? $tech(ndm,parasitic_tech) : ""}]

    # ── Build and execute create_lib command ──────────────────────────────────
    set create_lib_cmd "create_lib $lib_name"
    if {$tech_file ne "" && [file exists $tech_file]} {
        lappend create_lib_cmd -tech $tech_file
    } elseif {$tech_lib ne ""} {
        lappend create_lib_cmd -use_technology_lib $tech_lib
    }
    if {[info exists tech(design_lib_scale_factor)] && $tech(design_lib_scale_factor) ne ""} {
        lappend create_lib_cmd -scale_factor $tech(design_lib_scale_factor)
    }
    if {$parasitic_tech_lib ne ""} {
        lappend create_lib_cmd -use_parasitic_tech_lib $parasitic_tech_lib
    }
    # BUG FIX #1 (init): Avoid double {{braces}} — expand list properly
    if {[llength $ref_libs] > 0} {
        lappend create_lib_cmd -ref_libs
        foreach _rl $ref_libs { lappend create_lib_cmd $_rl }
    }

    handle_info "create_lib: $create_lib_cmd"
    eval $create_lib_cmd

    # Set link_library for timing
    if {[llength $fusion_db_list] > 0} {
        set_app_var link_library $fusion_db_list
        handle_info "link_library set with [llength $fusion_db_list] DB files"
    }

    redirect -file $::REPORTS_DIR/report_ref_libs { report_ref_libs }
    handle_info "Design library created: $lib_name"
}

# ==============================================================================
# flow_proc: read_design
# FC-RM: read_verilog (netlist or RTL), current_block, link_block,
#         set_early_data_check_policy
# ==============================================================================
flow_proc read_design {
    handle_info "Reading design..."
    global flow synth_pnr tech

    # FC-RM: set_svf for formality
    set_svf $::OUTPUTS_DIR/init_design.svf

    # BUG FIX #2 (init): RTL read aligned with FC-RM — use read_verilog/read_sverilog per RM
    set rtl_filelist "$::RTL_DIR/${::design_name}.f"
    set rtl_format [expr {$synth_pnr(input,rtl_format) ne "" ? $synth_pnr(input,rtl_format) : "sverilog"}]

    handle_info "Reading RTL: $rtl_filelist (format=$rtl_format)"
    if {$rtl_format eq "sverilog"} {
        read_sverilog -f $rtl_filelist
    } elseif {$rtl_format eq "verilog"} {
        read_verilog -f $rtl_filelist
    } elseif {$rtl_format eq "vhdl"} {
        read_vhdl -f $rtl_filelist
    } else {
        # Fallback to analyze for other formats
        analyze -format $rtl_format -f $rtl_filelist
    }
    elaborate $::design_name

    current_block $::design_name
    link_block

    # FC-RM: set_early_data_check_policy
    if {$synth_pnr(common,compile,qor_mode) eq "early_design"} {
        set_early_data_check_policy -policy lenient -if_not_exist
    }

    save_lib
    handle_info "Design read and linked: $::design_name"
}

# ==============================================================================
# flow_proc: setup_technology
# FC-RM: set_technology -node, tech setup script, read_physical_rules
# ==============================================================================
flow_proc setup_technology {
    handle_info "Setting up technology..."
    global synth_pnr tech

    # FC-RM: set_technology -node
    if {[info exists tech(node)] && $tech(node) ne ""} {
        redirect -file $::REPORTS_DIR/set_technology { set_technology -node $tech(node) -report_only }
        set_technology -node $tech(node)
        handle_info "Technology node set: $tech(node)"
    }

    # FC-RM: Technology setup (routing direction, offset, site default, site symmetry)
    # Script lives alongside tech_config.tcl in config/tech/<tech_name>/<version>/
    if {[info exists tech(tech_setup_script)] && $tech(tech_setup_script) ne "" && [file exists $tech(tech_setup_script)]} {
        handle_info "Sourcing tech setup: $tech(tech_setup_script)"
        source $tech(tech_setup_script)
    }

    # FC-RM: read_physical_rules
    if {[info exists tech(physical_rules_file)] && $tech(physical_rules_file) ne "" && [file exists $tech(physical_rules_file)]} {
        handle_info "Reading physical rules: $tech(physical_rules_file)"
        read_physical_rules $tech(physical_rules_file)
    }

    save_lib -all
    handle_info "Technology setup completed"
}

# ==============================================================================
# flow_proc: load_floorplan
# FC-RM: read_def / source floorplan TCL, resolve_pg_nets,
#         associate_mv_cell, read scan DEF
# ==============================================================================
flow_proc load_floorplan {
    handle_info "Loading floorplan..."
    global synth_pnr tech

    # FC-RM: TCL_FLOORPLAN_FILE or DEF_FLOORPLAN_FILES
    if {[info exists synth_pnr(input,fp_tcl)] && $synth_pnr(input,fp_tcl) ne "" && [file exists $synth_pnr(input,fp_tcl)]} {
        handle_info "Sourcing floorplan TCL: $synth_pnr(input,fp_tcl)"
        source $synth_pnr(input,fp_tcl)
    } elseif {[info exists synth_pnr(input,def_file)] && $synth_pnr(input,def_file) ne ""} {
        if {[file exists $synth_pnr(input,def_file)]} {
            handle_info "Reading DEF floorplan: $synth_pnr(input,def_file)"
            read_def $synth_pnr(input,def_file)
        } else {
            handle_warning "DEF file not found: $synth_pnr(input,def_file)"
        }
    } else {
        handle_info "No floorplan specified — will use inline floorplan from compile"
    }

    # FC-RM: resolve_pg_nets after DEF
    if {[info exists synth_pnr(input,upf_file)] && $synth_pnr(input,upf_file) ne ""} {
        catch {resolve_pg_nets}
    }

    # FC-RM: Source switch connectivity and associate MV cells
    if {[info exists synth_pnr(common,switch_connectivity_file)] && $synth_pnr(common,switch_connectivity_file) ne "" && [file exists $synth_pnr(common,switch_connectivity_file)]} {
        source $synth_pnr(common,switch_connectivity_file)
        associate_mv_cell -power_switches
    }

    # FC-RM: SCANDEF
    if {[info exists synth_pnr(input,scan_def)] && $synth_pnr(input,scan_def) ne ""} {
        if {[file exists $synth_pnr(input,scan_def)]} {
            handle_info "Reading scan DEF: $synth_pnr(input,scan_def)"
            read_def $synth_pnr(input,scan_def)
        }
    }

    # BUG FIX #9 (init): Create site rows if not present after floorplan load
    set _trk $tech(track)
    if {[sizeof_collection [get_site_rows -quiet]] == 0} {
        handle_info "No site rows found — creating default site rows..."
        if {$_trk ne "" && $tech(${_trk},site) ne ""} {
            create_site_rows -site $tech(${_trk},site)
            handle_info "  Site rows created with site: $tech(${_trk},site)"
        } else {
            create_site_rows
            handle_info "  Site rows created with default site"
        }
    } else {
        handle_info "Site rows already present: [sizeof_collection [get_site_rows]]"
    }

    handle_info "Floorplan loaded"
}

# ==============================================================================
# flow_proc: initialize_floorplan
# FC-RM: initialize_floorplan if no DEF/TCL provided (auto floorplan)
# For unified synth+PNR flow — creates default floorplan from utilization
# ==============================================================================
flow_proc initialize_floorplan {
    handle_info "Initializing floorplan (FC-RM)..."
    global synth_pnr tech

    # Skip if floorplan was already loaded from DEF or TCL
    if {[sizeof_collection [get_cells -hier -filter "is_hard_macro==true" -quiet]] > 0 ||
        [sizeof_collection [get_site_rows -quiet]] > 0} {
        handle_info "Floorplan already present — skipping auto-initialize"
        return
    }

    # FC-RM: initialize_floorplan with utilization target
    set util [expr {$synth_pnr(fp,core_utilization) ne "" ? $synth_pnr(fp,core_utilization) : 0.70}]
    set ratio [expr {$synth_pnr(fp,aspect_ratio) ne "" ? $synth_pnr(fp,aspect_ratio) : 1.0}]
    set offset [expr {$synth_pnr(fp,core_offset) ne "" ? $synth_pnr(fp,core_offset) : "5 5 5 5"}]

    handle_info "  Utilization: $util, Aspect ratio: $ratio"
    initialize_floorplan -core_utilization $util \
        -core_aspect_ratio $ratio \
        -core_offset $offset

    # Create site rows if not present
    set _trk $tech(track)
    if {[sizeof_collection [get_site_rows -quiet]] == 0} {
        if {$_trk ne "" && $tech(${_trk},site) ne ""} {
            create_site_rows -site $tech(${_trk},site)
        } else {
            create_site_rows
        }
        handle_info "  Site rows created"
    }

    handle_info "Floorplan initialized"
}

# ==============================================================================
# flow_proc: insert_physical_cells
# FC-RM: Tap cells, boundary cells, endcap cells — required before placement
# Critical for unified synth+PNR flow where FC does direct synthesis+placement
# ==============================================================================
flow_proc insert_physical_cells {
    handle_info "Inserting physical cells (FC-RM)..."
    global synth_pnr tech

    set _trk $tech(track)

    # ── FC-RM: Tap cells (well tie) ──────────────────────────────────────────
    set _tap_var ""
    if {$_trk ne "" && [info exists tech(${_trk},well_tap)] && $tech(${_trk},well_tap) ne ""} {
        set _tap_var $tech(${_trk},well_tap)
    } elseif {[info exists tech($tech(track),well_tap)] && $tech($tech(track),well_tap) ne ""} {
        set _tap_var $tech($tech(track),well_tap)
    }

    if {$_tap_var ne ""} {
        set tap_cells [lindex $_tap_var 0]
        set tap_dist [expr {$synth_pnr(init_design,fp_tap_cell_distance) ne "" ? $synth_pnr(init_design,fp_tap_cell_distance) : 30}]

        handle_info "  Inserting tap cells: $tap_cells (every ${tap_dist}um)"
        create_tap_cells -lib_cell $tap_cells \
            -distance $tap_dist \
            -pattern stagger
        handle_info "  Tap cells inserted: [sizeof_collection [get_cells -hier -filter ref_name==$tap_cells -quiet]]"
    } else {
        handle_warning "  No tap cells defined in tech(\$track,well_tap)"
    }

    # ── FC-RM: Boundary cells ────────────────────────────────────────────────
    set _endcap_var ""
    if {$_trk ne "" && [info exists tech(${_trk},endcap)] && $tech(${_trk},endcap) ne ""} {
        set _endcap_var $tech(${_trk},endcap)
    } elseif {[info exists tech($tech(track),endcap)] && $tech($tech(track),endcap) ne ""} {
        set _endcap_var $tech($tech(track),endcap)
    }

    if {$_endcap_var ne ""} {
        set endcap_cell $_endcap_var

        handle_info "  Inserting boundary/endcap cells: $endcap_cell"
        set_boundary_cell_rules -left_boundary_cell $endcap_cell \
            -right_boundary_cell $endcap_cell
        compile_boundary_cells
        handle_info "  Boundary cells inserted"
    } else {
        handle_info "  No endcap cells defined — skipping boundary cells"
    }

    # ── FC-RM: Power switch cells (for UPF flows) ────────────────────────────
    if {[info exists synth_pnr(input,upf_file)] && $synth_pnr(input,upf_file) ne ""} {
        catch {
            associate_mv_cell -power_switches
            handle_info "  Power switch cells associated"
        }
    }

    # ── FC-RM: Spare cells (optional) ────────────────────────────────────────
    if {[info exists synth_pnr(common,spare_cells_file)] && $synth_pnr(common,spare_cells_file) ne "" && [file exists $synth_pnr(common,spare_cells_file)]} {
        handle_info "  Sourcing spare cells: $synth_pnr(common,spare_cells_file)"
        source $synth_pnr(common,spare_cells_file)
    }

    save_lib -all
    handle_info "Physical cells inserted"
}

# ==============================================================================
# flow_proc: setup_design_checks
# FC-RM: uniquify, check_design, report_design_mismatch, report_unbound,
#         check_duplicates -remove
# ==============================================================================
flow_proc setup_design_checks {
    handle_info "Running design checks..."
    global flow synth_pnr tech

    # FC-RM: Uniquify design
    set_app_option -name design.uniquify_naming_style -value ${::design_name}_%s_%d
    uniquify

    # FC-RM: Design mismatch checks
    redirect -file $::REPORTS_DIR/check_design.design_mismatch {
        check_design -checks design_mismatch
    }
    redirect -file $::REPORTS_DIR/report_design_mismatch { report_design_mismatch -verbose }
    redirect -file $::REPORTS_DIR/report_unbound { report_unbound }

    # FC-RM: Remove duplicate shapes
    check_duplicates -remove

    handle_info "Design checks completed"
}

# ==============================================================================
# flow_proc: setup_mcmm
# FC-RM: UPF load, MCMM scenario creation — modes, corners, scenarios,
#         parasitic tech per corner, propagated clock removal
# Replaces old separate load_constraints + setup_parasitics + setup_mcmm
# ==============================================================================
flow_proc setup_mcmm {
    handle_info "Setting up UPF + MCMM scenarios..."
    global synth_pnr tech

    set run_dir $::env(CBFLOW_RUN_DIR)

    # ── Step 1: Load UPF (before MCMM) ──────────────────────────────────────
    if {[info exists synth_pnr(common,upf_mode)] && $synth_pnr(common,upf_mode) ne "" && $synth_pnr(common,upf_mode) eq "golden"} {
        set_app_options -name mv.upf.enable_golden_upf -value true
    }
    set upf_file "$::UPF_DIR/${::design_name}.upf"
    load_upf $upf_file
    if {[info exists synth_pnr(input,upf_supplemental)] && [file exists $synth_pnr(input,upf_supplemental)]} {
        load_upf -supplemental $synth_pnr(input,upf_supplemental)
    }
    commit_upf

    # ── Step 2: Create modes (from operating_modes — SDC per mode) ───────────
    global operating_modes
    foreach _mode [array names operating_modes] {
        set _sdc [dict get $operating_modes($_mode) constraint_file]
        set _sdc_path "$::SDC_DIR/$_sdc"
        create_mode $_mode
        current_mode $_mode
        read_sdc $_sdc_path
        handle_info "  Mode: $_mode (SDC: $_sdc)"
    }

    # ── Step 3: Create corners (from analysis_views — timing libs + parasitics)
    global analysis_views
    set _trk [expr {[info exists tech(track)] ? $tech(track) : ""}]
    set _corners_created {}
    foreach scenario [array names analysis_views] {
        array set _v $analysis_views($scenario)
        set _corner_name "${_v(corner)}_${_v(lib_set_ref)}"
        if {$_corner_name ni $_corners_created} {
            # Timing libs from tech_config — skip corner if not defined for this track.
            set _lib_key "${_trk},lib,${_v(lib_set_ref)},timing"
            if {![info exists tech($_lib_key)]} {
                handle_warning "Skipping corner ${_corner_name}: tech($_lib_key) not defined"
                continue
            }
            set _timing_libs $tech($_lib_key)

            # RC parasitic from tech_config
            set _rc $_v(rc_corner)
            set _tlu [expr {[info exists tech(rcx,${_rc},tluplus)] ? $tech(rcx,${_rc},tluplus) : ""}]

            create_corner $_corner_name
            set_parasitic_parameters -corner $_corner_name \
                -library_cell_late_spec $_timing_libs \
                -library_cell_early_spec $_timing_libs

            # Read parasitic tech for this corner
            if {$_tlu ne ""} {
                read_parasitic_tech -tlup $_tlu -layermap $tech($project(metal_stack),tluplus_map) -name $_corner_name
            }

            lappend _corners_created $_corner_name
            handle_info "  Corner: $_corner_name (libs: [llength $_timing_libs], rc: $_rc)"
        }
        array unset _v
    }

    # ── Step 4: Create scenarios (mode x corner from analysis_views) ─────────
    foreach scenario [array names analysis_views] {
        array set _v $analysis_views($scenario)
        set _corner_name "${_v(corner)}_${_v(lib_set_ref)}"
        create_scenario -name $scenario -mode $_v(mode) -corner $_corner_name
        # Set scenario setup/hold based on analysis_type
        switch $_v(analysis_type) {
            "setup"      { set_scenario_status $scenario -setup true -hold false }
            "hold"       { set_scenario_status $scenario -setup false -hold true }
            "setup_hold" { set_scenario_status $scenario -setup true -hold true }
        }
        array unset _v
    }
    handle_info "MCMM: [llength $_corners_created] corners, [array size analysis_views] scenarios"

    # Activate scenarios for this stage from mmmc node assignments
    set _node_scenarios [get_node_scenarios $::STAGE_NAME "all"]
    if {[llength $_node_scenarios] > 0} {
        set_scenario_status -active false [get_scenarios -filter active]
        set_scenario_status -active true $_node_scenarios
        handle_info "Active scenarios for $::STAGE_NAME: $_node_scenarios"
    }

    # FC-RM: Design constraints (dont_touch, clock_gating, etc.)
    if {[info exists synth_pnr(common,constraints_setup_file)] && $synth_pnr(common,constraints_setup_file) ne "" && [file exists $synth_pnr(common,constraints_setup_file)]} {
        handle_info "Sourcing constraints setup: $synth_pnr(common,constraints_setup_file)"
        source $synth_pnr(common,constraints_setup_file)
    }

    # ── Step 5: Remove propagated clocks (FC-RM requirement for ASCII input) ─
    set cur_mode [current_mode]
    foreach_in_collection mode [all_modes] {
        current_mode $mode
        catch { remove_propagated_clocks [all_clocks] }
        catch { remove_propagated_clocks [get_ports] }
        catch { remove_propagated_clocks [get_pins -hierarchical] }
    }
    current_mode $cur_mode

    handle_info "MCMM setup completed"
}

# ==============================================================================
# flow_proc: setup_timing_variations
# FC-RM: POCV / AOCV setup for on-chip variation analysis
# ==============================================================================
flow_proc setup_timing_variations {
    handle_info "Setting up timing variation analysis..."
    global synth_pnr tech

    # FC-RM: POCV setup (preferred over AOCV)
    if {[info exists synth_pnr(common,pocv_setup_file)] && $synth_pnr(common,pocv_setup_file) ne "" && [file exists $synth_pnr(common,pocv_setup_file)]} {
        handle_info "Sourcing POCV setup: $synth_pnr(common,pocv_setup_file)"
        source $synth_pnr(common,pocv_setup_file)
        set_app_options -name time.pocvm_enable_analysis -value true
        reset_app_options time.aocvm_enable_analysis
        handle_info "POCV analysis enabled"
    } elseif {[info exists synth_pnr(common,aocv_setup_file)] && $synth_pnr(common,aocv_setup_file) ne "" && [file exists $synth_pnr(common,aocv_setup_file)]} {
        # FC-RM: AOCV setup (mutually exclusive with POCV)
        handle_info "Sourcing AOCV setup: $synth_pnr(common,aocv_setup_file)"
        source $synth_pnr(common,aocv_setup_file)
        handle_info "AOCV analysis enabled"
    } elseif {[info exists tech(ocv,derate_file)] && $tech(ocv,derate_file) ne "" && [file exists $tech(ocv,derate_file)]} {
        handle_info "Sourcing OCV derate: $tech(ocv,derate_file)"
        source $tech(ocv,derate_file)
    }

    handle_info "Timing variation setup completed"
}

# ==============================================================================
# flow_proc: setup_lib_cell_purpose
# FC-RM: set_lib_cell_purpose — dont_use, tie cells, hold, CTS restrictions
# ==============================================================================
flow_proc setup_lib_cell_purpose {
    handle_info "Setting library cell purpose restrictions..."
    global synth_pnr tech
    apply_vt_dont_use

    set _trk $tech(track)

    # FC-RM: Source lib cell purpose file
    if {[info exists synth_pnr(common,lib_cell_purpose_file)] && $synth_pnr(common,lib_cell_purpose_file) ne "" && [file exists $synth_pnr(common,lib_cell_purpose_file)]} {
        handle_info "Sourcing lib cell purpose: $synth_pnr(common,lib_cell_purpose_file)"
        source $synth_pnr(common,lib_cell_purpose_file)
    } elseif {[info exists tech(lib_cell_purpose_file)] && $tech(lib_cell_purpose_file) ne "" && [file exists $tech(lib_cell_purpose_file)]} {
        handle_info "Sourcing lib cell purpose from tech: $tech(lib_cell_purpose_file)"
        source $tech(lib_cell_purpose_file)
    }

    # FC-RM: Dont-use cells (track-specific)
    set _dont_use ""
    if {$_trk ne "" && [info exists tech(${_trk},dont_use)] && $tech(${_trk},dont_use) ne ""} {
        set _dont_use $tech(${_trk},dont_use)
    } elseif {[info exists tech(dont_use_cells)] && $tech(dont_use_cells) ne ""} {
        set _dont_use $tech(dont_use_cells)
    }

    if {$_dont_use ne ""} {
        foreach cell $_dont_use {
            set_lib_cell_purpose -exclude optimization [get_lib_cells $cell]
        }
        handle_info "Dont-use cells applied: [llength $_dont_use] cells"
    }

    handle_info "Library cell restrictions applied"
}

# ==============================================================================
# flow_proc: setup_clock_ndr
# FC-RM: Clock NDR rules, routing rules for CTS
# ==============================================================================
flow_proc setup_clock_ndr {
    handle_info "Setting up clock NDR rules..."
    global synth_pnr tech

    # FC-RM: Source CTS NDR rule file
    if {[info exists synth_pnr(cts,cts_ndr_file)] && $synth_pnr(cts,cts_ndr_file) ne "" && [file exists $synth_pnr(cts,cts_ndr_file)]} {
        handle_info "Sourcing CTS NDR rules: $synth_pnr(cts,cts_ndr_file)"
        source $synth_pnr(cts,cts_ndr_file)
    } elseif {[info exists tech(cts_ndr_file)] && $tech(cts_ndr_file) ne "" && [file exists $tech(cts_ndr_file)]} {
        source $tech(cts_ndr_file)
    }

    # FC-RM: Via ladder definitions
    if {[info exists tech(via_ladder_file)] && $tech(via_ladder_file) ne "" && [file exists $tech(via_ladder_file)]} {
        handle_info "Sourcing via ladder definitions"
        source $tech(via_ladder_file)
    }

    redirect -file $::REPORTS_DIR/report_routing_rules { report_routing_rules -verbose }
    redirect -file $::REPORTS_DIR/report_clock_routing_rules { report_clock_routing_rules }
    redirect -file $::REPORTS_DIR/report_clock_settings { report_clock_settings }

    handle_info "Clock NDR setup completed"
}

# ==============================================================================
# flow_proc: setup_placement_constraints
# FC-RM: Placement spacing labels, spacing rules, abutment rules
# ==============================================================================
flow_proc setup_placement_constraints {
    handle_info "Setting up placement constraints..."
    global synth_pnr

    # FC-RM: Source placement constraint files
    if {[info exists synth_pnr(place,placement_constraint_files)] && $synth_pnr(place,placement_constraint_files) ne "" && [llength $synth_pnr(place,placement_constraint_files)] > 0} {
        foreach file $synth_pnr(place,placement_constraint_files) {
            if {[file exists $file]} {
                handle_info "Sourcing placement constraint: $file"
                source $file
            }
        }
    }

    # FC-RM: Additional floorplan constraints
    if {[info exists synth_pnr(common,additional_floorplan_file)] && $synth_pnr(common,additional_floorplan_file) ne "" && [file exists $synth_pnr(common,additional_floorplan_file)]} {
        source $synth_pnr(common,additional_floorplan_file)
    }

    handle_info "Placement constraints applied"
}

# ==============================================================================
# flow_proc: setup_power_activity
# FC-RM: read_saif, switching activity, infer_switching_activity
# ==============================================================================
flow_proc setup_power_activity {
    handle_info "Setting up power activity..."
    global synth_pnr

    # FC-RM: saif_map -start
    saif_map -start

    # FC-RM: read_saif
    if {[info exists synth_pnr(common,saif_file)] && $synth_pnr(common,saif_file) ne ""} {
        if {[file exists $synth_pnr(common,saif_file)]} {
            set read_saif_cmd "read_saif $synth_pnr(common,saif_file)"
            if {[info exists synth_pnr(common,saif_power_scenario)] && $synth_pnr(common,saif_power_scenario) ne ""} {
                lappend read_saif_cmd -scenarios $synth_pnr(common,saif_power_scenario)
            }
            if {[info exists synth_pnr(common,saif_source_instance)] && $synth_pnr(common,saif_source_instance) ne ""} {
                lappend read_saif_cmd -strip_path $synth_pnr(common,saif_source_instance)
            }
            if {[info exists synth_pnr(common,saif_target_instance)] && $synth_pnr(common,saif_target_instance) ne ""} {
                lappend read_saif_cmd -path $synth_pnr(common,saif_target_instance)
            }
            handle_info "Reading SAIF: $read_saif_cmd"
            eval $read_saif_cmd
        }
    }

    # FC-RM: Infer switching activity if total_power metric and no simulated activity
    set qor_metric [expr {$synth_pnr(common,compile,qor_metric) ne "" ? $synth_pnr(common,compile,qor_metric) : "timing"}]
    if {$qor_metric eq "total_power"} {
        catch {
            foreach sce [get_object_name [get_scenarios -filter "dynamic_power"]] {
                infer_switching_activity -apply -sci_based all -scenario $sce
            }
        }
        handle_info "Switching activity inferred for total_power metric"
    }

    handle_info "Power activity setup completed"
}

# ==============================================================================
# flow_proc: setup_dft
# FC-RM: DFT ports setup
# ==============================================================================
flow_proc setup_dft {
    handle_info "Setting up DFT..."
    global synth_pnr

    # FC-RM: DFT ports file
    if {[info exists synth_pnr(synthesis,dft_ports_file)] && $synth_pnr(synthesis,dft_ports_file) ne "" && [file exists $synth_pnr(synthesis,dft_ports_file)]} {
        handle_info "Sourcing DFT ports: $synth_pnr(synthesis,dft_ports_file)"
        source $synth_pnr(synthesis,dft_ports_file)
    }

    handle_info "DFT setup completed"
}

# ==============================================================================
# flow_proc: connect_power_ground
# FC-RM: connect_pg_net
# ==============================================================================
flow_proc connect_power_ground {
    handle_info "Connecting power/ground nets..."
    global synth_pnr

    # FC-RM: User PG connection script or automatic
    if {[info exists synth_pnr(common,connect_pg_net_script)] && $synth_pnr(common,connect_pg_net_script) ne "" && [file exists $synth_pnr(common,connect_pg_net_script)]} {
        source $synth_pnr(common,connect_pg_net_script)
    } else {
        connect_pg_net
    }

    handle_info "PG nets connected"
}

# ==============================================================================
# flow_proc: set_qor_strategy_init
# FC-RM: set_qor_strategy for initial design setup
# ==============================================================================
flow_proc set_qor_strategy_init {
    handle_info "Setting QoR strategy..."
    global synth_pnr

    set metric [expr {$synth_pnr(common,compile,qor_metric) ne "" ? $synth_pnr(common,compile,qor_metric) : "timing"}]
    set mode [expr {$synth_pnr(common,compile,qor_mode) ne "" ? $synth_pnr(common,compile,qor_mode) : "balanced"}]

    set_qor_strategy -stage pnr -metric $metric -mode $mode

    handle_info "QoR strategy: metric=$metric, mode=$mode"
}

# ==============================================================================
# flow_proc: run_floorplan_checks
# FC-RM: check_floorplan_rules, rm_check_design
# ==============================================================================
flow_proc run_floorplan_checks {
    handle_info "Running floorplan checks..."
    global synth_pnr

    # FC-RM: check_floorplan_rules
    catch {
        redirect -file $::REPORTS_DIR/check_floorplan_rules.rpt { check_floorplan_rules }
    }

    # FC-RM: Floorplan rule script
    if {[info exists synth_pnr(common,floorplan_rule_script)] && $synth_pnr(common,floorplan_rule_script) ne "" && [file exists $synth_pnr(common,floorplan_rule_script)]} {
        source $synth_pnr(common,floorplan_rule_script)
    }

    handle_info "Floorplan checks completed"
}

# ==============================================================================
# flow_proc: save_design
# FC-RM: save_upf, save_lib, save_block -as, set_svf -off
# ==============================================================================
flow_proc save_design {
    handle_info "Saving init_design block..."
    global synth_pnr flow

    set run_dir $::env(CBFLOW_RUN_DIR)

    # FC-RM: save_upf
    set upf_mode [expr {$synth_pnr(common,upf_mode) ne "" ? $synth_pnr(common,upf_mode) : "none"}]
    file mkdir "$run_dir/outputs"
    if {$upf_mode eq "golden"} {
        save_upf ${run_dir}/outputs/init_design.supplemental.upf
    } elseif {[info exists synth_pnr(input,upf_file)] && $synth_pnr(input,upf_file) ne ""} {
        save_upf ${run_dir}/outputs/init_design.save_upf
    }

    # FC-RM: save_lib -all, save_block
    save_lib -all
    save_block
    if {[info exists synth_pnr(common,output,block_labeling)] && $synth_pnr(common,output,block_labeling) ne "" && $synth_pnr(common,output,block_labeling)} {
        save_block -as ${::design_name}/init_design
        handle_info "Block saved: ${::design_name}/init_design"
        cbflow_record_block_state $::STAGE_NAME "init_design" $::NODE_NAME
    }

    # FC-RM: Close SVF
    set_svf -off

    handle_info "Init design saved"
}

# ==============================================================================
# flow_proc: generate_reports
# FC-RM: report_qor, report_timing, report_design, write_tech_file,
#         write_qor_data, report_msg, run_end
# ==============================================================================
flow_proc generate_reports {
    handle_info "Generating init_design reports..."
    global synth_pnr

    set run_dir $::env(CBFLOW_RUN_DIR)
    file mkdir "$::REPORTS_DIR"

    set max_paths [expr {$synth_pnr(common,analysis,max_paths) ne "" ? $synth_pnr(common,analysis,max_paths) : 100}]

    # FC-RM: Core reports
    redirect -file $::REPORTS_DIR/report_qor.rpt { report_qor }
    redirect -file $::REPORTS_DIR/report_timing.max.rpt {
        report_timing -max_paths $max_paths -delay_type max
    }
    redirect -file $::REPORTS_DIR/report_timing.min.rpt {
        report_timing -max_paths $max_paths -delay_type min
    }
    redirect -file $::REPORTS_DIR/report_design.rpt { report_design -physical }
    redirect -file $::REPORTS_DIR/report_utilization.rpt { report_utilization }
    redirect -file $::REPORTS_DIR/report_clocks.rpt { report_clocks }

    # FC-RM: check_timing (constraint completeness)
    redirect -file $::REPORTS_DIR/check_timing.rpt { check_timing }

    # FC-RM: write_tech_file dump
    catch { write_tech_file $::REPORTS_DIR/tech_file.dump }

    # FC-RM: write_qor_data
    catch {
        write_qor_data -report_list "performance host_machine report_app_options" \
            -label init_design -output $run_dir/qor_data
    }

    # BUG FIX #3: run_end does NOT exist in FC — removed
    # Use report_msg -summary instead
    redirect -file $::REPORTS_DIR/report_msg_summary.rpt { report_msg -summary }

    handle_info "Init design reports generated in: $::REPORTS_DIR"
}

# ==============================================================================
# Execute all flow_procs in definition order
# ==============================================================================
flow_exec_all

# BUG FIX #7: Exit tool after stage completion (or on error)
# Without this, fc_shell hangs waiting for input after flow completes
handle_info "Init design completed — exiting fc_shell"
exit
