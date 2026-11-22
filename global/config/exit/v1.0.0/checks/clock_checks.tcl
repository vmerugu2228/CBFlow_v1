########################################################################
# CBflow Exit Check Library — Clock Checks
# 25 clock-related checks for CTS/timing quality verification
########################################################################

array set clock_checks {
    "clock_skew" {
        "id"          "CLOCK_0001"
        "description"             "Global clock skew across all sequential elements"
        "script"                  "check_clock_quality.tcl"
        "category"                "clock"
        "severity"                "critical"
        "min_phase_index"               "0"
        "applicable_milestones"   "CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "report_clock_timing.skew.rpt"
        "metric_pattern"          {Max\s+Skew\s*:\s*([\d.]+)}
        "unit"        "ps"
        "operator"                "<="
        "default_threshold"       "100"
    }
    "clock_insertion_delay" {
        "id"          "CLOCK_0002"
        "description"             "Maximum clock insertion delay from source to sink"
        "script"                  "check_clock_quality.tcl"
        "category"                "clock"
        "severity"                "major"
        "min_phase_index"               "0"
        "applicable_milestones"   "CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "report_clock_timing.setup.rpt"
        "metric_pattern"          {Max\s+Insertion\s+Delay\s*:\s*([\d.]+)}
        "unit"        "ps"
        "operator"                "<="
        "default_threshold"       "500"
    }
    "clock_coverage" {
        "id"          "CLOCK_0003"
        "description"             "Percentage of sequential elements covered by clock tree"
        "script"                  "check_clock_quality.tcl"
        "category"                "clock"
        "severity"                "critical"
        "min_phase_index"               "1"
        "applicable_milestones"   "CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "report_clock_qor.rpt"
        "metric_pattern"          {Clock\s+Coverage\s*:\s*([\d.]+)\s*%}
        "unit"        "%"
        "operator"                ">="
        "default_threshold"       "100.0"
    }
    "clock_latency_balance" {
        "id"          "CLOCK_0004"
        "description"             "Latency balance across clock domains"
        "script"                  "check_clock_quality.tcl"
        "category"                "clock"
        "severity"                "major"
        "min_phase_index"               "1"
        "applicable_milestones"   "CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "report_clock_qor.rpt"
        "metric_pattern"          {Latency\s+Imbalance\s*:\s*([\d.]+)}
        "unit"        "ps"
        "operator"                "<="
        "default_threshold"       "50"
    }
    "clock_transition" {
        "id"          "CLOCK_0005"
        "description"             "Maximum clock transition time at sink pins"
        "script"                  "check_clock_quality.tcl"
        "category"                "clock"
        "severity"                "major"
        "min_phase_index"               "1"
        "applicable_milestones"   "CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "report_clock_timing.setup.rpt"
        "metric_pattern"          {Max\s+Transition\s*:\s*([\d.]+)}
        "operator"                "<="
        "default_threshold"       "150"
    }
    "clock_power" {
        "id"          "CLOCK_0006"
        "description"             "Total clock network dynamic power consumption"
        "script"                  "check_power.tcl"
        "category"                "clock"
        "severity"                "major"
        "min_phase_index"               "1"
        "applicable_milestones"   "CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "report_power.rpt"
        "metric_pattern"          {Clock\s+Network\s+Power\s*:\s*([\d.]+)}
        "operator"                "<="
        "default_threshold"       "50.0"
    }
    "clock_fanout" {
        "id"          "CLOCK_0007"
        "description"             "Maximum fanout of any clock buffer in the tree"
        "script"                  "check_clock_quality.tcl"
        "category"                "clock"
        "severity"                "minor"
        "min_phase_index"               "1"
        "applicable_milestones"   "CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "report_clock_qor.rpt"
        "metric_pattern"          {Max\s+Fanout\s*:\s*(\d+)}
        "operator"                "<="
        "default_threshold"       "32"
    }
    "useful_skew" {
        "id"          "CLOCK_0008"
        "description"             "Timing benefit gained from useful skew optimization"
        "script"                  "check_clock_quality.tcl"
        "category"                "clock"
        "severity"                "minor"
        "min_phase_index"               "1"
        "applicable_milestones"   "CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "report_clock_timing.setup.rpt"
        "metric_pattern"          {Useful\s+Skew\s+Benefit\s*:\s*([\d.]+)}
        "unit"        "ps"
        "operator"                ">="
        "default_threshold"       "0"
    }
    "non_clock_cells_in_clock" {
        "id"          "CLOCK_0009"
        "description"             "Non-clock cells (non-buffer/inverter) found in clock tree"
        "script"                  "check_clock_quality.tcl"
        "category"                "clock"
        "severity"                "critical"
        "min_phase_index"               "1"
        "applicable_milestones"   "CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "report_clock_qor.rpt"
        "metric_pattern"          {Non-Clock\s+Cells\s*:\s*(\d+)}
        "operator"                "=="
        "default_threshold"       "0"
    }
    "undefined_cells_in_clock" {
        "id"          "CLOCK_0010"
        "description"             "Cells in clock tree not in the allowed clock cell list"
        "script"                  "check_clock_quality.tcl"
        "category"                "clock"
        "severity"                "critical"
        "min_phase_index"               "1"
        "applicable_milestones"   "CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "report_clock_qor.rpt"
        "metric_pattern"          {Undefined\s+Clock\s+Cells\s*:\s*(\d+)}
        "operator"                "=="
        "default_threshold"       "0"
    }
    "clock_reconvergence" {
        "id"          "CLOCK_0011"
        "description"             "Clock reconvergence pessimism removal analysis"
        "script"                  "check_clock_quality.tcl"
        "category"                "clock"
        "severity"                "major"
        "min_phase_index"               "2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_clock_timing.setup.rpt"
        "metric_pattern"          {CRPR\s+Pessimism\s*:\s*([\d.]+)}
        "operator"                "<="
        "default_threshold"       "50"
    }
    "clock_mesh_drc" {
        "id"          "CLOCK_0012"
        "description"             "DRC violations on clock mesh routing"
        "script"                  "check_drc.tcl"
        "category"                "clock"
        "severity"                "major"
        "min_phase_index"               "2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_clock_qor.rpt"
        "metric_pattern"          {Clock\s+Mesh\s+DRC\s*:\s*(\d+)}
        "operator"                "=="
        "default_threshold"       "0"
    }
    "icg_usage" {
        "id"          "CLOCK_0013"
        "description"             "ICG cell utilization ratio across the design"
        "script"                  "check_utilization.tcl"
        "category"                "clock"
        "severity"                "minor"
        "min_phase_index"               "1"
        "applicable_milestones"   "CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "report_clock_qor.rpt"
        "metric_pattern"          {ICG\s+Utilization\s*:\s*([\d.]+)\s*%}
        "unit"        "%"
        "operator"                ">="
        "default_threshold"       "50.0"
    }
    "clock_buffer_ratio" {
        "id"          "CLOCK_0014"
        "description"             "Ratio of clock buffers to clock inverters in tree"
        "script"                  "check_clock_quality.tcl"
        "category"                "clock"
        "severity"                "minor"
        "min_phase_index"               "2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_clock_qor.rpt"
        "metric_pattern"          {Buffer/Inverter\s+Ratio\s*:\s*([\d.]+)}
        "unit"        "%"
        "operator"                "<="
        "default_threshold"       "3.0"
    }
    "clock_ndr_compliance" {
        "id"          "CLOCK_0015"
        "description"             "Clock net compliance with non-default routing rules"
        "script"                  "check_drc.tcl"
        "category"                "clock"
        "severity"                "major"
        "min_phase_index"               "2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_clock_qor.rpt"
        "metric_pattern"          {NDR\s+Violations\s*:\s*(\d+)}
        "operator"                "=="
        "default_threshold"       "0"
    }
    "clock_tree_depth" {
        "id"          "CLOCK_0016"
        "description"             "Maximum clock tree depth measured in logic levels"
        "script"                  "check_clock_quality.tcl"
        "category"                "clock"
        "severity"                "minor"
        "min_phase_index"               "1"
        "applicable_milestones"   "CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "report_clock_qor.rpt"
        "metric_pattern"          {Max\s+Tree\s+Depth\s*:\s*(\d+)}
        "operator"                "<="
        "default_threshold"       "20"
    }
    "clock_duty_cycle" {
        "id"          "CLOCK_0017"
        "description"             "Clock duty cycle distortion at worst sink"
        "script"                  "check_clock_quality.tcl"
        "category"                "clock"
        "severity"                "major"
        "min_phase_index"               "2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_clock_timing.setup.rpt"
        "metric_pattern"          {Duty\s+Cycle\s+Distortion\s*:\s*([\d.]+)\s*%}
        "operator"                "<="
        "default_threshold"       "5.0"
    }
    "clock_jitter_margin" {
        "id"          "CLOCK_0018"
        "description"             "Remaining jitter and uncertainty margin"
        "script"                  "check_clock_quality.tcl"
        "category"                "clock"
        "severity"                "major"
        "min_phase_index"               "2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_clock_timing.setup.rpt"
        "metric_pattern"          {Jitter\s+Margin\s*:\s*([\d.]+)}
        "unit"        "ps"
        "operator"                ">="
        "default_threshold"       "10"
    }
    "inter_clock_skew" {
        "id"          "CLOCK_0019"
        "description"             "Skew between different clock domains at crossing points"
        "script"                  "check_clock_quality.tcl"
        "category"                "clock"
        "severity"                "major"
        "min_phase_index"               "2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_clock_timing.skew.rpt"
        "metric_pattern"          {Inter-Domain\s+Skew\s*:\s*([\d.]+)}
        "unit"        "ps"
        "operator"                "<="
        "default_threshold"       "200"
    }
    "clock_gating_efficiency" {
        "id"          "CLOCK_0020"
        "description"             "Percentage of gated clocks in the design"
        "script"                  "check_utilization.tcl"
        "category"                "clock"
        "severity"                "minor"
        "min_phase_index"               "2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_power.rpt"
        "metric_pattern"          {Clock\s+Gating\s+Efficiency\s*:\s*([\d.]+)\s*%}
        "unit"        "%"
        "operator"                ">="
        "default_threshold"       "70.0"
    }
    "clock_occ_timing" {
        "id"          "CLOCK_0021"
        "description"             "On-chip clock controller timing closure"
        "script"                  "check_timing.tcl"
        "category"                "clock"
        "severity"                "minor"
        "min_phase_index"               "3"
        "applicable_milestones"   "BTO"
        "report_pattern"          "report_clock_timing.setup.rpt"
        "metric_pattern"          {OCC\s+WNS\s*:\s*([-\d.]+)}
        "operator"                ">="
        "default_threshold"       "0"
    }
    "clock_dft_coverage" {
        "id"          "CLOCK_0022"
        "description"             "DFT clock controllability and observability coverage"
        "script"                  "check_file_exists.tcl"
        "category"                "clock"
        "severity"                "minor"
        "min_phase_index"               "3"
        "applicable_milestones"   "BTO"
        "report_pattern"          "report_clock_qor.rpt"
        "metric_pattern"          {DFT\s+Clock\s+Coverage\s*:\s*([\d.]+)\s*%}
        "unit"        "%"
        "operator"                ">="
        "default_threshold"       "95.0"
    }
    "clock_latency_max" {
        "id"          "CLOCK_0023"
        "description"             "Absolute maximum clock latency limit across all sinks"
        "script"                  "check_clock_quality.tcl"
        "category"                "clock"
        "severity"                "major"
        "min_phase_index"               "1"
        "applicable_milestones"   "CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "report_clock_timing.setup.rpt"
        "metric_pattern"          {Max\s+Latency\s*:\s*([\d.]+)}
        "unit"        "ps"
        "operator"                "<="
        "default_threshold"       "1000"
    }
    "clock_hold_margin" {
        "id"          "CLOCK_0024"
        "description"             "CTS hold timing margin across all clock paths"
        "script"                  "check_timing.tcl"
        "category"                "clock"
        "severity"                "critical"
        "min_phase_index"               "2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_clock_timing.skew.rpt"
        "metric_pattern"          {Hold\s+Margin\s*:\s*([-\d.]+)}
        "operator"                ">="
        "default_threshold"       "0"
    }
    "clock_power_vs_budget" {
        "id"          "CLOCK_0025"
        "description"             "Clock power consumption relative to allocated power budget"
        "script"                  "check_power.tcl"
        "category"                "clock"
        "severity"                "major"
        "min_phase_index"               "2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_power.rpt"
        "metric_pattern"          {Clock\s+Power\s+Budget\s+Used\s*:\s*([\d.]+)\s*%}
        "operator"                "<="
        "default_threshold"       "100.0"
    }
}
