#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow - LEC Compare Command File
# Description: Logic equivalence comparison between golden and revised designs
# Tool: Synopsys Formality
# Based on: FC-RM Y-2026.03 fm_r2g.tcl
# Usage: Source this file in Formality or run standalone
# ═══════════════════════════════════════════════════════════════════════════════

# Source environment variables
set run_dir $::env(CBFLOW_RUN_DIR)
set env_file "$run_dir/.run.cbflow.tcl"

if {[file exists $env_file]} {
    source -e $env_file
} else {
    puts stderr "ERROR: Environment file (.run.cbflow.tcl) not found at $env_file"
    exit 1
}

# Source flow utilities
if {[info exists ::env(FLOW_DIR)]} {
    set FLOW_DIR $::env(FLOW_DIR)
} else {
    puts stderr "ERROR: FLOW_DIR not found in environment"
    exit 1
}

if {![info exists ::env(UTILITIES_VERSION)] || $::env(UTILITIES_VERSION) eq ""} {
    puts stderr "ERROR: UTILITIES_VERSION not set."
    exit 1
}

set utils_path "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} {
    source -e $utils_path
} else {
    puts stderr "ERROR: Cannot find flow utilities at $utils_path"
    exit 1
}

namespace import ::CBFlow::Utilities::print_header

# Source generated configuration file
set config_file "$run_dir/work/LEC/compare1/run/config.tcl"
if {[file exists $config_file]} {
    source -e $config_file
}

# Source tech_config
if {[info exists ::env(TECH_NAME)] && $::env(TECH_NAME) ne "" && [info exists ::env(TECH_VERSION)]} {
    set _tc "$::env(CONFIG_ROOT)/tech/$::env(TECH_NAME)/$::env(TECH_VERSION)/tech_config.tcl"
    if {[file exists $_tc]} { source -e $_tc }
}

# Source user_config for overrides
if {[file exists "$run_dir/setup/user_config.tcl"]} { source -e "$run_dir/setup/user_config.tcl" }

# Declare global arrays
global lec project tech flow

# Source FORMALITY tool config
set _tool_config "[file dirname [info script]]/formality_config.tcl"
if {[file exists $_tool_config]} { source $_tool_config }
handle_info "Starting LEC compare stage with Synopsys Formality..."

# Initialize flow namespace
if {![namespace exists ::flow]} {
    namespace eval ::flow {
        variable exec_mode "auto"
        variable current_stage ""
        variable start_time [clock seconds]
        variable flow_errors {}
    }
}

set ::flow::exec_mode "auto"

