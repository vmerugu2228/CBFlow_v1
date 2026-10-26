#===============================================================================
# Logo Display Utilities for CBFlow Management System
#
# Description: Comprehensive header and logo display for CBFlow commands
# Version: 1.0.0
# Author: CBFlow Development Team
#
# Features:
# - ASCII art logo display
# - System information headers
# - Context-aware display modes
# - Color-coded output support
#===============================================================================

# Source required modules
set script_dir [file dirname [file normalize [info script]]]
source [file join $script_dir error_utils.tcl]

#===============================================================================
# DISPLAY MODE CONSTANTS
#===============================================================================

namespace eval ::LogoDisplay {
    # Display modes
    variable FULL_HEADER    "full"
    variable COMPACT_HEADER "compact"
    variable MINIMAL_HEADER "minimal"
    variable ASCII_ONLY     "ascii"

    # Color codes (if terminal supports colors)
    variable BLUE    ""
    variable GREEN   ""
    variable YELLOW  ""
    variable CYAN    ""
    variable BOLD    ""
    variable RESET   ""
}

#===============================================================================
# CORE DISPLAY FUNCTIONS
#===============================================================================

# Display full header with ASCII art and system information
proc ::LogoDisplay::display_full_header {} {
    global logo

    puts ""

    # Generate comprehensive logo box with all content inside
    set logo_lines [list]

    # Top border
    lappend logo_lines "╔══════════════════════════════════════════════════════════════════╗"

    # Empty line
    lappend logo_lines "║                                                                  ║"

    # Dynamic ASCII art letters based on logo(name)
    set ascii_rows [generate_system_ascii $logo(name)]
    foreach row $ascii_rows {
        # Ensure each row is exactly 66 characters wide
        set row_len [string length $row]
        if {$row_len < 66} {
            set padding [expr {66 - $row_len}]
            set row [format "%s%*s" $row $padding ""]
        } elseif {$row_len > 66} {
            set row [string range $row 0 65]
        }
        lappend logo_lines "║${row}║"
    }

    # Empty line
    lappend logo_lines "║                                                                  ║"

    # Helper function to ensure exact 66-character content
    proc ensure_66_chars {text} {
        set len [string length $text]
        if {$len >= 66} {
            return [string range $text 0 65]
        } else {
            set padding [expr {(66 - $len) / 2}]
            set right_padding [expr {66 - $len - $padding}]
            set result [format "%*s%s%*s" $padding "" $text $right_padding ""]
            # Force to exactly 66 characters
            if {[string length $result] < 66} {
                set result [format "%-66s" $result]
            } elseif {[string length $result] > 66} {
                set result [string range $result 0 65]
            }
            return $result
        }
    }

    # Tagline
    set tagline_centered [ensure_66_chars $logo(tagline)]
    lappend logo_lines "║${tagline_centered}║"

    # Motto
    set motto_centered [ensure_66_chars $logo(motto)]
    lappend logo_lines "║${motto_centered}║"

    # Empty line
    lappend logo_lines "║                                                                  ║"

    # Version and build info
    set version_info "Version: $logo(version) | Build: $logo(build_date)"
    set version_centered [ensure_66_chars $version_info]
    lappend logo_lines "║${version_centered}║"

    # Copyright
    set copyright_centered [ensure_66_chars $logo(copyright)]
    lappend logo_lines "║${copyright_centered}║"

    # Empty line
    lappend logo_lines "║                                                                  ║"

    # Features header
    set features_header "Key Features:"
    set header_centered [ensure_66_chars $features_header]
    lappend logo_lines "║${header_centered}║"

    # Empty line
    lappend logo_lines "║                                                                  ║"

    # Features list
    foreach feature $logo(features) {
        set feature_centered [ensure_66_chars $feature]
        lappend logo_lines "║${feature_centered}║"
    }

    # Bottom border
    lappend logo_lines "║                                                                  ║"
    lappend logo_lines "╚══════════════════════════════════════════════════════════════════╝"

    # Display the complete logo
    foreach line $logo_lines {
        puts $line
    }
    puts ""
}

