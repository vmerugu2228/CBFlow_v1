# Test Compression: Reducing Test Data and Test Time

## The Test Data Volume Problem

Modern SoCs contain millions to billions of flip-flops organized into scan chains. Without compression, each test pattern must shift in a value for every flip-flop and shift out a response from every flip-flop. For a design with 10 million scan flip-flops and 50,000 test patterns, the raw test data volume would be 500 billion bits -- roughly 60 gigabytes. ATE memory is typically limited to 256 MB to a few gigabytes, and test time at $2-5 per second on ATE makes uncompressed testing economically impossible for modern designs.

Test compression solves this by exploiting the inherent don't-care (X) density in ATPG patterns. A typical pattern specifies values for only 1-5% of scan flip-flops; the remaining 95-99% are don't-cares that the ATPG tool can set to any value. Compression architectures encode only the specified (care) bits and expand them on-chip, achieving compression ratios of 50x to 200x or more.

## Compression Architecture Overview

A compression architecture consists of two main components:

**Decompressor (Input Side)**: Located between the scan input pins and the internal scan chains. It takes a small number of external input channels and expands them to drive a large number of internal scan chains. The decompressor ensures that the specified care bits are correctly delivered to their target flip-flops while filling don't-care positions with deterministic but pseudo-random values.

**Compressor (Output Side)**: Located between the internal scan chain outputs and the scan output pins. It reduces the large number of chain outputs to a small number of external output channels. The compressor must preserve the ability to observe faults -- if a fault effect appears on any internal chain, it must propagate to the compressed outputs.

The **compression ratio** is defined as (internal chain count) / (external channel count), or equivalently, the factor by which test data volume is reduced compared to uncompressed testing.

## Embedded Deterministic Test (EDT) -- Siemens Tessent

EDT is Siemens (formerly Mentor Graphics) Tessent's compression architecture and is one of the most widely deployed in the industry.

**Decompressor**: Based on a linear feedback shift register (LFSR) or ring generator that produces pseudo-random sequences. The external channels provide seed data that initializes the LFSR, which then generates a sequence that fills the internal scan chains. Care bit positions are satisfied by solving a system of linear equations over GF(2) to find the right seed.

**Compressor**: Uses an XOR network (spatial compactor) that combines internal chain outputs into fewer output channels. The XOR tree is designed to minimize the probability of aliasing (two different responses producing the same compressed output). Chain masking can be used to block chains with unknown (X) values from corrupting the compressor.

**Key Features**:
- Compression ratios of 100-300x are common
- Low area overhead (typically <1% of design area)
- Chain masking handles X-tolerance
- Supports low-pin-count testing for high channel efficiency
- Pipeline decompressor for higher shift frequencies

## DFTMAX -- Synopsys

DFTMAX is Synopsys's compression technology, available in several variants.

**DFTMAX (Adaptive Scan)**: Uses a codec-based architecture where a compressor/decompressor pair is inserted around the scan chains. The design uses internal scan chains that are reconfigured using a proprietary adaptive scan approach.

**DFTMAX Ultra**: An advanced version that achieves higher compression ratios by using a different encoding scheme. It supports both internal and external compression modes, allowing flexibility in test strategy.

**Key architectural features**:
- Codec-based compression with XOR network decompressor
- Spatial compactor on the output side
- Support for pipeline compression to enable higher shift frequencies
- Integrated with Synopsys DFT Compiler and TetraMAX ATPG
- Compression ratios of 50-200x typical

**Pipeline Scan**: A variant that adds pipeline stages within the scan chain to allow higher shift clock frequencies. This reduces shift time further since more data can be shifted per unit time.

## Cadence Modus Compression

Cadence's Modus Test solution provides integrated compression within its DFT synthesis and ATPG flow.

**Architecture**: Uses an XOR-based decompressor feeding internal scan chains and a space compactor on the output side. The architecture is designed for tight integration with the Modus ATPG engine.

**Key features**:
- Integrated compression-aware ATPG
- Efficient handling of X-sources through masking
- Support for hierarchical compression
- Compatible with multiple scan architectures

