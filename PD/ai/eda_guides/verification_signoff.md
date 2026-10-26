# Verification Sign-Off

## Overview

Verification sign-off is the formal decision point at which the verification team declares that the design has been sufficiently verified and is ready for tapeout. It is one of the most consequential decisions in a chip project — premature sign-off risks silicon bugs, while excessive caution delays time-to-market. Sign-off is not a single metric or checklist item; it is a holistic assessment combining quantitative metrics (coverage, bug rates, regression results), qualitative analysis (risk assessment, feature completeness), and process verification (documentation, reviews, waivers).

## Coverage Closure

### Functional Coverage Closure

Functional coverage is the primary metric for verification completeness. It measures whether the verification plan's intended scenarios have been exercised.

**Sign-off criteria:**
- 100% of all planned coverpoints and crosses hit (after exclusions).
- All exclusions documented with technical justification and reviewed.
- Cross-coverage at meaningful granularity (not just individual coverpoints).
- Transition coverage for all state machines and protocol sequences.

**Closure process:**
1. Identify uncovered bins from the merged coverage database.
2. For each gap, determine root cause:
   - Missing test/constraint: Write targeted test.
   - Unreachable scenario: Document and exclude.
   - Design limitation: Confirm with design team.
3. Iterate until all bins are covered or excluded.

### Code Coverage Closure

Code coverage measures RTL structural exercise.

**Typical sign-off targets:**

| Coverage Type | Block Level | Subsystem | Full Chip |
|--------------|-------------|-----------|-----------|
| Statement | 100% | 98% | 95% |
| Branch | 100% | 95% | 90% |
| Condition | 95% | 90% | 85% |
| Toggle | 95% | 90% | 85% |
| FSM State | 100% | 100% | 100% |
| FSM Transition | 95% | 90% | 85% |

**Closure process:**
1. Merge code coverage from the full regression suite.
2. Identify uncovered code.
3. Classify each uncovered item:
   - Testable gap: Write test to exercise the code.
   - Dead code: Confirm with design team and exclude (or remove dead code).
   - Untestable in verification environment: Document limitation and risk.
4. Document all exclusions with justification.

### Assertion Coverage

Assertion coverage verifies that assertions have been exercised (not vacuously true).

**Sign-off criteria:**
- All assertions have attempted (antecedent matched at least once).
- Zero assertion failures in passing regression.
- Cover properties paired with assertions have been hit.
- Formal proofs completed for targeted properties.

## Bug Rate Trending

### Bug Rate Curve

The bug discovery rate (bugs found per week) is one of the most reliable indicators of verification maturity. A healthy project shows:

```
Bugs/week
^
|  *
| * *
|*   *
|     * *
|       * * *
|           * * * *
|                 * * * *
+------------------------→ Time
         Declining trend
```

**Sign-off criteria:**
- Declining bug rate for at least 3 consecutive weeks.
- No Severity 1 (blocking) bugs open.
- No Severity 2 (major functionality) bugs open.
- All Severity 3 (minor) bugs assessed for tapeout risk.

### Bug Categorization

| Severity | Description | Sign-off Requirement |
|----------|-------------|---------------------|
| Sev1 | Functional failure, data corruption | Must fix before tapeout |
| Sev2 | Major feature broken, performance failure | Must fix before tapeout |
| Sev3 | Minor issue, workaround available | Risk-assessed, may waive |
| Sev4 | Cosmetic, documentation | No tapeout impact |

### Bug Escape Analysis

Review past bugs to identify potential verification gaps:
- Were there bug categories that were found late? Why?
- Are there features similar to late-found bugs that need additional scrutiny?
- Do the bug patterns suggest systematic verification weaknesses?

## Risk Assessment

### Verification Risk Matrix

For each design feature, assess the verification risk:

| Feature | Complexity | Novelty | Coverage | Bug History | Risk Level |
|---------|-----------|---------|----------|-------------|------------|
| DMA engine | High | New design | 98% | 15 bugs, all fixed | Medium |
| UART | Low | Reused IP | 100% | 2 bugs, all fixed | Low |
| Cache coherency | Very High | New protocol | 95% | 25 bugs, 2 open | High |
| Power management | High | Modified | 92% | 8 bugs, all fixed | Medium-High |

### Risk Mitigation

For high-risk areas:
- Additional targeted testing.
- Formal verification proofs.
- Independent review by a second engineer.
- Silicon validation plan for post-silicon verification.
- Potential metal-fix or ECO plan if bugs are found.

### Uncovered Risk Areas

Identify areas that cannot be fully verified before tapeout:
- System-level interactions not reproducible in simulation.
- Performance under real-world workloads.
- Analog-digital interactions beyond RNM accuracy.
- Multi-chip interconnect behavior.
- Manufacturing process variation effects.

Document these risks and the corresponding post-silicon validation plans.

## Sign-Off Checklist

### Functional Verification

- [ ] All Vplan features marked as verified with evidence (tests, coverage, formal proofs).
- [ ] Functional coverage at 100% (after reviewed exclusions).
- [ ] Code coverage at target levels (after reviewed exclusions).
- [ ] Assertion coverage confirms non-vacuous exercise.
- [ ] Formal verification proofs completed for targeted properties.
- [ ] Equivalence checking (RTL-to-gate) passed.

### Regression

