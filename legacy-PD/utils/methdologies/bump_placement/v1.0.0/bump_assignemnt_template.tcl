###############################################################################
# SIGNAL I/O TO BUMP ASSIGNMENT FILE
# Format: REGION_NAME, llx, lly, urx, ury, {signal_list}
#
# REGION_NAME: Descriptive name for the region (e.g., LEFT_SIDE, TOP_EDGE)
# llx, lly:    Lower-left corner coordinates (microns)
# urx, ury:    Upper-right corner coordinates (microns)
# signal_list: List of signal names in curly braces
#
# Example:
# LEFT_SIDE, 100, 1000, 500, 5000, {sig_a sig_b sig_c data[0] data[1]}
#
# Notes:
# - Lines starting with # are comments
# - Bus signals use brackets: data[0], addr[7]
# - Signals are assigned to nearest available bump in the region
# - Bumps must be available (not already assigned to power/ground)
# - I/O cells are automatically placed near the assigned bumps
# - Signal direction is auto-detected (input/output/inout)
###############################################################################

# LEFT SIDE SIGNALS (Example: Low-speed control signals)
# Update coordinates based on your floorplan
LEFT_SIDE, 100, 1000, 500, 5000, {clk_in reset_n enable data_valid chip_select}

# RIGHT SIDE SIGNALS (Example: High-speed data outputs)
# Update coordinates based on your floorplan  
RIGHT_SIDE, 9500, 1000, 10000, 5000, {data_out[0] data_out[1] data_out[2] data_out[3] ready_out error_flag}

# TOP EDGE SIGNALS (Example: Address bus)
# Update coordinates based on your floorplan
TOP_EDGE, 2000, 9500, 8000, 10000, {addr[0] addr[1] addr[2] addr[3] addr[4] addr[5] addr[6] addr[7]}

# BOTTOM EDGE SIGNALS (Example: Debug and test signals)
# Update coordinates based on your floorplan
BOTTOM_EDGE, 2000, 100, 8000, 500, {debug[0] debug[1] debug[2] debug[3] test_mode scan_enable jtag_tck jtag_tdi jtag_tdo}

# CUSTOM REGION 1 (Example: Left-bottom corner for specific interface)
# You can define any rectangular region
INTERFACE_A, 100, 100, 1000, 1000, {if_a_clk if_a_data[0] if_a_data[1] if_a_valid if_a_ready}

# CUSTOM REGION 2 (Example: Right-top corner for another interface)
INTERFACE_B, 9000, 9000, 10000, 10000, {if_b_clk if_b_data[0] if_b_data[1] if_b_valid if_b_ready}

###############################################################################
# INSTRUCTIONS FOR USE:
###############################################################################
# 1. Update the coordinates (llx, lly, urx, ury) to match your die size
#    - Use coordinates in microns
#    - Make sure regions don't overlap with analog macros
#
# 2. Replace signal names with your actual signal names from the netlist
#    - Signal names must match exactly (case-sensitive)
#    - Bus signals use brackets: data[0], data[1], etc.
#
# 3. Group related signals by region for better organization
#    - Group by interface, protocol, or function
#    - Signals in same region will get nearby bumps
#
# 4. The script will:
#    - Find nearest available bump to region center for each signal
#    - Assign bump to signal net
#    - Place appropriate I/O cell (INPUT/OUTPUT/BIDIR) near bump
#    - Report any signals that couldn't be assigned
#
# 5. To get your die coordinates, run in Innovus:
#    dbGet top.fPlan.box
#    Returns: {llx lly urx ury}
#
# 6. To list your top-level signals, run in Innovus:
#    dbGet top.terms.name
###############################################################################
