# RACE Engine Command Reference

CBflow v2.0.0 uses the RACE (Run Automation & Control Engine) as its sole executor. GNU Make is **not** used anywhere in the system. All status tracking is done via the RACE SQLite database (`.race_*.db`) -- there is no `.stamps/` directory.

For the complete command reference, see:
- [Python Scripts Reference](python-scripts-reference.md) -- All CLI commands
- [Configuration Reference](configuration-reference.md) -- All config files

---

## Execution Commands

### cbflow run all

Execute the complete flow DAG from start to finish. RACE builds the DAG from `node_config.tcl` at runtime and executes stages in dependency order. Completed nodes (tracked in the SQLite DB) are skipped automatically.

```bash
cbflow run all                              # Execute full DAG
cbflow run all --validate                   # With pre/post validation
cbflow run all --lsf                        # Submit via LSF
cbflow run all --lsf --queue XL             # LSF with queue override
cbflow run all --collect-metrics            # Collect metrics after run
```

### cbflow run stage

Execute a single stage and its dependencies (if not already complete).

```bash
cbflow run stage --name place1              # Run specific stage
cbflow run stage --name cts1 --lsf          # Run stage via LSF
```

---

## Status and Monitoring

### cbflow run status

Query node/subnode status from the RACE SQLite database.

```bash
cbflow run status                           # Stage completion overview
cbflow run status --details                 # Show all subnodes per stage
```

### cbflow run show-graph

Visualize the RACE DAG as an ASCII dependency graph.

```bash
cbflow run show-graph                       # Show dependency graph
cbflow run show-graph --detail              # Show with subnodes
```

### cbflow run list-nodes

List all nodes in the current DAG.

```bash
cbflow run list-nodes
```

### cbflow run verify-dag

Verify the DAG structure from node_config without executing anything.

```bash
cbflow run verify-dag
```

---

## Re-execution Controls

All of these commands update the RACE SQLite database. When issued while the engine is actively running (active engine sync), the running engine detects the DB changes and adjusts its execution plan in real time.

### cbflow run retrace

Mark a node and all its downstream dependencies for re-execution in the RACE DB.

```bash
cbflow run retrace --from cts1              # Retrace from CTS onwards
cbflow run retrace --from inputs1           # Retrace entire flow
```

After retracing, run `cbflow run all` to re-execute the affected nodes.

### cbflow run bypass

Skip a node without executing it. The node is marked as "bypassed" in the RACE DB.

```bash
cbflow run bypass --node export_data1       # Skip export_data1
cbflow run bypass --stages export_data1     # Alternate syntax
```

### cbflow run force

Force re-run a node regardless of its current status in the DB.

```bash
cbflow run force --node place1              # Force re-run place1
cbflow run force --stages place1            # Alternate syntax
```

### cbflow run forcevalidate

Force-validate a node or range of nodes (mark them as successfully completed in the DB without actually running them).

```bash
cbflow run forcevalidate --node signoff1                # Single node
cbflow run forcevalidate --from place1 --to pro1        # Range of nodes
cbflow run forcevalidate --from cts1                    # From node to end
cbflow run forcevalidate --to route1                    # From start to node
```

---

## Custom DAG Modifications

### cbflow run add-node

Add a custom node to the RACE DAG at runtime.

```bash
cbflow run add-node --node eco1 --type eco --dep signoff1
```

### cbflow run create-branch

Create a branch in the DAG for experimental runs.

```bash
cbflow run create-branch --name timing_experiment --from cts1
```

### cbflow run delete-node

Remove a custom node from the DAG. Fails if other nodes depend on the target node (dependency protection).

```bash
cbflow run delete-node --node eco1
```

### cbflow run rename-node

Rename a node in the RACE DAG. All dependency references are updated automatically. Only custom nodes (added via `add-node` or `create-branch`) can be renamed; built-in nodes from node_config.tcl cannot be renamed.

```bash
cbflow run rename-node --node eco1 --new-name eco_timing_fix1
```

