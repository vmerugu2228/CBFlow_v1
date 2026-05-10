#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# OMNI FLOW - Edit Restricted Configuration
# Description: Variables that cannot be modified by users without authorization
# ═══════════════════════════════════════════════════════════════════════════════

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                         RESTRICTED VARIABLES DEFINITION                     │
# └─────────────────────────────────────────────────────────────────────────────┘

# Critical flow configuration variables that should not be modified by users
set restricted_variables {
    "flow(version)"
    "flow(config_version)"
    "flow(omni_version)"
    "flow(build_date)"
    "flow(author)"
    "flow(types)"
    "flow(parallel_node_types)"
    "flow(stages,synth)"
    "flow(stages,pnr)"
    "flow(stages,signoff)"
    "flow(mandatory_global_vars)"
    "flow(mandatory_vars,synth)"
    "flow(mandatory_vars,pnr)"
    "flow(mandatory_vars,signoff)"
    "flow(valid_status)"
    "flow(run_init_directories)"
    "runtime(terminal_type)"
    "runtime(timeout,synthesis)"
    "runtime(timeout,place)"
    "runtime(timeout,cts)"
    "runtime(timeout,route)"
    "runtime(timeout,signoff)"
}

# Technology node critical parameters (foundry-specific)
set restricted_tech_variables {
    "tech(node)"
    "tech(process)"
    "tech(foundry)"
    "tech(metal_stack)"
    "tech(metal,count)"
    "tech(dr,min_width)"
    "tech(dr,min_spacing)"
    "tech(dr,via_size)"
    "tech(dr,track_pitch)"
    "tech(dr,site_width)"
    "tech(dr,site_height)"
    "tech(elec,supply_voltage)"
    "tech(elec,threshold_voltage)"
}

# Tool configuration restrictions
set restricted_tool_variables {
    "tools(synth,tool)"
    "tools(pnr,tool)"
    "tools(sta,tool)"
    "tools(drc,tool)"
    "tools(lvs,tool)"
    "tools(erc,tool)"
    "tools(antenna,tool)"
}

# Leadership and team contact information (sensitive)
set restricted_contact_variables {
    "flow(leads,project_lead_email)"
    "flow(leads,deputy_project_lead_email)"
    "flow(leads,chip_lead_email)"
    "flow(leads,deputy_chip_lead_email)"
    "flow(leads,technical_lead_email)"
    "flow(leads,cad_manager_email)"
    "flow(teams,frontend_lead_email)"
    "flow(teams,backend_lead_email)"
    "flow(teams,verification_lead_email)"
    "flow(teams,dft_lead_email)"
    "flow(teams,signoff_lead_email)"
    "flow(teams,frontend_group)"
    "flow(teams,backend_group)"
    "flow(teams,verification_group)"
    "flow(teams,dft_group)"
    "flow(teams,signoff_group)"
    "flow(teams,cad_group)"
    "flow(management,engineering_manager_email)"
    "flow(management,design_director_email)"
    "flow(emergency,oncall_engineer)"
    "flow(emergency,escalation_manager)"
    "flow(notification,smtp_server)"
    "flow(notification,smtp_port)"
    "flow(notification,from_address)"
    "flow(notification,reply_to)"
}

# Combine all restricted variables
set all_restricted_variables [concat $restricted_variables $restricted_tech_variables $restricted_tool_variables $restricted_contact_variables]

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                         BYPASS MECHANISM                                   │
# └─────────────────────────────────────────────────────────────────────────────┘

# Bypass variable - if set to true, allows overriding restricted variables
# Setting this will trigger email notification to leads
set flow(bypass_restrictions) "false"

# Bypass reasons (required when bypass is enabled)
set flow(bypass_reason) ""
set flow(bypass_requester) ""
set flow(bypass_requester_email) ""
set flow(bypass_approval_ref) ""

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                         RESTRICTION VALIDATION FUNCTIONS                   │
# └─────────────────────────────────────────────────────────────────────────────┘

