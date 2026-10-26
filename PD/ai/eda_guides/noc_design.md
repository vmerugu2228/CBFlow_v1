# Network-on-Chip: Topology, Routing, QoS, and Power Management

## Overview

Network-on-Chip (NoC) is a communication architecture that replaces traditional shared-bus and crossbar interconnects with a packet-switched network fabric. As SoC complexity has grown to hundreds of IP blocks, NoC has become the dominant interconnect paradigm for designs requiring scalable bandwidth, deterministic latency, and flexible topology. NoC brings networking concepts -- routing, flow control, quality-of-service, and congestion management -- into the silicon domain.

## NoC Fundamentals

### Architecture Components

A NoC consists of three primary elements:

- **Network Interfaces (NI)**: convert bus transactions (AXI, AHB) into network packets and back. The NI packetizes requests, attaches routing headers, and reassembles responses. It is the bridge between the IP's native protocol and the network.
- **Routers (switches)**: forward packets from input ports to output ports based on routing decisions. Each router has input buffers, a crossbar switch, an arbiter, and routing logic.
- **Links**: physical wires connecting routers. Link width (data bits), pipeline depth, and metal layer assignment determine bandwidth and latency.

### Packet Format

A typical NoC packet contains:

- **Header flit**: destination address, source ID, transaction type, QoS class, packet length
- **Payload flits**: data words (for write transactions) or read data (for responses)
- **Tail flit**: marks packet end, carries error detection (CRC or parity)

Flit (flow control digit) is the smallest unit of flow control. Phit (physical digit) is the smallest unit transmitted per clock cycle on a link.

## Topology Selection

### Mesh Topology

The 2D mesh is the most studied NoC topology:

- **Structure**: routers arranged in an N x M grid, each connected to four neighbors
- **Advantages**: regular structure, short wires, scalable, floorplan-friendly
- **Disadvantages**: hop count grows as O(sqrt(N)), may over-provision links for non-uniform traffic
- **Use case**: many-core processors, GPU compute arrays, AI accelerators

The Manhattan distance between source (x1,y1) and destination (x2,y2) is |x1-x2| + |y1-y2| hops.

### Ring Topology

- **Structure**: routers connected in a unidirectional or bidirectional ring
- **Advantages**: simple, low router complexity, predictable latency for small networks
- **Disadvantages**: bandwidth bottleneck for large rings, hop count grows linearly with N
- **Use case**: small SoCs (4-8 nodes), cache coherence rings (e.g., Intel ring bus)

### Tree Topology

- **Structure**: hierarchical tree with root at the top
- **Advantages**: natural fit for hierarchical address decoding, low-latency for local traffic
- **Disadvantages**: root becomes bandwidth bottleneck, poor for uniform random traffic
- **Variants**: fat tree (wider links at higher levels) mitigates root bottleneck

### Hybrid and Custom Topologies

Real SoCs rarely use pure topologies. NoC generators (Arteris FlexNoC, Synopsys DesignWare NoC) create custom topologies optimized for the specific traffic pattern:

- **Star with spurs**: central switch with branches to subsystem clusters
- **Hierarchical mesh**: mesh within subsystems, tree between subsystems
- **Application-specific**: topology shaped by profiled traffic patterns from system models

The choice depends on: traffic pattern, bandwidth requirements, latency constraints, area budget, and floorplan geometry.

## Routing Algorithms

### Deterministic Routing

Every packet between a given source-destination pair follows the same path:

- **XY routing** (for mesh): route in X dimension first, then Y dimension. Simple, deadlock-free, but cannot adapt to congestion.
- **Source routing**: the entire path is encoded in the packet header at the source NI. Low router complexity but inflexible.

### Adaptive Routing

Packets can take different paths based on network conditions:

- **Partially adaptive**: allows some routing freedom while guaranteeing deadlock freedom (e.g., west-first, north-last, odd-even algorithms)
- **Fully adaptive**: packets can take any minimal or non-minimal path; requires deadlock avoidance mechanisms (virtual channels, escape channels)

### Deadlock Avoidance

Routing deadlock occurs when packets form a circular dependency, each waiting for buffer space held by the next. Prevention strategies:

- **Turn restrictions**: prohibit certain turns to break cycles (e.g., XY routing prohibits Y-then-X turns)
- **Virtual channels (VCs)**: multiple virtual channels per physical link, with VC allocation rules that prevent circular dependencies
- **Escape channels**: designate one VC for deadlock-free deterministic routing; adaptive traffic can use other VCs

## Flow Control

### Credit-Based Flow Control

The upstream router tracks available buffer space in the downstream router using credits:

1. Downstream router sends credits upstream (one credit per buffer slot)
2. Upstream router decrements credit count when sending a flit
3. Upstream router blocks when credits are exhausted
4. Downstream router sends new credit when a buffer slot is freed

Credit-based flow control maximizes link utilization but requires credit round-trip latency worth of buffering.

