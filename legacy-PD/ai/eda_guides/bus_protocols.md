# Bus Protocols

## Overview

Bus protocols define the rules for communication between IP blocks in a digital system. A well-chosen bus protocol simplifies integration, enables IP reuse, and provides a standardized framework for arbitration, addressing, and data transfer. The AMBA (Advanced Microcontroller Bus Architecture) family from ARM dominates modern SoC design, with AXI4, AHB, and APB serving different performance tiers. Wishbone is popular in the open-source hardware community. This guide covers the key features, signal sets, and design considerations for each protocol.

## AXI4 (Advanced eXtensible Interface)

AXI4 is the high-performance protocol in the AMBA family, designed for high-bandwidth, low-latency interconnects between processors, DMAs, memories, and peripherals.

### Key Features

- **Five independent channels**: Write Address (AW), Write Data (W), Write Response (B), Read Address (AR), Read Data (R). Each channel has its own valid/ready handshake.
- **Out-of-order completion**: Transactions can complete in a different order than they were issued (using transaction IDs).
- **Burst transfers**: Single address phase can initiate a burst of multiple data beats, amortizing address overhead.
- **Separate read and write paths**: Full duplex operation is possible.
- **Outstanding transactions**: Multiple transactions can be in-flight simultaneously.

### Channel Signals (Simplified)

```
Write Address Channel (AW):
  AWID, AWADDR, AWLEN, AWSIZE, AWBURST, AWVALID, AWREADY

Write Data Channel (W):
  WDATA, WSTRB, WLAST, WVALID, WREADY

Write Response Channel (B):
  BID, BRESP, BVALID, BREADY

Read Address Channel (AR):
  ARID, ARADDR, ARLEN, ARSIZE, ARBURST, ARVALID, ARREADY

Read Data Channel (R):
  RID, RDATA, RRESP, RLAST, RVALID, RREADY
```

### Handshake Rules

Each channel uses a valid/ready handshake:

1. The source asserts VALID when it has information to transfer.
2. The destination asserts READY when it can accept the information.
3. Transfer occurs when both VALID and READY are high on the same clock edge.
4. VALID must not depend on READY (to avoid deadlock).
5. Once VALID is asserted, information must remain stable until the transfer completes.

### Burst Types

- **FIXED** (AWBURST=0): Address remains constant. Used for FIFO-like peripherals.
- **INCR** (AWBURST=1): Address increments by the transfer size each beat. The most common type.
- **WRAP** (AWBURST=2): Address wraps at a boundary. Used for cache-line fills.

### Burst Length

AXI4 supports bursts of 1-256 beats (AWLEN/ARLEN = 0 to 255). AXI4-Lite has no burst support (single-beat only). AXI3 limited bursts to 1-16 beats.

### Transaction Ordering

Transactions with the same ID must complete in order. Transactions with different IDs can complete out of order. This allows the interconnect to route transactions to different slaves and complete them as the slaves respond.

### Write Strobes

WSTRB (write strobe) provides byte-level write granularity. Each bit of WSTRB corresponds to one byte of WDATA. Only bytes with WSTRB=1 are written; others are unchanged. This eliminates read-modify-write for sub-word writes.

### AXI4-Lite

A simplified version of AXI4 for low-throughput control/status register access:

- No burst support (single beat transfers only).
- No transaction IDs.
- Fixed data width (32 or 64 bits).
- No out-of-order completion.

AXI4-Lite is the standard for CSR (Configuration and Status Register) interfaces in most IP blocks.

### AXI4-Stream

A streaming protocol with no address channel, designed for unidirectional data flow (like video, audio, or network packets):

```
TDATA, TSTRB, TKEEP, TLAST, TID, TDEST, TUSER, TVALID, TREADY
```

AXI4-Stream is ideal for data processing pipelines where data flows in one direction without random access.

## AHB (Advanced High-Performance Bus)

AHB is a simpler, lower-performance protocol than AXI. It uses a single shared bus with a central arbiter.

### Key Features

- **Single address and data bus**: Shared among all masters and slaves.
- **Pipelined**: Address phase of the next transfer overlaps with the data phase of the current transfer.
- **No out-of-order**: Transactions complete strictly in order.
- **Split and retry**: Slaves can free the bus for other masters by issuing a split/retry response.

### Signal Set (Simplified)

