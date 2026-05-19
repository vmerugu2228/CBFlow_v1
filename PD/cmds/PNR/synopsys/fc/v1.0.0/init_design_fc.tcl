#!/usr/bin/env tclsh
# CBFlow PNR init_design - Synopsys Fusion Compiler
# FC-RM: init_design.tcl -- Design library creation, technology setup,
#         netlist read, constraints, MCMM, OCV, power, and QoR strategy
# Aligned with FC-RM Y-2026.03

# -- Environment & Utilities --------------------------------------------------
set run_dir $::env(CBFLOW_RUN_DIR)
set env_file "$run_dir/.run.cbflow.tcl"
if {[file exists $env_file]} { source $env_file } else { puts stderr "ERROR: .run.cbflow.tcl not found"; exit 1 }
if {[info exists ::env(FLOW_DIR)]} { set FLOW_DIR $::env(FLOW_DIR) } else { puts stderr "ERROR: FLOW_DIR not set"; exit 1 }
if {![info exists ::env(UTILITIES_VERSION)] || $::env(UTILITIES_VERSION) eq ""} { puts stderr "ERROR: UTILITIES_VERSION not set"; exit 1 }
set utils_path "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} { source $utils_path } else { puts stderr "ERROR: Utils not found: $utils_path"; exit 1 }
namespace import ::CBFlow::Utilities::print_header

# -- Flow Type & Stage --------------------------------------------------------
set FLOW_TYPE "PNR"
set STAGE_NAME "init_design"
set NODE_NAME "init_design1"

# -- Config & MMMC ------------------------------------------------------------
set config_file "$run_dir/work/$::env(CBFLOW_FLOW_TYPE)/$::env(CBFLOW_NODE_NAME)/run/config.tcl"
if {[file exists $config_file]} { source -e $config_file }
global pnr project tech flow

# Source tech_config
if {[info exists ::env(TECH_NAME)] && $::env(TECH_NAME) ne "" &&
    [info exists ::env(TECH_VERSION)] && $::env(TECH_VERSION) ne ""} {
    set _tech_config "$::env(CONFIG_ROOT)/tech/$::env(TECH_NAME)/$::env(TECH_VERSION)/tech_config.tcl"
    if {[file exists $_tech_config]} {
        source -e $_tech_config
        # Source FC tool config
set _tool_config "[file dirname [info script]]/fc_config.tcl"
if {[file exists $_tool_config]} { source $_tool_config }
handle_info "Tech config loaded: $_tech_config"
    } else {
        handle_warning "Tech config not found: $_tech_config"
    }
}

# Source MMMC config
catch {
    set mmmc_config_file "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/mmmc_config.tcl"
    if {[file exists $mmmc_config_file]} { source -e $mmmc_config_file }
}

# Source user_config (overrides)
if {[file exists "$run_dir/setup/user_config.tcl"]} {
    source -e "$run_dir/setup/user_config.tcl"
}

# -- Flow Initialization ------------------------------------------------------
handle_info "Starting $FLOW_TYPE $STAGE_NAME (FC-RM Y-2026.03 aligned)..."
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
set INPUTS_DIR "$run_dir/work/$FLOW_TYPE/netlist1"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

