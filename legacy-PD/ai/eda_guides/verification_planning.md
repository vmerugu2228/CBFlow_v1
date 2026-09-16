# Verification Planning

## Overview

A verification plan (Vplan) is the strategic document that defines what must be verified, how it will be verified, and the criteria for declaring verification complete. It bridges the gap between the design specification and the verification implementation, ensuring that every design feature is covered by appropriate tests, assertions, and coverage metrics. Effective verification planning is the single most impactful activity in a verification project — a well-constructed Vplan prevents wasted effort, missed bugs, and late-stage surprises.

## Feature Extraction

### From Specification to Features

The first step in verification planning is extracting a comprehensive list of verifiable features from the design specification. Features are organized hierarchically:

**Level 1 — Functional Areas**
- Data path operations
- Control path logic
- Protocol interfaces
- Error handling
- Power management
- Clock and reset behavior
- DFT (Design for Test) features

**Level 2 — Individual Features**
Each functional area breaks down into specific features:
- Data path: ALU operations, pipeline forwarding, data alignment
- Protocol: AXI read channel, AXI write channel, exclusive access, barrier transactions
- Error handling: ECC single-bit correction, ECC double-bit detection, parity error response

**Level 3 — Scenarios**
Each feature breaks down into specific scenarios:
- AXI read channel: single beat, burst, narrow transfer, unaligned, interleaved, out-of-order

### Feature Classification

Features are classified by verification complexity and risk:

| Classification | Description | Strategy |
|---------------|-------------|----------|
| Critical | Affects functionality or data integrity | Heavy coverage, formal + simulation |
| Standard | Normal operation modes | Constrained random + coverage |
| Corner case | Boundary conditions, rare scenarios | Directed tests + formal |
| Negative | Error injection, invalid inputs | Error sequences + assertions |
| Performance | Throughput, latency requirements | Long-running tests, emulation |

## Coverage Model Design

### Mapping Features to Coverage

Every feature in the Vplan maps to one or more coverage items:

```
Feature: AXI burst transactions
├── Coverpoint: burst_type (FIXED, INCR, WRAP)
├── Coverpoint: burst_length (1, 2, 4, 8, 16)
├── Coverpoint: burst_size (1, 2, 4, 8 bytes)
├── Cross: burst_type x burst_length x burst_size
├── Transition: burst sequences (back-to-back, interleaved)
└── Assertion: AXI protocol compliance
```

### Coverage Granularity

The coverage model should be neither too coarse (misses important scenarios) nor too fine (creates unachievable closure targets):

- **Too coarse**: `coverpoint opcode;` — only checks that each opcode has been issued, not that each opcode works correctly in all contexts.
- **Appropriate**: `cross opcode, data_size, error_mode;` — verifies that each opcode works with different data sizes and under error conditions.
- **Too fine**: Crossing every possible variable creates millions of bins that are impossible to close.

### Coverage Hierarchy

```
Block-level coverage
├── Protocol coverage (per-interface)
├── Functional coverage (per-feature)
├── Error coverage (per-error-type)
└── Configuration coverage (per-config-mode)

Subsystem-level coverage
├── Inter-block interaction coverage
├── Arbitration coverage
├── End-to-end data integrity coverage
└── Multi-interface coordination coverage

SoC-level coverage
├── Power state transition coverage
├── Clock domain interaction coverage
├── Boot sequence coverage
└── Use-case coverage
```

## Test Strategy

### Test Categories

**Constrained Random Tests**
The primary verification vehicle. Random tests with constraints generate diverse stimulus that explores the design space broadly.

- Base test: Default constraints, exercising normal operation.
- Stress tests: Tight constraints maximizing throughput, outstanding transactions, buffer utilization.
- Corner-case tests: Constraints targeting boundary values, extreme configurations.
- Error-injection tests: Constraints generating protocol violations, data corruption, timeout conditions.

**Directed Tests**
Hand-written sequences targeting specific scenarios that constrained random tests are unlikely to reach:

- Reset during mid-transaction.
- Specific register programming sequences.
- Multi-step error recovery procedures.
- Deterministic performance measurements.

**Formal Properties**
Assertions that are both checked during simulation and proven formally:

- Protocol compliance (handshake rules, timing requirements).
- State machine integrity (no deadlocks, no illegal transitions).
- Data integrity (no data corruption or loss).
- Security properties (no information leakage).

**Built-In Tests**
Automated register tests (reset, bit-bash, access), connectivity checks, and clock/reset verification.

### Test Architecture

