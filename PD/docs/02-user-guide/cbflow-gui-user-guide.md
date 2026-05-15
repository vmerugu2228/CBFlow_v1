# CBflow GUI User Guide

**Version:** 2.0.0
**Date:** May 2026
**Author:** CBflow Development Team

---

## Table of Contents

1. [Launching the GUI](#1-launching-the-gui)
2. [Layout Overview](#2-layout-overview)
3. [DAG Visualization](#3-dag-visualization)
4. [Node Selection and Info Panel](#4-node-selection-and-info-panel)
5. [Right-Click Context Menu](#5-right-click-context-menu)
6. [Branch Management](#6-branch-management)
7. [Node Management](#7-node-management)
8. [Config Editor](#8-config-editor)
9. [MMMC Scenario Editor](#9-mmmc-scenario-editor)
10. [Keyboard Shortcuts](#10-keyboard-shortcuts)
11. [Zoom and Pan Controls](#11-zoom-and-pan-controls)
12. [Subnode View](#12-subnode-view)
13. [Execution Control](#13-execution-control)
14. [Auto-Refresh and Live Updates](#14-auto-refresh-and-live-updates)

---

## 1. Launching the GUI

The CBflow GUI is a web-based dashboard that provides real-time visualization and control of RACE DAG execution. Launch it from within any run directory.

### Basic Launch

```bash
cd P0_run_SYNTH_PNR_run1/
cbflow run gui
```

The dashboard starts a local web server and prints the URL to the console:

```
CBflow Dashboard started on http://localhost:8080
Open this URL in your browser.
```

### Auto-Port Selection

The GUI automatically scans ports in the **8080-8180** range and binds to the first available port. If port 8080 is already in use (e.g., by another user's dashboard), it tries 8081, 8082, and so on. This eliminates "Address already in use" errors entirely.

```
# If 8080 is occupied:
CBflow Dashboard started on http://localhost:8083
```

### Custom Port

Override the auto-port behavior with the `--port` flag:

```bash
cbflow run gui --port 9000
```

### Multiple Simultaneous Dashboards

Because of auto-port selection, multiple dashboards can run on the same host without conflict. Each instance gets its own port:

```bash
# Terminal 1 (run1)
cd P0_run_SYNTH_PNR_run1/
cbflow run gui
# -> http://localhost:8080

# Terminal 2 (run2)
cd P0_run_SYNTH_PNR_run2/
cbflow run gui
# -> http://localhost:8081

# Terminal 3 (STA run)
cd P0_run_STA_run1/
cbflow run gui
# -> http://localhost:8082
```

---

## 2. Layout Overview

The GUI uses a 3-panel layout optimized for DAG navigation and node inspection.

```
+---------------------+-------------------------------+--------------------+
|                     |                               |                    |
|   LEFT PANEL        |       CENTER PANEL            |   RIGHT PANEL      |
|                     |                               |                    |
| +- Design Info ---+ |   +-------+    +-------+     | +- Properties ---+ |
| | Project: raven  | |   |inputs1| -> |synth1 | ->  | |                | |
| | Flow: SYNTH_PNR | |   +-------+    +-------+     | | (appears when  | |
| | Phase: P0       | |                    |          | |  editing config | |
| | Run: run1       | |               +-------+      | |  or MMMC)      | |
| | Status: RUNNING | |               |place1 | ->   | |                | |
| +-----------------+ |               +-------+      | |                | |
|                     |                    |          | |                | |
| +- Node Info -----+ |               +-------+      | |                | |
| | Name: place1    | |               | cts1  | ->   | |                | |
| | Type: PNR       | |               +-------+      | |                | |
| | Status: RUNNING | |                    |          | |                | |
| | Branch: main    | |                   ...        | |                | |
| | Tag: --         | |                               | |                | |
| | Deps: synth1    | |                               | |                | |
| | Jobs: 1 active  | |                               | |                | |
| | Runtime: 12m34s | |                               | |                | |
| +-----------------+ |                               | +----------------+ |
+---------------------+-------------------------------+--------------------+
```

### Left Panel

Contains two sections:

- **Design Info** -- Project name, flow type, phase, run name, and overall run status. Always visible.
- **Node Info** -- Detailed information about the currently selected node. Updates when you click a node in the DAG canvas.

### Center Panel (DAG Canvas)

The main visualization area showing the RACE DAG as a directed graph. Nodes are drawn as rectangles with color-coded status. Edges show dependency relationships. Supports zoom, pan, and interactive selection.

### Right Panel (Properties)

Context-sensitive panel that appears when editing configuration or MMMC scenarios. Hidden by default to maximize canvas space.

---

## 3. DAG Visualization

### Node Status Colors

Each node in the DAG is rendered with a background color corresponding to its current execution status:

| Status | Color | Description |
|--------|-------|-------------|
| **READY** | Purple | Node is ready to execute (all dependencies met) |
| **PENDING** | Blue | Node is waiting for dependencies to complete |
| **RUNNING** | Yellow | Node is currently executing |
| **DONE** | Green | Node completed successfully |
| **FAIL** | Red | Node execution failed |
| **BYPASSED** | Gray | Node was skipped via bypass command |
| **FORCE_VALIDATED** | Green (outlined) | Node was force-validated without execution |

### Color Legend

A color legend is displayed in the top-right corner of the DAG canvas for quick reference:

```
+-------------------------------------------+
| Legend:                                    |
| [####] READY    [####] PENDING            |
| [####] RUNNING  [####] DONE              |
| [####] FAIL     [####] BYPASSED          |
| [####] FORCE_VALIDATED                    |
+-------------------------------------------+
```

### Proportional Color Segments

When a node contains subnodes (e.g., `place1` has `setup`, `run`, `validate`, `finish`), the node rectangle is divided into proportional color segments reflecting the status of each subnode:

```
+-----place1------+
|  G  | Y |  B  |B|    G=green(setup done), Y=yellow(run active),
+------------------+    B=blue(validate+finish pending)
```

This provides at-a-glance progress visibility without expanding into the subnode view. A node with all subnodes complete appears fully green. A node with a failed subnode shows a red segment at the point of failure.

### Edge Rendering

- **Solid lines** connect nodes in dependency order (left to right)
- **Branch labels** appear on edges when branches exist (see [Branch Management](#6-branch-management))
- **Arrow direction** indicates execution flow (upstream to downstream)

---

## 4. Node Selection and Info Panel

### Selecting a Node

Click any node in the DAG canvas to select it. The selected node is highlighted with a bold border, and its details appear in the **Node Info** section of the left panel.

### Node Info Panel Details

| Field | Description |
|-------|-------------|
| **Name** | Node name (e.g., `place1`). Editable for custom nodes -- type a new name and click **Rename**. |
| **Type** | Flow type (e.g., `PNR`, `STA`, `ECO`) |
| **Status** | Current execution status (READY, PENDING, RUNNING, DONE, FAIL, BYPASSED, FORCE_VALIDATED) |
| **Branch** | Branch name if node belongs to a branch (default: `main`) |
| **Tag** | Branch tag if assigned (e.g., `experiment_v2`) |
| **Dependencies** | List of upstream nodes this node depends on |
| **Jobs** | Number of active LSF jobs for this node (if applicable) |
| **Runtime** | Elapsed execution time (updates live while RUNNING) |

### Renaming Custom Nodes

For custom nodes (nodes added via `add-node` or `create-branch`), the Name field in the Node Info panel is editable:

1. Click the node to select it
2. In the Node Info panel, click the node name text field
3. Type the new name
4. Click the **Rename** button (or press Enter)

Built-in nodes from node_config.tcl cannot be renamed from the GUI.

---

## 5. Right-Click Context Menu

Right-click any node in the DAG canvas to open the context menu. Available actions depend on the node's current status.

### Context Menu Actions

| Action | Description | Available When |
|--------|-------------|----------------|
| **Run** | Execute this node | READY, PENDING, FAIL |
| **Retrace** | Mark this node and all downstream for re-execution | DONE, FAIL, FORCE_VALIDATED |
| **Bypass** | Skip this node (mark as bypassed) | READY, PENDING, FAIL |
| **Force** | Force re-run regardless of status | Any status |
| **Force Validate** | Mark as completed without executing | READY, PENDING, FAIL |
| **Edit Config** | Open the Config Editor for this node | Any status |
| **Duplicate** | Create a copy of this node with `_copy` suffix | Any status |
| **Create Branch** | Create a new branch starting from this node | Any status |
| **Rename** | Rename this node (custom nodes only) | Custom nodes only |
| **View Subnodes** | Enter the subnode view for this node | Any status |
| **MMMC Scenarios** | Open the MMMC Scenario Editor | STA nodes with MMMC |
| **Interactive Session** | Open an interactive EDA tool session loading this node's design | DONE |

### Example Usage

```
Right-click on "cts1" (status: DONE)
  +---------------------------+
  | Run                       |
  | Retrace             R     |
  | Bypass               Y    |
  | Force                      |
  | Force Validate       V    |
  |---------------------------|
  | Edit Config          E    |
  | Duplicate            D    |
  | Create Branch        B    |
  | Rename                     |
  |---------------------------|
  | View Subnodes              |
  | MMMC Scenarios       M    |
  | Interactive Session        |
  +---------------------------+
```

Keyboard shortcut letters are shown next to each action for quick access after selecting a node.

---

## 6. Branch Management

Branches let you create alternative execution paths from any point in the DAG. This is useful for exploring timing experiments, ECO variations, or tool parameter sweeps without modifying the original flow.

### Creating a Branch

1. Right-click the node where the branch should start
2. Select **Create Branch**
3. In the dialog, enter:
   - **Branch Name** (required): A descriptive name (e.g., `timing_experiment`)
   - **Tag** (optional): A version or label (e.g., `v1`, `aggressive_cts`)
4. Click **Create**

The new branch appears as a parallel path in the DAG, connected to the source node:

```
                       main
  [inputs1] -> [synth1] -> [place1] -> [cts1] -> [route1] -> ...
                                |
                                | timing_experiment (tag: aggressive_cts)
                                +-> [place1_b1] -> [cts1_b1] -> [route1_b1] -> ...
```

You can also create branches from the CLI:

```bash
cbflow run create-branch --name timing_experiment --from place1 --tag aggressive_cts
```

### Branch Labels

- **Node labels**: Branch nodes display their branch name below the node name
- **Edge labels**: Edges into a branch show the branch name and tag
- **Branch colors**: Each branch is assigned a distinct color for visual differentiation

### Deleting a Branch

1. Open the **Edit** menu in the top menu bar
2. Select **Delete Branch**
3. A list of branches appears. Hover over a branch name to highlight all nodes belonging to that branch in the DAG canvas.
4. Click the branch to delete it
5. Confirm the deletion in the dialog

All nodes in the deleted branch are removed from the DAG. Nodes in other branches or the main flow are unaffected.

---

## 7. Node Management

### Adding a Node

1. Use the **Edit** menu > **Add Node**, or use the CLI:

```bash
cbflow run add-node --node eco1 --type eco --dep signoff1
```

2. In the GUI dialog, specify:
   - **Node Name**: Unique name for the new node
   - **Node Type**: Flow type (e.g., `eco`, `sta`, `pnr`)
   - **Dependencies**: One or more existing nodes this node depends on

The new node appears in the DAG connected to its specified dependencies.

### Deleting a Node

1. Right-click the node > context menu (if available), or use the CLI:

```bash
cbflow run delete-node --node eco1
```

**Dependency protection**: You cannot delete a node if other nodes depend on it. The GUI shows an error message listing the dependent nodes. Remove or reassign the dependents first.

```
Error: Cannot delete "eco1" -- the following nodes depend on it:
  - eco_verify1
  - release_eco1
Remove these dependencies first.
```

### Renaming a Node

Rename a node from either:

- **Node Info panel**: Click the name field, type the new name, click **Rename**
- **Right-click menu**: Select **Rename**, enter the new name in the dialog
- **CLI**: `cbflow run rename-node --node old_name --new-name new_name`

Renaming automatically updates all dependency references throughout the DAG.

### Duplicating a Node

1. Right-click the node > **Duplicate** (or press **D** with the node selected)
2. A copy is created with the `_copy` suffix (e.g., `place1` becomes `place1_copy`)
3. The duplicate has the same type and configuration but no execution status
4. Adjust dependencies as needed after duplicating

---

## 8. Config Editor

The Config Editor provides a GUI interface for viewing and modifying node configuration without manually editing TCL files. Changes are saved to `override_config.tcl` in the run's setup directory.

### Opening the Config Editor

Right-click any node > **Edit Config** (or press **E** with the node selected).

The Config Editor opens in the Right Panel with five configuration categories displayed as tabs.

### Configuration Categories

#### 8.1 Node Config

Settings from the flow's node configuration file (e.g., `SYNTH_PNR_config.tcl`).

| Setting | Example | Description |
|---------|---------|-------------|
| `stages` | `{inputs1 synth1 place1 ...}` | Stage list |
| `dependencies,place1` | `{synth1}` | Node dependencies |
| `subnodes,place1` | `{setup run validate finish}` | Subnode list |
| `runtime,timeout,place1` | `120` | Timeout in minutes |

#### 8.2 Tool Config

Settings from the tool-specific configuration file. For Fusion Compiler flows, this is `fc_config.tcl`. For PrimeTime flows, `pt_config.tcl`, and so on.

Tool config variables follow the convention of two scopes:

- **`fc(common,*)`** -- Settings shared across all nodes in the flow
- **`fc(<node>,*)`** -- Settings specific to a particular node

```tcl
# Common settings (apply to all nodes)
fc(common,enable_clock_gating)        true
fc(common,target_library)             "sc7p5t_cln28hpm_base_rvt_c14_tt_nominal_max_0p90v_25c.db"
fc(common,enable_spg)                 true

# Node-specific settings (override common for this node only)
fc(place1,congestion_effort)          high
fc(place1,enable_coarse_placement)    false
fc(cts1,max_skew)                     50
fc(route1,detail_route_effort)        high
```

The Config Editor shows both common and node-specific tool settings. When editing a value, you can choose whether the change applies to the common scope or only to the selected node.

#### 8.3 LSF & Resources

Controls LSF job submission parameters for the selected node.

| Setting | Values | Description |
|---------|--------|-------------|
| Queue Tier | S, M, L, XL, Ultra | LSF queue size tier |
| Memory | 4G - 128G | Memory resource requirement |
| CPU Count | 1 - 64 | Number of cores |
| Runtime Limit | 30 - 2880 min | Maximum wall-clock time |

#### 8.4 Flow Settings

General flow execution parameters.

| Setting | Values | Description |
|---------|--------|-------------|
| `flow(use_lsf)` | true / false | Enable LSF submission |
| `flow(use_xterm)` | true / false | Launch in xterm window |
| `flow(tool_module)` | Module string | Module to load (e.g., `synopsys/fc/2023.09`) |
| `flow(test_mode)` | true / false | Test mode (no EDA tools) |

#### 8.5 Exit Criteria

Milestone exit file requirements for the selected node's stage.

| Setting | Description |
|---------|-------------|
| Exit Files | List of files that must exist for the stage to pass exit checks |
| Exit Reports | Report files checked for pass/fail patterns |
| Exit Thresholds | Numeric thresholds (WNS, DRC count, etc.) |

### Search and Filter

The Config Editor includes a search bar at the top. Type any string to filter configuration variables by name or value. The filter applies across all five tabs simultaneously.

```
Search: [congestion          ]
  Showing 3 of 247 settings matching "congestion"
    fc(place1,congestion_effort)     = high
    fc(common,congestion_map_layers) = {M3 M4 M5}
    fc(route1,congestion_driven)     = true
```

### Editing Values

1. Click any value field to edit it
2. Modify the value
3. The changed field is highlighted to indicate unsaved changes

### Scope Toggles

When editing a value, a scope selector appears:

| Scope | Effect |
|-------|--------|
| **This node** | Override applies only to the selected node |
| **Branch** | Override applies to all nodes in the same branch |
| **All of this type** | Override applies to all nodes of the same flow type |

### Saving Changes

Click **Save** to write changes to `override_config.tcl`. The file is located at:

```
P0_run_SYNTH_PNR_run1/setup/override_config.tcl
```

All GUI config changes are saved as TCL `set` statements in this file. The override_config.tcl file sits at level 5 in the configuration hierarchy, overriding flow_config, project_config, tech_config, and user_config, but overridden by override_setup hooks.

---

## 9. MMMC Scenario Editor

The MMMC (Multi-Mode Multi-Corner) Scenario Editor manages which timing scenarios are active for STA and timing-related nodes.

### Opening the MMMC Editor

Right-click an STA node > **MMMC Scenarios** (or press **M** with an STA node selected).

### Scenario Checkboxes

Each defined timing scenario appears as a checkbox. Check or uncheck scenarios to include or exclude them from the run:

```
MMMC Scenario Editor - timing1
+---------------------------------------------------+
| [ ] Select All    [Filter: _________ ]            |
|                                                   |
| [x] func_ss_0p72v_rcmax_125c       (setup)       |
| [x] func_ff_0p84v_rcmin_m40c       (hold)        |
| [ ] func_tt_0p80v_rctyp_25c        (typical)     |
| [x] func_sf_0p72v_rcmax_m40c       (hold)        |
| [ ] scan_ss_0p72v_rcmax_125c       (scan setup)  |
| [ ] scan_ff_0p84v_rcmin_m40c       (scan hold)   |
+---------------------------------------------------+
| Quick-Assign Sets:                                |
|   [All Setup]  [All Hold]  [All Func]  [All Scan] |
|   [Signoff Set]  [Debug Set]                      |
+---------------------------------------------------+
|                        [Apply]  [Cancel]           |
+---------------------------------------------------+
```

### Quick-Assign Sets

Pre-defined scenario groups for common use cases:

| Set | Description |
|-----|-------------|
| **All Setup** | Select all setup-critical scenarios (ss corners) |
| **All Hold** | Select all hold-critical scenarios (ff corners) |
| **All Func** | Select all functional mode scenarios |
| **All Scan** | Select all scan/test mode scenarios |
| **Signoff Set** | Select the standard signoff scenario set |
| **Debug Set** | Select a minimal set for quick debug runs |

### Filters

Use the filter text box to narrow the scenario list by name, corner, or mode:

```
Filter: [rcmax]
  Showing 2 of 6 scenarios:
  [x] func_ss_0p72v_rcmax_125c
  [x] func_sf_0p72v_rcmax_m40c
```

### Applying Changes

Click **Apply** to update the active scenario set. If the flow is currently executing, the RACE engine picks up the change via active engine sync and adjusts the timing1 subnodes accordingly.

---

## 10. Keyboard Shortcuts

The GUI supports keyboard shortcuts for common operations. Shortcuts that operate on a node require a node to be selected first (click to select).

### Node-Level Shortcuts (requires node selection)

| Key | Action | Description |
|-----|--------|-------------|
| **R** | Retrace | Retrace from the selected node |
| **D** | Duplicate | Duplicate the selected node |
| **B** | Branch | Create a branch from the selected node |
| **V** | Force Validate | Force-validate the selected node |
| **Y** | Bypass | Bypass the selected node |
| **E** | Edit Config | Open Config Editor for the selected node |
| **M** | MMMC | Open MMMC Scenario Editor (STA nodes) |
| **S** | Stop | Stop execution of the selected node |

### Global Shortcuts (no selection required)

| Key | Action | Description |
|-----|--------|-------------|
| **F** | Fit to Window | Zoom and pan to fit the entire DAG in view |
| **L** | Reset Layout | Reset the DAG layout to default positions |
| **Esc** | Close | Close any open dialog, editor, or panel |
| **?** | Help | Show the keyboard shortcuts help overlay |

### Quick Reference Card

Press **?** at any time to display an overlay showing all available keyboard shortcuts.

---

## 11. Zoom and Pan Controls

### Zoom

- **Scroll wheel**: Zoom in/out centered on the cursor position
- **Pinch gesture**: Zoom on trackpad (macOS)
- The current zoom level is shown in the bottom-left corner of the canvas

### Pan

- **Click and drag** on empty canvas space to pan the view
- Works with both mouse and trackpad

### Fit to Window

- Press **F** to automatically zoom and pan so the entire DAG fits within the visible canvas area
- Also available via the toolbar button (fit icon)

### Moving Nodes

- **Ctrl+drag** (or Cmd+drag on macOS) on a node to reposition it within the canvas
- Node positions are preserved across auto-refresh cycles
- Custom positions reset when pressing **L** (Reset Layout)

---

## 12. Subnode View

Each node contains subnodes (typically `setup`, `run`, `validate`, `finish`). The subnode view lets you inspect and control execution at this finer granularity.

### Entering Subnode View

- **Double-click** a node in the DAG canvas, or
- **Right-click** > **View Subnodes**

The canvas zooms into the selected node, showing its subnodes as individual boxes in a left-to-right pipeline:

```
Subnode View: place1                          [< Back]
+----------+    +----------+    +----------+    +----------+
|  setup   | -> |   run    | -> | validate | -> |  finish  |
|  (DONE)  |    | (RUNNING)|    | (PENDING)|    | (PENDING)|
+----------+    +----------+    +----------+    +----------+
   0m02s           12m34s
```

### Returning to DAG View

- Click the **Back** button in the top-left corner of the canvas
- The view automatically fits the full DAG when returning (equivalent to pressing **F**)

### Subnode-Level Actions

Within the subnode view, you can right-click individual subnodes for a subset of context menu actions (Run, Retrace, Bypass, Force Validate).

---

## 13. Execution Control

The GUI provides direct execution control, synchronized with the RACE engine in real time.

### Run Controls

Available in the top toolbar:

| Button | Action | Description |
|--------|--------|-------------|
| **Run All** | Execute the complete DAG | Equivalent to `cbflow run all` |
| **Run Stage** | Execute the selected node only | Equivalent to `cbflow run stage --name <node>` |
| **Stop** | Stop the currently running execution | Gracefully terminates the active run |

### Retrace During Execution

You can issue retrace, bypass, and force-validate commands while the engine is actively running. The RACE engine uses **active engine sync** to detect changes in the SQLite DB and adjust its execution plan in real time:

1. While `Run All` is in progress, right-click a completed node
2. Select **Retrace**
3. The node and all downstream nodes are marked for re-execution
4. The running engine picks up the change and re-executes the affected nodes

This is the same active engine sync mechanism available from the CLI:

```bash
# Terminal 1: Engine running
cbflow run all

# Terminal 2: Retrace while running
cbflow run retrace --from cts1
```

### Execution Status Indicators

- The **Design Info** panel shows overall run status (IDLE, RUNNING, COMPLETE, FAILED)
- Active nodes pulse with a yellow animation
- The toolbar shows a progress indicator during execution

---

## 14. Auto-Refresh and Live Updates

The GUI automatically polls the RACE SQLite database for status changes, providing a live view of execution progress.

### Polling Interval

The dashboard polls every **2 seconds** for updates. This interval balances responsiveness with minimal system overhead.

### What Gets Updated

- Node status colors (PENDING -> RUNNING -> DONE transitions)
- Subnode progress segments within nodes
- Runtime counters for active nodes
- Design Info panel overall status
- New nodes added via CLI (`add-node`, `create-branch`)

### View Preservation

Auto-refresh preserves your current view state:

- **Zoom level** is maintained across updates
- **Pan position** is maintained across updates
- **Node selection** is maintained (selected node stays selected)
- **Custom node positions** (from Ctrl+drag) are preserved

### Smart SVG Update

The GUI uses a smart differential SVG update mechanism. Instead of re-rendering the entire DAG on each poll cycle, only the elements that have changed (node colors, status text, progress segments) are updated. This eliminates visual flicker and provides a smooth experience even with large DAGs.

### Manual Refresh

If you need to force an immediate refresh (e.g., after making changes via CLI), press **F5** or click the refresh button in the toolbar.

---

## Appendix A: Typical Workflow

A typical session using the CBflow GUI:

```
1. Create workspace and run
   $ cbflow workspace create --config user_config.tcl
   $ cd P0_run_SYNTH_PNR_run1/

2. Launch the GUI
   $ cbflow run gui
   -> Opens http://localhost:8080

3. Start execution
   Click "Run All" in the toolbar (or run "cbflow run all" in a terminal)

4. Monitor progress
   Watch nodes transition: purple(READY) -> yellow(RUNNING) -> green(DONE)
   Click nodes to see runtime, jobs, and subnode progress

5. Investigate a failure
   Red node appears -> click to select -> check Node Info for details
   Double-click to enter subnode view and identify which subnode failed

6. Edit configuration
   Right-click failed node -> Edit Config -> adjust parameters
   Changes saved to override_config.tcl

7. Retrace and re-run
   Right-click the fixed node -> Retrace (marks it and downstream for re-run)
   Click "Run All" to resume

8. Branch for experiments
   Right-click a node -> Create Branch -> name it "aggressive_timing"
   Edit config on the branch nodes independently

9. Force validate clean stages
   Right-click a known-good node -> Force Validate
   Skips re-execution for nodes that don't need re-running
```

---

## Appendix B: Troubleshooting

**Problem:** Dashboard fails to start -- "No available port in range 8080-8180"
- **Cause:** All 101 ports in the auto-port range are occupied
- **Fix:** Use `--port` to specify a port outside the default range, or close unused dashboards

**Problem:** Node colors not updating
- **Cause:** RACE database not being written to (engine may have crashed)
- **Fix:** Check the engine terminal for errors. Restart with `cbflow run all`.

**Problem:** Config Editor changes not taking effect
- **Cause:** The override_config.tcl was saved, but the stage was not retraced
- **Fix:** Right-click the node > Retrace, then re-run

**Problem:** Cannot rename a node
- **Cause:** Built-in nodes from node_config.tcl cannot be renamed
- **Fix:** Only custom nodes (added via add-node or create-branch) support renaming

**Problem:** Cannot delete a node -- "dependency protection" error
- **Cause:** Other nodes depend on the node you're trying to delete
- **Fix:** Delete or reassign the dependent nodes first

---

**See also:**
- [Complete User Guide](cbflow-complete-user-guide.md) -- Full CBflow walkthrough
- [Flow User Guide](cbflow-flow-user-guide.md) -- All 12 flows with stages
- [System Design](../04-architecture/system-design.md) -- RACE engine architecture
- [RACE Command Reference](../03-reference/makefile-reference.md) -- All RACE commands
