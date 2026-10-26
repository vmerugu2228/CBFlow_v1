# USB Interface: PHY, Protocol, Power Delivery, and Type-C

## Overview

Universal Serial Bus (USB) is the most ubiquitous peripheral interconnect, connecting billions of devices ranging from keyboards to high-speed storage and display adapters. USB has evolved from a simple 12 Mbps serial bus to a sophisticated multi-gigabit protocol with power delivery, alternate modes, and tunneling capabilities. Designing USB into an SoC requires understanding the PHY, protocol layers, enumeration, power delivery, and the Type-C connector ecosystem.

## USB Generations

| Standard | Speed | Encoding | Connector |
|---|---|---|---|
| USB 1.1 | 12 Mbps (Full Speed) | NRZI | Type-A/B |
| USB 2.0 | 480 Mbps (High Speed) | NRZI | Type-A/B/Mini/Micro |
| USB 3.0 (3.2 Gen1) | 5 Gbps (SuperSpeed) | 8b/10b | Type-A/B/Micro-B/C |
| USB 3.1 (3.2 Gen2) | 10 Gbps (SuperSpeed+) | 128b/132b | Type-A/C |
| USB 3.2 Gen2x2 | 20 Gbps | 128b/132b (x2 lanes) | Type-C only |
| USB4 | 20/40/80 Gbps | 128b/132b (tunneled) | Type-C only |

USB4 is based on the Thunderbolt 3 protocol and supports tunneling of USB 3.2, DisplayPort, and PCIe traffic over the Type-C cable.

## PHY Architecture

### USB 2.0 PHY

The USB 2.0 PHY handles Low Speed (1.5 Mbps), Full Speed (12 Mbps), and High Speed (480 Mbps):

**Transmitter:**
- **LS/FS**: differential voltage-mode driver, 3.3V signaling, NRZI encoding with bit-stuffing
- **HS**: current-mode driver, 400 mV differential, 45-ohm source termination
- **Chirp signaling**: used during speed negotiation (device drives single-ended K, host responds with alternating K-J)

**Receiver:**
- **Differential receiver**: squelch detector for HS (detects signal presence above 100 mV threshold)
- **Clock recovery**: PLL-based CDR for HS; bit-stuffing provides sufficient transitions for clock recovery
- **Disconnect detection**: monitor SE0 (single-ended zero) for HS disconnect

**UTMI/ULPI Interface:**
- **UTMI**: 8/16-bit parallel interface between PHY and controller; straightforward but pin-heavy
- **ULPI**: reduced pin-count interface (12 pins vs. 24 for UTMI); uses 60 MHz clock with 8-bit data

### USB 3.x PHY

USB 3.x adds a separate SuperSpeed PHY alongside the USB 2.0 PHY:

**SuperSpeed Transmitter:**
- AC-coupled differential driver with de-emphasis
- 8b/10b encoding (Gen1) or 128b/132b encoding (Gen2)
- Programmable transmitter presets (voltage swing, de-emphasis levels)

**SuperSpeed Receiver:**
- CTLE + DFE equalization
- CDR with spread-spectrum clock tracking (SSC: -2300 to -5350 ppm downspread)
- LFPS (Low-Frequency Periodic Signaling) detector for link state signaling

**PIPE Interface:**
- Standard interface between SuperSpeed PHY and controller
- 8/16/32-bit data path, PIPE4 for Gen1/Gen2, PIPE5 for Gen2x2/USB4

### USB4 PHY

USB4 uses enhanced SuperSpeed signaling over two differential pairs in each direction:

- Gen2x2: two 10 Gbps lanes (20 Gbps aggregate)
- Gen3: two 20 Gbps lanes (40 Gbps aggregate)
- Gen4 (USB4 v2): 80 Gbps with PAM3 signaling on existing lanes
- Retimer support: active retimers for long cable runs

## Protocol Layers

### USB 2.0 Protocol

USB 2.0 uses a polled, host-controlled protocol:

**Token Phase**: host sends token packet (IN/OUT/SETUP) identifying target endpoint
**Data Phase**: data packet transferred (host-to-device for OUT, device-to-host for IN)
**Handshake Phase**: receiver acknowledges (ACK/NAK/STALL)

**Transfer Types:**
- **Control**: bidirectional, guaranteed delivery, used for device configuration
- **Bulk**: large data transfers with error recovery, no bandwidth guarantee (storage, printing)
- **Interrupt**: guaranteed latency, small periodic transfers (HID devices)
- **Isochronous**: guaranteed bandwidth, no error recovery (audio, video)

### USB 3.x Protocol

SuperSpeed uses a packet-based, asynchronous protocol:

- **No polling**: device initiates transfers via ERDY (endpoint ready) notifications
- **Burst transfers**: device specifies burst size; host sends/receives multiple packets per transaction
- **Streams**: multiple independent data streams per endpoint (enables command queuing for storage)
- **Link layer**: LGOOD/LCRD flow control replaces token/handshake model

### USB4 Tunneling

USB4 multiplexes multiple protocols over a single connection:

- **USB 3.2 tunnel**: carries USB 3.2 traffic
- **DisplayPort tunnel**: carries DP Alt Mode video
- **PCIe tunnel**: carries PCIe data for Thunderbolt devices
- **Host-to-host tunnel**: enables networking between two hosts
- **Bandwidth allocation**: dynamic bandwidth distribution among tunnels

