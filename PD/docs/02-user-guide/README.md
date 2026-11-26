# User Guide

Complete guide to using CBflow v2.0.0 for ASIC physical design automation (open-source sky130 flows: [Open-Source Flow Guide](opensource-flow-guide.md); spec-to-GDS: [Spec-to-GDS Guide](spec-to-gds-guide.md)).

## Overview

This guide covers daily workflows for running design flows, managing configurations, tracking QoR, and using directory-based versioning across the CBflow framework. CBflow v2.0.0 supports 12 PD design flows (33 flow types across PD/DFT/DV/RTL — `cbflow flow types`) spanning the full PD lifecycle from synthesis through tapeout, all orchestrated by the RACE (Run Automation & Control Engine) dispatcher.

## RACE Engine

CBflow v2.0.0 uses RACE as its sole dispatcher. RACE is a Python-native DAG executor that:

- Builds the execution DAG from the node configs (`<FLOW>_config.tcl` + `<FLOW>_<tool>_config.tcl`) at runtime (no Makefile)
- Tracks all node status in a SQLite database (`.race_<run_dir>_<user>_<hash>.db` in `project(race,db_path)`, pointer `.race_db_pointer` in the run)
- Runs independent nodes / subnodes in parallel (capped by `flow(max_parallel_jobs)`)
- Generates dynamic subnodes (e.g., STA per MMMC scenario)
- Supports custom nodes at run level (`add-node`, `set-dep`, `create-branch`)

## Contents

### [CBflow Complete User Guide](cbflow-complete-user-guide.md)
Comprehensive reference covering the entire system:
- RACE engine architecture and DAG execution
- CLI command reference (workspace, run, flow)
- Supported flows with stage lists
- Configuration hierarchy and override system
- LSF resource management and queue tiers
- Input handshaking and release path conventions
- Email, AutoPPT, and checklist features

### [CBflow Flow User Guide](cbflow-flow-user-guide.md)
Detailed per-flow guide for all 12 design flows:
- SYNTH, FP, PNR, STA, LEC, EMIR, PV, ECO, CLP, POPT, FCFP, SYNTH_PNR — stages and required inputs
- Launch mode (test_mode / use_lsf / use_xterm), LSF tiers
- Custom nodes, set-dep, branches
- Commercial milestone releases and release-check

### [Versioning Workflow](versioning-workflow.md)
Directory-based version management:
- Copy a version directory
- Edit configuration or scripts
- Set-current via symlink promotion
- List and compare versions
- No Git worktrees -- pure directory operations

### [Release Management](release-management.md)
System-wide release management:
- Creating releases (auto and config modes)
- Design release path: `$project(release,path)/$phase/$block_name/<FLOW>/$release_tag` (see [Exit Release Guide](exit-release-guide.md))
- Generating and validating release configurations
- Viewing release information and comparing releases

### [CHANGELOG System](changelog-system.md)
Automated change tracking:
- Component CHANGELOGs
- Release CHANGELOGs
- Read-only, system-generated files

### [Dashboard Daemon Guide](dashboard-daemon-guide.md) *(new in v2.1.1; enhanced 2026-07-10)*
Per-user web dashboard daemon:
- One process serves all runs (replaces per-run foreground server)
- Deterministic per-user port (`flow(dashboard,port_base,<DISC>) + uid % flow(dashboard,port_width)`, PD: 9000 + uid%300)
- In-browser Register / Browse / Deregister UI
- One daemon per discipline (PD 9000, DFT 9300, DV 9600, RTL 9900 + uid % 300)
- SSH-tunnel auto-detection and CLI lifecycle (`cbflow run dashboard ...`)
- **New (2026-07-10):** Adaptive polling with ETag support, topological DAG layout, framework-config auto-refresh
- Troubleshooting common issues

### [SmartGrid / Project Dashboard Guide](project-dashboard-guide.md) *(updated 2026-11)*
Per-project dashboard of published releases:
- `cbflow smartgrid start --project <p>` (port `25000 + md5(uid:project) % 2500`)
- Published runs per flow; signoff runs (STA/PV/LEC) on their own pages
- Exit-centric releases page (block × exit matrix, signoff chips, order badge)
- Project page: one card per discipline (live / offline, Summary, Run dashboard) + Releases / Spec-to-GDS chain / Checklist / Schedule / Team tiles
- Checklist waivers, DEF viewer with IO pins, timing stage/corner filter, schedule

### [Exit Release Guide](exit-release-guide.md) *(new 2026-11)*
Design releases to exit milestones:
- Layout `<release,path>/<phase>/<block>/<FLOW>/<exit>`; the release exit follows the source stage
- Releasing an intermediate stage (bypass / `cbflow run set-dep` / add-node)
- Exit-named tags and `cbflow run release --clone-from`
- Exit plans per discipline (`project(phase_exits)`, `project(phase_exits,DV)`), exit-order gates
- Strict signoff inputs, release-node form, per-node overrides

