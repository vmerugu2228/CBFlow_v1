#!/usr/bin/env tclsh

# LSF Auto-Integration Module
# Simple module to automatically enable LSF for CBFlow scripts
# Just source this file to enable LSF integration

# Check if LSF integration should be enabled
set enable_lsf_integration false

# Check environment variable
if {[info exists ::env(CBFLOW_ENABLE_LSF)] && $::env(CBFLOW_ENABLE_LSF) eq "1"} {
    set enable_lsf_integration true
}

# Check for LSF configuration file
if {!$enable_lsf_integration} {
    set config_dirs [list \
        "../../../config/flow/v1.0.0" \
        "../../config/flow/v1.0.0" \
        "../config/flow/v1.0.0" \
        "config/flow/v1.0.0" \
    ]

    foreach config_dir $config_dirs {
        set lsf_config [file join $config_dir "lsf_config.tcl"]
        if {[file exists $lsf_config]} {
            set enable_lsf_integration true
            break
        }
    }
}

# Enable LSF integration if available
if {$enable_lsf_integration} {
    if {[catch {
        source [file join [file dirname [info script]] "lsf_integration.tcl"]
        ::lsf::integration::initialize
    } error]} {
        puts stderr "Warning: Failed to initialize LSF integration: $error"
        puts stderr "Continuing with local execution..."
    } else {
        puts "✓ LSF integration enabled for CBFlow execution"
    }
} else {
    puts "LSF integration not available - using local execution"
}