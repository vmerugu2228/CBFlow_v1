# CTS Optimization: Clock Tree Synthesis Strategy and Techniques

## Overview

Clock Tree Synthesis (CTS) builds the physical clock distribution network that delivers clock signals from the clock source (PLL output, clock input pad) to every sequential element (flip-flop, latch, memory clock pin). CTS is one of the most critical steps in physical design because clock skew, insertion delay, and clock power directly impact timing closure, performance, and power consumption.

A well-built clock tree achieves low skew, minimal insertion delay, balanced loading, and reasonable power. A poorly built tree creates timing violations that are extremely difficult to fix in later stages.

## CTS Fundamentals

### Clock Tree Structure

A clock tree is a buffer/inverter tree that fans out from a single root (clock source) to many leaves (clock sinks):

- **Root**: The clock source pin (e.g., PLL output)
- **Trunk**: The high-fanout portion near the root, driving major branches
- **Branches**: Intermediate buffering stages
- **Leaves**: The clock pins of flip-flops, latches, and macro clock inputs
- **Sinks**: The actual clock consumers (leaf cells in CTS terminology)

### Key Metrics

- **Insertion delay**: Total delay from clock root to clock sink. Lower is better for performance
- **Skew**: Difference in arrival time between the earliest and latest clock sinks. Lower is better for timing closure
- **Transition time (slew)**: Clock signal edge rate at each sink. Must meet library maximum transition constraints
- **Power**: Clock network typically consumes 30-40% of total dynamic power. Minimizing unnecessary buffering reduces power

## Clock Buffer and Inverter Selection

### Cell Selection Strategy

CTS tools select from a set of allowed clock buffers and inverters:

- **Clock buffers (CKBUF)**: Dedicated clock buffer cells with balanced rise/fall delays and low jitter
- **Clock inverters (CKINV)**: Used in pairs (inverter-inverter = buffer) for better duty cycle preservation
- **Drive strength range**: Provide CTS with a range of drive strengths (e.g., CKBUF_X2, X4, X8, X16)
- **Vt selection**: Use SVT or LVT cells for clock buffers to minimize insertion delay. Avoid HVT for clock buffers

### Why Inverters Over Buffers?

Many CTS engines prefer inverter pairs over buffers because:
- Inverters have one stage of amplification; buffers have two (less delay)
- Inverter pairs can be independently sized for rise/fall balancing
- Inverter-based trees often achieve lower insertion delay
- Duty cycle distortion is better managed with inverter pairs

### Cell Selection Best Practice

```
Specify CTS cells:
- Include 4-6 different drive strengths (e.g., X2, X4, X8, X12, X16)
- Include both buffers and inverters
- Exclude very small cells (X1) that have poor drive and high sensitivity to loading
- Exclude very large cells (X32+) unless needed for trunk driving
- Use the same Vt type for all CTS cells for consistency
```

## Sink Clustering

### What Is Clustering?

The CTS engine groups (clusters) nearby clock sinks so that each cluster is served by a single buffer. The cluster size and shape determine the tree structure:

- **Cluster size**: Number of sinks per cluster (e.g., 10-30 sinks)
- **Cluster radius**: Maximum distance from cluster center to any sink
- **Balanced clustering**: Each cluster should have approximately equal total capacitance for skew balance

### Clustering Strategy

- Small clusters: Better skew control, more buffers, higher power
- Large clusters: Fewer buffers, lower power, worse skew control
- The CTS engine balances these automatically, guided by skew/power constraints
- Manual clustering can be applied for special cases (e.g., grouping sinks that must have near-zero skew)

## Level Balancing

### Concept

The tree should have the same number of buffer stages (levels) from root to every leaf. Unbalanced levels cause systematic skew because different buffer counts means different delay.

### Implementation

- The CTS engine inserts dummy buffers (balance buffers) in short paths to equalize levels
- Level balancing adds some power overhead but is essential for low skew
- At each level, the CTS engine sizes buffers to equalize delay, not just level count

### Useful Skew

Not all sinks need to arrive at the same time. Useful skew intentionally offsets clock arrival at specific sinks to help timing:

- If a path from FF_A to FF_B has negative setup slack, delaying the clock to FF_B (or advancing it to FF_A) provides more data path time
- CTS tools can target non-zero skew for specific sinks based on timing analysis
- Useful skew is powerful but must be carefully managed -- it borrows from hold margin

## Multi-Source CTS

### Single Source vs. Multi-Source

