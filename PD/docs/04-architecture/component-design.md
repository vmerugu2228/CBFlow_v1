# Component Design

Module map of CBflow v2.0.0 — what each component owns and who calls it.
Paths are relative to `$CBFLOW_ROOT`.

```
                 bin/cbflow → global/bin/cbflow  (+ PD/DFT/DV/RTL bin/cbflow-<disc>)
                                   │
       ┌───────────────┬───────────┼──────────────┬────────────────┬──────────────┐
       ▼               ▼           ▼              ▼                ▼              ▼
 workspace_cmd    run_cmd ──► race_engine    flow_cmd /       dashboard /     test_cmd
 start_run        (Python)    (DAG + DB)     cbflow-flow      SmartGrid       test_suite/
       │                          │          (+ PD commands)  (Python HTTP)
       │                          ▼
       │            tclsh <DISC>/cmds/<FLOW>/<vendor>/<tool>/<ver>/<type>_subnode_handler.tcl
       │                          │  handler_common.tcl / launch_utils.tcl
       │                          ▼
       │            generate_setup.tcl → config.tcl + setup.tcl      (config cascade)
       │                          ▼
       │            tool shell (fc_shell, innovus, tessent, … | cbflow-oss <tool>)
       │                          ▼
       │            command file: utils.tcl bootstrap → flow_proc … → flow_exec_all
       │                          ▼
       └────────────────► release_utils.tcl → <release,path>/<phase>/<block>/<FLOW>/<tag>
```

---

## 1. Launchers (`global/bin/`, `<DISC>/bin/`)

| File | Role |
|---|---|
| `global/bin/cbflow` | universal entry: workspace, run, flow, bundle, migrate, test, dashboard, smartgrid, smartgenie, `--version`, `--completions` |
| `global/bin/cbflow-flow` | `cbflow flow …` router; unknown subcommands dispatch to the owning discipline launcher via `global/config/cli/discipline_commands.tcl` |
| `global/bin/cbflow-run`, `cbflow-workspace`, `cbflow-project`, `cbflow-release`, `cbflow-config`, `cbflow-version`, `cbflow-bundle`, `cbflow-verify`, `cbflow-healthcheck` | direct entry points (also reachable through `cbflow`) |
| `global/bin/_cbflow_paths.sh` | resolves `CBFLOW_ROOT` and derives every other `CBFLOW_*` / `*_VERSION` variable |
| `global/bin/cbflow-oss`, `cbflow-oss-checks` | open-source tool container launcher; report-only checklist runner |
| `global/bin/cbflow-test-suite` | back-compat shim → `cbflow test --static` |
| `PD/bin/cbflow-pd` | `flow library-manager | mmmc-manager | checklist` |
| `DFT/bin/cbflow-dft`, `DV/bin/cbflow-dv`, `RTL/bin/cbflow-rtl` | extension points (no owned subcommands yet) |

## 2. Python commands (`global/utils/commands/`)

| Module | Role |
|---|---|
| `workspace_cmd.py`, `start_run.py` | `cbflow workspace …`: run dir, `.run.cbflow.env/.tcl`, launch preflight, DB init, run-dir naming |
| `run_cmd.py` | `cbflow run …`: all / stage / status / retrace / bypass / force / forcevalidate / add-node / set-dep / create-branch / release / gui / db-manage / … |
| `race_engine.py` | `DagBuilder`, `StatusDB`, `RaceEngine` (execution, sync, ownership, timeouts) |
| `config_resolver.tcl`, `tcl_config_parser.py`, `cbflow_config.py`, `config_validator.py` | resolve the cascade through tclsh and expose resolved values to Python |
| `flow_cmd.py`, `project_cmd.py`, `release_cmd.py`, `version_cmd.py`, `config_cmd.py`, `dashboard_cmd.py` | `cbflow flow …` families |
| `test_cmd.py`, `test_suite/` | `cbflow test` (static, e2e, dispatch / CLI smoke, integration, hardcode) |

`global/utils/core/`: `paths.py` (root resolution), `env.py`, `registry.py`
(flow registry + discipline lookups), `db.py` (`find_race_db_from_run_dir`,
checklist schema), `release_exits.py`, `config_reader.py`, `interactive.py`,
`errors.py`.

PD-owned Python (`PD/utils/commands/`): `library_manager_cmd.py`,
`mmmc_manager_cmd.py`, `checklist_cmd.py`, `autoppt_cmd.py`, `email_cmd.py`,
`metrics_cmd.py`, `qor_report_cmd.py`, `lsf_cmd.py`, `dev_cmd.py`,
`plugin_cmd.py`, `migrate_cmd.py`, `trending_cmd.py`, …

## 3. Tcl runtime (`global/utils/utilities/v1.0.0/`)

