# CBflow Documentation

Complete documentation for CBflow v2.0.0 -- a comprehensive PD automation framework for ASIC physical design flows.

## What is CBflow?

CBflow is a Python/Bash/TCL automation framework that orchestrates ASIC physical design flows across Synopsys, Cadence, and Mentor tool suites. It provides:

- **RACE Engine**: Run Automation & Control Engine -- Python-native DAG executor that replaced GNU Make entirely. Builds DAG from node_config.tcl at runtime, tracks status in SQLite DB (sole status tracking -- no `.stamps/` directory), supports file change detection with automatic downstream retrace, parallel subnode execution, dynamic subnode generation, active engine sync (retrace/bypass/forcevalidate during execution), and dashboard auto-port (8080-8180 range).
- **12 Design Flows**: SYNTH, FP, PNR, STA, LEC, EMIR, PV, ECO, CLP, POPT, FCFP, SYNTH_PNR
- **Multi-Vendor Support**: Synopsys (FC, PT, Formality, ICV, RedHawk, VC_LP), Cadence (Genus, Innovus, Tempus, Conformal LP, Voltus), Mentor (Calibre)
- **153 Command Files**: FC-RM Y-2026.03 aligned, with per-stage reports, proper REPORTS_DIR/OUTPUTS_DIR
- **flow_proc Engine**: Auto-ordered registration, flow_exec_all, prepend/append/replace hooks
- **Override Hierarchy**: flow_config -> project_config -> tech_config -> user_config -> override_config -> override_setup
- **Release Mechanism**: `$release_path/$phase/$block_name/$release_tag` with mandatory file validation
- **Input Handshaking**: Release tag mode (`<flow>(input,<type>_release_tag)`) or direct path mode
- **Phase Milestones**: P0 (trial), P1 (impl), P2 (pre-signoff), P3 (tapeout) with 6 stage exits
- **LSF + XTerm Launch**: 6 queue tiers (S/M/L/XL/ultra), module loads, bsub+xterm wrapper
- **Email Notifications**: 6 templates (run-creation, run-status, run-summary, checklist, reminder, release-update)
- **AutoPPT Generation**: PD Run Summary matching template (19-col QoR table, per-stage slides)
- **Checklist CLI**: add-check (script/grep/file modes), list-checks, remove-check, status, sign-off, waivers
- **Per-Corner STA**: Each corner runs independently via dynamic timing_scenario handler
- **Test Suite**: 994 tests across 8 categories (`bin/cbflow-test-suite`)
- **Directory-Based Versioning**: Copy, edit, set-current via symlink (no Git worktrees)
- **3 Tech Configs**: GF 22FDX, TSMC 7nm, TSMC 5nm

## RACE Engine Overview

RACE (Run Automation & Control Engine) is the Python-native DAG executor at the core of CBflow v2.0.0. It completely replaces GNU Make -- Make is NOT used and NOT required.

- **DAG from node_config.tcl**: RACE builds the execution graph at runtime directly from node_config.tcl. There is no Makefile generation step.
- **SQLite DB for status tracking**: Each run stores status in a SQLite database (`.race_<uid>.db`). The `.stamps/` directory has been completely removed -- the RACE DB is the sole status tracking mechanism. DB path: `$project(race,db_path)/$project/$domain/$flow/$user_$run_$uid.db`
- **File change detection**: Edit an input file and RACE auto-retraces all downstream nodes.
- **Parallel subnode execution**: PV runs drc/lvs/erc/perc/xor in parallel after fill completes.
- **Dynamic MMMC scenario subnodes**: STA generates per-scenario subnodes from user_config at runtime, enabling parallel per-scenario execution.
- **Active engine sync**: Issue `retrace`, `bypass`, or `forcevalidate` commands while the engine is running -- the engine picks up changes from the DB in real time.
- **Dashboard auto-port**: The web dashboard automatically selects an available port in the 8080-8180 range, eliminating "Address already in use" errors.
- **Custom nodes at run level**: Use `add-node` and `create-branch` to extend the DAG without editing node_config.
- **Tested flows**: SYNTH_PNR, STA, LEC, CLP, SYNTH, PNR (6 flows fully tested)
- **Dispatcher config**: `set flow(dispatcher) "race"` in flow_config.tcl

