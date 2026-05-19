# Scan Design: Scan Insertion and Chain Architecture

## Scan Insertion Fundamentals

Scan design is the cornerstone of structural testing in digital ICs. The core concept is straightforward: replace standard flip-flops with scan flip-flops that have a multiplexed input, then chain these scan flip-flops together into shift registers called scan chains. In normal (functional) mode, the scan flip-flop behaves identically to the original. In test (scan) mode, data shifts serially through the chain, allowing direct control and observation of every registered node in the design.

This transformation converts the sequential test problem (which is exponentially hard) into a combinational one (which is tractable). Once all flip-flop states can be directly loaded and observed via scan, ATPG only needs to solve combinational Boolean satisfiability for the logic between register stages.

## Scan Flip-Flop Architecture

A scan flip-flop adds a 2:1 multiplexer at the D-input of a standard flip-flop. The two inputs are:

- **D (functional data)**: The normal data path, active when scan_enable = 0
- **SI (scan input)**: Serial data from the previous flip-flop in the scan chain, active when scan_enable = 1

The **SE (scan enable)** signal controls the multiplexer. The **Q output** serves both as functional output and as the scan output (SO) feeding the next flip-flop in the chain.

Most standard cell libraries provide dedicated scan flip-flop cells (SDFF) that integrate the mux into the flip-flop cell, offering better area and timing than a discrete mux plus flip-flop. Libraries typically include variants: scan D flip-flop, scan D flip-flop with reset, scan D flip-flop with enable, and combined reset+enable variants.

## Scan Chain Architecture

A scan chain is a serial shift register formed by connecting the SO of one scan flip-flop to the SI of the next. The chain has:

- **Scan-In (SI) pin**: Primary input that feeds data into the first flip-flop of the chain
- **Scan-Out (SO) pin**: Primary output that captures data from the last flip-flop

During a **shift operation**, scan_enable is asserted and the clock toggles repeatedly, shifting data through the entire chain. The number of clock cycles needed equals the chain length (number of flip-flops). During a **capture operation**, scan_enable is deasserted and one or two clock pulses apply a test vector and capture the circuit response into the scan flip-flops.

A typical test pattern application sequence is:
1. **Shift in**: Assert SE, apply shift clocks to load the test vector into all scan chains simultaneously
2. **Launch**: Deassert SE, apply one functional clock pulse (for stuck-at) or two pulses (for transition faults)
3. **Capture**: The circuit response is captured into scan flip-flops on the clock edge
4. **Shift out**: Assert SE, shift out captured responses while simultaneously shifting in the next test vector

## Scan Chain Design Considerations

**Chain Count**: The number of scan chains is typically limited by available scan I/O pins (or compression channel count). More chains mean shorter chains, which means fewer shift cycles per pattern and reduced test time. With compression, the internal chain count can be 100-1000x the physical scan pin count.

**Chain Length**: All chains should be balanced to within +/-1 flip-flop. The longest chain determines shift cycle count, so unbalanced chains waste test time. Synthesis tools automatically balance chains, but manual intervention may be needed for hierarchical designs.

**Chain Ordering**: Initially, scan chains are stitched in an arbitrary (often alphabetical or synthesis) order. During physical design, chains are reordered based on physical proximity to minimize scan routing wirelength and congestion. This is critical for timing and routability -- a chain that zigzags across the die creates long routes and potential timing violations.

**Clock Domain Handling**: Flip-flops from different clock domains should generally be on separate scan chains, or at minimum, same-domain flip-flops should be grouped within chains. Mixing clock domains in a single chain requires careful handling to avoid shift failures when clocks have different frequencies or phases.

## Scan Enable Signal

The scan_enable (SE) signal is one of the most critical signals in test mode:

- It must reach every scan flip-flop in the design with minimal skew
- It must meet timing at the scan shift frequency (SE must be stable before the shift clock edge)
- It has extremely high fanout (every scan flip-flop), requiring significant buffering
- Late SE arrival causes functional data to be captured instead of scan data, corrupting the chain

Best practices for SE:
- Treat SE as a high-fanout net requiring dedicated buffering
- SE transitions must settle within one shift clock period
- Use dedicated scan_enable ports rather than reusing functional pins when possible
- Buffer SE hierarchically to manage skew across the design

