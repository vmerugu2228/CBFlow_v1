################################################################################
# CBflow v2.0.0 — Physical Design Check Library
# File: PD/config/exit/v1.0.0/checks/physical_checks.tcl
#
# 20 physical design checks for exit milestone validation.
# Covers: connectivity, power mesh, well taps, endcaps, fillers, IO, PG, spare.
################################################################################

array set physical_checks {

    "unconnected_cells" {
        "description"             "Cells with unconnected pins — no dangling connections"
        "script"                  "check_legality.tcl"
        "category"                "physical"
        "severity"                "critical"
        "min_phase"               "P1"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "check_connectivity.rpt"
        "metric_pattern"          "^Unconnected cells\\s*:\\s*(\\d+)"
        "operator"                "=="
        "default_threshold"       "0"
    }

    "floating_pins" {
        "description"             "Floating input pins — no undriven inputs"
        "script"                  "check_legality.tcl"
        "category"                "physical"
        "severity"                "critical"
        "min_phase"               "P1"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "check_connectivity.rpt"
        "metric_pattern"          "^Floating input pins\\s*:\\s*(\\d+)"
        "operator"                "=="
        "default_threshold"       "0"
    }

    "open_nets" {
        "description"             "Physically open signal nets — no broken connections"
        "script"                  "check_routing.tcl"
        "category"                "physical"
        "severity"                "critical"
        "min_phase"               "P1"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "check_connectivity.rpt"
        "metric_pattern"          "^Open signal nets\\s*:\\s*(\\d+)"
        "operator"                "=="
        "default_threshold"       "0"
    }

    "missing_vias_power" {
        "description"             "Missing vias in power mesh — all junctions connected"
        "script"                  "check_routing.tcl"
        "category"                "physical"
        "severity"                "critical"
        "min_phase"               "P2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_pg.rpt"
        "metric_pattern"          "^Missing power vias\\s*:\\s*(\\d+)"
        "operator"                "=="
        "default_threshold"       "0"
    }

    "power_strap_coverage" {
        "description"             "VDD/VSS strap coverage per layer meets requirement"
        "script"                  "check_utilization.tcl"
        "category"                "physical"
        "severity"                "major"
        "min_phase"               "P1"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "report_power.rpt"
        "metric_pattern"          "^Power strap coverage\\s*:\\s*(\\d+\\.?\\d*)%"
        "operator"                ">="
        "default_threshold"       "95.0"
    }

    "power_strap_width" {
        "description"             "Power strap width compliance with design rules"
        "script"                  "check_drc.tcl"
        "category"                "physical"
        "severity"                "major"
        "min_phase"               "P2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_power.rpt"
        "metric_pattern"          "^Power strap width violations\\s*:\\s*(\\d+)"
        "operator"                "=="
        "default_threshold"       "0"
    }

    "power_mesh_ir_drop" {
        "description"             "IR drop at worst case within voltage margin"
        "script"                  "check_power.tcl"
        "category"                "physical"
        "severity"                "critical"
        "min_phase"               "P2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_power.rpt"
        "metric_pattern"          "^Worst IR drop\\s*:\\s*(\\d+\\.?\\d*)\\s*mV"
        "operator"                "<="
        "default_threshold"       "30.0"
    }

    "em_violations" {
        "description"             "Electromigration current density violations"
        "script"                  "check_power.tcl"
        "category"                "physical"
        "severity"                "critical"
        "min_phase"               "P2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_power.rpt"
        "metric_pattern"          "^EM violations\\s*:\\s*(\\d+)"
        "operator"                "=="
        "default_threshold"       "0"
    }

    "well_tap_coverage" {
        "description"             "N-well/P-well tap coverage ratio meets latch-up rules"
        "script"                  "check_utilization.tcl"
        "category"                "physical"
        "severity"                "major"
        "min_phase"               "P2"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "check_legality.rpt"
        "metric_pattern"          "^Well tap coverage\\s*:\\s*(\\d+\\.?\\d*)%"
        "operator"                ">="
        "default_threshold"       "100.0"
    }

    "endcap_completeness" {
        "description"             "Row-end endcap cells present at all row boundaries"
        "script"                  "check_legality.tcl"
        "category"                "physical"
        "severity"                "major"
        "min_phase"               "P2"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "check_legality.rpt"
        "metric_pattern"          "^Missing endcap cells\\s*:\\s*(\\d+)"
        "operator"                "=="
        "default_threshold"       "0"
    }

    "filler_completeness" {
        "description"             "Filler cell coverage — no gaps in cell rows"
        "script"                  "check_legality.tcl"
        "category"                "physical"
        "severity"                "major"
        "min_phase"               "P2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "check_legality.rpt"
        "metric_pattern"          "^Filler gaps\\s*:\\s*(\\d+)"
        "operator"                "=="
        "default_threshold"       "0"
    }

    "decap_placement" {
        "description"             "Decap cell distribution for power integrity"
        "script"                  "check_utilization.tcl"
        "category"                "physical"
        "severity"                "minor"
        "min_phase"               "P2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_design.rpt"
        "metric_pattern"          "^Decap coverage\\s*:\\s*(\\d+\\.?\\d*)%"
        "operator"                ">="
        "default_threshold"       "85.0"
    }

    "boundary_cell_check" {
        "description"             "Voltage area boundary cells properly placed"
        "script"                  "check_legality.tcl"
        "category"                "physical"
        "severity"                "major"
        "min_phase"               "P2"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "check_legality.rpt"
        "metric_pattern"          "^Missing boundary cells\\s*:\\s*(\\d+)"
        "operator"                "=="
        "default_threshold"       "0"
    }

    "pin_density_check" {
        "description"             "Pin density within routability threshold"
        "script"                  "check_file_exists.tcl"
        "category"                "physical"
        "severity"                "minor"
        "min_phase"               "P1"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "report_design.rpt"
        "metric_pattern"          "^Pin density hotspots\\s*:\\s*(\\d+)"
        "operator"                "<="
        "default_threshold"       "0"
    }

    "io_ring_continuity" {
        "description"             "IO power ring continuity — no breaks in ring"
        "script"                  "check_routing.tcl"
        "category"                "physical"
        "severity"                "critical"
        "min_phase"               "P1"
        "applicable_milestones"   "FP_EXIT PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "report_pg.rpt"
        "metric_pattern"          "^IO ring breaks\\s*:\\s*(\\d+)"
        "operator"                "=="
        "default_threshold"       "0"
    }

    "pg_connection_check" {
        "description"             "All standard cells PG connected — no floating power/ground"
        "script"                  "check_routing.tcl"
        "category"                "physical"
        "severity"                "critical"
        "min_phase"               "P2"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "report_pg.rpt"
        "metric_pattern"          "^Unconnected PG cells\\s*:\\s*(\\d+)"
        "operator"                "=="
        "default_threshold"       "0"
    }

    "spare_cell_placement" {
        "description"             "Spare cell distribution across design area"
        "script"                  "check_utilization.tcl"
        "category"                "physical"
        "severity"                "minor"
        "min_phase"               "P2"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "report_design.rpt"
        "metric_pattern"          "^Spare cell coverage\\s*:\\s*(\\d+\\.?\\d*)%"
        "operator"                ">="
        "default_threshold"       "90.0"
    }

    "tie_cell_connection" {
        "description"             "Tie-high/tie-low cell completeness — no direct VDD/VSS ties"
        "script"                  "check_legality.tcl"
        "category"                "physical"
        "severity"                "major"
        "min_phase"               "P2"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "check_connectivity.rpt"
        "metric_pattern"          "^Missing tie cells\\s*:\\s*(\\d+)"
        "operator"                "=="
        "default_threshold"       "0"
    }

    "blockage_coverage" {
        "description"             "Hard/soft blockage proper coverage in floorplan"
        "script"                  "check_file_exists.tcl"
        "category"                "physical"
        "severity"                "minor"
        "min_phase"               "P1"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "report_design.rpt"
        "metric_pattern"          "^Blockage coverage errors\\s*:\\s*(\\d+)"
        "operator"                "=="
        "default_threshold"       "0"
    }

    "cell_padding_check" {
        "description"             "Cell-to-cell spacing padding meets requirements"
        "script"                  "check_file_exists.tcl"
        "category"                "physical"
        "severity"                "minor"
        "min_phase"               "P2"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "check_legality.rpt"
        "metric_pattern"          "^Cell padding violations\\s*:\\s*(\\d+)"
        "operator"                "=="
        "default_threshold"       "0"
    }

}
