# DSP Design: Filters, FFT, MAC Units, Fixed-Point Arithmetic, and Optimization

## Overview

Digital Signal Processing (DSP) is fundamental to many SoC applications including audio, communications, radar, image processing, and sensor fusion. DSP hardware ranges from dedicated accelerators with specialized datapaths to programmable DSP cores with instruction-level optimizations. Understanding DSP algorithms, hardware architectures, fixed-point arithmetic, and optimization techniques is essential for designing efficient signal processing subsystems.

## Core DSP Operations

### Multiply-Accumulate (MAC)

The MAC operation is the fundamental building block of DSP:

```
accumulator = accumulator + (A * B)
```

**Hardware implementation:**
- **Multiplier**: array multiplier, Booth-encoded multiplier, or Wallace tree multiplier
- **Accumulator**: wide adder with register (typically 40-80 bits to prevent overflow)
- **Single-cycle MAC**: pipelined multiply and add in one clock cycle
- **Throughput**: one MAC per cycle per MAC unit

**MAC sizing:**
- 16x16 + 40-bit accumulator: common for audio and communications DSP
- 24x24 + 56-bit accumulator: high-precision audio
- 32x32 + 64-bit accumulator: general-purpose DSP
- 8x8 + 32-bit accumulator: ML inference (INT8 dot products)

### Fused Operations

DSP architectures often provide fused operations:

- **Dual MAC**: two MAC operations per cycle using separate data paths
- **Complex MAC**: (a+jb)(c+jd) = (ac-bd) + j(ad+bc) in one or two cycles
- **Saturating add/subtract**: clamp result at max/min value instead of wrapping (prevents audio clicks)
- **Rounding**: convergent rounding (round-to-even) for unbiased results

## FIR Filters

### Finite Impulse Response Filter

FIR filters compute a weighted sum of input samples:

```
y[n] = sum(h[k] * x[n-k]) for k = 0 to N-1
```

where h[k] are the filter coefficients and N is the filter order.

**Properties:**
- **Linear phase**: symmetric coefficients guarantee linear phase response (no phase distortion)
- **Stability**: always stable (no feedback)
- **Latency**: N/2 samples for symmetric FIR (group delay)
- **Computation**: N MACs per output sample

### FIR Hardware Implementation

**Direct form:**
- Shift register for input samples (N-1 delay elements)
- N multipliers + (N-1) adders for fully parallel implementation
- Throughput: one output per clock cycle
- Area: O(N) multipliers

**Transpose form:**
- Pipeline multipliers output through adder chain
- Better timing (shorter critical path through single adder vs. adder tree)
- Same throughput as direct form

**Systolic array:**
- Data flows through pipeline of processing elements
- Each PE: one multiplier + one adder + one delay
- Natural fit for FPGA implementation
- High clock frequency due to short combinational paths

**Time-multiplexed (single MAC):**
- One MAC unit reused N times per output sample
- Area: O(1) multiplier; throughput: one output per N clocks
- Use case: low-area implementations when sample rate is much lower than clock rate

**Polyphase decomposition:**
- Splits FIR into M sub-filters for M-fold decimation or interpolation
- Reduces computation by factor of M
- Standard technique for sample rate conversion

## IIR Filters

### Infinite Impulse Response Filter

IIR filters use feedback, enabling sharper frequency response with fewer coefficients:

```
y[n] = sum(b[k]*x[n-k]) - sum(a[k]*y[n-k])
```

**Properties:**
- **Efficiency**: equivalent frequency response with 1/5 to 1/10 the coefficients of FIR
- **Non-linear phase**: inherent phase distortion (can be mitigated with all-pass compensation)
- **Stability**: feedback can cause instability if poles are outside unit circle
- **Sensitivity**: coefficient quantization can move poles, affecting stability and frequency response

### IIR Implementation

**Second-Order Sections (SOS/biquad):**
- Cascade of second-order biquad sections: each section has 2 poles and 2 zeros
- More numerically stable than high-order direct form
- Each biquad: 5 multiplications + 4 additions per sample
- Standard structure for audio EQ, crossover filters

**Hardware considerations:**
- Feedback path creates a data dependency: y[n-1] must be available before computing y[n]
- Limits pipelining: cannot pipeline within a single biquad section
- Solution: pipeline between biquad stages (inter-section pipelining)
- Look-ahead computation: algebraic transformation to enable limited intra-section pipelining

## FFT (Fast Fourier Transform)

### Algorithm

The FFT computes the Discrete Fourier Transform in O(N log N) operations instead of O(N^2):

- **Radix-2**: split N-point DFT into two N/2-point DFTs; requires N to be power of 2
- **Radix-4**: split into four N/4-point DFTs; reduces multiplications by ~25% vs. radix-2
- **Split-radix**: combines radix-2 and radix-4 for further reduction
- **Mixed-radix**: supports arbitrary N by combining different radix stages

### FFT Hardware Architecture

**Pipelined FFT (streaming):**
- Each butterfly stage is a dedicated hardware unit
- Data flows continuously through the pipeline
- Throughput: one output per clock cycle after pipeline fill
- Latency: N + pipeline depth
- Area: O(log N) butterfly units + O(N) memory for delay lines
- Use case: high-throughput continuous processing (radar, communications)

