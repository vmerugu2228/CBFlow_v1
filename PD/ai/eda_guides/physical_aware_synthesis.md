# Physical-Aware Synthesis: Placement-Aware Optimization, Congestion, and Timing Correlation

## Overview

Physical-aware synthesis bridges the gap between logical synthesis and physical design by incorporating physical information (placement, routing, congestion) into the synthesis optimization process. Traditional synthesis operates on a purely logical netlist with wireload models that poorly predict actual wire delays, leading to significant timing and congestion surprises during place-and-route. Physical-aware synthesis uses floorplan data, placement estimates, and congestion maps to produce netlists that correlate much better with final physical implementation results.

## The Correlation Problem

### Why Traditional Synthesis Falls Short

Traditional (non-physical) synthesis estimates wire delays using statistical wireload models:

- **Wireload models**: estimate wire delay based on fanout count; coarse and inaccurate
- **Typical errors**: 30-50% delay mismatch between synthesis and post-route timing
- **Consequences**: paths optimized in synthesis become violations after P&R; paths that appeared clean become critical

This mismatch causes:
- Multiple iterations between synthesis and P&R
- Over-optimization of non-critical paths (wasting area and power)
- Under-optimization of paths that become critical after placement
- Congestion hotspots that synthesis cannot predict

### What Physical-Aware Synthesis Provides

Physical-aware synthesis uses physical design data during optimization:

- **Placement-driven wire delay**: actual net lengths based on cell placement, not statistical models
- **Congestion awareness**: avoid creating dense logic in congested regions
- **Timing correlation**: synthesis timing matches P&R timing within 5-10% instead of 30-50%
- **Reduced iterations**: fewer synthesis-to-P&R loops needed to close timing

## Physical-Aware Synthesis Approaches

### Topographical Synthesis (Synopsys Design Compiler Topographical/NXT)

DC Topographical mode performs a coarse placement during synthesis:

1. **Initial synthesis**: technology mapping and basic optimization
2. **Virtual placement**: tool performs a fast placement of cells using the floorplan and timing constraints
3. **Wire delay estimation**: compute wire delays from virtual placement coordinates
4. **Optimization**: re-optimize with placement-based wire delays
5. **Iterate**: repeat placement and optimization until convergence

**Key inputs:**
- DEF floorplan (block boundaries, pin positions, macro locations)
- Physical libraries (LEF) with cell dimensions
- TLU+ or ITF technology models for RC extraction
- SDC timing constraints

**Benefits:**
- Wire delay accuracy within 10% of post-P&R
- Congestion map available during synthesis
- Buffering decisions account for actual distance between source and sink
- Register placement can be optimized for datapath timing

### Design Compiler NXT (DC NXT)

DC NXT extends topographical synthesis with deeper physical integration:

- **Full placement engine**: uses the ICC2/Fusion Compiler placement algorithm
- **Incremental optimization**: performs global and detailed optimization with physical-aware cost functions
- **Multibit banking**: groups flip-flops into multibit cells based on placement proximity
- **Data path optimization**: physically groups datapath logic for shorter interconnect

### Genus Physical Synthesis (Cadence)

Cadence Genus provides physical-aware synthesis through:

- **GigaPlace**: built-in placement engine runs during synthesis
- **Physical optimization**: gate sizing, buffering, and restructuring with placement-based timing
- **Congestion-driven synthesis**: congestion feedback drives restructuring and cell sizing decisions
- **iSpatial flow**: tight integration with Innovus for synthesis-implementation co-optimization

## Placement-Aware Optimization

### Placement-Based Buffering

Traditional synthesis inserts buffers based on estimated wire delays. Physical-aware synthesis places buffers with knowledge of actual distances:

- **Buffer location**: buffer placed at optimal point along the wire route, not just logically
- **Buffer sizing**: drive strength chosen based on actual wire length and load capacitance
- **Repeater insertion**: long wires (cross-chip) get repeaters at optimal intervals based on physical distance
- **Avoid over-buffering**: non-physical synthesis inserts too many buffers for wires that turn out to be short

### Placement-Based Gate Sizing

Cell drive strength optimization considering physical context:

- **Fan-out of 4 (FO4)**: traditional metric becomes inaccurate for long wires
- **Wire-dominated paths**: increase driver strength beyond what fanout alone suggests
- **Local paths**: reduce driver strength for short, local connections (save area/power)
- **Transition time balancing**: equalize slew rates considering actual wire RC

### Datapath Optimization

Physical-aware tools optimize datapath structures with placement knowledge:

- **Bit-slice alignment**: align corresponding bits of arithmetic units vertically for short, uniform wiring
- **Carry chain routing**: place carry chain cells adjacent for minimal wire delay on the critical carry path
- **Multibit grouping**: group flip-flops serving the same bus into multibit cells when physically proximate
- **Datapath folding**: fold wide datapaths to reduce wire length when layout aspect ratio is constrained

## Congestion-Aware Synthesis

### Understanding Congestion

Routing congestion occurs when more wires need to pass through a region than the available routing tracks can accommodate:

