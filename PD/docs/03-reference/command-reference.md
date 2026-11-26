# CBflow Command Reference

Every `cbflow` command and flag in CBflow v2.0.0, checked against the `--help`
output of the code. Run any command with `-h` for the authoritative list.

Launchers: `bin/cbflow` (→ `global/bin/cbflow`) is the universal entry point.
`PD/bin/cbflow-pd`, `DFT/bin/cbflow-dft`, `DV/bin/cbflow-dv`, `RTL/bin/cbflow-rtl`
own discipline subcommands (today only PD: `flow library-manager`,
`flow mmmc-manager`, `flow checklist`) and fall through to `cbflow` for
everything else. `cbflow flow <sub>` auto-dispatches discipline-owned
subcommands via `global/config/cli/discipline_commands.tcl`.

Names used in examples: projects `opensky` (phases P0-P3, sky130 open-source
flow) and `bumblebee` (phases LC1-LC5); stages are node names (`place1`,
`cts1`, `release_data1` — see `cbflow run list-nodes`); run directories are
`<phase>_run_<FLOW>_<block>_<run>`.

---

## Top level

| Command | Purpose |
|---|---|
| `cbflow workspace …` | Create and inspect runs (from `workarea/<design>/`) |
| `cbflow run …` | Execute and control a run (from a run directory) |
| `cbflow run dashboard …` | Per-user run dashboard daemon |
| `cbflow flow …` | Flow info, projects, checklists, library / MMMC managers (any directory) |
| `cbflow smartgrid …` | Project-level dashboard daemon |
| `cbflow test …` | Test suite |
| `cbflow migrate …` | Carry user values from an old config file into a new one |
| `cbflow bundle …` | Customer delivery tarball |
| `cbflow smartgenie …` | AI agent (`cbflow smartgenie --help`) |
| `cbflow --version` / `--help` / `--completions bash\|zsh` | Version chain, help, shell completion |

Legacy aliases: `cbflow dashboard …` → `cbflow run dashboard …` and
`cbflow project-dashboard …` → `cbflow smartgrid …` (both print a deprecation note);
`cbflow test-suite` = `cbflow test`.

---

## cbflow workspace

Run from `workarea/<design_name>/` (the workarea path is enforced from `project(workarea_path)`).

| Subcommand | Flags | Purpose |
|---|---|---|
| `template` | `--flow/-t FLOW` (req), `--project/-p P`, `--output/-o FILE` | Generate a `user_config.tcl` template |
| `create` | `--config/-c FILE`, `--force/-f`, `--accept-restricted/--yes` | Create a run. `--force` deletes an existing run dir; a stale RACE DB is archived as `<db>.stale-<ts>` |
| `status` | `--run/-r NAME\|N`, `--summary` | Workspace overview, or one run |
| `run-status` | `--run/-r` (req), `--details/-d`, `--summary` | Status of one run |
| `list-runs` / `list` | — | List runs |
| `validate` | — | Validate workspace configuration |
| `update` | `--release/-r` (req) | Update the workspace to a release |
| `clean` | `--confirm` | Delete all run directories |

```bash
cbflow workspace template --flow PNR --project opensky > user_config.tcl
cbflow workspace create --config user_config.tcl
cbflow workspace status --run 1 --summary
```

`workspace create` fails (and removes the partial run dir) when
`flow(use_lsf)` is true and `bsub` is missing, or `flow(use_xterm)` is true and
`xterm` is missing.

---

## cbflow run

Run from inside a run directory (except `release` without `--from-run`, which
runs from the workarea, and `release-check` / `release-lock`).

### Execution

| Subcommand | Flags | Purpose |
|---|---|---|
| `all` | `--validate`, `--lsf`, `--queue Q`, `--collect-metrics` | Run the whole DAG |
| `stage` | `--name/-n STAGE` (req), `--subnode/-s SUB`, `--validate`, `--lsf`, `--queue Q` | Run one stage (or one subnode) |
| `interactive` | `--node/-n NODE` (req), `--notiming` | Interactive tool session on a node's saved design (`INTERACTIVE/<node>_<ts>`); STA per-scenario subnode names accepted |