proc validate_variable_restrictions {} {
    global all_restricted_variables flow
    
    set violations {}
    set bypass_active false
    
    # Check if bypass is enabled
    if {[info exists flow(bypass_restrictions)] && $flow(bypass_restrictions) eq "true"} {
        set bypass_active true
        handle_warning "⚠️  RESTRICTION BYPASS ENABLED"
        
        # Validate bypass requirements
        if {![info exists flow(bypass_reason)] || $flow(bypass_reason) eq ""} {
            handle_error "Bypass reason is required when restrictions are bypassed"
            return false
        }
        
        if {![info exists flow(bypass_requester)] || $flow(bypass_requester) eq ""} {
            handle_error "Bypass requester name is required when restrictions are bypassed"
            return false
        }
        
        if {![info exists flow(bypass_requester_email)] || $flow(bypass_requester_email) eq ""} {
            handle_error "Bypass requester email is required when restrictions are bypassed"
            return false
        }
    }
    
    # Check for user config overrides of restricted variables
    set user_config_files {
        "user_config.tcl"
        "setup/user_config.tcl"
        "../user_config.tcl"
        "config/user_override.tcl"
        "local_config.tcl"
    }
    
    foreach config_file $user_config_files {
        if {[file exists $config_file]} {
            set violations [concat $violations [check_file_for_restrictions $config_file]]
        }
    }
    
    if {[llength $violations] > 0} {
        if {$bypass_active} {
            handle_warning "🚨 RESTRICTED VARIABLES OVERRIDDEN (BYPASS ACTIVE)"
            foreach violation $violations {
                handle_warning "  • $violation"
            }
            
            # Send notification email to leads
            send_restriction_bypass_notification $violations
            
            return true  ; # Allow with notification
        } else {
            handle_error "❌ RESTRICTED VARIABLES MODIFIED WITHOUT AUTHORIZATION"
            foreach violation $violations {
                handle_error "  • $violation"
            }
            handle_error ""
            handle_error "To override these restrictions:"
            handle_error "1. Set flow(bypass_restrictions) \"true\" in your config"
            handle_error "2. Set flow(bypass_reason) \"<reason>\" explaining why"
            handle_error "3. Set flow(bypass_requester) \"<your_name>\""
            handle_error "4. Set flow(bypass_requester_email) \"<your_email>\""
            handle_error "5. Set flow(bypass_approval_ref) \"<approval_reference>\" (optional)"
            handle_error ""
            handle_error "This will send notification to project leads."
            
            return false
        }
    }
    
    return true
}

proc check_file_for_restrictions {filename} {
    global all_restricted_variables
    
    set violations {}
    
    if {![file exists $filename]} {
        return $violations
    }
    
    set fd [open $filename "r"]
    set line_num 0
    
    while {[gets $fd line] >= 0} {
        incr line_num
        
        # Skip comments and empty lines
        set line [string trim $line]
        if {[string match "#*" $line] || $line eq ""} {
            continue
        }
        
        # Check for 'set variable_name' patterns
        if {[regexp {^\s*set\s+([^\s\(]+(?:\([^)]+\))?)\s+} $line -> var_name]} {
            if {$var_name in $all_restricted_variables} {
                lappend violations "$filename:$line_num - $var_name"
            }
        }
    }
    
    close $fd
    return $violations
}

proc send_restriction_bypass_notification {violations} {
    global flow
    
    # Collect recipient emails
    set recipients {}
    
    # Add project leads
    if {[info exists flow(leads,project_lead_email)]} {
        lappend recipients $flow(leads,project_lead_email)
    }
    if {[info exists flow(leads,chip_lead_email)]} {
        lappend recipients $flow(leads,chip_lead_email)
    }
    if {[info exists flow(leads,technical_lead_email)]} {
        lappend recipients $flow(leads,technical_lead_email)
    }
    if {[info exists flow(leads,cad_manager_email)]} {
        lappend recipients $flow(leads,cad_manager_email)
    }
    
    # Add management
    if {[info exists flow(management,engineering_manager_email)]} {
        lappend recipients $flow(management,engineering_manager_email)
    }
    
    if {[llength $recipients] == 0} {
        handle_warning "No recipient emails configured for restriction bypass notification"
        return
    }
    
    # Prepare email content
    set timestamp [clock format [clock seconds] -format "%Y-%m-%d %H:%M:%S"]
    set hostname [info hostname]
    set username [exec whoami]
    set working_dir $::env(CBFLOW_RUN_DIR)
    
    set subject "🚨 OMNI FLOW: Restricted Variables Override - Approval Required"
    
    set email_body "OMNI FLOW SECURITY ALERT: Restricted Configuration Override\n"
    append email_body "═══════════════════════════════════════════════════════════\n\n"
    
    append email_body "OVERRIDE DETAILS:\n"
    append email_body "• Timestamp: $timestamp\n"
    append email_body "• Hostname: $hostname\n"
    append email_body "• Username: $username\n"
    append email_body "• Working Directory: $working_dir\n"
    append email_body "• Requester: $flow(bypass_requester)\n"
    append email_body "• Requester Email: $flow(bypass_requester_email)\n"
    append email_body "• Reason: $flow(bypass_reason)\n"
    
    if {[info exists flow(bypass_approval_ref)] && $flow(bypass_approval_ref) ne ""} {
        append email_body "• Approval Reference: $flow(bypass_approval_ref)\n"
    }
    
    append email_body "\n"
    append email_body "RESTRICTED VARIABLES MODIFIED:\n"
    foreach violation $violations {
        append email_body "• $violation\n"
    }
    
    append email_body "\n"
    append email_body "VARIABLE VALUES:\n"
    foreach violation $violations {
        set var_info [split $violation " - "]
        if {[llength $var_info] >= 2} {
            set var_name [lindex $var_info 1]
            if {[info exists ::$var_name]} {
                set var_value [set ::$var_name]
                append email_body "• $var_name = \"$var_value\"\n"
            }
        }
    }
    
    append email_body "\n"
    append email_body "ACTION REQUIRED:\n"
    append email_body "1. Review the override request and justification\n"
    append email_body "2. Verify approval reference (if provided)\n"
    append email_body "3. Contact requester if additional information needed\n"
    append email_body "4. Document approval/rejection in project records\n"
    
    append email_body "\n"
    append email_body "This is an automated notification from OMNI FLOW.\n"
    append email_body "Please do not reply to this email.\n"
    
    # Send email notification
    send_email_notification $recipients $subject $email_body
    
    handle_info "📧 Restriction bypass notification sent to:"
    foreach recipient $recipients {
        handle_info "   • $recipient"
    }
}