### [Open-Source Flow Guide](opensource-flow-guide.md) *(new 2026-11)*
RTL-to-GDS on sky130 with the `opensource` vendor:
- Yosys / OpenROAD / OpenSTA / KLayout + Magic + Netgen through `cbflow-oss`
- opensky hierarchy and the OSS0/OSS1/OSS2 library tags
- DFT, clock gating, multi-Vt, SRAM macros, floorplan / STA / PV options
- Workarea scripts (`run_p1_dl3.sh`, `run_p1_dl2.sh`, `run_signoff.sh`, release tests)

### [Library Manager Guide](library-manager-user-guide.md)
Library tags (`<lib_tag_root>/<tech>/<TAG>/`): `generate`, `add --category block|memory` (SPEF linking, `--pv-pending`),
`check --lib_tag` (required views per category; design netlist / RTL vs the tag), `status --lib_tag`.

### [MMMC Manager Guide](mmmc-manager-user-guide.md)
`mmmc_config.tcl` generation, scenario sets, per-node scenarios, Cadence view definition.

### [GUI User Guide](cbflow-gui-user-guide.md)
The run dashboard: DAG, action bar, multi-select, Set Dependencies…, MMMC dialog, release-node form.

### [SmartGenie User Guide](smartgenie-user-guide.md)
The AI assistant (local / hybrid / cloud) and its MCP tools.

### [Troubleshooting](troubleshooting.md)
Common issues and solutions:
- Workspace create pre-flight (bsub / xterm), ownership, re-running
- Input handshakes and strict signoff inputs
- Exit order and publish refusals
- Library tags, dashboards, framework versioning

## Quick Reference

### Workspace and Run Management
```bash
# Create workspace and run
cbflow workspace create --config user_config.tcl
cbflow workspace create --config user_config.tcl --force
cbflow workspace status

# Execute flows (via RACE DAG)
cbflow run all
cbflow run stage --name place1
cbflow run status
cbflow run logs --tail 50 --level ERROR

# Execution control
cbflow run retrace --from cts1
cbflow run bypass --stages export_data1
cbflow run force --stages place1
cbflow run forcevalidate --node signoff1
cbflow run forcevalidate --from place1 --to pro1
cbflow run forcevalidate --from place1
cbflow run forcevalidate --to pro1

# Interactive session
cbflow run interactive --node place1

# Email and reporting
cbflow run email --to user@co.com --template run-status
cbflow run autoppt --format pptx

# Checklist
cbflow run checklist --milestone CTS_EXIT --phase P2
cbflow flow checklist add-check --milestone CTS_EXIT --name timing_met --type mandatory \
    --script check_timing.tcl --criteria "setup_wns >= 0"
cbflow flow checklist sign-off --milestone CTS_EXIT --run-dir . --approver chip_lead

# DAG management
cbflow run add-node --node export_data2 --type export_data --dep place1
cbflow run set-dep --node export_data1 --deps place1
cbflow run create-branch --branch experimental --from cts1
cbflow run list-nodes
cbflow run show-graph
```

### Versioning (Directory-Based)
```bash
# Copy version
cbflow flow version copy --dir config --from v1.0.0 --to v1.0.1

# Edit files in the new version directory
# ... edit config/v1.0.1/* ...

# Set as current (creates symlink)
cbflow flow version set-current --dir config --version v1.0.1

# List and compare versions
cbflow flow version list --dir config
cbflow flow version diff --dir config --v1 v1.0.0 --v2 v1.0.1
```

### Releases (exit milestones)
```bash
cbflow run set-dep --node export_data1 --deps place1      # release place -> PLACE_EXIT
cbflow run stage --name release_data1
cbflow run release --from-run . --node release_data1 --publish
cbflow run release --from-run . --clone-from BTO --tag MTO --publish
cbflow run release-check --tag PRO_EXIT --project opensky --phase P2
```

### Libraries and dashboards
```bash
cbflow flow library-manager check  --tech skywater_130nm --lib_tag OSS2
cbflow flow library-manager status --tech skywater_130nm --project opensky --lib_tag OSS2
cbflow run gui                                   # run dashboard (per-user, per-discipline daemon)
cbflow smartgrid start --project opensky         # SmartGrid project dashboard
```

### Input Handshaking
```bash
# Option 1: Reference a release tag (preferred)
set pnr(input,release_tag)          "P1_SYNTH_v1"   ;# every input from one tag
set pnr(input,def_file_release_tag) "FP_EXIT"       ;# one input from another tag

# Option 2: Direct path
set pnr(input,netlist) "/path/to/synthesized_netlist.v"
```

## Getting Help

### Documentation
- [Quick Start](../01-quick-start/) -- Getting started
- [Reference](../03-reference/) -- Configuration and script reference
- [Examples](../06-examples/) -- Real-world workflows

### Advanced Topics
- [Architecture](../04-architecture/) -- RACE engine design and system internals
- [Developer Guide](../05-developer/) -- Contributing and extending

### Test Suite
```bash
cbflow test --static      # static categories (see ../05-developer/test-suite.md)
cbflow test --hardcode    # opt-in no-hardcode audit
```

---

**Ready to start?** Begin with the [Complete User Guide](cbflow-complete-user-guide.md) for a full walkthrough, or jump to the [Flow User Guide](cbflow-flow-user-guide.md) for per-flow details.
