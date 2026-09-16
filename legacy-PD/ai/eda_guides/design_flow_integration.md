# Design Flow Integration: End-to-End RTL to GDSII Flow

## Overview

The end-to-end semiconductor design flow takes a design from Register Transfer Level (RTL) description through synthesis, physical implementation, and signoff to produce the GDSII layout data sent to the foundry for manufacturing. Each stage has specific inputs, outputs, quality metrics, and handoff requirements. PD engineers must understand the complete flow to appreciate how upstream decisions impact downstream results and to identify the root cause of issues that manifest at any stage.

## Flow Stages Overview

```
RTL Design
    |
    v
Logic Synthesis
    |
    v
Floorplanning
    |
    v
Placement
    |
    v
Clock Tree Synthesis (CTS)
    |
    v
Routing
    |
    v
Signoff (Timing, Physical, Power)
    |
    v
Tapeout (GDSII to Foundry)
```

## Stage 1: RTL Design

### Description

RTL design is the functional design stage where hardware engineers describe the chip's behavior in Verilog, SystemVerilog, or VHDL. The RTL is the golden functional specification.

### Outputs to Physical Design

- **RTL source files**: Synthesizable Verilog/VHDL.
- **Timing constraints (SDC)**: Clock definitions, I/O timing, false/multicycle paths, design rule constraints.
- **UPF file**: Power intent specification (for multi-voltage designs).
- **DFT requirements**: Scan chain configuration, MBIST strategy, JTAG interface.

### Handoff Considerations

- RTL must be lint-clean and synthesis-ready (no non-synthesizable constructs).
- Constraints must be complete and consistent (no unconstrained paths).
- UPF must match the RTL hierarchy and port names.
- Memory and hard IP macro list must be finalized.

## Stage 2: Logic Synthesis

### Description

Synthesis converts RTL into a gate-level netlist using cells from the standard cell library. The synthesizer optimizes for timing, area, and power.

### Tools

- Synopsys Design Compiler (DC) / Fusion Compiler (FC)
- Cadence Genus

### Key Activities

1. **RTL elaboration**: Parse and elaborate the RTL into a generic Boolean network.
2. **Technology mapping**: Map generic gates to target technology standard cells.
3. **Timing optimization**: Size cells, restructure logic, insert buffers to meet timing.
4. **DFT insertion**: Insert scan chains, test muxes, JTAG logic (if not done separately).
5. **Clock gating insertion**: Insert ICG cells to gate clocks to idle registers.
6. **Multi-Vt optimization**: Assign Vt flavors to minimize leakage while meeting timing.
7. **Power domain handling**: Apply UPF, insert isolation, retention, and level shifter cells.

### Outputs

- **Gate-level netlist** (Verilog): The synthesized netlist with technology-specific cells.
- **SDC constraints**: Updated constraints with generated clocks and tool-derived exceptions.
- **DEF** (optional): Physical-aware synthesis may produce a preliminary placement DEF.
- **Synthesis reports**: Timing (WNS/TNS), area, power, cell count, Vt distribution.

### Handoff Quality Metrics

| Metric | Target |
|---|---|
| Setup WNS | >= -200ps (some slack is expected; P&R will recover) |
| Setup TNS | Manageable for P&R (< 10% of paths negative) |
| Area utilization | Estimated; validate against floorplan budget |
| Clock gating ratio | > 80% of sequential bits gated |

## Stage 3: Floorplanning

### Description

Floorplanning defines the physical structure of the chip: die size, macro placement, power grid, I/O pad placement, and partition boundaries.

### Key Activities

1. **Die size estimation**: Based on synthesis area, macro count, and target utilization (typically 60-75%).
2. **Macro placement**: Position SRAM, ROM, analog IP, PLL, and other hard macros. Macros are placed first because they are rigid.
3. **I/O pad/bump placement**: Define the pad ring (wire-bond) or bump map (flip-chip) based on the package specification.
4. **Power grid design**: Create the VDD/VSS power distribution network (rings, straps, via arrays).
5. **Voltage area definition**: For multi-voltage designs, define the physical regions for each power domain.
6. **Placement blockages**: Define regions where standard cells cannot be placed (under macros, in analog areas, routing channels).
7. **Pin placement**: Assign pin locations for hierarchical blocks.

