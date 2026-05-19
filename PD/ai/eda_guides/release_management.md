# Release Management: Tapeout Milestones, Exit Criteria, and Signoff Checklists

## Overview

Release management in physical design is the structured process of moving a chip design through a series of milestone checkpoints from initial floorplanning to final manufacturing handoff. Each milestone has defined exit criteria that must be met before the design advances to the next stage. This disciplined approach prevents costly rework, ensures all stakeholders agree on design readiness, and provides a clear framework for managing the complexity of a multi-month tapeout schedule.

## Milestone Framework

The standard PD milestone framework consists of six major gates, each representing a critical phase transition in the design flow:

```
FP_EXIT  -->  PLACE_EXIT  -->  CTS_EXIT  -->  PRO_EXIT  -->  BTO  -->  MTO
(Floorplan)  (Placement)    (Clock Tree)   (Post-Route)   (Block TO)  (Mask TO)
```

Each milestone is a formal review where the design team presents QoR data, signoff status, and risk assessment to management and stakeholders. Advancement past a milestone requires explicit sign-off from designated approvers.

## FP_EXIT: Floorplan Exit

### Description

FP_EXIT marks the completion of the floorplanning phase. The physical foundation of the chip is established: die size is finalized, macros are placed, I/O pads are assigned, and the power grid is designed.

### Exit Criteria

**Mandatory:**
- Die size finalized and approved by package team.
- All hard macros placed (SRAM, ROM, PLL, analog IP, SerDes).
- I/O pad/bump assignment complete and consistent with package design.
- Power grid designed and passing preliminary IR drop analysis (<5% VDD static).
- Voltage areas defined for all power domains (multi-voltage designs).
- Placement blockages and routing blockages correctly defined.
- Standard cell utilization within target range (60-75%).
- Preliminary congestion analysis shows no overflow.
- All IP collateral received and validated (LEF, LIB, GDS).

**Recommended:**
- Preliminary timing estimate shows feasibility at target frequency.
- Pin assignments for hierarchical partitions agreed upon.
- DFT strategy (scan chain count, compression ratio) finalized.
- Power budget allocated to blocks.

### Deliverables

- Floorplan DEF file (version-controlled).
- Power grid TCL script and IR drop report.
- Utilization and congestion estimation report.
- Macro placement and I/O assignment document.
- Risk log identifying any open issues.

## PLACE_EXIT: Placement Exit

### Description

PLACE_EXIT confirms that standard cell placement is complete and timing is on a trajectory to close. Placement is the most impactful stage for timing QoR; poor placement cannot be fully recovered by downstream optimizations.

### Exit Criteria

**Mandatory:**
- All standard cells legally placed within the floorplan.
- No placement density hotspots exceeding 85% local utilization.
- Setup WNS better than -100ps on the worst corner (ideally better than -50ps).
- No routing congestion overflow (estimated by global route).
- Scan chain ordering complete.
- Clock gating cells placed and optimized.
- Multi-Vt optimization complete; leakage within budget at target Vt distribution.
- Hold timing assessed; hold fixing deferred to CTS stage but no show-stoppers identified.

**Recommended:**
- Physical-aware synthesis correlation: post-placement timing within 10% of synthesis prediction.
- Placement QoR stable across 3+ consecutive nightly builds.
- Critical path analysis identifies no structural issues requiring RTL changes.

### Deliverables

- Placed DEF file.
- Timing report (WNS/TNS per corner per mode).
- Congestion map and utilization report.
- Power report (leakage, Vt distribution).
- Updated risk log.

## CTS_EXIT: Clock Tree Synthesis Exit

### Description

CTS_EXIT marks the completion of clock tree construction and post-CTS optimization. The clock network is the highest-priority structure in the design; its quality directly determines timing closure success.

### Exit Criteria

**Mandatory:**
- Clock trees built for all clock domains.
- Clock skew within target (<50-100ps per domain, design-dependent).
- Clock latency within budget.
- Setup WNS better than -50ps (ideally 0ps).
- Setup TNS trending toward zero.
- Hold timing: WHS better than -20ps; hold fixing plan in place.
- No max-transition or max-capacitance violations on clock nets.
- Clock power within budget (typically 30-50% of total dynamic power).
- CTS results consistent across nightly builds.

