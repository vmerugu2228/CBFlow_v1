# DFT Physical Design: Placement, Routing, and Physical Optimization for Test

## DFT in Physical Design

DFT structures occupy silicon area, require routing resources, and impose physical constraints that interact with the functional design. Physical design for DFT encompasses scan chain routing, DFT-aware placement, test pin allocation, compression I/O planning, and BIST physical integration. Poor physical DFT implementation leads to routing congestion, timing violations in test modes, and increased die area -- while good physical DFT is nearly invisible in its overhead.

## Scan Chain Routing

### The Scan Routing Challenge

A scan chain connects the SO (scan output) of each flip-flop to the SI (scan input) of the next flip-flop in the chain. For a design with 10 million flip-flops in 1,000 chains, there are approximately 10 million scan connections that must be routed in addition to all functional connections. Scan routing can consume 5-15% of total routing resources if not managed carefully.

### Scan Chain Reordering

Scan chain reordering is the most important physical DFT optimization. After initial DFT insertion, scan chains are stitched in an arbitrary order (typically synthesis order based on instance names). This creates chains that zigzag randomly across the die, with long routes between consecutive scan cells.

**Physical-aware reordering** reassigns flip-flops to scan chain positions based on physical proximity:
1. After placement, identify the physical location of every scan flip-flop
2. For each chain, reorder flip-flops so that consecutive cells are physically close
3. The optimal ordering minimizes total scan chain wirelength

Reordering algorithms:
- **Nearest-neighbor**: Start at the scan-in pad, find the nearest unassigned flip-flop, add it to the chain, repeat. Simple and effective.
- **TSP-based**: Treat as a traveling salesman problem and apply heuristic solvers. Better quality but slower.
- **Partition-based**: Divide the die into regions and assign chain segments to regions, then order within regions. Balances global and local optimization.

**Reordering impact**:
- Reduces scan chain wirelength by 50-80% compared to pre-reorder
- Significantly reduces scan routing congestion
- Improves scan shift timing (shorter routes = less delay)
- May require chain re-balancing after reordering

### Scan Chain Reordering in P&R Tools

```tcl
# In Innovus
read_scandef design.scandef        ;# read pre-reorder chain definitions
place_design                        ;# place cells
reorder_scan_chains                 ;# physical-aware reordering
write_scandef reordered.scandef     ;# export reordered chains for ATPG
```

```tcl
# In ICC2 / Fusion Compiler
place_opt                           ;# placement optimization
optimize_dft -scan_reorder          ;# scan chain reordering during optimization
write_scan_def reordered.scandef
```

### Scan Routing Congestion Mitigation

Even after reordering, scan routing can cause congestion in dense designs:

- **Scan route layer assignment**: Assign scan routes to upper metal layers (less congested) while reserving lower layers for functional signals
- **Scan-aware placement**: During placement, slightly adjust flip-flop positions to improve scan chain locality without degrading functional timing
- **Chain count adjustment**: More chains with fewer flip-flops each generally route better than fewer long chains
- **Abutment-based scan**: In extreme cases, restrict scan chains to flip-flops within the same placement row or region

## DFT-Aware Placement

### Compression Logic Placement

Compression codec (decompressor/compressor) logic should be placed near the chip periphery, close to scan I/O pads:

- Decompressor input: connects to scan-in pads
- Compressor output: connects to scan-out pads
- Internal chain connections: fan out from decompressor to chip interior and converge from interior to compressor

**Placement strategy**: Place decompressor near scan-in pad cluster, compressor near scan-out pad cluster. Codec cells form a moderate-sized logic block (a few thousand gates) that benefits from being kept together.

### OCC Placement

OCC controllers should be placed near the clock tree root:
- OCC output feeds the clock tree -- distance from OCC to CTS root adds latency and skew
- OCC is typically a small block (a few hundred gates) that fits near the clock source
- Multiple OCCs (one per clock domain) should each be near their respective clock roots

### BIST Controller Placement

**MBIST controllers**: Place near the memory instances they test. The MBIST-to-memory interface mux is on the critical path for memory timing. Long routes from MBIST controller to memory ports add delay.

**LBIST controllers**: Less placement-critical since LBIST connects to scan chains that are distributed across the design. Place LBIST near the JTAG TAP or test control region.

### Test Point Placement

Test points (control and observation points) are added at specific logic nodes identified during DFT insertion. Their placement follows their functional connectivity -- a control test point is placed near the node it controls, and an observation test point is placed near the node it observes.

Test points can cause local congestion due to added connections. If test point density is high in a region, consider reducing test point count or spreading them more evenly.

## Test Pin Placement

### Scan I/O Pin Planning

Scan input and output pins should be planned during floorplanning:

