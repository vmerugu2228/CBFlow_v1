# On-Chip Clocking (OCC) Methodology

## Purpose of On-Chip Clocking

On-chip clocking (OCC) controllers are essential DFT structures that enable at-speed testing of digital circuits. The fundamental challenge is that scan shift must occur at a relatively slow frequency (typically 10-200 MHz) to ensure reliable data transfer through long scan chains, while the capture cycle for transition fault testing must occur at the design's functional frequency (often 1-5 GHz in modern designs). The OCC bridges this gap by generating precisely controlled clock pulses that switch between slow shift clocks and fast capture clocks.

Without OCC, at-speed testing would require the ATE to generate and deliver high-frequency clock signals through the package, board, and socket -- a significant challenge at GHz frequencies where signal integrity degrades rapidly. OCC generates the at-speed pulses internally using the chip's own PLL or clock source, ensuring the capture timing matches actual operational conditions.

## OCC Architecture

A typical OCC controller contains several key components:

### Clock Source Selection

A multiplexer selects between:
- **PLL output clock**: The functional clock at target frequency, used for at-speed capture
- **External test clock (TCK or dedicated)**: A slower clock provided by the ATE for shift operations
- **Bypass clock**: An alternative clock path for cases where the PLL cannot lock during test

Selection is controlled by OCC mode registers, typically loaded via scan chains or JTAG.

### Pulse Generator

The pulse generator creates the specific clock sequences needed for different test modes:

**Shift pulse**: Derived from the slow external clock. Applied repeatedly during the scan shift phase. Simple gated version of the shift clock.

**At-speed pulse pair**: For transition testing, the pulse generator creates exactly two (LOC) or one (LOS) at-speed clock pulses derived from the PLL clock. Precise timing between these pulses determines the at-speed test window.

**Single capture pulse**: For stuck-at testing, a single capture pulse at any frequency. No at-speed requirement.

### Glitch-Free Multiplexing

Switching between clock sources must be glitch-free to prevent spurious clock edges that would corrupt scan data or cause false captures. The OCC uses synchronized handshake logic:

1. Current clock source is gated off (output held stable)
2. Multiplexer switches to the new source
3. New source is gated on only after synchronization

This sequence ensures no runt pulses or overlapping edges appear on the OCC output.

### Mode Controller

A small state machine (often loaded via scan) that sequences through test operations:
- Enter shift mode (slow clock, SE=1)
- Transition to capture mode (fast clock, SE=0)
- Generate launch/capture pulses
- Return to shift mode

## Launch-On-Shift (LOS)

In LOS mode, the last shift clock pulse serves as the launch event:

1. Shift data into scan chains at slow frequency with SE=1
2. On the last shift pulse, the scan chain settles to the shifted-in state
3. SE transitions from 1 to 0 (during the period between last shift and capture)
4. One at-speed capture pulse captures the transition response

**OCC requirements for LOS**:
- Generate slow shift clocks (from external source)
- Generate exactly one at-speed capture pulse (from PLL)
- Ensure SE transitions cleanly between the last shift and the capture
- SE timing is critical: it must deassert after the last shift clock and before the capture clock, with sufficient setup time on all scan flip-flops

**Timing considerations**:
- SE must meet timing to all flip-flops -- since SE has massive fanout, this can be challenging at high capture frequencies
- The transition being tested is from the shifted-in value to whatever the combinational logic produces -- this limits the initializations that can be created
- Inter-clock-domain paths cannot be tested in LOS if the launch value depends on a different clock domain

## Launch-On-Capture (LOC)

In LOC mode, an explicit launch capture pulse precedes the capture pulse:

1. Shift data into scan chains at slow frequency
2. SE deasserts
3. First at-speed clock pulse (launch): captures a functional response into flip-flops, establishing the launch state
4. Second at-speed clock pulse (capture): captures the transition response

**OCC requirements for LOC**:
- Generate slow shift clocks
- Generate exactly two consecutive at-speed clock pulses
- Maintain SE deasserted during both pulses
- The delay between the two at-speed pulses defines the test window and must match the functional clock period

**Advantages over LOS**:
- More flexible launch state initialization (the launch pulse propagates logic, creating realistic internal states)
- Higher transition fault coverage (typically 2-5% higher than LOS)
- Better correlation with actual functional timing
- Can test inter-clock-domain paths if both clocks are launched simultaneously

