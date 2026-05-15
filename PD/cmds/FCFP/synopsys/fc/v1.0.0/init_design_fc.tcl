#!/usr/bin/env tclsh
# CBFlow FCFP init_design - Synopsys Fusion Compiler
# FC-RM: init_dp.tcl -- Design library creation, technology setup,
#         netlist read, constraints, power connections, and initial save
# Aligned with FC-RM Y-2026.03
set run_dir $::env(CBFLOW_RUN_DIR)
set env_file "$run_dir/.run.cbflow.tcl"
if {[file exists $env_file]} { source $env_file } else { puts stderr "ERROR: .run.cbflow.tcl not found"; exit 1 }
if {[info exists ::env(FLOW_DIR)]} { set FLOW_DIR $::env(FLOW_DIR) } else { puts stderr "ERROR: FLOW_DIR not set"; exit 1 }
if {![info exists ::env(UTILITIES_VERSION)] || $::env(UTILITIES_VERSION) eq ""} { puts stderr "ERROR: UTILITIES_VERSION not set"; exit 1 }
set utils_path "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} { source $utils_path } else { puts stderr "ERROR: Utils not found"; exit 1 }
namespace import ::CBFlow::Utilities::print_header
set config_file "$run_dir/work/FCFP/init_design/run/config.tcl"
if {[file exists $config_file]} { source $config_file }
global fcfp project tech flow
# Source FC tool config
set _tool_config "[file dirname [info script]]/fc_config.tcl"
if {[file exists $_tool_config]} { source $_tool_config }
handle_info "Starting FCFP init_design..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

# Source tech_config
if {[info exists ::env(TECH_NAME)] && $::env(TECH_NAME) ne "" &&
    [info exists ::env(TECH_VERSION)] && $::env(TECH_VERSION) ne ""} {
    set _tc "$::env(CONFIG_ROOT)/tech/$::env(TECH_NAME)/$::env(TECH_VERSION)/tech_config.tcl"
    if {[file exists $_tc]} { source -e $_tc }
}
# Source user_config for overrides
if {[file exists "$run_dir/setup/user_config.tcl"]} { source -e "$run_dir/setup/user_config.tcl" }

set WORK_DIR "$run_dir/work/FCFP/init_design1"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

# ==============================================================================
# flow_proc: create_design_library
# FC-RM: create_lib with technology file, NDM reference libraries
# ==============================================================================
flow_proc create_design_library {
    handle_info "Creating design library..."
    global fcfp tech flow

    set run_dir $::env(CBFLOW_RUN_DIR)
    file mkdir "$run_dir/work/FCFP/init_design/run"

    set design_name [expr {[info exists fc(common,design_name)] ? $fc(common,design_name) : $flow(design_name)}]
    set lib_name [expr {[info exists fc(common,design_lib_name)] ? $fc(common,design_lib_name) : "${design_name}.nlib"}]

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

    # Sub-block abstract NDM libs -- hierarchical DP flow
    if {[info exists fc(common,chip_type)] && $fc(common,chip_type) eq "hierarchical"} {
        if {[info exists tech(ndm,sub_blocks)] && [llength $tech(ndm,sub_blocks)] > 0} {
            foreach lib $tech(ndm,sub_blocks) {
                if {$lib ne ""} { lappend ref_libs $lib }
            }
            handle_info "Hierarchical flow: [llength $tech(ndm,sub_blocks)] sub-block libraries added"
        }
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
    global fcfp flow

    set design_name [expr {[info exists fc(common,design_name)] ? $fc(common,design_name) : $flow(design_name)}]

    if {[info exists fcfp(input,netlist)] && $fcfp(input,netlist) ne ""} {
        handle_info "Reading netlist: $fcfp(input,netlist)"
        read_verilog -top $design_name $fcfp(input,netlist)
    } elseif {[info exists fc(common,input_netlist)] && $fc(common,input_netlist) ne ""} {
        handle_info "Reading netlist: $fc(common,input_netlist)"
        read_verilog -top $design_name $fc(common,input_netlist)
    } else {
        handle_error "No netlist specified -- set fcfp(input,netlist) or fc(common,input_netlist)"
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
    global fcfp tech

    set tech_node ""
    if {[info exists fc(common,technology_node)] && $fc(common,technology_node) ne ""} {
        set tech_node $fc(common,technology_node)
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
        source -e $tech(tech_setup_script)
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
    global fcfp

    # Read SDC
    if {[info exists fcfp(input,sdc_file)] && $fcfp(input,sdc_file) ne ""} {
        if {[file exists $fcfp(input,sdc_file)]} {
            handle_info "Reading SDC: $fcfp(input,sdc_file)"
            read_sdc $fcfp(input,sdc_file)
        }
    } elseif {[info exists fc(common,input_sdc)] && $fc(common,input_sdc) ne ""} {
        foreach sdc_file $fc(common,input_sdc) {
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
            if {[info exists fc(common,input_upf_supplemental)] && [file exists $fc(common,input_upf_supplemental)]} {
                handle_info "Loading supplemental UPF: $fc(common,input_upf_supplemental)"
                load_upf -supplemental $fc(common,input_upf_supplemental)
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
    global fcfp

    if {[info exists fc(common,connect_pg_net_script)] && [file exists $fc(common,connect_pg_net_script)]} {
        source -e $fc(common,connect_pg_net_script)
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
    set design_name [expr {[info exists fc(common,design_name)] ? $fc(common,design_name) : $flow(design_name)}]

    if {[info exists fcfp(input,upf_file)] && $fcfp(input,upf_file) ne ""} {
        save_upf ${run_dir}/outputs/init_design.save_upf
    }

    save_lib -all
    save_block
    save_block -as ${design_name}/init_design
    handle_info "Block saved: ${design_name}/init_design"

    # Set SVF for formal verification
    if {[info exists fc(common,svf_file)] && $fc(common,svf_file) ne ""} {
        set_svf $fc(common,svf_file)
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

    set max_paths [expr {[info exists fc(analysis,max_paths)] ? $fc(analysis,max_paths) : 100}]

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
# Source setup.tcl and overrides before flow_exec_all
# ==============================================================================
set _setup_file "$run_dir/work/FCFP/init_design/run/setup.tcl"
if {[file exists $_setup_file]} { handle_info "Sourcing setup hooks: $_setup_file"; source $_setup_file }
set _override_file "$run_dir/setup/override_setup.tcl"
if {[file exists $_override_file]} { handle_info "Sourcing user override: $_override_file"; source $_override_file }
set _stage_override "$run_dir/setup/override_setup.init_design.tcl"
if {[file exists $_stage_override]} { handle_info "Sourcing stage override: $_stage_override"; source $_stage_override }

flow_exec_all

# Exit tool after stage completion
exit
