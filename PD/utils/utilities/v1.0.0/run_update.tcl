#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow Run Update Script
# Description: Updates a run directory to use a newer release version
# Version: v1.0.0
# Usage: tclsh run_update.tcl <run_dir> [-workspace <dir>] [-release <version>] [-backup]
# ═══════════════════════════════════════════════════════════════════════════════

# ┌─ Helper Functions ─────────────────────────────────────────────────────────┐

proc log_info {msg} {
    puts "ℹ \[CBFlow_INFO\] $msg"
}

proc log_success {msg} {
    puts "✓ \[CBFlow_SUCCESS\] $msg"
}

proc log_warning {msg} {
    puts "⚠ \[CBFlow_WARNING\] $msg"
}

proc log_error {msg} {
    puts "✗ \[CBFlow_ERROR\] $msg"
}

# ┌─ Version Comparison ───────────────────────────────────────────────────────┐

proc parse_version {version_str} {
    # Parse version string like "v1.2.3" into list {1 2 3}
    set version_str [string trimleft $version_str "vV"]
    set parts [split $version_str "."]
    set result {}
    foreach part $parts {
        if {[string is integer -strict $part]} {
            lappend result $part
        } else {
            lappend result 0
        }
    }
    # Ensure at least 3 parts
    while {[llength $result] < 3} {
        lappend result 0
    }
    return $result
}

proc compare_versions {v1 v2} {
    # Returns: 1 if v1 > v2, -1 if v1 < v2, 0 if equal
    set p1 [parse_version $v1]
    set p2 [parse_version $v2]

    for {set i 0} {$i < 3} {incr i} {
        set n1 [lindex $p1 $i]
        set n2 [lindex $p2 $i]
        if {$n1 > $n2} {
            return 1
        } elseif {$n1 < $n2} {
            return -1
        }
    }
    return 0
}

proc compare_versions_desc {v1 v2} {
    return [expr {-1 * [compare_versions $v1 $v2]}]
}

# ┌─ Environment File Parsing ─────────────────────────────────────────────────┐

proc read_env_file {env_file} {
    # Read environment file and return as dict
    set env_vars [dict create]

    if {![file exists $env_file]} {
        return $env_vars
    }

    set fp [open $env_file r]
    while {[gets $fp line] >= 0} {
        set line [string trim $line]
        # Skip comments and empty lines
        if {$line eq "" || [string match "#*" $line]} {
            continue
        }
        # Parse export VAR="value" or VAR="value"
        if {[regexp {^(?:export\s+)?([A-Z_][A-Z0-9_]*)=["']?([^"']*)["']?$} $line -> key value]} {
            dict set env_vars $key $value
        }
    }
    close $fp
    return $env_vars
}

proc get_release_version_from_env {env_file} {
    set env_vars [read_env_file $env_file]
    if {[dict exists $env_vars CBFLOW_RELEASE_VERSION]} {
        return [dict get $env_vars CBFLOW_RELEASE_VERSION]
    }
    return ""
}

# ┌─ Release Discovery ────────────────────────────────────────────────────────┐

proc get_available_releases {core_dir} {
    # Get list of available releases from releases directory
    set releases_dir [file join $core_dir "releases"]
    set releases {}

    if {![file exists $releases_dir]} {
        return $releases
    }

    foreach item [glob -nocomplain -directory $releases_dir *] {
        set name [file tail $item]
        if {[file isdirectory $item] && [string match "v*" $name] && $name ne "current"} {
            # Verify it has a MANIFEST.json
            if {[file exists [file join $item "MANIFEST.json"]]} {
                lappend releases $name
            }
        }
    }

    # Sort by version (newest first)
    set releases [lsort -command compare_versions_desc $releases]
    return $releases
}

proc get_latest_release {core_dir} {
    set releases [get_available_releases $core_dir]
    if {[llength $releases] > 0} {
        return [lindex $releases 0]
    }
    return ""
}

# ┌─ Manifest Loading ─────────────────────────────────────────────────────────┐

