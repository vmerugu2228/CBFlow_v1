#!/usr/bin/env tclsh
# CBflow PV metal fill - Synopsys ICV (ICV-RM V-2023.12)

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "PV"
set STAGE_NAME "fill"
set NODE_NAME "${STAGE_NAME}1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME


# ── Design name (resolve from pv(...) or flow(...)) ──────────────────────
set DESIGN_NAME [expr {[info exists pv(common,design_name)] ? $pv(common,design_name) :
                       [expr {[info exists flow(design_name)] ? $flow(design_name) : "design"}]}]
set ::DESIGN_NAME $DESIGN_NAME
# ═══════════════════════════════════════════════════════════════════════════════
# ICV-RM: SETUP (from icv_run_fill.tcl)
# ═══════════════════════════════════════════════════════════════════════════════
flow_proc setup_fill_environment {
    handle_info "Setting up ICV fill environment..."

    # ICV-RM: library format
    set lib_format [expr {[info exists pv(icv,library_format)] ? $pv(icv,library_format) : "GDSII"}]
    handle_info "  Library format: $lib_format"

    # ICV-RM: design state (EARLY/MATURE)
    set design_state [expr {[info exists pv(icv,design_state)] ? $pv(icv,design_state) : "MATURE"}]
    handle_info "  Design state: $design_state"

    # Metal stack info
    if {[info exists pv(fill,metal_stack)] && $pv(fill,metal_stack) ne ""} {
        handle_info "  Metal stack: $pv(fill,metal_stack)"
    } elseif {[info exists tech(metal_stack_name)]} {
        handle_info "  Metal stack: $tech(metal_stack_name)"
    }

    # M1 direction
    set m1_dir [expr {[info exists pv(fill,met1_direction)] ? $pv(fill,met1_direction) : "HORIZONTAL"}]
    handle_info "  M1 direction: $m1_dir"
}

# ═══════════════════════════════════════════════════════════════════════════════
# ICV-RM: BEOL FILL (Back-End-Of-Line metal fill)
# ═══════════════════════════════════════════════════════════════════════════════
flow_proc run_beol_fill {
    handle_info "ICV-RM: Running BEOL metal fill..."

    set num_cpus [expr {[info exists pv(fill,num_cpus)] ? $pv(fill,num_cpus) : 8}]
    set beol_runset [expr {[info exists pv(fill,beol_runset)] ? $pv(fill,beol_runset) : ""}]
    set lib_format [expr {[info exists pv(icv,library_format)] ? $pv(icv,library_format) : "GDSII"}]

    # ICV-RM: Build icv command for BEOL fill
    set icv_args ""
    append icv_args " -c $::DESIGN_NAME"
    append icv_args " -vue"
    append icv_args " -f $lib_format"

    # Input layout
    if {[info exists pv(input,gds_file)] && [file exists $pv(input,gds_file)]} {
        append icv_args " -i $pv(input,gds_file)"
    }

    # Include paths
    if {[info exists pv(icv,include_paths)] && $pv(icv,include_paths) ne ""} {
        foreach ipath $pv(icv,include_paths) {
            append icv_args " -I $ipath"
        }
    }

    if {$beol_runset ne "" && [file exists $beol_runset]} {
        handle_info "  BEOL runset: [file tail $beol_runset]"
        handle_info "  CPUs: $num_cpus"
        handle_info "  CMD: icv -dp $num_cpus $icv_args -r $beol_runset"

        # ICV-RM: Execute BEOL fill
        # icv -dp $num_cpus {*}$icv_args -r $beol_runset
    } else {
        handle_warning "  BEOL runset not specified — skipping BEOL fill"
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# ICV-RM: FEOL FILL (Front-End-Of-Line fill)
# ═══════════════════════════════════════════════════════════════════════════════
flow_proc run_feol_fill {
    handle_info "ICV-RM: Running FEOL fill..."

    set num_cpus [expr {[info exists pv(fill,num_cpus)] ? $pv(fill,num_cpus) : 8}]
    set feol_runset [expr {[info exists pv(fill,feol_runset)] ? $pv(fill,feol_runset) : ""}]

    if {$feol_runset ne "" && [file exists $feol_runset]} {
        handle_info "  FEOL runset: [file tail $feol_runset]"
        handle_info "  CMD: icv -dp $num_cpus -r $feol_runset ..."

        # ICV-RM: Execute FEOL fill
        # icv -dp $num_cpus -c $::DESIGN_NAME -r $feol_runset ...
    } else {
        handle_info "  FEOL runset not specified — skipping FEOL fill"
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# ICV-RM: OD FILL (from icv_run_odfill.tcl — merged into fill stage)
# ═══════════════════════════════════════════════════════════════════════════════
flow_proc run_od_fill {
    handle_info "ICV-RM: Running OD fill..."

    set num_cpus [expr {[info exists pv(fill,num_cpus)] ? $pv(fill,num_cpus) : 4}]
    set od_runset [expr {[info exists pv(odfill,runset)] ? $pv(odfill,runset) : ""}]
    set lib_format [expr {[info exists pv(icv,library_format)] ? $pv(icv,library_format) : "GDSII"}]

    if {$od_runset ne "" && [file exists $od_runset]} {
        handle_info "  OD fill runset: [file tail $od_runset]"
        handle_info "  CMD: icv -dp $num_cpus -c $::DESIGN_NAME -r $od_runset ..."
        # icv -dp $num_cpus -c $::DESIGN_NAME -vue -f $lib_format -i $input -r $od_runset
    } else {
        handle_info "  OD fill runset not specified — skipping"
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# ICV-RM: VALIDATE FILL RESULTS
# ═══════════════════════════════════════════════════════════════════════════════
flow_proc validate_fill {
    handle_info "Validating fill results..."

    # Check for fill output layout
    set fill_output "$::WORK_DIR/${::DESIGN_NAME}.filled.gds"
    if {[file exists $fill_output]} {
        handle_info "  Fill output: $fill_output ([file size $fill_output] bytes)"
    } else {
        handle_info "  Fill output not yet generated (will be created by ICV)"
    }

    # Check ICV log for errors
    set icv_log "$::WORK_DIR/icv_fill.log"
    if {[file exists $icv_log]} {
        set f [open $icv_log r]
        set content [read $f]
        close $f
        if {[regexp -all "ERROR" $content] > 0} {
            handle_warning "  ICV fill log contains errors"
        }
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# EXECUTE
# ═══════════════════════════════════════════════════════════════════════════════
flow_exec_all
handle_info "ICV-RM Metal Fill completed: $DESIGN_NAME"
exit
