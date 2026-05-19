# DFT Insertion Flow: From RTL to Test-Ready Netlist

## DFT Insertion in the Design Flow

DFT insertion transforms a functional design into one that supports structural testing. This process typically occurs during or after logic synthesis, though DFT planning begins much earlier at the architecture phase. The flow involves multiple insertion steps, each adding specific test infrastructure, followed by verification through DFT design rule checks (DRC).

The overall DFT insertion sequence in a typical flow is:

1. RTL analysis and test architecture definition
2. Scan replacement (during synthesis or post-synthesis)
3. Test point insertion
4. On-chip clock controller (OCC) insertion
5. Compression (EDT/DFTMAX) insertion
6. Wrapper insertion (for core-level test in SoCs)
7. BIST insertion (LBIST and MBIST)
8. JTAG/boundary scan insertion
9. DFT DRC verification
10. ATPG pattern generation

## Pre-Synthesis DFT Planning

Before any physical DFT insertion, critical planning decisions must be made:

**Test architecture**: Define the overall test strategy -- which blocks use scan, BIST, or both. Determine hierarchical vs. flat test approach. Plan test access mechanism for multi-core SoCs.

**Pin allocation**: Reserve pins for scan I/O, JTAG (TCK, TMS, TDI, TDO, TRST), BIST control, and any dedicated test pins. Shared/multiplexed pin strategies must be defined early.

**Clock architecture for test**: Identify all clock domains. Plan OCC placement. Determine which clocks need at-speed test capability. Plan PLL bypass for test mode.

**Scan chain planning**: Estimate the number of scan chains based on flip-flop count, compression ratio, and available scan pins. Plan chain partitioning across clock domains.

**Coverage targets**: Define stuck-at, transition, and other coverage goals that will drive DFT decisions throughout the flow.

## Scan Replacement

Scan replacement maps standard flip-flops to their scan equivalents. This can happen:

**During synthesis (preferred)**: The synthesis tool (Design Compiler, Genus, Fusion Compiler) performs scan replacement as part of the mapping step. The scan flip-flops are technology-mapped to library scan cells (SDFF, SDFFRX, etc.).

**Post-synthesis**: A separate DFT tool replaces already-mapped non-scan flip-flops with scan equivalents. Less common in modern flows but sometimes used for IP integration.

Key scan replacement considerations:
- Ensure the library contains scan equivalents for all flip-flop variants used (reset, enable, set, combinations)
- Flip-flops to exclude from scan (dont_scan attribute): clock dividers, JTAG registers, certain async crossing registers
- Lockup latches: Inserted at clock domain boundaries within scan chains to prevent hold violations during shift when adjacent flip-flops are on different clock edges
- Multi-bit flip-flop handling: Some libraries have scan versions of multi-bit cells; otherwise they must be split before scan replacement

## Test Point Insertion

Test points improve fault coverage by adding controllability and observability at nodes that are hard to test.

**Control test points**: A logical AND or OR gate inserted at a hard-to-control node, with one input from a scan flip-flop. During test, the scan flip-flop can force the node to a specific value. In functional mode, the control input is set to the non-controlling value (1 for AND, 0 for OR), making the test point transparent.

**Observation test points**: A dedicated flip-flop that samples a hard-to-observe node and is included in a scan chain. This makes the internal signal directly observable without requiring path sensitization to a primary output.

Test point insertion is guided by testability analysis:
- SCOAP (Sandia Controllability/Observability Analysis Program) computes combinational and sequential controllability/observability at every node
- Nodes with high controllability or observability difficulty are candidates for test points
- Typical insertion: 1-5% of design area allocated to test points
- Diminishing returns: first 500-1000 test points provide the most coverage improvement

## On-Chip Clock Controller (OCC)

The OCC is essential for at-speed transition fault testing. It generates precisely timed clock pulses for the launch-capture sequence while allowing slower shift clock operation.

### OCC Architecture

The OCC typically contains:
- **Clock multiplexer**: Selects between functional PLL clock and external test clock
- **Launch pulse generator**: Creates the at-speed launch and capture pulses
- **Shift clock gate**: Controls clock during shift operations
- **Mode controller**: Configurable via scan or JTAG to select LOS, LOC, or other modes

### OCC Insertion

Each clock domain typically gets its own OCC instance. Insertion involves:
1. Identify all functional clock roots
2. Insert OCC between clock source and clock distribution network
3. Connect OCC control signals to scan chains or JTAG
4. Ensure OCC does not add significant clock skew

Placement of OCC is critical -- it must be physically close to the clock root to minimize skew between the OCC output and the distributed clock.

## Compression Insertion