- **Global routing estimation**: during synthesis, the tool estimates routing demand vs. supply per global routing cell
- **Congestion hotspots**: regions where demand exceeds supply; causes detours, timing degradation, DRC violations
- **Congestion sources**: high-fanout nets, dense logic clusters, macro pin congestion, narrow channels

### Congestion Reduction Techniques

**Logic restructuring:**
- Decompose high-fanout nets into hierarchical buffer trees spreading across less congested areas
- Clone logic: duplicate cells to reduce fanout and spread routing demand
- Restructure multiplexers and AND-OR-INVERT structures to reduce wire density

**Cell sizing for congestion:**
- Prefer smaller cells in congested regions (less routing blockage from cell pins)
- Avoid unnecessarily large drivers that consume routing resources for pin access

**Placement spreading:**
- Tool spreads cells in congested regions even if it increases wire length slightly
- Trade-off: slightly longer wires but routable design vs. compact but unroutable

**Net weight adjustment:**
- Apply congestion-aware net weights during optimization
- Reduce optimization effort on non-critical nets that cross congested regions
- Prioritize timing-critical nets for preferred routing resources

### Macro-Aware Synthesis

Macros (SRAMs, IP blocks) create routing obstructions and congestion:

- **Macro halos**: synthesis tool respects macro halos; avoids placing standard cells too close to macro edges
- **Pin accessibility**: optimize logic placement to access macro pins without creating congestion
- **Macro channel sizing**: synthesis can estimate channel width needed and warn of insufficient spacing

## Timing Correlation

### Measuring Correlation

Timing correlation between synthesis and P&R is measured by:

- **Slack correlation**: compare path slack at synthesis vs. post-route; ideal is 1:1
- **Endpoint correlation**: compare WNS (worst negative slack) per endpoint
- **Path ranking correlation**: do the same paths appear critical in both stages?
- **Typical target**: synthesis-to-route correlation within 5-10% for well-configured physical-aware synthesis

### Improving Correlation

**Floorplan accuracy:**
- Provide accurate macro placement and pin positions
- Define realistic block boundaries and shapes
- Include power domain boundaries and voltage areas

**Library and technology files:**
- Use consistent libraries between synthesis and P&R
- Include multi-corner multi-mode (MCMM) scenarios
- Use accurate RC models (TLU+ or nxtgrd)

**Constraint consistency:**
- Same SDC constraints in synthesis and P&R
- Same clock definitions, uncertainty, and margins
- Same multi-cycle path and false path exceptions

**Optimization consistency:**
- Map optimization effort between synthesis and P&R tools
- Use same cell libraries (including dont_use, dont_touch settings)
- Preserve synthesis placement hints during P&R

### Incremental Optimization in P&R

Even with good physical-aware synthesis, P&R tools perform additional optimization:

- **In-place optimization (IPO)**: sizing, buffering, and VT swapping without changing placement
- **Useful skew**: adjust clock tree to borrow time between sequential stages
- **Post-route optimization**: fix timing violations caused by actual routing (detours, crosstalk)

The goal of physical-aware synthesis is to minimize the delta between synthesis and P&R, so P&R optimization is incremental rather than major restructuring.

## Physical-Aware Synthesis Flow

### Recommended Flow

1. **Floorplan preparation**: create DEF with block boundaries, macro placement, pin positions
2. **Constraint preparation**: SDC with accurate clock definitions, I/O delays, and exceptions
3. **Initial compile**: physical-aware synthesis with floorplan
4. **Congestion analysis**: review congestion map; adjust floorplan or synthesis settings if needed
5. **Optimization iteration**: refine synthesis with congestion and timing feedback
6. **Netlist handoff**: write optimized netlist, SDC, and physical placement (DEF) for P&R
7. **P&R**: import synthesis netlist with placement; perform placement refinement and routing
8. **Correlation check**: compare synthesis and post-route timing; iterate if correlation is poor

### Synopsys Fusion Compiler

Fusion Compiler goes beyond physical-aware synthesis to a unified synthesis-implementation tool:

- Single tool performs synthesis, placement, CTS, routing, and optimization
- Eliminates the synthesis-to-P&R handoff gap entirely
- Continuous optimization throughout the flow with full physical context
- Best achievable correlation (synthesis IS implementation)

### Cadence iSpatial Flow

Genus + Innovus iSpatial flow provides tight synthesis-implementation coupling:

- Genus physical synthesis with Innovus placement engine
- Shared data model between synthesis and implementation
- Incremental optimization in Innovus preserving Genus decisions

## Practical Recommendations

- Always use physical-aware synthesis for designs targeting advanced nodes (16nm and below)
- Invest time in accurate floorplan creation; garbage in, garbage out
- Monitor congestion during synthesis; address congestion early rather than after routing failure
- Compare synthesis and post-route timing after each major design change; track correlation trends
- Use the same tool vendor for synthesis and P&R when possible for best correlation
- Preserve physical information across ECO cycles; avoid resynthesizing from scratch

Physical-aware synthesis is no longer optional for complex designs. It is the foundation for predictable design closure, reducing the number of synthesis-P&R iterations from potentially dozens to just a few, saving weeks in the design schedule.
