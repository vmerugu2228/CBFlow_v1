#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# OMNI FLOW - Update Config Script
# Checks for changes in config files and regenerates consolidated config if needed
# ═══════════════════════════════════════════════════════════════════════════════

# Source utilities
set script_dir [file dirname [info script]]
if {[file exists "$script_dir/utils.tcl"]} {
    source "$script_dir/utils.tcl"
} elseif {[info exists env(FLOW_DIR)]} {
    source "$env(FLOW_DIR)/utils/utils.tcl"
} else {
    handle_error "Cannot find utils.tcl"
}


# Namespace for update_config procedures
namespace eval UpdateConfig {
    proc show_usage {} {
        show_script_header "Update Config Script" ""
        show_usage_section "Usage" {
            "tclsh \$FLOW_DIR/utils/update_config.tcl"
        }
        show_usage_section "Requirements" {
            "- Must be run from inside a run directory (e.g., run_PNR_test_001/)"
            "- user_config.tcl must exist in the run directory"
            "- .env.tcl must exist in the run directory"
        }
        show_usage_section "Description" {
            "Checks user configuration and validates flow setup."
        }
        show_usage_section "Example" {
            "cd run_PNR_test_001"
            "tclsh \$FLOW_DIR/utils/update_config.tcl"
        }
    }

    proc read_metadata_file {metadata_file} {
        array set checksums {}
        if {![file exists $metadata_file]} {
            return [array get checksums]
        }
        set fp [open $metadata_file r]
        while {[gets $fp line] >= 0} {
            set line [string trim $line]
            if {$line eq "" || [string match "#*" $line]} {
                continue
            }
            if {[regexp {^(.+)\s+(.+)$} $line -> filepath checksum]} {
                set checksums($filepath) $checksum
            }
        }
        close $fp
        return [array get checksums]
    }

    proc get_file_checksum {filepath} {
        if {![file exists $filepath]} {
            return "MISSING"
        }
        set mtime [file mtime $filepath]
        set size [file size $filepath]
        return "${mtime}-${size}"
    }

    proc validate_run_directory {} {
        if {![file exists ".env.tcl"]} {
            handle_error "Not in a run directory (missing .env.tcl)"
            return false
        }
        return true
    }

    proc get_current_config_files {} {
        source ".env.tcl"
        if {[file exists "setup/user_config.tcl"]} {
            source "setup/user_config.tcl"
        }
        set config_files {}
        set flow_config "$FLOW_DIR/config/flow_config.tcl"
        if {[file exists $flow_config]} {
            lappend config_files [list $flow_config "FLOW_CONFIG"]
        }
        if {[info exists PROJECT_NAME]} {
            set project_config "$FLOW_DIR/config/${PROJECT_NAME}_config.tcl"
            if {[file exists $project_config]} {
                lappend config_files [list $project_config "PROJECT_CONFIG"]
            }
        }
        if {[info exists TECH_NODE]} {
            set tech_config "$FLOW_DIR/config/${TECH_NODE}_config.tcl"
            if {[file exists $tech_config]} {
                lappend config_files [list $tech_config "TECH_CONFIG"]
            }
        }
        set user_config "setup/user_config.tcl"
        if {[file exists $user_config]} {
            lappend config_files [list $user_config "USER_CONFIG"]
        }
        return $config_files
    }

    proc check_for_changes {config_files metadata_file} {
        array set old_checksums [UpdateConfig::read_metadata_file $metadata_file]
        set changes_detected 0
        set changed_files {}
        foreach config_info $config_files {
            set config_file [lindex $config_info 0]
            set config_name [lindex $config_info 1]
            set current_checksum [UpdateConfig::get_file_checksum $config_file]
            set old_checksum ""
            if {[info exists old_checksums($config_file)]} {
                set old_checksum $old_checksums($config_file)
            } else {
                foreach {meta_path meta_checksum} [array get old_checksums] {
                    if {[file tail $meta_path] eq [file tail $config_file]} {
                        set old_checksum $meta_checksum
                        break
                    }
                }
            }
            if {$old_checksum ne ""} {
                if {$current_checksum ne $old_checksum} {
                    if {$current_checksum eq "MISSING"} {
                        handle_warning "Missing: $config_name ($config_file)"
                    } else {
                        handle_info "Changed: $config_name"
                    }
                    lappend changed_files $config_name
                    set changes_detected 1
                } else {
                    handle_info "Unchanged: $config_name"
                }
            } else {
                handle_info "New: $config_name"
                lappend changed_files $config_name
                set changes_detected 1
            }
        }
        return [list $changes_detected $changed_files]
    }

    proc main {} {
        global argc argv
        if {$argc > 0} {
            UpdateConfig::show_usage
            exit 1
        }
        if {![UpdateConfig::validate_run_directory]} {
            exit 1
        }
        foreach required_file {.config.tcl setup/.config_metadata} {
            if {![file exists $required_file]} {
                handle_error "[lindex [split $required_file /] end] not found\nRun generate_config.tcl first to create initial configuration"
            }
        }
        # Use environment variable for run directory
        if {[info exists ::env(RUN_DIR)]} {
            set current_dir $::env(RUN_DIR)
            set run_dir_name [file tail $::env(RUN_DIR)]
        } else {
            set current_dir $::env(CBFLOW_RUN_DIR)
            set run_dir_name [file tail $current_dir]
            puts "WARNING: RUN_DIR not found in environment, using current directory: $current_dir"
        }
        print_section "Checking config files for changes"
        puts "Run directory: $run_dir_name"
        set config_files [UpdateConfig::get_current_config_files]
        if {[llength $config_files] == 0} {
            handle_error "No config files found"
        }
        set metadata_file "config/.config_metadata"
        set change_result [UpdateConfig::check_for_changes $config_files $metadata_file]
        set changes_detected [lindex $change_result 0]
        set changed_files [lindex $change_result 1]
        puts ""
        if {$changes_detected} {
            handle_info "Changes detected in: [join $changed_files {, }]"
            handle_info "Regenerating consolidated configuration..."
            source ".env.tcl"
            set generate_script "$FLOW_DIR/utils/generate_config.tcl"
            set user_config "config/user_config.tcl"
            if {![file exists $generate_script]} {
                handle_error "Generate config script not found: $generate_script"
            }
            if {![file exists $user_config]} {
                handle_error "User config not found: $user_config"
            }
            handle_info "Calling: tclsh $generate_script . $user_config"
            if {[catch {
                exec tclsh $generate_script "." $user_config
            } result]} {
                handle_error "Failed to regenerate config\n$result"
            }
            handle_info "Configuration updated successfully!"
            puts "   Updated: .config.tcl"
            puts "   Metadata: $metadata_file"
        } else {
            handle_info "No changes detected - configuration is up to date"
        }
        puts ""
    }
}

# Execute main
UpdateConfig::main