| File | Role |
|---|---|
| `utils.tcl` | flow_proc engine (`flow_proc`, `flow_exec_all`, `flow_proc_prepend/append/replace`), `setup_dirs`, node helpers (`cbflow_node_name`, `cbflow_node_deps`, `cbflow_node_type`, `cbflow_upstream_node`, `cbflow_chain_node`, `cbflow_source_node`, `cbflow_dep_node`), `cbflow_release_dir`, `cbflow_require`, test-mode interception |
| `handler_common.tcl` | `handler_parse_args`, `handler_load_configs`, `handler_dispatch` (setup / run / validate / finish), `handler_validate`, `handler_publish_release`, `handler_dispatch_inputs`, `handler_resolve_inputs` |
| `launch_utils.tcl` | `determine_launch_mode`, `generate_launch_wrapper`, `submit_job` (LSF / xterm / local), `handler_run` |
| `resolve_inputs.tcl` | `::CBFlow::InputResolve` — handshake resolution (tag / per-input tag / from_run / explicit path), `generate_output_manifest` |
| `release_utils.tcl` | `::CBFlow::Release` — exit tag, `check_exit_order`, copy, manifest, notes, `RELEASE_COMPLETE` |
| `tool_overlay.tcl` | `cbflow_reload_tool_overlay` — user_config-selected tool overlay |
| `oss_utils.tcl` | open-source PD helpers (`oss_get`, `oss_load_stage`, `oss_upstream_node`, `oss_stage_out`, DEF→GDS, Vt handling, …) |
| `oss_flow_utils.tcl` | open-source RTL / DFT / DV driver helpers (`oss_run`, `oss_exec_all`, `oss_get_opt`, …) |
| `oss_checks.tcl`, `oss_checkgrp_<group>.tcl` | open-source checklist library groups (fp, timing_si, clock, power, routing_mfg, physical, milestone) |
| `oss_scandef.tcl` | OpenROAD scandef chain-order fix |
| `config_loader.tcl`, `flow_init.tcl`, `init_utils.tcl`, `directory_utils.tcl`, `display_utils.tcl`, `error_utils.tcl` | shared plumbing |

Discipline Tcl helpers: `DFT/utils/utilities/v1.0.0/oss_dft_utils.tcl`
(+ `dft_tessent_common.tcl`), `RTL/utils/utilities/v1.0.0/oss_rtl_utils.tcl`,
`DV/utils/utilities/v1.0.0/oss_dv_utils.tcl`.

## 4. Generation (`global/utils/generation/v1.0.0/`)

`generate_setup.tcl` writes each node's `config.tcl` (cascade) and `setup.tcl`
(flow_proc hooks); `vendor_for_tool` maps a tool name to its vendor directory.
`generate_config.tcl`, `generate_inputs.tcl` are supporting generators.

## 5. Handlers and command files (`<DISC>/cmds/<FLOW>/<vendor>/<tool>/v1.0.0/`)

- `<type>_subnode_handler.tcl` per node type — thin, calls `handler_dispatch`
  (`inputs_subnode_handler.tcl` calls `handler_dispatch_inputs`).
- `<stage>_<tool>.tcl` command file per stage — the 10-line bootstrap, flow_procs,
  `flow_exec_all` / `oss_exec_all`, `exit`.
- Vendors: `synopsys`, `cadence`, `mentor`, `generic` (DV `review`),
  `opensource` (yosys, openroad, opensta, magic, fault, iverilog, verilator,
  rtlcheck, …).

## 6. Dashboards

| Package | Role |
|---|---|
| `global/utils/dashboard/` | per-user run dashboard daemon (`daemon.py`, `router.py`, `race_dashboard.py`, `registry.py`, `run_dash_config.py`) |
| `global/utils/project_dashboard/` | SmartGrid: `router.py` (pages + API), `releases.py`, `chain.py` (sign-off chain), `floorplan.py` (DEF viewer), `checklist_stats.py`, `schedule_config.py`, `tracker_db.py`, `dash_config.py` |

## 7. Open-source helpers

| Path | Role |
|---|---|
| `RTL/utils/oss/spec_tool.py`, `rtl_check.py` | RTL_SPEC collateral; RTL_LINT / RTL_CDC / UPF_CHECK checks |
| `DV/utils/oss/uvmgen.py`, `dv_tool.py` | UVM env generation; regress / covmerge / triage / signoff |
| `DFT/utils/oss/oss_dft.py` | scan trace, fault sim, ATPG glue |
| `global/utils/oss/install_*.sh` | tools installed into `lsf(oss,tools_dir)` (pytools, UVM, Atalanta, IP-XACT schema) |

## 8. AI (`PD/ai/`)

SmartGenie agents (local / cloud / server), knowledge base and MCP server —
see [PD/ai/README.md](../../ai/README.md).

---

**See also:**
- [System Design](system-design.md)
- [Data Flow](data-flow.md)
