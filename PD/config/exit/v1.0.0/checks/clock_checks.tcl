########################################################################
# CBflow Exit Check Library — Clock Checks
# 25 clock-related checks for CTS/timing quality verification
########################################################################

array set clock_checks {
    "clock_skew" {
        "description"             "Global clock skew across all sequential elements"
        "category"                "clock"
        "severity"                "critical"
        "min_phase"               "P0"
        "applicable_milestones"   "CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "report_clock_timing.skew.rpt"
        "metric_pattern"          {Max\s+Skew\s*:\s*([\d.]+)}
        "operator"                "<="
        "default_threshold"       "100"
    }
    "clock_insertion_delay" {
        "description"             "Maximum clock insertion delay from source to sink"
        "category"                "clock"
        "severity"                "major"
        "min_phase"               "P0"
        "applicable_milestones"   "CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "report_clock_timing.setup.rpt"
        "metric_pattern"          {Max\s+Insertion\s+Delay\s*:\s*([\d.]+)}
        "operator"                "<="
        "default_threshold"       "500"
    }
    "clock_coverage" {
        "description"             "Percentage of sequential elements covered by clock tree"
        "category"                "clock"
        "severity"                "critical"
        "min_phase"               "P1"
        "applicable_milestones"   "CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "report_clock_qor.rpt"
        "metric_pattern"          {Clock\s+Coverage\s*:\s*([\d.]+)\s*%}
        "operator"                ">="
        "default_threshold"       "100.0"
    }
    "clock_latency_balance" {
        "description"             "Latency balance across clock domains"
        "category"                "clock"
        "severity"                "major"
        "min_phase"               "P1"
        "applicable_milestones"   "CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "report_clock_qor.rpt"
        "metric_pattern"          {Latency\s+Imbalance\s*:\s*([\d.]+)}
        "operator"                "<="
        "default_threshold"       "50"
    }
    "clock_transition" {
        "description"             "Maximum clock transition time at sink pins"
        "category"                "clock"
        "severity"                "major"
        "min_phase"               "P1"
        "applicable_milestones"   "CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "report_clock_timing.setup.rpt"
        "metric_pattern"          {Max\s+Transition\s*:\s*([\d.]+)}
        "operator"                "<="
        "default_threshold"       "150"
    }
    "clock_power" {
        "description"             "Total clock network dynamic power consumption"
        "category"                "clock"
        "severity"                "major"
        "min_phase"               "P1"
        "applicable_milestones"   "CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "report_power.rpt"
        "metric_pattern"          {Clock\s+Network\s+Power\s*:\s*([\d.]+)}
        "operator"                "<="
        "default_threshold"       "50.0"
    }
    "clock_fanout" {
        "description"             "Maximum fanout of any clock buffer in the tree"
        "category"                "clock"
        "severity"                "minor"
        "min_phase"               "P1"
        "applicable_milestones"   "CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "report_clock_qor.rpt"
        "metric_pattern"          {Max\s+Fanout\s*:\s*(\d+)}
        "operator"                "<="
        "default_threshold"       "32"
    }
    "useful_skew" {
        "description"             "Timing benefit gained from useful skew optimization"
        "category"                "clock"
        "severity"                "minor"
        "min_phase"               "P1"
        "applicable_milestones"   "CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "report_clock_timing.setup.rpt"
        "metric_pattern"          {Useful\s+Skew\s+Benefit\s*:\s*([\d.]+)}
        "operator"                ">="
        "default_threshold"       "0"
    }
    "non_clock_cells_in_clock" {
        "description"             "Non-clock cells (non-buffer/inverter) found in clock tree"
        "category"                "clock"
        "severity"                "critical"
        "min_phase"               "P1"
        "applicable_milestones"   "CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "report_clock_qor.rpt"
        "metric_pattern"          {Non-Clock\s+Cells\s*:\s*(\d+)}
        "operator"                "=="
        "default_threshold"       "0"
    }
    "undefined_cells_in_clock" {
        "description"             "Cells in clock tree not in the allowed clock cell list"
        "category"                "clock"
        "severity"                "critical"
        "min_phase"               "P1"
        "applicable_milestones"   "CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "report_clock_qor.rpt"
        "metric_pattern"          {Undefined\s+Clock\s+Cells\s*:\s*(\d+)}
        "operator"                "=="
        "default_threshold"       "0"
    }
    "clock_reconvergence" {
        "description"             "Clock reconvergence pessimism removal analysis"
        "category"                "clock"
        "severity"                "major"
        "min_phase"               "P2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_clock_timing.setup.rpt"
        "metric_pattern"          {CRPR\s+Pessimism\s*:\s*([\d.]+)}
        "operator"                "<="
        "default_threshold"       "50"
    }
    "clock_mesh_drc" {
        "description"             "DRC violations on clock mesh routing"
        "category"                "clock"
        "severity"                "major"
        "min_phase"               "P2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_clock_qor.rpt"
        "metric_pattern"          {Clock\s+Mesh\s+DRC\s*:\s*(\d+)}
        "operator"                "=="
        "default_threshold"       "0"
    }
    "icg_usage" {
        "description"             "ICG cell utilization ratio across the design"
        "category"                "clock"
        "severity"                "minor"
        "min_phase"               "P1"
        "applicable_milestones"   "CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "report_clock_qor.rpt"
        "metric_pattern"          {ICG\s+Utilization\s*:\s*([\d.]+)\s*%}
        "operator"                ">="
        "default_threshold"       "50.0"
    }
    "clock_buffer_ratio" {
        "description"             "Ratio of clock buffers to clock inverters in tree"
        "category"                "clock"
        "severity"                "minor"
        "min_phase"               "P2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_clock_qor.rpt"
        "metric_pattern"          {Buffer/Inverter\s+Ratio\s*:\s*([\d.]+)}
        "operator"                "<="
        "default_threshold"       "3.0"
    }
    "clock_ndr_compliance" {
        "description"             "Clock net compliance with non-default routing rules"
        "category"                "clock"
        "severity"                "major"
        "min_phase"               "P2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_clock_qor.rpt"
        "metric_pattern"          {NDR\s+Violations\s*:\s*(\d+)}
        "operator"                "=="
        "default_threshold"       "0"
    }
    "clock_tree_depth" {
        "description"             "Maximum clock tree depth measured in logic levels"
        "category"                "clock"
        "severity"                "minor"
        "min_phase"               "P1"
        "applicable_milestones"   "CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "report_clock_qor.rpt"
        "metric_pattern"          {Max\s+Tree\s+Depth\s*:\s*(\d+)}
        "operator"                "<="
        "default_threshold"       "20"
    }
    "clock_duty_cycle" {
        "description"             "Clock duty cycle distortion at worst sink"
        "category"                "clock"
        "severity"                "major"
        "min_phase"               "P2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_clock_timing.setup.rpt"
        "metric_pattern"          {Duty\s+Cycle\s+Distortion\s*:\s*([\d.]+)\s*%}
        "operator"                "<="
        "default_threshold"       "5.0"
    }
    "clock_jitter_margin" {
        "description"             "Remaining jitter and uncertainty margin"
        "category"                "clock"
        "severity"                "major"
        "min_phase"               "P2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_clock_timing.setup.rpt"
        "metric_pattern"          {Jitter\s+Margin\s*:\s*([\d.]+)}
        "operator"                ">="
        "default_threshold"       "10"
    }
    "inter_clock_skew" {
        "description"             "Skew between different clock domains at crossing points"
        "category"                "clock"
        "severity"                "major"
        "min_phase"               "P2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_clock_timing.skew.rpt"
        "metric_pattern"          {Inter-Domain\s+Skew\s*:\s*([\d.]+)}
        "operator"                "<="
        "default_threshold"       "200"
    }
    "clock_gating_efficiency" {
        "description"             "Percentage of gated clocks in the design"
        "category"                "clock"
        "severity"                "minor"
        "min_phase"               "P2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_power.rpt"
        "metric_pattern"          {Clock\s+Gating\s+Efficiency\s*:\s*([\d.]+)\s*%}
        "operator"                ">="
        "default_threshold"       "70.0"
    }
    "clock_occ_timing" {
        "description"             "On-chip clock controller timing closure"
        "category"                "clock"
        "severity"                "minor"
        "min_phase"               "P3"
        "applicable_milestones"   "BTO"
        "report_pattern"          "report_clock_timing.setup.rpt"
        "metric_pattern"          {OCC\s+WNS\s*:\s*([-\d.]+)}
        "operator"                ">="
        "default_threshold"       "0"
    }
    "clock_dft_coverage" {
        "description"             "DFT clock controllability and observability coverage"
        "category"                "clock"
        "severity"                "minor"
        "min_phase"               "P3"
        "applicable_milestones"   "BTO"
        "report_pattern"          "report_clock_qor.rpt"
        "metric_pattern"          {DFT\s+Clock\s+Coverage\s*:\s*([\d.]+)\s*%}
        "operator"                ">="
        "default_threshold"       "95.0"
    }
    "clock_latency_max" {
        "description"             "Absolute maximum clock latency limit across all sinks"
        "category"                "clock"
        "severity"                "major"
        "min_phase"               "P1"
        "applicable_milestones"   "CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "report_clock_timing.setup.rpt"
        "metric_pattern"          {Max\s+Latency\s*:\s*([\d.]+)}
        "operator"                "<="
        "default_threshold"       "1000"
    }
    "clock_hold_margin" {
        "description"             "CTS hold timing margin across all clock paths"
        "category"                "clock"
        "severity"                "critical"
        "min_phase"               "P2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_clock_timing.skew.rpt"
        "metric_pattern"          {Hold\s+Margin\s*:\s*([-\d.]+)}
        "operator"                ">="
        "default_threshold"       "0"
    }
    "clock_power_vs_budget" {
        "description"             "Clock power consumption relative to allocated power budget"
        "category"                "clock"
        "severity"                "major"
        "min_phase"               "P2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_power.rpt"
        "metric_pattern"          {Clock\s+Power\s+Budget\s+Used\s*:\s*([\d.]+)\s*%}
        "operator"                "<="
        "default_threshold"       "100.0"
    }
}