# Display compact header without ASCII art
proc ::LogoDisplay::display_compact_header {} {
    global logo

    puts ""

    # Generate compact logo box with essential content
    set logo_lines [list]

    # Top border
    lappend logo_lines "╔══════════════════════════════════════════════════════════════════╗"

    # System name and version
    set name_version "$logo(name) $logo(version)"
    set nv_len [string length $name_version]
    set nv_padding [expr {(66 - $nv_len) / 2}]
    set nv_centered [format "%*s%s%*s" $nv_padding "" $name_version $nv_padding ""]
    lappend logo_lines "║$nv_centered║"

    # Description
    set desc_len [string length $logo(description)]
    set desc_padding [expr {(66 - $desc_len) / 2}]
    set desc_centered [format "%*s%s%*s" $desc_padding "" $logo(description) $desc_padding ""]
    lappend logo_lines "║$desc_centered║"

    # Empty line
    lappend logo_lines "║                                                                  ║"

    # Tagline and copyright
    set tag_copy "$logo(tagline) | $logo(copyright)"
    set tc_len [string length $tag_copy]
    if {$tc_len > 66} {
        # Split if too long
        set tagline_len [string length $logo(tagline)]
        set tagline_padding [expr {(66 - $tagline_len) / 2}]
        set tagline_centered [format "%*s%s%*s" $tagline_padding "" $logo(tagline) $tagline_padding ""]
        lappend logo_lines "║$tagline_centered║"

        set copyright_len [string length $logo(copyright)]
        set copyright_padding [expr {(66 - $copyright_len) / 2}]
        set copyright_centered [format "%*s%s%*s" $copyright_padding "" $logo(copyright) $copyright_padding ""]
        lappend logo_lines "║$copyright_centered║"
    } else {
        set tc_padding [expr {(66 - $tc_len) / 2}]
        set tc_centered [format "%*s%s%*s" $tc_padding "" $tag_copy $tc_padding ""]
        lappend logo_lines "║$tc_centered║"
    }

    # Bottom border
    lappend logo_lines "╚══════════════════════════════════════════════════════════════════╝"

    # Display the complete logo
    foreach line $logo_lines {
        puts $line
    }
    puts ""
}

# Display minimal header - just name and version
proc ::LogoDisplay::display_minimal_header {} {
    global logo

    puts ""

    # Generate minimal logo box
    set name_version "$logo(name) $logo(version)"
    set nv_len [string length $name_version]
    set nv_padding [expr {(66 - $nv_len) / 2}]
    set nv_centered [format "%*s%s%*s" $nv_padding "" $name_version $nv_padding ""]

    puts "╔══════════════════════════════════════════════════════════════════╗"
    puts "║$nv_centered║"
    puts "╚══════════════════════════════════════════════════════════════════╝"
    puts ""
}

# Display ASCII art only
proc ::LogoDisplay::display_ascii_only {} {
    global logo

    puts ""
    # Use the logo ascii_art from config which now contains CBFlow
    foreach line $logo(ascii_art) {
        puts $line
    }
    puts ""
}

# Display system status information
proc ::LogoDisplay::display_system_status {} {
    global logo

    # Generate system status box
    set status_lines [list]

    # Top border
    lappend status_lines "╔══════════════════════════════════════════════════════════════════╗"

    # Header
    set header "System Information:"
    set header_len [string length $header]
    set header_padding [expr {(66 - $header_len) / 2}]
    set header_centered [format "%*s%s%*s" $header_padding "" $header $header_padding ""]
    lappend status_lines "║$header_centered║"

    # Empty line
    lappend status_lines "║                                                                  ║"

    # Flow system info
    set flow_info "Flow System: $logo(name) $logo(version)"
    set flow_len [string length $flow_info]
    set flow_padding [expr {(66 - $flow_len) / 2}]
    set flow_centered [format "%*s%s%*s" $flow_padding "" $flow_info $flow_padding ""]
    lappend status_lines "║$flow_centered║"

    # Build date
    set build_info "Build Date: $logo(build_date)"
    set build_len [string length $build_info]
    set build_padding [expr {(66 - $build_len) / 2}]
    set build_centered [format "%*s%s%*s" $build_padding "" $build_info $build_padding ""]
    lappend status_lines "║$build_centered║"

    # Support
    set support_info "Support: $logo(contact)"
    set support_len [string length $support_info]
    set support_padding [expr {(66 - $support_len) / 2}]
    set support_centered [format "%*s%s%*s" $support_padding "" $support_info $support_padding ""]
    lappend status_lines "║$support_centered║"

    # Empty line
    lappend status_lines "║                                                                  ║"

    # Supported flows header
    set flows_header "Supported Flow Types:"
    set flows_len [string length $flows_header]
    set flows_padding [expr {(66 - $flows_len) / 2}]
    set flows_centered [format "%*s%s%*s" $flows_padding "" $flows_header $flows_padding ""]
    lappend status_lines "║$flows_centered║"

    # Flow list
    set flow_list [join $logo(supported_flows) " | "]
    set list_len [string length $flow_list]
    set list_padding [expr {(66 - $list_len) / 2}]
    set list_centered [format "%*s%s%*s" $list_padding "" $flow_list $list_padding ""]
    lappend status_lines "║$list_centered║"

    # Bottom border
    lappend status_lines "║                                                                  ║"
    lappend status_lines "╚══════════════════════════════════════════════════════════════════╝"

    # Display the status box
    foreach line $status_lines {
        puts $line
    }
    puts ""
}