### Outputs

- **DEF file**: Contains die outline, macro locations, I/O placement, power grid, and blockages.
- **Floorplan reports**: Area utilization, macro-to-macro spacing, power grid analysis.

### Handoff Quality Metrics

| Metric | Target |
|---|---|
| Standard cell utilization | 60-75% (design dependent) |
| Macro-to-macro spacing | Per foundry min + routing margin |
| Power grid IR drop | < 3% VDD (estimated) |
| Routing congestion (estimated) | No hotspots > 90% overflow |

## Stage 4: Placement

### Description

Placement assigns physical (x, y) coordinates to every standard cell in the netlist within the floorplan.

### Key Activities

1. **Global placement**: Coarse placement of all cells, optimizing wirelength and congestion.
2. **Legalization**: Snap cells to legal row positions (aligned to placement grid).
3. **Detailed placement**: Local optimization to improve timing and routability.
4. **Scan chain reordering**: Reorder scan chains to minimize scan routing wirelength.
5. **Timing-driven placement**: Move cells to reduce timing-critical path delays.
6. **Congestion-driven placement**: Spread cells in congested regions.
7. **Power optimization**: Swap cells to lower-leakage Vt variants on non-critical paths.

### Outputs

- **Placed DEF**: Updated DEF with cell locations.
- **Placement reports**: Timing (WNS/TNS), congestion maps, utilization, cell density.

### Handoff Quality Metrics

| Metric | Target |
|---|---|
| Setup WNS | >= -100ps (improving toward zero) |
| Hold WNS | May be negative (fixed during CTS/route) |
| Congestion | No overflow (all routing demands satisfiable) |
| Max cell density (local) | < 85% in any region |

## Stage 5: Clock Tree Synthesis (CTS)

### Description

CTS builds the physical clock distribution network from the clock source (PLL/oscillator) to all sequential elements (flip-flops, latches, memories).

### Key Activities

1. **Clock tree construction**: Insert clock buffers and inverters to distribute the clock with balanced delay (low skew).
2. **Skew balancing**: Equalize clock arrival times at all endpoints within a clock domain.
3. **Useful skew**: Intentionally skew clocks to borrow time from slack-rich paths.
4. **Clock gating**: Optimize clock gate placement and buffering.
5. **Post-CTS optimization**: Re-optimize data paths after clock tree insertion to fix timing degradation.
6. **Hold fixing**: Insert delay buffers on short paths to fix hold violations.

### Outputs

- **CTS DEF**: Updated DEF with clock tree cells and clock routing.
- **CTS reports**: Skew, latency, insertion delay, clock tree depth, clock power.

### Handoff Quality Metrics

| Metric | Target |
|---|---|
| Clock skew | < 50-100ps per domain |
| Setup WNS | >= -50ps (nearly closed) |
| Hold WNS | >= 0ps (or close, with route fixing to follow) |
| Clock tree power | Within clock power budget |

## Stage 6: Routing

### Description

Routing creates the physical metal wire connections for all signal and clock nets.

### Key Activities

1. **Global routing**: Assign routing resources to each net at a coarse level.
2. **Track assignment**: Assign specific metal tracks to each net segment.
3. **Detail routing**: Create exact geometric wire shapes compliant with DRC rules.
4. **Via insertion**: Insert vias at layer transitions; attempt via doubling for reliability.
5. **DRC fixing**: Resolve DRC violations introduced during routing.
6. **Antenna fixing**: Fix antenna violations by layer hopping or diode insertion.
7. **Post-route optimization**: Final timing and DRC optimization after routing.
8. **Metal fill**: Insert dummy metal to meet density requirements.
9. **Filler cell insertion**: Insert decap and filler cells in empty spaces.