# ── Directories ──────────────────────────────────────────────────────────────
set WORK_DIR "$run_dir/work/LEC/compare1"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                       SETUP LIBRARIES                                      │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc setup_libraries {
    global lec project tech
    handle_info "Setting up reference libraries for Formality..."

    set run_dir $::env(CBFLOW_RUN_DIR)
    file mkdir $::REPORTS_DIR
    file mkdir $::OUTPUTS_DIR

    # Enable Synopsys auto setup mode
    set_app_var synopsys_auto_setup true

    # Read fusion reference library (NDM/db)
    if {[info exists lec(input,ref_lib)] && $lec(input,ref_lib) ne ""} {
        if {[file exists [which $lec(input,ref_lib)]]} {
            handle_info "Reading fusion reference library: $lec(input,ref_lib)"
            read_db -flib [which $lec(input,ref_lib)]
        } else {
            handle_error "Reference library not found: $lec(input,ref_lib)"
        }
    } elseif {[info exists lec(input,link_library)] && $lec(input,link_library) ne ""} {
        # Fallback to individual technology libraries
        foreach tech_lib $lec(input,link_library) {
            handle_info "Reading technology library: $tech_lib"
            read_db -technology_library $tech_lib
        }
    } elseif {[info exists tech(lib,reference_library)] && $tech(lib,reference_library) ne ""} {
        handle_info "Reading fusion reference library from tech config: $tech(lib,reference_library)"
        read_db -flib [which $tech(lib,reference_library)]
    }

    # Set link_library if specified
    if {[info exists lec(input,link_library_list)] && $lec(input,link_library_list) ne ""} {
        set_app_var link_library $lec(input,link_library_list)
    }

    handle_info "Library setup completed"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                    READ REFERENCE DESIGN                                   │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc read_reference_design {
    global lec project tech
    handle_info "Reading reference (golden) design..."

    set design_name $project(top_module)

    if {[info exists lec(input,netlist_golden)] && $lec(input,netlist_golden) ne ""} {
        # Reference is a netlist (gate-level or from prior PNR stage)
        handle_info "Reading golden netlist: $lec(input,netlist_golden)"
        read_verilog -r $lec(input,netlist_golden)
        set_top r:/WORK/${design_name}
    } elseif {[info exists lec(input,rtl_files)] && $lec(input,rtl_files) ne ""} {
        # Reference is RTL source
        set rtl_format "sverilog"
        if {[info exists lec(input,rtl_format)] && $lec(input,rtl_format) ne ""} {
            set rtl_format $lec(input,rtl_format)
        }
        switch $rtl_format {
            sverilog {
                handle_info "Reading RTL (SystemVerilog): $lec(input,rtl_files)"
                read_sverilog -r $lec(input,rtl_files) -work_library WORK
            }
            verilog {
                handle_info "Reading RTL (Verilog): $lec(input,rtl_files)"
                read_verilog -r $lec(input,rtl_files) -work_library WORK
            }
            vhdl {
                handle_info "Reading RTL (VHDL): $lec(input,rtl_files)"
                read_vhdl -r $lec(input,rtl_files) -work_library WORK
            }
            default {
                handle_error "Unknown RTL format: $rtl_format"
            }
        }
        set set_top_cmd "set_top r:/WORK/${design_name}"
        if {[info exists lec(input,set_top_args)] && $lec(input,set_top_args) ne ""} {
            lappend set_top_cmd $lec(input,set_top_args)
        }
        handle_info "Running: $set_top_cmd"
        eval $set_top_cmd
    } elseif {[info exists lec(input,ref_ndm)] && $lec(input,ref_ndm) ne ""} {
        # Reference is an NDM block
        set read_ndm_cmd "read_ndm -r $lec(input,ref_ndm) -block ${design_name}/$lec(input,ref_ndm_block)"
        handle_info "Running: $read_ndm_cmd"
        eval $read_ndm_cmd
    } else {
        handle_error "No reference design specified. Set lec(input,netlist_golden), lec(input,rtl_files), or lec(input,ref_ndm)."
    }

    handle_info "Reference design read completed"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                 READ IMPLEMENTATION DESIGN                                 │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc read_implementation_design {
    global lec project tech
    handle_info "Reading implementation (revised) design..."

    set design_name $project(top_module)

    if {[info exists lec(input,netlist_revised)] && $lec(input,netlist_revised) ne ""} {
        handle_info "Reading revised netlist: $lec(input,netlist_revised)"
        read_verilog -i $lec(input,netlist_revised)
    } elseif {[info exists lec(input,imp_ndm)] && $lec(input,imp_ndm) ne ""} {
        set read_ndm_cmd "read_ndm -i $lec(input,imp_ndm) -block ${design_name}/$lec(input,imp_ndm_block)"
        handle_info "Running: $read_ndm_cmd"
        eval $read_ndm_cmd
    } else {
        handle_error "No implementation netlist specified. Set lec(input,netlist_revised) or lec(input,imp_ndm)."
    }

    set_top i:/WORK/${design_name}

    handle_info "Implementation design read completed"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                    LOAD POWER INTENT                                       │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc load_power_intent {
    global lec project tech
    handle_info "Loading power intent (UPF/SVF)..."

    # Load SVF guidance file
    if {[info exists lec(input,svf_file)] && $lec(input,svf_file) ne ""} {
        if {[file exists [which $lec(input,svf_file)]]} {
            handle_info "Setting SVF: $lec(input,svf_file)"
            set_svf $lec(input,svf_file)
        } else {
            handle_warning "SVF file not found: $lec(input,svf_file)"
        }
    }

    # Load UPF for multi-voltage designs
    set upf_mode "none"
    if {[info exists lec(input,upf_mode)] && $lec(input,upf_mode) ne ""} {
        set upf_mode $lec(input,upf_mode)
    }

    if {$upf_mode ne "none" && [info exists lec(input,upf_file)] && $lec(input,upf_file) ne ""} {
        switch $upf_mode {
            prime {
                handle_info "Loading UPF (prime mode) for reference: $lec(input,upf_file)"
                load_upf -r $lec(input,upf_file)
                # Implementation UPF
                if {[info exists lec(input,upf_file_impl)] && $lec(input,upf_file_impl) ne ""} {
                    handle_info "Loading UPF (prime mode) for implementation: $lec(input,upf_file_impl)"
                    load_upf -i $lec(input,upf_file_impl) -target dc_netlist
                }
            }
            golden {
                handle_info "Loading UPF (golden mode) for reference: $lec(input,upf_file)"
                set load_upf_cmd "load_upf -r -strict_check false -target dc_pg_netlist $lec(input,upf_file)"
                if {[info exists lec(input,supplemental_upf)] && $lec(input,supplemental_upf) ne ""} {
                    lappend load_upf_cmd -supplemental $lec(input,supplemental_upf)
                }
                eval $load_upf_cmd
                # Implementation UPF (golden)
                if {[info exists lec(input,upf_file_impl)] && $lec(input,upf_file_impl) ne ""} {
                    set load_upf_impl_cmd "load_upf -i -strict_check false -target dc_netlist $lec(input,upf_file_impl)"
                    if {[info exists lec(input,supplemental_upf_impl)] && $lec(input,supplemental_upf_impl) ne ""} {
                        lappend load_upf_impl_cmd -supplemental $lec(input,supplemental_upf_impl)
                    }
                    eval $load_upf_impl_cmd
                }
            }
            default {
                handle_info "UPF mode set to '$upf_mode' -- no UPF loaded"
            }
        }
        # By default Formality verifies with all UPF supplies ON; FC-RM recommends false
        set_app_var verification_force_upf_supplies_on false
    }

    handle_info "Power intent loading completed"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                         RUN MATCH                                          │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc run_match {
    global lec project
    handle_info "Matching compare points between reference and implementation..."

    set run_dir $::env(CBFLOW_RUN_DIR)
    set design_name $project(top_module)

    # Run automatic compare-point matching
    match

    # Report unmatched points
    report_unmatched_points > "$::REPORTS_DIR/${design_name}.fmv_unmatched_points.rpt"

    handle_info "Compare point matching completed"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                        RUN VERIFY                                          │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc run_verify {
    global lec project
    handle_info "Running formal verification..."

    set run_dir $::env(CBFLOW_RUN_DIR)
    set design_name $project(top_module)

    if {![verify]} {
        handle_warning "Verification FAILED -- generating debug reports"
        set ::fm_passed FALSE
    } else {
        handle_info "Verification PASSED -- designs are logically equivalent"
        set ::fm_passed TRUE
    }

    # Always generate status report
    report_status > "$::REPORTS_DIR/${design_name}.report_status.rpt"

    handle_info "Formal verification completed (result: $::fm_passed)"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                    GENERATE REPORTS                                        │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc generate_reports {
    global lec project
    handle_info "Generating LEC reports..."

    set run_dir $::env(CBFLOW_RUN_DIR)
    set design_name $project(top_module)

    file mkdir $::REPORTS_DIR
    file mkdir $::OUTPUTS_DIR

    # Generate failing / aborted / analysis reports on failure
    if {[info exists ::fm_passed] && $::fm_passed eq "FALSE"} {
        report_failing_points > "$::REPORTS_DIR/${design_name}.fmv_failing_points.rpt"
        report_aborted        > "$::REPORTS_DIR/${design_name}.fmv_aborted_points.rpt"
        analyze_points -all   > "$::REPORTS_DIR/${design_name}.fmv_analyze_points.rpt"
    }

    # Summary result file
    set rpt "$::OUTPUTS_DIR/comparison.rpt"
    set fp [open $rpt w]
    puts $fp "==============================================================================="
    puts $fp "CBFlow LEC - Comparison Report (Synopsys Formality)"
    puts $fp "==============================================================================="
    puts $fp "Generated: [clock format [clock seconds]]"
    if {[info exists project(top_module)]} { puts $fp "Design: $project(top_module)" }
    if {[info exists project(name)]}       { puts $fp "Project: $project(name)" }
    puts $fp ""
    puts $fp "Verification Result: [expr {[info exists ::fm_passed] ? $::fm_passed : \"UNKNOWN\"}]"
    puts $fp ""
    puts $fp "Reports Generated:"
    puts $fp "  $::REPORTS_DIR/${design_name}.fmv_unmatched_points.rpt"
    puts $fp "  $::REPORTS_DIR/${design_name}.report_status.rpt"
    if {[info exists ::fm_passed] && $::fm_passed eq "FALSE"} {
        puts $fp "  $::REPORTS_DIR/${design_name}.fmv_failing_points.rpt"
        puts $fp "  $::REPORTS_DIR/${design_name}.fmv_aborted_points.rpt"
        puts $fp "  $::REPORTS_DIR/${design_name}.fmv_analyze_points.rpt"
    }
    close $fp

    handle_info "LEC reports generated in $::REPORTS_DIR"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                       SAVE SESSION                                         │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc save_session {
    global lec project
    handle_info "Saving Formality session for debug..."

    set run_dir $::env(CBFLOW_RUN_DIR)
    set design_name $project(top_module)

    # Save session on failure for interactive debug
    if {[info exists ::fm_passed] && $::fm_passed eq "FALSE"} {
        handle_info "Saving session to $::REPORTS_DIR/${design_name} for debug"
        save_session -replace $::REPORTS_DIR/${design_name}
    } else {
        handle_info "Verification passed -- session save skipped"
    }

    handle_info "Save session step completed"
}

# ==============================================================================
# Source setup.tcl and overrides before flow_exec_all
# ==============================================================================
set _setup_file "$run_dir/work/LEC/compare1/run/setup.tcl"
if {[file exists $_setup_file]} { handle_info "Sourcing setup hooks: $_setup_file"; source -e $_setup_file }
set _override_file "$run_dir/setup/override_setup.tcl"
if {[file exists $_override_file]} { handle_info "Sourcing user override: $_override_file"; source -e $_override_file }
set _stage_override "$run_dir/setup/override_setup.compare.tcl"
if {[file exists $_stage_override]} { handle_info "Sourcing stage override: $_stage_override"; source -e $_stage_override }

flow_exec_all
exit
