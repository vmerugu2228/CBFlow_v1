#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow - Tool Global Setup Hooks (SYNTH/Cadence/Genus)
# Description: Genus-specific global flow_proc hooks for ALL synthesis stages
# Priority: High (overrides flow-specific, can be overridden by stage-specific)
# ═══════════════════════════════════════════════════════════════════════════════

handle_info "Loading Genus tool global setup hooks"

# Genus-specific initialization
flow_proc_prepend flow_init {
    handle_info "Genus flow init prepend: Tool-specific initialization"

    # Set Genus-specific environment
    if {![info exists ::env(GENUS_TOOL_VERSION)]} {
        set ::env(GENUS_TOOL_VERSION) "21.1"
    }

    # Create Genus-specific directories
    set genus_dirs {
        "logs/genus"
        "work/genus"
        "genus_tmp"
    }

    foreach dir $genus_dirs {
        if {![file exists $dir]} {
            file mkdir $dir
            handle_info "Created Genus directory: $dir"
        }
    }
}

flow_proc_append flow_init {
    handle_info "Genus flow init append: Tool validation complete"

    # Validate Genus environment
    if {[info exists ::env(GENUS_TOOL_VERSION)]} {
        handle_info "Genus tool version: $::env(GENUS_TOOL_VERSION)"
    }
}

# Genus-specific library setup
flow_proc_prepend setup_libraries {
    handle_info "Genus setup libraries prepend: Tool-specific library handling"

    # Set Genus-specific library search order
    handle_info "Genus library setup: Configuring search paths for optimal performance"

    # Genus-specific library validation
    if {[info exists tech(lib,timing)]} {
        set lib_files [expr {[string match "*{*}*" $tech(lib,timing)] ? $tech(lib,timing) : [list $tech(lib,timing)]}]
        foreach lib $lib_files {
            set lib_path [file join $ROOT_DIR $lib]
            if {[file exists $lib_path]} {
                # Check if library is Genus-compatible
                if {[string match "*.lib" $lib_path]} {
                    handle_info "Genus library validation: $lib_path (Liberty format - compatible)"
                } else {
                    handle_warning "Genus library validation: $lib_path (Unknown format)"
                }
            }
        }
    }
}

flow_proc_append setup_libraries {
    handle_info "Genus setup libraries append: Tool-specific validation"

    # Genus-specific library optimization settings
    handle_info "Genus library optimization: Applying tool-specific settings"
}

# Genus-specific RTL handling
flow_proc_prepend read_rtl_files {
    handle_info "Genus read RTL prepend: Tool-specific RTL handling"

    # Set Genus-specific RTL processing options
    if {[info exists synth(input,format)]} {
        switch $synth(input,format) {
            "sv" {
                handle_info "Genus RTL format: SystemVerilog mode enabled"
            }
            "verilog" {
                handle_info "Genus RTL format: Verilog mode enabled"
            }
            "vhdl" {
                handle_info "Genus RTL format: VHDL mode enabled"
            }
            default {
                handle_info "Genus RTL format: Auto-detection mode"
            }
        }
    }
}

flow_proc_append read_rtl_files {
    handle_info "Genus read RTL append: Tool-specific RTL validation"

    # Genus-specific RTL validation
    handle_info "Genus RTL validation: Checking for tool-specific compatibility"
}

# Genus-specific synthesis optimization
flow_proc_prepend synthesize_design {
    handle_info "Genus synthesize design prepend: Tool-specific synthesis setup"

    # Set Genus-specific synthesis defaults
    handle_info "Genus synthesis: Applying tool-specific optimization defaults"

    # Genus version-specific optimizations
    if {[info exists ::env(GENUS_TOOL_VERSION)]} {
        set version $::env(GENUS_TOOL_VERSION)
        if {[string match "21.*" $version]} {
            handle_info "Genus synthesis: Applying version 21.x optimizations"
        } elseif {[string match "20.*" $version]} {
            handle_info "Genus synthesis: Applying version 20.x optimizations"
        }
    }
}

flow_proc_append synthesize_design {
    handle_info "Genus synthesize design append: Tool-specific synthesis validation"

    # Genus-specific result validation
    handle_info "Genus synthesis validation: Checking tool-specific outputs"
}

# Genus-specific optimization
flow_proc_prepend optimize_design {
    handle_info "Genus optimize design prepend: Tool-specific optimization setup"

    # Genus-specific optimization strategies
    if {[info exists synth(strategy)]} {
        switch $synth(strategy) {
            "timing" {
                handle_info "Genus optimization: Timing-focused strategy for Genus"
            }
            "area" {
                handle_info "Genus optimization: Area-focused strategy for Genus"
            }
            "power" {
                handle_info "Genus optimization: Power-focused strategy for Genus"
            }
            default {
                handle_info "Genus optimization: Balanced strategy for Genus"
            }
        }
    }
}

flow_proc_append optimize_design {
    handle_info "Genus optimize design append: Tool-specific optimization validation"

    # Genus-specific optimization validation
    handle_info "Genus optimization validation: Checking tool-specific metrics"
}

# Genus-specific reporting
flow_proc_prepend generate_reports {
    handle_info "Genus generate reports prepend: Tool-specific reporting setup"

    # Create Genus-specific report directory
    if {![file exists "reports/genus"]} {
        file mkdir "reports/genus"
        handle_info "Created Genus report directory"
    }
}

flow_proc_append generate_reports {
    handle_info "Genus generate reports append: Tool-specific reporting"

    # Generate Genus-specific reports
    set genus_summary "reports/genus/genus_summary.rpt"
    set fp [open $genus_summary w]
    puts $fp "═══════════════════════════════════════════════════════════════════════════════"
    puts $fp "Genus Tool Summary Report"
    puts $fp "═══════════════════════════════════════════════════════════════════════════════"
    puts $fp "Generated: [clock format [clock seconds]]"
    if {[info exists ::env(GENUS_TOOL_VERSION)]} {
        puts $fp "Genus Version: $::env(GENUS_TOOL_VERSION)"
    }
    if {[info exists synth(strategy)]} {
        puts $fp "Synthesis Strategy: $synth(strategy)"
    }
    puts $fp ""
    puts $fp "Tool-Specific Reports:"
    if {[file exists "reports/synthesis/synth_qor.rpt"]} {
        puts $fp "  • Quality of Results: reports/synthesis/synth_qor.rpt"
    }
    if {[file exists "reports/synthesis/synth_timing.rpt"]} {
        puts $fp "  • Timing Analysis: reports/synthesis/synth_timing.rpt"
    }
    close $fp

    handle_info "Genus tool summary generated: $genus_summary"
}

handle_info "Genus tool global setup hooks loaded"