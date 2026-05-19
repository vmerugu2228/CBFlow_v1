# Security Verification

## Overview

Security verification ensures that a digital design protects sensitive data and operations from unauthorized access, information leakage, and malicious attacks. As connected devices proliferate (IoT, automotive, mobile, cloud), hardware security has become a first-class design requirement. Security bugs in silicon are particularly dangerous because they cannot be patched like software — a hardware vulnerability in a shipped chip persists for the product's entire lifetime. Security verification encompasses side-channel analysis, fault injection testing, secure boot verification, key management validation, and information flow analysis.

## Threat Model

### Hardware Security Threats

1. **Side-channel attacks**: Extracting secret information by observing physical characteristics (power consumption, electromagnetic emissions, timing variations).
2. **Fault injection attacks**: Inducing errors (voltage glitching, clock glitching, laser fault injection) to bypass security checks or leak information.
3. **Physical attacks**: Probing, reverse engineering, or modifying the chip physically.
4. **Software attacks exploiting hardware**: Using software to exploit hardware vulnerabilities (Spectre, Meltdown, Rowhammer).
5. **Debug interface attacks**: Exploiting JTAG, debug ports, or test modes to access protected resources.
6. **Supply chain attacks**: Tampering during manufacturing (hardware Trojans).

### Security Requirements

A typical security specification includes:
- Confidentiality: Secret keys and sensitive data must not leak to untrusted observers.
- Integrity: Critical data and code must not be modified by unauthorized entities.
- Authentication: The system must verify the identity of code and commands before execution.
- Availability: Security mechanisms must not create denial-of-service vulnerabilities.
- Isolation: Security domains must be properly isolated from non-secure domains.

## Side-Channel Analysis

### Power Side-Channel

The power consumed by a digital circuit varies depending on the data being processed. An attacker can use statistical analysis of power traces to extract secret keys from cryptographic implementations.

**Verification approach:**

1. **Hamming weight/distance analysis**: Verify that the power consumption (modeled as switching activity) does not correlate with secret data values.
2. **Differential Power Analysis (DPA) resistance**: Simulate the design with known keys and verify that countermeasures (masking, hiding) prevent key extraction.
3. **Toggle count analysis**: Count signal transitions on internal wires during cryptographic operations and verify that toggle counts are data-independent.

```systemverilog
// Monitor switching activity on sensitive signals
always @(posedge clk) begin
  if (crypto_active) begin
    toggle_count = $countones(key_xor_data ^ $past(key_xor_data));
    // Assert that toggle count is data-independent (masked implementation)
    // This is a simplified check; real DPA analysis requires statistical methods
  end
end
```

### Timing Side-Channel

If the execution time of a cryptographic operation depends on the secret key or data, an attacker can infer secrets by measuring timing.

**Verification approach:**
- Assert that all cryptographic operations complete in constant time regardless of input data.
- Verify that branch conditions in security-critical paths do not depend on secret data.

```systemverilog
// Assert constant-time execution
property p_constant_time_crypto;
  @(posedge clk)
  $rose(crypto_start) |-> ##FIXED_LATENCY crypto_done;
endproperty

AST_CONSTANT_TIME: assert property (p_constant_time_crypto)
  else $error("Crypto operation completed in variable time — timing side channel");
```

### Electromagnetic Side-Channel

Similar to power analysis but based on EM emissions. Verification at the RTL level focuses on the same countermeasures (masking, constant-time execution) since EM emissions correlate with switching activity.

## Fault Injection Verification

### Types of Fault Injection

- **Single-bit flip**: One register bit is flipped.
- **Multi-bit flip**: Multiple bits flip simultaneously.
- **Instruction skip**: A control signal is held for one cycle, causing an operation to be skipped.
- **Clock glitch**: An extra clock edge causes double-clocking or setup violations.
- **Voltage glitch**: Supply voltage drops, causing logic errors.

### Fault Injection Simulation

```systemverilog
// Inject a single-bit fault into a register
task inject_fault(string register_path, int bit_position);
  force `DUT_PATH.register_path[bit_position] =
    ~`DUT_PATH.register_path[bit_position];
  @(posedge clk);
  release `DUT_PATH.register_path[bit_position];
endtask
```

### Security Response Verification

After fault injection, verify that the design detects and responds appropriately:

1. **Detection**: Error detection mechanisms (parity, ECC, redundancy checks) trigger.
2. **Response**: The design takes protective action (halt, reset, zeroize secrets, alert).
3. **No bypass**: The fault does not bypass security checks (authentication, access control).

```systemverilog
// Inject fault during authentication and verify no bypass
task test_auth_bypass();
  // Start authentication
  start_authentication(valid_credentials);

  // Inject fault into the comparison logic
  inject_fault("u_auth.compare_result", 0);

  // Verify authentication fails (fault detected, not bypassed)
  assert (!auth_grant)
    else $error("SECURITY: Fault injection bypassed authentication");

  // Verify tamper detection triggered
  assert (tamper_detected)
    else $error("SECURITY: Fault not detected by tamper monitor");
endtask
```

### Formal Fault Analysis

Formal verification can exhaustively check that no single-point fault can bypass security:

```systemverilog
// Formal property: no single bit flip can bypass access control
assume property (@(posedge clk)
  $countones(register_state ^ golden_register_state) <= 1);
assert property (@(posedge clk)
  !authorized |-> !access_granted);
