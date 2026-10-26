# Emulation and FPGA Prototyping

## Overview

As SoC designs grow to billions of transistors, software simulation alone cannot achieve the throughput needed for system-level validation, firmware development, and long-running test scenarios. Hardware emulation and FPGA prototyping bridge this gap by executing the design on specialized hardware at speeds orders of magnitude faster than software simulation. Emulation provides high debug visibility at moderate speed, while FPGA prototyping offers near-real-time performance with reduced debug capability.

## Hardware Emulation

### Emulation Platforms

The three major emulation platforms are:

**Cadence Palladium Z-Series**
- Custom processor-based architecture.
- Capacity: Billions of gates per system.
- Speed: 1-10 MHz effective clock rate for large designs.
- Strengths: Deep debug visibility, transaction-based acceleration, power analysis support.

**Siemens Veloce Strato**
- Custom ASIC-based architecture using proprietary emulation chips.
- Capacity: Multi-billion gate support with modular expansion.
- Speed: Competitive MHz-range performance.
- Strengths: Enterprise-grade reliability, strong mixed-signal support, efficient power modeling.

**Synopsys ZeBu EP1**
- FPGA-based emulation using arrays of Xilinx/AMD FPGAs.
- Capacity: Scalable to multi-billion gates through FPGA cascading.
- Speed: Fastest raw clock rates among emulation platforms (often 5-10 MHz).
- Strengths: Fast compile times (relative to other emulators), high performance, broad protocol VIP support.

### Emulation Use Cases

**Software-Driven Verification**
The primary driver for emulation adoption. Running actual firmware, device drivers, RTOS, and application software on the hardware model validates software-hardware interaction months before silicon is available.

- Boot sequence verification (BIOS, bootloader, OS kernel).
- Device driver validation for all peripherals.
- Interrupt handling and real-time response verification.
- Multi-core software execution and cache coherency testing.

**Long-Running Test Scenarios**
Tests that would take days or weeks in simulation complete in hours on emulation:
- Memory subsystem stress tests.
- Network protocol compliance suites.
- Storage controller endurance tests.
- Full system benchmarks.

**System-Level Validation**
Emulators connect to real-world interfaces through speed adapters (also called speed bridges or rate adapters):
- Ethernet: Connect to real network stacks.
- USB: Connect to real USB devices.
- PCIe: Connect to real PCIe endpoints or root complexes.
- Display: Drive real displays for GPU/display controller validation.

**Power Analysis**
Modern emulators support activity-based power estimation:
- Toggle activity is captured during emulation execution.
- Activity data feeds power analysis tools (Joules, PrimeTime PX).
- Enables power profiling of real software workloads that are infeasible to simulate.

### Emulation Compile Flow

1. **RTL preparation**: Synthesize RTL for the emulation platform. This involves technology mapping to the emulator's internal representation.
2. **Partitioning**: Distribute the design across the emulator's processing elements.
3. **Mapping**: Map design elements to emulator resources (processors, memories, I/O).
4. **Programming**: Load the compiled design onto the emulation hardware.
5. **Verification**: Run basic sanity checks to confirm correct compilation.

Compile times range from hours to days for large SoC designs. Incremental compilation reduces recompile time after small RTL changes.

### Transaction-Based Acceleration (TBA)

TBA replaces pin-level stimulus with transaction-level communication between the testbench and the emulated design:

```
Software testbench (host) <-> Transaction channel <-> DUT (emulator)
```

Instead of driving individual clock edges and signals, the testbench sends high-level transactions (read/write commands, packet descriptors). This dramatically increases effective throughput by eliminating the overhead of pin-level synchronization between host and emulator.

### Debug in Emulation

Emulation debug capabilities include:
- **Waveform capture**: Record signal activity on selected signals for offline analysis. Limited by emulator memory — cannot capture everything.
- **Trigger-based capture**: Start recording when specific conditions are met (signal values, event sequences).
- **Real-time probing**: Observe selected signals during execution without stopping.
- **Software-aware debug**: Correlate hardware activity with software execution (program counter, call stack).

## FPGA Prototyping

### Prototyping Platforms

**Synopsys HAPS (High-performance ASIC Prototyping System)**
- Based on Xilinx/AMD Virtex UltraScale+ FPGAs.
- Modular: Stack multiple FPGA boards for larger designs.
- Integrated debug via Synopsys Identify and Certify tools.

**Cadence Protium**
- FPGA-based prototyping using Xilinx/AMD FPGAs.
- Integrated with Cadence Palladium for hybrid emulation/prototyping.
- Automated partitioning across multiple FPGAs.

