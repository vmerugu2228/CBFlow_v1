# Built-In Self-Test (BIST) Architecture

## BIST Concept and Motivation

Built-In Self-Test (BIST) embeds test generation and response analysis hardware directly on the chip, enabling the device to test itself with minimal external equipment. Unlike scan-based testing which relies on expensive ATE to supply patterns and analyze responses, BIST requires only a start signal and a pass/fail check of the final signature.

BIST is motivated by several factors: (1) reduced ATE test time since patterns are generated on-chip at-speed, (2) field testing capability where ATE is unavailable, (3) at-speed testing that matches functional operating conditions, (4) reduced test data volume since patterns need not be stored externally, and (5) the ability to test structures that are difficult to access externally (deeply embedded memories, analog blocks).

The two major categories are **Logic BIST (LBIST)** for testing random logic and **Memory BIST (MBIST)** for testing embedded SRAM, ROM, and register files.

## Logic BIST (LBIST) Architecture

An LBIST system consists of three core components:

### Pseudo-Random Pattern Generator (PRPG)

The PRPG generates test stimuli by producing pseudo-random binary sequences. The most common implementation is a **Linear Feedback Shift Register (LFSR)** -- a shift register with XOR feedback taps defined by a characteristic polynomial.

An n-bit LFSR with a primitive polynomial generates a maximal-length sequence of 2^n - 1 unique states before repeating. For LBIST, the LFSR output bits are fed into the scan chain inputs, filling the chains with pseudo-random values each shift cycle.

LFSR design considerations:
- **Polynomial selection**: Use primitive polynomials for maximal-length sequences. Common choices are trinomials or pentanomials for hardware efficiency.
- **Bit width**: Typically matches the number of scan chains or scan input channels. 32-bit to 64-bit LFSRs are common.
- **Seeding**: The initial LFSR state (seed) can be fixed or programmable. Multiple seeds may be used in sequence to improve coverage.
- **Phase shifters**: XOR networks that create additional pseudo-random sequences from the LFSR, providing more unique patterns to different scan chains.

### Multiple-Input Signature Register (MISR)

The MISR compresses the scan chain outputs into a compact signature. It is essentially an LFSR with multiple parallel inputs -- each scan chain output is XORed into the MISR at a different stage.

After all patterns are applied, the MISR contains a final signature that is a function of all captured responses. This signature is compared against a known-good (golden) signature. A mismatch indicates a fault was detected.

MISR design considerations:
- **Signature length**: Typically 32-64 bits. Longer signatures reduce aliasing probability (probability that a faulty response produces the correct signature). For an n-bit MISR, aliasing probability is approximately 2^(-n).
- **X-contamination**: A single X value entering the MISR corrupts the entire signature from that point forward. This is the most critical challenge in LBIST. X-sources must be masked or bounded.
- **Multiple signatures**: Some implementations capture intermediate signatures at intervals to improve diagnostic resolution.

### BIST Controller

The BIST controller is a state machine that orchestrates the test:
1. Initialize PRPG with seed
2. For each pattern: shift PRPG values into scan chains, apply capture pulse(s), shift responses into MISR
3. After all patterns: compare MISR signature with expected value
4. Report pass/fail

The controller manages the scan enable signal, clock generation, pattern count, and interface to the JTAG/test access infrastructure.

## LBIST Coverage Challenges

Pseudo-random patterns inherently achieve lower fault coverage than deterministic ATPG because certain fault sites are **random-pattern resistant (RPR)**. RPR faults occur at nodes requiring specific, low-probability input combinations -- for example, an AND gate with 20 inputs requires all inputs at 1 to propagate a SA0 fault on any input, a probability of 2^(-20).

Techniques to improve LBIST coverage:

**Test Points**: Insert control points (AND/OR gates that force a node to 0/1 during BIST) and observation points (flip-flops that sample hard-to-observe nodes and feed them to the MISR). Test point insertion can increase coverage from ~60-70% to 90-95% but adds area and may impact timing.

