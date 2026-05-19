#!/usr/bin/env tclsh
# CBFlow FCFP commit_blocks - Synopsys Fusion Compiler
# FC-RM: commit_blocks.tcl -- Block reference creation, constraint splitting,
#         and sub-block preparation for hierarchical DP
# Aligned with FC-RM Y-2026.03
set run_dir $::env(CBFLOW_RUN_DIR)
set env_file "$run_dir/.run.cbflow.tcl"
if {[file exists $env_file]} { source $env_file } else { puts stderr "ERROR: .run.cbflow.tcl not found"; exit 1 }
if {[info exists ::env(FLOW_DIR)]} { set FLOW_DIR $::env(FLOW_DIR) } else { puts stderr "ERROR: FLOW_DIR not set"; exit 1 }
if {![info exists ::env(UTILITIES_VERSION)] || $::env(UTILITIES_VERSION) eq ""} { puts stderr "ERROR: UTILITIES_VERSION not set"; exit 1 }
set utils_path "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} { source $utils_path } else { puts stderr "ERROR: Utils not found"; exit 1 }
namespace import ::CBFlow::Utilities::print_header
set config_file "$run_dir/work/$::env(CBFLOW_FLOW_TYPE)/$::env(CBFLOW_NODE_NAME)/run/config.tcl"
if {[file exists $config_file]} { source $config_file }
global fcfp project tech flow
# Source FC tool config
set _tool_config "[file dirname [info script]]/fc_config.tcl"
if {[file exists $_tool_config]} { source $_tool_config }
handle_info "Starting FCFP commit_blocks..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

# Source tech_config
if {[info exists ::env(TECH_NAME)] && $::env(TECH_NAME) ne "" &&
    [info exists ::env(TECH_VERSION)] && $::env(TECH_VERSION) ne ""} {
    set _tc "$::env(CONFIG_ROOT)/tech/$::env(TECH_NAME)/$::env(TECH_VERSION)/tech_config.tcl"
    if {[file exists $_tc]} { source -e $_tc }
}

set WORK_DIR "$run_dir/work/FCFP/commit_blocks1"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

# ==============================================================================
# flow_proc: load_design
# Open the design library and block from init_design
# ==============================================================================
flow_proc load_design {
    handle_info "Loading design for commit_blocks..."
    global fcfp flow

    set design_name [expr {[info exists fc(common,design_name)] ? $fc(common,design_name) : $flow(design_name)}]

    if {[info exists fc(common,open_lib)] && $fc(common,open_lib) ne ""} {
        open_lib $fc(common,open_lib)
    }

    if {[info exists fc(copy_block,from)] && $fc(copy_block,from) ne ""} {
        copy_block -from $fc(copy_block,from) -to ${design_name}/commit_blocks
        current_block ${design_name}/commit_blocks
    } else {
        open_block ${design_name}/init_design
        copy_block -from ${design_name}/init_design -to ${design_name}/commit_blocks
        current_block ${design_name}/commit_blocks
    }

    link_block
    handle_info "Design loaded: $design_name"
}

# ==============================================================================
# flow_proc: create_block_refs
# FC-RM: Create block references for sub-blocks, power domain mapping
# ==============================================================================
flow_proc create_block_refs {
    handle_info "Creating block references..."
    global fcfp

    # Get sub-block list
    if {[info exists fc(common,sub_blocks)] && [llength $fc(common,sub_blocks)] > 0} {
        foreach block $fc(common,sub_blocks) {
            handle_info "Creating block reference for: $block"
            create_block -hier $block
        }
    }

    # Power domain mapping for sub-blocks
    if {[info exists fc(common,power_domain_map_script)] && [file exists $fc(common,power_domain_map_script)]} {
        handle_info "Sourcing power domain map: $fc(common,power_domain_map_script)"
        source -e $fc(common,power_domain_map_script)
    }

    # Commit blocks
    if {[info exists fc(common,commit_block_list)] && [llength $fc(common,commit_block_list)] > 0} {
        foreach block $fc(common,commit_block_list) {
            handle_info "Committing block: $block"
            commit_block -block_ref $block
        }
    } else {
        commit_block
    }

    handle_info "Block references created and committed"
}

# ==============================================================================
# flow_proc: split_constraints
# FC-RM: Split SDC/UPF constraints for each sub-block
# ==============================================================================
flow_proc split_constraints {
    handle_info "Splitting constraints for sub-blocks..."
    global fcfp

    set run_dir $::env(CBFLOW_RUN_DIR)
    set split_dir "$run_dir/results/fcfp/split_constraints"
    file mkdir $split_dir

    if {[info exists fc(common,split_constraints_script)] && [file exists $fc(common,split_constraints_script)]} {
        source -e $fc(common,split_constraints_script)
    } else {
        # Auto-split constraints per sub-block
        if {[info exists fc(common,sub_blocks)] && [llength $fc(common,sub_blocks)] > 0} {
            foreach block $fc(common,sub_blocks) {
                file mkdir "$split_dir/$block"
                handle_info "Splitting constraints for: $block"
                catch {
                    write_sdc -block $block "$split_dir/$block/${block}.sdc"
                }
                catch {
                    save_upf -block $block "$split_dir/$block/${block}.upf"
                }
            }
        }
    }

    handle_info "Constraint splitting completed"
}

# ==============================================================================
# flow_proc: save_design
# FC-RM: save_lib, save_block
# ==============================================================================
flow_proc save_design {
    handle_info "Saving commit_blocks..."
    global fcfp flow

    set design_name [expr {[info exists fc(common,design_name)] ? $fc(common,design_name) : $flow(design_name)}]

    save_lib -all
    save_block
    save_block -as ${design_name}/commit_blocks
    handle_info "Block saved: ${design_name}/commit_blocks"
}

# ==============================================================================
# flow_proc: generate_reports
# ==============================================================================
flow_proc generate_reports {
    handle_info "Generating commit_blocks reports..."
    global fcfp

    redirect -file $::REPORTS_DIR/report_design.rpt { report_design -physical }
    redirect -file $::REPORTS_DIR/report_blocks.rpt { report_blocks }
    redirect -file $::REPORTS_DIR/report_utilization.rpt { report_utilization }
    redirect -file $::REPORTS_DIR/report_msg_summary.rpt { report_msg -summary }

    handle_info "Commit_blocks reports generated in: $::REPORTS_DIR"
}

# ==============================================================================
# Source setup.tcl and overrides before flow_exec_all
# ==============================================================================
set _setup_file "$run_dir/work/$::env(CBFLOW_FLOW_TYPE)/$::env(CBFLOW_NODE_NAME)/run/setup.tcl"
if {[file exists $_setup_file]} { handle_info "Sourcing setup hooks: $_setup_file"; source $_setup_file }
set _override_file "$run_dir/setup/override_setup.tcl"
if {[file exists $_override_file]} { handle_info "Sourcing user override: $_override_file"; source $_override_file }
set _stage_override "$run_dir/setup/override_setup.commit_blocks.tcl"
if {[file exists $_stage_override]} { handle_info "Sourcing stage override: $_stage_override"; source $_stage_override }

flow_exec_all

# Exit tool after stage completion
exit
