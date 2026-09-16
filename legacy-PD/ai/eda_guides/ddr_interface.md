# DDR Memory Interface: PHY, Controller, Timing, and Calibration

## Overview

DDR (Double Data Rate) SDRAM is the dominant external memory technology for computing systems, from mobile phones to data center servers. Designing a DDR interface requires deep understanding of the PHY (physical layer), memory controller, signal integrity, timing margins, and training algorithms. The DDR interface is often the most timing-critical and power-hungry subsystem on an SoC, and its performance directly determines system throughput for memory-bound workloads.

## DDR Generations

### DDR4

- **Data rate**: 1600-3200 MT/s per pin
- **Voltage**: 1.2V
- **Prefetch**: 8n (8 bits per read/write per clock)
- **Bank groups**: 4 bank groups with 4 banks each (16 total)
- **Features**: CRC on write data, parity on command/address, VrefDQ training
- **Use case**: desktops, servers, embedded systems

### DDR5

- **Data rate**: 3200-8800 MT/s per pin
- **Voltage**: 1.1V
- **Prefetch**: 16n
- **Channels**: dual independent 32-bit channels per DIMM (vs. single 64-bit in DDR4)
- **Features**: on-die ECC, decision feedback equalization (DFE), improved power management (PMIC on DIMM)
- **Bank groups**: 8 bank groups with 4 banks each (32 total)

### LPDDR4/LPDDR5

- **LPDDR4**: 1600-4266 MT/s, 1.1V/0.6V, 16-bit channels, low-power mobile focus
- **LPDDR5**: 3200-8533 MT/s, 1.05V/0.5V, dynamic voltage-frequency scaling, write-X feature for power savings
- **LPDDR5X**: up to 8533 MT/s, further power reductions
- **Use case**: smartphones, tablets, automotive, AI at the edge

## PHY Architecture

### Transmit Path

The DDR PHY transmit path converts parallel data from the controller into serialized DDR signals:

1. **Write FIFO**: buffers data from controller clock domain
2. **Serializer (OSER)**: converts parallel data to double-data-rate (DDR) serial stream
3. **Output driver**: push-pull driver with programmable impedance (ZQ calibration)
4. **DQS generation**: data strobe aligned with data transitions, with programmable delay

Key transmit parameters:
- **Output impedance**: 34/40/48 ohm, matched to transmission line characteristic impedance
- **Slew rate**: controlled to reduce EMI while maintaining eye opening
- **Pre-emphasis**: optional driver pre-emphasis for high data rates to compensate channel loss

### Receive Path

The receive path captures DDR signals and delivers parallel data to the controller:

1. **Input buffer**: differential receiver for DQ and DQS with programmable Vref
2. **DQS delay line**: programmable delay to center DQS in the data eye
3. **Sampler (ISER)**: captures data on both edges of delayed DQS
4. **Deserializer**: converts serial DDR data to parallel for controller
5. **Read FIFO**: re-synchronizes data from DQS domain to controller clock domain

### DLL/PLL

- **DLL (Delay-Locked Loop)**: generates precisely delayed clocks for timing alignment; used in older DDR PHYs
- **PLL (Phase-Locked Loop)**: generates PHY clocks from reference clock; provides frequency multiplication and phase adjustment
- **Phase interpolator**: fine-grained phase adjustment for per-bit deskew

### ZQ Calibration

ZQ calibration matches the PHY output driver impedance to an external precision resistor:

- **Initial calibration (ZQCAL)**: performed at power-up; sweeps driver strength to match 240-ohm external resistor
- **Periodic calibration (ZQCS)**: short calibration to track PVT (process, voltage, temperature) drift
- **Importance**: impedance mismatch causes signal reflections that close the data eye

## Memory Controller Architecture

### Command/Address Path

The controller generates DRAM commands following strict protocol timing:

- **Activate (ACT)**: opens a row in a bank; must wait tRCD before read/write
- **Read (RD)**: issues column address; data arrives after CAS latency (CL)
- **Write (WR)**: issues column address; data sent after write latency (WL)
- **Precharge (PRE)**: closes an open row; must wait tRP before next activate
- **Refresh (REF)**: refreshes all rows; occurs periodically (tREFI ~7.8 us for DDR4)

### Scheduling

The memory controller scheduler optimizes DRAM access patterns:

- **Open-page policy**: keep rows open, exploit locality (hits to open rows avoid tRCD penalty)
- **Close-page policy**: precharge after each access, good for random traffic
- **Adaptive policy**: switch based on observed hit rate
- **Reordering**: reorder pending requests to maximize bank-level parallelism and row hits
- **Priority**: honor QoS priorities from the SoC interconnect

### Refresh Management

DRAM cells leak charge and require periodic refresh:

