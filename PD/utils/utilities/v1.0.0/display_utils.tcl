#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow Display Utilities (Refactored)
# Description: Logo display and branding utilities for all CBFlow scripts
# Version: v1.0.0
# Namespace: ::CBFlow::Utilities::DisplayUtils
# Usage: source display_utils_refactored.tcl
# ═══════════════════════════════════════════════════════════════════════════════

# ┌─ Main Namespace ─────────────────────────────────────────────────────────────┐
namespace eval ::CBFlow::Utilities::DisplayUtils {

    # ┌─ Namespace Variables ─────────────────────────────────────────────────────┐
    variable version "v1.0.0"
    variable debug_mode false

    # Logo configuration
    variable LOGO_NAME "CBFLOW"
    variable COMPANY_NAME "Custom Backend Flow"
    variable TAGLINE "Physical Design Automation Framework"
    variable COPYRIGHT "© 2025 CBFlow Team"
    variable FRAMEWORK_VERSION "v1.0.0"
    variable LOGO_MESSAGE "Advanced Physical Design Flow Management"

    # ┌─ ASCII Art Character Definitions ─────────────────────────────────────────┐

    # Define ASCII art patterns for each character
    variable ASCII_CHARS
    array set ASCII_CHARS {
        "A" {
            "  █████  "
            " ██   ██ "
            " ███████ "
            " ██   ██ "
            " ██   ██ "
        }
        "B" {
            " ██████  "
            " ██   ██ "
            " ██████  "
            " ██   ██ "
            " ██████  "
        }
        "C" {
            "  ██████ "
            " ██      "
            " ██      "
            " ██      "
            "  ██████ "
        }
        "D" {
            " ██████  "
            " ██   ██ "
            " ██   ██ "
            " ██   ██ "
            " ██████  "
        }
        "E" {
            " ███████ "
            " ██      "
            " █████   "
            " ██      "
            " ███████ "
        }
        "F" {
            " ███████ "
            " ██      "
            " █████   "
            " ██      "
            " ██      "
        }
        "G" {
            "  ██████ "
            " ██      "
            " ██  ███ "
            " ██   ██ "
            "  ██████ "
        }
        "H" {
            " ██   ██ "
            " ██   ██ "
            " ███████ "
            " ██   ██ "
            " ██   ██ "
        }
        "I" {
            " ███████ "
            "    ██   "
            "    ██   "
            "    ██   "
            " ███████ "
        }
        "L" {
            " ██      "
            " ██      "
            " ██      "
            " ██      "
            " ███████ "
        }
        "O" {
            "  ██████ "
            " ██   ██ "
            " ██   ██ "
            " ██   ██ "
            "  ██████ "
        }
        "W" {
            " ██   ██ "
            " ██   ██ "
            " ██ █ ██ "
            " ███ ███ "
            " ██   ██ "
        }
        " " {
            "         "
            "         "
            "         "
            "         "
            "         "
        }
    }

    # ┌─ Border Configuration Functions ──────────────────────────────────────────┐

    proc get_border_style {} {
        global env

        # Check for ASCII border preference
        if {([info exists env(USE_ASCII_BORDERS)] && $env(USE_ASCII_BORDERS) eq "1") ||
            [info exists ::env(USE_ASCII_BORDERS)]} {
            return [list \
                "+---------------------------------------------------------------------------+" \
                "|" \
                "+---------------------------------------------------------------------------+"]
        } else {
            return [list \
                "╔═══════════════════════════════════════════════════════════════════════════╗" \
                "║" \
                "╚═══════════════════════════════════════════════════════════════════════════╝"]
        }
    }

    # ┌─ ASCII Art Generation Functions ──────────────────────────────────────────┐

    proc generate_ascii_char {char} {
        variable ASCII_CHARS
        set upper_char [string toupper $char]

        if {[info exists ASCII_CHARS($upper_char)]} {
            return $ASCII_CHARS($upper_char)
        } else {
            # Return space pattern for unknown characters
            return $ASCII_CHARS(" ")
        }
    }

    proc generate_logo_art {logo_text} {
        # Generate ASCII art for the entire logo
        set char_patterns {}

        # Get ASCII patterns for each character
        for {set i 0} {$i < [string length $logo_text]} {incr i} {
            set char [string index $logo_text $i]
            lappend char_patterns [generate_ascii_char $char]
        }

        # Combine patterns line by line
        set logo_lines {}
        for {set row 0} {$row < 5} {incr row} {
            set line ""
            foreach pattern $char_patterns {
                append line [lindex $pattern $row]
            }
            lappend logo_lines $line
        }

        return $logo_lines
    }

    proc center_text {text width} {
        set text_len [string length $text]
        if {$text_len >= $width} {
            return [string range $text 0 [expr {$width - 1}]]
        }

        set padding [expr {($width - $text_len) / 2}]
        set left_pad [string repeat " " $padding]
        set right_pad [string repeat " " [expr {$width - $text_len - $padding}]]

        return "${left_pad}${text}${right_pad}"
    }

    # ┌─ Logo Display Functions ──────────────────────────────────────────────────┐

