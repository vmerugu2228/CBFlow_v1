# Placement Optimization: Global Placement, Legalization, and Congestion Control

## Overview

Placement determines the physical location of every standard cell in the design. It is the most influential step in the PnR flow after floorplanning -- placement quality directly determines achievable timing, routability, and power. Modern placers use sophisticated multi-objective optimization to simultaneously minimize wire length, meet timing constraints, control congestion, and respect physical constraints.

Understanding how placers work and how to control them is essential for achieving design closure efficiently.

## Placement Flow

The placement process consists of several sequential phases:

### 1. Global Placement

Global placement determines the approximate location of every cell by minimizing total wire length (half-perimeter wire length, HPWL) subject to density constraints:

- Cells are treated as movable points
- The placement area is divided into bins (grid cells)
- Density constraints prevent bins from exceeding target utilization
- The optimizer iteratively adjusts cell positions to minimize a cost function combining wire length and density penalty
- Modern placers use analytical methods (e.g., ePlace, quadratic placement) followed by force-directed refinement

Global placement is fast but produces an approximate solution with overlapping cells.

### 2. Detailed Placement

Detailed placement refines the global placement result:
- Resolves cell overlaps
- Optimizes local wire length by swapping neighboring cells
- Respects cell orientation rules (flip, mirror)
- Minimizes displacement from global placement positions

### 3. Legalization

Legalization snaps cells to legal positions on the placement grid:
- Cells must align to placement rows (Y-coordinate on row pitch)
- Cells must align to the placement site grid (X-coordinate on site width)
- Multi-height cells must span complete rows
- Cells must not overlap each other or blockage regions
- Legalization minimizes total displacement from the pre-legal positions

After legalization, every cell has a legal, non-overlapping position on the placement grid.

### 4. Post-Placement Optimization

After legal placement, optimization passes improve timing and other metrics:
- Cell resizing (swap to larger/smaller drive strength)
- Vt swapping (swap to HVT/LVT/SVT variants)
- Buffer insertion on long nets
- Logic restructuring (gate cloning, pin swapping)
- Local cell movement for timing improvement

## Timing-Driven Placement

### Concept

Timing-driven placement adds timing awareness to the wire length objective. Cells on critical paths are placed closer together to reduce wire delay:

- Net weights are derived from timing slack -- nets with worse slack get higher weights
- The placer penalizes wire length on critical nets more heavily
- Cells with tight timing relationships are pulled together
- Multiple timing optimization iterations alternate with placement refinement

### Controlling Timing-Driven Placement

Key controls:
- **Timing constraints (SDC)**: Accurate SDC is essential. Incorrect constraints mislead the placer
- **Path groups**: Define path groups for critical interfaces to give them priority
- **Net weight adjustment**: Manually increase weight on known critical nets
- **Effort level**: Higher placement effort = more timing optimization iterations = longer runtime
- **Max displacement**: Limit how far cells can move during timing optimization to preserve congestion quality

### Common Timing-Driven Pitfalls

- Over-constraining: Setting unrealistically tight constraints causes the placer to over-optimize some paths at the expense of others
- Under-constraining: Missing constraints allow the placer to spread cells without concern for timing
- Ignoring hold timing: Placers primarily optimize setup timing during placement. Hold timing is typically fixed later but placement can make hold fixing harder

## Congestion-Driven Placement

### Why Congestion Matters

If placement creates regions with more routing demand than supply, the router will fail to complete or produce excessive detours that ruin timing. Congestion-driven placement distributes cells to avoid routing hotspots.

### How Congestion-Driven Placement Works

1. After initial global placement, a fast global route estimates congestion
2. Congestion maps identify overflow regions (more demand than capacity)
3. The placer reduces cell density in congested regions by:
   - Spreading cells outward from congested areas
   - Creating virtual density caps in hot regions
   - Adding congestion penalty to the objective function
4. This iterate between placement and congestion estimation
5. The process may sacrifice wire length or timing to reduce congestion

### Congestion Metrics

