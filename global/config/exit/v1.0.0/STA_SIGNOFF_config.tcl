# ═══════════════════════════════════════════════════════════════════════════════
# STA_SIGNOFF Checklist — static timing signoff of a released exit
# The STA run's own checks (the exit's PNR checklist lives in <EXIT>_config).
# Values come from the tool overlay's report map (STA_<tool>_config.tcl
# checklist,*): worst / total over every timed MMMC scenario.
# Published with the STA run's SmartGrid entry (the exit it verified).
# ═══════════════════════════════════════════════════════════════════════════════

set milestone_info(name)        "STA_SIGNOFF"
set milestone_info(discipline)  "PD"
set milestone_info(flow_type)   "STA"
set milestone_info(stage)       "merge_reports"
set milestone_info(description) "Static timing signoff over all MMMC scenarios"
set milestone_info(stage_node)  "merge_reports1"

# No library check packs — every STA check is listed below.
array set check_packs {}

array set mandatory_checks {
    "sta_scenarios" {
        "id"                "STA_0001"
        "description"       "MMMC scenarios timed"
        "criteria"          "at least one scenario timed"
        "operator"          ">="
        "default_threshold" "1"
        "min_phase_index"   "0"
    }
    "sta_failing_scenarios" {
        "id"                "STA_0002"
        "description"       "Scenarios failing setup or hold slack"
        "criteria"          "no scenario below the signoff slack"
        "operator"          "=="
        "default_threshold" "0"
        "min_phase_index"   "0"
    }
    "sta_setup_wns" {
        "id"                "STA_0003"
        "description"       "Worst setup slack (WNS) over all scenarios"
        "criteria"          "setup_wns >= threshold"
        "unit"              "ns"
        "operator"          ">="
        "default_threshold" "0"
        "min_phase_index"   "0"
    }
    "sta_setup_tns" {
        "id"                "STA_0004"
        "description"       "Worst setup total negative slack (TNS)"
        "criteria"          "setup_tns >= threshold"
        "unit"              "ns"
        "operator"          ">="
        "default_threshold" "0"
        "min_phase_index"   "0"
    }
    "sta_hold_wns" {
        "id"                "STA_0005"
        "description"       "Worst hold slack (WNS) over all scenarios"
        "criteria"          "hold_wns >= threshold"
        "unit"              "ns"
        "operator"          ">="
        "default_threshold" "0"
        "min_phase_index"   "0"
    }
    "sta_hold_tns" {
        "id"                "STA_0006"
        "description"       "Worst hold total negative slack (TNS)"
        "criteria"          "hold_tns >= threshold"
        "unit"              "ns"
        "operator"          ">="
        "default_threshold" "0"
        "min_phase_index"   "0"
    }
    "sta_max_tran" {
        "id"                "STA_0007"
        "description"       "Max transition violations (worst scenario)"
        "criteria"          "no max transition violations"
        "operator"          "=="
        "default_threshold" "0"
        "min_phase_index"   "0"
    }
    "sta_max_cap" {
        "id"                "STA_0008"
        "description"       "Max capacitance violations (worst scenario)"
        "criteria"          "no max capacitance violations"
        "operator"          "=="
        "default_threshold" "0"
        "min_phase_index"   "0"
    }
    "sta_dont_use" {
        "id"                "STA_0012"
        "description"       "Instances of don't-use cells in the netlist"
        "criteria"          "no don't-use cell instantiated"
        "operator"          "=="
        "default_threshold" "0"
        "min_phase_index"   "0"
    }
    "sta_dont_touch" {
        "id"                "STA_0013"
        "description"       "Don't-touch instance patterns missing from the netlist"
        "criteria"          "every don't-touch instance kept"
        "operator"          "=="
        "default_threshold" "0"
        "min_phase_index"   "0"
    }
}

array set optional_checks {
    "sta_max_fanout" {
        "id"                "STA_0009"
        "description"       "Max fanout violations (worst scenario)"
        "criteria"          "no max fanout violations"
        "operator"          "=="
        "default_threshold" "0"
        "min_phase_index"   "0"
    }
    "sta_noise" {
        "id"                "STA_0010"
        "description"       "Crosstalk noise violations (needs SI-capable STA)"
        "criteria"          "no noise violations"
        "operator"          "=="
        "default_threshold" "0"
        "min_phase_index"   "0"
    }
    "sta_total_power" {
        "id"                "STA_0011"
        "description"       "Total power, worst scenario (reported)"
        "criteria"          "reported"
        "unit"              "mW"
        "operator"          ">="
        "default_threshold" "0"
        "min_phase_index"   "0"
    }
}
