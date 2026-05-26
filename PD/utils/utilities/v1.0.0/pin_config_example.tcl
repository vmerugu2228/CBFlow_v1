#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# Example IO Pin Placement Configuration
#
# Usage in FC:
#   source place_io_pins.tcl
#   source pin_config_example.tcl      ;# or your custom pin config
#   place_groups pin_groups
#   report_pin_placement "reports/pin_placement.rpt"
#
# Or from command file:
#   place_from_file "/path/to/my_pin_config.tcl"
#
# Format:
#   group_name {
#       side      "left|right|top|bottom"
#       start     <offset from corner in microns>
#       layer     "M4|M5|..."
#       pitch     <pin-to-pin spacing in microns>
#       direction "in|out|inout"
#       pins      {pin1 pin2 pin3 ...}
#   }
#
# Side reference:
#   ┌──────── top ────────┐
#   │                     │
#   left                right
#   │                     │
#   └────── bottom ───────┘
#
# Start offset is measured from:
#   left/right: bottom corner upward
#   top/bottom: left corner rightward
# ═══════════════════════════════════════════════════════════════════════════════

array set pin_groups {

    data_input_bus {
        side        "left"
        start       10.0
        layer       "M4"
        pitch       2.0
        direction   "in"
        pins        {
            data_in[0] data_in[1] data_in[2] data_in[3]
            data_in[4] data_in[5] data_in[6] data_in[7]
            data_in[8] data_in[9] data_in[10] data_in[11]
            data_in[12] data_in[13] data_in[14] data_in[15]
        }
    }

    address_bus {
        side        "left"
        start       50.0
        layer       "M4"
        pitch       2.0
        direction   "in"
        pins        {
            addr[0] addr[1] addr[2] addr[3]
            addr[4] addr[5] addr[6] addr[7]
            addr[8] addr[9] addr[10] addr[11]
        }
    }

    write_control {
        side        "left"
        start       80.0
        layer       "M4"
        pitch       3.0
        direction   "in"
        pins        {wr_en rd_en byte_en[0] byte_en[1] byte_en[2] byte_en[3]}
    }

    clock_and_reset {
        side        "bottom"
        start       30.0
        layer       "M5"
        pitch       10.0
        direction   "in"
        pins        {clk reset_n}
    }

    scan_pins {
        side        "bottom"
        start       60.0
        layer       "M5"
        pitch       5.0
        direction   "inout"
        pins        {scan_en scan_in test_mode scan_clk}
    }

    data_output_bus {
        side        "right"
        start       10.0
        layer       "M4"
        pitch       2.0
        direction   "out"
        pins        {
            data_out[0] data_out[1] data_out[2] data_out[3]
            data_out[4] data_out[5] data_out[6] data_out[7]
            data_out[8] data_out[9] data_out[10] data_out[11]
            data_out[12] data_out[13] data_out[14] data_out[15]
        }
    }

    status_signals {
        side        "right"
        start       50.0
        layer       "M4"
        pitch       3.0
        direction   "out"
        pins        {valid ready error overflow underflow}
    }

    scan_output {
        side        "top"
        start       30.0
        layer       "M5"
        pitch       5.0
        direction   "out"
        pins        {scan_out[0] scan_out[1] scan_out[2] scan_out[3]}
    }

    power_control {
        side        "top"
        start       70.0
        layer       "M5"
        pitch       8.0
        direction   "in"
        pins        {pwr_switch_ack pwr_switch_req sleep_mode}
    }
}
