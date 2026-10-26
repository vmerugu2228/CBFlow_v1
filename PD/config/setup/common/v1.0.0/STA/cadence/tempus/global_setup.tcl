#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow - Tool Global Setup Hooks (STA/Cadence/Tempus)
# Description: Tempus-specific global flow_proc hooks for all STA stages
# ═══════════════════════════════════════════════════════════════════════════════

handle_info "Loading Tempus tool global setup hooks"

flow_proc_prepend flow_init {
    handle_info "Tempus flow init prepend: Tool-specific initialization"

    if {![info exists ::env(TEMPUS_TOOL_VERSION)]} {
        set ::env(TEMPUS_TOOL_VERSION) "21.1"
    }

    set tempus_dirs {
        "logs/tempus"
        "work/tempus"
        "reports/timing"
        "reports/extraction"
        "results/timing"
        "results/extraction"
    }

    foreach dir $tempus_dirs {
        if {![file exists $dir]} {
            file mkdir $dir
            handle_info "Created Tempus directory: $dir"
        }
    }
}

flow_proc_append flow_init {
    handle_info "Tempus flow init append: Tool validation complete"
    if {[info exists ::env(TEMPUS_TOOL_VERSION)]} {
        handle_info "Tempus tool version: $::env(TEMPUS_TOOL_VERSION)"
    }
}

flow_proc_prepend setup_libraries {
    handle_info "Tempus setup libraries prepend: Configuring timing libraries"
}

flow_proc_append setup_libraries {
    handle_info "Tempus setup libraries append: Library validation complete"
}

flow_proc_prepend run_extraction {
    handle_info "Tempus extraction prepend: Configuring extraction engine"
    if {[info exists ::env(TEMPUS_TOOL_VERSION)]} {
        handle_info "Tempus extraction: Using version $::env(TEMPUS_TOOL_VERSION)"
    }
}

flow_proc_append run_extraction {
    handle_info "Tempus extraction append: Extraction results validated"
}

flow_proc_prepend run_timing_analysis {
    handle_info "Tempus timing prepend: Configuring STA engine"
}

flow_proc_append run_timing_analysis {
    handle_info "Tempus timing append: STA results validated"
}

flow_proc_prepend generate_timing_reports {
    handle_info "Tempus reports prepend: Configuring report generation"
    if {![file exists "reports/tempus"]} {
        file mkdir "reports/tempus"
    }
}

flow_proc_append generate_timing_reports {
    handle_info "Tempus reports append: Generating tool-specific summary"

    set tempus_summary "reports/tempus/tempus_summary.rpt"
    set fp [open $tempus_summary w]
    puts $fp "═══════════════════════════════════════════════════════════════════════════════"
    puts $fp "Tempus Tool Summary Report"
    puts $fp "═══════════════════════════════════════════════════════════════════════════════"
    puts $fp "Generated: [clock format [clock seconds]]"
    if {[info exists ::env(TEMPUS_TOOL_VERSION)]} {
        puts $fp "Tempus Version: $::env(TEMPUS_TOOL_VERSION)"
    }
    puts $fp ""
    puts $fp "Timing Reports:"
    foreach rpt_name {
        "setup_timing.rpt"
        "hold_timing.rpt"
        "timing_qor.rpt"
        "constraint_violations.rpt"
    } {
        if {[file exists "reports/timing/$rpt_name"]} {
            puts $fp "  $rpt_name"
        }
    }
    close $fp
    handle_info "Tempus tool summary generated: $tempus_summary"
}

handle_info "Tempus tool global setup hooks loaded"