```
HADDR[31:0]   - Address
HTRANS[1:0]   - Transfer type (IDLE, BUSY, NONSEQ, SEQ)
HWRITE        - Write (1) or read (0)
HSIZE[2:0]    - Transfer size (byte, halfword, word, etc.)
HBURST[2:0]   - Burst type
HWDATA[31:0]  - Write data
HRDATA[31:0]  - Read data
HREADY        - Transfer complete (slave to master)
HRESP         - Transfer response (OKAY, ERROR)
HSEL          - Slave select (from address decoder)
```

### Pipelined Operation

```
Cycle 1: Address A1, Data D0 (from previous transfer)
Cycle 2: Address A2, Data D1 (data for A1)
Cycle 3: Address A3, Data D2 (data for A2)
```

The one-cycle address-data pipeline means HREADY must be checked before advancing to the next transfer. When a slave is not ready, it deasserts HREADY, causing both the address and data phases to stall.

### AHB vs AXI

AHB is simpler to implement but has lower throughput due to its shared bus architecture. Use AHB for moderate-bandwidth peripherals and legacy IP. Use AXI for high-bandwidth paths (memory, DMA, display).

## APB (Advanced Peripheral Bus)

APB is the low-power, low-complexity protocol for slow peripherals (UART, GPIO, timers, etc.).

### Key Features

- **Non-pipelined**: Each transfer takes at least two cycles (setup + access).
- **Single master**: The APB bridge is the only master; peripherals are slaves.
- **No burst**: Every transfer is a single-beat operation.
- **Simple interface**: Minimal signals, minimal logic.

### Signal Set

```
PADDR[31:0]  - Address
PSEL         - Peripheral select
PENABLE      - Access enable (high in access phase)
PWRITE       - Write (1) or read (0)
PWDATA[31:0] - Write data
PRDATA[31:0] - Read data
PREADY       - Slave ready (for wait states)
PSLVERR      - Slave error
```

### Transfer Phases

```
Setup Phase  (PSEL=1, PENABLE=0): Address and control are presented
Access Phase (PSEL=1, PENABLE=1): Data transfer occurs (PREADY checked)
```

If PREADY is low during the access phase, the bridge inserts wait states. Once PREADY goes high, the transfer completes.

### APB Bridge

An AHB-to-APB or AXI-to-APB bridge converts high-performance bus transactions to APB. The bridge handles protocol conversion, clock domain crossing (if needed), and address decoding for multiple APB peripherals.

## Wishbone

Wishbone is an open-source bus protocol commonly used in OpenCores and academic projects.

### Key Features

- **Simple handshake**: CYC (bus cycle), STB (strobe), ACK (acknowledge).
- **Synchronous**: All transfers are clock-synchronous.
- **Flexible**: Supports single, burst, and pipelined transfers.
- **No licensing**: Freely available specification.

### Signal Set (Simplified)

```
ADR_O[31:0]  - Address
DAT_O[31:0]  - Write data
DAT_I[31:0]  - Read data
WE_O         - Write enable
SEL_O[3:0]   - Byte select
STB_O        - Strobe (valid transfer)
CYC_O        - Bus cycle (held for entire burst)
ACK_I        - Acknowledge
```

### Transfer

```
Master asserts CYC and STB with address and data.
Slave responds with ACK when ready.
Transfer completes when both STB and ACK are high.
```

## Interconnect Design

### Crossbar

A crossbar switch provides simultaneous connections between multiple masters and slaves. Each master-slave pair has a dedicated path. Maximum bandwidth but highest area cost.

### Shared Bus

All masters share a single bus through arbitration. Low area but limited bandwidth (only one transfer at a time).

### Network on Chip (NoC)

For large SoCs, a network topology (mesh, ring, tree) routes packets between masters and slaves. Scalable to many endpoints but adds routing latency.

## Design Best Practices

1. Choose the protocol based on bandwidth requirements: AXI for high-bandwidth, AHB for mid-range, APB for slow peripherals.
2. Use AXI4-Lite for all CSR interfaces.
3. Use AXI4-Stream for unidirectional data pipelines.
4. Always implement the full handshake protocol; cutting corners causes deadlocks.
5. Add protocol checkers (assertion monitors) at every bus interface during verification.
6. Size data widths to match the dominant transfer size (avoid 64-bit buses for 8-bit peripherals).
7. Use write strobes instead of read-modify-write.
8. Register all outputs from bridges and interconnects to meet timing.
9. Test with back-to-back transfers, stalls, errors, and interleaved traffic.
10. Document the address map, including alignment requirements and reserved regions.
