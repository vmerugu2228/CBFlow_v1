# Exit Releases — User Guide

This guide covers how a run releases its design data to an **exit milestone**,
for example FP_EXIT, PLACE_EXIT or BTO, and how that release reaches SmartGrid.
It does not cover framework versioning; for that, see [Release Management](release-management.md).

---

## 1. Layout and tag

A release is written to:

```
<project(release,path)>/<phase>/<block>/<FLOW>/<tag>/
```

Each part is resolved like this:

- **phase** is always the run's phase, `CBFLOW_PROJECT_PHASE`. Workspace create takes it from `project(phase)` in the user config, else `project(current_phase)`. The key `project(release,phase)` is no longer read for the layout.
- **block** is `project(release,block_name)`, else the design name.
- **tag** is `project(release,tag)` when it is set. Otherwise the tag is the **exit name**.

A re-release replaces the existing directory. A finished release contains `RELEASE_COMPLETE` (`STATUS=PASS|…`) and `MANIFEST.json`.

### Exits per phase

The exits each phase delivers are project-defined. This is the opensky example:

```tcl
set project(phase_exits) {
    P0 {FP_EXIT PRO_EXIT}
    P1 {FP_EXIT PRO_EXIT}
    P2 {FP_EXIT PLACE_EXIT CTS_EXIT PRO_EXIT BTO MTO}
    P3 {FP_EXIT PLACE_EXIT CTS_EXIT PRO_EXIT BTO MTO}
}
```

The global order is `MILESTONE_ORDER {FP_EXIT PLACE_EXIT CTS_EXIT PRO_EXIT BTO MTO}`
in `PD/config/flow/v1.0.0/release_config.tcl`. The flows each exit expects are
listed in `release_tags(<exit>) {... required_flows {...}}`, for example
`FP_EXIT` requires `{SYNTH_PNR PNR FP FCFP PV}`.

---

## 2. The release follows its source stage

An `export_data` / `release_data` pair releases its **source stage**. The
source stage is the nearest non-bypassed implementation node upstream of the
export node, following the first-dependency chain.

The exit comes from `MILESTONE_STAGE_MAPPING(<exit>)` in `release_config.tcl`:

| Source stage | Exit |
|---|---|
| `init_design` | FP_EXIT |
| `place` | PLACE_EXIT |
| `cts_opt` | CTS_EXIT |
| `pro` | PRO_EXIT |
| `signoff` | BTO (or MTO) |

- The exit is clamped to the phase's exits. If the phase does not have that exit, the phase's latest earlier exit is used.
- `cts` and `route` have no exit of their own, so releasing them is an error.
- A release before `pro` carries no SPEF.
- A release before `signoff` carries no timing models.

Today the source-stage exit is applied by the open-source PNR release (`release_data_openroad.tcl`).

---

## 3. Releasing an intermediate stage (e.g. place → PLACE_EXIT)

There are three ways to do it.

**1. Bypass the stages after it:**

```bash
cbflow run bypass --stages cts1,cts_opt1,route1,pro1,signoff1
cbflow run stage --name release_data1
```

**2. Rewire export onto the stage.** On the CLI:

```bash
cbflow run set-dep --node export_data1 --deps place1
cbflow run stage --name release_data1
```

In the run dashboard, right-click `export_data1` and choose **Set Dependencies…**.

**3. Add an export + release pair under the stage:**

```bash
cbflow run add-node --node export_data2  --type export_data  --dep place1
cbflow run add-node --node release_data2 --type release_data --dep export_data2
cbflow run stage --name release_data2
cbflow run release --from-run . --node release_data2 --publish
```

`workarea/test_place_release.sh` runs all three. `SRC=place1` gives PLACE_EXIT and `SRC=cts_opt1` gives CTS_EXIT.

### `set-dep`

```bash
cbflow run set-dep --node <node> --deps <a>[,<b>...]   # comma- or space-separated
cbflow run set-dep --node <node> --reset               # back to the node config's deps
```

- Base-node changes are stored as `dep_overrides` in `setup/runtime_flow_config.tcl`.
- Custom nodes have their deps edited directly. `--reset` applies only to base-node overrides.
- Cycles are refused.

### Bypass markers

A stage whose jobs are all bypassed gets the marker `work/<FLOW>/<node>/BYPASSED`.
Command files and the source-stage lookup read the marker through `cbflow_node_bypassed`.
A retrace or force removes it.

---

## 4. Releasing the same data as another exit (e.g. MTO = BTO)

**Same run, new tag.** Set the release node's tag to the other exit. Either use the release form in the run dashboard and click **Save**, or write the file yourself:

```tcl
# setup/override_config.release_data1.tcl
set project(release,tag) "MTO"
```

Then re-run the release node:

```bash
cbflow run retrace --from release_data1 && cbflow run stage --name release_data1
```