**Siemens Veloce proFPGA**
- Multi-FPGA prototyping platform.
- Supports Xilinx/AMD and Intel/Altera FPGAs.
- Modular architecture with high-bandwidth inter-FPGA connections.

### Prototyping Speed

FPGA prototypes run at 10-100 MHz (actual design clock frequency), compared to 1-10 MHz for emulators. This speed advantage makes prototyping essential for:
- Early software development (OS boot, application testing).
- Real-time interface testing (streaming video, real-time audio).
- Performance benchmarking with actual workloads.
- System integration with real peripherals and devices.

### Multi-FPGA Partitioning

Large SoCs exceed single-FPGA capacity and must be partitioned across multiple FPGAs:

- **Automatic partitioning**: Tools analyze the design's connectivity graph and partition for minimal inter-FPGA communication.
- **Manual partitioning**: The engineer specifies partition boundaries (typically at well-defined interfaces like bus boundaries).
- **Time-division multiplexing (TDM)**: Serializes inter-FPGA signals over limited physical pins, trading bandwidth for pin count.

Inter-FPGA communication introduces latency and limits the achievable clock frequency. Careful partitioning at natural interface boundaries minimizes this impact.

### Memory Considerations

- **Block RAM mapping**: On-chip SRAMs map to FPGA block RAMs. Capacity may be insufficient for large memory arrays.
- **External memory**: Large memories (DDR controllers, caches) connect to external DDR modules on the prototyping board.
- **Memory initialization**: Preloading memories (ROM content, firmware images) requires attention to FPGA configuration flow.

### Prototyping Debug

Debug visibility in FPGA prototypes is inherently limited:

- **Embedded logic analyzers**: Xilinx ChipScope/ILA or Intel SignalTap capture selected signals in FPGA block RAM. Triggered capture with limited depth.
- **Trace buffers**: Dedicated trace buffer FPGAs capture wider signal sets.
- **Software-based debug**: JTAG connection to embedded processors for software-level debug.
- **Bring-up challenges**: Initial prototyping bring-up requires systematic debugging of clock generation, reset distribution, and inter-FPGA communication.

## Hybrid Emulation

### Concept

Hybrid emulation combines the debug capability of emulation with the speed of FPGA prototyping:

- The block under test runs on the emulator (with full debug visibility).
- The rest of the SoC runs on FPGA prototype (at high speed).
- A high-bandwidth connection bridges the two platforms.

### Benefits

- Full waveform capture and debug for the DUT.
- Near-prototype speed for the surrounding environment.
- Software runs at realistic speeds while hardware bugs can be debugged with emulator-level visibility.

## Power Emulation

### Activity-Based Power Estimation

Emulators capture switching activity (toggle counts) for every net in the design during execution of realistic workloads. This data feeds power analysis tools:

1. Run target workload on emulator (boot sequence, benchmark, use case).
2. Export activity data (FSDB, SAIF, or VCD format).
3. Import activity into power analysis tool (PrimeTime PX, Voltus).
4. Analyze power: dynamic (switching + internal), leakage, per-domain breakdown.

### Advantages Over Simulation-Based Power

- Orders of magnitude more switching activity data (from longer, more realistic workloads).
- Software-realistic power profiles (actual firmware execution patterns).
- Enables power optimization before silicon is available.

## Selection Criteria

| Criterion | Simulation | Emulation | FPGA Prototype |
|-----------|-----------|-----------|----------------|
| Speed | 1-100 Hz | 1-10 MHz | 10-100 MHz |
| Debug | Full | Good | Limited |
| Cost | Low (software) | High ($M) | Moderate |
| Compile | Minutes | Hours-days | Hours |
| Accuracy | Highest (4-state) | High (2-state) | High (2-state) |
| Best for | Functional debug | SW-HW co-validation | SW development |

## Best Practices

1. **Use emulation for software-hardware co-validation** and system-level test scenarios that exceed simulation capacity.
2. **Deploy FPGA prototypes early** for software team enablement — even partial prototypes accelerate SW development.
3. **Invest in transaction-based acceleration** to maximize emulation throughput.
4. **Plan debug strategy before compile** — knowing which signals to capture avoids costly recompiles.
5. **Automate the emulation compile flow** — regression on emulation requires reliable, repeatable builds.
6. **Leverage hybrid approaches** when both speed and debug visibility are needed simultaneously.

## Summary

Emulation and FPGA prototyping are essential for modern SoC verification, enabling software-driven validation, long-running tests, and system-level integration that software simulation cannot achieve. Emulation provides superior debug at moderate speed; prototyping offers maximum performance with limited debug. Hybrid approaches combine the best of both. Power emulation enables realistic power analysis of actual software workloads. Together with simulation and formal verification, emulation and prototyping form the complete verification toolkit for complex SoC designs.
