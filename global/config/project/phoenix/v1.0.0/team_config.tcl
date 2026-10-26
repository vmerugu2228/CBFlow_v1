#!/usr/bin/env tclsh
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                            TEAM CONFIGURATION                               ║
# ║                    Organizational and Team Information                       ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# This file contains all team, organizational, and contact information.
# It defines project leadership, team contacts, and notification settings.
#
# Usage: source config/project/team_config.tcl

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                         TEAM & ORGANIZATIONAL DATA                          ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# ┌─ Company Information ──────────────────────────────────────────────────────┐
array set team {
    company "CBFlow Development Team"
    department "Physical Design Engineering"
    organization "Semiconductor Division"
}

# ┌─ Project Leadership ───────────────────────────────────────────────────────┐
array set team {
    leads,project_lead "John Smith"
    leads,project_lead_email "john.smith@company.com"
    leads,chip_lead "Michael Chen"
    leads,chip_lead_email "michael.chen@company.com"
    leads,technical_lead "David Rodriguez"
    leads,technical_lead_email "david.rodriguez@company.com"
}

# ┌─ Engineering Team Leads ───────────────────────────────────────────────────┐
array set team {
    teams,frontend_lead "Alex Thompson"
    teams,frontend_lead_email "alex.thompson@company.com"
    teams,backend_lead "Emma Davis"
    teams,backend_lead_email "emma.davis@company.com"
    teams,verification_lead "Robert Wilson"
    teams,verification_lead_email "robert.wilson@company.com"
    teams,signoff_lead "James Brown"
    teams,signoff_lead_email "james.brown@company.com"
}

# ┌─ Group Email Lists ────────────────────────────────────────────────────────┐
array set team {
    groups,frontend "frontend-team@company.com"
    groups,backend "backend-team@company.com"
    groups,verification "verification-team@company.com"
    groups,signoff "signoff-team@company.com"
    groups,cad "cad-team@company.com"
}

# ┌─ Emergency Contacts ───────────────────────────────────────────────────────┐
array set team {
    emergency,oncall_engineer "oncall-engineer@company.com"
    emergency,escalation_manager "escalation@company.com"
    emergency,primary_contact "emergency@company.com"
}

# ┌─ Notification Settings ────────────────────────────────────────────────────┐
array set team {
    notification,smtp_server "smtp.company.com"
    notification,smtp_port "587"
    notification,from_address "flow-automation@company.com"
    notification,reply_to "no-reply@company.com"
    notification,enabled true
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                           TEAM HELPER FUNCTIONS                             ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# ┌─ Team Information Access Functions ────────────────────────────────────────┐
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
    return "unknown@company.com"
}

proc get_emergency_contact {} {
    global team
    if {[info exists team(emergency,oncall_engineer)]} {
        return $team(emergency,oncall_engineer)
    }
    return "emergency@company.com"
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
    return "${team_name}@company.com"
}

# ┌─ Team Validation Functions ────────────────────────────────────────────────┐
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

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                              INITIALIZATION                                 ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# Validate configuration on load
if {![info exists ::team_config_loaded]} {
    if {[validate_team_config]} {
        puts "INFO: Team configuration loaded successfully - $team(company)"
    } else {
        puts "WARNING: Team configuration has missing or invalid settings"
    }
    set ::team_config_loaded true
}

# ═══════════════════════════════════════════════════════════════════════════════
# END OF TEAM CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════════