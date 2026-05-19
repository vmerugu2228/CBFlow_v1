# GPU Architecture: Shader Cores, Warp Scheduling, Memory Hierarchy, and Compute

## Overview

Graphics Processing Units (GPUs) have evolved from fixed-function graphics accelerators into massively parallel general-purpose processors. Modern GPUs contain thousands of execution units organized for throughput-oriented workloads including 3D rendering, machine learning training and inference, scientific computing, and video processing. Understanding GPU architecture is essential for SoC designers integrating graphics and compute capabilities, from mobile GPUs in smartphone SoCs to discrete datacenter accelerators.

## GPU Architecture Overview

### High-Level Organization

A modern GPU consists of:

- **Shader/Compute cores**: hundreds to thousands of execution units organized into processing clusters
- **Memory hierarchy**: register file, shared memory/L1 cache, L2 cache, DRAM (GDDR/HBM)
- **Fixed-function units**: rasterizer, texture units, render output units (ROPs), video codec, display controller
- **Command processor**: receives commands from CPU via command queues; dispatches work to shader cores
- **Interconnect**: network connecting compute clusters to L2 cache and memory controllers

### Architecture Terminology

| NVIDIA Term | AMD Term | ARM/Qualcomm Term | Description |
|---|---|---|---|
| SM (Streaming Multiprocessor) | CU (Compute Unit) | Shader Core | Basic processing block |
| Warp (32 threads) | Wavefront (32/64 threads) | Warp/Wave | SIMT execution group |
| CUDA Core | Stream Processor | ALU | Single execution unit |
| Tensor Core | Matrix Core | - | Matrix multiply unit |

## SIMT Execution Model

### Single Instruction, Multiple Threads (SIMT)

GPUs execute groups of threads in lockstep, sharing a single instruction stream:

- **Thread**: individual work item with its own registers and program counter (logically)
- **Warp/Wavefront**: group of 32 (NVIDIA) or 32/64 (AMD) threads executing the same instruction simultaneously
- **Divergence**: when threads in a warp take different branch paths, both paths are executed serially with appropriate threads masked; this is called branch divergence and wastes execution cycles
- **Reconvergence**: threads reconverge after the divergent region; hardware stack tracks reconvergence points

### Warp Scheduling

Each SM manages multiple warps to hide latency:

**Scheduling strategies:**
- **Round-robin**: cycle through ready warps sequentially
- **Greedy-then-oldest (GTO)**: continue executing current warp until it stalls, then switch to oldest ready warp
- **Two-level scheduling**: divide warps into active and pending groups; schedule from active group; swap groups when all stall
- **Loose round-robin (LRR)**: round-robin with some flexibility to skip stalled warps

**Latency hiding:**
- When a warp stalls on memory access (100-400 cycles), the scheduler immediately switches to another ready warp
- With enough concurrent warps (occupancy), memory latency is completely hidden
- This is fundamentally different from CPUs, which rely on caches and speculation to hide latency

### Occupancy

Occupancy = active warps / maximum warps per SM

Factors limiting occupancy:
- **Register usage**: each thread uses registers from a fixed register file; more registers per thread = fewer concurrent threads
- **Shared memory usage**: shared memory is partitioned among thread blocks; more shared memory per block = fewer concurrent blocks
- **Thread block size**: must be a multiple of warp size; maximum threads per block is hardware-limited

Higher occupancy generally (but not always) improves performance by providing more warps for latency hiding.

## Shader Core (SM/CU) Architecture

### Execution Units

A typical SM contains:

- **INT32 units**: integer arithmetic (32 units in many NVIDIA SM generations)
- **FP32 units**: single-precision floating-point (32-128 units)
- **FP64 units**: double-precision (typically 1/2 or 1/32 of FP32 throughput)
- **FP16 units**: half-precision (2x FP32 throughput; important for ML inference)
- **SFU (Special Function Unit)**: transcendentals (sin, cos, exp, rsqrt)
- **Load/Store units**: address generation and memory access
- **Tensor cores**: dedicated matrix multiply-accumulate (e.g., 4x4 FP16 matrix multiply per cycle)

### Register File

- Extremely large per SM: 64K-256K 32-bit registers
- Partitioned among all threads in all active warps
- Register allocation is static at kernel launch; determined by compiler
- No register renaming (unlike CPU); thread registers are architecturally mapped

### Shared Memory and L1 Cache

- Per-SM configurable memory (e.g., 48KB shared + 16KB L1, or 16KB shared + 48KB L1)
- **Shared memory**: software-managed scratchpad; visible to all threads in a thread block; enables inter-thread communication
- **Bank conflicts**: shared memory organized in banks (32 banks); simultaneous access to same bank serializes (except broadcast)
- **L1 cache**: caches global memory accesses; unified with shared memory in newer architectures

## Memory Hierarchy

### Register File
- Fastest access (zero latency beyond pipeline)
- Largest aggregate storage (across all SMs, hundreds of KB to MB)
- Private per-thread

### Shared Memory / L1 Cache
- Per-SM, ~64-228 KB
- Low latency (~20-30 cycles)
- Shared among threads in a block (shared memory) or cached globally (L1)

### L2 Cache
- Shared across all SMs
- Size: 2-96 MB depending on GPU
- Latency: ~200 cycles
- Serves as coherence point for multi-SM access

