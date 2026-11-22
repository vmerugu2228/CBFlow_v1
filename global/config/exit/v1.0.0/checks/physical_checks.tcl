################################################################################
# CBflow v2.0.0 — Physical Design Check Library
# File: PD/config/exit/v1.0.0/checks/physical_checks.tcl
#
# 20 physical design checks for exit milestone validation.
# Covers: connectivity, power mesh, well taps, endcaps, fillers, IO, PG, spare.
################################################################################

array set physical_checks {

    "unconnected_cells" {
        "id"          "PHYSICAL_0001"
        "description"             "Cells with unconnected pins"
        "script"                  "check_legality.tcl"
        "category"                "physical"
        "severity"                "critical"
        "min_phase_index"               "1"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "check_connectivity.rpt"
        "metric_pattern"          "^Unconnected cells\\s*:\\s*(\\d+)"
        "operator"                "=="
        "default_threshold"       "0"
    }

    "floating_pins" {
        "id"          "PHYSICAL_0002"
        "description"             "Floating (undriven) input pins"
        "script"                  "check_legality.tcl"
        "category"                "physical"
        "severity"                "critical"
        "min_phase_index"               "1"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "check_connectivity.rpt"
        "metric_pattern"          "^Floating input pins\\s*:\\s*(\\d+)"
        "operator"                "=="
        "default_threshold"       "0"
    }

    "open_nets" {
        "id"          "PHYSICAL_0003"
        "description"             "Physically open signal nets"
        "script"                  "check_routing.tcl"
        "category"                "physical"
        "severity"                "critical"
        "min_phase_index"               "1"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "check_connectivity.rpt"
        "metric_pattern"          "^Open signal nets\\s*:\\s*(\\d+)"
        "operator"                "=="
        "default_threshold"       "0"
    }

    "missing_vias_power" {
        "id"          "PHYSICAL_0004"
        "description"             "Missing vias at power-mesh junctions"
        "script"                  "check_routing.tcl"
        "category"                "physical"
        "severity"                "critical"
        "min_phase_index"               "2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_pg.rpt"
        "metric_pattern"          "^Missing power vias\\s*:\\s*(\\d+)"
        "operator"                "=="
        "default_threshold"       "0"
    }

    "power_strap_coverage" {
        "id"          "PHYSICAL_0005"
        "description"             "VDD/VSS strap coverage per layer"
        "script"                  "check_utilization.tcl"
        "category"                "physical"
        "severity"                "major"
        "min_phase_index"               "1"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "report_power.rpt"
        "metric_pattern"          "^Power strap coverage\\s*:\\s*(\\d+\\.?\\d*)%"
        "unit"        "%"
        "operator"                ">="
        "default_threshold"       "95.0"
    }

    "power_strap_width" {
        "id"          "PHYSICAL_0006"
        "description"             "Power strap width compliance with design rules"
        "script"                  "check_drc.tcl"
        "category"                "physical"
        "severity"                "major"
        "min_phase_index"               "2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_power.rpt"
        "metric_pattern"          "^Power strap width violations\\s*:\\s*(\\d+)"
        "operator"                "=="
        "default_threshold"       "0"
    }

    "power_mesh_ir_drop" {
        "id"          "PHYSICAL_0007"
        "description"             "IR drop at worst case within voltage margin"
        "script"                  "check_power.tcl"
        "category"                "physical"
        "severity"                "critical"
        "min_phase_index"               "2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_power.rpt"
        "metric_pattern"          "^Worst IR drop\\s*:\\s*(\\d+\\.?\\d*)\\s*mV"
        "operator"                "<="
        "default_threshold"       "30.0"
    }

    "em_violations" {
        "id"          "PHYSICAL_0008"
        "description"             "Electromigration current density violations"
        "script"                  "check_power.tcl"
        "category"                "physical"
        "severity"                "critical"
        "min_phase_index"               "2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_power.rpt"
        "metric_pattern"          "^EM violations\\s*:\\s*(\\d+)"
        "unit"        "%"
        "operator"                "=="
        "default_threshold"       "0"
    }

    "well_tap_coverage" {
        "id"          "PHYSICAL_0009"
        "description"             "N-well/P-well tap coverage (latch-up)"
        "script"                  "check_utilization.tcl"
        "category"                "physical"
        "severity"                "major"
        "min_phase_index"               "2"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "check_legality.rpt"
        "metric_pattern"          "^Well tap coverage\\s*:\\s*(\\d+\\.?\\d*)%"
        "unit"        "%"
        "operator"                ">="
        "default_threshold"       "100.0"
    }

    "endcap_completeness" {
        "id"          "PHYSICAL_0010"
        "description"             "Row-end endcap cells present at all row boundaries"
        "script"                  "check_legality.tcl"
        "category"                "physical"
        "severity"                "major"
        "min_phase_index"               "2"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "check_legality.rpt"
        "metric_pattern"          "^Missing endcap cells\\s*:\\s*(\\d+)"
        "operator"                "=="
        "default_threshold"       "0"
    }

    "filler_completeness" {
        "id"          "PHYSICAL_0011"
        "description"             "Gaps in cell rows without filler"
        "script"                  "check_legality.tcl"
        "category"                "physical"
        "severity"                "major"
        "min_phase_index"               "2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "check_legality.rpt"
        "metric_pattern"          "^Filler gaps\\s*:\\s*(\\d+)"
        "operator"                "=="
        "default_threshold"       "0"
    }

    "decap_placement" {
        "id"          "PHYSICAL_0012"
        "description"             "Decap cell distribution for power integrity"
        "script"                  "check_utilization.tcl"
        "category"                "physical"
        "severity"                "minor"
        "min_phase_index"               "2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_design.rpt"
        "metric_pattern"          "^Decap coverage\\s*:\\s*(\\d+\\.?\\d*)%"
        "operator"                ">="
        "default_threshold"       "85.0"
    }

    "boundary_cell_check" {
        "id"          "PHYSICAL_0013"
        "description"             "Voltage area boundary cells properly placed"
        "script"                  "check_legality.tcl"
        "category"                "physical"
        "severity"                "major"
        "min_phase_index"               "2"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "check_legality.rpt"
        "metric_pattern"          "^Missing boundary cells\\s*:\\s*(\\d+)"
        "operator"                "=="
        "default_threshold"       "0"
    }

    "pin_density_check" {
        "id"          "PHYSICAL_0014"
        "description"             "Pin density (routability)"
        "script"                  "check_file_exists.tcl"
        "category"                "physical"
        "severity"                "minor"
        "min_phase_index"               "1"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "report_design.rpt"
        "metric_pattern"          "^Pin density hotspots\\s*:\\s*(\\d+)"
        "unit"        "%"
        "operator"                "<="
        "default_threshold"       "0"
    }

    "io_ring_continuity" {
        "id"          "PHYSICAL_0015"
        "description"             "Breaks in the IO power ring"
        "script"                  "check_routing.tcl"
        "category"                "physical"
        "severity"                "critical"
        "min_phase_index"               "1"
        "applicable_milestones"   "FP_EXIT PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "report_pg.rpt"
        "metric_pattern"          "^IO ring breaks\\s*:\\s*(\\d+)"
        "operator"                "=="
        "default_threshold"       "0"
    }

    "pg_connection_check" {
        "id"          "PHYSICAL_0016"
        "description"             "Standard cells without PG connection"
        "script"                  "check_routing.tcl"
        "category"                "physical"
        "severity"                "critical"
        "min_phase_index"               "2"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "report_pg.rpt"
        "metric_pattern"          "^Unconnected PG cells\\s*:\\s*(\\d+)"
        "operator"                "=="
        "default_threshold"       "0"
    }

    "spare_cell_placement" {
        "id"          "PHYSICAL_0017"
        "description"             "Spare cell distribution across design area"
        "script"                  "check_utilization.tcl"
        "category"                "physical"
        "severity"                "minor"
        "min_phase_index"               "2"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "report_design.rpt"
        "metric_pattern"          "^Spare cell coverage\\s*:\\s*(\\d+\\.?\\d*)%"
        "operator"                ">="
        "default_threshold"       "90.0"
    }

    "tie_cell_connection" {
        "id"          "PHYSICAL_0018"
        "description"             "Inputs tied directly to VDD/VSS (no tie cell)"
        "script"                  "check_legality.tcl"
        "category"                "physical"
        "severity"                "major"
        "min_phase_index"               "2"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "check_connectivity.rpt"
        "metric_pattern"          "^Missing tie cells\\s*:\\s*(\\d+)"
        "operator"                "=="
        "default_threshold"       "0"
    }

    "blockage_coverage" {
        "id"          "PHYSICAL_0019"
        "description"             "Hard/soft blockage proper coverage in floorplan"
        "script"                  "check_file_exists.tcl"
        "category"                "physical"
        "severity"                "minor"
        "min_phase_index"               "1"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "report_design.rpt"
        "metric_pattern"          "^Blockage coverage errors\\s*:\\s*(\\d+)"
        "unit"        "%"
        "operator"                "=="
        "default_threshold"       "0"
    }

    "cell_padding_check" {
        "id"          "PHYSICAL_0020"
        "description"             "Cell-to-cell spacing / padding violations"
        "script"                  "check_file_exists.tcl"
        "category"                "physical"
        "severity"                "minor"
        "min_phase_index"               "2"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "check_legality.rpt"
        "metric_pattern"          "^Cell padding violations\\s*:\\s*(\\d+)"
        "operator"                "=="
        "default_threshold"       "0"
    }

}
