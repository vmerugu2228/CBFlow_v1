# Test Access Mechanism (TAM) and Hierarchical DFT

## The Test Access Challenge

Modern SoCs integrate dozens to hundreds of IP cores -- processors, DSPs, memories, accelerators, peripherals -- each of which must be tested. The test access mechanism (TAM) is the infrastructure that delivers test stimuli from the chip's test pins to each embedded core and transports test responses back out. Without a well-designed TAM, individual cores may be unreachable for testing, or testing may be serialized to the point where test time becomes unacceptable.

The TAM must solve three fundamental problems: (1) transport -- move test data between chip pins and core test ports, (2) isolation -- prevent interference between cores during testing, and (3) scheduling -- manage concurrent and sequential test of multiple cores within power and pin constraints.

## IEEE 1500 Test Wrapper Standard

IEEE 1500 defines a standard wrapper architecture for embedded cores, providing a consistent interface between the core's internal DFT and the SoC-level TAM.

### Wrapper Architecture

The wrapper surrounds each core with three components:

**Wrapper Boundary Register (WBR)**: A scan chain of wrapper cells placed on all core I/O ports. Each wrapper cell can:
- Pass data transparently (functional mode)
- Capture data from the core's functional output (inward test observation)
- Drive data into the core's functional input (inward test stimulus)
- Capture data from the SOC interconnect (outward test observation)
- Drive data onto the SoC interconnect (outward test stimulus)

**Wrapper Instruction Register (WIR)**: Controls the wrapper mode. Standard instructions include:
- `WS_BYPASS`: Single-bit bypass for minimal TAM overhead
- `WS_EXTEST`: Test interconnect between cores (drive/capture at wrapper boundary)
- `WS_INTEST_SCAN`: Test core internal logic using scan chains through the wrapper
- `WS_SAFE`: Drive safe values on core outputs (prevent bus contention)
- `WS_PRELOAD`: Preload wrapper cells before EXTEST

**Wrapper Bypass Register (WBR_BYPASS)**: Single-bit bypass path for fast TAM traversal when the core is not under test.

### Wrapper Modes

**Normal/Functional Mode**: Wrapper is transparent. Core operates normally within the SoC.

**Intest Mode**: Wrapper isolates the core from the SoC. Internal scan chains and wrapper input cells form a complete test path. TAM delivers patterns to the wrapper, which feeds them to the core's internal scan chains. Core test responses flow back through the wrapper to the TAM.

**Extest Mode**: Wrapper drives values onto SoC interconnect from output wrapper cells and captures values from input wrapper cells. Tests the wiring between this core and adjacent cores.

### Wrapper Cell Types

- **WC_INPUT**: On core input ports. Can capture SoC data or drive test data inward.
- **WC_OUTPUT**: On core output ports. Can capture core output data or drive test data outward.
- **WC_INOUT**: On bidirectional ports. Combines input and output cell functionality.
- **WC_CLOCK**: On clock ports. Must handle clock without disrupting test mode clocking.

## TAM Architectures

### Dedicated TAM Wires

Dedicated wires run from chip test pins to each core wrapper. The TAM width (number of wires) determines test data bandwidth.

**Flat TAM**: All cores connect to the same set of TAM wires. Simple but limits parallelism (only one core can use the TAM at a time).

**Partitioned TAM**: TAM wires are divided into groups (TAM partitions). Different cores connect to different partitions, enabling parallel testing. For example, 64 TAM wires split into 4 partitions of 16 wires each, with 4 cores tested simultaneously.

**Hierarchical TAM**: TAM is organized in levels. A chip-level TAM connects to subsystem-level TAMs, which connect to core wrappers. Enables modular design and reuse.

### Test Bus Architecture

**TestRail**: A serial scan bus where wrapper boundary registers are daisy-chained. Simple but slow -- all data must shift through all wrappers in the chain.

**Multiplexed Bus**: A shared bus with address-based core selection. More complex but enables random access to any core.

### Fork-and-Merge TAM

TAM wires fan out (fork) to multiple cores and merge back. A multiplexer selects which core connects to the TAM at any time. Enables flexible scheduling of core tests.

## Core-Level Test

Core-level test treats each core as a self-contained unit:

### Block-Level ATPG

ATPG is run on each core individually:
- Faster ATPG runtime (smaller problem size)
- Enables parallel development (core DFT developed by IP team)
- Patterns are portable -- same patterns work in any SoC that integrates the core
- Core-level patterns are mapped to chip-level patterns through the TAM/wrapper

