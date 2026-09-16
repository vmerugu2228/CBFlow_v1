# Ethernet Interface: MAC, PHY, SerDes, TSN, and PTP

## Overview

Ethernet is the dominant networking technology for LAN, data center, automotive, and industrial applications. Designing Ethernet into an SoC involves integrating a MAC (Media Access Controller), PHY (Physical Layer), and SerDes, along with protocol-specific features like Time-Sensitive Networking (TSN) and Precision Time Protocol (PTP). Ethernet speeds range from 10 Mbps to 800 Gbps, with each speed class having distinct PHY requirements and interface standards.

## Ethernet Speed Classes

| Speed | Standard | Medium | Interface to MAC |
|---|---|---|---|
| 10/100 Mbps | 802.3, 802.3u | Copper Cat5 | MII/RMII |
| 1 Gbps | 802.3ab | Copper Cat5e/6 | GMII/RGMII/SGMII |
| 2.5/5 Gbps | 802.3bz | Copper Cat5e/6 | USXGMII/XFI |
| 10 Gbps | 802.3ae, 802.3an | Fiber/Copper Cat6a | XGMII/XFI/SFI |
| 25 Gbps | 802.3by | Fiber/Copper | 25GAUI |
| 100 Gbps | 802.3ba, 802.3bs | Fiber/Copper/DAC | CAUI-4, 100GAUI-2 |
| 400 Gbps | 802.3bs, 802.3ck | Fiber/DAC | 400GAUI-8 |

## MAC Architecture

### Transmit Path

1. **Frame assembly**: construct Ethernet frame with destination MAC, source MAC, EtherType, payload, FCS
2. **VLAN tagging**: insert 802.1Q VLAN tag if configured
3. **Padding**: pad frames shorter than 64 bytes to minimum size
4. **FCS generation**: compute CRC-32 over the frame and append as Frame Check Sequence
5. **Inter-Packet Gap (IPG)**: enforce minimum 12-byte gap between frames
6. **Flow control**: honor PAUSE frames or Priority Flow Control (PFC) signals

### Receive Path

1. **Preamble/SFD detection**: detect 7-byte preamble and Start Frame Delimiter
2. **Address filtering**: compare destination MAC against unicast, multicast, and broadcast filters
3. **VLAN extraction**: extract and process VLAN tags
4. **FCS check**: verify CRC-32; discard corrupted frames
5. **Statistics**: count frames, bytes, errors, drops for RMON/SNMP MIB compliance
6. **Timestamp**: capture receive timestamp for PTP (see below)

### MAC Features

- **Jumbo frames**: support frames up to 9000+ bytes for reduced per-packet overhead
- **Checksum offload**: compute/verify IP, TCP, UDP checksums in hardware
- **Segmentation offload**: split large TCP segments into MAC-sized frames (TSO/LSO)
- **Receive Side Scaling (RSS)**: hash-based distribution of received frames across multiple queues/CPUs
- **Priority queues**: multiple transmit/receive queues mapped to traffic classes

## MAC-to-PHY Interfaces

### MII Family

- **MII (Media Independent Interface)**: 4-bit data, 25 MHz for 100 Mbps; original standard
- **RMII (Reduced MII)**: 2-bit data, 50 MHz for 100 Mbps; fewer pins
- **GMII (Gigabit MII)**: 8-bit data, 125 MHz for 1 Gbps
- **RGMII (Reduced GMII)**: 4-bit DDR data, 125 MHz for 1 Gbps; widely used in embedded designs
- **SGMII (Serial GMII)**: serial 1.25 Gbps link; single differential pair per direction

### XGMII and Beyond

- **XGMII**: 32-bit data, 156.25 MHz DDR for 10 Gbps; wide parallel bus
- **XAUI**: serialized XGMII over 4 lanes at 3.125 Gbps each
- **XFI/SFI**: single-lane 10.3125 Gbps serial interface
- **USXGMII**: unified serial interface supporting 10M to 10G on single SerDes lane
- **XLAUI/CAUI**: 40G/100G interfaces using multiple 10G/25G lanes

### MDIO Management

The MDIO (Management Data Input/Output) interface provides register-level access to PHY configuration:

- **Clause 22**: 5-bit PHY address, 5-bit register address (32 registers per PHY)
- **Clause 45**: 5-bit port address, 16-bit device/register address (supports extended register sets)
- **Configuration**: speed, duplex, auto-negotiation, loopback, power-down, LED control

## PHY Design

### Copper PHY (BASE-T)

Copper Ethernet PHYs for twisted-pair cable:

- **10/100/1G**: uses multi-level signaling (PAM5 for 1G) on 4 twisted pairs
- **2.5G/5G (NBASE-T)**: extends 1G PHY technology to higher speeds on Cat5e/6 cable
- **10GBASE-T**: DSP-intensive; requires sophisticated echo cancellation, crosstalk cancellation, and equalization

Key analog blocks:
- **ADC/DAC**: multi-bit converters at symbol rate (125 Msym/s for 1G)
- **Echo canceller**: cancels transmitted signal coupling into receive path (full-duplex on shared pairs)
- **NEXT/FEXT cancellers**: cancel crosstalk from adjacent pairs
- **Equalizer**: compensates frequency-dependent cable loss
- **Baseline wander correction**: removes DC component from AC-coupled signal

### Fiber/SerDes PHY

