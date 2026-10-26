#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow - SYNTH Flow Level Setup Hooks
# Description: SYNTH-specific flow_proc hooks that apply to ALL SYNTH flows
# Priority: Medium-High (overrides project, can be overridden by tool-specific setup)
# ═══════════════════════════════════════════════════════════════════════════════

handle_info "Loading SYNTH flow-level setup hooks"

# SYNTH flow initialization hooks
flow_proc_prepend flow_init {
    handle_info "SYNTH flow init prepend: Synthesis flow initialization"

    # Set SYNTH-specific environment
    if {![info exists ::env(SYNTH_FLOW_MODE)]} {
        set ::env(SYNTH_FLOW_MODE) "standard"
    }

    # Create SYNTH-specific directories
    set synth_dirs {
        "logs/synthesis"
        "reports/synthesis"
        "work/SYNTH"
        "results/synthesis"
    }

    foreach dir $synth_dirs {
        if {![file exists $dir]} {
            file mkdir $dir
            handle_info "Created SYNTH directory: $dir"
        }
    }
}

flow_proc_append flow_init {
    handle_info "SYNTH flow init append: Synthesis flow validation complete"

    # Validate SYNTH-specific configuration
    if {[info exists synth(stages)]} {
        handle_info "SYNTH flow stages: [join $synth(stages) {, }]"
    }
}

# SYNTH-specific library setup hooks
flow_proc_prepend setup_libraries {
    handle_info "SYNTH setup libraries prepend: Synthesis library validation"

    # Validate synthesis-specific library requirements
    if {[info exists tech(lib,timing)]} {
        handle_info "Synthesis timing libraries: configured"
    } else {
        add_flow_error "Missing synthesis timing libraries"
    }

    # Set synthesis-specific library variables
    if {[info exists tech(lib,timing)] && [info exists synth(library,effort)]} {
        handle_info "Synthesis library effort: $synth(library,effort)"
    }
}

flow_proc_append setup_libraries {
    handle_info "SYNTH setup libraries append: Synthesis library setup validation"

    # Validate library loading for synthesis
    if {[info exists tech(lib,timing)]} {
        # Check if libraries are accessible
        set lib_files [expr {[string match "*{*}*" $tech(lib,timing)] ? $tech(lib,timing) : [list $tech(lib,timing)]}]
        set valid_libs 0
        foreach lib $lib_files {
            if {[file exists [file join $ROOT_DIR $lib]]} {
                incr valid_libs
            }
        }
        handle_info "SYNTH library validation: $valid_libs/[llength $lib_files] libraries accessible"
    }
}

# SYNTH-specific RTL processing hooks
flow_proc_prepend read_rtl_files {
    handle_info "SYNTH read RTL prepend: Synthesis RTL validation"

    # Validate RTL input configuration
    set rtl_methods 0
    if {[info exists synth(input,rtl_release_tag)]} { incr rtl_methods }
    if {[info exists synth(input,rtl_release_dir)]} { incr rtl_methods }
    if {[info exists synth(input,rtl_filelist)]} { incr rtl_methods }

    if {$rtl_methods == 0} {
        add_flow_error "No RTL input method configured for synthesis"
    } elseif {$rtl_methods > 1} {
        handle_warning "Multiple RTL input methods configured - using priority order"
    }
}

flow_proc_append read_rtl_files {
    handle_info "SYNTH read RTL append: Synthesis RTL processing validation"

    # Validate RTL files were processed
    if {[file exists "work/SYNTH/inputs/rtl"]} {
        set rtl_count [llength [glob -nocomplain "work/SYNTH/inputs/rtl/*"]]
        if {$rtl_count > 0} {
            handle_info "SYNTH RTL validation: $rtl_count files processed"
        } else {
            add_flow_error "No RTL files found after processing"
        }
    }
}

# SYNTH-specific constraint processing hooks
flow_proc_prepend read_constraints {
    handle_info "SYNTH read constraints prepend: Synthesis constraint validation"

    # Validate constraint input configuration
    set sdc_methods 0
    if {[info exists synth(input,sdc_release_tag)]} { incr sdc_methods }
    if {[info exists synth(input,sdc_release_dir)]} { incr sdc_methods }
    if {[info exists synth(input,sdc_func_file)]} { incr sdc_methods }

    if {$sdc_methods == 0} {
        handle_warning "No SDC input method configured - synthesis may not meet timing"
    }
}

flow_proc_append read_constraints {
    handle_info "SYNTH read constraints append: Synthesis constraint validation"

    # Validate constraints were loaded
    if {[file exists "work/SYNTH/inputs/constraints"]} {
        set sdc_count [llength [glob -nocomplain "work/SYNTH/inputs/constraints/*.sdc"]]
        handle_info "SYNTH constraint validation: $sdc_count SDC files loaded"
    }
}

# SYNTH-specific synthesis hooks
flow_proc_prepend synthesize_design {
    handle_info "SYNTH synthesize design prepend: Pre-synthesis validation"

    # Validate synthesis prerequisites
    set prerequisites_ok true

    # Check if libraries are loaded
    if {![info exists tech(lib,timing)]} {
        add_flow_error "Libraries not configured for synthesis"
        set prerequisites_ok false
    }

    # Check if RTL is loaded
    if {![file exists "work/SYNTH/inputs/rtl"] || [llength [glob -nocomplain "work/SYNTH/inputs/rtl/*"]] == 0} {
        add_flow_error "RTL files not available for synthesis"
        set prerequisites_ok false
    }

    if {$prerequisites_ok} {
        handle_info "SYNTH synthesis prerequisites validated"
    }
}

flow_proc_append synthesize_design {
    handle_info "SYNTH synthesize design append: Post-synthesis validation"

    # Validate synthesis outputs
    if {[file exists "results/netlist"]} {
        set netlist_files [glob -nocomplain "results/netlist/*.v"]
        if {[llength $netlist_files] > 0} {
            handle_info "SYNTH synthesis validation: Netlist generated successfully"
        } else {
            add_flow_error "SYNTH synthesis failed - no netlist generated"
        }
    }
}

# SYNTH-specific reporting hooks
flow_proc_append generate_reports {
    handle_info "SYNTH generate reports append: Synthesis-specific reporting"

    # Generate SYNTH flow summary
    set synth_summary "reports/synthesis/synth_flow_summary.rpt"
    if {[file exists "reports/synthesis"]} {
        set fp [open $synth_summary w]
        puts $fp "═══════════════════════════════════════════════════════════════════════════════"
        puts $fp "SYNTH Flow Summary Report"
        puts $fp "═══════════════════════════════════════════════════════════════════════════════"
        puts $fp "Generated: [clock format [clock seconds]]"

        # Report flow status
        if {[info exists ::flow::flow_errors] && [llength $::flow::flow_errors] > 0} {
            puts $fp "Flow Status: FAILED ([llength $::flow::flow_errors] errors)"
            puts $fp "Errors:"
            foreach error $::flow::flow_errors {
                puts $fp "  - $error"
            }
        } else {
            puts $fp "Flow Status: SUCCESS"
        }

        # Report key metrics
        if {[file exists "reports/synthesis/synth_qor.rpt"]} {
            puts $fp "QoR Report: Available"
        }
        if {[file exists "results/netlist/synth.v"]} {
            puts $fp "Netlist: Generated"
        }
        close $fp

        handle_info "SYNTH flow summary generated: $synth_summary"
    }
}

handle_info "SYNTH flow-level setup hooks loaded"