`flow(max_parallel_jobs)` caps local parallel jobs (0 = unlimited).

### Status and inspection

| Subcommand | Flags | Purpose |
|---|---|---|
| `status` | `--details/-d`, `--output/-o FILE` | Stage completion (RACE DB) |
| `report` | `--node/-n`, `--dump-setup` (default on), `--no-dump` | Per-node report |
| `list-nodes` | — | Base + custom nodes with status |
| `show-graph` | `--detail/-d` | ASCII DAG |
| `targets` | — | Stages as `cbflow run stage` commands |
| `gen-makefile` | — | Verify the RACE DAG (legacy name; no Makefile) |
| `logs` | `--list/-l`, `--tail/-t N`, `--search/-s RE`, `--level DEBUG\|INFO\|WARNING\|ERROR`, `--file/-f` | Log viewer |
| `validate` | `--type all\|config\|inputs\|exit`, `--stage S` | Validation checks |
| `debug` | `--dump-resolved-cfg`, `--key 'arr(key)'` | Resolved config keys + source files |
| `lsf-status` | `--flow F` | LSF jobs |
| `release-info` | — | Release / component versions of the run |

### Flow control (also accepted while `run all` is running — active engine sync)

| Subcommand | Flags | Purpose |
|---|---|---|
| `retrace` | `--from STAGE`, `--run` | Invalidate a stage and every later stage (all when no `--from`) |
| `bypass` | `--stages/-s A,B` (req) | Mark stages or `<stage>:<scenario>` subnodes done without running (`work/<FLOW>/<node>/BYPASSED` once a whole stage is bypassed) |
| `force` | `--stages/-s A,B` (req) | Re-run these stages or `<stage>:<scenario>` subnodes now; completed dependents are invalidated (sibling scenarios untouched) |
| `forcevalidate` | `--node/-n X` \| `--from X [--to Y]` \| `--to Y` \| `--stages A,B` | Mark stages (or `<stage>:<scenario>` subnodes) done (ran outside CBflow) |
| `clean` | `--confirm` | Delete `work/`, `logs/`; deregister from the dashboard |

### DAG editing

| Subcommand | Flags | Purpose |
|---|---|---|
| `add-node` | `--type/-t T` (req), `--dep/-d NODE`, `--node/-n NAME`, `--resource-tier/-r XS\|S\|M\|L\|XL\|ultra` | Add a custom node (inherits `runtime,timeout`) |
| `set-dep` | `--node/-n N` (req), `--deps/-d A,B` \| `--reset` | Rewire a node's dependencies |
| `delete-node` | `--node/-n` (req) | Remove a custom node |
| `create-branch` | `--branch/-b NAME` (req), `--from STAGE` (req) | Branch the remaining flow from a stage |
| `list-branches` | — | List branches |
| `delete-branch` | `--branch/-b NAME` \| `--from NODE` | Delete a branch |

```bash
cbflow run add-node --node place2 --type place --dep place1
cbflow run set-dep --node export_data1 --deps place1
cbflow run create-branch --branch timing_fix --from cts1
```

### Releases

Layout: `<project(release,path)>/<phase>/<block>/<FLOW>/<tag>`; tag =
`project(release,tag)` else the exit name. Exits per phase come from
`project(phase_exits)` (per discipline: `project(phase_exits,<DISC>)`); order from
`MILESTONE_ORDER` (`PD/config/flow/v1.0.0/release_config.tcl`).

`release` flags:

| Flag | Meaning |
|---|---|
| `--tag/-t EXIT` | Exit milestone (default `project(release,active_tag)`) |
| `--name NAME` | Release tag name (default: the exit name) |
| `--dry-run` | Validate only |
| `--from-run RUN` | Run that released itself (open-source `release_data` stage); nothing is repackaged |
| `--node NODE` | With `--from-run`: the release node (e.g. `release_data2`); default the flow's `release_data` node |
| `--clone-from EXIT` | With `--from-run` + `--tag`: copy that exit's release to `--tag` (same source stage; exit order checked; records `CLONED_FROM`) |
| `--publish` | Publish to SmartGrid (opt-in; starts the daemon; a publish error fails the command) |
| `--no-publish` | Do not publish (the default) |
| `--override` | On publish, replace the existing (project, block, phase, milestone) entry |

