# RACE Engine Command Reference

CBflow v2.0.0 uses the RACE (Run Automation & Control Engine) as its sole executor. GNU Make is **not** used anywhere in the system. All status tracking is done via the RACE SQLite database (`.race_*.db`) -- there is no `.stamps/` directory.

For the complete command reference, see:
- [Command Reference](command-reference.md) -- Every CLI command and flag
- [Python Scripts Reference](python-scripts-reference.md) -- Command modules
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

Execute a single stage (node name, e.g. `place1`; see `cbflow run list-nodes`) and its dependencies (if not already complete).

```bash
cbflow run stage --name place1              # Run specific stage
cbflow run stage --name cts1 --lsf          # Run stage via LSF
cbflow run stage --name init_design1 --subnode run   # One subnode only
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

### cbflow run gen-makefile

Verify the RACE DAG structure without executing anything (legacy command name — no Makefile is generated).

```bash
cbflow run gen-makefile
```

---

## Re-execution Controls

All of these commands update the RACE SQLite database. When issued while the engine is actively running (active engine sync), the running engine detects the DB changes and adjusts its execution plan in real time.

### cbflow run retrace

Invalidate a stage and every later stage (in flow order) in the RACE DB.

```bash
cbflow run retrace --from cts1              # Retrace from CTS onwards
cbflow run retrace                          # Retrace entire flow
cbflow run retrace --from cts1 --run        # Retrace and rerun
```

After retracing, run `cbflow run all` (or pass `--run`) to re-execute the affected nodes.

### cbflow run bypass

Skip stages without executing them. They are marked as bypassed in the RACE DB; a fully bypassed stage gets `work/<FLOW>/<node>/BYPASSED`.

```bash
cbflow run bypass --stages export_data1                       # Skip export_data1
cbflow run bypass --stages cts1,cts_opt1,route1,pro1,signoff1 # Release place1 as PLACE_EXIT
```

### cbflow run force

Re-run only the named stages (downstream is not invalidated; dependencies must be DONE).

```bash
cbflow run force --stages place1            # Force re-run place1
cbflow run force --stages cts1,cts_opt1     # Several stages
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

Add a custom node to the RACE DAG at runtime. The node type must be a stage type of the run's flow; added nodes inherit `runtime,timeout`. `--resource-tier XS|S|M|L|XL|ultra` overrides the LSF tier.

```bash
cbflow run add-node --node place2 --type place --dep place1
cbflow run add-node --node export_data2 --type export_data --dep place1
cbflow run add-node --node release_data2 --type release_data --dep export_data2
```

### cbflow run set-dep

Rewire a node's dependencies (base or custom node); `--reset` restores the node config's dependencies. Also in the run GUI (right-click → Set Dependencies…).

```bash
cbflow run set-dep --node export_data1 --deps place1
cbflow run set-dep --node export_data1 --reset
```

### cbflow run create-branch

Create a branch in the DAG for experimental runs.

```bash
cbflow run create-branch --branch timing_experiment --from cts1
cbflow run list-branches
cbflow run delete-branch --branch timing_experiment
```

### cbflow run delete-node

Remove a custom node from the DAG. Fails if other nodes depend on the target node (dependency protection).

```bash
cbflow run delete-node --node place2
```