```
Test hierarchy:
├── base_test (common setup, default configuration)
│   ├── smoke_test (minimal functionality check)
│   ├── random_test (broad constrained random)
│   │   ├── stress_test (high-throughput, deep queues)
│   │   ├── corner_test (boundary values, rare configs)
│   │   └── error_test (fault injection, protocol violations)
│   ├── directed_test_suite
│   │   ├── reset_test (reset during various operations)
│   │   ├── power_test (power state transitions)
│   │   └── config_test (all configuration combinations)
│   └── register_test_suite
│       ├── reg_reset_test (verify reset values)
│       ├── reg_bit_bash_test (walking 1/0 patterns)
│       └── reg_access_test (front-door/back-door comparison)
```

## Verification Schedule

### Phase-Based Approach

**Phase 1: Infrastructure (Weeks 1-4)**
- Testbench architecture and component development.
- Interface agents (driver, monitor, sequencer).
- Basic scoreboard and reference model.
- Smoke test passing.

**Phase 2: Feature Verification (Weeks 5-12)**
- Constrained random test development.
- Coverage model implementation.
- Formal property development and proofs.
- Register model integration and built-in tests.
- Coverage-driven closure for individual features.

**Phase 3: Integration and Stress (Weeks 13-18)**
- Multi-feature interaction testing.
- Stress and performance tests.
- Error injection and recovery tests.
- Gate-level simulation (post-synthesis).

**Phase 4: Closure and Sign-Off (Weeks 19-24)**
- Coverage hole analysis and closure.
- Bug rate trending analysis.
- Gate-level simulation (post-PnR with SDF).
- Power-aware simulation.
- Sign-off review.

### Milestones

| Milestone | Criteria |
|-----------|----------|
| TB Ready | Smoke test passing, all agents functional |
| Feature Complete | All planned tests developed and running |
| Coverage 80% | 80% functional coverage, 85% code coverage |
| Coverage 95% | 95% functional coverage, 90% code coverage |
| Bug Rate Declining | 3 consecutive weeks with fewer new bugs |
| Sign-Off | All criteria met, formal review completed |

## Sign-Off Criteria

### Quantitative Criteria

- **Functional coverage**: Typically 100% of all non-excluded coverpoints and crosses.
- **Code coverage**: Typically 95%+ for statement, branch, and condition; 90%+ for toggle; 80%+ for FSM.
- **Assertion coverage**: All assertions have fired (non-vacuous) and passed.
- **Regression pass rate**: 100% (all tests pass across all seeds).
- **Bug rate**: Declining trend for at least 3 consecutive weeks; no open Sev1 or Sev2 bugs.

### Qualitative Criteria

- All Vplan features have been verified (traceability from feature to test to coverage).
- All formal properties have been proven or have bounded proofs with acceptable depth.
- Gate-level simulation has been run for critical tests.
- Power-aware simulation has verified all power state transitions.
- CDC verification has been completed for all clock domain crossings.
- All exclusions have been reviewed and documented with justification.

### Sign-Off Review

A formal sign-off review involves:
1. Presentation of all quantitative metrics.
2. Review of open issues, waivers, and exclusions.
3. Risk assessment for any incomplete verification areas.
4. Agreement from design, verification, and project leadership.

## Verification Plan Management

### Vplan Tools

Modern verification management tools provide integrated Vplan tracking:

- **Cadence vManager**: Hierarchical Vplan linked to coverage, tests, and metrics.
- **Synopsys Verdi/URG**: Coverage analysis and Vplan integration.
- **Siemens Questa Verification Management**: Vplan-driven verification with UCDB coverage databases.

### Living Document

The Vplan is not static — it evolves throughout the project:
- New features added as the specification is updated.
- Coverage model refined based on simulation results.
- Test strategy adjusted based on bug patterns.
- Sign-off criteria reviewed and updated based on project risk.

### Traceability Matrix

A traceability matrix links every element of the verification chain:

```
Specification Feature -> Vplan Entry -> Test(s) -> Coverage Point(s) -> Result
```

This ensures no feature falls through the cracks and every test has a clear purpose.

## Best Practices

1. **Start the Vplan before RTL development** — write the verification plan from the specification, not the implementation.
2. **Review the Vplan with designers** — they know the design intent and critical corners.
3. **Prioritize by risk** — allocate more verification effort to complex, novel, or safety-critical features.
4. **Track coverage continuously** — do not wait until the end to discover coverage holes.
5. **Maintain traceability** — every feature must trace to tests and coverage; every test must trace to a feature.
6. **Document all exclusions and waivers** with technical justification.

## Summary

Verification planning is the foundation of a successful verification project. Feature extraction from the specification, coverage model design, test strategy development, and clear sign-off criteria ensure that verification effort is directed and measurable. A well-maintained Vplan with traceability, continuous coverage tracking, and regular reviews enables teams to achieve verification closure with confidence and predictability.