Gates (no bypass flag): at release, earlier exits of the phase must be
`RELEASE_COMPLETE` (skipped in test mode and for signoff flows); at publish,
earlier exits must already be on SmartGrid. Signoff flows (STA / PV / LEC) read
only their exit's release (`<flow>(release,exit_from)`).

```bash
# from the workarea
cbflow run release --tag PLACE_EXIT --dry-run
cbflow run release --tag BTO --publish
# open-source: the run released itself
cbflow run release --from-run P1_run_PNR_gcd_b1 --node release_data1 --publish
cbflow run release --from-run P1_run_PNR_gcd_b1 --clone-from BTO --tag MTO --publish
```

Releasing an intermediate stage (e.g. place1 → PLACE_EXIT; cts_opt → CTS_EXIT,
pro → PRO_EXIT, signoff → BTO):

```bash
cbflow run bypass --stages cts1,cts_opt1,route1,pro1,signoff1 && cbflow run stage --name release_data1
# or
cbflow run set-dep --node export_data1 --deps place1 && cbflow run stage --name release_data1
# or
cbflow run add-node --node export_data2 --type export_data --dep place1
cbflow run add-node --node release_data2 --type release_data --dep export_data2
cbflow run stage --name release_data2
```

Releasing the same data as another exit (MTO = BTO): set the release node's tag
(`setup/override_config.release_data1.tcl: set project(release,tag) "MTO"`,
or the run GUI release form), then
`cbflow run retrace --from release_data1 && cbflow run stage --name release_data1`;
or use `--clone-from` as above.

| Subcommand | Flags | Purpose |
|---|---|---|
| `release-check` | `--tag/-t` (req), `--project/-p` (req), `--phase` (default `$CBFLOW_PROJECT_PHASE`), `--block/-b` | Every block of `project(block_list)` released for an exit |
| `release-lock` | `--unlock` | Production permissions (or 777 with `--unlock`) |
| `update` | `--release/-r V`, `--no-backup` | Move the run to another release |

```bash
cbflow run release-check --tag BTO --project opensky --phase P2
cbflow run release-check --tag PLACE_EXIT --project bumblebee --phase LC2 --block cpu_core
```

### Checklist, reports, notifications

| Subcommand | Flags | Purpose |
|---|---|---|
| `checklist` | `--milestone/-m`, `--phase/-p`, `--format text\|json\|html`, `--project`, `--sign-off`, `--approver`, `--list` | Exit checklist on this run |
| `email` | `--to` (req), `--template run-creation\|run-status\|run-summary\|checklist\|reminder\|release-update` (req), `--subject/-s`, `--message/-m`, `--due-date/--due`, `--milestone`, `--attach …`, `--preview`, `--html` | Email notification |
| `autoppt` | `--format/-f html\|pptx`, `--output/-o` | Run summary deck (when enabled) |
| `db-manage` | `--list/-l`, `--delete/-d RUN`, `--cleanup`, `--check` | RACE DB sessions (`flow(race,db_max_sessions)`) |
| `gui` | `--no-browser`, `--public`, `--bind-addr A`, `--foreground`, `--port/-p` (foreground only), `--daemon` | Register the run with the dashboard daemon and open it |
| `help` | — | Long help with examples |

```bash
cbflow run checklist --milestone PRO_EXIT --phase P2
cbflow run checklist --milestone FP_EXIT --sign-off --approver chip_lead
```

---

## cbflow run dashboard

One daemon per user per discipline. Port =
`flow(dashboard,port_base,<DISC>) + uid % flow(dashboard,port_width)`
(PD 9000, DFT 9300, DV 9600, RTL 9900; width 300). With `--project <p>`:
`flow(dashboard,project_port_base,<DISC>)` (20000 / 21000 / 22000 / 23000)
+ hash % 1000. Every verb takes `--discipline PD|DFT|DV|RTL` and `--project P`.

