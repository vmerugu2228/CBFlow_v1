# PD Project Management

## Overview

Physical design project management requires a unique blend of technical depth and organizational discipline. Unlike software projects, PD timelines are driven by silicon schedules with immovable tapeout deadlines, and late discoveries can cost weeks of rework. Effective PD project management means structuring teams, tracking milestones, allocating tasks, and managing risk in a way that accounts for the iterative and deeply interdependent nature of physical design work.

## Team Structure

### PD Lead

The PD lead owns the overall physical implementation schedule and quality-of-results (QoR). Responsibilities include:

- Defining the floorplan strategy and block partitioning
- Setting timing, power, and area targets per milestone
- Reviewing QoR dashboards and making go/no-go decisions at each gate
- Interfacing with architecture, RTL, DFT, IP integration, and foundry teams
- Escalating risk items and resource conflicts to the program manager

A strong PD lead understands both the tool flow and the underlying silicon physics. They make architectural tradeoff decisions (e.g., accepting a utilization increase to close timing) that junior engineers cannot.

### PD Engineers

PD engineers execute the implementation. Depending on project size, roles may be specialized:

- **Floorplan engineer**: Partition placement, macro placement, pin assignment, power grid design
- **Timing engineer**: Constraint development, STA signoff, ECO management
- **Clock engineer**: Clock tree synthesis, skew balancing, clock domain crossing verification
- **Routing/DRC engineer**: Detail routing, DRC/LVS closure, metal fill, antenna fixing
- **Power engineer**: IR drop analysis, EM analysis, power optimization (clock gating, MTCMOS)

On smaller teams one engineer may cover multiple areas. On large SoCs with 50+ blocks, each block may have a dedicated PD engineer with specialists handling chip-level integration.

### CAD Engineers

CAD engineers build and maintain the flow infrastructure:

- Tool installation, licensing, and version qualification
- Flow scripting (TCL/Python/Make) for synthesis, PnR, and signoff
- Reference flow development and methodology documentation
- Regression and QoR tracking automation
- Debug support for tool crashes, convergence issues, and methodology questions

The CAD/PD boundary varies by organization. In some teams, senior PD engineers write their own scripts; in others, CAD owns all automation and PD engineers interact through standardized interfaces.

### Supporting Roles

- **Library/IP team**: Provide timing models (.lib), physical abstractions (LEF), and integration guides
- **DFT engineers**: Deliver scan chain insertion constraints, BIST logic, and ATPG patterns
- **Package/board engineers**: Define bump maps, package parasitics, and board-level constraints
- **Verification engineers**: Provide formal/simulation sign-off for ECOs and late netlist changes

## Task Allocation Strategies

### Block-Based Allocation

Assign each block to a dedicated engineer who owns it from floorplanning through signoff. This builds deep knowledge of the block's characteristics but can create bottlenecks if one block is harder than expected.

### Phase-Based Allocation

Assign engineers by implementation phase (e.g., one team handles all floorplans, another handles all CTS). This promotes methodology consistency but can lose context when handing off between phases.

### Hybrid Model

Most mature teams use a hybrid: block ownership for large or critical blocks, with specialist overlays for timing closure, power, and signoff. The PD lead triages daily, shifting resources to the critical path.

### Key Allocation Principles

- Assign the most experienced engineer to the hardest block, not the biggest one
- Pair junior engineers with mentors on non-critical blocks for training
- Keep a "float" engineer unassigned to handle late surprises and ECOs
- Rotate signoff review duties to prevent single-point-of-failure knowledge

## Milestone Tracking

### Typical PD Milestones

| Milestone | Key Deliverables |
|-----------|-----------------|
| M0: Kickoff | Constraints received, flow qualified, floorplan exploration started |
| M1: Floorplan freeze | Macro placement, power grid, pin assignment approved |
| M2: Placement done | Placement complete, initial timing assessment, congestion acceptable |
| M3: CTS done | Clock tree built, post-CTS timing met with margin |
| M4: Route done | Detail routing complete, DRC < threshold, timing converging |
| M5: Pre-signoff | All signoff checks running, ECO pipeline active |
| M6: Signoff | All checks clean, GDSII generated, LVS/DRC/ERC clean |
| M7: Tapeout | Final GDSII delivered to foundry |

