# Data Flow

How data moves through CBflow: from a user config to a run, from a run to an
exit release, and from a release into the next flow and SmartGrid. Paths are
relative to `$CBFLOW_ROOT`.

> Framework (CBflow code) versioning — `cbflow flow version` / `cbflow flow dev`
> — is a separate topic: see [Versioning Strategy](git-strategy.md) and the
> [Versioning Workflow](../02-user-guide/versioning-workflow.md).

---

## 1. Workspace creation

```
workarea/<block>/uc_<FLOW>.tcl                 user config (flow(type), flow(design_name), flow(run_name), …)
        │  cbflow workspace create --config uc_<FLOW>.tcl
        ▼
global/utils/commands/workspace_cmd.py + start_run.py
  - flow(discipline,<FLOW>)  → discipline root (PD/ DFT/ DV/ RTL/)
  - project(workarea_path)   → run dir must sit under it
  - _preflight_launch_bins   → bsub / xterm present when use_lsf / use_xterm
        ▼
<workarea>/<block>/<phase>_run_<FLOW>_<block>_<run>/
  .run.cbflow.env / .run.cbflow.tcl   FLOW_DIR, CONFIG_ROOT, SCRIPTS_ROOT, CBFLOW_*, *_VERSION, CBFLOW_PROJECT_PHASE
  setup/user_config.tcl               the user config
  setup/override_config*.tcl          (optional, per node — run GUI writes these)
  setup/runtime_flow_config.tcl       (add-node / create-branch / set-dep)
  work/<FLOW>/<node>/…                created per node
  .race_db_pointer                    → project(race,db_path)/<proj>/<DISC>/<FLOW>/<run>_<user>_<hash>.db
```

A stale DB at the same path is archived as `<db>.stale-<ts>` (with `-wal` / `-shm`).

## 2. Run execution

```
cbflow run all | stage --name <node>
        ▼
race_engine.py  DagBuilder  ── config_resolver.tcl (full cascade, resolved vars) ──┐
        │       stages / dependencies / subnodes / dynamic scenario fan-out         │
        ▼                                                                           │
for each ready job (≤ flow(max_parallel_jobs)):                                     │
  tclsh <DISC>/cmds/<FLOW>/<vendor>/<tool>/<ver>/<type>_subnode_handler.tcl <subnode> <run_dir> <node>
        │                                                                           │
        ├─ setup     generate_setup.tcl → work/<FLOW>/<node>/run/config.tcl + setup.tcl
        ├─ run       launch wrapper → tool shell (lsf(tool_shell,<tool>); cbflow-oss for opensource)
        │              └─ command file: bootstrap → flow_proc … → flow_exec_all
        │                   reads  work/<FLOW>/<upstream>/outputs/…  (oss_upstream_node / cbflow_chain_node)
        │                   writes work/<FLOW>/<node>/{reports,outputs,logs}/…
        ├─ validate  mandatory outputs present (production mode)
        └─ finish    timestamp; release node → optional SmartGrid publish
        ▼
StatusDB  jobs / run_logs / stage_metrics / lsf_details / … (SQLite, WAL)
```

Inputs nodes resolve upstream data before anything runs (next section).

## 3. Inputs: handshake resolution

```
<flow>(input,<x>)                     explicit path         ─┐ highest
<flow>(input,<x>_release_tag)         per-input tag          │
<flow>(input,release_tag)             generic tag            │
<flow>(input,from_run)                sibling run manifest  ─┘
        │  resolve_inputs.tcl::resolve_flow_inputs
        │  flow_input_handshake(<FLOW>,<x>) {<src_flow|ANY> <category> "<file>"}   (PD release_config.tcl §6)
        ▼
<release,path>/<phase>/<block>/<SRC_FLOW>/<tag>/<category>/<file>   (must carry RELEASE_COMPLETE)
        ▼
staged into work/<FLOW>/inputs1/… under the block-named convention (<design>.v, <design>.<mode>.sdc, …)
```

Signoff flows (STA / PV / LEC) take only the release of the exit they verify
(`<flow>(release,exit_from)`); `<flow>(release,exit_exempt_inputs)` lists
exceptions.

## 4. Release

```
export_data1 ──► release_data1        (PD: source stage = cbflow_source_node, bypassed nodes skipped)
        │  ::CBFlow::Release (release_utils.tcl)
        │    tag   = project(release,tag) | exit (default_exit_tag / release_exit_for_stage)
        │    phase = CBFLOW_PROJECT_PHASE
        │    check_exit_order: earlier exits of project(phase_exits[,<DISC>]) released
        ▼
<release,path>/<phase>/<block>/<FLOW>/<tag>/
    <category>/…  MANIFEST.json  RELEASE_NOTES.md  RELEASE_COMPLETE
```

`cbflow run release --from-run <run> [--node <n>] [--clone-from <exit> --tag <exit>] --publish`
releases / clones / publishes from the CLI.

## 5. Publish and SmartGrid

```
release node finish (project(release,publish) true)  or  cbflow run release … --publish
        │  publish order gate: earlier exits already on SmartGrid
        ▼
SmartGrid tracker DB (~/.cbflow/project-dashboard by default, flow(smartgrid,state_dir))
        ▼
cbflow smartgrid start --project <p>
  /                      published runs per flow (signoff runs attach to their exit)
  /project/<p>           discipline cards + project section
  /project/<p>/releases  exit-centric releases; /checklist (waivers); /schedule; /team
  /project/<p>/chain     spec-to-GDS sign-off chain (project(signoff_chain,<phase>))
```

## 6. Spec-to-GDS chain (cross-discipline)

```
RTL_SPEC ──SPEC_EXIT──► RTL_LINT ──LINT_SIGNOFF──► SYNTH ─► FP ─► PNR ─► STA / PV / LEC
             │          RTL_CDC  ──CDC_SIGNOFF        │                     (signoff exits)
             │          UPF_CHECK──UPF_SIGNOFF        └─ scandef ─► SCAN_INSERT ─► ATPG ─► GLS
             └─ spec / RAL / vPlan ──► TB_SETUP ─► M1..M4_EXEC ─► DV_SIGNOFF
```

Each arrow is a release consumed through a handshake entry; the order and tags
are data in `project(signoff_chain,<phase>)` and `workarea/run_spec2gds.sh`
drives it. See the [Spec-to-GDS Guide](../02-user-guide/spec-to-gds-guide.md).

---

**See also:**
- [System Design](system-design.md) — overall architecture
- [Component Design](component-design.md) — module map
