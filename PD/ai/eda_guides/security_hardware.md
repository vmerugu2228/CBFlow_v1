# Hardware Security: Crypto Engines, PUF, Secure Boot, and Side-Channel Countermeasures

## Overview

Hardware security is a critical aspect of modern SoC design, protecting intellectual property, user data, and system integrity against both remote and physical attacks. Security features must be designed into the silicon from the start -- they cannot be effectively bolted on later. This guide covers cryptographic hardware engines, physically unclonable functions (PUFs), secure boot chains, ARM TrustZone, and countermeasures against side-channel attacks.

## Cryptographic Hardware Engines

### Symmetric Ciphers

**AES (Advanced Encryption Standard):**
- Block size: 128 bits; key sizes: 128, 192, or 256 bits
- Hardware implementation: iterative (one round per clock, 10-14 cycles/block) or fully unrolled (one block per clock, high throughput)
- Modes of operation: ECB, CBC, CTR, GCM (authenticated encryption), XTS (storage encryption)
- Area: 10-50K gates depending on implementation style and throughput
- AES-GCM: combines encryption with authentication using Galois field multiplication; standard for TLS, IPsec

**ChaCha20-Poly1305:**
- Stream cipher + MAC; alternative to AES for software-friendly environments
- Increasingly used in TLS 1.3 and WireGuard VPN
- Hardware implementation: quarter-round function repeated 20 times

### Asymmetric Cryptography

**RSA:**
- Key sizes: 2048, 3072, 4096 bits
- Hardware: modular exponentiation using Montgomery multiplication
- Performance: RSA-2048 sign ~1 ms in dedicated hardware
- Use case: secure boot signature verification, certificate processing

**Elliptic Curve Cryptography (ECC):**
- Key sizes: 256, 384, 521 bits (equivalent security to much larger RSA keys)
- Curves: NIST P-256, P-384; Curve25519, Ed25519
- Hardware: point multiplication using scalar multiplication engines
- More area-efficient than RSA for equivalent security
- Use case: key exchange (ECDH), digital signatures (ECDSA)

### Hash Functions

- **SHA-256**: 256-bit output; standard for secure boot, certificate verification, integrity checking
- **SHA-384/512**: larger output for higher security requirements
- **SHA-3 (Keccak)**: alternative hash family; sponge construction; resistance to length extension attacks
- **HMAC**: keyed hash for message authentication; HMAC-SHA-256 widely used in protocols

### Crypto Engine Architecture

A typical SoC crypto subsystem:

```
CPU/DMA -> Crypto Engine Input FIFO -> Key Scheduler -> Cipher Core -> Output FIFO -> Memory
                                            |
                                       Key Storage
                                       (OTP/PUF)
```

Key architectural features:
- **DMA interface**: scatter-gather DMA for processing large data buffers without CPU involvement
- **Key management**: hardware key storage with access control; keys never exposed to software
- **Multi-context**: support multiple concurrent encryption contexts for different clients
- **Hardware acceleration**: dedicated datapaths for common operations (AES, SHA, RSA/ECC)

## Physically Unclonable Functions (PUF)

### Concept

A PUF exploits manufacturing variation to create a unique, unclonable device identifier:

- Each chip has slightly different transistor characteristics due to process variation
- A PUF circuit converts these variations into a unique bit string (PUF response)
- The response is reproducible on the same chip but different on every other chip
- Cannot be cloned because the manufacturing variations cannot be precisely reproduced

### PUF Types

**SRAM PUF:**
- Exploits the preferred power-up state of uninitialized SRAM cells
- Each cell has a slight mismatch between cross-coupled inverters, biasing it toward 0 or 1
- Power-up pattern is unique per chip and reproducible (~95% stable bits)
- Advantage: uses existing SRAM; no additional circuit required
- Disadvantage: requires controlled power-up; sensitive to voltage and temperature

**Ring Oscillator PUF:**
- Pairs of identically designed ring oscillators have slightly different frequencies due to process variation
- Compare frequencies of pairs; faster oscillator determines bit value
- Advantage: simple, robust, measurable at any time (not just power-up)
- Disadvantage: requires dedicated oscillator circuits

**Arbiter PUF:**
- Race condition between two signal paths through a chain of multiplexers
- Challenge bits select path configuration; response bit is determined by which path is faster
- Advantage: large challenge-response space
- Disadvantage: susceptible to modeling attacks with machine learning

### PUF Applications

- **Device authentication**: prove device identity without storing secret keys
- **Key generation**: derive encryption keys from PUF response; keys exist only when needed
- **Anti-counterfeiting**: PUF response serves as hardware fingerprint
- **Secure storage**: encrypt stored keys with PUF-derived key; decryption only possible on the same chip

### Error Correction for PUF

PUF responses have ~5% noisy bits. Fuzzy extractors correct these:

1. **Enrollment**: generate PUF response; compute helper data using error-correcting code
2. **Reconstruction**: generate PUF response again; use helper data to correct errors
3. **Key derivation**: hash corrected response to produce stable key
4. **Security requirement**: helper data must not leak information about the key (secure sketch)

## Secure Boot

### Boot Chain of Trust

Secure boot ensures only authenticated firmware runs on the device:

1. **Root of Trust (RoT)**: immutable code in ROM (Boot ROM); first code executed after reset
2. **First-stage bootloader**: Boot ROM verifies signature of first-stage bootloader using public key hash stored in OTP
3. **Second-stage bootloader**: first-stage verifies second-stage signature
4. **OS kernel**: second-stage verifies kernel signature
5. **Applications**: kernel verifies application signatures

