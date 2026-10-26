# AI Accelerator Design

## Overview

AI accelerators (NPUs, TPUs, neural processing units) are specialized chips designed to execute neural network inference and training workloads with far greater efficiency than general-purpose CPUs or GPUs. The explosion of AI workloads from large language models, computer vision, recommendation systems, and autonomous driving has created a massive demand for purpose-built silicon. PD engineers working on AI accelerators face unique challenges: extremely high compute density, massive memory bandwidth requirements, complex dataflow architectures, and aggressive power targets. This guide covers the architectural concepts and physical design considerations specific to AI chip design.

## Systolic Arrays

### Concept

A systolic array is a grid of processing elements (PEs) connected in a regular, nearest-neighbor topology. Data flows rhythmically through the array (like a heartbeat, hence "systolic"), with each PE performing a multiply-accumulate (MAC) operation on the data as it passes through.

### How It Works

For matrix multiplication (C = A x B), the fundamental operation in neural networks:

```
        B columns flow down
        |   |   |   |
A row ->PE ->PE ->PE ->PE -> Output
A row ->PE ->PE ->PE ->PE -> Output
A row ->PE ->PE ->PE ->PE -> Output
```

Each PE receives one element from matrix A (from the left) and one element from matrix B (from above), multiplies them, adds the result to its accumulator, and passes the data to the next PE.

### Google TPU Systolic Array

Google's TPU v1 uses a 256x256 systolic array of 8-bit MACs:

- 256 x 256 = 65,536 MACs
- Operating at ~700 MHz = ~92 TOPS (Tera Operations Per Second) at INT8
- Total area: ~331 mm2 in 28nm

### Physical Design Implications

- **Regular structure**: Systolic arrays are highly regular, enabling structured placement approaches
- **High density**: 65K MACs in a small area creates extreme cell density and congestion
- **Clock distribution**: The clock must reach every PE with minimal skew across the entire array. A 256x256 array spanning several millimeters requires careful CTS
- **Data movement**: Input data must be distributed to array edges; output data must be collected. This creates high wire density at array boundaries
- **Power delivery**: The array consumes significant power; uniform IR drop across the array is critical for consistent timing

## Dataflow Architectures

### Why Dataflow Matters

In neural networks, the dominant cost is data movement, not computation. Moving one byte of data from off-chip DRAM consumes 100-1000x more energy than performing one MAC operation. Dataflow architecture determines how data (weights, activations, partial sums) flows through the compute array and memory hierarchy.

### Dataflow Types

**Weight-stationary**: Weights are loaded into the PEs and remain there while activations flow through. Minimizes weight movement.

- **Best for**: Layers where the same weights are reused across many input activations (e.g., fully connected layers)
- **Physical implication**: Each PE has a local weight register that is loaded once and read many times. Weight distribution network is simple

**Output-stationary**: Partial sums (outputs) remain in the PEs and accumulate as weights and activations flow through. Minimizes partial sum movement.

- **Best for**: Convolutional layers where each output pixel accumulates many partial products
- **Physical implication**: PEs need accumulators with sufficient bit width (16-32 bits) to hold intermediate sums without overflow

**Input-stationary**: Input activations remain in PEs while weights flow through. Minimizes input movement.

- **Best for**: Depthwise separable convolutions and certain RNN architectures

**Row-stationary**: A hybrid approach (used in MIT Eyeriss) that maps computation to maximize data reuse across all data types simultaneously.

### Reconfigurable Dataflow

Advanced accelerators support multiple dataflow modes, switching between weight-stationary, output-stationary, and other modes depending on the layer type. This maximizes utilization across diverse neural network architectures.

**Physical implication**: Reconfigurable dataflow requires more complex interconnects between PEs (not just nearest-neighbor) and multiplexed data paths, increasing routing complexity.

## Memory Hierarchy

### The Memory Wall

AI workloads demand massive memory bandwidth:

- A single transformer inference (GPT-class model) reads hundreds of GB of weights
- Training updates these weights for every batch, requiring both read and write bandwidth
- Activation memory grows with batch size and model width