- [ ] Full regression passing at 100% (all tests, all seeds).
- [ ] Regression stable for at least 2 consecutive full runs.
- [ ] No flaky tests (intermittent failures investigated and resolved).
- [ ] Coverage merged from all regression runs.

### Specific Verification Domains

- [ ] CDC verification: All structural checks clean; formal protocol verification completed.
- [ ] Power-aware verification: All power states and transitions verified.
- [ ] Gate-level simulation: Post-synthesis and post-PnR GLS completed for selected tests.
- [ ] DFT verification: Scan chain, BIST, JTAG verified at gate level.
- [ ] Security verification: All threat model items verified (if applicable).
- [ ] Performance verification: Throughput, latency, bandwidth within specification.

### Bug Status

- [ ] Zero open Sev1 bugs.
- [ ] Zero open Sev2 bugs.
- [ ] All Sev3 bugs assessed and documented.
- [ ] Bug rate declining for 3+ consecutive weeks.
- [ ] Bug escape analysis completed.

### Documentation and Process

- [ ] All coverage exclusions documented and reviewed.
- [ ] All formal waivers documented and reviewed.
- [ ] Verification plan traceability complete (feature → test → coverage → result).
- [ ] Sign-off review meeting conducted with stakeholders.
- [ ] Post-silicon validation plan documented for uncovered risks.

## Sign-Off Review Process

### Review Meeting

The sign-off review is a formal meeting with key stakeholders:

**Attendees:**
- Verification lead (presenter).
- Design lead.
- Project manager.
- Architecture representative.
- Quality assurance (optional).

**Agenda:**
1. Coverage metrics presentation (functional, code, assertion, formal).
2. Bug status and trending.
3. Risk assessment for each major feature.
4. Exclusion and waiver review.
5. Open issues and known limitations.
6. Post-silicon validation plan.
7. Sign-off decision.

### Sign-Off Decision Outcomes

- **Sign-off approved**: All criteria met; tapeout can proceed.
- **Conditional sign-off**: Minor gaps identified with agreed mitigation plan and timeline.
- **Sign-off deferred**: Significant gaps require additional verification before re-review.

## Coverage Regression Prevention

### Maintaining Coverage

After sign-off, coverage must be maintained through tapeout:
- Any RTL change after sign-off triggers re-verification.
- ECO (Engineering Change Order) changes require targeted regression.
- Coverage must not decrease after post-sign-off changes.

### ECO Verification

ECOs are late-stage RTL changes (timing fixes, bug fixes, metal changes). ECO verification includes:
1. Equivalence checking (pre-ECO vs. post-ECO).
2. Targeted regression on affected features.
3. Coverage delta analysis (confirm no coverage regression).
4. Formal property re-proof for affected logic.

## Metrics Dashboard

### Sign-Off Dashboard Content

```
Verification Sign-Off Dashboard
================================
Date: 2024-01-15
Design: My_SoC v2.0

Coverage Summary:
  Functional Coverage:  99.2% (target: 100%)  [4 bins remaining]
  Code Coverage:
    Statement:          98.7% (target: 95%)    ✓
    Branch:             96.3% (target: 90%)    ✓
    Condition:          93.1% (target: 85%)    ✓
    Toggle:             91.8% (target: 85%)    ✓
    FSM State:          100%  (target: 100%)   ✓
    FSM Transition:     94.2% (target: 85%)    ✓

Regression:
  Total tests:          2,847
  Passing:              2,847 (100%)          ✓
  Stable for:           3 consecutive runs     ✓

Bugs:
  Open Sev1:            0                      ✓
  Open Sev2:            0                      ✓
  Open Sev3:            2 (assessed, waived)   ✓
  Bug rate trend:       Declining 4 weeks      ✓

Formal:
  Properties proven:    342/350 (97.7%)
  Bounded:             8 (depth ≥ 100 cycles)
  Equivalence check:   PASS                    ✓

CDC:
  Structural clean:    PASS                    ✓
  Formal protocol:     PASS                    ✓

Status: READY FOR SIGN-OFF REVIEW
```

## Common Sign-Off Pitfalls

1. **Rushing coverage closure**: Excluding bins without proper justification to hit targets.
2. **Ignoring bug rate**: Signing off while bug rate is still high (not declining).
3. **Incomplete formal verification**: Accepting bounded proofs without understanding the depth limitation.
4. **Missing CDC verification**: Treating CDC as optional rather than mandatory.
5. **Skipping GLS**: Relying solely on RTL simulation and equivalence checking.
6. **Post-sign-off RTL churn**: Making changes after sign-off without re-verification.

## Best Practices

1. **Track metrics continuously** — do not wait until the end to compile sign-off data.
2. **Hold regular coverage reviews** (weekly) to maintain momentum toward closure.
3. **Document everything** — exclusions, waivers, risk assessments, and known limitations.
4. **Use multiple independent metrics** — no single metric is sufficient for sign-off confidence.
5. **Plan for post-silicon validation** — acknowledge that pre-silicon verification cannot cover everything.
6. **Maintain traceability** from specification features through tests to coverage to results.

## Summary

Verification sign-off is a rigorous, evidence-based assessment of verification completeness and design readiness for tapeout. Coverage closure (functional, code, assertion), bug rate trending, risk assessment, and process compliance combine to provide sign-off confidence. A structured sign-off review with documented evidence, exclusion justification, and risk mitigation plans ensures that the sign-off decision is well-founded. Post-sign-off discipline (ECO verification, coverage maintenance) preserves the verification investment through tapeout.