**Recommended:**
- Useful skew optimization applied where beneficial.
- Post-CTS power analysis confirms total power within budget.
- Cross-domain clock interactions verified (no unexpected CDC paths).

### Deliverables

- Post-CTS DEF file.
- Clock tree report (skew, latency, depth, buffer count per domain).
- Updated timing reports (all corners, all modes).
- Clock power report.
- Hold violation list with remediation plan.

## PRO_EXIT: Post-Route Optimization Exit

### Description

PRO_EXIT (also called ROUTE_EXIT) confirms that routing is complete, post-route optimization has been performed, and the design is ready for signoff analysis. This is the most comprehensive milestone before tapeout.

### Exit Criteria

**Mandatory:**
- All nets routed (zero unrouted nets).
- In-design DRC: zero violations (or documented known issues with fix plan).
- In-design LVS: clean connectivity.
- Setup WNS = 0ps across all signoff corners and modes.
- Setup TNS = 0ps.
- Hold WNS = 0ps (all hold violations fixed).
- No max-transition violations.
- No max-capacitance violations.
- Antenna violations: zero (or fix plan with projected completion).
- Via doubling rate > 80% (design-dependent).
- Metal fill inserted; density within foundry requirements.
- IR drop analysis: static < 5% VDD, dynamic < 10% VDD.
- EM analysis: all wires and vias within limits.

**Recommended:**
- Signoff STA (PrimeTime/Tempus) run on all corners showing same results as in-design STA.
- Formal equivalence check (LEC) passes between post-route netlist and RTL.
- DFT: ATPG coverage > 95%.
- Power analysis with realistic vectors confirms power budget compliance.

### Deliverables

- Final routed DEF file.
- Exported GDS/OASIS.
- Post-route Verilog netlist.
- SPEF files for all extraction corners.
- Comprehensive timing reports (all MMMC corners/modes).
- DRC/LVS/antenna reports.
- IR drop and EM reports.
- Power report.
- Formal equivalence report.

## BTO: Block Tapeout

### Description

BTO is the milestone where an individual block (partition) within a hierarchical SoC is declared complete and ready for integration into the top level. BTO applies to designs where multiple blocks are implemented independently and then assembled.

### Exit Criteria

**Mandatory:**
- All PRO_EXIT criteria met for the block.
- Signoff DRC (Calibre/ICV) clean on the block GDS.
- Signoff LVS clean on the block GDS.
- Signoff STA clean across all MMMC corners.
- Block pin timing (input/output delay at block ports) meets the top-level timing budget.
- Power report delivered to the top-level integration team.
- Block abstract (LEF) generated and validated.
- Block timing model (ILM/ETM) generated and validated for top-level STA.

**Recommended:**
- Block-level EM/IR analysis clean.
- Block-level antenna clean.
- Formal equivalence clean.
- Documentation of any known issues or waivers.

### Deliverables

- Block GDS file.
- Block LEF/abstract.
- Block timing model (ILM for PrimeTime, ETM for Tempus).
- Block SPEF.
- Block SDC (for top-level constraint generation).
- Block power model.
- All signoff reports.

## MTO: Mask Tapeout

### Description

MTO is the final milestone: the design data is frozen, fully verified, and delivered to the foundry for mask fabrication. MTO is irreversible; any change after MTO requires a full mask respin.

### Exit Criteria

**Mandatory:**
- All BTO criteria met for every block (or all PRO_EXIT criteria for flat designs).
- Top-level integration complete (all blocks assembled).
- Top-level signoff DRC clean (on merged GDS).
- Top-level signoff LVS clean (on merged GDS).
- Top-level signoff ERC clean.
- Top-level signoff antenna clean.
- Top-level signoff STA clean (all MMMC corners/modes, all blocks).
- Metal density compliance for all layers.
- EM/IR analysis clean at top level.
- Formal equivalence clean (RTL to final netlist).
- DFT: scan, MBIST, JTAG verified.
- GDS merged with seal ring/frame, fill, and all IP.
- GDS checksums generated and verified.
- Foundry tapeout checklist completed (all items checked).
- Management sign-off (design lead, project manager, VP of engineering).

**Recommended:**
- Power-up sequence verified (multi-voltage designs).
- ESD protection verified (Calibre PERC or equivalent).
- Reliability checks complete (latch-up, aging margins).
- Tapeout dry run completed successfully 1-2 weeks before actual MTO.

### Deliverables