# ==============================================================================
# flow_proc: create_design_library
# FC-RM: create_lib with technology file, NDM reference libraries, and
#         optional on-the-fly fusion library creation from LEF+DB
# All library/technology info comes from tech() array (tech_config.tcl)
# ==============================================================================
flow_proc create_design_library {
    handle_info "Creating design library..."
    global pnr tech flow

    set run_dir $::env(CBFLOW_RUN_DIR)
    file mkdir "$run_dir/work/PNR/init_design1/run"

    set design_name [expr {[info exists fc(common,design_name)] ? $fc(common,design_name) : $flow(design_name)}]
    set lib_name [expr {[info exists fc(common,design_lib_name)] ? $fc(common,design_lib_name) : "${design_name}.nlib"}]

    # Remove existing library safely -- handle .nfs lock files from NFS
    if {[file exists $lib_name]} {
        handle_info "Removing existing library: $lib_name"
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

    # -- Build reference library list (from tech array) ------------------------
    set ref_libs [list]

    # NDM reference libraries (preferred -- contain timing+physical+logical)
    if {[info exists tech(ndm,standard_cells)] && $tech(ndm,standard_cells) ne ""} {
        lappend ref_libs $tech(ndm,standard_cells)
    }
    if {[info exists tech(ndm,memory)] && $tech(ndm,memory) ne ""} {
        lappend ref_libs $tech(ndm,memory)
    }
    if {[info exists tech(ndm,io_pads)] && $tech(ndm,io_pads) ne ""} {
        lappend ref_libs $tech(ndm,io_pads)
    }

    # Sub-block abstract NDM libs -- only for hierarchical designs
    set chip_type [expr {[info exists fc(common,chip_type)] ? $fc(common,chip_type) : "flat"}]
    if {$chip_type eq "hierarchical" && [info exists tech(ndm,sub_blocks)] && [llength $tech(ndm,sub_blocks)] > 0} {
        foreach lib $tech(ndm,sub_blocks) {
            if {$lib ne ""} { lappend ref_libs $lib }
        }
        handle_info "Hierarchical flow: [llength $tech(ndm,sub_blocks)] sub-block libraries added"
    }

    # Additional NDM libs (analog, custom)
    if {[info exists tech(ndm,additional)] && [llength $tech(ndm,additional)] > 0} {
        foreach lib $tech(ndm,additional) {
            if {$lib ne ""} { lappend ref_libs $lib }
        }
    }

    # PNR-specific: reference NDMs from pnr config override
    if {[info exists fc(common,ndm_libs)] && [llength $fc(common,ndm_libs)] > 0} {
        foreach lib $fc(common,ndm_libs) {
            if {$lib ne "" && $lib ni $ref_libs} { lappend ref_libs $lib }
        }
    }

    # -- On-the-fly fusion library creation (LEF + DB from tech) ---------------
    set fusion_lef_list [list]
    set fusion_db_list [list]

    if {[llength $ref_libs] == 0} {
        handle_info "No NDM reference libraries, checking LEF+DB for fusion library creation..."

        if {[info exists tech(lef,standard_cells)]} { lappend fusion_lef_list $tech(lef,standard_cells) }
        if {[info exists tech(lef,macros)]}         { lappend fusion_lef_list $tech(lef,macros) }
        if {[info exists tech(lef,io_pads)]}        { lappend fusion_lef_list $tech(lef,io_pads) }
        if {[info exists tech(lef,memory)]}         { lappend fusion_lef_list $tech(lef,memory) }

        if {[info exists tech(db,standard_cells)]}  { lappend fusion_db_list $tech(db,standard_cells) }
        if {[info exists tech(db,macros)]}          { lappend fusion_db_list $tech(db,macros) }
        if {[info exists tech(db,io_pads)]}         { lappend fusion_db_list $tech(db,io_pads) }
        if {[info exists tech(db,memory)]}          { lappend fusion_db_list $tech(db,memory) }

        if {[llength $fusion_lef_list] > 0 && [llength $fusion_db_list] > 0} {
            handle_info "Creating fusion reference libraries from LEF+DB..."
            set fusion_dir "$run_dir/work/PNR/init_design1/fusion_libs"
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
            handle_warning "LEF files found but no timing DB -- set tech(db,*) in tech_config.tcl"
            set ref_libs $fusion_lef_list
        }
    }

    # -- Technology file (from tech array) -------------------------------------
    set tech_file ""
    set tech_lib ""
    if {[info exists tech(tech_file)] && $tech(tech_file) ne ""} { set tech_file $tech(tech_file) }
    if {[info exists tech(ndm,tech_lib)] && $tech(ndm,tech_lib) ne ""} { set tech_lib $tech(ndm,tech_lib) }

    # Parasitic tech library
    set parasitic_tech_lib ""
    if {[info exists tech(ndm,parasitic_tech)] && $tech(ndm,parasitic_tech) ne ""} {
        set parasitic_tech_lib $tech(ndm,parasitic_tech)
    }

    # -- Build and execute create_lib command ----------------------------------
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
    # Avoid double {{braces}} -- expand list properly
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
# FC-RM: read_verilog (gate-level netlist from synthesis), current_block,
#         link_block -- PNR reads post-synthesis netlist, not RTL
# ==============================================================================
flow_proc read_design {
    handle_info "Reading design netlist..."
    global pnr flow

    set design_name [expr {[info exists fc(common,design_name)] ? $fc(common,design_name) : $flow(design_name)}]

    # FC-RM: set_svf for formality
    set_svf $::OUTPUTS_DIR/init_design.svf

    # PNR reads gate-level netlist from synthesis output
    set netlist_file ""
    if {[info exists pnr(input,netlist)] && $pnr(input,netlist) ne ""} {
        set netlist_file $pnr(input,netlist)
    } elseif {[info exists fc(common,input_netlist)] && $fc(common,input_netlist) ne ""} {
        set netlist_file $fc(common,input_netlist)
    } else {
        # Default: look in inputs directory
        set netlist_file "$::NETLIST_DIR/${design_name}.v"
        if {![file exists $netlist_file]} {
            set netlist_file "$::NETLIST_DIR/${design_name}.vg"
        }
    }

    if {$netlist_file ne "" && [file exists $netlist_file]} {
        handle_info "Reading netlist: $netlist_file"
        read_verilog -top $design_name $netlist_file
    } else {
        handle_error "Netlist not found: $netlist_file -- set pnr(input,netlist)"
        return -code error "Missing netlist"
    }

    current_block $design_name
    link_block

    # Report initial design statistics
    set cell_count [sizeof_collection [get_cells -hierarchical -quiet]]
    set port_count [sizeof_collection [get_ports * -quiet]]
    handle_info "Design linked: $cell_count cells, $port_count ports"

    save_lib
    handle_info "Design read and linked: $design_name"
}

# ==============================================================================
# flow_proc: setup_technology
# FC-RM: set_technology -node, tech setup script, read_physical_rules
# ==============================================================================
flow_proc setup_technology {
    handle_info "Setting up technology..."
    global pnr tech

    # FC-RM: set_technology -node
    if {[info exists tech(node)] && $tech(node) ne ""} {
        redirect -file $::REPORTS_DIR/set_technology { set_technology -node $tech(node) -report_only }
        set_technology -node $tech(node)
        handle_info "Technology node set: $tech(node)"
    }

    # FC-RM: Technology setup (routing direction, offset, site default, site symmetry)
    if {[info exists tech(tech_setup_script)] && $tech(tech_setup_script) ne "" && [file exists $tech(tech_setup_script)]} {
        handle_info "Sourcing tech setup: $tech(tech_setup_script)"
        source -e $tech(tech_setup_script)
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
# FC-RM: read_def / source floorplan TCL -- PNR-specific: expects floorplan
#         from FP flow output or user-provided DEF
# ==============================================================================
flow_proc load_floorplan {
    handle_info "Loading floorplan..."
    global pnr tech

    # FC-RM: TCL_FLOORPLAN_FILE or DEF_FLOORPLAN_FILES
    if {[info exists pnr(input,fp_tcl)] && $pnr(input,fp_tcl) ne "" && [file exists $pnr(input,fp_tcl)]} {
        handle_info "Sourcing floorplan TCL: $pnr(input,fp_tcl)"
        source -e $pnr(input,fp_tcl)
    } elseif {[info exists pnr(input,def_file)] && $pnr(input,def_file) ne ""} {
        if {[file exists $pnr(input,def_file)]} {
            handle_info "Reading DEF floorplan: $pnr(input,def_file)"
            read_def $pnr(input,def_file)
        } else {
            handle_warning "DEF file not found: $pnr(input,def_file)"
        }
    } else {
        handle_info "No floorplan specified -- auto-initialize in next step"
    }

    # FC-RM: resolve_pg_nets after DEF
    if {[info exists pnr(input,upf_file)] && $pnr(input,upf_file) ne ""} {
        catch {resolve_pg_nets}
    }

    # FC-RM: Source switch connectivity and associate MV cells
    if {[info exists fc(common,switch_connectivity_file)] && [file exists $fc(common,switch_connectivity_file)]} {
        source -e $fc(common,switch_connectivity_file)
        associate_mv_cell -power_switches
    }

    # FC-RM: SCANDEF
    if {[info exists pnr(input,scan_def)] && $pnr(input,scan_def) ne ""} {
        if {[file exists $pnr(input,scan_def)]} {
            handle_info "Reading scan DEF: $pnr(input,scan_def)"
            read_def $pnr(input,scan_def)
        }
    }

    # Create site rows if not present after floorplan load
    if {[sizeof_collection [get_site_rows -quiet]] == 0} {
        handle_info "No site rows found -- creating default site rows..."
        if {[info exists tech(site_default)] && $tech(site_default) ne ""} {
            create_site_rows -site $tech(site_default)
            handle_info "  Site rows created with site: $tech(site_default)"
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
# ==============================================================================
flow_proc initialize_floorplan {
    handle_info "Initializing floorplan (FC-RM)..."
    global pnr tech

    # Skip if floorplan was already loaded from DEF or TCL
    if {[sizeof_collection [get_cells -hier -filter "is_hard_macro==true" -quiet]] > 0 ||
        [sizeof_collection [get_site_rows -quiet]] > 0} {
        handle_info "Floorplan already present -- skipping auto-initialize"
        return
    }

    # FC-RM: initialize_floorplan with utilization target
    set util [expr {[info exists fc(fp,core_utilization)] ? $fc(fp,core_utilization) : 0.70}]
    set ratio [expr {[info exists fc(fp,aspect_ratio)] ? $fc(fp,aspect_ratio) : 1.0}]
    set offset [expr {[info exists fc(fp,core_offset)] ? $fc(fp,core_offset) : "5 5 5 5"}]

    handle_info "  Utilization: $util, Aspect ratio: $ratio"
    initialize_floorplan -core_utilization $util \
        -core_aspect_ratio $ratio \
        -core_offset $offset

    # Create site rows if not present
    if {[sizeof_collection [get_site_rows -quiet]] == 0} {
        if {[info exists tech(site_default)] && $tech(site_default) ne ""} {
            create_site_rows -site $tech(site_default)
        } else {
            create_site_rows
        }
        handle_info "  Site rows created"
    }

    handle_info "Floorplan initialized"
}

# ==============================================================================
# flow_proc: insert_physical_cells
# FC-RM: Tap cells, boundary cells, endcap cells -- required before placement
# ==============================================================================
flow_proc insert_physical_cells {
    handle_info "Inserting physical cells (FC-RM)..."
    global pnr tech

    # -- FC-RM: Tap cells (well tie) ------------------------------------------
    if {[info exists tech(cells,well_tap)] && $tech(cells,well_tap) ne ""} {
        set tap_cells [lindex $tech(cells,well_tap) 0]
        set tap_dist [expr {[info exists fc(fp,tap_cell_distance)] ? $fc(fp,tap_cell_distance) : 30}]

        handle_info "  Inserting tap cells: $tap_cells (every ${tap_dist}um)"
        create_tap_cells -lib_cell $tap_cells \
            -distance $tap_dist \
            -pattern stagger
        handle_info "  Tap cells inserted: [sizeof_collection [get_cells -hier -filter ref_name==$tap_cells -quiet]]"
    } else {
        handle_warning "  No tap cells defined in tech(cells,well_tap)"
    }

    # -- FC-RM: Boundary cells ------------------------------------------------
    if {[info exists tech(cells,endcap)] && $tech(cells,endcap) ne ""} {
        set endcap_cell $tech(cells,endcap)
        handle_info "  Inserting boundary/endcap cells: $endcap_cell"
        set_boundary_cell_rules -left_boundary_cell $endcap_cell \
            -right_boundary_cell $endcap_cell
        compile_boundary_cells
        handle_info "  Boundary cells inserted"
    } else {
        handle_info "  No endcap cells defined -- skipping boundary cells"
    }

    # -- FC-RM: Power switch cells (for UPF flows) ----------------------------
    if {[info exists pnr(input,upf_file)] && $pnr(input,upf_file) ne ""} {
        catch {
            associate_mv_cell -power_switches
            handle_info "  Power switch cells associated"
        }
    }

    # -- FC-RM: Spare cells (optional) ----------------------------------------
    if {[info exists fc(common,spare_cells_file)] && [file exists $fc(common,spare_cells_file)]} {
        handle_info "  Sourcing spare cells: $fc(common,spare_cells_file)"
        source -e $fc(common,spare_cells_file)
    }

    save_lib -all
    handle_info "Physical cells inserted"
}

# ==============================================================================
# flow_proc: setup_design_checks
# FC-RM: check_design, report_design_mismatch, report_unbound, check_duplicates
# ==============================================================================
flow_proc setup_design_checks {
    handle_info "Running design checks..."
    global pnr flow

    set design_name [expr {[info exists fc(common,design_name)] ? $fc(common,design_name) : $flow(design_name)}]

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
# flow_proc: load_constraints
# FC-RM: read_sdc, load_upf (primary + supplemental), commit_upf
# ==============================================================================
flow_proc load_constraints {
    handle_info "Loading timing and power constraints..."
    global pnr flow

    set design_name [expr {[info exists fc(common,design_name)] ? $fc(common,design_name) : $flow(design_name)}]

    # SDC constraints
    set sdc_file ""
    if {[info exists pnr(input,sdc)] && $pnr(input,sdc) ne ""} {
        set sdc_file $pnr(input,sdc)
    } elseif {[info exists pnr(input,sdc_file)] && $pnr(input,sdc_file) ne ""} {
        set sdc_file $pnr(input,sdc_file)
    } else {
        set sdc_file "$::SDC_DIR/${design_name}.sdc"
    }

    if {$sdc_file ne "" && [file exists $sdc_file]} {
        handle_info "Reading SDC: $sdc_file"
        source -e $sdc_file
    } else {
        handle_warning "SDC file not found: $sdc_file"
    }

    # UPF power intent
    if {[info exists fc(common,upf_mode)] && $fc(common,upf_mode) eq "golden"} {
        set_app_options -name mv.upf.enable_golden_upf -value true
    }

    set upf_file ""
    if {[info exists pnr(input,upf_file)] && $pnr(input,upf_file) ne ""} {
        set upf_file $pnr(input,upf_file)
    } else {
        set upf_file "$::UPF_DIR/${design_name}.upf"
    }

    if {$upf_file ne "" && [file exists $upf_file]} {
        handle_info "Loading UPF: $upf_file"
        load_upf $upf_file

        # FC-RM: Supplemental UPF (golden UPF flow)
        if {[info exists pnr(input,upf_supplemental)] && [file exists $pnr(input,upf_supplemental)]} {
            handle_info "Loading supplemental UPF: $pnr(input,upf_supplemental)"
            load_upf -supplemental $pnr(input,upf_supplemental)
        }

        handle_info "Committing UPF..."
        commit_upf
    } else {
        handle_info "No UPF file found -- single power domain"
    }

    handle_info "Constraints loaded"
}

# ==============================================================================
# flow_proc: setup_parasitics
# FC-RM: read_parasitic_tech -tlup / -layermap
# ==============================================================================
flow_proc setup_parasitics {
    handle_info "Setting up parasitic technology..."
    global tech

    # FC-RM: Only source parasitic setup if PARASITIC_TECH_LIB was not specified in create_lib
    set parasitic_in_lib false
    if {[info exists tech(ndm,parasitic_tech)] && $tech(ndm,parasitic_tech) ne ""} {
        set parasitic_in_lib true
        handle_info "Parasitic tech already loaded via create_lib -use_parasitic_tech_lib"
    }

    if {!$parasitic_in_lib} {
        # TLU+ must include -layermap in same command to avoid memory issue
        set _tlu_map ""
        if {[info exists tech(tluplus,map)] && [file exists $tech(tluplus,map)]} {
            set _tlu_map $tech(tluplus,map)
        }

        # TLU+ max with map file
        if {[info exists tech(tluplus,max)] && [file exists $tech(tluplus,max)]} {
            handle_info "Reading TLU+ max: $tech(tluplus,max)"
            if {$_tlu_map ne ""} {
                read_parasitic_tech -tlup $tech(tluplus,max) -layermap $_tlu_map -name maxTLU
            } else {
                read_parasitic_tech -tlup $tech(tluplus,max) -name maxTLU
            }
        }
        # TLU+ min with map file
        if {[info exists tech(tluplus,min)] && [file exists $tech(tluplus,min)]} {
            handle_info "Reading TLU+ min: $tech(tluplus,min)"
            if {$_tlu_map ne ""} {
                read_parasitic_tech -tlup $tech(tluplus,min) -layermap $_tlu_map -name minTLU
            } else {
                read_parasitic_tech -tlup $tech(tluplus,min) -name minTLU
            }
        }

        # QRC tech file (alternative to TLU+)
        if {[info exists tech(ext,qrc_tech)] && [file exists $tech(ext,qrc_tech)]} {
            handle_info "Reading QRC tech: $tech(ext,qrc_tech)"
            read_parasitic_tech -tlup $tech(ext,qrc_tech)
        }
    }

    handle_info "Parasitic technology setup completed"
}

# ==============================================================================
# flow_proc: setup_mcmm
# FC-RM: MCMM scenario creation -- modes, corners, scenarios
# ==============================================================================
flow_proc setup_mcmm {
    handle_info "Setting up MCMM scenarios..."
    global pnr tech

    set run_dir $::env(CBFLOW_RUN_DIR)

    # FC-RM: Source user MCMM setup script if provided
    if {[info exists fc(common,mcmm_setup_file)] && [file exists $fc(common,mcmm_setup_file)]} {
        handle_info "Sourcing MCMM setup: $fc(common,mcmm_setup_file)"
        source -e $fc(common,mcmm_setup_file)
    } else {
        # Auto-create MCMM from CBflow mmmc_config analysis_views
        handle_info "Creating MCMM scenarios from mmmc_config..."
        global analysis_views library_sets

        if {[info exists analysis_views] && [array size analysis_views] > 0} {
            # Create modes
            set _modes_created {}
            foreach scenario [array names analysis_views] {
                array set _v $analysis_views($scenario)
                set _mode $_v(mode)
                if {$_mode ni $_modes_created} {
                    set _sdc_file [expr {[info exists _v(constraint_file)] ? $_v(constraint_file) : ""}]
                    set _sdc_path "$::SDC_DIR/$_sdc_file"
                    if {[file exists $_sdc_path]} {
                        create_mode $_mode
                        current_mode $_mode
                        source -e $_sdc_path
                        handle_info "  Created mode: $_mode (SDC: $_sdc_file)"
                    } else {
                        handle_warning "  SDC not found for mode $_mode: $_sdc_path"
                    }
                    lappend _modes_created $_mode
                }
                array unset _v
            }

            # Create corners
            set _corners_created {}
            foreach scenario [array names analysis_views] {
                array set _v $analysis_views($scenario)
                set _corner_name "$_v(corner)_$_v(lib_set_ref)"
                if {$_corner_name ni $_corners_created} {
                    set _lib_set $_v(lib_set_ref)
                    set _timing_libs {}
                    if {[info exists library_sets(${_lib_set},timing)]} {
                        set _timing_libs $library_sets(${_lib_set},timing)
                    }
                    if {[llength $_timing_libs] > 0} {
                        create_corner $_corner_name
                        handle_info "  Created corner: $_corner_name (libs: [llength $_timing_libs])"
                    }
                    lappend _corners_created $_corner_name
                }
                array unset _v
            }

            # Create scenarios (mode + corner combinations)
            foreach scenario [array names analysis_views] {
                array set _v $analysis_views($scenario)
                set _mode $_v(mode)
                set _corner_name "$_v(corner)_$_v(lib_set_ref)"
                create_scenario -name $scenario -mode $_mode -corner $_corner_name
                handle_info "  Created scenario: $scenario (mode=$_mode, corner=$_corner_name)"
                array unset _v
            }

            handle_info "MCMM: [llength $_modes_created] modes, [llength $_corners_created] corners, [array size analysis_views] scenarios"
        } else {
            handle_info "No MCMM analysis_views defined -- single corner mode"
        }
    }

    # Activate scenarios for init_design from mmmc_config
    if {[info exists fc(init_design,active_scenarios)] && $fc(init_design,active_scenarios) ne ""} {
        set_scenario_status -active false [get_scenarios -filter active]
        set_scenario_status -active true $fc(init_design,active_scenarios)
        handle_info "Active scenarios (user override): $fc(init_design,active_scenarios)"
    } elseif {[info commands get_node_scenarios] ne ""} {
        set node_scenarios [get_node_scenarios "pnr" "all"]
        if {[llength $node_scenarios] > 0} {
            set_scenario_status -active false [get_scenarios -filter active]
            set_scenario_status -active true $node_scenarios
            handle_info "Active scenarios (from mmmc_config): $node_scenarios"
        }
    }

    # FC-RM: Design constraints (dont_touch, clock_gating, etc.)
    if {[info exists fc(common,constraints_setup_file)] && [file exists $fc(common,constraints_setup_file)]} {
        handle_info "Sourcing constraints setup: $fc(common,constraints_setup_file)"
        source -e $fc(common,constraints_setup_file)
    }

    # FC-RM: Remove propagated clocks (for ASCII/netlist input)
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
    global pnr tech

    # FC-RM: POCV setup (preferred over AOCV)
    if {[info exists fc(common,pocv_setup_file)] && [file exists $fc(common,pocv_setup_file)]} {
        handle_info "Sourcing POCV setup: $fc(common,pocv_setup_file)"
        source -e $fc(common,pocv_setup_file)
        set_app_options -name time.pocvm_enable_analysis -value true
        reset_app_options time.aocvm_enable_analysis
        handle_info "POCV analysis enabled"
    } elseif {[info exists fc(common,aocv_setup_file)] && [file exists $fc(common,aocv_setup_file)]} {
        handle_info "Sourcing AOCV setup: $fc(common,aocv_setup_file)"
        source -e $fc(common,aocv_setup_file)
        handle_info "AOCV analysis enabled"
    } elseif {[info exists tech(ocv,derate_file)] && [file exists $tech(ocv,derate_file)]} {
        handle_info "Sourcing OCV derate: $tech(ocv,derate_file)"
        source -e $tech(ocv,derate_file)
    }

    handle_info "Timing variation setup completed"
}

# ==============================================================================
# flow_proc: setup_lib_cell_purpose
# FC-RM: set_lib_cell_purpose -- dont_use, tie cells, hold, CTS restrictions
# ==============================================================================
flow_proc setup_lib_cell_purpose {
    handle_info "Setting library cell purpose restrictions..."
    global pnr tech

    # FC-RM: Source lib cell purpose file
    if {[info exists fc(common,lib_cell_purpose_file)] && [file exists $fc(common,lib_cell_purpose_file)]} {
        handle_info "Sourcing lib cell purpose: $fc(common,lib_cell_purpose_file)"
        source -e $fc(common,lib_cell_purpose_file)
    } elseif {[info exists tech(lib_cell_purpose_file)] && [file exists $tech(lib_cell_purpose_file)]} {
        handle_info "Sourcing lib cell purpose from tech: $tech(lib_cell_purpose_file)"
        source -e $tech(lib_cell_purpose_file)
    }

    # FC-RM: Dont-use cells
    if {[info exists tech(dont_use_cells)] && $tech(dont_use_cells) ne ""} {
        foreach cell $tech(dont_use_cells) {
            set_lib_cell_purpose -exclude optimization [get_lib_cells $cell]
        }
        handle_info "Dont-use cells applied: [llength $tech(dont_use_cells)] cells"
    }

    handle_info "Library cell restrictions applied"
}

# ==============================================================================
# flow_proc: setup_clock_ndr
# FC-RM: Clock NDR rules, routing rules for CTS
# ==============================================================================
flow_proc setup_clock_ndr {
    handle_info "Setting up clock NDR rules..."
    global pnr tech

    # FC-RM: Source CTS NDR rule file
    if {[info exists fc(common,cts_ndr_file)] && [file exists $fc(common,cts_ndr_file)]} {
        handle_info "Sourcing CTS NDR rules: $fc(common,cts_ndr_file)"
        source -e $fc(common,cts_ndr_file)
    } elseif {[info exists tech(cts_ndr_file)] && [file exists $tech(cts_ndr_file)]} {
        source -e $tech(cts_ndr_file)
    }

    # FC-RM: Via ladder definitions
    if {[info exists tech(via_ladder_file)] && [file exists $tech(via_ladder_file)]} {
        handle_info "Sourcing via ladder definitions"
        source -e $tech(via_ladder_file)
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
    global pnr

    # FC-RM: Source placement constraint files
    if {[info exists fc(common,placement_constraint_files)] && [llength $fc(common,placement_constraint_files)] > 0} {
        foreach file $fc(common,placement_constraint_files) {
            if {[file exists $file]} {
                handle_info "Sourcing placement constraint: $file"
                source -e $file
            }
        }
    }

    # FC-RM: Additional floorplan constraints
    if {[info exists fc(common,additional_floorplan_file)] && [file exists $fc(common,additional_floorplan_file)]} {
        source -e $fc(common,additional_floorplan_file)
    }

    handle_info "Placement constraints applied"
}

# ==============================================================================
# flow_proc: setup_power_activity
# FC-RM: read_saif, switching activity, infer_switching_activity
# ==============================================================================
flow_proc setup_power_activity {
    handle_info "Setting up power activity..."
    global pnr

    # FC-RM: saif_map -start
    saif_map -start

    # FC-RM: read_saif
    if {[info exists fc(common,saif_file)] && $fc(common,saif_file) ne ""} {
        if {[file exists $fc(common,saif_file)]} {
            set read_saif_cmd "read_saif $fc(common,saif_file)"
            if {[info exists fc(common,saif_power_scenario)] && $fc(common,saif_power_scenario) ne ""} {
                lappend read_saif_cmd -scenarios $fc(common,saif_power_scenario)
            }
            if {[info exists fc(common,saif_source_instance)] && $fc(common,saif_source_instance) ne ""} {
                lappend read_saif_cmd -strip_path $fc(common,saif_source_instance)
            }
            if {[info exists fc(common,saif_target_instance)] && $fc(common,saif_target_instance) ne ""} {
                lappend read_saif_cmd -path $fc(common,saif_target_instance)
            }
            handle_info "Reading SAIF: $read_saif_cmd"
            eval $read_saif_cmd
        }
    }

    handle_info "Power activity setup completed"
}

# ==============================================================================
# flow_proc: setup_dft
# FC-RM: DFT ports setup
# ==============================================================================
flow_proc setup_dft {
    handle_info "Setting up DFT..."
    global pnr

    # FC-RM: DFT ports file
    if {[info exists fc(common,dft_ports_file)] && [file exists $fc(common,dft_ports_file)]} {
        handle_info "Sourcing DFT ports: $fc(common,dft_ports_file)"
        source -e $fc(common,dft_ports_file)
    }

    handle_info "DFT setup completed"
}

# ==============================================================================
# flow_proc: connect_power_ground
# FC-RM: connect_pg_net
# ==============================================================================
flow_proc connect_power_ground {
    handle_info "Connecting power/ground nets..."
    global pnr

    # FC-RM: User PG connection script or automatic
    if {[info exists fc(common,connect_pg_net_script)] && [file exists $fc(common,connect_pg_net_script)]} {
        source -e $fc(common,connect_pg_net_script)
    } else {
        connect_pg_net
    }

    handle_info "PG nets connected"
}

# ==============================================================================
# flow_proc: set_qor_strategy_init
# FC-RM: set_qor_strategy for initial PNR design setup
# ==============================================================================
flow_proc set_qor_strategy_init {
    handle_info "Setting QoR strategy..."
    global pnr

    set metric [expr {[info exists fc(compile,qor_metric)] ? $fc(compile,qor_metric) : "timing"}]
    set mode [expr {[info exists fc(compile,qor_mode)] ? $fc(compile,qor_mode) : "balanced"}]

    set_qor_strategy -stage pnr -metric $metric -mode $mode

    handle_info "QoR strategy: metric=$metric, mode=$mode"
}

# ==============================================================================
# flow_proc: run_floorplan_checks
# FC-RM: check_floorplan_rules
# ==============================================================================
flow_proc run_floorplan_checks {
    handle_info "Running floorplan checks..."
    global pnr

    # FC-RM: check_floorplan_rules
    catch {
        redirect -file $::REPORTS_DIR/check_floorplan_rules.rpt { check_floorplan_rules }
    }

    # FC-RM: Floorplan rule script
    if {[info exists fc(common,floorplan_rule_script)] && [file exists $fc(common,floorplan_rule_script)]} {
        source -e $fc(common,floorplan_rule_script)
    }

    handle_info "Floorplan checks completed"
}

# ==============================================================================
# flow_proc: save_design
# FC-RM: save_upf, save_lib, save_block -as, set_svf -off
# ==============================================================================
flow_proc save_design {
    handle_info "Saving init_design block..."
    global pnr flow

    set run_dir $::env(CBFLOW_RUN_DIR)
    set design_name [expr {[info exists fc(common,design_name)] ? $fc(common,design_name) : $flow(design_name)}]

    # FC-RM: save_upf
    set upf_mode "none"
    if {[info exists fc(common,upf_mode)]} { set upf_mode $fc(common,upf_mode) }
    file mkdir "$run_dir/outputs"
    if {$upf_mode eq "golden"} {
        save_upf ${run_dir}/outputs/init_design.supplemental.upf
    } elseif {[info exists pnr(input,upf_file)] && $pnr(input,upf_file) ne ""} {
        save_upf ${run_dir}/outputs/init_design.save_upf
    }

    # FC-RM: save_lib -all, save_block
    save_lib -all
    save_block
    if {[info exists fc(output,block_labeling)] && $fc(output,block_labeling)} {
        save_block -as ${design_name}/init_design
        handle_info "Block saved: ${design_name}/init_design"
    }

    # FC-RM: Close SVF
    set_svf -off

    handle_info "Init design saved"
}

# ==============================================================================
# flow_proc: generate_reports
# FC-RM: report_qor, report_timing, report_design, write_tech_file,
#         write_qor_data, report_msg
# ==============================================================================
flow_proc generate_reports {
    handle_info "Generating init_design reports..."
    global pnr

    set run_dir $::env(CBFLOW_RUN_DIR)
    file mkdir "$::REPORTS_DIR"

    set max_paths [expr {[info exists fc(analysis,max_paths)] ? $fc(analysis,max_paths) : 100}]

    # FC-RM: Core reports
    # FC-RM: Core reports
    redirect -file $::REPORTS_DIR/report_qor.rpt { report_qor -nosplit }
    redirect -file $::REPORTS_DIR/report_qor_summary.rpt { report_qor -summary -nosplit }
    redirect -file $::REPORTS_DIR/report_timing.max.rpt {
        report_timing -max_paths $max_paths -delay_type max -nosplit
    }
    redirect -file $::REPORTS_DIR/report_timing.min.rpt {
        report_timing -max_paths $max_paths -delay_type min -nosplit
    }
    redirect -file $::REPORTS_DIR/report_design.rpt { report_design -physical }
    redirect -file $::REPORTS_DIR/report_utilization.rpt { report_utilization }
    redirect -file $::REPORTS_DIR/report_clocks.rpt { report_clocks }

    # FC-RM: check_timing (constraint completeness)
    redirect -file $::REPORTS_DIR/check_timing.rpt { check_timing }

    # FC-RM: App options snapshot
    redirect -file $::REPORTS_DIR/report_app_options.end.rpt { report_app_options -non_default * }

    # FC-RM: write_tech_file dump
    catch { write_tech_file $::REPORTS_DIR/tech_file.dump }

    # FC-RM: write_qor_data
    catch {
        write_qor_data -report_list "performance host_machine report_app_options" \
            -label init_design -output $run_dir/qor_data
    }

    # FC-RM: report_msg summary
    redirect -file $::REPORTS_DIR/report_msg_summary.rpt { report_msg -summary }

    handle_info "Init design reports generated in: $::REPORTS_DIR"
}

# ==============================================================================
# Source setup.tcl (flow_proc hooks: prepend, append, replace)
# Must be sourced AFTER flow_proc definitions but BEFORE flow_exec_all
# ==============================================================================
set _setup_file "$run_dir/work/$::env(CBFLOW_FLOW_TYPE)/$::env(CBFLOW_NODE_NAME)/run/setup.tcl"
if {[file exists $_setup_file]} {
    handle_info "Sourcing setup hooks: $_setup_file"
    source -e $_setup_file
}
# Also source user override directly if present
set _override_file "$run_dir/setup/override_setup.tcl"
if {[file exists $_override_file]} {
    handle_info "Sourcing user override: $_override_file"
    source -e $_override_file
}
set _stage_override "$run_dir/setup/override_setup.init_design.tcl"
if {[file exists $_stage_override]} {
    handle_info "Sourcing stage override: $_stage_override"
    source -e $_stage_override
}

# ==============================================================================
# Execute all flow_procs in definition order
# ==============================================================================
flow_exec_all

handle_info "Init design completed -- exiting fc_shell"
exit
