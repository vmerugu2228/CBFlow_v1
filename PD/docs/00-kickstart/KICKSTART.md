# CBflow Kickstart Guide

**Copy to Unix, set PATH, run your first flow in 5 minutes.**

---

## 1. Copy to Unix

```bash
# Copy CBflow to your Unix/Linux machine
scp -r CBflow_clone/PD user@server:/opt/cbflow
# OR
rsync -avz CBflow_clone/PD user@server:/opt/cbflow
```

## 2. Set Environment

```bash
export CBFLOW_HOME=/opt/cbflow
export PATH=$CBFLOW_HOME/bin:$PATH

# Tab completion (bash)
source $CBFLOW_HOME/completions/cbflow.bash

# Verify
cbflow --version
```

## 3. Configure Project

Edit your project config (`config/project/<name>/v1.0.0/<name>_config.tcl`):

```tcl
set project(name)               "my_chip"
set project(cbflow_release)     "v1.0.0"
set project(release,path)       "/proj/my_chip/releases"
set project(release,phase)      "P0"
set project(release,block_name) "top"
set project(release,tag)        "v1.0.0"
```

## 4. Create User Config

```tcl
# user_config.tcl — minimum for SYNTH_PNR flow
set flow(design_name)               "my_design"
set flow(dispatcher)                "race"
set synth_pnr(design_name)          "my_design"
set synth_pnr(input,rtl_filelist)   "/proj/rtl/my_design.f"
set synth_pnr(input,sdc_file)       "/proj/constraints/my_design.sdc"
set synth_pnr(input,upf)            "/proj/power/my_design.upf"
```

## 5. Create Run and Execute

```bash
# Create run directory
cbflow workspace create --config user_config.tcl
cd P0_run_SYNTH_PNR_run1/

# Run the full flow (RACE builds DAG from node_config.tcl, executes all nodes)
cbflow run all

# Check status (reads from RACE SQLite DB)
cbflow run status

# View logs
cbflow run logs --tail 20

# Generate summary
cbflow run autoppt
```

## 6. RACE Engine Basics

CBflow v2.0.0 uses the **RACE (Run Automation & Control Engine)** as its dispatcher. RACE is a Python-native DAG executor that:

- Builds the execution DAG from `node_config.tcl` at runtime
- Tracks all node status in a SQLite database (`.race_<uid>.db`)
- Detects file changes on inputs and auto-retraces downstream nodes
- Runs independent subnodes in parallel (e.g., PV: drc/lvs/erc/perc/xor)
- Generates dynamic subnodes (e.g., STA per-corner from user_config)

There is no Makefile, no `.make/` directory, and no `make` command. All execution is handled by RACE.

## 7. Key Commands

| Command | Purpose |
|---------|---------|
| `cbflow run all` | Run complete flow |
| `cbflow run stage --name place1` | Run single stage |
| `cbflow run status` | Check progress (from RACE DB) |
| `cbflow run retrace --from cts1` | Mark CTS and downstream for re-execution |
| `cbflow run bypass --node <node>` | Skip a node |
| `cbflow run force --node <node>` | Force re-run a node |
| `cbflow run forcevalidate --node <node>` | Force validate a specific node |
| `cbflow run forcevalidate --from X --to Y` | Force validate a range of nodes |
| `cbflow run checklist --milestone PRO_EXIT --phase P2` | Exit checklist |
| `cbflow run email --to user@co.com --template run-summary` | Email report |
| `cbflow run autoppt --format html` | Generate PPT summary |
| `cbflow run interactive --load signoff1` | Interactive session |
| `cbflow run logs --level ERROR` | View errors |
| `cbflow run add-node --node <n> --type <t>` | Add custom node to DAG |
| `cbflow run create-branch --name <n>` | Create a flow branch |
| `cbflow run show-graph` | Visualize DAG |

## 8. Supported Flows (12)