| Verb | Flags |
|---|---|
| `start` / `restart` | `--port N`, `--foreground`, `--public`, `--bind-addr A` |
| `stop` | — |
| `status` / `list` | `--all` |
| `open` | `[run_dir \| run_id]` |
| `logs` | `--follow/-f` |
| `prune` | `-y/--yes`, `--include-archived` |
| `register` | `run_dir` (discipline auto-detected) |
| `deregister` | `run_dir \| run_id` |

`cbflow flow dashboard …` is the same command. Bind priority: `--bind-addr` >
`--public` > `CBFLOW_DASHBOARD_BIND_ADDR` > `127.0.0.1`. See
[Production Dashboard Setup](dashboard-production-setup.md).

---

## cbflow smartgrid

Project-level dashboard. Port = `flow(smartgrid,port_base)` (25000) +
md5(uid:project) % `flow(smartgrid,port_span)` (2500). Every verb needs `--project`.

| Verb | Flags |
|---|---|
| `start` / `restart` | `--port N`, `--foreground`, `--public`, `--bind-addr A` |
| `stop`, `status`, `open`, `list` | — |
| `logs` | `--follow/-f` |
| `unpublish` | `--block`, `--phase`, `--milestone` (all required) |

```bash
cbflow smartgrid start --project opensky
cbflow smartgrid unpublish --project opensky --block gcd --phase P1 --milestone PRO_EXIT
```

Publishing happens through `cbflow run release … --publish` (or the run GUI
release form). Signoff runs (STA / PV / LEC) attach to the exit they verified.

---

## cbflow flow

| Subcommand | Notes |
|---|---|
| `types [--domain PD\|DFT\|DV\|RTL]` | Flow types per discipline (33: PD 12, DFT 7, DV 9, RTL 5) |
| `info --flow F` / `stages --flow F` / `nodes --flow F` | Flow tool, stages, nodes |
| `check` | Installation check |
| `project list\|info --name P\|create\|delete --name P --confirm\|manage` | Projects |
| `release generate-config\|create\|list\|info\|set-current\|validate\|components\|diff` | CBflow install releases (not exit releases) |
| `version list\|create\|set-current\|get-current\|copy\|diff\|status` | Directory versioning |
| `dev start --component C --from V\|status\|diff --component C\|promote --component C\|sandbox-create [--base B] [--dir D]\|sandbox-push [--dir D]` | Dev versions |
| `config manage-flow\|manage-node\|manage-tech\|validate\|status` | Config management |
| `plugin list\|scaffold\|register\|unregister` | Flow plugins |
| `qor-report generate\|compare\|summary` | QoR reports |
| `trending report\|baseline\|check\|record\|stats` | QoR trending |
| `metrics collect\|report\|export` | Metrics DB |
| `lsf-manager show\|map\|validate` | LSF queues / stage mapping |
| `email …` / `autoppt …` | Aliases of `cbflow run email` / `autoppt` |
| `dashboard …` | Alias of `cbflow run dashboard` |
| `checklist …` | PD launcher — see below |
| `library-manager …` | PD launcher — `scan, check, list, verify, generate-mmmc, generate, add, coverage, status` (`-h` per command) |
| `mmmc-manager …` | PD launcher — `show, validate, add-mode, remove-mode, add-pvt, remove-pvt, add-rc, set-node, list-views, list-scenarios, generate-view-def, generate` |

### cbflow flow checklist

Milestones are declared in `global/config/exit/v1.0.0/<MILESTONE>_config.tcl`:
PD FP_EXIT PLACE_EXIT CTS_EXIT PRO_EXIT BTO MTO (+ STA_SIGNOFF); DFT
CORE_DFT_EXIT TOP_DFT_EXIT EDT_OCC_EXIT SCAN_INSERT_EXIT ATPG_PREPD_EXIT
ATPG_POSTPD_EXIT; DV SPEC_RAMP_EXIT PLANNING_EXIT TB_SETUP_EXIT M1_EXIT-M4_EXIT
ECO_EXEC_EXIT DV_SIGNOFF_EXIT; RTL SPEC_EXIT LINT_SIGNOFF CDC_SIGNOFF UPF_SIGNOFF.

