# ARM Architecture: Cortex Families, AMBA Bus, GIC, Cache Coherency, and TrustZone

## Overview

ARM (Advanced RISC Machines) architecture dominates the SoC landscape from mobile phones to data center servers. Understanding ARM's processor families, bus protocols, interrupt controllers, cache coherency, and security architecture is essential for any SoC designer. This guide covers the Cortex-M, Cortex-A, and Cortex-R processor families, the AMBA bus protocols (AXI, AHB, APB), the Generic Interrupt Controller (GIC), hardware cache coherency, and the TrustZone security architecture.

## ARM Cortex Processor Families

### Cortex-M (Microcontroller)

Designed for deeply embedded, power-constrained, real-time applications:

- **Architecture**: ARMv6-M (M0/M0+), ARMv7-M (M3/M4/M7), ARMv8-M (M23/M33/M55/M85)
- **Pipeline**: 2-stage (M0) to 6-stage (M7); in-order execution
- **Features**: Thumb/Thumb-2 instruction set (compact 16/32-bit encoding), hardware FPU (M4/M7), DSP extensions (M4/M7), MVE/Helium vector extension (M55/M85)
- **Interrupt**: NVIC (Nested Vectored Interrupt Controller) tightly coupled to core; 12-cycle worst-case interrupt latency
- **Memory**: typically tightly-coupled memory (TCM) or unified SRAM; optional MPU (Memory Protection Unit); no MMU
- **Power**: sub-milliwatt operation possible; sleep modes with state retention
- **Use case**: IoT sensors, motor control, audio processing, wearables, automotive MCU

### Cortex-A (Application)

Designed for high-performance, OS-capable applications:

- **Architecture**: ARMv7-A (A5/A7/A9/A15/A17), ARMv8-A (A35/A53/A55/A57/A72/A73/A75/A76/A77/A78/X1/X2/X3/X4), ARMv9-A (A510/A710/A715/A720/X4)
- **Pipeline**: 8-13+ stage superscalar, out-of-order execution (big cores); 8-stage in-order (LITTLE cores)
- **Features**: full virtual memory (MMU + TLB), L1/L2/L3 cache hierarchy, NEON/SVE/SVE2 SIMD, hardware crypto extensions
- **big.LITTLE**: heterogeneous multi-core with big (high-performance) and LITTLE (high-efficiency) cores; DynamIQ cluster allows mix within a single cluster
- **Use case**: smartphones, tablets, laptops, servers, automotive infotainment

### Cortex-R (Real-Time)

Designed for safety-critical, hard real-time applications:

- **Architecture**: ARMv7-R (R4/R5), ARMv8-R (R52/R52+/R82)
- **Pipeline**: 8-11 stage, dual-issue, in-order
- **Features**: tightly-coupled memory (TCM) with ECC, MPU (no MMU in v7-R; optional MMU in R82), lockstep mode for ASIL-D compliance
- **Lockstep**: two cores execute identical instructions; outputs compared cycle-by-cycle; mismatch triggers error
- **Use case**: automotive powertrain, brake systems, industrial control, storage controllers, baseband processing

## AMBA Bus Protocols

### AXI (Advanced eXtensible Interface)

AXI4 is the high-performance bus protocol for SoC interconnect:

**Channels (5 independent channels):**
- **AW (Write Address)**: master sends write address and control
- **W (Write Data)**: master sends write data with byte strobes
- **B (Write Response)**: slave sends write completion status
- **AR (Read Address)**: master sends read address and control
- **R (Read Data)**: slave returns read data and status

**Key features:**
- **Separate read/write channels**: fully independent; simultaneous read and write
- **Outstanding transactions**: master can issue multiple requests before receiving responses (pipelining)
- **Out-of-order completion**: slave can complete transactions in any order (identified by ARID/AWID)
- **Burst transfers**: INCR (incrementing), WRAP (wrapping for cache lines), FIXED (FIFO access)
- **Data widths**: 32, 64, 128, 256, 512, 1024 bits
- **QoS signals**: ARQOS/AWQOS for priority indication to interconnect

**AXI4-Lite:**
- Simplified version for low-throughput register access
- Single beat only (no bursts), no out-of-order, no QoS
- Use case: APB replacement for simple peripherals

**AXI4-Stream:**
- Point-to-point streaming interface (no address)
- Continuous data flow with TVALID/TREADY handshake
- Use case: video pipelines, network data path, DSP chains

### AHB (Advanced High-performance Bus)

AHB is a medium-performance pipelined bus:

- **Single-channel**: multiplexed address and data (not simultaneous like AXI)
- **Pipelined**: address phase overlaps with data phase of previous transfer
- **Burst support**: incrementing and wrapping bursts (4, 8, 16 beats)
- **Multi-layer**: AHB multi-layer allows multiple masters with arbitration
- **Use case**: peripheral buses, legacy IP connections, DMA bridges

**AHB-Lite:**
- Single-master simplified version; no arbitration needed
- Use case: sub-system internal buses

### APB (Advanced Peripheral Bus)

APB is a simple, low-power bus for slow peripherals:

- **Two-phase protocol**: setup phase (address, write data) + access phase (clock in/out data)
- **No pipelining**: simple protocol, low gate count decoder
- **No burst**: single-word transfers only
- **Bridge**: AHB-to-APB or AXI-to-APB bridge converts from high-performance bus
- **Use case**: UART, SPI, I2C, GPIO, timer, watchdog registers

### ACE (AXI Coherency Extension)

ACE extends AXI4 for hardware cache coherency:

- **Additional channels**: snoop address (AC), snoop response (CR), snoop data (CD)
- **Cache states**: supports MOESI-like coherency protocol
- **Use case**: connecting coherent masters (CPU clusters) to coherent interconnect (CCI, CCN, CMN)

