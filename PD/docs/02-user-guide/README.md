# User Guide

Complete guide to using CBflow v2.0.0 for ASIC physical design automation.

## Overview

This guide covers daily workflows for running design flows, managing configurations, tracking QoR, and using directory-based versioning across the CBflow framework. CBflow v2.0.0 supports 12 design flows spanning the full PD lifecycle from synthesis through tapeout.

## Contents

### [CBflow Complete User Guide](cbflow-complete-user-guide.md)
Comprehensive reference covering the entire system:
- Architecture and directory structure
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
- Per-corner STA (no MMMC stage)
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

### [Troubleshooting](troubleshooting.md)
Common issues and solutions:
- Flow execution failures
- LSF job issues
- Configuration and versioning problems
- Stamp file and dependency issues

### v1.0.0 Makefile Guides
Legacy makefile documentation for reference:
- [v1.0.0 README](v1.0.0/README.md) -- Makefile guide index
- [Core Makefile Guide](v1.0.0/core-makefile-guide.md) -- System management commands
- [Run Makefile Guide](v1.0.0/run-makefile-guide.md) -- Flow execution and stage management
- [Workspace Makefile Guide](v1.0.0/workspace-makefile-guide.md) -- Workspace and run initialization

## Quick Reference

### Workspace and Run Management
```bash
# Create workspace and run
cbflow workspace create --config user_config.tcl
cbflow workspace create --config user_config.tcl --force
cbflow workspace status

# Execute flows
cbflow run all
cbflow run stage --name place1
cbflow run status
cbflow run logs --tail 50 --level ERROR

# Interactive session
cbflow run interactive --load place1

# Email and reporting
cbflow run email --to user@co.com --template run-status
cbflow run autoppt --format pptx

# Checklist
cbflow run checklist
cbflow flow checklist add-check --name timing_met --mode script --script check_timing.sh
cbflow flow checklist sign-off --milestone CTS_EXIT
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
- [Architecture](../04-architecture/) -- System design and internals
- [Developer Guide](../05-developer/) -- Contributing and extending

### Test Suite
```bash
bin/cbflow-test-suite    # 994 tests covering all flows and commands
```

---

**Ready to start?** Begin with the [Complete User Guide](cbflow-complete-user-guide.md) for a full walkthrough, or jump to the [Flow User Guide](cbflow-flow-user-guide.md) for per-flow details.