### Memory Levels

**Register file**: Within each PE, registers hold the current operands (weight, activation, partial sum). Access energy: ~0.01 pJ per read.

**Local SRAM (scratchpad)**: Shared across a group of PEs. Stores weight tiles, activation tiles, and partial sums. Typical size: 256KB-4MB per compute cluster. Access energy: ~1-5 pJ per read.

**Global SRAM buffer**: Chip-level buffer shared across all compute clusters. Typical size: 16-64MB. Access energy: ~10-50 pJ per read.

**HBM (High Bandwidth Memory)**: Off-chip DRAM stacked on a silicon interposer adjacent to the compute die. Provides 1-6 TB/s bandwidth. Typical capacity: 16-192 GB. Access energy: ~10-20 pJ per bit.

**Off-package DRAM**: Standard DDR or LPDDR memory on the board. Lower bandwidth, highest capacity, highest energy per access.

### Physical Design Implications

- **SRAM dominance**: AI accelerators are often 50-70% SRAM by area. Macro placement is the critical floorplan challenge
- **Memory bandwidth matching**: The compute array must be fed by sufficient memory bandwidth. This drives SRAM capacity and placement proximity decisions
- **HBM integration**: HBM stacks are placed adjacent to the compute die on a silicon interposer. The D2D interface requires careful physical design (see chiplet_design.md)
- **Power for SRAM**: SRAM read/write consumes significant dynamic power. SRAM placement must consider power grid capacity

## Sparsity Exploitation

### The Opportunity

Neural networks exhibit significant sparsity:

- **Weight sparsity**: After pruning, 50-95% of weights can be zero
- **Activation sparsity**: ReLU activation function outputs zero for negative inputs, creating 30-70% activation sparsity
- **Structured sparsity**: NVIDIA's 2:4 structured sparsity format guarantees that at least 2 out of every 4 elements are zero

### Hardware Support

**Sparse encodings**: Store only non-zero values with their indices (CSR, CSC, bitmap formats). Reduces memory footprint and bandwidth.

**Zero-skipping**: Skip MAC operations where one operand is zero. Saves compute energy and time.

**Sparse compute units**: PEs that can process variable numbers of non-zero elements per cycle.

### Physical Design Implications

- **Irregular data access**: Sparse formats create non-sequential memory access patterns, complicating SRAM design
- **Variable throughput**: Sparse compute units have workload-dependent throughput, complicating timing and utilization analysis
- **Index processing overhead**: Logic for compressing/decompressing sparse formats adds area and timing paths
- **Interconnect complexity**: Routing non-zero values to the correct PEs requires crossbar or routing networks, increasing congestion

## Quantization

### Concept

Quantization reduces the numerical precision of weights and activations from floating point (FP32, FP16) to lower-precision formats (INT8, INT4, or even binary).

### Common Formats

| Format | Bits | Dynamic Range | Use Case |
|--------|------|--------------|----------|
| FP32 | 32 | High | Training (baseline) |
| BF16 | 16 | High (same exponent as FP32) | Training |
| FP16 | 16 | Medium | Training/inference |
| FP8 (E4M3/E5M2) | 8 | Medium | Training |
| INT8 | 8 | Low | Inference |
| INT4 | 4 | Very low | Inference (with calibration) |
| Binary/Ternary | 1-2 | Minimal | Specialized inference |

### Impact on Hardware

- **MAC unit size**: An INT8 multiplier is ~4x smaller than an FP16 multiplier. Lower precision means more MACs per unit area
- **Memory bandwidth**: INT8 requires half the bandwidth of FP16 for the same number of operations. This relaxes the memory wall problem
- **Accumulator width**: Even with INT8 inputs, the accumulator must be wider (INT32) to avoid overflow during summation

### Physical Design Implications

- **Configurable precision**: Many accelerators support multiple precisions. MAC units have configurable datapath width, requiring muxing logic
- **Mixed precision**: Different layers may use different precision. The compute array must handle precision transitions
- **Power efficiency**: Lower precision reduces switching activity and power. An INT8 accelerator consumes approximately 4x less power per operation than FP16