Compression logic (decompressor and compressor) is inserted around the scan chains:

1. **Define compression architecture**: Specify external channel count, internal chain count, compression ratio
2. **Insert decompressor**: Between scan input pins and internal chain heads
3. **Insert compressor**: Between internal chain tails and scan output pins
4. **Add mask logic**: Chain masking registers for X-handling
5. **Connect control signals**: Compression mode, mask control, via JTAG or dedicated pins

Tool-specific insertion:
- **Synopsys DFT Compiler**: `insert_dft` command with DFTMAX specification
- **Siemens Tessent Shell**: `insert_test_logic` with EDT configuration
- **Cadence Modus**: Compression insertion within the DFT synthesis step

## Wrapper Insertion

For hierarchical SoC testing, IEEE 1500-style test wrappers isolate individual cores, allowing them to be tested independently.

A wrapper consists of:
- **Wrapper cells**: On all core I/O ports (similar to boundary scan cells but for core boundaries)
- **Wrapper instruction register**: Controls wrapper mode (functional, inward-facing test, outward-facing test)
- **Wrapper bypass register**: Single-bit path for fast bypass when core is not under test

Wrapper modes:
- **Normal mode**: Wrapper is transparent; core operates functionally
- **Intest mode**: Wrapper cells drive test values into core inputs and capture core outputs. Tests core internal logic.
- **Extest mode**: Wrapper cells drive values from core outputs and capture at core inputs. Tests interconnect between cores.

## BIST Insertion

### LBIST Insertion
1. Insert PRPG (LFSR + phase shifter) driving scan chain inputs
2. Insert MISR collecting scan chain outputs
3. Insert BIST controller state machine
4. Add test point insertion (driven by BIST coverage analysis)
5. Connect control/status to JTAG

### MBIST Insertion
1. Generate MBIST controllers for each memory group
2. Insert interface mux logic on each memory port
3. Connect MBIST controller outputs to memory inputs
4. Connect memory outputs to MBIST comparator
5. Add repair analysis logic if memories have redundancy
6. Connect MBIST control/status to JTAG/TAM

## JTAG Insertion

Boundary scan insertion adds:
1. Boundary scan cells on all I/O pads
2. TAP controller
3. Instruction register
4. IDCODE register
5. Bypass register
6. Optional IJTAG network for instrument access

JTAG is typically inserted at the top level of the chip, though the TAP controller logic can be synthesized and placed like any other logic.

## DFT DRC Verification

After all DFT insertion steps, DFT design rule checks verify correctness:

### Structural DRC
- All scannable flip-flops are in scan chains
- Scan chains are fully connected (no breaks)
- Chain lengths are balanced
- Lockup latches present at required clock domain boundaries
- No feedback paths in scan chains

### Clock DRC
- All clocks reach their intended flip-flops in both functional and test modes
- Clock gating cells have proper test enable bypass
- OCC is properly connected and functional
- No clock glitches during mode transitions

### Reset DRC
- Asynchronous set/reset signals are properly controlled during scan
- Reset during scan shift is disabled (would corrupt shift data)
- Set/reset signals can be activated during capture if needed for specific faults

### Compression DRC
- Decompressor/compressor connections are correct
- X-sources are identified and masking is adequate
- Channel balance is verified

### BIST DRC
- BIST connections to scan chains/memories are correct
- BIST controller state machine is properly connected
- PRPG/MISR feedback polynomials are valid

## Post-Insertion Optimization

After DFT insertion, the netlist undergoes:

**Incremental synthesis**: Re-optimize timing with DFT structures in place. Test mode timing constraints are added alongside functional constraints.

**Scan chain reordering**: Performed during or after placement to optimize chain routing. Reordering swaps flip-flop positions within chains based on physical proximity.

**Test mode timing closure**: Shift paths must meet timing at shift frequency. OCC paths must meet timing at functional frequency. This often requires dedicated test mode constraints in the SDC.

## Tool Command Examples

**Synopsys DFT Compiler/Fusion Compiler**:
```
set_scan_configuration -chain_count 100
set_dft_signal -view existing_dft -type ScanEnable -port SE
insert_dft
```

**Siemens Tessent Shell**:
```
set_context dft -no_rtl
read_verilog design.v
set_current_design top
add_clocks TCK -period 100
set_scan_configuration -chain_count 100
insert_test_logic
```

**Cadence Modus**:
```
set_db dft_scan_style muxed_scan
set_db dft_prefix DFT_
define_scan_chain -name chain1 -sdi SI1 -sdo SO1
synthesize -to_scan
```

Each tool has its own syntax and conventions, but the fundamental DFT insertion concepts are the same across all commercial tools.