### Outputs

- **Routed DEF/GDS**: Complete physical layout with all metal and via connections.
- **Routing reports**: DRC violations, timing (WNS/TNS), congestion, via doubling ratio.
- **SPEF**: Extracted parasitics for signoff timing analysis.
- **Final netlist**: Post-route gate-level Verilog.

## Stage 7: Signoff

### Description

Signoff is the independent verification phase where the design is checked by golden tools to confirm readiness for manufacturing.

### Signoff Checks

| Category | Tool(s) | Check |
|---|---|---|
| Timing | PrimeTime / Tempus | Setup, hold, max transition, max cap (all MMMC corners) |
| Physical | Calibre / ICV / Pegasus | DRC, LVS, ERC, antenna |
| Power | RedHawk / Voltus | Static/dynamic IR drop, EM |
| Formal | Formality / Conformal | Logical equivalence (RTL vs. netlist, pre-route vs. post-route) |
| DFT | Tessent / Modus | Scan coverage, ATPG, MBIST |

### Signoff Iteration

Signoff is iterative. Violations found during signoff are fixed using ECO (Engineering Change Order) operations in the P&R tool, and signoff checks are re-run:

```
Route -> Extract -> STA signoff -> ECO fixes -> Re-route -> Re-extract -> Re-check
                                                    |
                                                    v
                                         DRC/LVS signoff -> Fix -> Re-check
```

## Stage 8: Tapeout

### Description

Tapeout is the final data preparation and delivery to the foundry (see manufacturing_signoff.md for details).

### Key Activities

1. GDS export and merge.
2. Final DRC/LVS/ERC on merged GDS.
3. Density verification.
4. Frame generation.
5. Data packaging per foundry checklist.
6. Data transfer to foundry.

## Data Formats Between Stages

| Handoff Point | Key Formats |
|---|---|
| RTL to Synthesis | Verilog/SV, SDC, UPF, Liberty (.lib), LEF |
| Synthesis to P&R | Verilog netlist, SDC, UPF, DEF (optional), LEF |
| P&R to Signoff STA | Verilog netlist, SPEF, SDC |
| P&R to Physical Verification | GDS/OASIS, Verilog netlist |
| P&R to Power Signoff | DEF, SPEF, VCD/SAIF |
| Final to Foundry | GDS/OASIS, documentation |

## Handoff Quality and Communication

### Between Teams

- **RTL to PD**: Weekly constraint reviews, block area estimates, power budgets. RTL team provides early netlist drops for floorplan exploration.
- **PD to Signoff**: Clear criteria for what constitutes "signoff ready" (e.g., WNS > -10ps, zero DRC, LVS clean).
- **PD to Package**: Bump map, power map, thermal requirements communicated early.
- **PD to DFT**: Scan chain count, compression ratio, MBIST configuration.

### Iteration Loops

No stage is truly one-pass. Common iteration loops include:
- **Synthesis-floorplan iteration**: Synthesis area informs die size; floorplan congestion may require synthesis re-optimization.
- **Placement-CTS iteration**: CTS results may require placement changes for better clock tree balance.
- **Route-signoff iteration**: Signoff violations require ECO fixes in the P&R tool.
- **Cross-stage escalation**: Timing closure failure at route may require synthesis re-optimization or even RTL changes.

## Best Practices

1. Define clear exit criteria for each stage before starting the flow.
2. Track QoR metrics at every stage and compare against targets.
3. Run signoff checks incrementally (not just at the end) to catch issues early.
4. Maintain version control for all design data (netlists, DEFs, constraints).
5. Document every non-default tool setting and customization.
6. Communicate handoff data clearly between teams using standardized checklists.

The end-to-end design flow is a complex, iterative process. PD engineers who understand the complete picture can diagnose issues faster, communicate more effectively across teams, and deliver higher-quality designs.
