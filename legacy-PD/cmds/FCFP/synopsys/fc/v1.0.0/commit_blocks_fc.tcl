#!/usr/bin/env tclsh
# CBFlow FCFP commit_blocks - Synopsys Fusion Compiler

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "FCFP"
set STAGE_NAME "commit_blocks"
set NODE_NAME "${STAGE_NAME}1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# ==============================================================================
flow_proc load_design {
    handle_info "Loading design for commit_blocks..."
    global fcfp flow

    set design_name [expr {[info exists fcfp(common,design_name)] ? $fcfp(common,design_name) : $flow(design_name)}]

    if {[info exists fcfp(common,open_lib)] && $fcfp(common,open_lib) ne ""} {
        open_lib $fcfp(common,open_lib)
    }

    if {[info exists fcfp(copy_block,from)] && $fcfp(copy_block,from) ne ""} {
        copy_block -from $fcfp(copy_block,from) -to ${design_name}/commit_blocks
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
    if {[info exists fcfp(common,sub_blocks)] && [llength $fcfp(common,sub_blocks)] > 0} {
        foreach block $fcfp(common,sub_blocks) {
            handle_info "Creating block reference for: $block"
            create_block -hier $block
        }
    }

    # Power domain mapping for sub-blocks
    if {[info exists fcfp(common,power_domain_map_script)] && [file exists $fcfp(common,power_domain_map_script)]} {
        handle_info "Sourcing power domain map: $fcfp(common,power_domain_map_script)"
        source $fcfp(common,power_domain_map_script)
    }

    # Commit blocks
    if {[info exists fcfp(common,commit_block_list)] && [llength $fcfp(common,commit_block_list)] > 0} {
        foreach block $fcfp(common,commit_block_list) {
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

    if {[info exists fcfp(common,split_constraints_script)] && [file exists $fcfp(common,split_constraints_script)]} {
        source $fcfp(common,split_constraints_script)
    } else {
        # Auto-split constraints per sub-block
        if {[info exists fcfp(common,sub_blocks)] && [llength $fcfp(common,sub_blocks)] > 0} {
            foreach block $fcfp(common,sub_blocks) {
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

    set design_name [expr {[info exists fcfp(common,design_name)] ? $fcfp(common,design_name) : $flow(design_name)}]

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
# ==============================================================================

flow_exec_all

# Exit tool after stage completion
exit