proc send_email_notification {recipients subject body} {
    global flow
    
    # Get SMTP configuration
    set smtp_server "localhost"
    set smtp_port "25"
    set from_address "omni-flow@localhost"
    
    if {[info exists flow(notification,smtp_server)]} {
        set smtp_server $flow(notification,smtp_server)
    }
    if {[info exists flow(notification,smtp_port)]} {
        set smtp_port $flow(notification,smtp_port)
    }
    if {[info exists flow(notification,from_address)]} {
        set from_address $flow(notification,from_address)
    }
    
    # Create temporary email file
    set temp_file "/tmp/omni_flow_notification_[clock seconds].txt"
    set fd [open $temp_file "w"]
    
    puts $fd "From: $from_address"
    puts $fd "To: [join $recipients ", "]"
    puts $fd "Subject: $subject"
    puts $fd ""
    puts $fd $body
    
    close $fd
    
    # Send email using sendmail (if available)
    if {[catch {exec which sendmail} sendmail_path]} {
        # Fallback: save email to file for manual processing
        set notification_file "omni_flow_restriction_notification_[clock seconds].txt"
        file rename $temp_file $notification_file
        handle_warning "Sendmail not available. Notification saved to: $notification_file"
    } else {
        # Send email
        if {[catch {exec $sendmail_path [join $recipients " "] < $temp_file} result]} {
            handle_warning "Failed to send email notification: $result"
            set notification_file "omni_flow_restriction_notification_[clock seconds].txt"
            file rename $temp_file $notification_file
            handle_warning "Notification saved to: $notification_file"
        } else {
            handle_info "Email notification sent successfully"
            file delete $temp_file
        }
    }
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                         UTILITY FUNCTIONS                                  │
# └─────────────────────────────────────────────────────────────────────────────┘

proc list_restricted_variables {} {
    global all_restricted_variables
    
    handle_info "OMNI FLOW - Restricted Variables List:"
    handle_info "═══════════════════════════════════════════════════════════════"
    handle_info ""
    handle_info "The following variables cannot be modified in user configuration files:"
    handle_info ""
    
    set count 1
    foreach var $all_restricted_variables {
        handle_info "$count. $var"
        incr count
    }
    
    handle_info ""
    handle_info "Total restricted variables: [llength $all_restricted_variables]"
    handle_info ""
    handle_info "To override these restrictions (with notification to leads):"
    handle_info "• Set flow(bypass_restrictions) \"true\""
    handle_info "• Set flow(bypass_reason) \"<justification>\""
    handle_info "• Set flow(bypass_requester) \"<your_name>\""
    handle_info "• Set flow(bypass_requester_email) \"<your_email>\""
}

proc show_restriction_status {} {
    global flow
    
    handle_info "OMNI FLOW - Restriction Status:"
    handle_info "═══════════════════════════════════════════════════════════════"
    
    if {[info exists flow(bypass_restrictions)] && $flow(bypass_restrictions) eq "true"} {
        handle_warning "🚨 RESTRICTIONS BYPASSED"
        if {[info exists flow(bypass_reason)]} {
            handle_info "Reason: $flow(bypass_reason)"
        }
        if {[info exists flow(bypass_requester)]} {
            handle_info "Requester: $flow(bypass_requester)"
        }
        if {[info exists flow(bypass_requester_email)]} {
            handle_info "Email: $flow(bypass_requester_email)"
        }
    } else {
        handle_info "✅ RESTRICTIONS ACTIVE"
        handle_info "All restricted variables are protected from user modification"
    }
}

# Load utility functions if available
if {[file exists [file dirname [info script]]/../utils/utils.tcl]} {
    source [file dirname [info script]]/../utils/utils.tcl
} else {
    # Fallback implementations
    proc handle_info {msg} { puts "INFO: $msg" }
    proc handle_warning {msg} { puts "WARNING: $msg" }
    proc handle_error {msg} { puts "ERROR: $msg" }
}

# Auto-validate when this file is sourced
if {[info script] ne "" && [file tail [info script]] eq "edit_restricted_config.tcl"} {
    # Only validate if we're being sourced, not executed directly
    if {$argc == 0} {
        validate_variable_restrictions
    }
}