# Display project context information
proc ::LogoDisplay::display_project_context {project_name technology release} {
    puts "Project Context:"
    puts "  Project: $project_name"
    puts "  Technology: $technology"
    puts "  Release: $release"
    puts ""
}

#===============================================================================
# COMMAND-SPECIFIC DISPLAY FUNCTIONS
#===============================================================================

# Display header for help command
proc ::LogoDisplay::display_help_header {} {
    display_full_header

    puts "Available Commands & Usage Information:"
    puts "═══════════════════════════════════════"
    puts ""
}

# Display header for init command
proc ::LogoDisplay::display_init_header {project_name technology release} {
    display_full_header

    puts "CBFlow Environment Initialization"
    puts "═══════════════════════════════════"
    puts ""

    display_project_context $project_name $technology $release
}

# Display header for create_run command with dynamic flow logo
proc ::LogoDisplay::display_create_run_header {flow_type} {
    global logo

    # Display full logo with all features
    display_full_header

    puts "Creating New $flow_type Run"
    puts "══════════════════════════════"
    puts ""

    # Get flow description if available
    global flow_descriptions
    if {[info exists flow_descriptions($flow_type)]} {
        puts "Flow Type: $flow_type - $flow_descriptions($flow_type)"
    } else {
        puts "Flow Type: $flow_type"
    }
    puts ""
}

# Display header for status/info commands
proc ::LogoDisplay::display_status_header {} {
    display_minimal_header
    display_system_status
}

# Display footer with support information
proc ::LogoDisplay::display_footer {} {
    global logo

    puts ""
    puts "────────────────────────────────────────────────────────────────"
    puts "For support and documentation: $logo(contact)"
    puts "System website: $logo(website)"
    puts "────────────────────────────────────────────────────────────────"
    puts ""
}

#===============================================================================
# DYNAMIC FLOW LOGO GENERATION
#===============================================================================