### Milestone Gates

Each milestone should have explicit entry and exit criteria. For example, M4 exit criteria might be:

- WNS > -50ps (with known waiver list)
- DRC count < 500 (excluding fill-related)
- IR drop within 5% of target
- LVS clean at block level
- No remaining hold violations after CTS

### Tracking Mechanisms

- **Daily standup**: 15-minute sync on blockers and progress
- **Weekly QoR review**: Formal review of timing/power/area dashboards with the full team
- **Milestone gate review**: Formal sign-off meeting with stakeholders before proceeding
- **Risk register**: Maintained by the PD lead, reviewed weekly

## Risk Management

### Common PD Risks

**Schedule Risks**
- Late RTL freeze or frequent ECOs after netlist handoff
- Library/IP delivery delays (missing .lib corners, wrong LEF abstractions)
- Tool bugs requiring workarounds or version changes mid-project
- Underestimated block complexity leading to timing closure difficulty

**Technical Risks**
- Congestion hotspots requiring floorplan rearchitecture
- IR drop violations requiring power grid redesign
- Clock skew issues from poor CTS constraints or topology
- Electromigration failures discovered late in signoff
- Antenna violations requiring extensive rerouting

**Resource Risks**
- Key engineer departure or reassignment
- License shortages during crunch periods
- Compute infrastructure limitations (disk space, memory, CPU)
- Dependency on external teams (DFT, verification) missing their deadlines

### Risk Mitigation Strategies

1. **Early prototyping**: Run a fast, low-effort implementation early to identify showstoppers before committing to a floorplan
2. **Margin budgeting**: Build 5-10% margin into timing targets at each stage; do not plan to use every last picosecond
3. **Parallel exploration**: Run 2-3 floorplan variants in parallel during early stages rather than committing to one
4. **Incremental signoff**: Run signoff checks incrementally (not just at the end) to catch issues while they are still cheap to fix
5. **ECO discipline**: Establish a formal ECO request and approval process; uncontrolled ECOs are the top schedule killer
6. **Automation investment**: Automate repetitive tasks (regression runs, QoR collection, report generation) to free engineer time for debug
7. **Cross-training**: Ensure at least two engineers can work on any critical block to prevent single-point-of-failure

### Risk Register Template

| Risk ID | Description | Probability | Impact | Mitigation | Owner | Status |
|---------|-------------|-------------|--------|------------|-------|--------|
| R01 | Late RTL ECO after M3 | High | High | Freeze agreement with RTL lead | PD Lead | Open |
| R02 | Memory macro LEF delay | Medium | High | Use placeholder, parallel track with IP team | IP Lead | Monitoring |
| R03 | Routing congestion in DSP block | High | Medium | Explore 2 floorplan variants | PD Eng A | Active |

## Communication Patterns

### Cross-Functional Interfaces

PD does not operate in isolation. Establish regular sync points with:

- **RTL team**: Weekly sync on netlist changes, synthesis warnings, design intent
- **DFT team**: Bi-weekly sync on scan chain status, BIST integration, test coverage
- **Verification team**: As-needed sync on ECO functional verification
- **Package team**: Monthly sync on bump map, RDL routing, package parasitics
- **Foundry**: As-needed for DRC waiver requests, tech file updates, and IPD questions

### Escalation Path

Define a clear escalation path before the project starts. When a block misses a milestone:

1. PD engineer raises the issue in daily standup
2. PD lead assesses impact and attempts local mitigation (extra resources, modified approach)
3. If unresolvable within one week, escalate to program manager with options and recommendations
4. Program manager decides: accept schedule slip, add resources, or descope features

## Lessons Learned

After every tapeout, conduct a retrospective covering:

- What went well (replicate in next project)
- What went poorly (root cause and corrective action)
- Tool and flow improvements identified
- Estimation accuracy (planned vs. actual effort per block)
- Risk register review (which risks materialized, which mitigations worked)

Document findings and feed them into the next project's planning phase. The best PD organizations treat every tapeout as a learning opportunity that improves the next one.
