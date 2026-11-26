# Python Scripts Reference

Where each `cbflow` command is implemented in CBflow v2.0.0. For every
subcommand and flag see the [Command Reference](command-reference.md) (or run
the command with `-h`).

After the cbflow_global refactor the Python command modules live in two places:

- `global/utils/commands/` — cross-discipline commands and libraries
- `PD/utils/commands/` — PD-owned commands (checklist, library / MMMC managers, dashboards, reports, LSF)

Shared packages (`core.paths`, `core.registry`, `core.release_exits`, `core.db`, …)
live in `global/utils/core/`. The launchers (`global/bin/cbflow`,
`global/bin/cbflow-flow`, `PD/bin/cbflow-pd`) route each command to its module.

Flow execution is done by the RACE engine (`race_engine.py`): the DAG is built
from the node configs at run time and all status is kept in the run's SQLite DB.
There is no Makefile generation step.

---

## Command modules

| Module | Command | Subcommands |
|---|---|---|
| `global/utils/commands/workspace_cmd.py` | `cbflow workspace` | create, template, list-runs (list), run-status, status, update, clean, validate |
| `global/utils/commands/run_cmd.py` | `cbflow run` | all, stage, status, retrace, bypass, force, forcevalidate, clean, list-nodes, show-graph, add-node, set-dep, delete-node, create-branch, list-branches, delete-branch, update, gen-makefile, release-info, release, release-lock, release-check, targets, logs, validate, report, lsf-status, debug, interactive, email, autoppt, checklist, gui, db-manage, help |
| `PD/utils/commands/dashboard_daemon_cmd.py` | `cbflow run dashboard` (also `cbflow flow dashboard`, legacy `cbflow dashboard`) | start, stop, restart, status, open, logs, list, prune, register, deregister |
| `PD/utils/commands/project_dashboard_cmd.py` | `cbflow smartgrid` (legacy `cbflow project-dashboard`) | start, stop, restart, status, open, logs, list, unpublish |
| `global/utils/commands/flow_cmd.py` | `cbflow flow types\|info\|stages\|nodes\|check` | — |
| `global/utils/commands/project_cmd.py` | `cbflow flow project` | list, info, create, delete, manage |
| `global/utils/commands/release_cmd.py` | `cbflow flow release` (CBflow install releases) | generate-config, create, list, info, set-current, validate, components, diff |
| `global/utils/commands/version_cmd.py` | `cbflow flow version` | list, create, set-current, get-current, copy, diff, status |
| `global/utils/commands/config_cmd.py` | `cbflow flow config` | manage-flow, manage-node, manage-tech, validate, status |
| `global/utils/commands/test_cmd.py` (+ `test_suite/`) | `cbflow test` | static / e2e / dispatch-smoke / cli-smoke / integration / hardcode suites |
| `PD/utils/commands/dev_cmd.py` | `cbflow flow dev` | start, status, diff, promote, sandbox-create, sandbox-push |
| `PD/utils/commands/plugin_cmd.py` | `cbflow flow plugin` | list, scaffold, register, unregister |
| `PD/utils/commands/qor_report_cmd.py` | `cbflow flow qor-report` | generate, compare, summary |
| `PD/utils/commands/trending_cmd.py` | `cbflow flow trending` | report, baseline, check, record, stats |
| `PD/utils/commands/metrics_cmd.py` | `cbflow flow metrics` | collect, report, export |
| `PD/utils/commands/lsf_manager_cmd.py` | `cbflow flow lsf-manager` | show, map, validate |
| `PD/utils/commands/checklist_cmd.py` | `cbflow flow checklist` (PD launcher) | generate, status, sign-off, list, list-checks, add-check, remove-check, waiver |
| `PD/utils/commands/library_manager_cmd.py` | `cbflow flow library-manager` (PD launcher) | scan, check, list, verify, generate-mmmc, generate, add, coverage, status |
| `PD/utils/commands/mmmc_manager_cmd.py` | `cbflow flow mmmc-manager` (PD launcher) | show, validate, add-mode, remove-mode, add-pvt, remove-pvt, add-rc, set-node, list-views, list-scenarios, generate-view-def, generate |
| `PD/utils/commands/email_cmd.py` | `cbflow run email` (alias `cbflow flow email`) | templates run-creation, run-status, run-summary, checklist, reminder, release-update |
| `PD/utils/commands/autoppt_cmd.py` | `cbflow run autoppt` (alias `cbflow flow autoppt`) | `--format html\|pptx`, `--output` |
| `PD/utils/commands/migrate_cmd.py` | `cbflow migrate` | `--old`, `--new`, `--dry-run` |

## Libraries and helpers (no CLI of their own)

| Module | Role |
|---|---|
| `global/utils/commands/race_engine.py` | RACE DAG executor + SQLite DB (jobs, run_info, run_config, job_order, dag_structure, stage_metrics, …); active engine sync; dynamic subnodes (STA per-scenario) |
| `global/utils/commands/start_run.py` | Run creation for `workspace create` (run dir, env files, launch-binary preflight, RACE DB init) |
| `global/utils/commands/config_resolver.tcl` | Runs the Tcl config cascade and captures resolved variables |
| `global/utils/commands/tcl_config_parser.py`, `_tcl_utils.py`, `cbflow_config.py`, `config_validator.py` | Config reading / validation from Python |
| `global/utils/commands/logging_config.py` | Logging setup |
| `global/utils/commands/dashboard_cmd.py` | Legacy single-run dashboard app |
| `PD/utils/commands/node_manager.py` | add-node / set-dep / delete-node / branch operations |
| `PD/utils/commands/graph_renderer.py` | `show-graph` rendering |
| `PD/utils/commands/status_provider.py` | Status from the RACE DB |
| `PD/utils/commands/log_viewer.py` | `cbflow run logs` |
| `PD/utils/commands/validation_cmd.py` | `cbflow run validate` / `--validate` checks |
| `PD/utils/commands/lsf_cmd.py` | `cbflow run lsf-status` |
| `PD/utils/commands/dispatcher.py` | Hands execution to RACE (the only backend) |
| `PD/utils/commands/makefile_generator.py` | Legacy Makefile generator (not used by RACE) |
| `PD/utils/commands/restricted_vars.py` | Restricted-variable guard used by `workspace create` |

## Exit codes

Commands return 0 on success and non-zero on failure (1 for usage, validation
and configuration errors). `cbflow run release --publish` returns non-zero when
the publish fails; a release without `--publish` never fails on SmartGrid.

---

**See also:** [Command Reference](command-reference.md) ·
[RACE Engine Command Reference](makefile-reference.md) ·
[Configuration Reference](configuration-reference.md) ·
[LSF Reference](lsf-reference.md) · [MMMC Reference](mmmc-reference.md)