### Advantages
- Design reuse: Core test patterns travel with the core IP
- Faster turnaround: Block-level ATPG completes in minutes vs. hours for chip-level
- Better coverage: Focused ATPG on smaller blocks often achieves higher coverage
- Debug isolation: Failures are immediately localized to a specific core

### Challenges
- Interconnect between cores must be tested separately (via EXTEST)
- Some faults at core boundaries may be missed by both core-level and interconnect tests
- TAM overhead (area, routing, pins) can be significant
- Wrapper insertion impacts core timing

## Hierarchical DFT

Hierarchical DFT combines block-level and top-level testing:

### Hierarchical Scan

1. Each core has internal scan chains with local SI/SO ports
2. Wrappers provide access to internal chains via the TAM
3. At the top level, core chains are accessed through the TAM or concatenated into chip-level chains
4. Compression can be applied at core level, top level, or both

### Hierarchical Compression

**Core-level compression**: Each core has its own EDT/DFTMAX codec. Core patterns are compressed independently. TAM carries compressed data.
- Advantage: Core test is self-contained and reusable
- Disadvantage: Each codec adds area overhead; many small codecs are less efficient than one large one

**Top-level compression**: A single chip-level codec serves all cores. Internal scan chains from all cores feed into the top-level compressor.
- Advantage: More efficient compression; single codec
- Disadvantage: No core-level test independence; chip-level ATPG required

**Hybrid compression**: Subsystem-level codecs serve groups of related cores. Balances efficiency and modularity.

## Test Scheduling

With multiple cores sharing TAM resources, a test schedule determines when each core is tested:

### Sequential Scheduling
Cores tested one at a time. Simple but total test time is the sum of all core test times. Unacceptable for large SoCs.

### Concurrent Scheduling
Multiple cores tested simultaneously on different TAM partitions. Total test time is determined by the longest single-core test (assuming sufficient TAM bandwidth).

### Optimal Scheduling
Formulate as an optimization problem:
- Minimize total test time
- Subject to TAM bandwidth constraints (total active TAM width <= available width)
- Subject to power constraints (total active test power <= power budget)
- Subject to pin constraints (total active scan I/O <= available pins)

This is an NP-hard bin-packing variant. Heuristic algorithms (greedy, simulated annealing, ILP relaxation) find near-optimal solutions.

### Power-Constrained Scheduling

Power limits how many cores can be tested simultaneously:
- Estimate power for each core's test (shift power + capture power)
- Schedule cores in groups whose total power stays within budget
- Larger cores with higher power are often tested alone; smaller cores are grouped

## IEEE 1687 (IJTAG) for Flexible Test Access

IJTAG provides a reconfigurable access network for embedded instruments (including DFT controllers):

### Segment Insertion Bit (SIB)

A programmable switch that includes or excludes a network segment:
- SIB=0: Segment bypassed (1-bit pass-through)
- SIB=1: Segment included in scan path (full access to instruments behind SIB)

SIBs can be hierarchically nested, creating a tree-structured access network. Only the instruments currently under test are included in the scan path, minimizing shift overhead.

### Instrument Connectivity Language (ICL)

Describes the IJTAG network topology: which SIBs connect to which instruments, data register widths, and access paths.

### Procedural Description Language (PDL)

Scripts that describe how to access specific instruments: which SIBs to open, what data to shift, and how to interpret responses.

### IJTAG Benefits for DFT
- On-demand access: Only include relevant DFT controllers in the scan path
- Reduced overhead: Bypass unused instruments to minimize shift cycles
- Flexible configuration: Reconfigure the access network for different test phases
- Standardized interface: Vendor-neutral description of test access

## TAM Design Guidelines

1. **Allocate sufficient TAM bandwidth**: Total TAM width should support the desired parallelism. Rule of thumb: TAM width = 2-4x the width needed for the longest-test-time core.
2. **Balance TAM partitions**: Distribute cores across partitions to equalize test time per partition.
3. **Minimize TAM routing**: Physical TAM wires must be routed across the chip. Keep TAM connections short and avoid congestion.
4. **Plan for diagnosis**: TAM must support diagnostic modes with more detailed observation, not just production pass/fail.
5. **Consider power constraints early**: Power-constrained scheduling may require more TAM partitions than bandwidth alone would suggest.
6. **Design for reuse**: Use IEEE 1500 wrappers on all reusable cores. Document wrapper architecture in core delivery.
7. **Integrate with JTAG**: The TAM should be accessible via the JTAG interface for debug and bring-up, not just through dedicated test pins.
