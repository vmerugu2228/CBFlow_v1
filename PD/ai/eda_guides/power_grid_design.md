# Power Distribution Network (PDN) Design

## Overview

The power distribution network (PDN) delivers supply voltage (VDD) and ground (VSS) from the package bumps or bond pads to every transistor on the die. A well-designed PDN ensures that voltage at every point in the chip remains within the allowable IR drop budget, current density remains below electromigration (EM) limits, and the network does not consume excessive routing resources needed for signals.

PDN design is one of the earliest and most critical tasks in physical implementation. An inadequate power grid causes timing failures (from excessive IR drop), reliability failures (from EM), and can be very expensive to fix late in the design cycle.

## PDN Architecture

A typical power grid has a hierarchical structure:

### Package Level

- Bond wires or flip-chip bumps deliver current from the package to the die
- Flip-chip: C4 or micro-bumps on a regular array. Each bump can carry 50-200 mA
- Wire-bond: Bond wires at die periphery. Limited number and current capacity
- Package-level inductance and resistance are significant at high frequencies

### Top-Level Ring

- A power ring runs around the chip periphery (or around major blocks)
- Connects to package bumps/pads
- Typically on the top 1-2 metal layers
- Ring width is sized for EM safety given total block current

### Power Stripes

- Horizontal and vertical metal stripes distribute power across the die
- Stripes run on upper/intermediate metals (e.g., M8-M9 for top stripes, M6-M7 for intermediate)
- Stripe width and pitch are the primary knobs for controlling IR drop
- Alternating VDD and VSS stripes on each layer

### Follow Pins (Standard Cell Rails)

- M1 power rails inside standard cell rows connect directly to cells
- Follow pins run horizontally along each cell row at VDD and VSS positions
- The standard cell architecture defines rail width and pitch
- Follow pins connect upward to the stripe network through via stacks

### Via Arrays

- Via arrays connect stripes on different layers and connect stripes to follow pins
- Via arrays at stripe intersections should be as large as possible to minimize resistance
- Each via array must meet via spacing and enclosure rules
- Via count directly impacts the resistance from top metal to standard cell rail

## Stripe Design

### Stripe Width Calculation

Stripe width is determined by two constraints -- IR drop budget and EM limit:

**For EM:**
```
Min_width = I_max / (J_max * thickness)
```
Where J_max is the maximum current density (from foundry EM rules, e.g., 1-5 mA/um for DC at 105C) and I_max is the current flowing through that segment.

**For IR drop:**
Target IR drop is typically 3-5% of VDD. For a 0.75V supply, that is 22-37 mV.
```
V_drop = I * R_segment
R_segment = rho * length / (width * thickness)
```

### Stripe Pitch

Stripe pitch determines how far current must travel laterally from the nearest stripe to reach every standard cell:
- Tighter pitch = lower IR drop but more routing resources consumed
- Typical stripe pitch: 20-100 um depending on current density and layer
- Power-hungry blocks (CPUs, DSPs) need tighter pitch
- Low-power blocks (memories in retention) can use wider pitch

### Stripe Offset and Alignment

- Stripes should align with macro power pins for direct connection
- Stagger VDD/VSS stripe positions for uniform distribution
- Avoid stripe-free regions that create IR drop hotspots
- Offset stripes on alternating layers for mesh-like coverage

## Mesh vs. Stripe Topology

### Stripe Topology

- Parallel stripes on each layer, perpendicular stripes on adjacent layers
- Simple to implement and analyze
- Good for regular layouts with uniform current density
- Easier to accommodate macros and blockages

### Mesh Topology

- Cross-hatched grid of VDD and VSS on multiple layers, connected at every intersection
- Lower IR drop for the same metal usage (current can take multiple paths)
- More robust -- damage to one segment does not disconnect large areas
- More complex to design and analyze
- Common in high-performance designs (CPUs, GPUs)

### Hybrid Approach

Most production designs use a hybrid:
- Mesh on upper metals (M8-M10) for global distribution
- Stripes on intermediate metals (M5-M7) for regional distribution
- Follow pins on M1 for standard cell connection
- The mesh provides redundancy; the stripes provide directed current flow

## IR Drop Budgeting

Total IR drop from package to transistor is divided into segments:

| Segment | Typical Budget |
|---|---|
| Package (bump to die pad) | 1-2% of VDD |
| Top metal ring | 0.5% |
| Top-to-intermediate stripes | 1-1.5% |
| Intermediate stripes to follow pins | 1-1.5% |
| Follow pin to cell | 0.5% |
| **Total** | **3-5% of VDD** |

### Static vs. Dynamic IR Drop

- **Static IR drop**: Average DC voltage drop. Proportional to average current and resistance
- **Dynamic IR drop**: Transient voltage drop during switching events. Depends on di/dt, package inductance (Ldi/dt), and local decoupling capacitance
- Dynamic IR drop can be 2-3x worse than static IR drop during peak activity
- Decap cells and on-die bypass capacitance mitigate dynamic IR drop

## EM-Safe Widths

Electromigration (EM) failure occurs when current density exceeds safe limits over the chip's lifetime. EM rules specify maximum DC and AC current density per metal layer:

### Current Density Limits

- Limits depend on metal layer, temperature, and design lifetime (typically 10-15 years)
- DC limit (unidirectional current): 1-5 mA/um at 105C for intermediate metals
- AC/RMS limit (bidirectional switching current): 5-10x the DC limit
- Signal wires rarely violate EM; power wires are the primary concern

### EM Analysis Flow

1. Extract power grid network (R and current sources)
2. Run static EM analysis with average current estimates
3. Identify wires and vias exceeding current density limits
4. Fix by widening wires, adding parallel stripes, or adding via arrays
5. Run dynamic EM analysis with switching activity for signal EM

### EM Fix Strategies

- Widen power stripes in violation areas
- Add additional stripes or supplemental power routes
- Increase via array size at critical junctions
- Reduce local current density by redistributing cell placement
- Add more package bumps/bonds in high-current areas

## Power Domain Considerations

Modern SoCs have multiple power domains with different supply voltages and power states:

- Each domain needs its own VDD grid (VSS is often shared)
- Domain boundaries require power isolation (level shifters, isolation cells)
- Always-on domains need robust power grids that remain energized during sleep modes
- Power switches (header/footer cells) require special grid connections

## Practical Guidelines for PD Engineers

1. **Design power grid before placement**: The power grid structure should be defined during floorplanning, before standard cell placement. Placement must respect grid structure
2. **Budget IR drop per segment**: Allocate IR drop budget to each level of the power hierarchy. Track actual vs. budget throughout implementation
3. **Size for worst-case current**: Use activity-based power estimates for average current. Add guardband (20-30%) for peak activity
4. **Check both static and dynamic IR drop**: Static analysis alone is insufficient. Dynamic analysis with realistic switching patterns catches transient voltage droops
5. **Via arrays matter**: Insufficient via connections between layers can create bottlenecks even if stripe widths are adequate
6. **Iterate with placement**: After placement, re-analyze IR drop. High-activity cells near grid edges may need local power reinforcement
7. **Account for macro blockages**: Macros block power stripes. Plan stripe routing around macros with adequate margin
8. **EM signoff early**: Do not wait until post-route signoff. Run EM analysis after power grid creation and fix violations before proceeding
9. **Decap cell planning**: Place decap cells in available whitespace, especially near high-switching blocks, to mitigate dynamic IR drop
10. **Power grid DRC**: Verify power grid meets all width, spacing, and density rules before proceeding to placement
