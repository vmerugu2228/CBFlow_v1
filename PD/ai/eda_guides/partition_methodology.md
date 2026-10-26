# Partitioning Methodology: Strategies, Sizing, and Reintegration

## Overview

Partitioning is the process of dividing a large SoC design into smaller blocks (partitions) for hierarchical implementation. The quality of partitioning decisions has a cascading impact on the entire design process -- it determines block sizes, interface complexity, timing budgetability, team assignments, and ultimately the schedule and quality of the final chip.

Good partitioning creates blocks that are independently closable, have clean interfaces, and minimize inter-block dependencies. Poor partitioning creates blocks with excessive inter-block communication, timing-critical cross-boundary paths, and integration nightmares.

## Partitioning Approaches

### Floorplan-Driven Partitioning

In floorplan-driven partitioning, the physical layout guides the partition boundaries:

1. Start with a preliminary floorplan showing major functional blocks and their physical locations
2. Draw partition boundaries based on physical proximity and routing channel availability
3. Assign logic to partitions based on which physical region it falls into
4. Iterate boundaries to minimize cross-boundary connections

**Advantages:**
- Natural alignment with physical implementation
- Partitions are physically contiguous (no scattered logic)
- Channels between partitions provide routing resources for inter-block connections
- Power grid and clock tree follow partition boundaries naturally

**Disadvantages:**
- May split logically coherent units across partitions
- Requires preliminary floorplan before partitioning decisions
- Physical constraints may force sub-optimal logical groupings

### Netlist-Driven Partitioning

In netlist-driven partitioning, the logical structure guides the partition boundaries:

1. Analyze the RTL/netlist hierarchy and identify natural block boundaries
2. Use the existing RTL module hierarchy as partition candidates
3. Apply graph partitioning algorithms to minimize the number of cross-boundary nets (min-cut partitioning)
4. Adjust boundaries to achieve target partition sizes

**Advantages:**
- Preserves logical hierarchy and design intent
- Minimizes inter-block communication (min-cut)
- Easier to verify (partitions align with RTL verification units)
- Natural for IP reuse (each IP is its own partition)

**Disadvantages:**
- May create physically awkward shapes
- Logical proximity does not always correlate with physical proximity
- May not account for routing resource availability

### Hybrid Approach (Recommended)

The most effective approach combines both:

1. Start with the RTL hierarchy to identify candidate partitions
2. Evaluate each candidate against physical criteria (size, aspect ratio, interface count)
3. Use floorplan analysis to validate physical feasibility
4. Adjust boundaries to balance logical cleanliness with physical implementability
5. Iterate until a stable partition plan emerges

## Partition Sizing

### Target Block Size

Partition size affects tool runtime, engineer productivity, and design quality:

| Block Size (Instances) | Tool Runtime | Engineer Effort | Optimization Quality |
|---|---|---|---|
| < 100K | Minutes | Low | Excellent (over-partitioned) |
| 100K-500K | 1-4 hours | Moderate | Very good |
| 500K-2M | 4-12 hours | Substantial | Good |
| 2M-5M | 12-48 hours | High | Acceptable |
| 5M-10M | 2-5 days | Very high | Challenging |
| > 10M | > 1 week | Extreme | Flat may not be feasible |

**Recommended target: 500K-3M instances per partition** for most designs. This balances tool runtime (overnight runs possible) with partition count (manageable number of interfaces).

### Sizing Constraints

- **Minimum size**: Below 100K instances, the overhead of hierarchical methodology (interface models, budgets, assembly) exceeds the benefit. Keep small blocks flat at the top level
- **Maximum size**: Above 5M instances, tool runtime becomes prohibitive for iterative optimization. Split further
- **Uniformity**: Roughly equal-sized partitions enable balanced workload across engineers. Avoid having one 5M-instance block and five 200K-instance blocks
- **Critical blocks**: Performance-critical blocks (CPU, DSP) may need to be smaller for faster iteration even if the design can handle larger blocks

### Area Estimation for Sizing

To estimate partition size before implementation:
```
Block instances ~= (RTL module cell count from synthesis) x 1.1  (10% overhead for CTS, hold buffers)
Block area ~= block_instances x avg_cell_area / target_utilization
```

## Minimizing Inter-Block Communication

### Why It Matters

Every signal crossing a partition boundary:
- Must be budgeted for timing (top-level routing delay)
- Adds a pin to the block interface (pin access challenge)
- Creates a potential timing convergence issue between block and top level
- Increases top-level routing demand

### Strategies for Minimizing Cross-Boundary Signals

1. **Follow the hierarchy**: RTL module boundaries usually correspond to well-defined interfaces with limited signal count
2. **Pipeline registers at boundaries**: If possible, place pipeline stages at partition boundaries. This creates clean register-to-register timing across the boundary
3. **Avoid splitting tightly-coupled logic**: Datapaths, state machines, and control logic with many internal signals should stay in one partition
4. **Move glue logic into partitions**: Small pieces of top-level glue logic should be absorbed into adjacent partitions rather than left at the top level
5. **Bus grouping**: Group related bus signals into the same partition crossing to simplify pin planning

### Cross-Boundary Signal Count Guidelines

| Partition Interface | Typical Signal Count | Assessment |
|---|---|---|
| < 100 signals | Simple, easy to manage | Excellent |
| 100-500 signals | Moderate, manageable | Good |
| 500-2000 signals | Complex, requires careful planning | Acceptable |
| 2000-5000 signals | Very complex, significant routing challenge | Concerning |
| > 5000 signals | Extremely complex, consider re-partitioning | Problematic |

