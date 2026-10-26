# Clock Tree Synthesis (CTS)

## Overview

Clock Tree Synthesis is one of the most critical steps in physical design. The clock network distributes the timing reference to every sequential element (flip-flop, latch, memory) in the design. The quality of the clock tree directly impacts timing closure, power consumption, and signal integrity. A poorly built clock tree can make timing closure impossible regardless of how well placement and routing are executed.

## Fundamental Concepts

### Clock Tree Metrics

- **Insertion Delay (Latency):** The propagation delay from the clock source (PLL output or clock port) to the clock pin of a flip-flop. Typical range: 200 ps to 2 ns depending on design size and technology.

- **Skew:** The difference in insertion delay between any two flip-flops in the same clock domain. Target: < 5-10% of clock period.

- **Transition (Slew):** The rise/fall time of the clock signal at each point. Must meet library-specified max_transition constraints. Typical target: < 80-100 ps at flip-flop clock pins.

- **Duty Cycle Distortion:** Change in the 50/50 duty cycle caused by asymmetric rise/fall delays through buffers and inverters. Critical for double-data-rate (DDR) interfaces.

- **Power:** The clock network typically consumes 30-50% of total dynamic power. Every buffer added increases switching power.

### Clock Tree Elements

- **Clock buffers:** Dedicated CK-prefixed buffers with balanced rise/fall delays and high drive strength.
- **Clock inverters:** Often preferred over buffers for better duty cycle control (inverter pairs cancel skew).
- **Clock gating cells (ICG):** Integrated clock gating cells that gate the clock to idle register banks.
- **Clock muxes:** Select between clock sources (functional vs. test, PLL vs. bypass).

## Clock Tree Topologies

### H-Tree

A balanced binary tree where each level splits the signal equally between two subtrees. The classic H-tree achieves near-zero skew by ensuring equal wire length from source to all sinks.

**Advantages:** Excellent skew balance, predictable latency.
**Disadvantages:** Inflexible to non-uniform sink distribution, wastes routing resources in sparse regions.

**Best for:** Memory arrays, regular datapath structures.

### Buffered Tree (Standard CTS)

The most common topology in ASIC design. The CTS engine builds a tree by clustering flip-flops geographically, inserting buffers to meet transition and skew targets, and balancing the tree through iterative refinement.

**Advantages:** Adapts to arbitrary sink distributions, tool-automated.
**Disadvantages:** Skew increases with design complexity, sensitive to placement quality.

**Best for:** General-purpose ASIC designs, SoCs.

### Clock Mesh

A grid of wires (mesh) driven by multiple buffers distributes the clock signal. All flip-flops tap into the mesh at their local position. The mesh inherently provides low skew because all points on the mesh see nearly the same signal arrival.

**Advantages:** Very low skew (< 10 ps), robust to OCV.
**Disadvantages:** High power (mesh wires switch every cycle), significant routing resource consumption.

**Best for:** High-performance processors, designs where skew < 20 ps is mandatory.

### Hybrid Mesh-Tree

A tree distributes the clock to local mesh segments. This combines the efficiency of a tree for global distribution with the low-skew property of a mesh for local distribution.

**Advantages:** Balanced power vs. skew trade-off.
**Disadvantages:** More complex to implement and verify.

**Best for:** Large SoCs with aggressive timing targets.

### Spine

A single trunk line (spine) runs across the design with branches (ribs) feeding local clusters. Simple and area-efficient.

**Advantages:** Low buffer count, simple topology.
**Disadvantages:** Higher skew for widely distributed sinks.

**Best for:** Small blocks, low-frequency clocks.

## CTS Implementation Methodology

### Pre-CTS Checklist

1. Placement is complete and timing-clean (WNS > -50 ps pre-CTS).
2. Clock gating cells are placed and connected.
3. Macro clock pins are accessible.
4. Power grid is verified for IR drop and EM.
5. Clock SDC is complete (create_clock, generated clocks, clock groups, uncertainties).

### NDR (Non-Default Rule) for Clock Routing

Clock nets require wider wires and larger spacing to reduce resistance (lower IR drop, lower delay) and improve noise immunity.

```tcl
# Define NDR: double width, double spacing on metal layers
create_routing_rule cts_ndr \
    -widths {M3 0.10 M4 0.10 M5 0.10} \
    -spacings {M3 0.10 M4 0.10 M5 0.10}

# Apply to clock trunk and leaf nets
set_clock_routing_rules -net_type trunk -rule cts_ndr \
    -min_routing_layer M3 -max_routing_layer M5
set_clock_routing_rules -net_type leaf \
    -min_routing_layer M3 -max_routing_layer M4
```

### Shield Routing for Sensitive Clocks

For high-speed designs, shielding clock wires with VDD/VSS reduces crosstalk-induced jitter.

```tcl
# Add shielding to clock nets
create_routing_rule cts_shielded \
    -widths {M4 0.10 M5 0.10} \
    -spacings {M4 0.10 M5 0.10} \
    -shield_widths {M4 0.10 M5 0.10} \
    -shield_spacings {M4 0.05 M5 0.05}
```

