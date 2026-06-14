#!/usr/bin/env tclsh
# CBFlow FP init_design - Synopsys Fusion Compiler
# FC-RM: init_design_dp.tcl -- Design library creation, technology setup,
#         netlist read, constraints, power connections, and initial save
# Aligned with FC-RM Y-2026.03

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "FP"
set STAGE_NAME "init_design"
set NODE_NAME "init_design1"

# ── Config (full cascade: project → tech → flow → node → mmmc → tool → user) ─
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"

# ── Directories ──────────────────────────────────────────────────────────────
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# ==============================================================================
# flow_proc: create_design_library
# FC-RM: create_lib with technology file, NDM reference libraries
# All library/technology info comes from tech() array (tech_config.tcl)
# ==============================================================================
flow_proc create_design_library {
    handle_info "Creating design library..."
    global flow fp project tech

    set run_dir $::env(CBFLOW_RUN_DIR)
    file mkdir "$run_dir/work/FP/init_design1/run"

    set design_name [expr {[info exists fp(common,design_name)] ? $fp(common,design_name) : $flow(design_name)}]
    set lib_name [expr {[info exists fp(common,design_lib_name)] ? $fp(common,design_lib_name) : "${design_name}.nlib"}]

    # Delete existing library if present
    if {[file exists $lib_name]} {
        file delete -force $lib_name
    }

    # ── Build reference library list (track-aware) ─────────────────────────────
    set ref_libs [list]
    set _trk [expr {[info exists tech(track)] ? $tech(track) : ""}]

    # Priority 1: Track-categorized NDM list (new format)
    if {$_trk ne "" && [info exists tech(${_trk},ndm)]} {
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
        if {$_trk ne "" && [info exists tech(${_trk},lef)]} {
            set fusion_lef_list $tech(${_trk},lef)
        } else {
            if {[info exists tech(lef,standard_cells)]} { lappend fusion_lef_list $tech(lef,standard_cells) }
            if {[info exists tech(lef,macros)]}         { lappend fusion_lef_list $tech(lef,macros) }
            if {[info exists tech(lef,io_pads)]}        { lappend fusion_lef_list $tech(lef,io_pads) }
        }

        # Track-categorized DB list
        if {$_trk ne "" && [info exists tech(${_trk},db)]} {
            set fusion_db_list $tech(${_trk},db)
        } else {
            if {[info exists tech(db,standard_cells)]}  { lappend fusion_db_list $tech(db,standard_cells) }
            if {[info exists tech(db,memory)]}          { lappend fusion_db_list $tech(db,memory) }
            if {[info exists tech(db,io_pads)]}         { lappend fusion_db_list $tech(db,io_pads) }
        }

        if {[llength $fusion_lef_list] > 0 && [llength $fusion_db_list] > 0} {
            handle_info "Creating fusion reference libraries from LEF+DB..."
            set fusion_dir "$run_dir/work/FP/init_design1/fusion_libs"
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

    # Technology file (from tech array)
    set tech_file ""
    set tech_lib ""
    if {[info exists tech(tech_file)] && $tech(tech_file) ne ""} { set tech_file $tech(tech_file) }
    if {[info exists tech(ndm,tech_lib)] && $tech(ndm,tech_lib) ne ""} { set tech_lib $tech(ndm,tech_lib) }

    # Parasitic tech library
    set parasitic_tech_lib ""
    if {[info exists tech(ndm,parasitic_tech)] && $tech(ndm,parasitic_tech) ne ""} {
        set parasitic_tech_lib $tech(ndm,parasitic_tech)
    }

    # Build and execute create_lib command
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
    if {[llength $ref_libs] > 0} {
        lappend create_lib_cmd -ref_libs $ref_libs
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
# FC-RM: read_verilog (netlist), current_block, link_block
# ==============================================================================
flow_proc read_design {
    handle_info "Reading design..."
    global flow fp tech

    set design_name [expr {[info exists fp(common,design_name)] ? $fp(common,design_name) : $flow(design_name)}]

    # Read synthesized netlist
    if {[info exists fp(input,netlist)] && $fp(input,netlist) ne ""} {
        handle_info "Reading netlist: $fp(input,netlist)"
        read_verilog -top $design_name $fp(input,netlist)
    } elseif {[info exists fp(common,input_netlist)] && $fp(common,input_netlist) ne ""} {
        handle_info "Reading netlist: $fp(common,input_netlist)"
        read_verilog -top $design_name $fp(common,input_netlist)
    } else {
        handle_error "No netlist specified -- set fp(input,netlist) or fp(common,input_netlist)"
        return -code error "Missing netlist"
    }

    # Set current block and link
    current_block $design_name
    link_block

    # Report initial design statistics
    set cell_count [sizeof_collection [get_cells -hierarchical]]
    set port_count [sizeof_collection [get_ports *]]
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
    global flow fp tech

    # Set technology node
    set tech_node ""
    if {[info exists fp(common,technology_node)] && $fp(common,technology_node) ne ""} {
        set tech_node $fp(common,technology_node)
    } elseif {[info exists tech(node)] && $tech(node) ne ""} {
        set tech_node $tech(node)
    }
    if {$tech_node ne ""} {
        redirect -file $::REPORTS_DIR/set_technology { set_technology -node $tech_node -report_only }
        set_technology -node $tech_node
        handle_info "Technology node set: $tech_node"
    }

    # Source technology setup script (routing direction, offset, site)
    if {[info exists tech(tech_setup_script)] && [file exists $tech(tech_setup_script)]} {
        handle_info "Sourcing tech setup: $tech(tech_setup_script)"
        source $tech(tech_setup_script)
    }

    # Read physical rules
    if {[info exists tech(physical_rules_file)] && [file exists $tech(physical_rules_file)]} {
        handle_info "Reading physical rules: $tech(physical_rules_file)"
        read_physical_rules $tech(physical_rules_file)
    }

    save_lib -all
    handle_info "Technology setup completed"
}

# ==============================================================================
# flow_proc: load_constraints
# FC-RM: read_sdc, load_upf, commit_upf
# ==============================================================================
flow_proc load_constraints {
    handle_info "Loading timing and power constraints..."
    global flow fp

    # Read SDC
    if {[info exists fp(input,sdc_file)] && $fp(input,sdc_file) ne ""} {
        if {[file exists $fp(input,sdc_file)]} {
            handle_info "Reading SDC: $fp(input,sdc_file)"
            read_sdc $fp(input,sdc_file)
        }
    } elseif {[info exists fp(common,input_sdc)] && $fp(common,input_sdc) ne ""} {
        foreach sdc_file $fp(common,input_sdc) {
            if {[file exists $sdc_file]} {
                handle_info "Reading SDC: $sdc_file"
                read_sdc $sdc_file
            }
        }
    }

    # UPF power intent
    if {[info exists fp(input,upf_file)] && $fp(input,upf_file) ne ""} {
        if {[file exists $fp(input,upf_file)]} {
            handle_info "Loading UPF: $fp(input,upf_file)"
            load_upf $fp(input,upf_file)

            # Supplemental UPF
            if {[info exists fp(common,input_upf_supplemental)] && [file exists $fp(common,input_upf_supplemental)]} {
                handle_info "Loading supplemental UPF: $fp(common,input_upf_supplemental)"
                load_upf -supplemental $fp(common,input_upf_supplemental)
            }

            handle_info "Committing UPF..."
            commit_upf
        }
    } elseif {[info exists fp(common,input_upf)] && $fp(common,input_upf) ne ""} {
        foreach upf_file $fp(common,input_upf) {
            if {[file exists $upf_file]} {
                handle_info "Loading UPF: $upf_file"
                load_upf $upf_file
            }
        }
        commit_upf
    }

    handle_info "Constraints loaded"
}

# ==============================================================================
# flow_proc: connect_power_ground
# FC-RM: connect_pg_net
# ==============================================================================
flow_proc connect_power_ground {
    handle_info "Connecting power/ground nets..."
    global flow fp

    # User PG connection script or automatic
    if {[info exists fp(common,connect_pg_net_script)] && [file exists $fp(common,connect_pg_net_script)]} {
        source $fp(common,connect_pg_net_script)
    } else {
        connect_pg_net
    }

    handle_info "PG nets connected"
}

# ==============================================================================
# flow_proc: save_design
# FC-RM: save_lib, save_block
# ==============================================================================
flow_proc save_design {
    handle_info "Saving init_design block..."
    global fp flow

    set run_dir $::env(CBFLOW_RUN_DIR)
    set design_name [expr {[info exists fp(common,design_name)] ? $fp(common,design_name) : $flow(design_name)}]

    # Save UPF if applicable
    if {[info exists fp(input,upf_file)] && $fp(input,upf_file) ne ""} {
        save_upf ${run_dir}/outputs/init_design.save_upf
    }

    # Save library and block
    save_lib -all
    save_block
    save_block -as ${design_name}/init_design
    handle_info "Block saved: ${design_name}/init_design"

    handle_info "Init design saved"
}

# ==============================================================================
# flow_proc: generate_reports
# FC-RM: report_qor, report_timing, report_design
# ==============================================================================
flow_proc generate_reports {
    handle_info "Generating init_design reports..."
    global fp

    set run_dir $::env(CBFLOW_RUN_DIR)
    file mkdir "$::REPORTS_DIR"

    set max_paths [expr {[info exists fp(analysis,max_paths)] ? $fp(analysis,max_paths) : 100}]

    # Core reports
    redirect -file $::REPORTS_DIR/report_qor.rpt { report_qor }
    redirect -file $::REPORTS_DIR/report_timing.rpt {
        report_timing -max_paths $max_paths -delay_type max
    }
    redirect -file $::REPORTS_DIR/report_timing.min.rpt {
        report_timing -max_paths $max_paths -delay_type min
    }
    redirect -file $::REPORTS_DIR/report_design.rpt { report_design -physical }
    redirect -file $::REPORTS_DIR/report_utilization.rpt { report_utilization }
    redirect -file $::REPORTS_DIR/report_clocks.rpt { report_clocks }

    # Message summary
    redirect -file $::REPORTS_DIR/report_msg_summary.rpt { report_msg -summary }

    handle_info "Init design reports generated in: $::REPORTS_DIR"
}

# Source setup.tcl and overrides before flow_exec_all
# ==============================================================================

flow_exec_all

# Exit tool after stage completion
exit