# ASCII Letter Definitions (each letter is 6 rows high)
proc ::LogoDisplay::get_letter_ascii {letter} {
    switch [string toupper $letter] {
        "A" {
            return {
                " █████╗ "
                "██╔══██╗"
                "███████║"
                "██╔══██║"
                "██║  ██║"
                "╚═╝  ╚═╝"
            }
        }
        "B" {
            return {
                "██████╗ "
                "██╔══██╗"
                "██████╔╝"
                "██╔══██╗"
                "██████╔╝"
                "╚═════╝ "
            }
        }
        "C" {
            return {
                " ██████╗"
                "██╔════╝"
                "██║     "
                "██║     "
                "╚██████╝"
                " ╚═════╝"
            }
        }
        "D" {
            return {
                "██████╗ "
                "██╔══██╗"
                "██║  ██║"
                "██║  ██║"
                "██████╔╝"
                "╚═════╝ "
            }
        }
        "E" {
            return {
                "███████╗"
                "██╔════╝"
                "█████╗  "
                "██╔══╝  "
                "███████╗"
                "╚══════╝"
            }
        }
        "F" {
            return {
                "███████╗"
                "██╔════╝"
                "█████╗  "
                "██╔══╝  "
                "██║     "
                "╚═╝     "
            }
        }
        "G" {
            return {
                " ██████╗ "
                "██╔════╝ "
                "██║  ███╗"
                "██║   ██║"
                "╚██████╔╝"
                " ╚═════╝ "
            }
        }
        "H" {
            return {
                "██╗  ██╗"
                "██║  ██║"
                "███████║"
                "██╔══██║"
                "██║  ██║"
                "╚═╝  ╚═╝"
            }
        }
        "I" {
            return {
                "██╗"
                "██║"
                "██║"
                "██║"
                "██║"
                "╚═╝"
            }
        }
        "J" {
            return {
                "     ██╗"
                "     ██║"
                "     ██║"
                "██   ██║"
                "╚█████╔╝"
                " ╚════╝ "
            }
        }
        "K" {
            return {
                "██╗  ██╗"
                "██║ ██╔╝"
                "█████╔╝ "
                "██╔═██╗ "
                "██║  ██╗"
                "╚═╝  ╚═╝"
            }
        }
        "L" {
            return {
                "██╗     "
                "██║     "
                "██║     "
                "██║     "
                "███████╗"
                "╚══════╝"
            }
        }
        "M" {
            return {
                "███╗   ██╗"
                "████╗ ████║"
                "██╔████╔██║"
                "██║╚██╔╝██║"
                "██║ ╚═╝ ██║"
                "╚═╝     ╚═╝"
            }
        }
        "N" {
            return {
                "███╗   ██╗"
                "████╗  ██║"
                "██╔██╗ ██║"
                "██║╚██╗██║"
                "██║ ╚████║"
                "╚═╝  ╚═══╝"
            }
        }
        "O" {
            return {
                " ██████╗ "
                "██╔═══██╗"
                "██║   ██║"
                "██║   ██║"
                "╚██████╔╝"
                " ╚═════╝ "
            }
        }
        "P" {
            return {
                "██████╗ "
                "██╔══██╗"
                "██████╔╝"
                "██╔═══╝ "
                "██║     "
                "╚═╝     "
            }
        }
        "Q" {
            return {
                " ██████╗ "
                "██╔═══██╗"
                "██║   ██║"
                "██║▄▄ ██║"
                "╚██████╔╝"
                " ╚═════╝ "
            }
        }
        "R" {
            return {
                "██████╗ "
                "██╔══██╗"
                "██████╔╝"
                "██╔══██╗"
                "██║  ██║"
                "╚═╝  ╚═╝"
            }
        }
        "S" {
            return {
                "███████╗"
                "██╔════╝"
                "███████╗"
                "╚════██║"
                "███████║"
                "╚══════╝"
            }
        }
        "T" {
            return {
                "████████╗"
                "╚══██╔══╝"
                "   ██║   "
                "   ██║   "
                "   ██║   "
                "   ╚═╝   "
            }
        }
        "U" {
            return {
                "██╗   ██╗"
                "██║   ██║"
                "██║   ██║"
                "██║   ██║"
                "╚██████╔╝"
                " ╚═════╝ "
            }
        }
        "V" {
            return {
                "██╗   ██╗"
                "██║   ██║"
                "██║   ██║"
                "╚██╗ ██╔╝"
                " ╚████╔╝ "
                "  ╚══╝  "
            }
        }
        "W" {
            return {
                "██╗    ██╗"
                "██║    ██║"
                "██║ █╗ ██║"
                "██║███╗██║"
                "╚███╔███╔╝"
                " ╚══╝╚══╝ "
            }
        }
        "X" {
            return {
                "██╗  ██╗"
                "╚██╗██╔╝"
                " ╚███╔╝ "
                " ██╔██╗ "
                "██╔╝ ██╗"
                "╚═╝  ╚═╝"
            }
        }
        "Y" {
            return {
                "██╗   ██╗"
                "╚██╗ ██╔╝"
                " ╚████╔╝ "
                "  ╚██╔╝  "
                "   ██║   "
                "   ╚═╝   "
            }
        }
        "Z" {
            return {
                "███████╗"
                "╚══███╔╝"
                "  ███╔╝ "
                " ███╔╝  "
                "███████╗"
                "╚══════╝"
            }
        }
        default {
            # For unknown characters, return spaces
            return {
                "        "
                "        "
                "        "
                "        "
                "        "
                "        "
            }
        }
    }
}

# Generate dynamic ASCII art for system name
proc ::LogoDisplay::generate_system_ascii {system_name} {
    set name_upper [string toupper $system_name]
    set letters [split $name_upper ""]

    # Initialize 6 rows for the ASCII art (now each letter has 6 rows)
    set rows [list "" "" "" "" "" ""]

    # Build each row by concatenating letters
    foreach letter $letters {
        set letter_rows [get_letter_ascii $letter]

        for {set i 0} {$i < 6} {incr i} {
            set current_row [lindex $rows $i]
            set letter_row [lindex $letter_rows $i]

            # Add the letter with spacing
            if {$current_row ne ""} {
                set current_row "${current_row}${letter_row}"
            } else {
                set current_row $letter_row
            }

            lset rows $i $current_row
        }
    }

    # Center each row in the 66-character box and add box borders
    set ascii_lines [list]
    foreach row $rows {
        set row_len [string length $row]

        # Ensure exact 66-character width
        if {$row_len >= 66} {
            # Truncate if too long
            set row_final [string range $row 0 65]
        } else {
            # Center and pad to exactly 66 characters
            set padding [expr {(66 - $row_len) / 2}]
            set right_padding [expr {66 - $row_len - $padding}]
            set row_final [format "%*s%s%*s" $padding "" $row $right_padding ""]
        }

        # Double-check length and force to 66 if needed
        set final_len [string length $row_final]
        if {$final_len < 66} {
            set row_final [format "%-66s" $row_final]
        } elseif {$final_len > 66} {
            set row_final [string range $row_final 0 65]
        }

        lappend ascii_lines $row_final
    }

    return $ascii_lines
}