The rename is also available from the GUI: select a custom node, edit the name in the Node Info panel, and click **Rename**. See the [GUI User Guide](../02-user-guide/cbflow-gui-user-guide.md#4-node-selection-and-info-panel).

---

## Dev Workflow Commands

### cbflow flow dev start

Create a writable dev version from an existing released version. The dev version uses the `-dev` suffix convention (e.g., `v1.0.0-dev`).

```bash
cbflow flow dev start --dir cmds/SYNTH --from v1.0.0
# Creates: cmds/SYNTH/synopsys/fc/v1.0.0-dev/ (writable copy)
```

### cbflow flow dev status

Show all active dev versions across the project.

```bash
cbflow flow dev status
```

### cbflow flow dev diff

Show changes made in a dev version compared to its base version.

```bash
cbflow flow dev diff --dir cmds/SYNTH
```

### cbflow flow dev promote

Promote a dev version to a new released version. The new version is locked (`chmod 444` + `.locked` marker) and the dev version is removed.

```bash
cbflow flow dev promote --dir cmds/SYNTH --version v1.0.1
```

### cbflow flow dev sandbox-create

Create an isolated sandbox for experimentation without affecting the dev version.

```bash
cbflow flow dev sandbox-create --name experiment1
```

### cbflow flow dev sandbox-push

Push sandbox changes back to the dev version.

```bash
cbflow flow dev sandbox-push --name experiment1
```

---

## Version Locking

Released versions are permanently read-only. CBflow applies `chmod 444` to all files and creates a `.locked` marker file. This is irreversible -- there is no way to unlock a released version.

```bash
# A locked version directory:
# cmds/SYNTH/synopsys/fc/v1.0.0/.locked   (marker file)
# All files are chmod 444

# To make changes, start a dev version:
cbflow flow dev start --dir cmds/SYNTH --from v1.0.0
```

---

## Dashboard

### cbflow run gui

Launch the RACE web dashboard. The dashboard automatically selects an available port in the 8080-8180 range, eliminating "Address already in use" errors when multiple dashboards run on the same host.

```bash
cbflow run gui                              # Launch dashboard
cbflow run gui --port 9000                  # Launch on specific port
cbflow flow dashboard start                 # Alternative command
```

The assigned port is printed to the console on startup. Multiple dashboards can run simultaneously on the same host, each on a different auto-selected port.

For the complete GUI reference (layout, DAG visualization, config editor, branch management, keyboard shortcuts, MMMC scenario editor), see the [GUI User Guide](../02-user-guide/cbflow-gui-user-guide.md).

---

## Cleanup

### cbflow run clean

Delete work directories, logs, and the RACE SQLite database.

```bash
cbflow run clean --confirm                  # Delete work + logs + RACE DB
```

---

## Interactive Sessions

### cbflow run interactive

Open an interactive EDA tool session.

```bash
cbflow run interactive                      # Empty interactive session
cbflow run interactive --load place1        # Load saved design from place1
```

---

## Logs

### cbflow run logs

View execution logs.

```bash
cbflow run logs --list                      # List all log files
cbflow run logs --tail 50                   # Last 50 lines
cbflow run logs --tail 100 --level ERROR    # Filter by level
```

---

## Active Engine Sync

RACE supports active engine synchronization. When the engine is running (`cbflow run all` in progress), you can issue `retrace`, `bypass`, `force`, and `forcevalidate` commands from a separate terminal. The running engine detects the changes in the SQLite DB and adjusts its execution plan in real time -- no need to stop and restart.

Example workflow:
```bash
# Terminal 1: Engine is running
cbflow run all

# Terminal 2: Skip a slow node while engine is running
cbflow run bypass --node export_data1

# Terminal 2: Force re-run a node
cbflow run force --node place1

# Terminal 2: Retrace from a stage
cbflow run retrace --from cts1
```

---

## RACE SQLite Database

Each run has a dedicated SQLite database (`.race_<uid>.db`) that stores:
- Node and subnode status (pending, running, complete, failed, bypassed)
- Execution timestamps
- Input file checksums for change detection
- Execution history

The DB path follows the convention:
```
$project(race,db_path)/$project/$domain/$flow/$user_$run_$uid.db
```

Query the DB directly for debugging:
```bash
sqlite3 .race_*.db "SELECT * FROM run_info"
sqlite3 .race_*.db "SELECT node, status FROM node_status"
```

---

## Tool Configuration Reference

Tool config files define EDA tool-specific parameters using a two-level scoping convention. Each tool has its own config file.

### Tool Config Files

| Tool | Config File | Flows |
|------|-------------|-------|
| Fusion Compiler | `fc_config.tcl` | SYNTH, FP, PNR, FCFP, SYNTH_PNR, ECO |
| PrimeTime | `pt_config.tcl` | STA, POPT |
| Formality | `fm_config.tcl` | LEC |
| IC Validator | `icv_config.tcl` | PV |
| VC_LP | `vc_lp_config.tcl` | CLP |
| RedHawk | `redhawk_config.tcl` | EMIR |

### Scoping Convention

```tcl
# Common -- shared across all nodes in the flow
set fc(common,enable_spg)            true
set fc(common,max_routing_layer)     M8

# Node-specific -- overrides common for this node only
set fc(route1,detail_route_effort)   high
set fc(cts1,max_skew)                50
```

Resolution order: `fc(<node>,<param>)` > `fc(common,<param>)` > tool default.

### Overriding Tool Config

Tool config values can be overridden at any level of the config hierarchy. In practice, overrides are typically placed in `user_config.tcl` or `override_config.tcl`:

```tcl
# In user_config.tcl -- override route effort for this run
set fc(route1,detail_route_effort)   medium

# In override_config.tcl -- GUI Config Editor writes here
set fc(place1,congestion_effort)     high
```

See the [System Design](../04-architecture/system-design.md#tool-configuration-architecture) for full architecture details.

---

**Documentation Version**: 2.0.0