## Quick Start

1. **[Kickstart Guide](00-kickstart/KICKSTART.md)** -- Copy to Unix, set PATH, run first flow (5 min)
2. **[Quick Start Guide](01-quick-start/README.md)** -- Installation, prerequisites, first run
3. **[User Guide](02-user-guide/README.md)** -- Daily workflows and operations
4. **[Examples](06-examples/basic-workflows.md)** -- SYNTH_PNR, STA, PV, checklist, release examples

## Documentation Sections

### [01. Quick Start](01-quick-start/)
- [Installation & Setup](01-quick-start/installation.md) -- Prerequisites and setup
- [System Requirements](01-quick-start/system-requirements.md) -- Tools, Python, LSF, disk
- [Your First Version](01-quick-start/first-version.md) -- Directory-based versioning intro

### [02. User Guide](02-user-guide/)
- [Complete User Guide](02-user-guide/cbflow-complete-user-guide.md) -- Full walkthrough
- [Flow User Guide](02-user-guide/cbflow-flow-user-guide.md) -- All 12 flows with stages
- [Release Management](02-user-guide/release-management.md) -- Phase/tag release workflow
- [Versioning Workflow](02-user-guide/versioning-workflow.md) -- Copy/edit/symlink
- [Troubleshooting](02-user-guide/troubleshooting.md) -- Common issues

### [03. Reference](03-reference/)
- [Configuration Reference](03-reference/configuration-reference.md) -- All config files
- [Python Scripts Reference](03-reference/python-scripts-reference.md) -- All 28 CLI modules
- [LSF Reference](03-reference/lsf-reference.md) -- LSF queue/resource config
- [MMMC Reference](03-reference/mmmc-reference.md) -- Multi-mode multi-corner

### [04. Architecture](04-architecture/)
- [System Design](04-architecture/system-design.md) -- RACE engine, flow_proc, override, release, handshake
- [Data Flow](04-architecture/data-flow.md) -- Data flow diagrams
- [Component Design](04-architecture/component-design.md) -- Module details

### [05. Developer Guide](05-developer/)
- [Contributing](05-developer/contributing.md) -- Contribution process
- [Extending CBflow](05-developer/extending.md) -- Adding flows, flow_procs, checks

### [06. Examples](06-examples/)
- [Basic Workflows](06-examples/basic-workflows.md) -- SYNTH_PNR, STA, PV, checklist
- [Release Workflows](06-examples/release-workflows.md) -- Release/handshake scenarios
- [Advanced Scenarios](06-examples/advanced-scenarios.md) -- Complex use cases

## Command Reference

### cbflow CLI

| Command | Purpose |
|---------|---------|
| `cbflow workspace create` | Create workspace and run directory |
| `cbflow workspace status` | Show workspace status |
| `cbflow run all` | Run complete flow |
| `cbflow run stage --name <stage>` | Run specific stage |
| `cbflow run status` | Show run progress (from RACE DB) |
| `cbflow run retrace --from <stage>` | Mark node and downstream for re-execution |
| `cbflow run bypass --node <node>` | Skip a node (mark as bypassed in RACE DB) |
| `cbflow run force --node <node>` | Force re-run a node regardless of status |
| `cbflow run forcevalidate --node <node>` | Force validate a specific node |
| `cbflow run forcevalidate --from X --to Y` | Force validate a range of nodes |
| `cbflow run forcevalidate --from X` | Force validate from node X to end |
| `cbflow run forcevalidate --to Y` | Force validate from start to node Y |
| `cbflow run checklist --milestone BTO --phase P3` | Run exit milestone checklist |
| `cbflow run email --to user@co.com --template run-status` | Send email notification |
| `cbflow run autoppt --format html` | Generate PD run summary |
| `cbflow run interactive --load place1` | Open interactive EDA session |
| `cbflow run logs --tail 50 --level ERROR` | View logs |
| `cbflow run report --node pro1` | Detailed node report |
| `cbflow run add-node --node <n> --type <t>` | Add custom node to DAG |
| `cbflow run create-branch --name <n>` | Create a flow branch |
| `cbflow run list-nodes` | List all nodes in DAG |
| `cbflow run show-graph` | Show flow dependency graph |
| `cbflow flow version copy --from v1.0.0 --to v1.0.1` | Copy version |
| `cbflow flow version set-current --version v1.0.1` | Set current version |
| `cbflow flow checklist add-check --milestone BTO ...` | Add exit check |
| `cbflow flow checklist list-checks --milestone BTO` | List checks |