There is no `rename-node` CLI command; renaming a custom node is done from the run GUI (Node Info panel → **Rename**). See the [GUI User Guide](../02-user-guide/cbflow-gui-user-guide.md#4-node-selection-and-info-panel).

---

## Dev Workflow Commands

### cbflow flow dev start

Create a writable dev version from an existing released version. The dev version uses the `-dev` suffix convention (e.g., `v1.0.0-dev`).

```bash
cbflow flow dev start --component cmds/SYNTH --from v1.0.0
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
cbflow flow dev diff --component cmds/SYNTH
```

### cbflow flow dev promote

Promote a dev version (removes the `-dev` suffix). The new version is locked (`chmod 444` + `.locked` marker).

```bash
cbflow flow dev promote --component cmds/SYNTH
```

### cbflow flow dev sandbox-create

Create a local development sandbox (`--base <release>`, `--dir <path>`).

```bash
cbflow flow dev sandbox-create --dir ~/cbflow_sandbox
```

### cbflow flow dev sandbox-push

Push sandbox changes to the central install.

```bash
cbflow flow dev sandbox-push --dir ~/cbflow_sandbox
```

---

## Version Locking

Released versions are permanently read-only. CBflow applies `chmod 444` to all files and creates a `.locked` marker file. This is irreversible -- there is no way to unlock a released version.

```bash
# A locked version directory:
# cmds/SYNTH/synopsys/fc/v1.0.0/.locked   (marker file)
# All files are chmod 444

# To make changes, start a dev version:
cbflow flow dev start --component cmds/SYNTH --from v1.0.0
```

---

## Dashboard

### cbflow run gui

Register the run with the per-user run dashboard daemon (starting it if needed) and open the browser on the run. The daemon port is deterministic per user and discipline: `flow(dashboard,port_base,<DISC>) + uid % flow(dashboard,port_width)` (PD 9000, DFT 9300, DV 9600, RTL 9900; width 300).

```bash
cbflow run gui                              # Register + open in the daemon
cbflow run gui --no-browser                 # Register only
cbflow run gui --public                     # Daemon bound to 0.0.0.0 (LAN)
cbflow run gui --foreground --port 9090     # Legacy per-run server on a port
cbflow run dashboard start --port 9100      # Daemon on an explicit port
cbflow run dashboard status|stop|list|prune # Daemon lifecycle
```

See [Production Dashboard Setup](dashboard-production-setup.md) for remote access.

For the complete GUI reference (layout, DAG visualization, config editor, branch management, keyboard shortcuts, MMMC scenario editor), see the [GUI User Guide](../02-user-guide/cbflow-gui-user-guide.md).

---

## Cleanup

### cbflow run clean

Delete `work/` and `logs/` and deregister the run from the dashboard daemon. RACE databases are managed with `cbflow run db-manage`.

```bash
cbflow run clean --confirm                  # Delete work + logs
cbflow run db-manage --list                 # List RACE DBs
cbflow run db-manage --delete <run_name>    # Delete one run's DB (owner only)
```

---

## Interactive Sessions

### cbflow run interactive

Open an interactive EDA tool session (xterm) on a node's saved design, under `INTERACTIVE/<node>_<timestamp>`. Open-source runs go through `cbflow-oss interactive`.

```bash
cbflow run interactive --node place1                            # Load place1
cbflow run interactive --node timing1_func_ss_0p80v_rcmax_125c  # STA: exact scenario
cbflow run interactive --node place1 --notiming                 # No timing libs
```

---

## Logs

### cbflow run logs

View execution logs.

```bash
cbflow run logs --list                      # List all log files
cbflow run logs --tail 50                   # Last 50 lines
cbflow run logs --tail 100 --level ERROR    # Filter by level
cbflow run logs --search 'slack'            # Regex search
cbflow run logs --file place1.log           # One file
```

---

## Active Engine Sync

RACE supports active engine synchronization. When the engine is running (`cbflow run all` in progress), you can issue `retrace`, `bypass`, `force`, and `forcevalidate` commands from a separate terminal. The running engine detects the changes in the SQLite DB and adjusts its execution plan in real time -- no need to stop and restart.

Example workflow:
```bash
# Terminal 1: Engine is running
cbflow run all

# Terminal 2: Skip a slow node while engine is running
cbflow run bypass --stages export_data1

# Terminal 2: Force re-run a node
cbflow run force --stages place1

# Terminal 2: Retrace from a stage
cbflow run retrace --from cts1
```

---

## RACE SQLite Database

Each run has a dedicated SQLite database (`.race_<run_dir_name>_<user>_<hash>.db` in the `project(race,db_path)` area; the run dir holds a `.race_db_pointer`) that stores:
- Node and subnode status (pending, running, complete, failed, bypassed)
- Execution timestamps
- Input file checksums for change detection
- Execution history

Query the DB directly for debugging (path from `.race_db_pointer`):
```bash
sqlite3 "$(cat .race_db_pointer)" "SELECT * FROM run_info"
sqlite3 "$(cat .race_db_pointer)" "SELECT job_name, status FROM jobs"
```

---

## Tool Configuration Reference

There are no tool-specific arrays (`fc()`, `pt()`, `genus()`, …). Each flow
uses ONE array (`synth()`, `pnr()`, `sta()`, `fp()`, `lec()`, `pv()`, `eco()`,
…). Tool settings live in the tool overlay
`<disc>/config/flow/v1.0.0/node_configs/<FLOW>_<tool>_config.tcl`, selected by
`<flow>(tool,name)` (e.g. `PNR_fc_config.tcl`, `PNR_openroad_config.tcl`);
open-source tool keys use `<flow>(oss,…)`.

Overrides follow the cascade: `user_config.tcl`, then
`setup/override_config.tcl` → `.<stage>` → `.<branch>` → `.<node_type>` →
`.<node>` (last writer wins):

```tcl
# user_config.tcl — this run
set pnr(tool,name) "openroad"
# setup/override_config.place1.tcl — one node (the GUI Config Editor writes here)
set pnr(oss,place,density) 0.6
```

See the [System Design](../04-architecture/system-design.md#tool-configuration-architecture) for full architecture details.

---

**Documentation Version**: 2.0.0
