# Hierarchical Physical Design: Partitioning, Assembly, and Interface Models

## Overview

Hierarchical physical design is a methodology for implementing large SoCs by dividing them into smaller, more manageable blocks that are implemented independently and then assembled at the top level. This approach is essential for designs that exceed the capacity or runtime limits of flat implementation -- typically designs with more than 5-10 million instances, though the threshold varies by team and tool capability.

Hierarchical design enables parallel development by multiple engineers, reduces individual tool runtimes, and allows block reuse across projects. However, it introduces interface complexity, timing correlation challenges, and assembly integration issues that must be carefully managed.

## When to Use Hierarchical Design

### Indicators for Hierarchical Approach

- Design exceeds 5-10M instances (flat implementation too slow)
- Multiple design teams working in parallel with different schedules
- Block reuse across multiple SoCs (e.g., CPU core, memory subsystem)
- Different blocks have very different implementation requirements (e.g., high-speed digital + analog)
- Memory-limited tool environments

### Indicators for Flat Design

- Design is under 3-5M instances
- Single team with common schedule
- No block reuse requirement
- Uniform implementation requirements across the design

## Top-Down Methodology

### Overview

In top-down design, the top-level floorplan and constraints are defined first, then propagated down to blocks:

1. **Top-level floorplan**: Define die size, block placement, IO ring, power grid
2. **Block budgeting**: Derive block-level timing constraints from chip-level SDC
3. **Block pin placement**: Define pin locations for each block based on top-level routing
4. **Block implementation**: Each block team implements their block against budgeted constraints
5. **Top-level assembly**: Assemble completed blocks and implement top-level logic
6. **Timing closure**: Iterate between block and top-level timing until convergence

### Advantages

- Early validation of chip-level feasibility (die size, power, timing architecture)
- Clear block-level requirements defined upfront
- Parallel block implementation once budgets are established

### Challenges

- Block budgets must be conservative enough to account for uncertainty
- Budget changes late in the design cycle require block re-implementation
- Top-level timing is approximate until blocks are complete

## Bottom-Up Methodology

### Overview

In bottom-up design, blocks are implemented first (often based on preliminary estimates), then assembled at the top level:

1. **Block-level implementation**: Each block is designed and optimized independently
2. **Block characterization**: Generate timing models (ILM/ETM) for each block
3. **Top-level integration**: Place blocks and implement top-level logic
4. **Inter-block timing closure**: Optimize paths between blocks at the top level
5. **Iteration**: If inter-block timing fails, update block constraints and re-implement

### Advantages

- Block teams can start immediately without waiting for top-level budgets
- Existing blocks can be reused with existing implementations
- Natural for IP integration (pre-existing, pre-verified blocks)

### Challenges

- Inter-block timing issues discovered late
- Block interfaces may not match well (pin placement, timing budget)
- May require multiple iterations between block and top levels

## Hybrid Approach (Most Common)

Most real designs use a hybrid of top-down and bottom-up:

1. Initial top-down budgeting to set targets
2. Bottom-up block implementation against those targets
3. Top-level assembly and analysis
4. Iterative refinement of budgets and block implementations
5. 2-3 iterations between block and top level to converge

## Interface Logic Models (ILM)

### What is an ILM?

An Interface Logic Model is a reduced representation of a block that contains only the logic near the block boundary (interface logic) while abstracting away the deep interior:

- **Contains**: Flip-flops at the block boundary, combinational logic between boundary and first register stage, clock tree driving boundary registers
- **Removes**: All internal logic beyond the first register stage
- **Preserves**: Accurate timing at all block pins

### ILM Generation

```
Typical ILM extraction (Innovus):
  write_ilm -output block_ilm -model_type timing
```

The tool automatically identifies interface logic and extracts it.

### ILM Usage

- Used at the top level for timing analysis of inter-block paths
- Provides setup/hold timing at block pins with real (not estimated) delay
- Significantly smaller than the full block -- enables fast top-level timing
- Updated when the block timing changes (regenerate after block optimization)

### ILM Accuracy

- ILMs are accurate for paths that start or end within the interface boundary
- Paths that pass through the block interior (feedthroughs) must be modeled separately
- Clock tree within the ILM captures the insertion delay to boundary registers
- ILM timing should correlate within 5-10 ps of the full block timing for interface paths

## Extracted Timing Models (ETM)

### What is an ETM?

An ETM is a Liberty-like timing model extracted from a block's timing analysis. It represents the block as a black box with timing arcs on all pins:

- **Pin-to-pin timing arcs**: Combinational delay, setup/hold constraints, clock-to-output delay
- **No internal logic**: Complete abstraction of block internals
- **Standard Liberty format**: Can be used by any STA tool

### ETM vs. ILM

