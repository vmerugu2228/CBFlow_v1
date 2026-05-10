#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# RELEASE CONFIGURATION
# Description: Release directory structure and tag mappings
# ═══════════════════════════════════════════════════════════════════════════════

#===============================================================================
# PORTABLE PATH RESOLUTION
#===============================================================================
# Source path resolver for portable path detection
set script_dir_for_resolver [file dirname [file normalize [info script]]]
# Navigate from config/flow/v1.0.0 -> core (3 levels up)
set resolver_path [file join $script_dir_for_resolver "../../.." "utils" "utilities" "v2.0.0" "path_resolver.tcl"]

if {[file exists $resolver_path]} {
    source $resolver_path
    set project_root_resolved [::PathResolver::get_project_root]
} else {
    # Fallback: Check environment variable
    if {[info exists ::env(CBFLOW_PROJECT_ROOT)]} {
        set project_root_resolved $::env(CBFLOW_PROJECT_ROOT)
    } else {
        # Last resort: Try git command
        if {[catch {exec git rev-parse --show-toplevel} git_root] == 0} {
            set project_root_resolved [file join [string trim $git_root] "CBFlow" "PD"]
        } else {
            # Absolute fallback: Calculate from script location
            set project_root_resolved [file normalize [file join $script_dir_for_resolver "../../../.."]]
        }
    }
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                         RELEASE PATH CONFIGURATION                         │
# └─────────────────────────────────────────────────────────────────────────────┘

# Base release directory (portable - uses dynamically detected project root)
set release(base_dir) [file join $project_root_resolved "test_releases"]

# Release tag to directory mapping
# Pattern: release_base_dir/<category>/<tag>/
# Paths are now generated dynamically from base_dir
array set release_paths {
    rtl {
        "2024Q4_v2.0"    ""
        "2024Q3_v1.8"    ""
        "2024Q2_v1.5"    ""
    }
    constraints {
        "2024Q4_v2.0"    ""
        "2024Q3_v1.8"    ""
        "2024Q2_v1.5"    ""
    }
    power {
        "2024Q4_v2.0"    ""
        "2024Q3_v1.8"    ""
        "2024Q2_v1.5"    ""
    }
}

# Generate dynamic paths based on release(base_dir)
foreach category [array names release_paths] {
    set tag_dict [dict create]
    dict for {tag _} $release_paths($category) {
        dict set tag_dict $tag [file join $release(base_dir) $category $tag]
    }
    set release_paths($category) $tag_dict
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                         FILE NAMING CONVENTIONS                            │
# └─────────────────────────────────────────────────────────────────────────────┘

# File naming patterns for each category
# RTL: <design_name>.f
# SDC: <design_name>.<mode>.sdc (modes from project_config.tcl)
# UPF: <design_name>.upf

proc get_release_file_path {category tag design_name {mode ""}} {
    global release_paths

    # Get the release directory for this category and tag
    if {![info exists release_paths($category)] || ![dict exists $release_paths($category) $tag]} {
        error "ERROR: Release tag '$tag' not found for category '$category'"
    }

    set release_dir [dict get $release_paths($category) $tag]

    # Construct file name based on category and mode
    switch $category {
        "rtl" {
            set filename "${design_name}.f"
        }
        "constraints" {
            if {$mode eq ""} {
                set mode "func"  ; # Default mode
            }
            set filename "${design_name}.${mode}.sdc"
        }
        "power" {
            set filename "${design_name}.upf"
        }
        default {
            error "ERROR: Unknown category '$category'"
        }
    }

    return [file join $release_dir $filename]
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                         RELEASE VALIDATION                                 │
# └─────────────────────────────────────────────────────────────────────────────┘

proc validate_release_tag {category tag} {
    global release_paths

    # Check if category exists
    if {![info exists release_paths($category)]} {
        error "ERROR: Unknown release category '$category'. Available categories: [array names release_paths]"
    }

    # Check if tag exists in category
    if {![dict exists $release_paths($category) $tag]} {
        set available_tags [dict keys $release_paths($category)]
        error "ERROR: Release tag '$tag' not found for category '$category'. Available tags: $available_tags"
    }

    # Check if release directory exists
    set release_dir [dict get $release_paths($category) $tag]
    if {![file exists $release_dir]} {
        error "ERROR: Release directory does not exist: $release_dir"
    }

    return true
}

proc get_available_release_tags {category} {
    global release_paths

    if {![info exists release_paths($category)]} {
        return {}
    }

    return [dict keys $release_paths($category)]
}


# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                         UTILITY FUNCTIONS                                  │
# └─────────────────────────────────────────────────────────────────────────────┘

proc list_all_releases {} {
    global release_paths

    puts "Available Release Tags by Category:"
    puts "=================================="

    foreach category [lsort [array names release_paths]] {
        puts "\n$category:"
        set tags [dict keys $release_paths($category)]
        foreach tag [lsort $tags] {
            set path [dict get $release_paths($category) $tag]
            set exists [file exists $path]
            set status [expr {$exists ? "✓" : "✗"}]
            puts "  $status $tag -> $path"
        }
    }
}

puts "INFO: Release configuration loaded successfully"