### Flow Execution

| Command | Purpose |
|---------|---------|
| `cbflow run all` | Run complete flow end-to-end |
| `cbflow run stage --name place1` | Run single stage |
| `cbflow run retrace --from cts1` | Re-run from CTS onwards |
| `cbflow run bypass --node export_data1` | Skip a node |
| `cbflow run force --node place1` | Force re-run a node |
| `cbflow run forcevalidate --node signoff1` | Force validate a node |
| `cbflow run report --node pro1` | Detailed node report |
| `cbflow run show-graph` | Show flow dependency graph |

### Supported Flows (12)

| Flow | Description | Synopsys Tool | Cadence Tool |
|------|-------------|---------------|--------------|
| SYNTH | Synthesis | FC | Genus |
| FP | Floorplanning | FC | Innovus |
| PNR | Place & Route | FC | Innovus |
| STA | Static Timing Analysis | PT | Tempus |
| LEC | Logical Equivalence | Formality | -- |
| EMIR | EM/IR Analysis | RedHawk | Voltus |
| PV | Physical Verification | ICV | Calibre |
| ECO | Engineering Change Order | FC | -- |
| CLP | Clock Low Power | VC_LP | Conformal LP |
| POPT | Power Optimization | PT | -- |
| FCFP | Full Chip Floorplan | FC | Innovus |
| SYNTH_PNR | Unified Synth + PNR | FC | -- |

### Input Handshaking

```tcl
# Mode 1: Release tag (auto-resolves from release path)
set pnr(input,netlist_release_tag) "v1.0.2"
# Resolves: $project(release,path)/$phase/$block/v1.0.2/netlist/${design_name}.v

# Mode 2: Direct path
set pnr(input,netlist) "/proj/runs/synth_run1/outputs/top.v"
```

### Phase Milestones

| Phase | Stage Exits | Criteria |
|-------|-------------|----------|
| P0 | FP_EXIT | Relaxed (WNS -500ps, util 50%) |
| P1 | PLACE_EXIT, CTS_EXIT | Converging (WNS -80ps) |
| P2 | PRO_EXIT, BTO | Tight (WNS 0, DRC 0, LVS clean) |
| P3 | MTO | Tapeout (all zero, GDS clean) |

### Checklist Management

```bash
# Add a grep-based check
cbflow flow checklist add-check --milestone BTO \
  --name drc_zero --check-type mandatory \
  --description "DRC violations must be zero" \
  --grep-file "work/SYNTH_PNR/signoff1/reports/signoff_check_drc.rpt" \
  --grep-pattern "Total.*0.*violation" --grep-pass-if found

# Run checklist against current run
cbflow run checklist --milestone PRO_EXIT --phase P2

# Sign off
cbflow run checklist --milestone BTO --sign-off --approver chip_lead
```

## Technology Configs

| Config | Technology |
|--------|-----------|
| `gf_22nm` | GlobalFoundries 22FDX |
| `tsmc_7nm` | TSMC N7 |
| `tsmc_5nm` | TSMC N5 |

## Test Suite

```bash
bin/cbflow-test-suite                    # 994 tests, 8 categories
bin/cbflow-test-suite --verbose          # Show all PASS/FAIL/SKIP
bin/cbflow-test-suite --category 2       # Run specific category
bin/cbflow-test-suite --flow SYNTH_PNR   # Test single flow
```

Categories: Workspace, RACE DAG/Handlers, Override Mechanism, LSF, MMMC, Mandatory I/O, Log Parsing, Cross-Cutting.

## Shell Tab Completion

```bash
# Bash
source $CBFLOW_HOME/completions/cbflow.bash

# Zsh
fpath=($CBFLOW_HOME/completions $fpath)
autoload -Uz compinit && compinit
```

---

**Documentation Version**: 2.0.0
**Last Updated**: 2026-05-12

**Ready to start?** Begin with [Kickstart Guide](00-kickstart/KICKSTART.md)