| Feature | ILM | ETM |
|---|---|---|
| Accuracy | Higher (real logic) | Lower (abstracted) |
| Size | Medium | Small |
| Internal visibility | Boundary logic visible | Black box |
| Optimization | Can optimize interface | Cannot optimize |
| Format | Tool-specific | Standard Liberty |
| Cross-tool compatibility | Limited | Universal |

### When to Use Which

- **ILM**: When using the same PnR tool for block and top level. When top-level optimization needs to modify interface logic
- **ETM**: When blocks are from external IP vendors. When cross-tool compatibility is needed. When block internals must be hidden (IP protection)

## Block-Level Constraints

### Deriving Block Constraints

Block timing constraints must be derived from chip-level requirements:

#### Input Constraints

For each block input pin, define when the signal arrives:
```tcl
set_input_delay -clock CLK -max 2.5 [get_ports block_data_in]
set_input_delay -clock CLK -min 0.3 [get_ports block_data_in]
```

The max value = clock_period - required_setup_margin - estimated_top_routing_delay
The min value = estimated_hold_margin + estimated_top_routing_delay

#### Output Constraints

For each block output pin, define when the signal must be ready:
```tcl
set_output_delay -clock CLK -max 1.5 [get_ports block_data_out]
set_output_delay -clock CLK -min -0.2 [get_ports block_data_out]
```

#### Clock Constraints

Block clock constraints define the expected clock arrival at the block boundary:
```tcl
create_clock -period 2.0 -name CLK [get_ports clk]
set_clock_latency -source -max 0.8 [get_clocks CLK]
set_clock_uncertainty 0.05 [get_clocks CLK]
```

### Budget Methodology

The chip-level timing budget is divided between the source block, top-level routing, and destination block:

```
Clock period = source_block_delay + top_routing_delay + destination_block_delay + margin

Typical budget split:
  Source block:    40% of available time
  Top routing:     15-20% of available time
  Destination block: 40% of available time
  Margin:          5-10% of available time
```

Conservative budgeting (giving blocks less time) is safer but may over-constrain blocks unnecessarily. Aggressive budgeting risks inter-block timing failures at assembly.

## Top-Level Assembly

### Assembly Flow

1. **Place blocks**: Position block abstracts (LEF) on the die according to the floorplan
2. **Place top-level logic**: Place standard cells for glue logic, level shifters, isolation cells
3. **Create power grid**: Build top-level power distribution connecting to block power pins
4. **Route top-level**: Route connections between blocks and to IO
5. **Timing analysis**: Use ILM/ETM models for block timing; analyze inter-block paths
6. **Optimize**: Fix top-level timing violations through cell sizing, buffering, and routing
7. **Verify**: Run DRC, LVS on the assembled design

### Common Assembly Issues

- **Pin mismatch**: Block pin locations do not match the top-level routing. Requires block re-pin or routing detour
- **Power grid connectivity**: Block power pins do not align with top-level stripes. Requires power grid adjustment
- **Timing gaps**: Budget was too optimistic; inter-block paths fail. Requires budget re-allocation
- **Congestion at block boundaries**: Too many signals crossing a narrow channel between blocks

## Physical Verification in Hierarchical Design

### Block-Level Verification

Each block is verified independently:
- Block-level DRC (using block boundary conditions)
- Block-level LVS (using block-level netlist)
- Block-level STA (using block constraints)

### Top-Level Verification

- Top-level DRC includes block-to-block boundary checks
- Top-level LVS uses block CDL netlists
- Top-level STA uses ILM/ETM models for block timing
- Full-chip DRC may require merging block GDS with top-level GDS

### Cross-Boundary Issues

- DRC violations at block-to-block boundaries (spacing, density gradient)
- Antenna violations on nets spanning multiple blocks
- EM violations on inter-block power connections
- These require careful coordination between block and top-level teams

## Practical Guidance

1. **Define interfaces early**: Block boundaries, pin lists, and timing budgets must be stable before block implementation begins
2. **Automate budget generation**: Script the derivation of block constraints from chip-level SDC for consistency and repeatability
3. **Regular integration checks**: Assemble blocks (even with preliminary models) every 1-2 weeks to catch integration issues early
4. **Version control models**: Track ILM/ETM versions and block databases. Out-of-date models cause false timing results
5. **Convergence criterion**: Define measurable convergence criteria (e.g., inter-block WNS within 20 ps, no new DRC) before starting iterations
6. **Communication**: Hierarchical design requires close communication between block teams and the integration team. Establish regular sync meetings
7. **Block reuse planning**: If blocks will be reused, define a clean interface with adequate margin. Hard-code no internal assumptions about the SoC context
8. **Feedthrough planning**: Identify feedthrough signals early and reserve routing resources in affected blocks
9. **Power domain boundaries**: Align block boundaries with power domain boundaries where possible. Crossing both creates double complexity
10. **Sign-off flow**: Define whether signoff is done flat (all blocks merged) or hierarchical (blocks signed off independently). Each has tradeoffs in accuracy vs. runtime