## Channel Count and Pin Planning

**External Channels**: The number of scan input and scan output pins allocated to compression. More channels mean higher compression ratios for the same number of internal chains. Typical designs allocate 8-64 input channels and 8-64 output channels.

**Internal Chains**: The number of scan chains inside the compression domain. Can be 100-10,000+ depending on design size and target compression ratio. More internal chains = shorter chains = fewer shift cycles = less test time.

**Asymmetric Channels**: Input and output channel counts need not be equal. Some architectures benefit from more output channels (better observability) or more input channels (better controllability).

**Pin Allocation Trade-offs**: Every pin allocated to scan is a pin not available for functional I/O or power/ground. The DFT architect must balance test quality against pin budget. Shared (multiplexed) pins are common -- functional pins are reused as scan channels in test mode.

## X-Handling in Compression

Unknown values (X's) are the primary challenge in compression. Sources of X's include:
- Uninitialized memories read during scan capture
- Multi-driven buses in test mode
- Analog blocks with undefined digital outputs
- Asynchronous clock domain crossings

X's corrupt the compressor because an unknown value XORed with anything produces an unknown. Solutions include:

**X-Masking**: Selectively mask (block) scan chain outputs that contain X-values from reaching the compressor. The masked chains are not observed for that pattern, potentially reducing coverage. Masking control can be per-chain or per-chain-group.

**X-Bounding**: Insert logic that forces X-sources to known values during test mode. Requires careful design to ensure the bounding logic doesn't affect functional behavior.

**X-Tolerance**: Some compression architectures are inherently more tolerant of X's. Increasing the number of output channels provides redundant observation paths that can tolerate some X corruption.

**X-Press**: Tessent's technology for handling X's by selectively activating subsets of chains and performing multiple observations to reconstruct the full response despite X contamination.

## Compression Design Flow

1. **Plan compression architecture**: Determine channel count, compression ratio target, and pin allocation
2. **Insert compression logic**: During DFT synthesis, insert decompressor and compressor
3. **Verify compression DRC**: Check for structural issues (X-sources, clock domain mixing, chain length balance)
4. **Run compression-aware ATPG**: Generate patterns in the compressed domain
5. **Analyze compression efficiency**: Verify actual compression ratio meets targets, check for coverage loss due to X-masking
6. **Timing closure**: Ensure shift paths through decompressor/compressor meet timing at shift frequency
7. **Pattern export**: Generate patterns in compressed format for ATE

## Advanced Compression Topics

**Hierarchical Compression**: For large SoCs, compression can be applied at the block level (each block has its own codec) or at the top level (a single codec spans all blocks), or in a hybrid approach. Block-level compression enables parallel block testing and design reuse.

**Multi-Mode Compression**: Different compression configurations for different test modes (e.g., high compression for production test, lower compression for debug/diagnosis).

**2D Compression**: Exploits both spatial (across chains) and temporal (across shift cycles) don't-care patterns for even higher compression ratios.

**Streaming Compression**: Eliminates the need to store all patterns in ATE memory by streaming pattern data from the ATE controller, enabling effectively unlimited pattern counts.

## Compression Metrics

| Metric | Typical Range | Description |
|--------|---------------|-------------|
| Compression Ratio | 50x - 300x | Internal chains / external channels |
| Area Overhead | 0.5% - 2% | Silicon area for compression logic |
| Coverage Impact | <0.5% loss | Coverage reduction due to X-masking |
| X-tolerance | 1% - 5% X-density | Maximum X-density compressor can handle |
| Shift Frequency | 100 - 500 MHz | Clock frequency during scan shift |

## Production Considerations

In production, compression is essential for managing test costs. Key considerations include:
- ATE compatibility: Ensure the compression format is supported by the target ATE platform
- Pattern debugging: Compressed patterns are harder to debug; tools provide decompressed views
- Diagnosis: Fault diagnosis with compressed patterns requires decompression-aware diagnostic tools
- Yield learning: Compression should not obscure defect signatures needed for yield analysis
- Multi-site testing: Compression reduces per-site test time, enabling more parallel testing on multi-site ATE configurations
