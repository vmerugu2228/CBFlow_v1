# DFT for Low-Power Designs: Multi-Voltage and Power Domain Testing

## Low-Power Design and DFT Intersection

Modern SoCs employ aggressive low-power design techniques: multiple voltage domains, power gating (shutoff), voltage scaling (DVFS), retention registers, and level shifters. These techniques dramatically reduce functional power consumption but introduce significant DFT challenges. Every power management feature must be testable, and the test infrastructure itself must operate correctly across all power states.

This guide addresses DFT strategies for designs using UPF/CPF-based low-power architectures -- a distinct topic from managing power consumption during test (covered in low_power_test.md). Here, the focus is on ensuring that low-power structures are correctly tested and that DFT operates properly in a multi-voltage environment.

## Power Domain Challenges for DFT

### Power Gating and Scan

Power-gated domains are shut off during certain operating modes, with their power supply cut by header/footer switches. During test:

- A powered-off domain has no supply -- its scan flip-flops are dead
- Scan chains that pass through a powered-off domain will break (no shift capability)
- Powered-off flip-flops produce X-values that can corrupt compressor outputs

**Solution**: During scan testing, all power domains must be powered on. The DFT test modes must ensure all power switches are fully on before scan operations begin. This is typically achieved by:
1. JTAG or scan-loadable control registers that force all power switches ON
2. Dedicated test mode pins that override power management
3. Power sequencing logic that recognizes test mode and enables all supplies

### Isolation Cells

Isolation cells clamp outputs of a powered-off domain to safe values (0 or 1) to prevent floating inputs to always-on logic. During test:

- Isolation must be disabled when testing the power-gated domain (the domain is powered on for test, so isolation would mask the test response)
- Isolation must be enabled when testing the always-on domain with the gated domain powered off (to prevent X-propagation)
- The isolation cells themselves must be tested for correct functionality

**DFT strategy**: Control isolation enable signals from scan chains or JTAG. Include isolation cells in the scan test by creating patterns that verify both the clamped and unclamped states.

### Level Shifters

Level shifters translate signals between domains at different voltages. During test:

- All domains are typically at the same test voltage (often nominal), so level shifters pass through transparently
- The level shifters themselves must be tested -- but at uniform voltage, their voltage-shifting function is not exercised
- Full level shifter testing requires multi-voltage test sequences or dedicated BIST

**DFT approach**: Test level shifter logic function at uniform voltage (verifies the digital logic path). Optionally, use multi-voltage test modes on ATE that apply different voltages to different domains simultaneously to verify actual voltage translation.

### Retention Registers

Retention flip-flops save their state when the domain is powered off and restore it on power-up. Testing retention requires:

1. Load known values into retention flip-flops (via scan)
2. Power off the domain (trigger save operation)
3. Wait for the specified retention period
4. Power on the domain (trigger restore operation)
5. Read back values via scan and compare with expected

This sequence is fundamentally different from normal scan testing and requires dedicated test modes:
- JTAG-controlled power sequencing
- Programmable wait timer for retention period
- Ability to scan-in, power-off, power-on, scan-out without losing chain integrity

### Always-On Logic

Always-on domains (AON) remain powered in all modes. DFT for AON:
- AON scan chains operate normally in all power states
- AON logic can serve as a test controller backbone
- JTAG TAP controller and test mode control are typically in the AON domain
- OCC should be in AON to maintain clock control during power transitions

## Multi-Voltage Test Modes

Comprehensive testing of a multi-voltage design requires several test modes:

### All-On Test Mode

All power domains powered on at nominal voltage. Standard scan test:
- Full scan chain operation across all domains
- Maximum fault coverage for all logic
- Does not exercise power management features
- This is the primary production test mode

### Power Domain Isolation Test

Individual domains powered off while others are tested:
- Verifies isolation cell function (correct clamp values)
- Tests always-on logic without interference from gated domains
- Requires domain-specific scan chains that do not cross powered-off boundaries
- Multiple iterations may be needed (one per power configuration)

### Retention Test Mode

Specifically tests retention register save/restore:
- Sequence: scan-in -> save -> power-off -> delay -> power-on -> restore -> scan-out
- Verify all retention bits are correctly preserved
- Test at various temperatures and voltages for margin
- Can be combined with MBIST if retention memories exist

