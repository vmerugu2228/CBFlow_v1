#!/usr/bin/env tclsh
# CBFlow FCFP inputs - Synopsys Fusion Compiler

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "FCFP"
set STAGE_NAME "inputs"
set NODE_NAME "${STAGE_NAME}1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# ==============================================================================
flow_proc resolve_inputs {
    handle_info "Resolving input files..."
    global fcfp flow project
    if {![namespace exists ::CBFlow::InputResolve]} { return }
    handle_info "Input resolution completed"
}

flow_proc setup_dirs {
    handle_info "Setting up FCFP input directories..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    foreach dir {
        "work/FCFP/inputs/netlist"
        "work/FCFP/inputs/sdc"
        "work/FCFP/inputs/def"
        "work/FCFP/inputs/upf"
        "work/FCFP/inputs/library"
        "work/FCFP/inputs/lef"
        "work/FCFP/inputs/partitions"
        "logs/inputs"
        "reports/fcfp"
        "results/fcfp"
    } {
        file mkdir "$run_dir/$dir"
    }
    handle_info "FCFP input directories created"
}

# ==============================================================================
# flow_proc: read_libraries
# Read technology libraries, LEFs, and standard cell libraries
# ==============================================================================
flow_proc read_libraries {
    handle_info "Reading libraries for Fusion Compiler..."
    global fcfp tech

    set run_dir $::env(CBFLOW_RUN_DIR)

    set lib_name [expr {[info exists fcfp(common,DESIGN_LIB)] ? $fcfp(common,DESIGN_LIB) : "FCFP_DESIGN_LIB"}]

    if {[info exists tech(TECH_FILE)] && $tech(TECH_FILE) ne ""} {
        handle_info "Reading tech file: $tech(TECH_FILE)"
        create_lib $lib_name -technology $tech(TECH_FILE)
    }

    if {[info exists tech(REFERENCE_LIBRARY)]} {
        foreach ref_lib $tech(REFERENCE_LIBRARY) {
            handle_info "Reading reference library: $ref_lib"
            set_ref_libs -add $ref_lib
        }
    }

    if {[info exists tech(LEF_FILES)]} {
        foreach lef $tech(LEF_FILES) {
            handle_info "Reading LEF: $lef"
            read_lef $lef
        }
    } else {
        foreach lef [glob -nocomplain "$run_dir/work/FCFP/inputs/lef/*.lef"] {
            handle_info "Reading LEF: $lef"
            read_lef $lef
        }
    }

    handle_info "Libraries loaded"
}

# ==============================================================================
# flow_proc: read_hierarchical_design
# Read top-level and partition Verilog netlists
# ==============================================================================
flow_proc read_hierarchical_design {
    handle_info "Reading hierarchical design..."
    global fcfp project

    set run_dir $::env(CBFLOW_RUN_DIR)
    set netlist_dir "$run_dir/work/FCFP/inputs/netlist"
    set partition_dir "$run_dir/work/FCFP/inputs/partitions"

    # Read top-level netlist
    if {[info exists fcfp(common,TOP_NETLIST)]} {
        set top_netlist $fcfp(common,TOP_NETLIST)
    } else {
        set top_netlist [glob -nocomplain "$netlist_dir/*.v" "$netlist_dir/*.sv"]
    }
    foreach nf $top_netlist {
        handle_info "Reading top-level Verilog: $nf"
        read_verilog $nf
    }

    # Read partition netlists
    if {[info exists fcfp(common,PARTITION_NETLISTS)]} {
        set part_netlists $fcfp(common,PARTITION_NETLISTS)
    } else {
        set part_netlists [glob -nocomplain "$partition_dir/*.v" "$partition_dir/*.sv"]
    }
    foreach pf $part_netlists {
        handle_info "Reading partition Verilog: $pf"
        read_verilog $pf
    }

    # Link design
    if {[info exists fcfp(common,TOP_MODULE)]} {
        set top $fcfp(common,TOP_MODULE)
    } elseif {[info exists project(DESIGN_NAME)]} {
        set top $project(DESIGN_NAME)
    } else {
        handle_error "TOP_MODULE not defined"
        return -code error "Missing TOP_MODULE"
    }

    handle_info "Linking hierarchical design: $top"
    link_design $top
    handle_info "Hierarchical design loaded and linked"
}

