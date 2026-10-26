#!/usr/bin/env tclsh
#===============================================================================
# Test Logo Display System
#
# Description: Test script for the enhanced logo display utilities
# Author: CBFlow Development Team
#===============================================================================

# Set up the core directory path
set CORE_DIR [expr {[info exists ::env(FLOW_DIR)] ? $::env(FLOW_DIR) : [file dirname [file dirname [file dirname [file dirname [file normalize [info script]]]]]]}]

# Source required configurations and utilities
source "$CORE_DIR/config/flow/current/logo_config.tcl"
source "$CORE_DIR/utils/utilities/current/logo_display.tcl"

# Test all display modes
puts "Testing CBFlow Logo Display System"
puts "=================================="

puts "\n1. Testing Full Header Display:"
::LogoDisplay::display_full_header

puts "\n2. Testing Compact Header Display:"
::LogoDisplay::display_compact_header

puts "\n3. Testing Minimal Header Display:"
::LogoDisplay::display_minimal_header

puts "\n4. Testing ASCII Only Display:"
::LogoDisplay::display_ascii_only

puts "\n5. Testing System Status Display:"
::LogoDisplay::display_system_status

puts "\n6. Testing Flow-Specific Logo (SYNTH):"
::LogoDisplay::display_flow_logo "SYNTH"

puts "\n7. Testing Flow-Specific Logo (PNR):"
::LogoDisplay::display_flow_logo "PNR"

puts "\n8. Testing Help Header:"
::LogoDisplay::display_help_header

puts "\n9. Testing Footer:"
::LogoDisplay::display_footer

puts "\n10. Testing Dynamic ASCII Generation for 'CBFlow':"
set dynamic_ascii [::LogoDisplay::generate_system_ascii "CBFlow"]
foreach line $dynamic_ascii {
    puts "║$line║"
}

puts "\nLogo Display System Test Complete!"