Each stage verifies the next before transferring control, creating a chain of trust rooted in hardware.

### Key Components

- **Boot ROM**: mask ROM or OTP-based; contains root verification code; immutable after manufacturing
- **OTP (One-Time Programmable) memory**: stores public key hash, security configuration, device ID, lifecycle state
- **Secure key storage**: hardware-protected storage for root keys; accessible only by Boot ROM and crypto engine
- **Signature verification**: RSA or ECDSA signature check of each boot stage
- **Rollback protection**: monotonic counter in OTP prevents loading older (vulnerable) firmware versions

### Secure Boot Implementation

```
Power-On -> Boot ROM (ROM) -> Verify FSBL signature -> FSBL (Flash)
                                    |                     |
                              OTP: Public Key Hash   Verify SSBL signature -> SSBL
                                                                              |
                                                                        Verify OS signature -> OS
```

**Anti-rollback mechanism:**
- OTP stores a version counter
- Each firmware image includes a minimum version field
- Boot ROM rejects images with version less than OTP counter
- On successful update, OTP counter is incremented

## ARM TrustZone

### Architecture

TrustZone divides the system into two worlds:

- **Secure world**: runs trusted firmware, manages keys, performs sensitive operations
- **Normal (Non-secure) world**: runs the OS, applications, general-purpose code

**Hardware partitioning:**
- **NS bit**: every bus transaction carries a Non-Secure bit; hardware enforces access based on this bit
- **TZASC (TrustZone Address Space Controller)**: partitions memory regions into secure/non-secure
- **TZPC (TrustZone Protection Controller)**: partitions peripherals into secure/non-secure
- **Monitor mode (Cortex-A)**: handles transitions between worlds via SMC (Secure Monitor Call)

### TrustZone Use Cases

- **Secure key storage**: encryption keys accessible only from secure world
- **DRM (Digital Rights Management)**: content decryption in secure world; plain content never in normal world
- **Secure I/O**: biometric sensor, display path protected from normal world tampering
- **Trusted execution environment (TEE)**: OP-TEE, Trusty; runs secure services called by normal world

### SoC Integration

- All bus masters must propagate the NS bit
- All bus slaves must check the NS bit and enforce access policy
- Interconnect must support security-aware address decoding
- Interrupts must be partitioned (GIC Group 0 = secure, Group 1 = non-secure)
- DMA controllers must honor NS configuration to prevent DMA-based attacks

## Side-Channel Countermeasures

### Side-Channel Attack Types

**Timing attacks:**
- Attacker measures execution time of cryptographic operations
- Time differences reveal information about secret keys (e.g., RSA with naive square-and-multiply)
- Countermeasure: constant-time implementations; avoid data-dependent branches and memory access patterns

**Power analysis:**
- **SPA (Simple Power Analysis)**: directly observes power consumption patterns during crypto operations
- **DPA (Differential Power Analysis)**: statistical analysis of many power traces to extract key bits
- Countermeasure: masking (randomize intermediate values), hiding (add noise, randomize execution order)

**Electromagnetic (EM) analysis:**
- Similar to power analysis but measures EM emissions from the chip
- Can be more spatially targeted than power analysis
- Countermeasure: same as power analysis; additionally, metal shielding layers

**Fault injection:**
- Deliberately introduce faults (voltage glitch, clock glitch, laser) to cause computation errors
- Differential fault analysis extracts keys from faulty vs. correct outputs
- Countermeasure: redundant computation, error detection, voltage/clock glitch detectors, light sensors

### Hardware Countermeasures

**Masking:**
- Split every sensitive variable into multiple shares: x = x1 XOR x2 XOR ... XOR xn
- Process shares independently; each share individually reveals nothing about x
- Reconstruct result only at the end
- Cost: multiplicative area and power overhead (d+1 shares for d-th order security)

**Hiding:**
- **Random delays**: insert random NOP operations to desynchronize traces
- **Shuffling**: randomize the order of independent operations (e.g., S-box computations in different order each time)
- **Noise generation**: dedicated circuits that generate random switching activity

**Glitch detection:**
- **Voltage glitch detector**: comparator monitors supply for sub-nanosecond dips; triggers tamper response
- **Clock glitch detector**: monitors clock frequency and duty cycle for anomalies
- **Light sensor**: mesh of photosensitive circuits detects die exposure (decapsulation for laser fault injection)

**Tamper response:**
- Zeroize keys and sensitive data on tamper detection
- Lock device into non-recoverable state
- Log tamper event in OTP for forensic analysis

## Security Lifecycle Management

### Device Lifecycle States

| State | Description | Security |
|---|---|---|
| Blank | Fresh from fab; no keys provisioned | Open |
| Provisioned | Keys and certificates programmed in OTP | Manufacturing |
| Secured | Secure boot enforced; debug disabled | Field deployment |
| End-of-life | All keys zeroized; device decommissioned | Terminated |

Lifecycle state transitions are typically one-way (enforced by OTP bits) to prevent rollback to less secure states.

### Debug Security

- **Secure debug**: debug access requires authentication (certificate-based challenge-response)
- **Debug disable**: OTP bit permanently disables JTAG/debug in production devices
- **Partial debug**: allow non-invasive debug (trace) while blocking invasive debug (memory access)

Hardware security is not optional in modern SoC design. A comprehensive security architecture -- from secure boot and TrustZone partitioning to side-channel-resistant crypto engines -- must be planned from the earliest design phase and verified rigorously through both functional and penetration testing.