### CTS Cell Selection

Use only dedicated clock buffer/inverter cells:

```tcl
# Specify allowed CTS cells
set_lib_cell_purpose -include cts [get_lib_cells "*/CK*"]
set_lib_cell_purpose -exclude cts [get_lib_cells "*/BUF*"]

# Or in Innovus
set_ccopt_property buffer_cells {CKBUFX4 CKBUFX8 CKBUFX12 CKBUFX16 CKBUFX20}
set_ccopt_property inverter_cells {CKINVX4 CKINVX8 CKINVX12 CKINVX16}
```

### Running CTS

**In Fusion Compiler:**
```tcl
clock_opt
```

**In Innovus:**
```tcl
create_ccopt_clock_tree_spec
ccopt_design
```

## Useful Skew and CCD

### Concept

Traditional CTS aims for zero skew — all flip-flops see the clock edge at the same time. However, intentionally introducing skew (useful skew) can help close timing on critical paths.

If a setup-critical path from FF_A to FF_B has negative slack, delaying the clock to FF_B (the capture flip-flop) effectively gives the data more time to arrive. This is "borrowing" time from an adjacent pipeline stage that has positive slack.

### Concurrent Clock and Data (CCD) Optimization

CCD simultaneously optimizes clock tree insertion delays and data path timing, enabled in modern tools:

```tcl
# FC
set_app_options -name clock_opt.flow.enable_ccd -value true
clock_opt

# Innovus
set_ccopt_property enable_useful_skew true
ccopt_design
```

**Constraints on useful skew:**

- Cannot borrow more slack than is available in the donor path.
- Hold time requirements limit how much skew can be applied (increasing useful skew tightens hold).
- Tool must simultaneously satisfy setup and hold across all corners.

## Post-CTS Timing Analysis

After CTS, real clock latencies replace the ideal clock model used pre-CTS. This changes the timing picture significantly:

- Setup slack may improve or degrade depending on clock skew distribution.
- Hold analysis becomes meaningful for the first time — hold was previously masked by ideal clocks.
- Inter-clock-domain paths need careful review with real clock latencies.

### Key Reports

```tcl
# Setup timing post-CTS
report_timing -max_paths 50

# Hold timing post-CTS
report_timing -max_paths 50 -delay_type min

# Clock tree summary
report_clock_timing -type summary

# Skew report
report_clock_timing -type skew

# Clock tree power
report_power -clock_network
```

## Common Issues and Fixes

**Issue: Excessive clock skew (> target)**
- Verify CTS cell list includes sufficient drive strengths.
- Check for macros blocking clock routing paths.
- Ensure NDR rules are not preventing access to certain routing layers.
- Increase CTS layer range to allow routing on higher (faster) metals.

**Issue: High clock tree power**
- Reduce unnecessary buffer stages — check if target transition is too aggressive.
- Use clock gating to shut off clock to idle blocks.
- Consider reducing NDR requirements (single-width for leaf nets).
- Use inverter pairs instead of buffers to reduce cell count.

**Issue: Clock-to-data hold violations after CTS**
- This is expected — hold violations are masked pre-CTS by ideal clocks.
- Fix with post-CTS hold optimization: insert delay cells on short data paths.
- Set hold margin: 20-30 ps to account for OCV and extraction uncertainty.

**Issue: Transition violations on clock pins**
- Upsize clock buffers at violation points.
- Add buffer stages to break long wire segments.
- Ensure leaf-level buffers have adequate drive for the local fanout.

**Issue: Duty cycle distortion**
- Use inverter pairs (two inverters in series) instead of buffers for better duty cycle.
- Check for asymmetric loading on clock branches.
- Verify library characterization includes accurate rise/fall transition modeling.

## Best Practices

1. **Use dedicated CK cells** — never use regular data buffers for clock trees. CK cells have balanced rise/fall delays.
2. **Apply NDR on trunk nets** — double-width, double-spacing reduces RC delay and crosstalk.
3. **Limit CTS to 3-5 metal layers** — use mid-to-upper layers (M3-M5 or M4-M6) for clock routing.
4. **Enable useful skew/CCD** for timing-critical designs — it can recover 20-50 ps of WNS at no area cost.
5. **Review skew group definitions** — incorrect skew groups cause the tool to balance unrelated flip-flops.
6. **Budget for hold fixing** — CTS creates real skew that exposes hold violations. Reserve 5-10% area for hold buffers.
7. **Verify clock gating** — ensure all ICG cells are correctly placed and the enable timing is clean.
8. **Run OCV-aware CTS** — use POCV/AOCV derates during CTS to avoid post-signoff surprises.
9. **Minimize clock reconvergence** — reconvergent clock paths create additional skew uncertainty. Avoid unnecessary clock mux structures.
10. **Power-aware CTS** — clock power is 30-50% of dynamic power. Every optimization decision should weigh power against skew.