| Flow | What It Does |
|------|-------------|
| `SYNTH` | RTL synthesis |
| `FP` | Floorplanning |
| `PNR` | Place and route |
| `SYNTH_PNR` | Unified synthesis + PNR (FC) |
| `STA` | Static timing analysis (per-corner, dynamic subnodes) |
| `PV` | Physical verification (DRC/LVS/ERC, parallel subnodes) |
| `LEC` | Logic equivalence check |
| `ECO` | Engineering change order |
| `CLP` | Clock low power verification |
| `EMIR` | EM/IR drop analysis |
| `POPT` | Power optimization |
| `FCFP` | Full chip floorplan (hierarchical) |

## 9. Input Handshaking

```tcl
# In user_config.tcl — two modes:

# Mode 1: Release tag (auto-resolves from release directory)
set pnr(input,netlist_release_tag) "v1.0.2"

# Mode 2: Direct path
set pnr(input,netlist) "/proj/runs/synth_run1/outputs/my_design.v"
```

## 10. Override Hierarchy

All configs are consolidated into a single generated `config.tcl` per node. Command files source it once.

```
project_config.tcl            (project-specific)
  -> tech_config.tcl           (technology + libraries)
    -> flow_config.tcl          (flow defaults)
      -> node_config.tcl        (stage definitions)
        -> mmmc_config.tcl      (MMMC scenarios/corners)
          -> <tool>_config.tcl  (tool-specific: fc_config, pt_config)
            -> user_config.tcl  (per-run overrides)
              -> override_config.tcl              (global hook)
                -> override_config.<stage>.tcl    (stage-type hook)
                  -> override_config.<branch>.tcl (branch-scoped hook)
                    -> override_config.<node>.tcl (per-node hook)
```

Flow type must be explicitly set (via `CBFLOW_FLOW_TYPE` env var or user_config). If missing or invalid, CBflow exits with error and lists available flows.

## 11. Milestone Release

Releases are milestone-gated. Tags are predefined; leads set the active tag in project config.

```bash
# From workspace (where all runs live):
cbflow run release                      # Release using project's active tag
cbflow run release --tag PLACE_EXIT     # Specific milestone
cbflow run release --dry-run            # Validate without copying

# Predefined tags: FP_EXIT, PLACE_EXIT, CTS_EXIT, PRO_EXIT, BTO, MTO
# Release path: <base>/<project>/<design>/<phase>_<tag>/<FLOW>/
```

## 12. SmartGenie AI Agent

```bash
# Setup (one time)
brew install ollama && ollama serve && ollama pull qwen2.5:7b
cbflow smartgenie ingest --all       # Build knowledge base (4000+ chunks)
cbflow smartgenie setup              # Verify

# Use
cbflow smartgenie                    # Interactive AI agent
cbflow smartgenie "run SYNTH_PNR"    # One-shot command
cbflow smartgenie search "hold fix"  # Search knowledge

# Enterprise (multi-user, shared learning)
cbflow smartgenie serve              # Start central server
export SMARTGENIE_SERVER=http://server:8091
cbflow smartgenie "prompt"           # All users connect, knowledge auto-shared
```

100% private — runs on-premise via Ollama. No data leaves your network. See [SmartGenie User Guide](../02-user-guide/smartgenie-user-guide.md).

## 13. Customer Bundle & Permissions

```bash
# Create customer bundle (all files 777 for safe unzip)
cbflow bundle                           # Creates CBflow_v2.0.0_<date>.tar.gz
cbflow bundle --output /path/to/dir     # Custom output directory

# After customer unpacks:
tar xzf CBflow_v2.0.0_20260519.tar.gz
cd CBflow_v2.0.0_20260519
bin/cbflow run release-lock             # Lock: configs=444, scripts=555, dirs=755
bin/cbflow run release-lock --unlock    # Unlock: restore 777 (development mode)
```

Lead config (in project_config.tcl):
```tcl
set project(release,active_tag)  "BTO"
set project(release,expiry_date) "2026-06-30"
set project(release,path)        "/proj/releases"
```

## 12. Test Suite

```bash
bin/cbflow-test-suite              # 994 tests, all categories
bin/cbflow-test-suite --verbose    # Show all results
```

---

**Next**: [Quick Start Guide](../01-quick-start/README.md) for detailed setup.