**Disadvantages**:
- More complex OCC design
- The launch state is not fully controllable (it is a function of the shifted-in state and one cycle of logic evaluation)
- Power during the two-pulse sequence can be higher than LOS

## PLL Bypass

During test, the PLL may not be able to lock to a stable reference due to:
- Test mode clock source changes
- ATE-supplied reference clock jitter
- Power supply noise during scan operations
- PLL not designed for the test frequency range

PLL bypass routes a test clock directly to the clock distribution network, bypassing the PLL. This is essential for stuck-at testing (no at-speed requirement) and for scan shift.

For at-speed transition testing, the PLL must be active and locked. The OCC manages the transition:
1. Use bypass clock for scan shift
2. Switch to PLL clock for at-speed capture
3. Switch back to bypass clock for next shift cycle

This transition must be glitch-free and properly synchronized.

## Clock Controller Design for Multiple Domains

Modern SoCs have dozens of clock domains. Each domain needs its own OCC instance or a shared OCC with domain-aware control.

### Per-Domain OCC

Each clock domain has a dedicated OCC instance:
- Independent control of each domain's test clock sequence
- Allows different domains to be tested at different frequencies
- Higher area overhead but simpler design

### Shared OCC with Domain Selection

A single OCC serves multiple domains through a clock distribution network:
- Mode registers select which domains receive at-speed pulses
- Untargeted domains receive no capture pulse (their flip-flops retain shift values)
- Lower area but more complex control logic

### Multi-Clock At-Speed Testing

Testing paths that cross clock domain boundaries requires both source and destination clocks to generate at-speed pulses simultaneously. The OCC must synchronize the launch/capture sequences across domains:

- Source domain OCC generates launch pulse
- Destination domain OCC generates capture pulse
- The relative timing between domains must match the functional specification (same-frequency, rational-ratio, or specified phase relationship)

## At-Speed Test Timing Constraints

OCC paths have specific timing requirements that must be closed during STA:

**Shift frequency constraints**: All scan paths (SI to SO through scan chains) must meet timing at the shift clock frequency. This is typically easy since shift is slow.

**SE timing constraints**: SE must meet setup and hold at every scan flip-flop relative to the capture clock. This is often the tightest constraint since SE transitions from 1 to 0 just before capture, and the capture is at functional speed.

**OCC internal timing**: The OCC's internal state machine, mux control, and pulse generation logic must meet timing. Critical paths include:
- Clock mux control signals (must be stable before clock edge)
- Pulse width control (at-speed pulses must have sufficient width)
- Mode register to OCC control paths

**SDC for test mode**: Dedicated SDC constraints define the shift frequency, capture frequency, and OCC control signal timing. These are typically in a separate test-mode SDC file or appended to the functional SDC with mode conditions.

Example test mode constraints:
```
create_clock -name shift_clk -period 20.0 [get_ports TCK]
create_clock -name capture_clk -period 1.0 [get_pins OCC/pll_clk]
set_multicycle_path -setup 2 -from [get_clocks shift_clk] -to [get_clocks capture_clk]
set_false_path -from [get_clocks capture_clk] -to [get_clocks shift_clk]
```

## OCC Debug and Silicon Bring-Up

OCC issues are among the most common DFT silicon failures:

**Clock not toggling**: PLL not locking, bypass path not working, OCC stuck in wrong mode. Debug by observing OCC output with on-chip oscilloscope or frequency divider.

**Glitches on clock switch**: Insufficient synchronization during clock source switching. Can cause random scan failures that are difficult to reproduce.

**SE timing failure**: SE arrives too late for the capture clock, causing some flip-flops to capture functional data (SE=0) while others still see SE=1. Results in scan chain mismatches that vary with pattern.

**At-speed pulse count wrong**: Generating more or fewer at-speed pulses than intended. One extra pulse during transition testing corrupts the expected response.

## Best Practices

- Design OCC as a parameterized, reusable IP block with configurable features
- Verify OCC behavior with gate-level simulation in all test modes before tape-out
- Include OCC diagnostics (pulse count, clock frequency measurement) accessible via JTAG
- Allow OCC mode configuration via both scan and JTAG for flexibility during bring-up
- Allocate sufficient buffering for SE signal -- this is consistently the most timing-critical test mode signal
- Validate PLL lock time under test conditions at all PVT corners
