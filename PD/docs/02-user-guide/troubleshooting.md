# Troubleshooting Guide

Common problems with CBflow runs, releases, libraries and dashboards, with the message you see and the fix.
For framework versioning (`cbflow flow version` / `cbflow flow release` / `cbflow flow dev`), see the last section.

---

## 1. Installation and environment

### `cbflow: command not found` / wrong install picked up

```bash
export CBFLOW_ROOT=/path/to/CBflow_clone
export PATH=$CBFLOW_ROOT/bin:$PATH
cbflow --version        # prints the resolved root, global and discipline directories
```

Only `CBFLOW_ROOT` is user-facing; do not export `CBFLOW_CORE_DIR` / `CBFLOW_GLOBAL_DIR` by hand (the launcher
derives them). Copy the whole umbrella install — `PD/` alone cannot run, because every run sources `global/`.

### `.run.cbflow.tcl not found` / run command rejected

`cbflow run …` must be run from inside a run directory (`<phase>_run_<FLOW>_<block>_<run>/`).
`cbflow workspace create` must be run from the block's workarea, `<project(workarea_path)>/<block>/`.

### Which value did the run actually use?

```bash
cbflow run debug --dump-resolved-cfg --key 'flow(use_lsf)'   # value + the file that set it
cbflow run report --node place1 --dump-setup                  # node's config.tcl / setup.tcl
grep 'flow(test_mode)' work/*/*/run/config.tcl | head
```

---

## 2. Workspace create

### `Workspace create blocked` — bsub / xterm / DISPLAY

`workspace create` checks the launch mode before creating anything and removes a partial run directory on failure:

| Setting | Needs |
|---|---|
| `flow(use_lsf) "true"` | `bsub` on `PATH` (or `CBFLOW_BSUB_CMD`) |
| `flow(use_xterm) "true"` (the default) | `xterm` on `PATH`; `$DISPLAY` at run time |

Fix: install the tool, or set `flow(use_xterm) "false"` / `flow(use_lsf) "false"` in the user config. Values must
be booleans (`true/false/1/0/yes/no/on/off`); anything else is an error. `flow(test_mode) "true"` skips the check.

### Run already exists

```bash
cbflow workspace create --config uc_PNR.tcl --force    # DESTRUCTIVE: removes the existing run
```

Or change `flow(run_name)`. `--accept-restricted` (alias `--yes`) accepts restricted-variable overrides without the
prompt; it does not recreate a run.

### `disk I/O error` / stale RACE DB

`workspace create` archives a stale RACE DB (with its `-wal` / `-shm`) as `<db>.stale-<ts>` and creates a new
one. If the race area is full or on a bad mount, check `project(race,db_path)` and `cbflow run db-manage --check`.

### `project(lib_config_tag) not set — no library config loaded`

Set the tag in the PD overlay (`PD/config/project/<proj>/v1.0.0/<proj>_pd_config.tcl`) or per run in the user
config: `set project(lib_config_tag) "OSS2"`.

### `lib_tag_root … points inside the framework tree`

Library tags must live outside `CBFLOW_ROOT`. Point `project(lib_tag_root)` (or `CBFLOW_LIB_TAG_ROOT`) at a
directory outside the install. A rejected root is not skipped in favour of a lower-priority one.

---

## 3. Running

### Stage "completed" but the tool never ran

Three gates protect against silent success: the `workspace create` pre-flight, the synchronous xterm launch
(`$DISPLAY` + wrapper checked, non-zero exit fails the job), and `handler_validate` in production mode
(`<flow>(mandatory_outputs,<stage>)` present and non-empty, `outputs/` not empty). If a run still looks empty:

```bash
grep -c "\[TEST MODE\]" work/*/*/run/*.log | grep -v ":0$"     # test-mode markers?
find work -name outputs -type d -exec sh -c 'echo "$1: $(ls $1 | wc -l)"' _ {} \;
```

### `Run owned by '<user>' — only the owner can modify this run`

Only the creator can run, retrace, bypass, force, forcevalidate, add / delete / rewire nodes. Status, logs and the
GUI are open to everyone. Copy the user config and create your own run.

### Re-running

```bash
cbflow run retrace --from cts1 --run      # clear cts1 + downstream and rerun
cbflow run force --stages place1          # rerun only place1 (deps must be DONE)
cbflow run bypass --stages cts1,cts_opt1  # mark done without running (BYPASSED marker)
```

A retrace or force removes `work/<FLOW>/<node>/BYPASSED`.

### `set-dep` refused

Cycles are refused. `--reset` only removes a base-node override (stored as `dep_overrides` in
`setup/runtime_flow_config.tcl`); custom nodes keep their edited deps.

### Too many parallel jobs / out of memory

`set flow(max_parallel_jobs) 4` in the user config (0 = unlimited). With LSF, pick a tier per node:
`cbflow run add-node … --resource-tier XL`, or `cbflow run all --lsf --queue L`.

---

## 4. Inputs and handshakes

### Input not found from a release tag

Check the release exists: `<project(release,path)>/<phase>/<block>/<FLOW>/<tag>/RELEASE_COMPLETE`. The phase is the
run's phase (`project(phase)` in the user config, else `project(current_phase)`). The handshake map
(`PD/config/flow/v1.0.0/release_config.tcl`, section 6) names the category / file each input comes from.
Priority: explicit path > per-input tag (`<flow>(input,<x>_release_tag)`) > generic `<flow>(input,release_tag)`.

