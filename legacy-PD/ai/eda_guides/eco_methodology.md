# ECO Methodology

## Overview

Engineering Change Order (ECO) is the process of making targeted modifications to a design after the main implementation flow is complete. ECOs are used to fix functional bugs, close timing violations, address DRC/LVS issues, and implement late-stage design changes — all while minimizing disruption to the existing layout. ECO discipline is what separates successful tapeouts from schedule disasters. A well-executed ECO fixes the problem with minimal collateral impact; a poorly executed one creates more problems than it solves.

## Types of ECO

### Functional ECO

Fixes logical bugs discovered after synthesis or during post-silicon validation planning. Requires gate-level netlist changes that alter the design's Boolean function.

**Triggers:**

- RTL bug found during gate-level simulation
- Late specification change
- Firmware/hardware interface correction
- Bug discovered during silicon bring-up (for respin)

### Timing ECO

Fixes setup or hold timing violations without changing the design's logical function.

**Triggers:**

- PrimeTime/Tempus signoff reveals timing violations
- IR drop analysis shows timing degradation
- SI analysis identifies crosstalk-induced timing failures
- Post-silicon timing failures

### Metal-Only ECO

Modifies only metal layers (routing) without changing cell placement or base layers. Allows mask re-fabrication of only the metal layers, saving significant cost and time (typically 2-4 weeks vs. 8-12 weeks for full mask set).

**Constraints:**

- No new cells can be added (must use existing spare cells or empty sites)
- No cell movement allowed
- Only metal and via layers can be modified
- Via layers that connect to lower base layers cannot be modified

### All-Layer ECO

Allows modification of all mask layers including base layers (diffusion, poly, implants). More expensive than metal-only ECO but provides full flexibility.

## Functional ECO Methodology

### Spare Cell Approach

Spare cells are pre-placed unused logic gates distributed throughout the design during initial PnR. When a functional ECO is needed, spare cells are repurposed to implement the fix.

**Spare cell insertion during PnR:**

```tcl
# Sprinkle spare cells during placement
# Typically 2-5% of total cell count
addFiller -cell {SPARE_INV SPARE_NAND2 SPARE_NOR2 SPARE_AOI22 SPARE_MUX2 SPARE_DFF} \
    -prefix SPARE -distributed

# Or define spare cell modules in RTL
// spare_cells.v
module spare_cells (
    input [3:0] spare_in,
    output [3:0] spare_out
);
    INV  spare_inv0  (.A(spare_in[0]), .Y(spare_out[0]));
    NAND2 spare_nand0 (.A(spare_in[1]), .B(spare_in[2]), .Y(spare_out[1]));
    NOR2  spare_nor0  (.A(spare_in[1]), .B(spare_in[2]), .Y(spare_out[2]));
    DFF   spare_dff0  (.D(spare_in[3]), .CK(1'b0), .Q(spare_out[3]));
endmodule
```

**Spare cell guidelines:**

- Distribute evenly across the die (avoid clustering)
- Include a variety of gate types (INV, NAND, NOR, AOI, MUX, DFF)
- Tie spare cell inputs to logic 0 or 1 to prevent floating gates
- Target 3-5% of total cell count as spare cells
- Place spare cells near major functional blocks

### Gate-Level ECO Patching

```tcl
# Example: Fix a missing AND condition on an enable signal
# Original: assign out = data;
# Fixed:    assign out = data & enable;

# Find a spare NAND2 near the target
set spare [get_cells SPARE_NAND2_row50_col100]

# Disconnect spare from tie-off
disconnect_net [get_nets spare_tie0] [get_pins $spare/A]
disconnect_net [get_nets spare_tie0] [get_pins $spare/B]

# Also need a spare inverter for NAND implementation of AND
set spare_inv [get_cells SPARE_INV_row50_col102]
disconnect_net [get_nets spare_tie1] [get_pins $spare_inv/A]

# Connect: NAND2(data, enable) -> INV -> out
connect_net data_net [get_pins $spare/A]
connect_net enable_net [get_pins $spare/B]
connect_net eco_nand_out [get_pins $spare/Y]
connect_net eco_nand_out [get_pins $spare_inv/A]

# Disconnect original driver and connect new output
disconnect_net [get_nets data_net] [get_pins original_driver/Y]
connect_net eco_final_out [get_pins $spare_inv/Y]
connect_net eco_final_out [get_pins target_sink/D]
```

### ECO Synthesis Flow

For more complex functional changes, use ECO synthesis:

1. Make the RTL fix.
2. Re-synthesize only the modified logic cone.
3. Map the changes to available spare cells.
4. Generate a gate-level ECO patch script.

```tcl
# In FC/DC
# Read original netlist
read_verilog original.v
# Read modified RTL
read_verilog -rtl modified_block.v
# ECO synthesis
compile_eco -spare_cells [get_cells SPARE_*]
# Write ECO script
write_changes -format icc2 -output eco_patch.tcl
```

## Timing ECO Methodology

### Setup Timing ECO Actions

Listed in order of preference (least disruptive first):

1. **Vt swapping:** Change HVT cells to SVT/LVT on critical paths. No placement change, minimal impact.

```tcl
size_cell u_critical_gate AND2X2_HVT -> AND2X2_SVT
```

2. **Cell upsizing:** Increase drive strength of cells on critical paths.

```tcl
size_cell u_weak_buf BUFX2 -> BUFX8
```

3. **Cell downsizing:** Decrease drive strength on non-critical paths to reduce load on critical nets.

4. **Buffer insertion:** Add buffers to break long nets or boost drive.

```tcl
insert_buffer long_critical_net BUFX4 -new_cell eco_buf_1
```

5. **Logic restructuring:** Re-map combinational logic to reduce depth.

