# Reference Documentation

Complete technical reference for CBflow v2.0.0 PD automation framework.

## Contents

### [Configuration Reference](configuration-reference.md)

All configuration files in the CBflow system:

- **flow_config.tcl** -- 12 flow types, flow(dispatcher)="race", flow(use_lsf), flow(use_xterm), email config (smtp_server/port/tls/auth/from/cc/recipients, on_run_create/complete/fail triggers), autoppt config, MMMC settings, logging
- **tool_launch_config.tcl** -- module loads for 9 EDA tools (fc, pt, fm, vc_lp, icv, redhawk, genus, innovus, tempus), tool shell commands, bsub defaults, 5 queue types (S:8GB/4cpu, M:16GB/8cpu, L:32GB/16cpu, XL:64GB/32cpu, ultra:128GB/64cpu), flow-to-queue mappings
- **release_config.tcl** -- release_exit_files per flow/phase/milestone, phase_criteria thresholds, milestone_flow_map, flow_input_handshake
- **mmmc_config.tcl** -- 19 analysis views, 3 process corners, 2 operating modes, 3 RC corners, 8 scenario sets, per-node assignments, library_sets
- **12 node configs** -- stages, dependencies, stage_types, node_types, work_dirs, timeouts, release_types, mandatory_input_groups (consumed by RACE to build DAG)
- **3 tech configs** -- gf_22nm, tsmc_7nm, tsmc_5nm
- **2 project configs** -- phoenix, ravendrive (with project(release,path/phase/block_name/tag))
- **6 exit configs** -- FP_EXIT, PLACE_EXIT, CTS_EXIT, PRO_EXIT, BTO, MTO (plus waivers, thresholds, remediation)

### [Python Scripts Reference](python-scripts-reference.md)

All 28 Python CLI modules:

- **run_cmd.py** -- 23 subcommands: all, stage, status, report, retrace, bypass, force, forcevalidate, clean, validate, logs, show-graph, list-nodes, list-branches, release-info, verify-dag, lsf-status, interactive, email, autoppt, checklist, help, add-node, delete-node, create-branch, delete-branch, update
- **workspace_cmd.py** -- create, status
- **checklist_cmd.py** -- generate, status, sign-off, list, list-checks, add-check, remove-check, waiver
- **email_cmd.py** -- 6 templates (run-creation, run-status, run-summary, checklist, reminder, release-update), preview mode, attachments
- **autoppt_cmd.py** -- html/pptx format, 5 slides (summary QoR table, place, CTS, ctsOpt, routeOpt)
- **release_cmd.py, version_cmd.py, flow_cmd.py, config_cmd.py, project_cmd.py**
- **lsf_cmd.py, lsf_manager_cmd.py**
- **library_manager_cmd.py, mmmc_manager_cmd.py**
- **log_viewer.py, race_engine.py, validation_cmd.py**
- **qor_report_cmd.py, dashboard_cmd.py, trending_cmd.py, metrics_cmd.py**
- **tcl_config_parser.py, logging_config.py, node_manager.py, graph_renderer.py, start_run.py, plugin_cmd.py**

### [LSF Reference](lsf-reference.md)

LSF (Load Sharing Facility) integration:
- 4 launch modes (local, xterm, LSF batch, LSF+xterm)
- 5 queue tiers (S, M, L, XL, ultra)
- Flow-to-queue mapping for all 12 flows
- bsub command construction
- Module load commands for 9 EDA tools

### [MMMC Reference](mmmc-reference.md)

Multi-Mode Multi-Corner analysis:
- PVT corner definitions (SS, TT, FF)
- Voltage, temperature, and RC corners
- Scenario naming convention
- Predefined scenario sets (setup, hold, power, signoff, all, sta_setup, sta_hold, sta_signoff)
- Per-node scenario assignments
- MMMC behavior in each flow (SYNTH, PNR, STA, SYNTH_PNR)
- MMMC Manager CLI commands
- Analysis view structure

### [Git Reference](git-reference.md)

Git branching, tagging, and versioning conventions:
- Branch naming scheme (version, current, workspace)
- Tag naming scheme (component tags, release tags)
- Directory-based versioning (copy, edit, set-current via symlink)
- Git worktree structure for isolated development

---

## Supported Flows (12)

| Flow | Description | Tool |
|------|-------------|------|
| SYNTH | Logic synthesis | Fusion Compiler / Genus |
| FP | Floorplanning | Fusion Compiler / Innovus |
| PNR | Place and route | Fusion Compiler / Innovus |
| STA | Static timing analysis | PrimeTime / Tempus |
| LEC | Logical equivalence checking | Formality |
| EMIR | EM/IR drop analysis | RedHawk |
| PV | Physical verification (DRC/LVS/ERC/PERC/XOR/fill) | ICV |
| ECO | Engineering change orders | Fusion Compiler |
| CLP | Conformal low power verification | VC LP |
| POPT | Power optimization | Fusion Compiler |
| FCFP | Fullchip floorplanning | Fusion Compiler |
| SYNTH_PNR | Unified synthesis to signoff | Fusion Compiler |

FCT and PHYV have been removed in v2.0.0 (merged into STA and PV respectively).

---

## Quick Command Lookup

### Run Management

```bash
cbflow run all                                 # Run complete flow (RACE DAG)
cbflow run stage --name <stage>                # Run single stage
cbflow run status [--details]                  # Show status (from RACE DB)
cbflow run report [--node <node>]              # Detailed report
cbflow run retrace [--from <stage>] [--run]    # Retrace and rerun
cbflow run bypass --node <node>                # Skip a node
cbflow run force --node <node>                 # Force re-run a node
cbflow run forcevalidate --node <node>         # Force validate specific node
cbflow run forcevalidate --from X --to Y       # Force validate range
cbflow run forcevalidate --from X              # Force validate from X to end
cbflow run forcevalidate --to Y                # Force validate start to Y
cbflow run clean                               # Clean run directory
cbflow run validate                            # Validate run
cbflow run logs [--tail N] [--level ERROR]     # View logs
cbflow run show-graph [--detail]               # Visualize RACE DAG
cbflow run list-nodes                          # List nodes
cbflow run list-branches                       # List branches
cbflow run release-info                        # Release info
cbflow run verify-dag                          # Verify DAG from node_config
cbflow run lsf-status                          # LSF job status
cbflow run interactive                         # Interactive tool session
cbflow run email --template <template>         # Send email
cbflow run autoppt [--format pptx|html]        # Generate PPT/HTML
cbflow run checklist --milestone <M> --phase <P>  # Exit checklist
cbflow run add-node --node <n> --type <t>      # Add custom node
cbflow run delete-node --node <n>              # Delete node
cbflow run create-branch --name <n>            # Create branch
cbflow run delete-branch --name <n>            # Delete branch
cbflow run update [--version <v>]              # Update run
cbflow run help                                # Full documentation
```

### Component Versioning

```bash
cbflow flow version copy --dir <dir> --from <v1> --to <v2>
cbflow flow version set-current --dir <dir> --version <v>
cbflow flow version list --dir <dir>
cbflow flow version diff --dir <dir> --v1 <v1> --v2 <v2>
```

---

## See Also

- [Quick Start](../01-quick-start/) -- Getting started
- [User Guide](../02-user-guide/) -- Workflows and usage
- [Architecture](../04-architecture/) -- RACE engine and system design
- [Developer Guide](../05-developer/) -- Contributing
- [Examples](../06-examples/) -- Real-world scenarios

---

**CBflow v2.0.0 Reference Documentation**