### Multi-Voltage Test Mode (Advanced)

Apply different voltages to different domains simultaneously:
- Requires ATE with multiple programmable supply channels
- Tests level shifter voltage translation function
- Tests design operation at actual voltage combinations
- Most expensive test mode (complex ATE setup, longer test time)

## Scan Chain Architecture for Low-Power Designs

### Domain-Contained Scan Chains

Each scan chain should be entirely within a single power domain:
- If a domain is powered off, only its chains are affected
- No chain breaks due to powered-off segments
- Simplifies power-sequenced test modes

### Cross-Domain Chain Handling

If chains must cross domain boundaries (e.g., for chain count optimization):
- Insert level shifters at domain boundaries within the chain
- Add isolation/bypass logic for powered-off segments
- Use lockup latches at domain boundaries for timing
- Consider the increased complexity and whether it is justified

### Retention Register Chain Placement

Retention flip-flops should be grouped together in dedicated scan chains or chain segments:
- Enables selective scan of retention registers during retention test
- Simplifies the save/restore test sequence
- Allows non-retention registers to be excluded from retention test (reducing test time)

## UPF/CPF Considerations for DFT

The power intent specification (UPF or CPF) must include DFT-aware definitions:

### UPF for Test Mode

```
# Define test power state where all domains are ON
add_power_state TOP/PD_ALL_ON -state ALL_ON_TEST {
  -supply_expr {power == FULL_ON && ground == FULL_ON}
}

# Create test mode strategy
set_isolation_strategy iso_test -domain PD_GATED \
  -isolation_power_net VDD_AON \
  -isolation_signal test_iso_en \
  -clamp_value 0 \
  -applies_to outputs
```

### DFT Tool UPF/CPF Integration

Modern DFT tools (Tessent, DFT Compiler, Modus) read UPF/CPF to:
- Understand power domain boundaries
- Automatically insert isolation control for test modes
- Route scan chains within power domains
- Generate power-aware test modes and sequences
- Flag violations where DFT structures cross power domains without proper level shifting or isolation

## DFT for Power Switches

Power switches (header/footer transistors) must themselves be tested:

### Switch Resistance Test
- Enable all switches
- Measure supply current or voltage drop to verify switch resistance
- Compare against expected values (failing switches show higher resistance)

### Switch Leakage Test
- Disable all switches (domain powered off)
- Measure leakage current through the switches
- Excessive leakage indicates switch defects

### Switch Control Test
- Verify that each switch control signal correctly turns the switch on/off
- Can be done via scan-controlled switch enables with IDDQ measurement

## Power-Aware DFT Verification

Verification must ensure DFT operates correctly across all power states:

### Structural Verification
- Scan chains do not cross un-powered domain boundaries during any test mode
- Level shifters exist on all scan signals crossing voltage domains
- Isolation is properly controlled during each test mode
- Retention scan sequences are structurally correct

### Functional Verification
- Simulate the complete test mode entry/exit sequence with power states
- Verify correct power sequencing during retention test
- Validate that all power management overrides work in test mode
- Check for X-propagation from powered-off domains

### Timing Verification
- STA for each test mode with correct voltage assignments
- Level shifter delays included in scan shift timing
- Retention save/restore timing meets specifications
- Power switch turn-on time included in test mode entry timing

## Industry Standards and Requirements

**ISO 26262 (Automotive)**: Requires testing of all safety-relevant power management features. Retention test, isolation test, and power domain fault detection are mandatory for ASIL-C and ASIL-D compliance.

**IEEE 1801 (UPF)**: Standardizes power intent specification. DFT tools that support UPF can automatically generate power-aware test structures.

**Common Platform (multi-foundry)**: Foundry-specific power management IP (switch cells, retention cells, isolation cells) must have tested, characterized DFT-compatible variants.

## Practical Guidelines

1. Define test power modes early in the architecture phase -- retrofitting is extremely costly
2. Keep scan chains within single power domains whenever possible
3. Place DFT control infrastructure (OCC, compression, JTAG) in always-on domains
4. Verify power-aware DFT with gate-level simulation including power state modeling
5. Plan ATE power supply channel allocation early -- multi-voltage test needs dedicated supply pins
6. Document all test modes, power sequences, and domain configurations in the test plan
7. Test retention at worst-case conditions (high temperature, low voltage) for reliability confidence