- **Group scan pins together**: Place all scan-in pins in one pad region and scan-out pins in another. This simplifies scan routing and reduces congestion from long diagonal routes.
- **Separate from functional pin clusters**: Avoid mixing scan pins with high-speed functional pins that have strict signal integrity requirements.
- **Consider ATE probe card layout**: Pin placement should align with the ATE probe card geometry for efficient wafer-level testing.
- **Minimize bond wire length**: For wire-bonded packages, scan pins near the chip edge reduce bond wire length.

### JTAG Pin Placement

TCK, TMS, TDI, TDO, and optional TRST should be placed considering:
- Board-level daisy chain: TDI and TDO must be easily routable to adjacent chips on the PCB
- Signal integrity: TCK drives all JTAG logic and should be near a clean power supply
- ESD protection: JTAG pins are often the first pins probed during silicon bring-up

### Dedicated Test Pins vs. Shared Pins

**Dedicated test pins**: Pins used only for test (scan I/O, test mode control). Provide the simplest implementation but consume pins.

**Shared (multiplexed) pins**: Functional pins reused as scan channels in test mode via a mux. Saves pins but adds mux delay on functional paths. The mux must be handled in timing analysis.

```
Functional I/O --+
                 |-- MUX --> Pad
Scan I/O --------+
                 ^
             test_mode
```

## Scan Compression Physical Considerations

### Decompressor Fanout

The decompressor drives many internal scan chains from few input channels. This creates a high-fanout structure:
- Each input channel feeds an XOR network that distributes to potentially hundreds of chains
- Buffer the decompressor output to manage fanout
- Place decompressor outputs in a star topology radiating toward the chip interior

### Compressor Convergence

The compressor collects many chain outputs into few output channels:
- Each output channel receives XOR-combined inputs from many chains
- The XOR tree must have balanced delay to avoid timing issues
- Chain outputs from across the die converge to the compressor -- this creates a "funnel" routing pattern
- Place the compressor where routing convergence is manageable

### Mask Register Routing

Chain masking logic connects to each internal chain's output. Mask register bits must route to the compressor input muxes:
- One mask bit per chain or per chain group
- Serial mask register loaded via JTAG or scan
- Route mask signals alongside chain outputs

## Physical Verification for DFT

### DFT-Specific DRC

Physical DFT checks verify:
- All scan chain connections are routed (no open scan nets)
- No scan shorts between chains (would corrupt shift data)
- Scan signal integrity (adequate spacing from aggressive switching nets)
- Clock tree integrity in test modes (OCC connections properly routed)

### Timing Analysis Considerations

Physical-aware timing analysis for test modes:
- Use actual extracted parasitics for scan routes
- Include interconnect delay in shift timing analysis
- Verify scan chain balance after physical reordering (physical reordering may change effective chain lengths if clock tree latencies differ)
- Analyze SE signal distribution with actual routing topology

### Power Grid for Test

Test mode power consumption patterns differ from functional:
- During shift, switching activity is distributed uniformly across all scan cells
- Power grid must handle this uniform high-current demand
- IR drop analysis in test mode should use appropriate switching activity profiles
- Decoupling capacitance must be adequate for test-mode power demands

## Hierarchical Physical DFT

For large SoCs with hierarchical physical design:

### Block-Level Physical DFT

1. Scan chain reordering within each block independently
2. Chain SI/SO ports placed at block boundary for top-level chain connection
3. MBIST controllers placed within each block near their memories
4. Compression codecs at block level if hierarchical compression is used

### Top-Level Integration

1. Block chain SI/SO connected through TAM or concatenated into chip-level chains
2. Top-level compression wraps all blocks if top-level compression is used
3. JTAG and test control routed from pads to all blocks
4. Scan I/O pads connected to appropriate compression or chain endpoints

### Physical Interface Requirements

Each block must define its DFT physical interface:
- Scan chain port locations (at block boundary pins)
- Clock domain ports for OCC connection
- BIST control/status port locations
- TAM wire routing channels reserved through the block

## Best Practices for DFT Physical Design

1. Always perform scan chain reordering after initial placement -- this is the single most impactful DFT physical optimization
2. Plan scan pin locations during floorplanning, not as an afterthought
3. Place DFT control logic (compression, OCC, BIST) during early floorplanning with awareness of their connectivity
4. Monitor scan routing congestion during detailed routing and iterate on chain reordering if needed
5. Include test mode timing analysis in the standard timing closure flow from the start
6. Verify scan chain integrity after ECOs -- any cell movement can break or degrade scan routes
7. Reserve routing resources for scan -- do not assume scan will route "for free" in the remaining capacity
8. Use scan chain visualization tools (available in all major P&R tools) to identify and fix routing hotspots
