# MSCTS (Multi-Source CTS) / Multipoint CTS Reference

Synopsys' canonical name for "multipoint CTS" is **MSCTS** — Multi-Source
Clock Tree Synthesis. CBflow ships an FC-RM-aligned MSCTS recipe as a
**standalone** Tcl script that the user can source from a custom hook or
interactive session. It is intentionally **not wired into** the default
`cts_fc.tcl` handler.

## Where it lives

```
PD/cmds/PNR/synopsys/fc/v1.0.0/mscts_fc.tcl
```

Direct port (1:1 logic and command names) of FC-RM Y-2026.03
`examples/mscts.regular.tcl`. Keeping it 1:1 means a future FC-RM bump
is a diff-and-merge rather than a rewrite.

## What it does

Builds a global clock distribution as one of:

| Topology | Behavior |
|---|---|
| `htree` (default) | H-tree from clock root → tap drivers → subtrees, with integrated tap assignment so the subsequent `clock_opt_cts` picks up the tap structure automatically |
| `subtree_only` | User-provided mesh net + auto tap-driver insertion onto it; useful when the chip already has a custom clock mesh and you only want CBflow to insert/legalize taps |

Both modes finish with `set_multisource_clock_tap_options -driver_objects
<tap_pins>` so the next CTS run sees them.

## When to run

After initial placement, before `clock_opt_cts`. In a CBflow run this
means either:

1. **From an interactive session** — most common workflow when bringing
   MSCTS up on a new block:
   ```bash
   cbflow run interactive --node place1
   # inside fc_shell:
   fc_shell> source <path>/mscts_inputs.tcl       ;# your MSCTS_* var settings
   fc_shell> source $::env(FLOW_DIR)/cmds/PNR/synopsys/fc/v1.0.0/mscts_fc.tcl
   ```

2. **From a custom hook** — when production needs MSCTS routinely, drop
   a hook that sources this file at the right point. Sample hook
   (place_opt post-script):
   ```tcl
   # setup/place_opt_post_hook.tcl in the run dir
   source /path/to/mscts_inputs.tcl
   source $::env(FLOW_DIR)/cmds/PNR/synopsys/fc/v1.0.0/mscts_fc.tcl
   ```

   Then in `user_config.tcl`:
   ```tcl
   set pnr(hooks,place_opt_post) "setup/place_opt_post_hook.tcl"
   ```

## Required inputs

Set these as Tcl variables BEFORE sourcing `mscts_fc.tcl`. The script's
own header lists all of them; the essentials:

| Variable | Purpose |
|---|---|
| `MSCTS_CLOCK` | Clock name (or list of clock names) |
| `MSCTS_SOURCE` | Clock root pin/port (or list) |
| `MSCTS_TOPOLOGY` | `"htree"` (default) or `"subtree_only"` |
| `MSCTS_PITCH` | Tap-driver grid pitch in design units (e.g. `100`) |
| `MSCTS_TAP_DRIVER_LIB_CELLS` | Lib-cell names for tap drivers |

For `htree` mode add:

| Variable | Purpose |
|---|---|
| `MSCTS_HTREE_LIB_CELLS` | Lib-cell names for H-tree drivers |
| `MSCTS_HTREE_NDR_RULE_NAME` | NDR rule applied to the H-tree |
| `MSCTS_HTREE_MIN_ROUTING_LAYER` / `MSCTS_HTREE_MAX_ROUTING_LAYER` | H-tree routing layer band |

For `subtree_only` mode add:

| Variable | Purpose |
|---|---|
| `MSCTS_MESH_NET` | Existing mesh net name |
| `MSCTS_MESH_NET_PORT` | Port driving the mesh net |
| `MSCTS_MESH_NET_PORT_TRANSITION` / `MSCTS_MESH_NET_PORT_DELAY` | Annotation at the mesh-net port |
| `MSCTS_INPUT_TRANSITION` / `MSCTS_NET_DELAY` | Tap-driver input transition + net delay |

Optional (both modes): `MSCTS_NET`, `MSCTS_TAP_DRIVER_MAX_DISPLACEMENT`,
`MSCTS_TAP_BOUNDARY`, `MSCTS_MACRO_KEEPOUT`,
`TCL_USER_MESH_ANNOTATION_SCRIPT`. See the script header for details.

## Sample inputs file

```tcl
# mscts_inputs.tcl — typical htree configuration
set MSCTS_CLOCK                      "core_clk"
set MSCTS_SOURCE                     "CLK_IN"
set MSCTS_TOPOLOGY                   "htree"
set MSCTS_PITCH                       150
set MSCTS_TAP_DRIVER_LIB_CELLS       {CKINVD12 CKINVD16 CKINVD24}
set MSCTS_HTREE_LIB_CELLS            {CKINVD24 CKINVD32}
set MSCTS_HTREE_NDR_RULE_NAME        "clock_2W2S"
set MSCTS_HTREE_MIN_ROUTING_LAYER    "M5"
set MSCTS_HTREE_MAX_ROUTING_LAYER    "M7"
set MSCTS_TAP_DRIVER_MAX_DISPLACEMENT  20
set MSCTS_MACRO_KEEPOUT              "true"
```

## Inputs validation

The script aggregates ALL missing-required-input errors before bailing
— you see the full list instead of one-error-per-run trial-and-error.
On any missing required var:

```
RM-error: MSCTS clock not defined.
RM-error: MSCTS tap drivers not defined.
RM-error: MSCTS NDR rule not defined.
RM-info: Errors encountered. There are requirements not met.
[script aborts with: MSCTS input validation failed]
```

## What the script touches (high-level)

| Phase | FC command |
|---|---|
| MV support | `set_app_options cts.multisource.enable_full_mv_support`, `opt.common.allow_physical_feedthrough` |
| Clear dont-touch on clock root | `set_dont_touch_network -clear`, `mark_clock_trees -clear` |
| H-tree synthesis | `set_regular_multisource_clock_tree_options`, `synthesize_regular_multisource_clock_trees` |
| Subtree-only tap insertion | `create_clock_drivers -loads <mesh_net>` |
| Mesh-net annotation | `set_annotated_transition`, `set_annotated_delay` (rise/fall × max/min) |
| Tap assignment for CTS | `set_multisource_clock_tap_options -driver_objects <tap_pins>` |

## Verification done locally

```
# Empty inputs → all required-var errors fire, aborts cleanly:
RM-error: MSCTS clock not defined.
RM-error: MSCTS clock source not defined.
RM-error: MSCTS tap drivers not defined.
[...]

# Minimal htree inputs (stubbed FC cmds) → completes:
DEBUG: x is 5 and y is 5
input number: 5; output number: 8
RM-info: MSCTS construction completed (topology=htree)

# subtree_only inputs (stubbed) → completes:
RM-info: TCL_USER_MESH_ANNOTATION_SCRIPT() is not defined. Applying default annotation
RM-info: MSCTS construction completed (topology=subtree_only)
```

## When to wire it into the default cts_fc.tcl

Right now we deliberately don't — Innovus integration is one piece of
work, MSCTS another. Once production has run MSCTS on a real block via
the interactive/hook path above and confirmed timing closure, we can
add a `pnr(cts,style) "MSCTS"` knob in `PNR_fc_config.tcl` and source
`mscts_fc.tcl` from `cts_fc.tcl::configure_cts` when that knob is set
(matching FC-RM's `CTS_STYLE == "MSCTS"` gate in `place_opt.tcl`).
