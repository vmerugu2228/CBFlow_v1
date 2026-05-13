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

Remove a custom node from the DAG.

```bash
cbflow run delete-node --node eco1
```

---

## Dashboard

### cbflow run gui

Launch the RACE web dashboard. The dashboard automatically selects an available port in the 8080-8180 range, eliminating "Address already in use" errors when multiple dashboards run on the same host.

```bash
cbflow run gui                              # Launch dashboard
cbflow flow dashboard start                 # Alternative command
```

The assigned port is printed to the console on startup.

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

**Documentation Version**: 2.0.0