## Inter-Block Timing

### Timing Budget Allocation

The chip-level clock period is divided between source block, top-level routing, and destination block for each inter-block path:

```
T_clock = T_source + T_top_routing + T_dest + T_margin

Where:
  T_source = Clock-to-Q of source register + combinational delay to output pin
  T_top_routing = Wire delay from source block pin to destination block pin
  T_dest = Combinational delay from input pin to destination register + setup time
  T_margin = Guardband for uncertainty
```

### Budget Methods

**Percentage-based:**
- Source block: 35-40% of clock period
- Top routing: 15-20%
- Destination block: 35-40%
- Margin: 5-10%

**Path-based:**
- Analyze specific inter-block paths using a preliminary top-level timing model
- Allocate budgets based on actual path structure and routing distance
- More accurate but requires more upfront analysis

**Symmetric vs. Asymmetric:**
- Symmetric: Source and destination get equal budget. Simple but may be sub-optimal
- Asymmetric: Budget varies per path based on source/destination complexity. More optimal but harder to manage

### Clock Budgeting

Each block receives a clock budget that includes:
- Expected clock insertion delay at the block boundary
- Clock uncertainty (jitter + skew + OCV)
- These constraints determine the effective timing available for data paths

### Timing Budget Iteration

Initial budgets are estimates. They are refined through iterations:

1. Set initial budgets (percentage-based)
2. Implement blocks against budgets
3. Assemble at top level with ILM/ETM models
4. Identify paths that violate timing
5. Re-allocate budgets: give more time to struggling blocks, take from blocks with margin
6. Re-implement affected blocks with updated budgets
7. Repeat until convergence (typically 2-3 iterations)

## Budgeting Methodology

### Conservative vs. Aggressive Budgets

**Conservative budgets:**
- Give blocks less time (tighter constraints)
- Leaves more margin at the top level
- Reduces risk of inter-block timing failure
- May over-constrain blocks, wasting area and power

**Aggressive budgets:**
- Give blocks more time (relaxed constraints)
- Leaves less margin at the top level
- Maximizes block-level QoR
- Higher risk of inter-block timing failure at assembly

**Recommended approach:** Start conservative (allocate 10-15% margin at top level), then relax as blocks demonstrate ability to meet tighter budgets.

### Budget Management

- Track budget vs. actual for every block at every milestone
- Flag blocks that are using more than 90% of their budget -- they may slip
- Maintain a "budget reserve" at the top level (5-10%) for unexpected issues
- Document all budget assumptions and changes

## Reintegration

### Block-to-Top Integration

After all blocks are implemented, they are integrated at the top level:

1. **Database assembly**: Import all block LEF abstracts and ILM/ETM models
2. **Top-level placement**: Place blocks per the floorplan. Place top-level glue logic
3. **Power grid connection**: Connect block power pins to the top-level power grid
4. **Clock tree completion**: Build top-level clock tree connecting to block clock pins
5. **Inter-block routing**: Route all connections between blocks
6. **Top-level optimization**: Optimize inter-block paths for timing
7. **Verification**: DRC, LVS, STA at the full-chip level

### Common Reintegration Issues

**Timing gaps:**
- Inter-block paths that were not adequately budgeted show timing violations
- Fix: Re-budget and re-implement affected blocks, or add top-level optimization (buffers, resizing)

**Pin congestion:**
- Too many signals crossing one block boundary create routing congestion at the interface
- Fix: Spread pins across multiple block edges, add routing resources, or re-partition

**Power grid mismatch:**
- Block power pins do not align with top-level power stripes
- Fix: Adjust top-level power grid or modify block pin placement

**Clock skew at boundaries:**
- Different clock tree implementations in adjacent blocks create skew at the boundary
- Fix: Use ILM-based CTS at the top level to balance inter-block skew

**DRC at boundaries:**
- Metal shapes from adjacent blocks violate spacing rules at the boundary
- Fix: Add guard bands at block edges, enforce minimum boundary spacing rules

### Full-Chip Assembly Verification

After integration, run full-chip verification:
- Merge all block GDS for full-chip DRC
- Merge all block netlists for full-chip LVS
- Run full-chip STA with propagated clocks
- Run full-chip IR drop and EM analysis
- Verify all power domain crossings (isolation, level shifting)

## Practical Guidance

1. **Partition early, adjust later**: Make initial partitioning decisions during architecture, refine during implementation. Changing partitions mid-flow is expensive
2. **Pipeline at boundaries**: The single most effective technique for clean inter-block timing is pipeline registers at partition boundaries
3. **Limit partition count**: Each additional partition adds management overhead. Target 4-12 partitions for most SoCs
4. **Assign owners**: Each partition should have a clear owner responsible for implementation, timing, and QoR
5. **Interface spec document**: Create a formal interface specification for each partition boundary defining signals, timing budgets, pin placement, and power requirements
6. **Regular integration builds**: Run weekly or bi-weekly integration builds even with preliminary blocks. Early integration finds problems early
7. **Avoid top-level logic**: Minimize logic at the top level. Move glue logic into partitions to reduce top-level complexity and timing challenges
8. **Clock domain boundaries**: Where possible, align partition boundaries with clock domain boundaries. Partitions spanning multiple clock domains add constraint complexity
9. **Power domain alignment**: Align power domain boundaries with partition boundaries. A partition that straddles two power domains requires complex internal UPF
10. **Reuse documentation**: If partitions will be reused, document all interface assumptions, clock requirements, and power requirements explicitly
