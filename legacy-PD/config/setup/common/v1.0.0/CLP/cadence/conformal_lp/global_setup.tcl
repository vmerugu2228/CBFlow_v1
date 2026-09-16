#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow - Tool Global Setup Hooks (CLP/Cadence/Conformal LP)
# Description: Conformal LP-specific global flow_proc hooks for all CLP stages
# Priority: High (overrides flow-specific, can be overridden by stage-specific)
# ═══════════════════════════════════════════════════════════════════════════════

handle_info "Loading Conformal LP tool global setup hooks"

# Conformal LP-specific initialization
flow_proc_prepend flow_init {
    handle_info "Conformal LP flow init prepend: Tool-specific initialization"

    # Set Conformal LP-specific environment
    if {![info exists ::env(CONFORMAL_LP_TOOL_VERSION)]} {
        set ::env(CONFORMAL_LP_TOOL_VERSION) "21.1"
    }

    # Create Conformal LP-specific directories
    set clp_dirs {
        "logs/conformal_lp"
        "work/conformal_lp"
        "reports/clp"
        "results/clp"
        "results/db"
    }

    foreach dir $clp_dirs {
        if {![file exists $dir]} {
            file mkdir $dir
            handle_info "Created Conformal LP directory: $dir"
        }
    }
}

flow_proc_append flow_init {
    handle_info "Conformal LP flow init append: Tool validation complete"

    if {[info exists ::env(CONFORMAL_LP_TOOL_VERSION)]} {
        handle_info "Conformal LP tool version: $::env(CONFORMAL_LP_TOOL_VERSION)"
    }
}

# Conformal LP-specific library setup
flow_proc_prepend setup_libraries {
    handle_info "Conformal LP setup libraries prepend: Tool-specific library handling"

    handle_info "Conformal LP library setup: Configuring cell libraries for LP verification"

    if {[info exists tech(lib,timing)]} {
        set lib_files [expr {[string match "*{*}*" $tech(lib,timing)] ? $tech(lib,timing) : [list $tech(lib,timing)]}]
        foreach lib $lib_files {
            set lib_path [file join $ROOT_DIR $lib]
            if {[file exists $lib_path]} {
                if {[string match "*.lib" $lib_path]} {
                    handle_info "Conformal LP library validation: $lib_path (Liberty format - compatible)"
                } else {
                    handle_warning "Conformal LP library validation: $lib_path (Unknown format)"
                }
            }
        }
    }
}

flow_proc_append setup_libraries {
    handle_info "Conformal LP setup libraries append: Library validation complete"
}

# Conformal LP-specific design reading
flow_proc_prepend read_design {
    handle_info "Conformal LP read design prepend: Configuring design import"
    handle_info "Conformal LP: Setting design read mode for low power analysis"
}

flow_proc_append read_design {
    handle_info "Conformal LP read design append: Design validation complete"
}

# Conformal LP-specific power intent handling
flow_proc_prepend read_power_intent {
    handle_info "Conformal LP read power intent prepend: Configuring UPF/CPF parsing"
}

flow_proc_append read_power_intent {
    handle_info "Conformal LP read power intent append: Power intent validated"
}

# Conformal LP-specific verification
flow_proc_prepend run_lp_verification {
    handle_info "Conformal LP verify prepend: Tool-specific verification setup"

    if {[info exists ::env(CONFORMAL_LP_TOOL_VERSION)]} {
        set version $::env(CONFORMAL_LP_TOOL_VERSION)
        handle_info "Conformal LP verification: Using version $version"
    }
}

flow_proc_append run_lp_verification {
    handle_info "Conformal LP verify append: Tool-specific result validation"
    handle_info "Conformal LP verification: Low power checks completed"
}

# Conformal LP-specific reporting
flow_proc_prepend generate_reports {
    handle_info "Conformal LP reports prepend: Tool-specific reporting setup"

    if {![file exists "reports/conformal_lp"]} {
        file mkdir "reports/conformal_lp"
        handle_info "Created Conformal LP report directory"
    }
}

flow_proc_append generate_reports {
    handle_info "Conformal LP reports append: Generating tool-specific summary"

    set clp_summary "reports/conformal_lp/conformal_lp_summary.rpt"
    set fp [open $clp_summary w]
    puts $fp "═══════════════════════════════════════════════════════════════════════════════"
    puts $fp "Conformal LP Tool Summary Report"
    puts $fp "═══════════════════════════════════════════════════════════════════════════════"
    puts $fp "Generated: [clock format [clock seconds]]"
    if {[info exists ::env(CONFORMAL_LP_TOOL_VERSION)]} {
        puts $fp "Conformal LP Version: $::env(CONFORMAL_LP_TOOL_VERSION)"
    }
    puts $fp ""
    puts $fp "Low Power Verification Reports:"
    foreach rpt_name {
        "connectivity_check.rpt"
        "isolation_check.rpt"
        "level_shifter_check.rpt"
        "retention_check.rpt"
        "power_switch_check.rpt"
        "comprehensive_check.rpt"
    } {
        if {[file exists "reports/clp/$rpt_name"]} {
            puts $fp "  $rpt_name"
        }
    }
    close $fp

    handle_info "Conformal LP tool summary generated: $clp_summary"
}

handle_info "Conformal LP tool global setup hooks loaded"