# ==============================================================================
# flow_proc: read_constraints
# Read SDC timing constraints and UPF power intent
# ==============================================================================
flow_proc read_constraints {
    handle_info "Reading constraints..."
    global fcfp

    set run_dir $::env(CBFLOW_RUN_DIR)
    set sdc_dir "$run_dir/work/FCFP/inputs/sdc"

    if {[info exists fcfp(common,SDC_FILES)]} {
        set sdc_files $fcfp(common,SDC_FILES)
    } else {
        set sdc_files [glob -nocomplain "$sdc_dir/*.sdc"]
    }
    foreach sdc $sdc_files {
        handle_info "Reading SDC: $sdc"
        read_sdc $sdc
    }

    if {[info exists fcfp(common,UPF_FILE)] && $fcfp(common,UPF_FILE) ne ""} {
        handle_info "Reading UPF: $fcfp(common,UPF_FILE)"
        load_upf $fcfp(common,UPF_FILE)
        commit_upf
    }

    if {[info exists fcfp(common,SCENARIO_SETUP)] && [file exists $fcfp(common,SCENARIO_SETUP)]} {
        handle_info "Reading MCMM scenario setup: $fcfp(common,SCENARIO_SETUP)"
        source -e $fcfp(common,SCENARIO_SETUP)
    }

    handle_info "Constraints loaded"
}

# ==============================================================================
# flow_proc: validate
# Validate all FCFP inputs are loaded correctly
# ==============================================================================
flow_proc validate {
    handle_info "Validating FCFP inputs..."
    global fcfp

    set run_dir $::env(CBFLOW_RUN_DIR)
    set errors 0

    set current [current_design]
    if {$current eq ""} {
        handle_error "No design linked"
        incr errors
    }

    set clocks [all_clocks]
    if {[sizeof_collection $clocks] == 0} {
        handle_warning "No clocks defined"
    }

    set ref_libs [get_ref_libs -quiet]
    if {$ref_libs eq ""} {
        handle_warning "No reference libraries set"
    }

    set rpt [open "$::REPORTS_DIR/input_validation.rpt" w]
    puts $rpt "FCFP Input Validation Report - [clock format [clock seconds]]"
    puts $rpt "============================================================"
    puts $rpt "Design:     $current"
    puts $rpt "Clocks:     [sizeof_collection $clocks]"
    puts $rpt "Ref libs:   $ref_libs"
    puts $rpt "Errors:     $errors"
    close $rpt

    if {$errors > 0} {
        return -code error "FCFP input validation failed"
    }
    handle_info "FCFP input validation passed"
}

# ==============================================================================
# flow_proc: set_dp_qor_strategy
# Set QoR strategy for compile_initial stage
# ==============================================================================
flow_proc set_dp_qor_strategy {
    handle_info "Setting QoR strategy for DP compile_initial stage..."
    global fcfp

    set qor_cmd "set_qor_strategy -stage compile_initial"

    if {[info exists fcfp(compile,qor_metric)] && $fcfp(compile,qor_metric) ne ""} {
        lappend qor_cmd -metric $fcfp(compile,qor_metric)
    } else {
        lappend qor_cmd -metric timing
    }

    if {[info exists fcfp(compile,reduced_effort)] && $fcfp(compile,reduced_effort)} {
        lappend qor_cmd -reduced_effort
    }

    if {[info exists fcfp(compile,active_scenarios)] && $fcfp(compile,active_scenarios) ne ""} {
        set_scenario_status -active false [get_scenarios -filter active]
        set_scenario_status -active true $fcfp(compile,active_scenarios)
    }

    handle_info "Running: $qor_cmd"
    eval $qor_cmd

    set rm_lib_type [get_attribute -quiet [current_design] rm_lib_type]
    if {$rm_lib_type ne "" && [regexp {h$} $rm_lib_type]} {
        handle_info "Hybrid library detected -- setting congestion_driven_max_util to 0.85"
        set_app_options -name place.coarse.congestion_driven_max_util -value 0.85
        eval $qor_cmd
    }

    handle_info "DP QoR strategy set"
}

# ==============================================================================
# flow_proc: run_early_compile
# Run early compile_fusion for area estimation before floorplanning
# ==============================================================================
flow_proc run_early_compile {
    handle_info "Running early compile_fusion for area estimation..."
    global fcfp

    set early_stage [expr {[info exists fcfp(compile,early_stage)] && $fcfp(compile,early_stage) ne "" ? $fcfp(compile,early_stage) : "initial_map"}]

    handle_info "compile_fusion -to $early_stage"
    compile_fusion -to $early_stage

    change_names -rules verilog -hierarchy -skip_physical_only_cells
    handle_info "Early compile ($early_stage) completed"
}

# ==============================================================================
# flow_proc: connect_pg_dp
# Connect PG nets after early compile
# ==============================================================================
flow_proc connect_pg_dp {
    handle_info "Connecting PG nets after early compile..."
    connect_pg_net
    handle_info "PG nets connected"
}

# ==============================================================================
# ==============================================================================

flow_exec_all

# Exit tool after stage completion
exit
