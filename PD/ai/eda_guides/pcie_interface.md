# PCIe Interface: Architecture, PHY, LTSSM, and CXL

## Overview

PCI Express (PCIe) is the dominant high-speed serial interconnect for connecting processors to peripherals, accelerators, storage, and networking devices. PCIe has evolved through multiple generations, each doubling bandwidth while maintaining backward compatibility. Understanding PCIe requires knowledge of its layered architecture, physical layer signaling, link training state machine (LTSSM), and emerging extensions like CXL (Compute Express Link).

## PCIe Generations

| Generation | Data Rate (per lane) | Encoding | Bandwidth (x16) |
|---|---|---|---|
| Gen1 | 2.5 GT/s | 8b/10b | 4 GB/s |
| Gen2 | 5.0 GT/s | 8b/10b | 8 GB/s |
| Gen3 | 8.0 GT/s | 128b/130b | 16 GB/s |
| Gen4 | 16.0 GT/s | 128b/130b | 32 GB/s |
| Gen5 | 32.0 GT/s | 128b/130b | 64 GB/s |
| Gen6 | 64.0 GT/s | 1b/1b (PAM4+FEC) | 128 GB/s |

Gen1/Gen2 use 8b/10b encoding (20% overhead). Gen3+ use 128b/130b encoding (~1.5% overhead). Gen6 introduces PAM4 signaling (4-level pulse amplitude modulation) to double the data rate without doubling the Nyquist frequency.

## Layered Architecture

### Physical Layer (PHY)

The PHY handles serialization, encoding, and electrical signaling:

**Analog Front-End (AFE):**
- **Transmitter**: current-mode or voltage-mode driver, programmable de-emphasis/pre-shoot
- **Receiver**: continuous-time linear equalizer (CTLE), decision feedback equalizer (DFE)
- **PLL/CDR**: phase-locked loop for clock generation; clock-data recovery for receiver
- **Impedance**: 50-ohm single-ended, 100-ohm differential

**Digital PHY:**
- **Serializer/Deserializer (SerDes)**: parallel-to-serial and serial-to-parallel conversion
- **Encoding**: 8b/10b (Gen1/2) or 128b/130b scrambled (Gen3+)
- **Elastic buffer**: absorbs frequency differences between local and recovered clocks
- **Lane alignment**: deskew multiple lanes within a link
- **PIPE interface**: standard interface between PHY and controller (MAC)

### Data Link Layer

The data link layer ensures reliable packet delivery:

- **Transaction Layer Packet (TLP) framing**: adds sequence number and LCRC (link CRC) to TLPs
- **ACK/NAK protocol**: receiver acknowledges or negative-acknowledges received TLPs
- **Replay buffer**: transmitter stores sent TLPs; replays on NAK or timeout
- **Flow control**: credit-based flow control prevents receiver buffer overflow
  - Posted (writes): separate credits for headers and data
  - Non-posted (reads, config): separate credits
  - Completion: separate credits
- **Data link layer packets (DLLPs)**: carry ACK/NAK, flow control updates, power management messages

### Transaction Layer

The transaction layer handles high-level request/completion transactions:

**Transaction Types:**
- **Memory Read/Write**: access memory-mapped resources
- **I/O Read/Write**: legacy I/O space access
- **Configuration Read/Write**: access device configuration space (256B legacy, 4KB extended)
- **Message**: interrupts (MSI/MSI-X), power management, error signaling

**TLP Structure:**
- Header: 3 or 4 DW (12 or 16 bytes), contains type, length, requester ID, address, tag
- Data payload: 0-4096 bytes (max payload size negotiated during enumeration)
- ECRC: optional end-to-end CRC

**Ordering Rules:**
- Relaxed ordering: allows reordering for performance
- ID-based ordering: preserves order per requester
- Strong ordering: producer/consumer model with strict ordering guarantees

## Link Training and Status State Machine (LTSSM)

The LTSSM manages link initialization, equalization, and power states:

### Detect State
- Transmitter checks for receiver presence by detecting impedance change
- Determines link width (x1, x2, x4, x8, x16)

### Polling State
- Transmitter sends TS1/TS2 training sequences
- Achieves bit lock (CDR locks to incoming data)
- Achieves symbol lock (aligns to encoding boundaries)
- Negotiates link speed capability

### Configuration State
- Determines final link width
- Performs lane-to-lane deskew
- Assigns lane numbers and link numbers
- Exchanges link and lane numbers via training sequences

### L0 (Active State)
- Normal operation; TLPs and DLLPs flow
- Link operates at negotiated speed and width

### Recovery State
- Re-trains the link to change speed, recover from errors, or exit low-power states
- Speed change: transitions through Recovery to negotiate new data rate
- Equalization (Gen3+): performs multi-phase equalization during recovery

### Equalization (Gen3+)

High-speed links require equalization to compensate for channel loss:

**Phase 0**: Downstream port (root complex) sends initial transmitter presets
**Phase 1**: Upstream port evaluates and requests coefficient adjustments
**Phase 2**: Downstream port evaluates and adjusts its transmitter
**Phase 3**: Upstream port fine-tunes using coefficient step requests

Gen4/5 extend equalization with more coefficients. Gen6 with PAM4 requires even more aggressive equalization.

### Low-Power States

- **L0s**: per-lane low-power; fast entry/exit (< 1 us); saves 50-70% link power
- **L1**: entire link powered down; slower exit (2-10 us); saves 80-90% link power
- **L1.1/L1.2 (ASPM substates)**: deeper sleep with PHY powered down; exit latency 32-64 us
- **L2**: auxiliary power only; used during system sleep
- **L3**: link fully off; requires full re-training

## PCIe Enumeration and Configuration

### Bus Enumeration

1. BIOS/firmware performs depth-first bus scan starting from root complex
2. Each device responds to configuration reads with vendor/device ID
3. Bridges are assigned secondary and subordinate bus numbers
4. BAR (Base Address Register) assignment allocates memory and I/O windows

### Configuration Space

- **Legacy (Type 0)**: 256 bytes, compatible with PCI
- **Extended**: 4 KB, accessed via MMCONFIG (memory-mapped configuration)
- **Capabilities**: linked list of capability structures (power management, MSI, PCIe, AER)

### MSI/MSI-X Interrupts

PCIe replaces legacy pin-based interrupts with message-signaled interrupts:

- **MSI**: writes to a memory address to signal interrupt; up to 32 vectors
- **MSI-X**: table-based; up to 2048 vectors; each vector has independent address/data
- **Advantage**: lower latency, no sharing, better scalability

## Advanced Error Reporting (AER)

PCIe defines a comprehensive error hierarchy:

- **Correctable errors**: receiver errors corrected by replay; no data loss
- **Uncorrectable non-fatal**: transaction-level errors; specific transaction fails but link continues
- **Uncorrectable fatal**: link-level errors; link must be reset

Error reporting uses AER capability structure with error status registers, mask registers, and severity configuration. Root complex receives error messages and generates system interrupts.

## CXL (Compute Express Link)

CXL is built on PCIe physical layer and extends it with three protocols:

### CXL.io
- Standard PCIe protocol for discovery, enumeration, configuration, and I/O
- Compatible with existing PCIe software stack

### CXL.cache
- Allows devices to cache host memory with hardware coherency
- Device issues snoop requests to host; host responds with data and coherency state
- Enables accelerators to access host memory with cache-line granularity and low latency

### CXL.mem
- Allows host to access device-attached memory as part of the system memory map
- Memory can be HDM (Host-managed Device Memory) or shared
- Enables memory expansion, pooling, and disaggregation

### CXL Versions

- **CXL 1.1**: PCIe Gen5, basic cache/mem protocols
- **CXL 2.0**: memory pooling, switching, hot-plug
- **CXL 3.0**: PCIe Gen6, fabric topology, shared memory, enhanced coherency

## PCIe PHY Design Considerations

### Signal Integrity

- **Channel loss budget**: Gen5 requires up to 36 dB channel loss compensation
- **Transmitter equalization**: 3-tap FIR (pre-cursor, main, post-cursor) with Gen3/4; more taps for Gen5/6
- **Receiver equalization**: CTLE + multi-tap DFE; Gen6 adds PAM4-specific equalization
- **Reference clock**: common clock (CC), separate reference clock with no spread (SRNS), or with spread (SRIS)

### Power Consumption

- **PHY power**: 10-20 mW per lane per GT/s (e.g., Gen5 x16 = 5-10W just for PHY)
- **ASPM**: aggressive use of L0s/L1 substates critical for power-constrained designs
- **Partial width**: dynamically reduce link width during low-traffic periods

### Verification

- **Protocol compliance**: PCIe compliance test suite with reference loopback
- **Electrical compliance**: eye mask testing at receiver, jitter measurement
- **Interoperability**: testing with multiple vendor devices
- **LTSSM coverage**: ensure all state transitions are exercised

## Implementation in SoC

### Hard Macro vs. Soft IP

- **Hard macro PHY**: pre-designed and characterized analog/mixed-signal block; guaranteed performance
- **Soft controller**: synthesizable RTL for data link and transaction layers; customizable
- **Typical integration**: hard PHY macro + soft controller + application layer

### PCIe Controller Features

- **Root complex or endpoint**: controller configurable for either role
- **Multi-function**: support multiple functions behind single link
- **SR-IOV**: single-root I/O virtualization for VM pass-through
- **ATS/PRI**: address translation services for IOMMU integration

PCIe remains the backbone of high-performance I/O, and with CXL extending its capabilities into memory and cache coherency domains, its importance continues to grow across computing platforms.
