#!/usr/bin/env tclsh
# CBFlow FCFP init_design - Synopsys Fusion Compiler (FC-RM Y-2026.03)

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "FCFP"
set STAGE_NAME "init_design"
set NODE_NAME "${STAGE_NAME}1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# ==============================================================================
# flow_proc: create_design_library
# FC-RM: create_lib with technology file, NDM reference libraries
# ==============================================================================
flow_proc create_design_library {
    handle_info "Creating design library..."
    global fcfp flow project tech

    set run_dir $::env(CBFLOW_RUN_DIR)
    file mkdir "$run_dir/work/FCFP/init_design/run"

    set design_name [expr {[info exists fcfp(common,design_name)] ? $fcfp(common,design_name) : $flow(design_name)}]
    set lib_name [expr {[info exists fcfp(common,design_lib_name)] ? $fcfp(common,design_lib_name) : "${design_name}.nlib"}]

    if {[file exists $lib_name]} { file delete -force $lib_name }

    # Build reference library list from tech()
    set ref_libs [list]
    if {[info exists tech(ndm,standard_cells)] && $tech(ndm,standard_cells) ne ""} {
        lappend ref_libs $tech(ndm,standard_cells)
    }
    if {[info exists tech(ndm,memory)] && $tech(ndm,memory) ne ""} {
        lappend ref_libs $tech(ndm,memory)
    }
    if {[info exists tech(ndm,io_pads)] && $tech(ndm,io_pads) ne ""} {
        lappend ref_libs $tech(ndm,io_pads)
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

    # Additional NDM libs
    if {[info exists tech(ndm,additional)] && [llength $tech(ndm,additional)] > 0} {
        foreach lib $tech(ndm,additional) {
            if {$lib ne ""} { lappend ref_libs $lib }
        }
    }

    # Fusion library creation from LEF+DB if no NDM
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
            set fusion_dir "$run_dir/work/FCFP/init_design/fusion_libs"
            file mkdir $fusion_dir
            create_fusion_reference_library \
                -output_directory $fusion_dir \
                -lef_files $fusion_lef_list \
                -db_files $fusion_db_list
            foreach lib [glob -nocomplain -type d ${fusion_dir}/*] {
                lappend ref_libs $lib
            }
        }
    }

    # Technology file
    set tech_file ""
    set tech_lib ""
    if {[info exists tech(tech_file)] && $tech(tech_file) ne ""} { set tech_file $tech(tech_file) }
    if {[info exists tech(ndm,tech_lib)] && $tech(ndm,tech_lib) ne ""} { set tech_lib $tech(ndm,tech_lib) }

    set parasitic_tech_lib ""
    if {[info exists tech(ndm,parasitic_tech)] && $tech(ndm,parasitic_tech) ne ""} {
        set parasitic_tech_lib $tech(ndm,parasitic_tech)
    }

    # Build and execute create_lib
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

    if {[llength $fusion_db_list] > 0} {
        set_app_var link_library $fusion_db_list
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
    global fcfp flow tech

    set design_name [expr {[info exists fcfp(common,design_name)] ? $fcfp(common,design_name) : $flow(design_name)}]

    if {[info exists fcfp(input,netlist)] && $fcfp(input,netlist) ne ""} {
        handle_info "Reading netlist: $fcfp(input,netlist)"
        read_verilog -top $design_name $fcfp(input,netlist)
    } elseif {[info exists fcfp(common,input_netlist)] && $fcfp(common,input_netlist) ne ""} {
        handle_info "Reading netlist: $fcfp(common,input_netlist)"
        read_verilog -top $design_name $fcfp(common,input_netlist)
    } else {
        handle_error "No netlist specified -- set fcfp(input,netlist) or fcfp(common,input_netlist)"
        return -code error "Missing netlist"
    }

    current_block $design_name
    link_block

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
    global fcfp flow tech

    set tech_node ""
    if {[info exists fcfp(common,technology_node)] && $fcfp(common,technology_node) ne ""} {
        set tech_node $fcfp(common,technology_node)
    } elseif {[info exists tech(node)] && $tech(node) ne ""} {
        set tech_node $tech(node)
    }
    if {$tech_node ne ""} {
        redirect -file $::REPORTS_DIR/set_technology { set_technology -node $tech_node -report_only }
        set_technology -node $tech_node
        handle_info "Technology node set: $tech_node"
    }

    if {[info exists tech(tech_setup_script)] && [file exists $tech(tech_setup_script)]} {
        handle_info "Sourcing tech setup: $tech(tech_setup_script)"
        source $tech(tech_setup_script)
    }

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
    global fcfp flow

    # Read SDC
    if {[info exists fcfp(input,sdc_file)] && $fcfp(input,sdc_file) ne ""} {
        if {[file exists $fcfp(input,sdc_file)]} {
            handle_info "Reading SDC: $fcfp(input,sdc_file)"
            read_sdc $fcfp(input,sdc_file)
        }
    } elseif {[info exists fcfp(common,input_sdc)] && $fcfp(common,input_sdc) ne ""} {
        foreach sdc_file $fcfp(common,input_sdc) {
            if {[file exists $sdc_file]} {
                handle_info "Reading SDC: $sdc_file"
                read_sdc $sdc_file
            }
        }
    }

    # UPF power intent
    if {[info exists fcfp(input,upf_file)] && $fcfp(input,upf_file) ne ""} {
        if {[file exists $fcfp(input,upf_file)]} {
            handle_info "Loading UPF: $fcfp(input,upf_file)"
            load_upf $fcfp(input,upf_file)
            if {[info exists fcfp(common,input_upf_supplemental)] && [file exists $fcfp(common,input_upf_supplemental)]} {
                handle_info "Loading supplemental UPF: $fcfp(common,input_upf_supplemental)"
                load_upf -supplemental $fcfp(common,input_upf_supplemental)
            }
            handle_info "Committing UPF..."
            commit_upf
        }
    }

    handle_info "Constraints loaded"
}

# ==============================================================================
# flow_proc: connect_power_ground
# FC-RM: connect_pg_net
# ==============================================================================
flow_proc connect_power_ground {
    handle_info "Connecting power/ground nets..."
    global fcfp flow

    if {[info exists fcfp(common,connect_pg_net_script)] && [file exists $fcfp(common,connect_pg_net_script)]} {
        source $fcfp(common,connect_pg_net_script)
    } else {
        connect_pg_net
    }

    handle_info "PG nets connected"
}

# ==============================================================================
# flow_proc: save_design
# FC-RM: save_lib, save_block, set_svf
# ==============================================================================
flow_proc save_design {
    handle_info "Saving init_design block..."
    global fcfp flow

    set run_dir $::env(CBFLOW_RUN_DIR)
    set design_name [expr {[info exists fcfp(common,design_name)] ? $fcfp(common,design_name) : $flow(design_name)}]

    if {[info exists fcfp(input,upf_file)] && $fcfp(input,upf_file) ne ""} {
        save_upf ${run_dir}/outputs/init_design.save_upf
    }

    save_lib -all
    save_block
    save_block -as ${design_name}/init_design
    handle_info "Block saved: ${design_name}/init_design"

    # Set SVF for formal verification
    if {[info exists fcfp(common,svf_file)] && $fcfp(common,svf_file) ne ""} {
        set_svf $fcfp(common,svf_file)
    }

    handle_info "Init design saved"
}

# ==============================================================================
# flow_proc: generate_reports
# FC-RM: report_qor, report_timing, report_design
# ==============================================================================
flow_proc generate_reports {
    handle_info "Generating init_design reports..."
    global fcfp

    set run_dir $::env(CBFLOW_RUN_DIR)
    file mkdir "$::REPORTS_DIR"

    set max_paths [expr {[info exists fcfp(analysis,max_paths)] ? $fcfp(analysis,max_paths) : 100}]

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
    redirect -file $::REPORTS_DIR/report_msg_summary.rpt { report_msg -summary }

    handle_info "Init design reports generated in: $::REPORTS_DIR"
}

# ==============================================================================
# ==============================================================================

flow_exec_all

# Exit tool after stage completion
exit