- **Single source**: One PLL drives the entire clock tree. Simple but long insertion delay for large dies
- **Multi-source**: Multiple clock sources (PLLs or clock generators) each drive a portion of the tree. Reduces insertion delay and power

### Multi-Source Implementation

- Divide the clock domain into regions, each served by a local clock source
- Balance the phase/frequency of all sources using a global reference
- The boundary between source regions must be carefully managed to avoid skew discontinuities
- Multi-source CTS is common in large SoCs (>10M gates) and high-frequency designs (>2 GHz)

## Clock Mesh

### Concept

A clock mesh is a grid of metal wires on one or two routing layers that distributes the clock signal across the die. The mesh provides extremely low skew because every point on the mesh is connected through multiple paths:

- Mesh wires are driven by multiple drivers at regular intervals
- Any driver-to-sink path is short (to the nearest mesh wire)
- Mesh redundancy makes skew robust against process variation

### Advantages

- Very low skew (< 5-10 ps for large meshes)
- Robust against local process variation
- Simple structure -- easy to analyze

### Disadvantages

- Very high power consumption (the entire mesh toggles every cycle)
- Consumes routing resources on the mesh layers
- Requires careful design of mesh driver placement and sizing

### When to Use Mesh

- High-performance processors where skew must be minimized
- Large clock domains where tree-based CTS cannot achieve target skew
- Designs where clock jitter tolerance is very tight

## H-Tree

### Concept

An H-tree is a symmetric binary tree structure where the wire lengths at each level are precisely balanced:

- The root splits into two branches (H shape)
- Each branch splits again (nested H shapes)
- Wire lengths at each level are identical by construction
- Provides inherently balanced delay to all sinks

### H-Tree + Mesh Hybrid

A common approach combines an H-tree for the trunk with a mesh at the leaves:
- H-tree distributes the clock from the root to multiple mesh driver points
- Local mesh at each H-tree leaf provides final distribution to sinks
- Combines the efficiency of H-tree with the low skew of mesh

## Clock Gating Integration

### Clock Gating and CTS

Clock gating cells (ICG -- Integrated Clock Gating cells) are part of the clock tree:
- ICGs are placed in the tree between the root and the sinks they gate
- The CTS engine must handle ICGs as intermediate tree nodes, not as leaves
- ICG placement affects tree balance and skew

### CTS Strategy for Clock Gating

- Place ICGs close to their gated sinks to maximize power savings
- Balance the tree through ICGs (ICGs are not transparent for CTS)
- Do not insert CTS buffers between an ICG and its gated sinks (this defeats the gating)
- Enable signal routing to ICGs must meet timing (enable setup/hold relative to clock)

## Post-CTS Optimization

### What Happens After CTS

1. **Post-CTS timing analysis**: Propagated clock timing (real clock delays, not ideal) reveals actual setup and hold violations
2. **Setup optimization**: Cell resizing, Vt swapping, and buffer insertion on data paths
3. **Hold optimization**: Insert hold fix buffers on paths with hold violations (short paths)
4. **Clock tree optimization**: Adjust buffer sizes and positions in the clock tree for better skew/power
5. **Useful skew optimization**: Further adjust clock arrival times to help failing setup paths

### Hold Fixing After CTS

Hold violations are the most common post-CTS issue:
- Short data paths between flip-flops clocked by different tree branches may have hold violations due to skew
- Fix by inserting delay buffers on the data path
- Use minimum-delay buffers (small, HVT cells) for hold fixing
- Hold fixing adds cells and routing, potentially impacting congestion
- Fix hold violations on all active corners (not just one corner)

## Practical Guidance

1. **Define CTS cell list carefully**: Include appropriate drive strengths and Vt flavors. Too few choices limits optimization; too many increases runtime
2. **Set realistic skew targets**: 20-50 ps skew is achievable for most designs. Targeting < 5 ps requires mesh and is expensive in power
3. **Analyze clock tree before routing**: Check insertion delay, skew, buffer count, and clock power after CTS but before routing. Fix issues now, not post-route
4. **Manage clock NDR**: Use NDR (wider wires, double spacing) for clock trunks to reduce RC delay and crosstalk sensitivity
5. **Avoid clock tree through congested regions**: Route clock tree segments on less congested layers or through channels
6. **Multi-corner CTS**: Build the tree at the worst-case corner (typically slow corner for insertion delay) and verify at all corners
7. **Clock power budget**: Set a power budget for the clock network (e.g., 30% of total dynamic power) and track actual vs. budget
8. **Useful skew with caution**: Useful skew helps setup but hurts hold. Always verify hold margin after useful skew optimization