**Weighted Random Patterns**: Bias the PRPG output so certain scan cells receive 0 or 1 with non-50% probability. Weight sets are stored on-chip or programmed via JTAG. This targets specific RPR faults.

**Hybrid BIST**: Combine LBIST with a deterministic BIST approach. The PRPG generates random patterns for easy faults, then a small deterministic pattern set (stored in on-chip ROM or computed from seeds) targets remaining hard faults.

**Top-Off Patterns**: After LBIST runs, a small set of deterministic scan patterns are applied externally to cover faults missed by LBIST. This hybrid approach achieves near-ATPG coverage levels.

## At-Speed BIST

LBIST is naturally suited for at-speed testing because the PRPG and MISR operate at the chip's internal clock frequency. For transition fault testing, the BIST controller generates launch-capture sequences at functional speed.

At-speed BIST advantages:
- Tests the design at actual operating conditions (voltage, temperature, frequency)
- No ATE speed limitations (ATE may not support the chip's full frequency)
- Enables speed binning -- determining the maximum operating frequency of each die
- In-system testing at power-on for reliability screening

## BIST for Field Testing

BIST enables ongoing self-test throughout the product lifetime:
- **Power-on self-test (POST)**: Run BIST at each power cycle to detect infant mortality and degradation
- **Concurrent BIST**: Run BIST during idle periods without disrupting normal operation
- **Safety-critical applications**: Automotive ISO 26262 and avionics require periodic self-test. BIST satisfies latent fault detection requirements for ASIL-B through ASIL-D levels.

## PRPG and MISR Implementation Details

### LFSR Polynomials

A standard LFSR uses the polynomial: x^n + x^k + ... + 1, where the exponents define the XOR feedback tap positions.

Example primitive polynomials:
- 16-bit: x^16 + x^14 + x^13 + x^11 + 1
- 32-bit: x^32 + x^22 + x^2 + x + 1

The LFSR can be implemented in **Fibonacci** (external XOR) or **Galois** (internal XOR) form. Galois form is preferred for high-speed operation since the XOR is in the feedback path between adjacent stages rather than in a long chain.

### Phase Shifters

When the number of scan chains exceeds the LFSR width, phase shifters generate additional independent sequences. A phase shifter is an XOR network that computes linear combinations of LFSR state bits, producing sequences that are time-shifted versions of the original. The shift amount is chosen to ensure low correlation between chains.

### Signature Analysis Mathematics

The MISR computes a polynomial division of the input sequence by its characteristic polynomial. The final remainder (signature) uniquely characterizes the input sequence with high probability. For an n-bit MISR:
- Good signature: Unique value computed from fault-free responses
- Aliasing probability: ~2^(-n) for random error patterns
- 32-bit MISR: aliasing probability ~2.3 x 10^(-10)

## BIST Area and Performance Overhead

| Component | Typical Area | Timing Impact |
|-----------|-------------|---------------|
| PRPG (32-bit LFSR) | ~200 gates | Minimal |
| Phase shifter | ~500-2000 gates | Minimal |
| MISR (32-bit) | ~300 gates | Minimal |
| BIST controller | ~1000-3000 gates | Minimal |
| Test points | 1-5% of design | May impact critical paths |
| Total BIST overhead | 1-5% of design area | <5% performance impact |

## BIST Integration Considerations

- **Clock control**: BIST needs clean clock generation without glitches. PLL bypass may be needed if the PLL cannot be used during BIST.
- **Power management**: BIST patterns have higher switching activity than functional operation (~50% toggle rate vs. 10-20%). Power management may be needed to avoid exceeding thermal limits.
- **Multiple clock domains**: Each clock domain typically needs its own PRPG/MISR pair or a shared controller with domain-aware sequencing.
- **Diagnosis**: BIST provides only pass/fail initially. For diagnosis, the MISR signature can be read out at intermediate points, or a scan-based diagnosis mode can dump internal state for analysis.
- **BIST scheduling**: In SoCs with multiple BIST engines (LBIST + multiple MBIST), scheduling concurrent BIST execution minimizes total test time while managing power constraints.
