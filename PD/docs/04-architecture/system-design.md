# System Design

Architecture of the CBflow v2.0.0 PD automation framework.

---

## RACE Engine (Run Automation & Control Engine)

RACE is the Python-native DAG executor at the core of CBflow v2.0.0. It completely replaces GNU Make -- Make is NOT used and NOT required anywhere in the system.

### How RACE Works

1. **DAG Construction**: RACE reads `node_config.tcl` at runtime and builds the execution DAG from the `stages` and `dependencies,<stage>` declarations. There is no intermediate Makefile or build-system artifact.

2. **SQLite DB for Status Tracking**: Each run has a dedicated SQLite database (`.race_<uid>.db`) that stores the status of every node and subnode. The DB path follows the convention:
   ```
   $project(race,db_path)/$project/$domain/$flow/$user_$run_$uid.db
   ```

3. **File Change Detection**: RACE tracks input file timestamps and checksums. When an input file is edited, RACE automatically identifies and retraces all downstream nodes that depend on it. This eliminates the need for manual retrace in most cases.

4. **Parallel Subnode Execution**: When the DAG contains independent subnodes at the same level, RACE executes them in parallel. For example, the PV flow runs drc, lvs, erc, perc, and xor in parallel after fill completes.

5. **Dynamic Subnodes**: RACE generates subnodes dynamically based on user_config at runtime. The STA flow creates per-corner subnodes from the user-specified timing scenarios, so each corner runs as an independent subnode.

6. **Custom Nodes at Run Level**: Users can extend the DAG at run time without editing node_config files:
   - `cbflow run add-node` -- add a custom node with specified dependencies
   - `cbflow run create-branch` -- create a branch in the DAG

### RACE Configuration

```tcl
# flow_config.tcl
set flow(dispatcher) "race"
```

### Active Engine Sync

RACE supports active engine synchronization: when you issue `retrace`, `bypass`, or `forcevalidate` commands while the engine is running, the changes are applied to the running engine immediately. There is no need to stop and restart the flow. The engine picks up the updated node status from the SQLite DB and adjusts its execution plan on the fly.

### RACE Commands

| Command | Purpose |
|---------|---------|
| `cbflow run all` | Execute the full DAG |
| `cbflow run stage --name <stage>` | Execute a single node |
| `cbflow run status` | Query node status from RACE DB |
| `cbflow run retrace --from <stage>` | Mark node and downstream for re-execution |
| `cbflow run bypass --node <node>` | Skip a node (mark bypassed in DB) |
| `cbflow run force --node <node>` | Force re-run regardless of status |
| `cbflow run forcevalidate --node X` | Force validate a specific node |
| `cbflow run forcevalidate --from X --to Y` | Force validate a range of nodes |
| `cbflow run forcevalidate --from X` | Force validate from node X to end |
| `cbflow run forcevalidate --to Y` | Force validate from start to node Y |
| `cbflow run gui` | Launch web dashboard (auto-port 8080-8180) |
| `cbflow run clean --confirm` | Delete work, logs, and RACE DB |
| `cbflow run verify-dag` | Verify DAG from node_config without executing |
| `cbflow run show-graph` | Visualize the RACE DAG |
| `cbflow run list-nodes` | List all nodes in the DAG |
| `cbflow run add-node` | Add a custom node |
| `cbflow run create-branch` | Create a DAG branch |

> **Note:** `retrace`, `bypass`, and `forcevalidate` can be issued while the engine is actively running. The running engine detects the DB changes and updates its execution plan in real time.

---

## flow_proc Engine

Every design step in CBflow is registered as a `flow_proc`. The construct takes a name and a body of EDA tool commands:

```tcl
flow_proc resolve_inputs {
    handle_info "Resolving input files..."
    # ... tool commands ...
}

flow_proc create_design_lib {
    handle_info "Creating design library..."
    # ... tool commands ...
}

flow_proc read_rtl_inputs {
    handle_info "Reading RTL design inputs..."
    # ... tool commands ...
}
```

`flow_proc` bodies are plain TCL executed inside the EDA tool shell (fc_shell, pt_shell, innovus, etc.). There is no dependency graph or topological sort -- `flow_exec_all` runs every registered flow_proc in **definition order**, top to bottom as they appear in the command file.

```tcl
# At the bottom of every command file:
flow_exec_all    ;# executes each flow_proc in the order it was defined
exit
```

### Hooks: prepend / append / replace

Users can modify any flow_proc without editing the base command file. Hook files are sourced after all flow_procs are defined but before `flow_exec_all`:

| Hook Type | Effect |
|-----------|--------|
| `prepend` | Insert code before the flow_proc body |
| `append`  | Insert code after the flow_proc body |
| `replace` | Completely replace the flow_proc body |

Hook files are sourced in this order at the end of each command file:

1. `$run_dir/work/<FLOW>/<node>/run/setup.tcl` -- generated per-node setup
2. `$run_dir/setup/override_setup.tcl` -- user global override
3. `$run_dir/setup/override_setup.<stage>.tcl` -- user stage-specific override

---

## Configuration Override Hierarchy