**Memory-based FFT (iterative):**
- Single butterfly unit reuses memory across stages
- N/2 butterfly operations per stage, log2(N) stages
- Throughput: one N-point FFT per N*log2(N)/2 clocks
- Area: O(1) butterfly unit + O(N) memory
- Use case: lower-throughput or area-constrained designs

**Butterfly unit (radix-2):**
```
X = A + W*B   (twiddle factor multiplication + addition)
Y = A - W*B   (subtraction)
```
Requires: one complex multiplier (4 real multipliers + 2 real adders) + 2 complex adders

**Twiddle factors:**
- Pre-computed ROM storing W = exp(-j*2*pi*k/N) values
- For radix-4: can reduce ROM by 4x using symmetry properties
- CORDIC-based twiddle: compute on-the-fly without ROM (area-efficient but higher latency)

### FFT Precision Considerations

- **Input word width**: typically 12-16 bits for ADC data
- **Internal word width**: grows by ~1 bit per stage (to prevent overflow) or use block floating-point
- **Twiddle factor width**: 16-24 bits depending on FFT size and SNR requirements
- **Block floating-point**: track maximum value per stage; apply common exponent; reduces word width

## Fixed-Point Arithmetic

### Why Fixed-Point

- **Area**: fixed-point multiplier ~1/4 area of floating-point at same bit width
- **Power**: proportionally lower dynamic power
- **Latency**: shorter combinational path
- **Determinism**: predictable timing and behavior

### Representation

**Qm.n format**: m integer bits + n fractional bits (total m+n+1 bits with sign)

Example: Q1.15 = 1 sign bit + 1 integer bit + 15 fractional bits = 16 bits total
- Range: -2.0 to +1.99997 (approximately)
- Resolution: 2^(-15) = 0.0000305

### Quantization Effects

**Truncation**: discard LSBs; introduces negative bias (DC offset)
**Rounding**: add 0.5 LSB before truncation; reduces bias but increases noise power slightly
**Convergent rounding**: round-to-even on tie; eliminates statistical bias entirely
**Saturation**: clamp at maximum/minimum value instead of wrapping; prevents catastrophic distortion

### Overflow Prevention

- **Guard bits**: extra MSBs in accumulator to absorb growth (e.g., N-tap FIR needs ceil(log2(N)) guard bits)
- **Scaling**: scale input or intermediate results to prevent overflow (shifts are free in hardware)
- **Block floating-point**: shared exponent for a block of values; balance between fixed and floating-point

### Fixed-Point Design Flow

1. **Algorithm development**: implement in floating-point (MATLAB, Python)
2. **Range analysis**: determine maximum values at each node; set integer widths
3. **Precision analysis**: simulate with various fractional widths; measure SNR, ENOB, or BER
4. **Bit-true model**: fixed-point model matching hardware behavior exactly
5. **RTL implementation**: implement matching bit-true model
6. **Verification**: compare RTL output against bit-true reference model

## DSP Processor Architecture

### Harvard Architecture

DSP processors use separate instruction and data memories:

- **Dual data memory**: X memory and Y memory for simultaneous operand fetch
- **Zero-overhead loops**: hardware loop counters avoid branch overhead
- **Bit-reversed addressing**: hardware support for FFT butterfly address generation
- **Circular buffering**: automatic modulo addressing for delay lines
- **Saturating arithmetic**: hardware saturation modes to prevent wrap-around

### VLIW (Very Long Instruction Word)

Many DSP processors use VLIW to exploit instruction-level parallelism:

- Multiple execution units (2-8 MACs, ALUs, load/store units)
- Compiler packs independent operations into a single wide instruction
- No dynamic scheduling overhead (unlike superscalar CPUs)
- Examples: TI C6000 (8-way VLIW), CEVA-XC (16-way)

### SIMD Extensions

General-purpose processors add DSP capability via SIMD:

- **ARM NEON**: 128-bit vectors (4x32, 8x16, 16x8)
- **ARM SVE/SVE2**: scalable vectors (128-2048 bits); includes DSP-oriented instructions
- **RISC-V V extension**: scalable vector with extensive DSP operations
- **x86 AVX-512**: 512-bit vectors with FMA (fused multiply-add)

## DSP Optimization Techniques

### Algorithmic Optimizations

- **Symmetry exploitation**: symmetric FIR coefficients allow N/2 multiplications instead of N
- **Polyphase decomposition**: reduce computation for sample rate conversion
- **FFT pruning**: skip computations for known-zero inputs or unused outputs
- **Cascaded integrator-comb (CIC)**: multiplier-free decimation/interpolation filter

### Hardware Optimizations

- **Coefficient quantization**: minimize coefficient word width while maintaining filter spec
- **Canonic signed digit (CSD)**: represent coefficients with minimum non-zero digits; replace multiplications with shifts and adds
- **Distributed arithmetic**: replace multiplications with lookup tables and accumulators
- **Resource sharing**: time-multiplex multipliers across filter taps when clock >> sample rate

### Power Optimizations

- **Clock gating**: gate DSP unit clock when no processing is active
- **Data-dependent gating**: skip multiplication when coefficient or data is zero
- **Memory optimization**: minimize memory accesses through data reuse and local buffering
- **Voltage scaling**: reduce voltage for DSP domain during low-throughput periods

DSP design bridges algorithm theory with hardware implementation. The key challenge is translating floating-point algorithms into efficient fixed-point hardware that meets precision requirements within area, power, and throughput constraints. A rigorous fixed-point analysis and bit-true verification methodology is essential for first-silicon success.
