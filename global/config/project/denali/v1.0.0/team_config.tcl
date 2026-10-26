#!/usr/bin/env tclsh
# ============================================================================
# TEAM CONFIGURATION - Denali Project
# Organizational and Team Information
# ============================================================================
#
# This file contains all team, organizational, and contact information.
# It defines project leadership, team contacts, and notification settings.
#
# Usage: source config/project/denali/v1.0.0/team_config.tcl

# ============================================================================
# TEAM & ORGANIZATIONAL DATA
# ============================================================================

# -- Company Information ----------------------------------------------------
array set team {
    company "Denali Design Team"
    department "Physical Design Engineering"
    organization "SmartSoC Division"
}

# -- Project Leadership -----------------------------------------------------
array set team {
    leads,project_lead "Sarah Kim"
    leads,project_lead_email "sarah.kim@smartsoc.com"
    leads,chip_lead "Vikram Merugu"
    leads,chip_lead_email "vmerugu@smartsoc.com"
    leads,technical_lead "Raj Patel"
    leads,technical_lead_email "raj.patel@smartsoc.com"
}

# -- Engineering Team Leads -------------------------------------------------
array set team {
    teams,frontend_lead "Lisa Wang"
    teams,frontend_lead_email "lisa.wang@smartsoc.com"
    teams,backend_lead "Chris Johnson"
    teams,backend_lead_email "chris.johnson@smartsoc.com"
    teams,verification_lead "Priya Sharma"
    teams,verification_lead_email "priya.sharma@smartsoc.com"
    teams,signoff_lead "Tom Wilson"
    teams,signoff_lead_email "tom.wilson@smartsoc.com"
}

# -- Group Email Lists ------------------------------------------------------
array set team {
    groups,frontend "denali-frontend@smartsoc.com"
    groups,backend "denali-backend@smartsoc.com"
    groups,verification "denali-verification@smartsoc.com"
    groups,signoff "denali-signoff@smartsoc.com"
    groups,cad "denali-cad@smartsoc.com"
}

# -- Emergency Contacts -----------------------------------------------------
array set team {
    emergency,oncall_engineer "denali-oncall@smartsoc.com"
    emergency,escalation_manager "denali-escalation@smartsoc.com"
    emergency,primary_contact "denali-emergency@smartsoc.com"
}

# -- Notification Settings --------------------------------------------------
array set team {
    notification,smtp_server "smtp.smartsoc.com"
    notification,smtp_port "587"
    notification,from_address "denali-flow@smartsoc.com"
    notification,reply_to "no-reply@smartsoc.com"
    notification,enabled true
}

# ============================================================================
# TEAM HELPER FUNCTIONS
# ============================================================================

# -- Team Information Access Functions --------------------------------------
proc get_company_name {} {
    global team
    if {[info exists team(company)]} {
        return $team(company)
    }
    return "Design Company"
}

proc get_project_lead {} {
    global team
    if {[info exists team(leads,project_lead)]} {
        return $team(leads,project_lead)
    }
    return "Unknown"
}

proc get_project_lead_email {} {
    global team
    if {[info exists team(leads,project_lead_email)]} {
        return $team(leads,project_lead_email)
    }
    return "unknown@smartsoc.com"
}

proc get_emergency_contact {} {
    global team
    if {[info exists team(emergency,oncall_engineer)]} {
        return $team(emergency,oncall_engineer)
    }
    return "emergency@smartsoc.com"
}

proc get_team_lead {team_name} {
    global team
    set lead_key "teams,${team_name}_lead"
    if {[info exists team($lead_key)]} {
        return $team($lead_key)
    }
    return "Unknown Lead"
}

proc get_team_email {team_name} {
    global team
    set email_key "groups,$team_name"
    if {[info exists team($email_key)]} {
        return $team($email_key)
    }
    return "${team_name}@smartsoc.com"
}

# -- Team Validation Functions ----------------------------------------------
proc validate_team_config {} {
    global team

    set required_vars {
        "company"
        "leads,project_lead"
        "leads,project_lead_email"
        "emergency,oncall_engineer"
        "notification,smtp_server"
    }

    set missing_vars {}

    foreach var $required_vars {
        if {![info exists team($var)] || $team($var) eq ""} {
            lappend missing_vars $var
        }
    }

    if {[llength $missing_vars] > 0} {
        puts "WARNING: Missing team configuration variables: [join $missing_vars {, }]"
        return false
    }

    return true
}

proc get_all_team_contacts {} {
    global team

    set contacts {}

    # Get all team leads
    foreach key [array names team "teams,*_lead_email"] {
        if {$team($key) ne ""} {
            lappend contacts $team($key)
        }
    }

    # Get all group emails
    foreach key [array names team "groups,*"] {
        if {$team($key) ne ""} {
            lappend contacts $team($key)
        }
    }

    return $contacts
}

# ============================================================================
# INITIALIZATION
# ============================================================================

# Validate configuration on load
if {![info exists ::team_config_loaded]} {
    if {[validate_team_config]} {
        puts "INFO: Team configuration loaded successfully - $team(company)"
    } else {
        puts "WARNING: Team configuration has missing or invalid settings"
    }
    set ::team_config_loaded true
}

# ============================================================================
# END OF TEAM CONFIGURATION
# ============================================================================