```

## Secure Boot Verification

### Secure Boot Chain

Secure boot verifies the integrity and authenticity of firmware before execution:

1. **ROM boot**: Immutable ROM code verifies the first-stage bootloader signature.
2. **Bootloader verification**: First-stage bootloader verifies the second-stage bootloader.
3. **OS kernel verification**: Second-stage bootloader verifies the OS kernel.
4. **Application verification**: OS verifies application integrity.

### Verification Checks

- **Signature verification**: Verify that invalid signatures are rejected.
- **Hash verification**: Verify that modified firmware is detected.
- **Key revocation**: Verify that revoked keys cannot authenticate firmware.
- **Anti-rollback**: Verify that older (potentially vulnerable) firmware versions are rejected.
- **Error handling**: Verify that verification failures halt boot (do not fall through to executing unverified code).

```systemverilog
// Test: boot with tampered firmware image
task test_tampered_boot();
  load_firmware(tampered_image);
  start_boot();

  // Verify boot halts at signature verification
  wait(boot_state == VERIFY_SIGNATURE);
  assert (boot_state != EXECUTE)
    else $error("SECURITY: Tampered firmware executed");
  assert (boot_error == SIGNATURE_MISMATCH)
    else $error("SECURITY: Tamper not detected");
endtask
```

## Key Management Verification

### Key Lifecycle

Verification must cover the complete key lifecycle:

1. **Key generation**: Random number generator produces keys with sufficient entropy.
2. **Key storage**: Keys stored in secure locations (OTP, secure SRAM, key slots) with access controls.
3. **Key usage**: Keys used only by authorized hardware blocks; never exposed on observable buses.
4. **Key derivation**: Derived keys computed correctly from master keys.
5. **Key zeroization**: Keys securely erased when required (tamper response, key update, power-down).

### Key Isolation Verification

```systemverilog
// Assert that key material never appears on the external bus
AST_KEY_NO_LEAK: assert property (@(posedge clk)
  ext_bus_data != stored_key[127:0] &&
  ext_bus_data != stored_key[255:128]
) else $error("SECURITY: Key material detected on external bus");

// Assert key slot access control
AST_KEY_ACCESS: assert property (@(posedge clk)
  key_read_request && !key_access_authorized |-> !key_data_valid
) else $error("SECURITY: Unauthorized key access granted");
```

### Key Zeroization

```systemverilog
// Verify keys are zeroized on tamper event
AST_ZEROIZE: assert property (@(posedge clk)
  tamper_event |-> ##[1:MAX_ZEROIZE_TIME] (key_storage == '0)
) else $error("SECURITY: Keys not zeroized within time limit after tamper");
```

## Information Flow Analysis

### Concept

Information flow analysis (IFA) tracks how data flows through the design to verify that sensitive information does not reach untrusted destinations. This is a formal verification technique.

### Tool Support

- **Synopsys VC Formal Security**: Formal-based information flow analysis.
- **Cadence JasperGold Security Path Verification**: Formal security verification.
- **Tortuga Logic Radix**: Hardware security verification platform.

### Information Flow Properties

```systemverilog
// Define security labels
// HIGH: secret data (keys, plaintext)
// LOW: observable data (bus outputs, debug ports)

// Property: no information flow from HIGH to LOW
// (Tool-specific syntax varies)
assert_no_flow: assert property (@(posedge clk)
  no_information_flow(secret_key, external_bus)
);
```

## Access Control Verification

### Memory Protection

Verify that memory protection units (MPU/MMU) correctly enforce access policies:

- Verify read/write/execute permissions for each memory region.
- Verify access from different security levels (secure, non-secure).
- Verify access from different privilege levels (user, supervisor, hypervisor).
- Test boundary conditions (access crossing region boundaries).

### Peripheral Access Control

Verify that peripherals are accessible only to authorized masters:

```systemverilog
// Assert that non-secure master cannot access secure peripheral
AST_SECURE_PERIPH: assert property (@(posedge clk)
  bus_request && (dest == SECURE_PERIPH) && (!master_is_secure) |->
  ##[1:5] bus_error
) else $error("SECURITY: Non-secure access to secure peripheral granted");
```

## Debug Interface Security

### JTAG/Debug Security

Verify that debug interfaces are properly secured:

- Debug access disabled in production fuse configuration.
- Secure debug requires authentication.
- Debug cannot access secure memory regions or key storage.
- Debug cannot bypass security features.

## Security Verification Methodology

### Security Verification Plan

The security verification plan extends the functional Vplan with security-specific items:

1. **Asset identification**: List all security assets (keys, credentials, sensitive data).
2. **Threat enumeration**: For each asset, enumerate threats (leakage, modification, bypass).
3. **Countermeasure verification**: For each threat, verify that countermeasures work.
4. **Negative testing**: Verify that attacks are detected and blocked.

### Security Coverage

Define coverage for security scenarios:
- All access control combinations (master x privilege x region x operation).
- All key lifecycle states (generation, storage, usage, derivation, zeroization).
- All tamper response scenarios.
- All boot chain verification outcomes (pass, fail for each stage).

## Best Practices

1. **Define the threat model early** — security verification is driven by threats, not features.
2. **Use formal methods for information flow** — simulation cannot exhaustively check data flow paths.
3. **Test negative scenarios explicitly** — verify that attacks fail, not just that normal operation succeeds.
4. **Verify fault injection resilience** — inject faults at every security-critical decision point.
5. **Verify key zeroization** — ensure secrets are destroyed when required, within the specified time.
6. **Include security tests in regression** — security is not a one-time check; it must be verified continuously.

## Summary

Security verification protects silicon designs against side-channel attacks, fault injection, unauthorized access, and information leakage. Side-channel analysis verifies countermeasure effectiveness. Fault injection testing confirms resilience to physical attacks. Secure boot verification ensures firmware integrity. Key management validation protects cryptographic material. Information flow analysis provides formal guarantees about data confidentiality. A threat-model-driven verification plan with comprehensive negative testing is essential for producing secure hardware.