| Verb | Flags |
|---|---|
| `list` | `--discipline` |
| `list-checks` | `--milestone`, `--phase`, `--run-dir`, `--output/-o`, `--summary/-s`, `--discipline` |
| `generate` | `--milestone`, `--project`, `--phase`, `--format text\|json\|html`, `--discipline` |
| `status` | `--milestone` (req), `--run-dir` (req), `--project`, `--phase`, `--discipline` |
| `sign-off` | `--milestone`, `--run-dir`, `--approver` (all req), `--phase`, `--discipline` |
| `add-check` | `--milestone`, `--name`, `--type mandatory\|optional\|file` (req); `--description`, `--script` + `--criteria` \| `--grep-file` + `--grep-pattern` [`--grep-pass-if found\|not_found`] \| `--file-path` |
| `remove-check` | `--milestone`, `--name` (req) |
| `waiver` | `--action list\|add\|revoke` (req), `--milestone`, `--check`, `--reason`, `--approver`, `--expiry YYYY-MM-DD`, `--project`, `--waiver-id` |

`--discipline` currently accepts `PD`, `DFT`, `DV`. Waivers: max 90 days, none on
BTO / MTO (`waiver_config.tcl`).

```bash
cbflow flow checklist list --discipline DFT
cbflow flow checklist list-checks --milestone BTO --phase P3 --run-dir . --summary
cbflow flow checklist waiver --action add --milestone PRO_EXIT --check <check> --reason "…" --approver chip_lead
```

---

## cbflow test

| Flag | Meaning |
|---|---|
| `--static` \| `--e2e` \| `--dispatch-smoke` \| `--cli-smoke` \| `--integration` \| `--hardcode` | Pick one suite (default: static + e2e) |
| `--flow F` / `--flows A,B` | Flows (default: the 12 PD flows) |
| `--category N\|hardcode` | One static category (`--list` shows them) |
| `--projects A,B\|ALL` | e2e projects (default bumblebee,denali) |
| `--vendor V`, `--timeout S` (300) | Fixture vendor, per-flow timeout |
| `--keep` \| `--keep-on-fail` (default) \| `--clean-on-fail` | Sandboxes |
| `--report FILE`, `--junit FILE`, `--ci` | Reports |
| `--verbose/-v` \| `--quiet/-q`, `--list`, `--cleanup`, `--destructive` | Misc |

---

## cbflow migrate / bundle

```bash
cbflow migrate --old <old.tcl> --new <new.tcl> [--dry-run]   # writes <new> in place, backup <new>.bak
cbflow bundle [--output DIR] [--version TAG]                 # tar.gz, 777; then cbflow run release-lock
```

---

## cbflow-oss (open-source tool container)

`global/bin/cbflow-oss` (also `bin/cbflow-oss`) runs the open-source tools in docker.

```bash
cbflow-oss <tool> <cmd_file> <log_file>     # tool: yosys openroad sta magic netgen klayout tclsh
                                            #       fault iverilog verilator rtlcheck vplan python3
cbflow-oss exec -- <argv...>                # arbitrary command line
cbflow-oss check                            # tools + versions in the image
cbflow-oss gui openroad <stage.odb>         # OpenROAD GUI
cbflow-oss gui klayout <file.gds|.def>      # KLayout GUI
cbflow-oss interactive <openroad|sta|yosys|oss_tclsh> [script]   # CBFLOW_OSS_GUI=1: OpenROAD GUI
cbflow-oss --help
```

Environment: `CBFLOW_OSS_IMAGE`, `CBFLOW_OSS_PDK_ROOT` (`$HOME/eda/pdks`),
`CBFLOW_OSS_MOUNTS`, `CBFLOW_OSS_TOOLS`, `CBFLOW_OSS_MAGICRC`, `CBFLOW_OSS_ENGINE` (`docker`).
`cbflow-oss-checks <run_dir> <node>…` writes the checklist library reports of
finished open-source PNR nodes.

---

**See also:** [Python Scripts Reference](python-scripts-reference.md) ·
[RACE Engine Command Reference](makefile-reference.md) ·
[Configuration Reference](configuration-reference.md) ·
`PD/docs/02-user-guide/exit-release-guide.md` ·
`PD/docs/02-user-guide/opensource-flow-guide.md`