# Generate flow-specific ASCII art logo
proc ::LogoDisplay::generate_flow_ascii {flow_name} {
    global logo

    # Get the main system name (CBFlow)
    set system_name [string toupper $logo(name)]

    # Create centered flow name display
    set flow_upper [string toupper $flow_name]
    set flow_display [join [split $flow_upper ""] " "]

    # Calculate center padding for flow name (66 chars wide box)
    set flow_len [string length $flow_display]
    set padding [expr {(66 - $flow_len) / 2}]
    set flow_centered [format "%*s%s%*s" $padding "" $flow_display $padding ""]

    # Create dynamic system name display based on logo(name)
    set system_ascii [generate_system_ascii $system_name]

    # Get flow description if available
    global flow_descriptions
    set description ""
    if {[info exists flow_descriptions($flow_name)]} {
        set description $flow_descriptions($flow_name)
    } else {
        set description "$flow_name Flow Execution"
    }

    # Calculate center padding for description
    set desc_len [string length $description]
    set desc_padding [expr {(66 - $desc_len) / 2}]
    set desc_centered [format "%*s%s%*s" $desc_padding "" $description $desc_padding ""]

    # Build the complete logo
    set logo_lines [list \
        "╔══════════════════════════════════════════════════════════════════╗" \
        "║$flow_centered║" \
        "║                                                                  ║" \
    ]

    # Add system ASCII art lines
    foreach line $system_ascii {
        lappend logo_lines "║$line║"
    }

    # Add description and footer
    lappend logo_lines "║                                                                  ║"
    lappend logo_lines "║$desc_centered║"
    lappend logo_lines "╚══════════════════════════════════════════════════════════════════╝"

    return $logo_lines
}

# Display flow-specific logo
proc ::LogoDisplay::display_flow_logo {flow_type} {
    set ascii_art [generate_flow_ascii $flow_type]

    puts ""
    foreach line $ascii_art {
        puts $line
    }
}

#===============================================================================
# UTILITY FUNCTIONS
#===============================================================================

# Check if terminal supports colors
proc ::LogoDisplay::supports_colors {} {
    # Simple check for color support
    if {[info exists ::env(TERM)] &&
        ($::env(TERM) eq "xterm" ||
         $::env(TERM) eq "xterm-color" ||
         $::env(TERM) eq "xterm-256color" ||
         [string match "*color*" $::env(TERM)])} {
        return 1
    }
    return 0
}

# Apply color formatting if supported
proc ::LogoDisplay::colorize {text color} {
    variable RESET

    if {[supports_colors]} {
        return "${color}${text}${RESET}"
    } else {
        return $text
    }
}

# Display with specified mode
proc ::LogoDisplay::display {mode args} {
    variable FULL_HEADER
    variable COMPACT_HEADER
    variable MINIMAL_HEADER
    variable ASCII_ONLY

    switch $mode {
        $FULL_HEADER    { display_full_header }
        $COMPACT_HEADER { display_compact_header }
        $MINIMAL_HEADER { display_minimal_header }
        $ASCII_ONLY     { display_ascii_only }
        default         { display_compact_header }
    }
}

#===============================================================================
# NAMESPACE EXPORT
#===============================================================================

namespace eval ::LogoDisplay {
    namespace export display_* supports_colors colorize display generate_flow_ascii
}

# Legacy compatibility - create global procedures
proc display_help_header {} { ::LogoDisplay::display_help_header }
proc display_init_header {project_name technology release} {
    ::LogoDisplay::display_init_header $project_name $technology $release
}
proc display_create_run_header {flow_type} {
    ::LogoDisplay::display_create_run_header $flow_type
}
proc display_status_header {} { ::LogoDisplay::display_status_header }
proc display_footer {} { ::LogoDisplay::display_footer }
proc display_flow_logo {flow_type} { ::LogoDisplay::display_flow_logo $flow_type }

puts "CBFlow Logo Display Utilities loaded"