- Final GDS/OASIS file with checksum.
- Complete foundry tapeout package (see manufacturing_signoff.md).
- All signoff reports archived.
- Tapeout log documenting every verification step and result.
- Management approval signatures.

## Sign-Off Checklist Template

A comprehensive signoff checklist ensures nothing is missed:

```
TAPEOUT SIGNOFF CHECKLIST
Design: ________________  Date: ________________
Process: _______________  Die Size: _____________

TIMING SIGNOFF
[ ] WNS = 0 all setup corners          Signed: ________
[ ] TNS = 0 all setup corners          Signed: ________
[ ] WHS = 0 all hold corners           Signed: ________
[ ] No max-transition violations        Signed: ________
[ ] No max-capacitance violations       Signed: ________
[ ] All modes analyzed                  Signed: ________
[ ] OCV/POCV enabled                    Signed: ________
[ ] SI analysis enabled                 Signed: ________

PHYSICAL VERIFICATION
[ ] DRC clean (tool: ____ ver: ____)    Signed: ________
[ ] LVS clean (tool: ____ ver: ____)    Signed: ________
[ ] ERC clean                           Signed: ________
[ ] Antenna clean                       Signed: ________
[ ] Density compliant                   Signed: ________

POWER/RELIABILITY
[ ] Static IR drop < ___% VDD          Signed: ________
[ ] Dynamic IR drop < ___% VDD         Signed: ________
[ ] EM clean                            Signed: ________
[ ] Total power < ___ W                 Signed: ________

DATA INTEGRITY
[ ] GDS merged successfully             Signed: ________
[ ] GDS checksum verified               Signed: ________
[ ] Layer mapping verified              Signed: ________
[ ] Foundry checklist complete          Signed: ________

FORMAL VERIFICATION
[ ] LEC RTL vs. netlist PASS           Signed: ________
[ ] LEC pre-route vs. post-route PASS  Signed: ________

DFT
[ ] Scan coverage > ____%              Signed: ________
[ ] MBIST verified                      Signed: ________
[ ] JTAG verified                       Signed: ________

APPROVALS
[ ] Design Lead                         Signed: ________
[ ] Project Manager                     Signed: ________
[ ] Quality/Reliability                 Signed: ________
[ ] VP Engineering                      Signed: ________
```

## Milestone Schedule Planning

### Typical Milestone Timeline

For a mid-complexity SoC block at an advanced node:

| Milestone | Weeks from Start | Duration |
|---|---|---|
| FP_EXIT | Week 2-3 | 2-3 weeks |
| PLACE_EXIT | Week 5-6 | 2-3 weeks |
| CTS_EXIT | Week 7-8 | 1-2 weeks |
| PRO_EXIT | Week 10-12 | 3-4 weeks |
| BTO | Week 13-14 | 1-2 weeks |
| MTO | Week 16-18 | 2-4 weeks (top integration) |

Total: approximately 16-18 weeks from floorplan start to MTO for a single block.

### Schedule Risk Factors

- **RTL changes after PLACE_EXIT**: Major disruption; may require returning to FP_EXIT.
- **Timing closure difficulties**: PRO_EXIT often slips due to stubborn timing violations.
- **IP delivery delays**: Missing IP can block FP_EXIT and propagate through the schedule.
- **Tool bugs**: Unexpected tool behavior can delay any milestone.
- **Foundry rule changes**: Late rule deck updates can introduce new DRC violations.

## Best Practices

1. **Define milestones at project kickoff**: All stakeholders must agree on exit criteria before the flow begins.
2. **No exceptions without formal approval**: Advancing past a milestone with unmet criteria requires explicit management approval and documented risk acceptance.
3. **Two-week signoff window**: Budget at least two weeks between PRO_EXIT and MTO for final signoff iterations.
4. **Dry run**: Conduct a full tapeout dry run (practice MTO) 2-3 weeks before the actual MTO date to identify gaps.
5. **Post-mortem**: After MTO, conduct a review to document what went well, what went wrong, and what to improve for the next tapeout.
6. **Continuous tracking**: Use the regression infrastructure (see regression_methodology.md) to continuously monitor exit criteria progress, not just at milestone reviews.

Release management transforms tapeout from a chaotic sprint into a disciplined engineering process. Rigorous milestone management is what separates teams that tape out on schedule from those that suffer repeated delays.