proc load_manifest {core_dir version} {
    set manifest_file [file join $core_dir "releases" $version "MANIFEST.json"]

    if {![file exists $manifest_file]} {
        log_error "Manifest not found: $manifest_file"
        return [dict create]
    }

    set fp [open $manifest_file r]
    set file_content [read $fp]
    close $fp

    set components [dict create]

    set lines [split $file_content "\n"]
    set current_comp ""

    foreach line $lines {
        # Match component name line
        if {[regexp {"([a-z_.]+)":\s*\{} $line -> comp_name]} {
            set current_comp $comp_name
        }
        # Match version line
        if {$current_comp ne "" && [regexp {"version":\s*"([^"]+)"} $line -> ver]} {
            dict set components $current_comp $ver
            set current_comp ""
        }
    }

    return $components
}

# ┌─ Backup Functions ─────────────────────────────────────────────────────────┐

proc backup_file {file_path backup_dir} {
    if {![file exists $file_path]} {
        return true
    }

    if {![file exists $backup_dir]} {
        file mkdir $backup_dir
    }

    set timestamp [clock format [clock seconds] -format "%Y%m%d_%H%M%S"]
    set filename [file tail $file_path]
    set backup_path [file join $backup_dir "${filename}.backup.${timestamp}"]

    if {[catch {file copy -force $file_path $backup_path} err]} {
        log_error "Failed to backup $filename: $err"
        return false
    }

    log_info "Backed up: $filename -> [file tail $backup_path]"
    return true
}

# ┌─ Environment Update Functions ─────────────────────────────────────────────┐

proc update_env_file {env_file new_version components core_dir} {
    if {![file exists $env_file]} {
        log_error "Environment file not found: $env_file"
        return false
    }

    # Read current content
    set fp [open $env_file r]
    set file_content [read $fp]
    close $fp

    # Update release version - line by line approach
    set lines [split $file_content "\n"]
    set new_lines {}

    foreach line $lines {
        set new_line $line

        # Update CBFLOW_RELEASE_VERSION
        if {[string match "*CBFLOW_RELEASE_VERSION=*" $line]} {
            if {[string match "export *" $line]} {
                set new_line "export CBFLOW_RELEASE_VERSION=\"$new_version\""
            } else {
                set new_line "CBFLOW_RELEASE_VERSION=\"$new_version\""
            }
        }

        # Update CBFLOW_RELEASE_DIR
        if {[string match "*CBFLOW_RELEASE_DIR=*" $line]} {
            if {[string match "export *" $line]} {
                set new_line "export CBFLOW_RELEASE_DIR=\"$core_dir/releases/$new_version\""
            } else {
                set new_line "CBFLOW_RELEASE_DIR=\"$core_dir/releases/$new_version\""
            }
        }

        # Update component versions
        dict for {comp_name comp_version} $components {
            set var_name "[string toupper [string map {. _} $comp_name]]_VERSION"
            if {[string match "*${var_name}=*" $line]} {
                if {[string match "export *" $line]} {
                    set new_line "export ${var_name}=\"$comp_version\""
                } else {
                    set new_line "${var_name}=\"$comp_version\""
                }
                break
            }
        }

        lappend new_lines $new_line
    }

    # Write updated content
    set fp [open $env_file w]
    puts -nonewline $fp [join $new_lines "\n"]
    close $fp

    return true
}

proc update_tcl_file {tcl_file new_version components core_dir} {
    if {![file exists $tcl_file]} {
        log_error "TCL file not found: $tcl_file"
        return false
    }

    # Read current content
    set fp [open $tcl_file r]
    set file_content [read $fp]
    close $fp

    # Update line by line
    set lines [split $file_content "\n"]
    set new_lines {}

    foreach line $lines {
        set new_line $line

        # Update CBFLOW_RELEASE_VERSION (both set var and set ::env forms)
        if {[string match "*CBFLOW_RELEASE_VERSION*" $line] && [string match "set *" $line]} {
            if {[string match "*::env(*" $line]} {
                set new_line "set ::env(CBFLOW_RELEASE_VERSION) \"$new_version\""
            } else {
                set new_line "set CBFLOW_RELEASE_VERSION \"$new_version\""
            }
        }

        # Update CBFLOW_RELEASE_DIR
        if {[string match "*CBFLOW_RELEASE_DIR*" $line] && [string match "set *" $line]} {
            if {[string match "*::env(*" $line]} {
                set new_line "set ::env(CBFLOW_RELEASE_DIR) \"$core_dir/releases/$new_version\""
            } else {
                set new_line "set CBFLOW_RELEASE_DIR \"$core_dir/releases/$new_version\""
            }
        }

        # Update component versions
        dict for {comp_name comp_version} $components {
            set var_name "[string toupper [string map {. _} $comp_name]]_VERSION"
            if {[string match "*${var_name}*" $line] && [string match "set *" $line]} {
                if {[string match "*::env(*" $line]} {
                    set new_line "set ::env(${var_name}) \"$comp_version\""
                } else {
                    set new_line "set ${var_name} \"$comp_version\""
                }
                break
            }
        }

        lappend new_lines $new_line
    }

    # Write updated content
    set fp [open $tcl_file w]
    puts -nonewline $fp [join $new_lines "\n"]
    close $fp

    return true
}

# ┌─ Makefile Regeneration ────────────────────────────────────────────────────┐

proc regenerate_makefile {run_dir} {
    log_info "Regenerating Makefile..."

    # Get generation script path from updated environment
    set env_file [file join $run_dir ".run.cbflow.env"]
    set env_vars [read_env_file $env_file]

    if {![dict exists $env_vars FLOW_DIR]} {
        log_warning "FLOW_DIR not found in environment"
        return false
    }

    set flow_dir [dict get $env_vars FLOW_DIR]
    set gen_version "v1.0.0"
    if {[dict exists $env_vars GENERATION_VERSION]} {
        set gen_version [dict get $env_vars GENERATION_VERSION]
    }

    set gen_script [file join $flow_dir "utils" "generation" $gen_version "gen_run_makefile.tcl"]

    if {![file exists $gen_script]} {
        log_warning "Makefile generation script not found: $gen_script"
        return false
    }

    # Save current directory
    set original_dir [pwd]

    # Change to run directory and regenerate
    cd $run_dir

    if {[catch {exec tclsh $gen_script} result]} {
        log_warning "Makefile generation had issues: $result"
    }

    cd $original_dir

    if {[file exists [file join $run_dir "Makefile"]]} {
        log_success "Makefile regenerated"
        return true
    }

    return false
}

# ┌─ Main Update Function ─────────────────────────────────────────────────────┐

proc update_run {run_dir args} {
    # Parse options
    set workspace_dir ""
    set target_release ""
    set do_backup true

    for {set i 0} {$i < [llength $args]} {incr i} {
        set arg [lindex $args $i]
        switch -- $arg {
            "-workspace" {
                incr i
                set workspace_dir [lindex $args $i]
            }
            "-release" {
                incr i
                set target_release [lindex $args $i]
            }
            "-backup" {
                set do_backup true
            }
            "-no-backup" {
                set do_backup false
            }
        }
    }

    puts ""
    puts "═══════════════════════════════════════════════════════════════"
    puts "  CBFlow Run Update"
    puts "═══════════════════════════════════════════════════════════════"
    puts ""

    # Validate run directory
    if {![file exists $run_dir]} {
        log_error "Run directory not found: $run_dir"
        return 1
    }

    set run_env_file [file join $run_dir ".run.cbflow.env"]
    set run_tcl_file [file join $run_dir ".run.cbflow.tcl"]

    if {![file exists $run_env_file]} {
        log_error "Not a valid run directory (missing .run.cbflow.env)"
        return 1
    }

    # Get current run version
    set current_version [get_release_version_from_env $run_env_file]
    if {$current_version eq ""} {
        log_error "Could not determine current release version"
        return 1
    }

    log_info "Run Directory: $run_dir"
    log_info "Current Version: $current_version"

    # Determine workspace directory
    if {$workspace_dir eq ""} {
        set workspace_dir [file dirname $run_dir]
    }

    set workspace_env_file [file join $workspace_dir ".cbflow.env"]

    # Get core directory
    set run_env_vars [read_env_file $run_env_file]
    set core_dir ""
    if {[dict exists $run_env_vars FLOW_DIR]} {
        set core_dir [dict get $run_env_vars FLOW_DIR]
    } elseif {[dict exists $run_env_vars CBFLOW_CORE_DIR]} {
        set core_dir [dict get $run_env_vars CBFLOW_CORE_DIR]
    }

    if {$core_dir eq ""} {
        log_error "Could not determine CBFlow core directory"
        return 1
    }

    # Determine target version
    if {$target_release eq ""} {
        # First check workspace
        if {[file exists $workspace_env_file]} {
            set workspace_version [get_release_version_from_env $workspace_env_file]
            if {$workspace_version ne "" && [compare_versions $workspace_version $current_version] > 0} {
                set target_release $workspace_version
                log_info "Workspace Version: $workspace_version"
            }
        }

        # Then check for even newer releases
        set latest_release [get_latest_release $core_dir]
        if {$latest_release ne ""} {
            log_info "Latest Available: $latest_release"
            if {$target_release eq "" || [compare_versions $latest_release $target_release] > 0} {
                set target_release $latest_release
            }
        }
    }

    # Check if update is needed
    if {$target_release eq ""} {
        log_info "No newer release available"
        puts ""
        return 0
    }

    set cmp [compare_versions $target_release $current_version]
    if {$cmp == 0} {
        log_success "Run is already at the target version ($current_version)"
        puts ""
        return 0
    }

    puts ""
    if {$cmp > 0} {
        log_info "Upgrade: $current_version -> $target_release"
    } else {
        log_warning "Downgrade: $current_version -> $target_release"
    }
    puts ""

    # Load new manifest
    set components [load_manifest $core_dir $target_release]
    if {[dict size $components] == 0} {
        log_error "Could not load manifest for release $target_release"
        return 1
    }

    log_info "Components to update: [dict size $components]"

    # Backup if enabled
    if {$do_backup} {
        set backup_dir [file join $run_dir ".backup"]
        backup_file $run_env_file $backup_dir
        backup_file $run_tcl_file $backup_dir
        if {[file exists [file join $run_dir ".run.cnflow.tcl"]]} {
            backup_file [file join $run_dir ".run.cnflow.tcl"] $backup_dir
        }
    }

    puts ""
    log_info "Updating environment files..."

    # Update environment files
    if {![update_env_file $run_env_file $target_release $components $core_dir]} {
        log_error "Failed to update .run.cbflow.env"
        return 1
    }
    log_success "Updated: .run.cbflow.env"

    if {[file exists $run_tcl_file]} {
        if {![update_tcl_file $run_tcl_file $target_release $components $core_dir]} {
            log_error "Failed to update .run.cbflow.tcl"
            return 1
        }
        log_success "Updated: .run.cbflow.tcl"
    }

    # Also update .run.cnflow.tcl if it exists
    set cnflow_file [file join $run_dir ".run.cnflow.tcl"]
    if {[file exists $cnflow_file]} {
        if {![update_tcl_file $cnflow_file $target_release $components $core_dir]} {
            log_warning "Failed to update .run.cnflow.tcl"
        } else {
            log_success "Updated: .run.cnflow.tcl"
        }
    }

    puts ""

    # Regenerate Makefile
    regenerate_makefile $run_dir

    puts ""
    puts "═══════════════════════════════════════════════════════════════"
    log_success "Run updated successfully!"
    log_info "Previous Version: $current_version"
    log_info "New Version:      $target_release"
    puts "═══════════════════════════════════════════════════════════════"
    puts ""

    return 0
}

# ┌─ Help ─────────────────────────────────────────────────────────────────────┐

proc show_help {} {
    puts "CBFlow Run Update Script v1.0.0"
    puts ""
    puts "Usage: tclsh run_update.tcl <run_dir> \[options\]"
    puts ""
    puts "Arguments:"
    puts "  run_dir               Path to run directory"
    puts ""
    puts "Options:"
    puts "  -workspace <dir>      Workspace directory (default: parent of run_dir)"
    puts "  -release <version>    Target release version (default: auto-detect)"
    puts "  -backup               Backup files before update (default)"
    puts "  -no-backup            Skip backup"
    puts "  -h, --help            Show this help"
    puts ""
    puts "Examples:"
    puts "  tclsh run_update.tcl /path/to/P0_run_PNR_test"
    puts "  tclsh run_update.tcl . -workspace /path/to/workspace"
    puts "  tclsh run_update.tcl . -release v2.0.0"
    puts ""
    puts "The script will:"
    puts "  1. Check current run's release version"
    puts "  2. Compare with workspace and available releases"
    puts "  3. Update environment files if newer version available"
    puts "  4. Regenerate Makefile with updated paths"
    puts ""
}

# ┌─ Main ─────────────────────────────────────────────────────────────────────┐

proc main {argc argv} {
    if {$argc == 0} {
        show_help
        return 1
    }

    set first_arg [lindex $argv 0]
    if {$first_arg in {"-h" "--help" "help"}} {
        show_help
        return 0
    }

    set run_dir [lindex $argv 0]
    if {$run_dir eq "."} {
        set run_dir [pwd]
    }
    set run_dir [file normalize $run_dir]

    set remaining_args [lrange $argv 1 end]

    return [update_run $run_dir {*}$remaining_args]
}

# ═══════════════════════════════════════════════════════════════════════════════
# Script Entry Point
# ═══════════════════════════════════════════════════════════════════════════════

if {[info script] eq $argv0} {
    exit [main $argc $argv]
}