Configuration loads in a strict cascade. Each layer can override values set by the previous layer:

```
flow_config.tcl                         # 1. Flow-wide defaults
    -> project_config.tcl               # 2. Project-specific settings
        -> tech_config.tcl              # 3. Technology/foundry settings
            -> user_config.tcl          # 4. User/block-level overrides
                -> override_config.tcl          # 5. Global hook
                    -> override_config.<stage>.tcl  # 6. Stage-specific hook
                        -> override_setup.tcl           # 7. Setup hook (global)
                            -> override_setup.<stage>.tcl   # 8. Stage setup hook
```

Later sources win. A variable set in `override_setup.inputs.tcl` overrides the same variable from `flow_config.tcl`.

### Config Loading Path

All flow and node configurations are loaded from a versioned directory:

```
$CONFIG_ROOT/flow/$FLOW_CONFIG_VERSION/
    flow_config.tcl
    mmmc_config.tcl
    release_config.tcl
    tool_launch_config.tcl
    node_configs/
        SYNTH_config.tcl
        SYNTH_PNR_config.tcl
        PNR_config.tcl
        STA_config.tcl
        PV_config.tcl
        ...
```

Tech configs load from `$CONFIG_ROOT/tech/$TECH_NAME/$TECH_VERSION/tech_config.tcl`. Project configs load from `$CONFIG_ROOT/project/<project_name>/<version>/<project_name>_config.tcl`.

---

## Tested Flows

The following 6 flows have been fully tested with the RACE engine: **SYNTH_PNR**, **STA**, **LEC**, **CLP**, **SYNTH**, **PNR**.

---

## Tool Mapping

CBflow supports 11 design flows across Synopsys, Cadence, and Mentor tool suites.

### Synopsys Tools

| Tool | Binary | Flows |
|------|--------|-------|
| Fusion Compiler | `fc_shell` | SYNTH, FP, PNR, FCFP, SYNTH_PNR, ECO |
| PrimeTime | `pt_shell` | STA, POPT |
| Formality | `fm_shell` | LEC |
| IC Validator | `icv` | PV |
| VC_LP | `vc_lp` | CLP |
| RedHawk | `redhawk` | EMIR |

### Cadence Tools

| Tool | Binary | Flows |
|------|--------|-------|
| Genus | `genus` | SYNTH |
| Innovus | `innovus` | FP, PNR, FCFP |
| Tempus | `tempus` | STA |
| Conformal | `lec` | CLP |
| Voltus | `voltus` | EMIR |

### Mentor Tools

| Tool | Binary | Flows |
|------|--------|-------|
| Calibre | `calibre` | PV |

Tool selection is controlled per-flow via the node_config arrays `<flow>(tool,vendor)` and `<flow>(tool,name)`. See [Extending CBflow](../05-developer/extending.md) for how to override tool selection.

---

## Directory Layout

### Reports

Each stage writes reports to its own work directory:

```
work/<FLOW>/<node>/reports/
    e.g. work/SYNTH_PNR/synthesis1/reports/synthesis_timing.rpt
         work/SYNTH_PNR/place1/reports/place_qor.rpt
         work/SYNTH_PNR/signoff1/reports/signoff_check_drc.rpt
```

### Outputs

Final deliverables (netlists, GDS, DEF, SDC, SPEF, UPF) are written to:

```
outputs/
    ${design_name}.v
    ${design_name}.gds
    ${design_name}.def
    ${design_name}.sdc
    ...
```

### RACE Database

The RACE SQLite database is stored per-run:

```
.race_<uid>.db
```

Full path: `$project(race,db_path)/$project/$domain/$flow/$user_$run_$uid.db`

The DB stores node status, timestamps, file checksums for change detection, and execution history.

### Dashboard Auto-Port

The RACE web dashboard (`cbflow run gui` or `cbflow flow dashboard start`) automatically selects an available port in the 8080-8180 range. If port 8080 is in use, it tries 8081, 8082, etc. This eliminates "Address already in use" errors when multiple dashboards run on the same host.

---

## Release System

### Release Path Structure

Releases are organized under the project release path:

```
$project(release,path)/$phase/$block/$tag/
    netlist/
    sdc/
    gds/
    def/
    upf/
    spef/
    data/
    reports/
    MANIFEST.json
    RELEASE_NOTES.md
    RELEASE_COMPLETE
```

- `$project(release,path)` -- base release directory (e.g., `/proj/my_chip/releases`)
- `$phase` -- design phase: P0, P1, P2, P3
- `$block` -- block/design name
- `$tag` -- release tag (e.g., `v1.0.2`)

The `release_data` stage in each flow calls `::CBFlow::Release::init`, copies deliverables, then generates:

1. **MANIFEST.json** -- metadata, file checksums, component versions
2. **RELEASE_NOTES.md** -- human-readable release description
3. **RELEASE_COMPLETE** -- marker file indicating a complete, valid release

### Input Handshaking

Downstream flows consume upstream releases through the input handshake mechanism. The `resolve_inputs` flow_proc checks for release tag variables and assembles paths automatically:

```tcl
# In user_config.tcl, user sets the release tag:
set pnr(input,netlist_release_tag) "v1.0.2"

# resolve_inputs checks the tag, looks up the handshake map,
# and assembles the full path:
#   $project(release,path)/$phase/$block/v1.0.2/netlist/${design_name}.v
```

The handshake map (defined in `release_config.tcl`) maps each `<flow>(input,<type>_release_tag)` to a triple: source flow, deliverable category, and file pattern. `::CBFlow::InputResolve::resolve` constructs the path from `project()` variables and validates that the release directory contains `RELEASE_COMPLETE`.

If no release tag is set, direct paths are used instead (e.g., `pnr(input,netlist) "/path/to/file.v"`). Release tags always take priority when both are provided.

---

## Launch Modes

CBflow supports four launch modes for EDA tool execution, controlled by `flow(use_lsf)` and `flow(use_xterm)`:

| Mode | LSF | xterm | Description |
|------|-----|-------|-------------|
| LSF + xterm | Yes | Yes | Submit to LSF, open interactive xterm session on compute node |
| LSF batch | Yes | No | Submit to LSF as batch job, no interactive window |
| xterm local | No | Yes | Launch tool in local xterm window |
| Local | No | No | Run tool in current shell |

LSF parameters (queue, CPUs, memory, wall time) are configured per-flow in `tool_launch_config.tcl` and the LSF tier system (XS, S, M, L, XL, Ultra).

---

## SYNTH_PNR Stages

The SYNTH_PNR flow is the primary unified synthesis-through-signoff flow. Its stages execute in this fixed order:

```
inputs -> init_design -> synthesis -> place -> cts -> cts_opt -> route -> pro -> signoff -> export_data -> release_data
```

Internally, node names carry a numeric suffix (e.g., `inputs1`, `synthesis1`, `place1`) to support multiple instances. Each stage has its own command file, subnode handler, and work directory.

Stage dependencies are declared in the node_config (and consumed by RACE to build the DAG):

```tcl
array set synth_pnr {
    stages {inputs1 init_design1 synthesis1 place1 cts1 cts_opt1 route1 pro1 signoff1 export_data1 release_data1}

    dependencies,inputs1          {}
    dependencies,init_design1     {inputs1}
    dependencies,synthesis1       {init_design1}
    dependencies,place1           {synthesis1}
    dependencies,cts1             {place1}
    dependencies,cts_opt1         {cts1}
    dependencies,route1           {cts_opt1}
    dependencies,pro1             {route1}
    dependencies,signoff1         {pro1}
    dependencies,export_data1     {signoff1}
    dependencies,release_data1    {export_data1}
}
```

---

## Per-Corner STA (Dynamic MMMC Scenario Subnodes)

The STA flow runs timing analysis on a per-corner basis. RACE generates dynamic subnodes from the user-specified MMMC scenarios in user_config. Each corner/scenario appears as an individual subnode in the timing1 stage, enabling parallel per-scenario execution:

```
STA stages:
  inputs1 -> extraction1 -> timing1 (per-scenario subnodes) -> reporting1 -> release_data1
```

Each MMMC scenario (e.g., `func_ss_0p76v_rcmax_150c`, `func_ff_0p84v_rcmin_m40c`) runs as an independent subnode within the timing1 stage. The `timing_scenario_handler` manages per-scenario dispatching. RACE creates one subnode per scenario at runtime and executes them in parallel when resources allow. Status for each scenario subnode is tracked individually in the RACE SQLite DB, so `cbflow run status --details` shows per-scenario completion.

---

## ICV PV Parallel Pipeline

The PV flow with ICV follows a fill-first, then parallel verification pattern. RACE executes the independent verification subnodes in parallel:

```
inputs -> fill -> [drc | lvs | erc | perc | xor] -> merge_data -> release_data
```

After `fill` completes, RACE launches the DRC, LVS, ERC, PERC, and XOR stages in parallel. Results are merged in `merge_data` before the final `release_data` stage packages everything for release.

---

## Standard Command File Pattern

Every command file in `cmds/<FLOW>/<vendor>/<tool>/<version>/` follows the same structure:

```
1. Header & environment bootstrap
   - Source .run.cbflow.tcl
   - Load utilities

2. Source tech_config
   - $CONFIG_ROOT/tech/$TECH_NAME/$TECH_VERSION/tech_config.tcl

3. Source user_config
   - $run_dir/setup/user_config.tcl

4. Set WORK_DIR, REPORTS_DIR, OUTPUTS_DIR

5. Source release utilities (for resolve_inputs stages)

6. Define flow_procs (in execution order)

7. Source setup hooks
   - $run_dir/work/<FLOW>/<node>/run/setup.tcl
   - $run_dir/setup/override_setup.tcl
   - $run_dir/setup/override_setup.<stage>.tcl

8. flow_exec_all

9. exit
```

---

**See also:**
- [Architecture Index](README.md)
- [Extending CBflow](../05-developer/extending.md) -- Adding flows, procs, and checks
- [Examples](../06-examples/basic-workflows.md) -- Workflow examples