## NPU/TPU Design Considerations

### Architecture Choices

**SIMD vs. Systolic vs. Spatial**: Different compute organizations offer different tradeoffs:

- **SIMD (Single Instruction Multiple Data)**: Simple control, well-suited for vector operations. Used in GPU tensor cores
- **Systolic array**: High utilization for matrix operations, regular data flow. Used in Google TPU
- **Spatial (CGRA-style)**: Configurable interconnect for flexible dataflow. Higher utilization across diverse workloads but more complex to program and implement

### On-Chip Network

AI accelerators require high-bandwidth, low-latency on-chip networks to connect compute clusters with memory:

- **Network-on-Chip (NoC)**: Packet-switched network for scalable multi-cluster communication
- **Bus/crossbar**: Simpler interconnect for smaller designs
- **Mesh/torus**: Regular topology matching the 2D layout of compute clusters

**Physical implication**: NoC routers and links consume significant area and power. NoC placement and routing affect chip-level timing and congestion.

### Compiler and Hardware Co-Design

AI accelerators are only useful if the compiler can efficiently map neural network computations onto the hardware:

- **Tiling**: The compiler partitions matrices into tiles that fit in local SRAM
- **Loop ordering**: The compiler determines the order of computation to maximize data reuse
- **Hardware-software interface**: The hardware architecture must expose enough flexibility for the compiler to optimize, without being so flexible that the hardware is inefficient

### Physical Design-Specific Challenges

**Power density**: AI accelerators can have power densities exceeding 1 W/mm2, approaching thermal limits. Power grid must handle extreme current density.

**Clock frequency vs. parallelism tradeoff**: AI accelerators often run at moderate clock frequencies (500 MHz - 1.5 GHz) but with massive parallelism (thousands of MACs). This relaxes timing closure compared to high-frequency CPUs but creates challenges in clock distribution across large arrays.

**Die size**: High-end AI accelerators push toward reticle limits (800mm2). Yield is a critical concern. Some designs adopt chiplet approaches to address this.

**I/O bandwidth**: HBM PHYs, PCIe Gen5/Gen6, and CXL interfaces consume significant die edge area and power. I/O placement and floor planning must balance compute area with I/O bandwidth.

**Thermal management**: Hot spots in the compute array can cause local timing degradation and reliability issues. Thermal-aware floorplanning distributes heat sources.

## Industry Landscape

| Accelerator | Company | Process | Architecture | Peak Performance |
|-------------|---------|---------|-------------|-----------------|
| TPU v5e | Google | 5nm | Systolic array | ~200 TFLOPS (BF16) |
| H100 | NVIDIA | 4nm | Tensor cores (SIMD) | 989 TFLOPS (FP8) |
| Trainium2 | AWS | 5nm | Systolic + SIMD | ~190 TFLOPS (BF16) |
| Gaudi 3 | Intel | 5nm | Matrix engines | ~1835 TFLOPS (FP8) |
| MI300X | AMD | 5nm/6nm | Matrix cores | ~1307 TFLOPS (FP8) |

These numbers evolve rapidly; the key insight is that AI accelerator design is a fast-moving domain where physical design innovation directly translates to competitive advantage.

## Summary for PD Engineers

AI accelerator physical design differs from general-purpose chip design in several key ways:

1. **Regularity**: Massive regular structures (systolic arrays, SRAM arrays) dominate the floorplan
2. **Memory-centric**: SRAM placement and data path routing are the critical floorplan decisions
3. **Power density**: Extreme compute density creates power delivery and thermal challenges
4. **Bandwidth-driven**: Memory bandwidth requirements drive interposer (HBM) and I/O PHY decisions
5. **Precision flexibility**: Multi-precision compute units add design complexity
6. **Scale**: Die sizes approaching reticle limits require chiplet strategies and yield optimization

PD engineers working on AI accelerators should develop expertise in large-scale regular structure placement, high-power-density PDN design, HBM/interposer integration, and thermal-aware floorplanning.