### Virtual Channel Flow Control

Multiple virtual channels share one physical link:

- Prevents head-of-line blocking: if one packet is stalled, others in different VCs can proceed
- Enables QoS: different traffic classes use different VCs with different arbitration priorities
- Typical implementation: 2-4 VCs per physical channel

### Wormhole vs. Store-and-Forward

- **Wormhole**: a packet's header flit reserves the path; body flits follow immediately. Low buffer requirements but susceptible to head-of-line blocking.
- **Virtual cut-through**: header flit can advance before tail arrives, but downstream must guarantee full-packet buffering. Better performance than wormhole for variable-size packets.
- **Store-and-forward**: entire packet is buffered at each hop before forwarding. Highest latency and buffer cost; rarely used in on-chip networks.

## Quality of Service (QoS)

### Traffic Classes

Modern SoCs have diverse traffic requirements:

| Traffic Class | Requirement | Example |
|---|---|---|
| Real-time | Bounded latency | Display controller, audio |
| High-bandwidth | Sustained throughput | Video codec, DMA |
| Low-latency | Minimum response time | CPU cache miss |
| Best-effort | No guarantees | Debug, configuration |

### QoS Mechanisms

- **Priority-based arbitration**: higher-priority traffic wins arbitration at routers
- **Bandwidth regulation**: rate limiters at NIs cap traffic injection per source, preventing starvation
- **Bandwidth reservation**: guaranteed minimum bandwidth allocation per flow or VC
- **Latency bounds**: combination of priority, dedicated VCs, and bandwidth regulation to bound worst-case latency
- **Traffic shaping**: smooth bursty traffic at NIs to reduce congestion

### QoS Configuration

NoC QoS is typically configured through:

- **Static configuration**: fixed priority and bandwidth allocations set at design time
- **Dynamic configuration**: firmware adjusts QoS parameters at runtime based on workload (e.g., video playback mode vs. gaming mode)
- **Hardware-managed**: NoC monitors congestion and adjusts routing/arbitration dynamically

## Power Management

### Clock Gating

- **Router clock gating**: gate router clock when no flits are present; wake on incoming flit
- **Link clock gating**: gate link clock during idle periods; requires wake-up latency
- **NI clock gating**: gate NI clock when IP is idle

### Power Gating

- **Router power gating**: power down unused routers in partially-utilized topologies
- **Requires**: isolation cells on all ports, state retention or re-initialization protocol
- **Challenge**: maintaining connectivity while some routers are powered down; may need bypass paths

### Voltage and Frequency Scaling

- **Per-region DVFS**: different NoC regions operate at different voltage/frequency based on traffic load
- **Requires**: voltage level shifters and clock domain crossings at region boundaries
- **Trade-off**: frequency reduction saves power but increases latency; must maintain QoS guarantees

### Low-Power Link Design

- **Data encoding**: use coding schemes (e.g., bus-invert coding) to reduce switching activity on links
- **Link width adaptation**: dynamically narrow link width during low-traffic periods
- **Drowsy links**: reduce link voltage during idle periods; fast wake-up compared to full power gating

## NoC Design Flow

### System Modeling

1. **Traffic profiling**: run representative workloads on system model to extract traffic patterns
2. **Topology exploration**: evaluate candidate topologies using cycle-accurate NoC simulators
3. **QoS verification**: verify latency and bandwidth guarantees under worst-case traffic

### RTL Generation

NoC generators produce synthesizable RTL from high-level specifications:

- Topology definition (nodes, links, router parameters)
- Address map and routing tables
- QoS configuration (VCs, priorities, bandwidth allocations)
- Power management features

### Physical Implementation

NoC-specific physical design considerations:

- **Floorplan co-optimization**: place routers near their connected IPs; minimize link length
- **Link pipelining**: insert pipeline stages on long links to meet timing; increases latency by one cycle per stage
- **Metal layer assignment**: use upper metal layers for long NoC links to reduce resistance
- **Clock tree**: NoC may span multiple clock domains; careful CTS for each domain

### Verification

- **Protocol checking**: verify NI correctly converts bus transactions to/from packets
- **Deadlock checking**: formal verification of routing algorithm deadlock freedom
- **Performance verification**: cycle-accurate simulation with realistic traffic
- **Power verification**: verify clock/power gating sequences don't drop packets

## Emerging Trends

- **Chiplet NoC**: die-to-die NoC extending on-chip network across chiplet boundaries (UCIe, BoW)
- **Optical NoC**: on-chip photonic links for ultra-high bandwidth
- **ML-optimized NoC**: topologies and routing optimized for machine learning dataflow patterns
- **Security-aware NoC**: traffic isolation, encryption, and side-channel resistance in the network fabric

NoC design bridges computer architecture, networking, and physical design. The right NoC architecture, combined with careful QoS configuration and power management, is critical to achieving the bandwidth, latency, and efficiency targets of modern SoCs.