## Generic Interrupt Controller (GIC)

### GIC Versions

**GICv2:**
- Up to 1020 SPIs (Shared Peripheral Interrupts)
- 16 SGIs (Software Generated Interrupts) per CPU
- 16 PPIs (Private Peripheral Interrupts) per CPU
- Memory-mapped CPU interface
- 8 CPU interfaces maximum

**GICv3:**
- Thousands of interrupt IDs (SPI, PPI, SGI, LPI)
- System register access (faster than memory-mapped)
- Affinity-based routing (hierarchical: cluster.core.thread)
- LPI (Locality-specific Peripheral Interrupt) support for MSI
- ITS (Interrupt Translation Service) for PCIe MSI-X translation

**GICv4:**
- Direct injection of virtual interrupts to VMs
- Eliminates hypervisor trap for virtual interrupt delivery
- Critical for server virtualization performance

### GIC Operation

1. Peripheral asserts interrupt (SPI wire or LPI message)
2. Distributor registers pending status and evaluates priority
3. Distributor routes to target CPU (1-of-N, fixed, or affinity-based)
4. CPU interface compares pending priority against running priority and priority mask
5. If pending priority is higher, CPU interface signals IRQ/FIQ to core
6. Core reads IAR (Interrupt Acknowledge Register) to get interrupt ID
7. GIC raises running priority to acknowledged interrupt level
8. ISR executes and clears the interrupt source
9. Software writes EOI (End of Interrupt) register
10. GIC lowers running priority and evaluates next pending interrupt

### Interrupt Security

GIC partitions interrupts into security groups:

- **Group 0**: secure interrupts; delivered as FIQ to secure world
- **Group 1 Secure**: secure interrupts delivered as IRQ to secure world
- **Group 1 Non-Secure**: non-secure interrupts delivered as IRQ to normal world

## Cache Coherency

### The Coherency Problem

In multi-core systems, each core has private L1/L2 caches. Without coherency, one core's cache may hold stale data after another core updates the same address.

### Coherency Protocols

**MOESI states:**
- **Modified (M)**: only copy, dirty (different from memory)
- **Owned (O)**: may be shared, this copy is authoritative (dirty)
- **Exclusive (E)**: only copy, clean (matches memory)
- **Shared (S)**: may be shared, clean
- **Invalid (I)**: not valid

**Snoop-based coherency:**
1. Core A writes to address X (transitions to Modified)
2. Core B reads address X; interconnect snoops Core A
3. Core A responds with data and transitions to Shared (or Owned)
4. Both cores now have valid copies

### ARM Coherent Interconnects

- **CCI (Cache Coherent Interconnect)**: CCI-400/500; connects 2-6 ACE masters; snoop filter
- **CCN (Cache Coherent Network)**: CCN-502/508/512; ring-based; up to 12 clusters + I/O coherent masters
- **CMN (Coherent Mesh Network)**: CMN-600/700; mesh topology; scalable to 256+ cores; directory-based coherency
- **DSU (DynamIQ Shared Unit)**: L3 cache and snoop filter within a DynamIQ cluster

### I/O Coherency

Peripherals (DMA, GPU) can participate in coherency:

- **ACE-Lite**: I/O coherent interface; peripheral issues cacheable transactions; interconnect manages coherency
- **Benefit**: eliminates software cache maintenance (flush/invalidate) before/after DMA
- **CHI (Coherent Hub Interface)**: ARM's newer coherency protocol replacing ACE for high-performance systems

## TrustZone Integration

### Hardware Partitioning

TrustZone creates hardware-enforced separation throughout the SoC:

- **Processor**: NS bit in SCR (Secure Configuration Register) determines current world
- **MMU**: separate page tables for secure and non-secure worlds
- **Cache**: cache lines tagged with NS bit; secure and non-secure data coexist in same cache
- **Interconnect**: propagates NS bit with every transaction
- **Memory controller**: TZASC partitions DRAM into secure/non-secure regions
- **Peripherals**: TZPC assigns peripherals to secure or non-secure world

### World Transitions

- **Normal to Secure**: SMC (Secure Monitor Call) instruction traps to EL3 monitor
- **Secure to Normal**: ERET from EL3 monitor returns to normal world
- **Monitor**: manages world switch; saves/restores banked registers
- **Overhead**: world switch takes ~1 us including cache maintenance (if needed)

### TrustZone for Cortex-M (ARMv8-M)

- **Security Attribution Unit (SAU)**: defines secure/non-secure memory regions
- **Secure Gateway (SG) instruction**: only entry point from non-secure to secure world
- **Banked peripherals**: separate NVIC, SysTick, MPU for each world
- **Fast context switch**: hardware stacking of secure registers on non-secure exception; no monitor needed

## DynamIQ and big.LITTLE

### big.LITTLE

Pairs high-performance (big) cores with energy-efficient (LITTLE) cores:

- **Task migration**: OS scheduler moves threads between big and LITTLE cores based on workload
- **Global Task Scheduling (GTS)**: all cores visible to scheduler; most flexible
- **Power savings**: 50-75% power reduction for light workloads on LITTLE cores

### DynamIQ

Evolved big.LITTLE with more flexibility:

- **Mixed clusters**: big and LITTLE cores in the same cluster sharing L3 cache
- **Asymmetric configurations**: 1 big + 3 LITTLE, 2 big + 6 LITTLE, etc.
- **Per-core DVFS**: independent voltage/frequency per core within a cluster
- **DSU**: DynamIQ Shared Unit provides shared L3 cache, snoop filter, and ACP (Accelerator Coherency Port)

ARM's ecosystem of processors, bus protocols, and system IP provides a comprehensive platform for SoC design, with well-defined interfaces and extensive tool support that accelerates development across markets from IoT to HPC.
