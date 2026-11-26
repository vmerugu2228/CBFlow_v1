# Reference Documentation

Complete technical reference for CBflow v2.0.0 (PD-focused; the CLI reference covers every discipline).

## Contents

### [Configuration Reference](configuration-reference.md)

All configuration files in the CBflow system, resolved in cascade order
(global project → discipline overlay → global tech → flow_registry →
discipline flow_config → node config + tool overlay → mmmc → user_config →
override_config.*):

- **global/config/** -- `flow/v1.0.0/flow_registry.tcl` (33 flow types, discipline map, launch defaults, dashboard ports), `tech/<node>/v1.0.0/tech_config.tcl` (gf_22nm, gf_28nm, skywater_130nm, tsmc_5nm, tsmc_7nm), `project/<p>/v1.0.0/` (bumblebee, denali, opensky, phoenix: identity, hierarchy, phases / phase_exits, MMMC), `exit/v1.0.0/` (PD / DFT / DV / RTL exit milestones, STA_SIGNOFF, waivers)
- **PD/config/** -- project overlay `<p>_pd_config.tcl` (workarea, release, lsf, lib_root / lib tag), `flow/v1.0.0/` (flow_config, release_config with MILESTONE_ORDER and flow_input_handshake, lsf_config, tool_launch_config, node_configs incl. open-source `<FLOW>_<tool>_config.tcl` overlays)
- **DFT/ DV/ RTL config/** -- each discipline's flow_config + node_configs

### [Command Reference](command-reference.md)

Every `cbflow` command and flag, checked against `--help`: workspace, run
(incl. set-dep, bypass, release `--from-run/--node/--clone-from/--publish/--no-publish/--override`),
run dashboard (`--discipline`), smartgrid, flow (checklist, library-manager,
mmmc-manager, …), test, migrate, bundle, cbflow-oss.

### [Python Scripts Reference](python-scripts-reference.md)

Which module implements each command (`global/utils/commands/` vs
`PD/utils/commands/`) and the helper libraries (race_engine, start_run,
node_manager, …).

### [RACE Engine Command Reference](makefile-reference.md)

Execution, status, flow-control and DAG-editing commands in RACE terms, active
engine sync, RACE DB, tool-config conventions.

### [Production Dashboard Setup](dashboard-production-setup.md)

Remote access to the run dashboard / SmartGrid daemons, ports, bind flags.

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

## Supported PD Flows (12)

All 33 flow types (PD 12, DFT 7, DV 9, RTL 5): `cbflow flow types`. PD flows also run on the open-source sky130 tools (yosys / OpenROAD / OpenSTA / KLayout / Magic + Netgen) for project `opensky`.

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

Stages are node names (`place1`, `cts1`, …; `cbflow run list-nodes`). Full flag
lists: [Command Reference](command-reference.md).

### Run Management (inside a run directory)

```bash
cbflow run all [--validate] [--lsf --queue XL]   # Run complete flow (RACE DAG)
cbflow run stage --name place1                   # Run single stage
cbflow run status [--details]                    # Status (from RACE DB)
cbflow run report [--node place1]                # Detailed report
cbflow run retrace [--from cts1] [--run]         # Invalidate (and rerun)
cbflow run bypass --stages cts1,route1           # Mark stages done without running
cbflow run force --stages place1                 # Re-run only these stages
cbflow run forcevalidate --node place1           # Mark a stage done
cbflow run forcevalidate --from X --to Y         # ... a range (--from X / --to Y alone too)
cbflow run add-node --node place2 --type place --dep place1
cbflow run set-dep --node export_data1 --deps place1   # Rewire (--reset restores)
cbflow run delete-node --node place2
cbflow run create-branch --branch fix --from cts1
cbflow run delete-branch --branch fix
cbflow run list-nodes | list-branches | show-graph [--detail] | targets
cbflow run gen-makefile                          # Verify the RACE DAG (legacy name)
cbflow run logs [--tail N] [--level ERROR]       # View logs
cbflow run validate [--type config] [--stage cts1]
cbflow run interactive --node place1             # Interactive tool session
cbflow run checklist --milestone BTO --phase P3  # Exit checklist on this run
cbflow run email --to a@b.com --template run-status
cbflow run autoppt [--format pptx|html]
cbflow run gui                                   # Open the run in the dashboard daemon
cbflow run db-manage --list                      # RACE DB sessions
cbflow run clean --confirm
cbflow run update [--release v2.0.0]
cbflow run help                                  # Full documentation
```

### Releases

```bash
cbflow run release --tag PLACE_EXIT [--dry-run]            # from the workarea
cbflow run release --tag BTO --publish [--override]        # + SmartGrid (opt-in)
cbflow run release --from-run <run> --node release_data1 --publish
cbflow run release --from-run <run> --clone-from BTO --tag MTO
cbflow run release-check --tag BTO --project opensky --phase P2
```
Layout: `<project(release,path)>/<phase>/<block>/<FLOW>/<tag>`.

### Dashboards

```bash
cbflow run dashboard start [--discipline PD|DFT|DV|RTL] [--project opensky] [--public]
cbflow run dashboard status|stop|list|prune
cbflow smartgrid start --project opensky
cbflow smartgrid open --project opensky
```

### Flow info, checklists, libraries

```bash
cbflow flow types [--domain RTL]
cbflow flow info --flow PNR
cbflow flow checklist list --discipline DFT
cbflow flow checklist list-checks --milestone PRO_EXIT --phase P2
cbflow flow library-manager status --lib_tag OSS1
cbflow flow mmmc-manager show --project opensky
```

### Component Versioning

```bash
cbflow flow version copy --dir <dir> --from <v1> --to <v2>
cbflow flow version set-current --dir <dir> --version <v>
cbflow flow version list --dir <dir>
cbflow flow version diff --dir <dir> --v1 <v1> --v2 <v2>
```

### Tests

```bash
cbflow test --static
cbflow test --e2e --flows SYNTH,PNR,STA
cbflow test --list
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