    proc display_company_info {} {
        variable COMPANY_NAME
        variable TAGLINE
        variable COPYRIGHT
        variable FRAMEWORK_VERSION
        variable LOGO_MESSAGE

        lassign [get_border_style] top_border side_border bottom_border

        # Display company information
        puts "${side_border}[center_text $COMPANY_NAME 75]${side_border}"
        puts "${side_border}[center_text $TAGLINE 75]${side_border}"
        puts "${side_border}[string repeat " " 75]${side_border}"
        puts "${side_border}[center_text $LOGO_MESSAGE 75]${side_border}"
        puts "${side_border}[string repeat " " 75]${side_border}"
        puts "${side_border}[center_text "$COPYRIGHT | Version: $FRAMEWORK_VERSION" 75]${side_border}"
        puts "${side_border}[string repeat " " 75]${side_border}"
    }

    proc display_logo_art {} {
        variable LOGO_NAME

        lassign [get_border_style] top_border side_border bottom_border

        # Generate and display ASCII art logo
        set logo_lines [generate_logo_art $LOGO_NAME]

        foreach line $logo_lines {
            puts "${side_border}[center_text $line 75]${side_border}"
        }

        puts "${side_border}[string repeat " " 75]${side_border}"
    }

    proc display_full_logo {} {
        lassign [get_border_style] top_border side_border bottom_border

        puts ""
        puts $top_border
        puts "${side_border}[string repeat " " 75]${side_border}"

        # Display ASCII art logo
        display_logo_art

        # Display company information
        display_company_info

        puts $bottom_border
        puts ""
    }

    proc display_simple_header {title subtitle} {
        lassign [get_border_style] top_border side_border bottom_border

        puts ""
        puts $top_border
        puts "${side_border}[center_text $title 75]${side_border}"
        if {$subtitle ne ""} {
            puts "${side_border}[center_text $subtitle 75]${side_border}"
        }
        puts $bottom_border
        puts ""
    }

    # ┌─ Script Header Functions ─────────────────────────────────────────────────┐

    proc show_script_header {script_name description} {
        variable FRAMEWORK_VERSION

        display_simple_header "CBFlow $script_name" $description
        puts "Framework Version: $FRAMEWORK_VERSION"
        puts "Timestamp: [clock format [clock seconds] -format "%Y-%m-%d %H:%M:%S"]"
        puts ""
    }

    proc show_usage_section {title items} {
        puts "$title:"
        foreach item $items {
            puts "  $item"
        }
        puts ""
    }

    # ┌─ Progress Display Functions ──────────────────────────────────────────────┐

    proc display_progress_bar {current total {width 50} {char "█"}} {
        set percentage [expr {$current * 100.0 / $total}]
        set filled [expr {int($current * $width / $total)}]
        set empty [expr {$width - $filled}]

        set progress_bar "[string repeat $char $filled][string repeat "░" $empty]"
        puts -nonewline "\r\[${progress_bar}\] [format "%.1f%%" $percentage] ($current/$total)"
        flush stdout

        if {$current == $total} {
            puts ""
        }
    }

    proc display_status_message {status message} {
        set timestamp [clock format [clock seconds] -format "%H:%M:%S"]

        switch -- $status {
            "info" { set prefix "ℹ️" }
            "warning" { set prefix "⚠️" }
            "error" { set prefix "❌" }
            "success" { set prefix "✅" }
            default { set prefix "🔵" }
        }

        puts "\[$timestamp\] $prefix $message"
    }

    # ┌─ Table Display Functions ─────────────────────────────────────────────────┐

    proc display_table {headers rows} {
        # Calculate column widths
        set col_widths {}
        for {set i 0} {$i < [llength $headers]} {incr i} {
            set max_width [string length [lindex $headers $i]]

            foreach row $rows {
                set cell_width [string length [lindex $row $i]]
                if {$cell_width > $max_width} {
                    set max_width $cell_width
                }
            }

            lappend col_widths [expr {$max_width + 2}]
        }

        # Display header
        set separator ""
        set header_line ""

        for {set i 0} {$i < [llength $headers]} {incr i} {
            set width [lindex $col_widths $i]
            set header [lindex $headers $i]

            append header_line [format "%-${width}s" $header]
            append separator [string repeat "-" $width]
        }

        puts $header_line
        puts $separator

        # Display rows
        foreach row $rows {
            set row_line ""
            for {set i 0} {$i < [llength $row]} {incr i} {
                set width [lindex $col_widths $i]
                set cell [lindex $row $i]
                append row_line [format "%-${width}s" $cell]
            }
            puts $row_line
        }
    }

    # ┌─ Export Functions ────────────────────────────────────────────────────────┐
    # Export key functions to global namespace for backwards compatibility

    proc export_to_global {} {
        # Export main logo display function
        proc ::display_early_logo {} {
            ::CBFlow::Utilities::DisplayUtils::display_full_logo
        }

        proc ::show_script_header {script_name description} {
            ::CBFlow::Utilities::DisplayUtils::show_script_header $script_name $description
        }

        proc ::show_usage_section {title items} {
            ::CBFlow::Utilities::DisplayUtils::show_usage_section $title $items
        }

        proc ::display_progress_bar {current total {width 50} {char "█"}} {
            ::CBFlow::Utilities::DisplayUtils::display_progress_bar $current $total $width $char
        }

        proc ::display_status_message {status message} {
            ::CBFlow::Utilities::DisplayUtils::display_status_message $status $message
        }

        proc ::display_table {headers rows} {
            ::CBFlow::Utilities::DisplayUtils::display_table $headers $rows
        }
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# Auto-Export to Global Namespace
# ═══════════════════════════════════════════════════════════════════════════════

# Automatically export functions when this file is sourced
::CBFlow::Utilities::DisplayUtils::export_to_global