### Global Memory (GDDR/HBM)
- Off-chip DRAM accessed through memory controllers
- **GDDR6/6X**: 16-24 GB, 500-1000 GB/s bandwidth
- **HBM2/HBM2E/HBM3**: stacked memory, 16-80 GB, 1-3 TB/s bandwidth
- Latency: 400-800 cycles
- Coalescing: adjacent threads accessing consecutive addresses merge into fewer memory transactions

### Memory Access Patterns

**Coalesced access**: threads in a warp access consecutive memory locations; hardware merges into a single wide transaction. Critical for performance.

**Strided access**: threads access non-consecutive addresses; results in multiple memory transactions; poor bandwidth utilization.

**Random access**: worst case; each thread generates a separate transaction.

## Graphics Pipeline

### Fixed-Function Stages

1. **Input Assembly**: read vertex/index buffers
2. **Vertex Shader**: transform vertex positions, compute per-vertex attributes (programmable)
3. **Tessellation**: subdivide geometry (optional, programmable control + fixed evaluation)
4. **Geometry Shader**: per-primitive processing (optional, programmable)
5. **Rasterization**: convert triangles to fragments (fixed-function)
6. **Fragment/Pixel Shader**: compute per-pixel color, texture sampling (programmable)
7. **Depth/Stencil Test**: per-fragment visibility testing (fixed-function)
8. **ROP (Render Output Unit)**: blending, anti-aliasing, write to framebuffer (fixed-function)

### Texture Units

- **Texture fetch**: read texels from texture maps stored in memory
- **Filtering**: bilinear, trilinear, anisotropic filtering in hardware
- **Cache hierarchy**: dedicated texture cache (L1T) for spatial locality
- **Texture formats**: compressed (BC/ASTC), HDR, sRGB conversion in hardware

### Tile-Based Rendering (Mobile GPUs)

Mobile GPUs (ARM Mali, Qualcomm Adreno, Imagination PowerVR) use tile-based deferred rendering (TBDR):

1. **Geometry pass**: bin triangles into screen-space tiles
2. **Per-tile rendering**: render each tile entirely in on-chip tile memory
3. **Tile writeback**: write completed tile to framebuffer in DRAM

**Advantage**: dramatically reduces bandwidth to external memory (the primary power consumer in mobile)
**Trade-off**: requires geometry pass to complete before pixel processing; binning overhead

## Compute Shaders and GPGPU

### Programming Models

- **CUDA**: NVIDIA's proprietary compute platform; dominant in ML/HPC
- **OpenCL**: open standard for heterogeneous computing; cross-vendor
- **Vulkan Compute**: compute shaders through Vulkan API
- **Metal**: Apple's GPU compute API
- **ROCm/HIP**: AMD's CUDA-compatible compute platform

### Kernel Execution Model

1. Application defines a **kernel** (function to run on GPU)
2. Kernel launched with a **grid** of **thread blocks** (work groups)
3. Each thread block assigned to one SM; threads in block can synchronize via shared memory
4. Thread blocks are independent; can execute in any order on any SM
5. Hardware schedules thread blocks to SMs based on resource availability

### Tensor Cores / Matrix Units

Dedicated matrix multiply-accumulate hardware for ML workloads:

- **NVIDIA Tensor Cores**: 4x4 FP16 matrix multiply + FP32 accumulate per cycle per tensor core
- **Sparsity support**: 2:4 structured sparsity doubles effective throughput (A100+)
- **Data types**: FP16, BF16, TF32, INT8, INT4, FP8 (progressively added in newer generations)
- **Throughput**: hundreds of TFLOPS for matrix operations vs. tens of TFLOPS for scalar FP

## Power and Thermal Management

### GPU Power Characteristics

- **Dynamic power**: dominated by thousands of ALUs switching; proportional to voltage, frequency, and utilization
- **Memory bandwidth power**: significant contributor; HBM reduces per-bit energy vs. GDDR
- **Leakage**: large die area means substantial leakage, especially at advanced nodes

### Power Management Techniques

- **DVFS**: dynamic voltage-frequency scaling based on workload and thermal headroom
- **Clock gating**: fine-grained per-SM and per-unit clock gating during idle cycles
- **Power gating**: disable idle SMs entirely; wake on demand
- **Thermal throttling**: reduce frequency when junction temperature exceeds limit
- **Power limit**: firmware enforces TDP (Thermal Design Power) by throttling frequency

## GPU in SoC Integration

### Integrated GPU Considerations

- **Memory sharing**: GPU uses system DRAM (shared with CPU); bandwidth contention
- **Cache coherency**: GPU may or may not be coherent with CPU caches; explicit flush/invalidate for non-coherent
- **Interconnect bandwidth**: GPU-to-memory path through SoC interconnect (NoC or dedicated)
- **Power domain**: GPU typically in its own power domain for independent DVFS and power gating
- **Driver model**: kernel-mode driver manages command submission, memory allocation, scheduling

GPU architecture is fundamentally optimized for throughput over latency, using massive parallelism and hardware multithreading to hide memory latency. This architectural philosophy makes GPUs unmatched for data-parallel workloads but requires understanding of the memory hierarchy, occupancy, and divergence characteristics for effective utilization.