A tag that names an exit becomes the milestone only when it maps to the **same
source stage**. BTO and MTO both map to signoff, so that works. Another stage's exit is refused. A tag that is not an exit name keeps the source-stage exit as the milestone.

**Clone a finished release:**

```bash
cbflow run release --from-run <run_dir> --clone-from BTO --tag MTO [--publish]
```

- This copies `<FLOW>/BTO` to `<FLOW>/MTO`.
- It requires that `BTO` is `RELEASE_COMPLETE` with `STATUS=PASS`, that both exits map to the same stage, and that the exit order holds.
- It records `CLONED_FROM` and rewrites the `MANIFEST.json` / `RELEASE_COMPLETE` tag.

---

## 5. `cbflow run release` options

| Option | Meaning |
|---|---|
| `--tag`, `-t <exit>` | Exit to release (default `project(release,active_tag)`) |
| `--name <tag>` | Release tag name (default: the exit name) |
| `--dry-run` | Validate only |
| `--from-run <run_dir>` | Use the release a run already made (open-source flows release themselves in `release_data`); no repackaging |
| `--node <release_node>` | With `--from-run`: which release node (default the flow's `release_data` node) |
| `--clone-from <exit>` | With `--from-run` and `--tag`: copy that exit's release to `--tag` |
| `--publish` | Publish to SmartGrid. Starts the daemon if needed and fails on a publish error |
| `--no-publish` | Skip publishing |
| `--override` | Replace an existing SmartGrid entry for (project, block, phase, milestone) |

Publishing is **opt-in**: without `--publish`, nothing is published.

---

## 6. Exit order gates

There are two gates.

1. **Release time.** `::CBFlow::Release::check_exit_order` refuses an exit while
   any earlier exit of the phase (`project(phase_exits)`) has no
   `RELEASE_COMPLETE` for the block, in any flow. The gate is skipped in test mode and for
   signoff flows.
2. **Publish time.** SmartGrid refuses a milestone that the phase does not have, or one whose earlier exits are not published yet for (project, block, phase):

   ```
   Not published: PRO_EXIT cannot release before FP_EXIT for gcd / P2.
   Release in order: FP_EXIT -> PLACE_EXIT -> CTS_EXIT -> PRO_EXIT -> BTO -> MTO (next: FP_EXIT).
   ```

Neither gate has a bypass flag. `--override` only replaces an existing entry.
`workarea/test_exit_order.sh` demonstrates the gate.

---

## 7. Signoff flows read only their exit's release

STA, PV and LEC verify one exit, and they read only that exit's release. Each overlay names the input that carries the exit:

| Flow | `<flow>(release,exit_from)` | `<flow>(release,exit_exempt_inputs)` |
|---|---|---|
| STA (opensta) | `input,release_tag` | `{}` |
| PV (magic) | `input,release_tag` | `{}` |
| LEC (yosys) | `input,netlist_revised_release_tag` | `{netlist_golden}` |

Inputs are strict. For a non-exempt input, the run refuses:

- `input,from_run`
- explicit `input,<X>` paths
- `input,<X>_release_tag` values other than the exit tag

The signoff release goes to `<block>/<FLOW>/<exit>`, and its publish attaches to that exit's cell. The exit entry must already be published. With `PV_MODE=hier`, `run_signoff.sh` releases to `<exit>_HIER`, which shows as a "PV HIER" variant chip.

---

## 8. Release node form and auto-publish

When you select a `release_data` node in the run dashboard, it shows a release form with these fields:

- the released tag
- an editable tag (empty means the exit name)
- **Publish to SmartGrid**
- **Replace existing entry**

**Save** writes to `setup/override_config.<node>.tcl`; it does not run anything:

```tcl
set project(release,tag)              "MTO"
set project(release,publish)          true
set project(release,publish_override) false
```

When the node runs again and finishes, `handler_publish_release` runs
`cbflow run release --from-run <run> --node <node> --publish [--override]`
if `project(release,publish)` is true. It does not publish in test mode.

---

## 9. Per-node overrides

`setup/override_config*.tcl` files apply in this order, lowest priority first. A later file wins.

1. `override_config.tcl`: all nodes
2. `override_config.<stage>.tcl`: e.g. `override_config.place.tcl`
3. `override_config.<branch>.tcl`
4. `override_config.<node_type>.tcl`
5. `override_config.<node>.tcl`: e.g. `override_config.release_data1.tcl`

There is no flow-name level. Put flow-wide settings in `override_config.tcl`,
for example the PNR fanout limit:

```tcl
set pnr(oss,drv,max_fanout) 10
```

The `override_setup.tcl` / `override_setup.<stage>.tcl` / `override_setup.<node>.tcl` files hold flow-proc hooks.

---

## See also

- [Open-Source Flow Guide](opensource-flow-guide.md): workarea scripts that chain releases
- [SmartGrid / Project Dashboard](project-dashboard-guide.md): releases page, publish
- [Library Manager](library-manager-user-guide.md): consuming block releases in a library tag