## Enumeration and Configuration

### Device Enumeration Sequence

1. **Attachment detection**: hub detects device connection via pull-up resistor change
2. **Reset**: host resets the port (drives SE0 for 10-50 ms)
3. **Speed detection**: chirp protocol determines HS capability; fall back to FS/LS
4. **Address assignment**: host assigns unique address via SET_ADDRESS request
5. **Descriptor reads**: host reads device, configuration, interface, and endpoint descriptors
6. **Driver binding**: OS matches descriptors to appropriate class driver
7. **Configuration**: host selects configuration via SET_CONFIGURATION

### Descriptor Hierarchy

```
Device Descriptor
  +-- Configuration Descriptor
        +-- Interface Descriptor
              +-- Endpoint Descriptor
  +-- String Descriptors
  +-- BOS Descriptor (USB 3.x)
        +-- USB 2.0 Extension
        +-- SuperSpeed Capability
        +-- Container ID
```

### Device Classes

USB defines standard device classes eliminating the need for vendor-specific drivers:

- **HID (Human Interface Device)**: keyboards, mice, game controllers
- **Mass Storage (MSC)**: USB flash drives, hard drives (BOT or UASP protocol)
- **Audio**: speakers, microphones (isochronous transfers)
- **Video (UVC)**: webcams, capture devices
- **CDC (Communications)**: serial adapters, networking
- **Billboard**: Type-C alternate mode advertisement

## USB Power Delivery (PD)

### Overview

USB PD is a protocol negotiated over the CC (Configuration Channel) pin in Type-C connectors:

- **USB 2.0 legacy**: 5V, 500 mA (2.5W)
- **USB 3.x legacy**: 5V, 900 mA (4.5W)
- **USB PD 3.1**: supports multiple voltage/current combinations up to 240W

### PD Power Rules

| PDO Type | Voltage | Max Current | Max Power |
|---|---|---|---|
| Fixed (SPR) | 5V/9V/15V/20V | 5A | 100W |
| Fixed (EPR) | 28V/36V/48V | 5A | 240W |
| PPS (Programmable) | 3.3-21V | 5A | Variable |
| AVS (Adjustable) | 15-48V | 5A | Variable |

### PD Negotiation

1. Source advertises capabilities (Source_Capabilities message) listing supported PDOs
2. Sink selects desired PDO and sends Request message
3. Source evaluates and sends Accept/Reject
4. Source adjusts voltage and sends PS_RDY (power supply ready)
5. Sink begins drawing power at new voltage/current

### PD Controller Integration

- **Standalone TCPC**: Type-C Port Controller manages CC signaling, PD messaging; communicates with SoC via I2C (TCPM interface)
- **Integrated TCPC**: some SoCs integrate the PD controller, reducing BOM cost
- **VBUS control**: external load switch or integrated FET controlled by TCPC

## Type-C Connector

### Physical Design

Type-C is a 24-pin reversible connector supporting:
- **USB 2.0**: D+/D- pair (top and bottom for reversibility)
- **SuperSpeed**: TX1/RX1 and TX2/RX2 differential pairs
- **CC1/CC2**: configuration channel for orientation detection, PD communication
- **SBU1/SBU2**: sideband use (DisplayPort AUX, audio)
- **VBUS**: power delivery (5-48V)
- **GND**: multiple ground pins for power return and signal integrity

### Orientation Detection

The CC pin determines cable orientation:
- Host applies Rp (pull-up) on CC1 and CC2
- Cable connects one CC pin through (the other may be VCONN for active cables)
- Host detects which CC pin sees the pull-down (Rd) to determine orientation
- MUX routes SuperSpeed lanes accordingly

### Alternate Modes

Type-C supports non-USB protocols via alternate modes:
- **DisplayPort Alt Mode**: routes DP lanes over USB SS pins; 1, 2, or 4 DP lanes
- **Thunderbolt Alt Mode**: routes Thunderbolt/USB4 protocol
- **HDMI Alt Mode**: routes HDMI signals
- Negotiated via PD Structured VDMs (Vendor Defined Messages)

## SoC Integration Considerations

### Controller Selection

- **Dual-Role Device (DRD)**: supports both host and device roles; essential for Type-C
- **On-The-Go (OTG)**: USB 2.0 role switching (largely superseded by Type-C DRD)
- **xHCI**: standard host controller interface for USB 3.x; reduces software complexity

### PHY Integration

- **Combo PHY**: single PHY supporting USB 3.x, PCIe, and DisplayPort (common in mobile SoCs)
- **Separate PHYs**: dedicated USB 2.0 PHY + USB 3.x PHY for maximum performance
- **PHY placement**: analog PHY macros placed near package pins; sensitive to noise

### Power Management

- **Selective suspend**: suspend idle devices while others remain active
- **L1 (LPM)**: link power management for USB 2.0 (reduced power, fast resume)
- **U1/U2 states**: SuperSpeed link low-power states (1-10 us exit latency)
- **Function suspend**: USB 3.x allows individual functions to suspend in composite devices

USB continues to evolve as the universal connector, absorbing the roles of display, power, and data connectivity into a single Type-C cable, while USB4 provides the bandwidth to support these combined workloads.
