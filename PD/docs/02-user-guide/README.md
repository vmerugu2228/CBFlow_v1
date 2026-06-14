# User Guide

Complete guide to using CBflow v2.0.0 for ASIC physical design automation.

## Overview

This guide covers daily workflows for running design flows, managing configurations, tracking QoR, and using directory-based versioning across the CBflow framework. CBflow v2.0.0 supports 12 design flows spanning the full PD lifecycle from synthesis through tapeout, all orchestrated by the RACE (Run Automation & Control Engine) dispatcher.

## RACE Engine

CBflow v2.0.0 uses RACE as its sole dispatcher. RACE is a Python-native DAG executor that:

- Builds the execution DAG from `node_config.tcl` at runtime (no Makefile generation)
- Tracks all node status in a SQLite database (`.race_<uid>.db`)
- DB path: `$project(race,db_path)/$project/$domain/$flow/$user_$run_$uid.db`
- Detects file changes on inputs and auto-retraces downstream nodes
- Runs independent subnodes in parallel (e.g., PV: drc/lvs/erc/perc/xor)
- Generates dynamic subnodes (e.g., STA per-corner from user_config)
- Supports custom nodes at run level (`add-node`, `create-branch`)

Configure in flow_config.tcl: `set flow(dispatcher) "race"`

## Contents

### [CBflow Complete User Guide](cbflow-complete-user-guide.md)
Comprehensive reference covering the entire system:
- RACE engine architecture and DAG execution
- CLI command reference (workspace, run, flow)
- All 12 supported flows with stage details
- Configuration hierarchy and override system
- LSF resource management and queue tiers
- Input handshaking and release path conventions
- Email, AutoPPT, and checklist features

### [CBflow Flow User Guide](cbflow-flow-user-guide.md)
Detailed per-flow guide for all 12 design flows:
- SYNTH, FP, PNR, STA, LEC, EMIR, PV, ECO
- CLP, POPT, FCFP, SYNTH_PNR
- Stage dependency diagrams and subnode details
- Input variables and key outputs per flow
- Per-corner STA (dynamic subnodes, no MMMC stage)
- ICV PV parallel verification pipeline

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
- Release path: `$project(release,path)/$phase/$block_name/$release_tag`
- Generating and validating release configurations
- Viewing release information and comparing releases

### [CHANGELOG System](changelog-system.md)
Automated change tracking:
- Component CHANGELOGs
- Release CHANGELOGs
- Read-only, system-generated files

### [Dashboard Daemon Guide](dashboard-daemon-guide.md) *(new in v2.1.1)*
Per-user web dashboard daemon:
- One process serves all runs (replaces per-run foreground server)
- Deterministic per-user port (9000 + uid%1000)
- In-browser Register / Browse / Deregister UI
- SSH-tunnel auto-detection and CLI lifecycle (`cbflow dashboard ...`)
- Troubleshooting common issues

### [Troubleshooting](troubleshooting.md)
Common issues and solutions:
- Flow execution failures
- LSF job issues
- Configuration and versioning problems
- RACE DB and node status issues

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
cbflow run bypass --node export_data1
cbflow run force --node place1
cbflow run forcevalidate --node signoff1
cbflow run forcevalidate --from place1 --to pro1
cbflow run forcevalidate --from place1
cbflow run forcevalidate --to pro1

# Interactive session
cbflow run interactive --load place1

# Email and reporting
cbflow run email --to user@co.com --template run-status
cbflow run autoppt --format pptx

# Checklist
cbflow run checklist
cbflow flow checklist add-check --name timing_met --mode script --script check_timing.sh
cbflow flow checklist sign-off --milestone CTS_EXIT

# DAG management
cbflow run add-node --node eco1 --type export_data --dep signoff
cbflow run create-branch --name experimental
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

### Input Handshaking
```bash
# Option 1: Reference a release tag (preferred)
set pnr(input,netlist_release_tag) "v1.0.2"

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
bin/cbflow-test-suite    # 994 tests covering all flows and commands
```

---

**Ready to start?** Begin with the [Complete User Guide](cbflow-complete-user-guide.md) for a full walkthrough, or jump to the [Flow User Guide](cbflow-flow-user-guide.md) for per-flow details.