Fiber and direct-attach copper (DAC) PHYs use high-speed SerDes:

- **Transmitter**: CML (Current-Mode Logic) driver with programmable swing and emphasis
- **Receiver**: TIA (transimpedance amplifier for fiber), CTLE, DFE
- **PCS (Physical Coding Sublayer)**: 64b/66b encoding (10G), FEC (25G+)
- **PMA (Physical Medium Attachment)**: SerDes analog front-end
- **Forward Error Correction (FEC)**: RS-FEC (Reed-Solomon) for 25G+; mandatory for 100G+ to achieve target BER

## SerDes Design

### Architecture

Ethernet SerDes follows the multi-lane approach for high aggregate bandwidth:

- **Single-lane**: 1G (1.25 Gbps), 10G (10.3125 Gbps), 25G (25.78125 Gbps)
- **Multi-lane**: 100G = 4x25G (CAUI-4) or 2x50G (100GAUI-2)
- **Per-lane rate**: scaling from 10G to 25G to 50G to 100G per lane with each generation

### SerDes Blocks

- **TX PLL**: generates serial clock from reference; LC-PLL or ring PLL
- **TX driver**: CML driver with 3-tap FIR equalizer (pre, main, post)
- **RX CTLE**: continuous-time linear equalizer with programmable peaking
- **RX DFE**: decision-feedback equalizer, typically 5-12 taps
- **RX CDR**: clock-data recovery using bang-bang or Alexander phase detector
- **Adaptation**: automatic gain/offset/DFE tap adaptation using LMS or sign-sign LMS algorithms

## Time-Sensitive Networking (TSN)

TSN is a set of IEEE 802.1 standards enabling deterministic, low-latency Ethernet:

### Key TSN Standards

- **802.1Qbv (Time-Aware Shaper)**: gate control lists open/close traffic class gates on a time schedule; guarantees bandwidth slots for time-critical traffic
- **802.1Qbu/802.3br (Frame Preemption)**: allows high-priority frames to preempt low-priority frame transmission, reducing worst-case latency
- **802.1CB (Frame Replication and Elimination)**: duplicates frames across redundant paths; eliminates duplicates at receiver for zero-loss failover
- **802.1AS (Generalized PTP)**: time synchronization profile for TSN networks
- **802.1Qci (Per-Stream Filtering and Policing)**: rate policing and filtering per stream for security and resource management
- **802.1Qcc (Stream Reservation Protocol)**: centralized or distributed resource reservation

### TSN Hardware Requirements

- **Per-queue gating**: hardware gate control per traffic class with nanosecond-precision scheduling
- **Preemption support**: MAC must support express and preemptable traffic classes
- **Clock synchronization**: PTP hardware timestamping with sub-microsecond accuracy
- **Guard bands**: configurable guard bands between gate events to prevent partial frame transmission

## Precision Time Protocol (PTP)

### Overview

IEEE 1588 PTP synchronizes clocks across Ethernet networks to sub-microsecond accuracy:

### Hardware Timestamping

Accurate PTP requires hardware timestamps at the PHY or MAC level:

- **Transmit timestamp**: captured when the first bit of the PTP event message crosses the reference plane
- **Receive timestamp**: captured when the first bit arrives at the reference plane
- **Reference plane**: typically the MII interface between MAC and PHY

### PTP Clock Architecture

SoC integration for PTP:

- **Free-running counter**: high-resolution timer (typically 1 ns or sub-nanosecond resolution)
- **Timestamp capture units**: latch counter value on transmit/receive events
- **Clock servo**: firmware adjusts counter rate based on master-slave offset measurements
- **One-step vs. two-step**: one-step inserts timestamp directly into outgoing frame (requires MAC hardware support); two-step sends timestamp in a follow-up message

### PTP Accuracy Factors

- **PHY latency variation**: asymmetric or variable PHY delay degrades accuracy
- **Timestamping point**: closer to the wire (at PHY) is more accurate than at MAC
- **Operating system jitter**: hardware timestamping eliminates OS scheduling jitter
- **Network asymmetry**: different propagation delay in each direction introduces offset error

## Automotive Ethernet

Automotive applications drive unique Ethernet requirements:

- **100BASE-T1 (802.3bw)**: 100 Mbps over single unshielded twisted pair; designed for automotive harness
- **1000BASE-T1 (802.3bp)**: 1 Gbps over single pair; PAM3 encoding
- **10BASE-T1S (802.3cg)**: 10 Mbps multi-drop bus; replaces CAN/LIN for sensor networks
- **TSN**: deterministic latency for ADAS, camera, lidar data fusion
- **Automotive EMC**: stringent electromagnetic compatibility requirements

## SoC Integration Considerations

- **DMA engine**: scatter-gather DMA for zero-copy packet transfer between MAC and system memory
- **Interrupt coalescing**: batch multiple packet completions into single interrupt for CPU efficiency
- **Hardware filtering**: MAC address, VLAN, EtherType filters in hardware to reduce CPU load
- **Energy Efficient Ethernet (EEE)**: 802.3az allows link to enter low-power idle during traffic gaps
- **Multi-port switches**: embedded Ethernet switch IP for automotive/industrial gateway SoCs

Ethernet's evolution from a simple LAN technology to a converged networking, timing, and control plane -- especially with TSN and PTP -- makes it increasingly critical in automotive, industrial, and data center SoC designs.
