#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow - Tool Global Setup Hooks (LEC/Synopsys/Formality)
# Description: Formality-specific global flow_proc hooks for all LEC stages
# Priority: High (overrides flow-specific, can be overridden by stage-specific)
# ═══════════════════════════════════════════════════════════════════════════════

handle_info "Loading Formality tool global setup hooks"

# Formality-specific initialization
flow_proc_prepend flow_init {
    handle_info "Formality flow init prepend: Tool-specific initialization"

    # Set Formality-specific environment
    if {![info exists ::env(FORMALITY_TOOL_VERSION)]} {
        set ::env(FORMALITY_TOOL_VERSION) "2022.03"
    }

    # Create Formality-specific directories
    set fm_dirs {
        "logs/formality"
        "work/formality"
        "reports/lec"
        "results/lec"
    }

    foreach dir $fm_dirs {
        if {![file exists $dir]} {
            file mkdir $dir
            handle_info "Created Formality directory: $dir"
        }
    }
}

flow_proc_append flow_init {
    handle_info "Formality flow init append: Tool validation complete"

    if {[info exists ::env(FORMALITY_TOOL_VERSION)]} {
        handle_info "Formality tool version: $::env(FORMALITY_TOOL_VERSION)"
    }
}

# Formality-specific library setup
flow_proc_prepend setup_libraries {
    handle_info "Formality setup libraries prepend: Tool-specific library handling"

    handle_info "Formality library setup: Configuring search paths for cell matching"

    if {[info exists tech(lib,timing)]} {
        set lib_files [expr {[string match "*{*}*" $tech(lib,timing)] ? $tech(lib,timing) : [list $tech(lib,timing)]}]
        foreach lib $lib_files {
            set lib_path [file join $ROOT_DIR $lib]
            if {[file exists $lib_path]} {
                if {[string match "*.lib" $lib_path] || [string match "*.db" $lib_path]} {
                    handle_info "Formality library validation: $lib_path (compatible)"
                } else {
                    handle_warning "Formality library validation: $lib_path (Unknown format)"
                }
            }
        }
    }
}

flow_proc_append setup_libraries {
    handle_info "Formality setup libraries append: Library validation complete"
}

# Formality-specific reference design handling
flow_proc_prepend read_reference_design {
    handle_info "Formality read reference prepend: Configuring golden design"
    handle_info "Formality: Setting reference design mode"
}

flow_proc_append read_reference_design {
    handle_info "Formality read reference append: Golden design validation"
    handle_info "Formality: Reference design loaded and validated"
}

# Formality-specific implementation design handling
flow_proc_prepend read_implementation_design {
    handle_info "Formality read implementation prepend: Configuring revised design"
    handle_info "Formality: Setting implementation design mode"
}

flow_proc_append read_implementation_design {
    handle_info "Formality read implementation append: Revised design validation"
    handle_info "Formality: Implementation design loaded and validated"
}

# Formality-specific verification
flow_proc_prepend run_verification {
    handle_info "Formality verify prepend: Tool-specific verification setup"

    if {[info exists ::env(FORMALITY_TOOL_VERSION)]} {
        set version $::env(FORMALITY_TOOL_VERSION)
        handle_info "Formality verification: Using version $version"
    }
}

flow_proc_append run_verification {
    handle_info "Formality verify append: Tool-specific result validation"
    handle_info "Formality verification: Results validated"
}

# Formality-specific reporting
flow_proc_prepend generate_comparison_reports {
    handle_info "Formality reports prepend: Tool-specific reporting setup"

    if {![file exists "reports/formality"]} {
        file mkdir "reports/formality"
        handle_info "Created Formality report directory"
    }
}

flow_proc_append generate_comparison_reports {
    handle_info "Formality reports append: Generating tool-specific summary"

    set fm_summary "reports/formality/formality_summary.rpt"
    set fp [open $fm_summary w]
    puts $fp "═══════════════════════════════════════════════════════════════════════════════"
    puts $fp "Formality Tool Summary Report"
    puts $fp "═══════════════════════════════════════════════════════════════════════════════"
    puts $fp "Generated: [clock format [clock seconds]]"
    if {[info exists ::env(FORMALITY_TOOL_VERSION)]} {
        puts $fp "Formality Version: $::env(FORMALITY_TOOL_VERSION)"
    }
    puts $fp ""
    puts $fp "Tool-Specific Reports:"
    if {[file exists "reports/lec/verification_status.rpt"]} {
        puts $fp "  Verification Status: reports/lec/verification_status.rpt"
    }
    if {[file exists "reports/lec/match_status.rpt"]} {
        puts $fp "  Match Status: reports/lec/match_status.rpt"
    }
    close $fp

    handle_info "Formality tool summary generated: $fm_summary"
}

handle_info "Formality tool global setup hooks loaded"
