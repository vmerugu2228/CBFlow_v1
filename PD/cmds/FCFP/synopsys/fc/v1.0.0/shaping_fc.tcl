#!/usr/bin/env tclsh
# CBFlow FCFP shaping - Synopsys Fusion Compiler

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "FCFP"
set STAGE_NAME "shaping"
set NODE_NAME "${STAGE_NAME}1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# ==============================================================================
# flow_proc: load_design
# ==============================================================================
flow_proc load_design {
    handle_info "Loading design for shaping..."
    global fcfp flow

    set design_name [expr {[info exists fcfp(common,design_name)] ? $fcfp(common,design_name) : $flow(design_name)}]

    if {[info exists fcfp(common,open_lib)] && $fcfp(common,open_lib) ne ""} {
        open_lib $fcfp(common,open_lib)
    }

    set from_label [expr {[info exists fcfp(shaping,from_label)] ? $fcfp(shaping,from_label) : "create_floorplan"}]
    copy_block -from ${design_name}/${from_label} -to ${design_name}/shaping
    current_block ${design_name}/shaping
    link_block

    handle_info "Design loaded: $design_name"
}

# ==============================================================================
# flow_proc: shape_blocks
# FC-RM: shape_blocks with channel/non-channel style
# ==============================================================================
flow_proc shape_blocks {
    handle_info "Shaping blocks..."
    global fcfp

    # Source pre-shaping constraints
    if {[info exists fcfp(shaping,constraint_script)] && [file exists $fcfp(shaping,constraint_script)]} {
        source -e $fcfp(shaping,constraint_script)
        handle_info "Shaping constraints loaded"
    }

    # Determine shaping style: channel (default) or non-channel
    set shaping_style "channel"
    if {[info exists fcfp(shaping,style)] && $fcfp(shaping,style) ne ""} {
        set shaping_style $fcfp(shaping,style)
    }

    set shape_cmd "shape_blocks"

    if {$shaping_style eq "non-channel"} {
        lappend shape_cmd -channels false
    }

    # Target utilization for shaping
    if {[info exists fcfp(shaping,target_utilization)] && $fcfp(shaping,target_utilization) ne ""} {
        lappend shape_cmd -core_utilization $fcfp(shaping,target_utilization)
    }

    # Min/max size constraints
    if {[info exists fcfp(shaping,min_width)] && $fcfp(shaping,min_width) ne ""} {
        lappend shape_cmd -min_width $fcfp(shaping,min_width)
    }
    if {[info exists fcfp(shaping,min_height)] && $fcfp(shaping,min_height) ne ""} {
        lappend shape_cmd -min_height $fcfp(shaping,min_height)
    }

    handle_info "Running: $shape_cmd (style=$shaping_style)"
    eval $shape_cmd

    handle_info "Block shaping completed"
}

# ==============================================================================
# flow_proc: check_shaping
# FC-RM: check_floorplan_rules after shaping
# ==============================================================================
flow_proc check_shaping {
    handle_info "Checking shaping results..."
    global fcfp

    redirect -file $::REPORTS_DIR/check_floorplan_rules.shaping {
        check_floorplan_rules
    }

    redirect -file $::REPORTS_DIR/report_placement.shaping {
        report_placement -physical_hierarchy_violations all -wirelength all
    }

    redirect -file $::REPORTS_DIR/report_utilization.shaping {
        report_utilization
    }

    handle_info "Shaping checks completed"
}

# ==============================================================================
# flow_proc: create_abstracts
# FC-RM: create_abstract for sub-blocks after shaping
# ==============================================================================
flow_proc create_abstracts {
    handle_info "Creating abstracts after shaping..."
    global fcfp

    create_abstract
    handle_info "Abstracts created"
}

# ==============================================================================
# flow_proc: save_design
# ==============================================================================
flow_proc save_design {
    handle_info "Saving shaping block..."
    global fcfp flow

    set design_name [expr {[info exists fcfp(common,design_name)] ? $fcfp(common,design_name) : $flow(design_name)}]

    save_lib -all
    save_block
    save_block -as ${design_name}/shaping
    handle_info "Block saved: ${design_name}/shaping"
}

# ==============================================================================
# flow_proc: generate_reports
# ==============================================================================
flow_proc generate_reports {
    handle_info "Generating shaping reports..."
    global fcfp

    set max_paths [expr {[info exists fcfp(analysis,max_paths)] ? $fcfp(analysis,max_paths) : 100}]

    redirect -file $::REPORTS_DIR/report_qor.rpt { report_qor }
    redirect -file $::REPORTS_DIR/report_timing.rpt {
        report_timing -max_paths $max_paths -delay_type max
    }
    redirect -file $::REPORTS_DIR/report_design.rpt { report_design -physical }
    redirect -file $::REPORTS_DIR/report_msg_summary.rpt { report_msg -summary }

    handle_info "Shaping reports generated in: $::REPORTS_DIR"
}

# ==============================================================================
# ==============================================================================

flow_exec_all

# Exit tool after stage completion
exit