6. **Useful skew adjustment:** Modify clock tree to intentionally skew the clock at specific endpoints.

### Hold Timing ECO Actions

1. **Delay cell insertion:** Insert dedicated delay cells on short paths.

```tcl
insert_buffer short_path_net DLYX2 -new_cell eco_dly_1
```

2. **Buffer insertion:** Add buffers (less precise than delay cells but more available).

3. **Cell downsizing on hold-critical paths:** Slower cells increase data path delay.

4. **Detour routing:** Add routing detour to increase wire delay (metal-only).

### PrimeTime ECO Guidance

PrimeTime can recommend ECO actions:

```tcl
# In PT: identify bottleneck cells
report_bottleneck -max_cells 30

# Automatic ECO recommendations
fix_eco_timing -type setup -methods {size_cell insert_buffer swap_vt}

# Validate ECO changes
update_timing -full
report_timing -max_paths 20

# Export changes
write_changes -format innovus -output pt_eco.tcl
```

### Applying ECO in PnR

```tcl
# In Innovus
source pt_eco.tcl

# Place ECO cells
place_eco_cells -fix_drc

# ECO routing
route_eco

# Verify
verify_drc
verify_connectivity

# Re-check timing
timeDesign -post_route
```

```tcl
# In FC/ICC2
source pt_eco.tcl

# Legalize ECO cells
place_eco_cells

# ECO route
route_eco

# Verify
check_routes
check_lvs
```

## Metal-Only ECO

### Freeze/Unfreeze Methodology

Metal-only ECO uses the freeze methodology to ensure that base layers are not modified:

```tcl
# Freeze all base layers (nothing below metal can change)
set_freeze_port -all
set_freeze_cell -all

# Unfreeze specific cells for ECO (spare cells only)
set_unfreeze_cell [get_cells SPARE_*]

# Make ECO changes (only spare cells and routing)
# ... ECO operations ...

# Route only ECO nets
route_eco -metal_only

# Verify that no base layer changes occurred
verify_freeze
```

### Metal-Only ECO Constraints

- Can only reroute existing nets or route new nets to spare cells
- Cannot move or add standard cells
- Cannot modify the power grid or clock tree (unless the clock tree is on metal layers)
- Limited by available spare cells and routing resources
- Via layers connecting to base layers (V0/contact layer) are frozen

### Metal-Only ECO Planning

Plan for metal-only ECO capability by:

1. Including adequate spare cells (3-5% of cell count)
2. Reserving routing capacity (do not push utilization above 85%)
3. Distributing spare cells near critical logic blocks
4. Including spare clock gating cells and spare flip-flops
5. Documenting spare cell locations and types

## ECO Verification

After every ECO, verify:

1. **Formal verification (LEC):** Prove that the ECO did not break functionality.
2. **Timing analysis (STA):** Confirm the ECO fixed the target violations without introducing new ones.
3. **DRC:** Verify no new DRC violations from ECO routing.
4. **LVS:** Verify connectivity matches the updated netlist.
5. **Power analysis:** Confirm the ECO did not push power over budget.

```tcl
# LEC verification of ECO
# Reference: pre-ECO netlist
# Implementation: post-ECO netlist
# Run formal verification (see formal_verification.md)
```

## Common Issues and Fixes

**Issue: No spare cells available near the ECO target**
- Check for spare cells in adjacent rows (within 50-100 um).
- Consider using filler cells that contain usable gates (some libraries offer this).
- As a last resort, resize an existing non-critical cell to free the site and place the ECO cell there.

**Issue: ECO routing causes DRC violations**
- The routing area may be congested. Try routing on different layers.
- Add routing detours to avoid congested regions.
- Run DRC-aware ECO routing: `route_eco -fix_drc`.

**Issue: ECO fixes setup but breaks hold**
- Cell upsizing can speed up paths, creating hold violations on related paths.
- Run both setup and hold checks after every ECO iteration.
- Fix hold violations after all setup ECOs are complete.

**Issue: Formal verification fails after functional ECO**
- Verify the ECO patch matches the intended RTL change.
- Check for accidental net disconnections or misconnections.
- Use the LEC debug flow to trace the failing logic cone.

**Issue: Metal-only ECO cannot fix the required change**
- If spare cells are insufficient, the fix requires an all-layer ECO.
- Document the limitation and escalate for schedule/cost decision.
- Consider a partial fix that mitigates the issue even if it cannot fully resolve it.

**Issue: ECO cycle time is too long (multiple PT-PnR iterations)**
- Use PT ECO guidance to batch multiple fixes in one iteration.
- Fix the worst violations first — diminishing returns on later iterations.
- Set a convergence criterion (e.g., stop when WNS > -10 ps).

## Best Practices

1. **Plan for ECO from the start** — insert spare cells, reserve routing capacity, document spare cell inventory.
2. **Fix the highest-impact issues first** — use bottleneck analysis to prioritize.
3. **Batch ECO changes** — applying 50 changes in one iteration is better than 50 single-change iterations.
4. **Verify after every ECO iteration** — LEC, STA, DRC, LVS. No exceptions.
5. **Minimize ECO scope** — change as few cells and nets as possible to reduce verification burden and risk.
6. **Prefer Vt swapping** as the first timing ECO action — it has no physical impact and rarely causes side effects.
7. **Keep a detailed ECO log** — what was changed, why, when, and what was verified.
8. **Run cross-corner/mode checks** — an ECO that fixes one corner may break another.
9. **Set a convergence deadline** — if timing is not closing after 3-4 ECO iterations, revisit the floorplan or constraints.
10. **Test metal-only ECO capability** early — do a trial metal-only ECO on a test case to verify the methodology works before you need it in production.