## Scan Modes

Designs typically support multiple test modes:

**Shift Mode**: SE=1, data shifts through chains. Clock frequency is typically 10-100 MHz (much slower than functional to ensure reliable shifting).

**Stuck-At Capture**: After shifting, SE=0, one capture clock pulse. No at-speed requirement -- the capture can happen at shift frequency. Tests combinational stuck-at faults.

**At-Speed Capture (Transition)**: After shifting, SE=0, two clock pulses at functional speed. The first pulse launches a transition; the second captures the response. Tests timing-related defects. Requires on-chip clock controller (OCC) to generate precisely timed at-speed pulses.

**BIST Mode**: Internal pattern generators and response analyzers are activated. Scan chains may be repurposed as PRPG/MISR elements.

## Scan Compression

Without compression, a design with 1 million flip-flops and 32 scan chains would have chains of ~31,250 flip-flops each, requiring 31,250 shift cycles per pattern. At 100 MHz shift clock, that is 312 microseconds per pattern. With 10,000 patterns, total shift time alone would be over 3 seconds -- extremely expensive on ATE.

Compression addresses this by inserting a **decompressor** between the scan input pins and the internal scan chains, and a **compressor** between the internal scan chains and the scan output pins. A small number of external channels (e.g., 16 inputs, 16 outputs) drive a large number of internal chains (e.g., 1,000+).

The decompressor expands the input stimulus using polynomial-based logic (like an LFSR) or XOR networks. The compressor combines the chain outputs into fewer output channels using XOR trees or similar structures. Compression ratios of 50-200x are common, reducing test time proportionally.

Major compression architectures include:
- **Synopsys DFTMAX**: Adaptive scan with codec-based compression
- **Siemens EDT (Embedded Deterministic Test)**: LFSR-based decompression with dedicated compressor
- **Cadence Modus compression**: Integrated compression in the Modus flow

## Scan Replacement Rules and Exceptions

Not all sequential elements can or should be scanned:

**Must scan**: All standard flip-flops in the functional logic, register files implemented with flip-flops, pipeline registers.

**Cannot scan**: Memory arrays (use MBIST instead), analog registers, certain multi-cycle path registers where scan insertion would break functionality, and flip-flops in clock generation logic (PLLs, clock dividers) unless carefully handled.

**Scan exclusions**: Designers may exclude specific flip-flops from scan chains using dont_scan attributes. Common exclusions include: flip-flops in asynchronous clock domain crossers (though this is debatable), registers controlling test infrastructure itself, and security-sensitive registers that should not be observable.

## DFT DRC for Scan

After scan insertion, DFT design rule checks verify the scan structure is correct:

- All scannable flip-flops are included in scan chains
- No combinational feedback loops exist in scan mode
- Scan chains are properly connected (SI to SO without breaks)
- Clock domains are handled correctly
- Asynchronous set/reset pins are properly controlled during scan
- No bus contention exists in scan mode
- Scan enable meets timing requirements

Violations must be resolved before proceeding to ATPG, as they will cause either incorrect pattern generation or silicon test failures.

## Hierarchical Scan

For large SoCs, scan insertion is often done hierarchically:

1. Each block/subsystem has its own scan chains with local SI/SO ports
2. At the top level, block-level chains are either concatenated into longer chip-level chains or connected through a test access mechanism (TAM)
3. Compression may be applied at the block level, the top level, or both

Hierarchical scan enables parallel development, block-level ATPG (faster runtime), and design reuse, but requires careful planning of the test access architecture to ensure all blocks are testable at the chip level.

## Practical Scan Design Tips

- Always verify scan chain integrity with a simple flush test (shift a known pattern through all chains and verify it emerges correctly) before running ATPG patterns
- Monitor scan chain routing congestion during physical design and reorder chains if needed
- Keep scan chain length reasonable (2,000-10,000 flip-flops per compressed internal chain is typical)
- Ensure adequate timing margin on scan shift paths -- shift failures are the most common DFT silicon issue
- Plan scan I/O pin locations early in floorplanning to minimize scan routing overhead