- **Overflow**: Number of routing tracks demanded minus available, per GRC (Global Routing Cell). Overflow > 0 means congestion
- **Hotspot count**: Number of GRCs with significant overflow
- **Peak congestion**: Maximum overflow in any GRC
- **Target**: Zero overflow on all layers after global routing

### Congestion Control Knobs

- **Utilization target**: Lower utilization reduces congestion risk
- **Placement density screen**: Limit maximum cell density per region
- **Congestion effort**: Higher effort = more iterations of spread/route/evaluate
- **Partial placement blockages**: Create soft blockages in known congestion areas to limit cell density
- **Cell padding**: Add extra spacing around cells to reduce effective density

## Scan-Chain Reordering

### Purpose

Scan chains connect sequential elements (flip-flops) for testability. The logical scan chain order is determined by DFT synthesis and may not respect physical proximity. Scan-chain reordering optimizes the physical connection order to minimize scan chain wire length.

### How It Works

1. The placer knows which cells are in each scan chain
2. After global placement, the scan chain is reordered so physically adjacent flip-flops are connected sequentially
3. This dramatically reduces scan chain wire length (often 50-80% reduction)
4. Reduced scan wire length improves routing congestion and scan shift timing

### Constraints

- Scan chain reordering must preserve scan-in-to-scan-out connectivity
- Lock-up latches at clock domain crossings must remain in their correct chain positions
- Ordering must respect partition boundaries in hierarchical designs
- Reordering should not violate maximum scan chain length constraints

### Best Practice

Always enable scan-chain reordering during placement. The benefit is almost always positive, and the runtime cost is minimal.

## Placement Blockages

### Types of Blockages

1. **Hard blockage**: No cells allowed in this region. Used around macros, in reserved routing corridors
2. **Soft blockage**: Cells discouraged but allowed if needed. Used for density control
3. **Partial blockage**: Cell density limited to a percentage (e.g., 50%). Useful for congestion management
4. **Halo blockage**: Automatically generated around macros with configurable width

### Effective Use of Blockages

- Use hard blockages for physical requirements (macro halos, no-place zones)
- Use soft/partial blockages for congestion management -- create them around known congestion hotspots
- Do not over-block: excessive blockages waste placement area and force cells into other regions, potentially creating new congestion hotspots
- Blockages interact with utilization: if blockages reduce available area below what is needed, placement will fail

## Multi-Height Cells

At advanced nodes, libraries may include multi-height cells (2-row or 3-row cells):

- Multi-height cells provide complex functions (wide muxes, multi-bit flip-flops) efficiently
- Placement must align multi-height cells to legal row boundaries
- More multi-height cells = more placement constraints
- The placer handles these automatically but may need guidance on row alignment

## Incremental Placement

After the initial placement, several scenarios require incremental (ECO) placement:

- Post-CTS buffer insertion
- Hold time buffer insertion
- Logic ECOs from functional changes
- Replacing cells after optimization

### Incremental Placement Guidelines

- Minimize displacement: new cells should be placed near their connected logic
- Respect existing placement quality: do not displace optimized cells unnecessarily
- Lock critical cells: prevent movement of cells on timing-critical paths
- Verify legality after incremental placement

## Practical Guidance

1. **Get SDC right first**: Placement quality depends heavily on constraint quality. Validate SDC before investing in placement optimization
2. **Start with congestion**: If congestion is a risk, prioritize congestion-driven placement even at the expense of some timing
3. **Iterative approach**: Run placement with default settings first. Analyze results (timing, congestion, utilization maps), then tune
4. **Utilization uniformity**: Aim for uniform utilization across the die. Hot/cold regions indicate floorplan or constraint issues
5. **Path group priority**: Use path groups to focus timing effort on the most critical interfaces
6. **Enable scan reordering**: Always reorder scan chains during placement
7. **Monitor displacement**: Large cell displacement from global to legal placement indicates density problems
8. **Save placement checkpoints**: Save placement databases at key stages for comparison and rollback
9. **Validate before CTS**: Check timing, congestion, and utilization quality before proceeding to CTS. Fixing placement problems after CTS is expensive
10. **Runtime vs. quality**: Higher effort levels improve quality but increase runtime. Use aggressive effort for final tapeout runs, faster settings for exploration