- **All-bank refresh**: all banks unavailable during tRFC (350 ns for 16Gb DDR4)
- **Per-bank refresh**: refresh one bank while others remain accessible (DDR5)
- **Fine-granularity refresh**: shorter, more frequent refresh windows reduce worst-case latency
- **Temperature-dependent refresh**: increase refresh rate at high temperatures
- **Targeted row refresh (TRR)**: mitigate row-hammer attacks by refreshing victim rows

### ECC and RAS

Reliability features in the memory controller:

- **Inline ECC**: SECDED (single-error correct, double-error detect) using extra data bits
- **On-die ECC**: DDR5 DRAMs have internal ECC (corrects single-bit errors within each 128-bit word before data leaves the DRAM)
- **Link ECC**: CRC/parity on the data bus to detect transmission errors
- **Scrubbing**: background reads to detect and correct soft errors before they accumulate
- **Address/command parity**: detect command bus errors

## Timing Parameters and Margins

### Key Timing Parameters

| Parameter | Description | DDR4 Example |
|---|---|---|
| tCK | Clock period | 0.625 ns (3200 MT/s) |
| CL | CAS latency (read) | 22 clocks |
| tRCD | Row-to-column delay | 14.16 ns |
| tRP | Row precharge time | 14.16 ns |
| tRAS | Row active time | 32 ns |
| tRC | Row cycle time | tRAS + tRP |
| tRFC | Refresh cycle time | 350 ns (16Gb) |
| tREFI | Refresh interval | 7.8 us |

### Timing Budget

The data eye at the receiver must have sufficient margin:

```
Total eye width = tCK/2 (unit interval)
  - Setup time of receiver
  - Hold time of receiver
  - DQ-DQS skew (per-bit + per-byte)
  - Jitter (PLL, DLL, ISI)
  - Cross-talk noise
  - Board/package SI effects
  = Remaining margin (must be > 0)
```

At DDR5-6400, the unit interval is 312.5 ps. After subtracting all timing consumers, the remaining margin may be only 20-40 ps, demanding aggressive training and careful board design.

## Training and Calibration

### Write Leveling

Compensates for clock-DQS skew caused by fly-by routing topology (DDR4/5):

1. Controller sends DQS transitions
2. DRAM samples DQS against CK and reports early/late
3. Controller adjusts DQS delay per byte lane until aligned with CK at the DRAM

### Read Gate Training

Determines when to enable the read DQS receiver:

1. Controller issues read commands
2. PHY sweeps the gate enable timing
3. Finds the window where valid DQS preamble is captured
4. Centers the gate enable within this window

### Write/Read DQ Training (Per-Bit Deskew)

Optimizes timing for each individual DQ bit:

1. Write known patterns to DRAM
2. Read back and compare
3. Sweep per-bit delay elements
4. Find passing window for each bit
5. Center delay in the passing window

### Vref Training

Optimizes the receive voltage reference for maximum noise margin:

- **Host Vref training**: adjust PHY receiver Vref for read data
- **DRAM Vref training (DDR4 MR6)**: adjust DRAM receiver Vref for write data
- **2D training**: simultaneously sweep timing and Vref to find the optimal (delay, Vref) point in the center of the 2D eye

### Training Sequence

A complete DDR initialization and training sequence:

1. Power-up and reset sequence
2. ZQ calibration (impedance matching)
3. Mode register programming (timing, ODT, Vref)
4. Write leveling
5. Read gate training
6. Write DQ training (per-bit deskew)
7. Read DQ training (per-bit deskew)
8. Vref training (2D sweep)
9. Periodic retraining during operation (for temperature drift)

## Board-Level Considerations

### Routing Guidelines

- **Length matching**: DQ/DQS signals matched within 5 mil per byte group
- **Fly-by topology**: CK/CMD/ADDR routed sequentially through DIMMs (compensated by write leveling)
- **Impedance control**: 40-50 ohm single-ended, 80-100 ohm differential for DQS
- **ODT (On-Die Termination)**: proper ODT settings critical for signal integrity; varies by topology and data rate

### Power Delivery

- **Decoupling**: extensive decoupling on VDD, VDDQ, and VPP rails
- **PMIC placement**: DDR5 DIMMs have on-DIMM PMIC; LPDDR uses SoC-integrated regulators
- **Power sequencing**: DRAM requires specific power-up sequence (VPP before VDD in some devices)

## Debug and Characterization

- **Eye diagram measurement**: capture the data eye at the receiver using oscilloscope or built-in eye monitor
- **Margin testing**: run training with artificially reduced margins to find weak bits
- **Shmoo plot**: 2D pass/fail map sweeping timing and voltage; visualizes margin
- **Error injection**: deliberately inject errors to verify ECC and error reporting paths
- **Thermal characterization**: run training at temperature extremes to verify margin across range

DDR interface design requires the convergence of analog circuit design, digital logic, signal integrity, and software (training firmware). A robust DDR subsystem with sufficient margin across PVT corners is essential for system reliability.