### Signoff run refuses its inputs

```
ERROR: sta(input,from_run) is not allowed for a signoff run — inputs come only from the PRO_EXIT release (sta(input,release_tag))
ERROR: signoff inputs must come only from the PRO_EXIT release (sta(input,release_tag)) — remove: ...
```

Signoff flows (`<flow>(release,exit_from)` set: STA opensta, PV magic, LEC yosys) read only the exit's release.
Remove explicit paths, `from_run` and other tags; only `<flow>(release,exit_exempt_inputs)` (LEC
`{netlist_golden}`) may come from elsewhere.

---

## 5. Releases and publishing

### `exit order — <block> <phase> cannot release <EXIT> before …`

Earlier exits of the same plan must be released first (`project(phase_exits)` for PD,
`project(phase_exits,<DISC>)` for other disciplines). There is no bypass flag: release the missing exits, or check
that the run's phase is right. Test mode and signoff flows skip the gate.

### `no exit maps to stage 'cts'`

`cts` and `route` have no exit. Release from place (PLACE_EXIT), cts_opt (CTS_EXIT), pro (PRO_EXIT) or signoff
(BTO / MTO). See the [Exit Release Guide](exit-release-guide.md#3-releasing-an-intermediate-stage-eg-place--place_exit).

### `Not published: …`

| Message | Fix |
|---|---|
| `no SmartGrid daemon is running for project <p>` | Publishing is opt-in: re-run with `--publish` (starts the daemon) or `cbflow smartgrid start --project <p>` |
| `phase <P> has no <EXIT> exit` | The phase does not deliver that exit (`project(phase_exits)`) |
| `<EXIT> cannot release before <earlier> for <block> / <P>` | Publish the earlier exits first |

`--override` replaces an existing entry; it does not bypass the order.

### Clone refused

`--clone-from BTO --tag MTO` needs a `RELEASE_COMPLETE` (STATUS=PASS) BTO release, both exits mapping to the same
source stage, and the exit order holding for the target.

---

## 6. Libraries

### `child block '<b>' is not in library tag <TAG>`

Add the child's release to the tag the parent uses:

```bash
cbflow flow library-manager add --tech skywater_130nm --project opensky --tag OSS2 \
    --category block --path <release,path>/P1/gcd/PNR/PRO_EXIT
```

### `PV release dir not found` on `add --category block`

GDS / CDL come from the sibling PV release (`<phase>/<block>/PV/<exit>`), which must be complete. Run PV signoff of
that exit, or add with `--pv-pending` and re-add without it once PV releases.

### `check --lib_tag` reports MISSING

```bash
cbflow flow library-manager check --tech skywater_130nm --lib_tag OSS2
```

`spef MISSING` on a block = the block was added from a release before `pro`. `lib n/m` = corners of the project's
MMMC library sets without a timing model. Required views come from `tech(required_views,<category>)`. To check a
design against the tag: add `--project <p> --design <b> --netlist_tag <T>` (or `--rtl_tag`).

### `lib_config.tcl is older than tech_config.tcl`

A warning from `status`: regenerate the tag (`generate --tech <t> --tag <TAG>`) if tech-level library keys changed.

---

## 7. Dashboards

### Run dashboard does not open / port in use

The daemon port is `flow(dashboard,port_base,<DISC>) + uid % 300` (PD 9000, DFT 9300, DV 9600, RTL 9900).

```bash
cbflow run dashboard status --all
cbflow run dashboard restart --discipline PD
cbflow run dashboard start --discipline PD --port 9999     # if something else holds the port
cbflow run dashboard logs --discipline PD
```

Over SSH, tunnel the port (`ssh -L 9201:localhost:9201 user@host`) or start with `--public`.

### SmartGrid shows a discipline as offline

The discipline card's **Run dashboard ↗** link starts that discipline's daemon for the project. If it cannot start,
run `cbflow run dashboard start --discipline <DISC> --project <p>` in a shell and check its log.

---

## 8. Framework versioning

```bash
cbflow flow version status                                     # version health
cbflow flow version list --dir config/flow
cbflow flow version copy --dir config/flow --from v1.0.0 --to v1.0.1
cbflow flow version set-current --dir config/flow --version v1.0.0   # roll back
cbflow flow dev start --component config/flow --from v1.0.0    # writable -dev copy of a locked version
cbflow flow dev diff --component config/flow
cbflow flow dev promote --component config/flow
cbflow flow release create --type patch --desc "..."           # add --force when no component changed
cbflow flow release validate --version v2.0.1
```

Released versions are locked (chmod 444 + `.locked`); edit through `dev start`, never in place.
`cbflow run release-lock --unlock` restores 777 on a whole install (development only).

---

## Getting more help

```bash
cbflow <command> --help                 # every subcommand has examples
cbflow run help                         # full run documentation
cbflow test --cli-smoke                 # every cbflow leaf command with safe args
bin/cbflow-healthcheck
```

See also the [Exit Release Guide](exit-release-guide.md), [Library Manager](library-manager-user-guide.md),
[Dashboard Daemon](dashboard-daemon-guide.md) and [SmartGrid](project-dashboard-guide.md) guides.
