# Python Scripts Reference

Technical reference for all 28 CBflow v2.0.0 Python CLI modules.

## Overview

CBflow's CLI is organized into command groups under the `cbflow` entry point. All 28 modules are located under `utils/commands/` and are invoked via:

```bash
cbflow <group> <subcommand> [options]
```

Supported flows across all modules: **SYNTH, FP, PNR, STA, LEC, EMIR, PV, ECO, CLP, POPT, FCFP, SYNTH_PNR** (12 flows).

---

## Module Index (28 modules)

| Module | Command Group | Subcommands | Purpose |
|--------|--------------|:-----------:|---------|
| `run_cmd.py` | `cbflow run` | 23 | Run execution, lifecycle, and management |
| `workspace_cmd.py` | `cbflow workspace` | 2 | Workspace initialization and status |
| `checklist_cmd.py` | `cbflow checklist` | 8 | Exit milestone checklist management |
| `email_cmd.py` | `cbflow email` | -- | Email notifications with 6 templates |
| `autoppt_cmd.py` | `cbflow autoppt` | -- | Automated PowerPoint/HTML report generation |
| `release_cmd.py` | `cbflow release` | -- | Release creation and management |
| `version_cmd.py` | `cbflow version` | -- | Directory-based version management |
| `flow_cmd.py` | `cbflow flow` | -- | Flow execution, status, and control |
| `config_cmd.py` | `cbflow config` | -- | Configuration management |
| `project_cmd.py` | `cbflow project` | -- | Project-level settings management |
| `lsf_cmd.py` | `cbflow lsf` | -- | LSF job submission and status |
| `lsf_manager_cmd.py` | `cbflow lsf-manager` | -- | LSF queue and resource management |
| `library_manager_cmd.py` | `cbflow library` | -- | Library scanning, checking, MMMC generation |
| `mmmc_manager_cmd.py` | `cbflow mmmc` | -- | MMMC configuration management |
| `log_viewer.py` | `cbflow logs` | -- | Log file viewing and search |
| `makefile_generator.py` | -- | -- | Makefile generation for flow execution |
| `validation_cmd.py` | `cbflow validate` | -- | Configuration and setup validation |
| `qor_report_cmd.py` | `cbflow qor-report` | -- | QoR report generation and comparison |
| `dashboard_cmd.py` | `cbflow dashboard` | -- | Status dashboard display |
| `trending_cmd.py` | `cbflow trending` | -- | QoR trending across runs |
| `metrics_cmd.py` | `cbflow metrics` | -- | Design metrics collection |
| `tcl_config_parser.py` | -- | -- | TCL configuration file parser (library) |
| `logging_config.py` | -- | -- | Logging configuration and setup (library) |
| `node_manager.py` | -- | -- | Flow node and stage management (library) |
| `graph_renderer.py` | -- | -- | Flow graph visualization (library) |
| `start_run.py` | -- | -- | Run initialization and bootstrapping (library) |
| `plugin_cmd.py` | `cbflow plugin` | -- | Plugin management |

---

## run_cmd.py

The primary command handler for flow execution within a run directory. Provides 23 subcommands covering the full run lifecycle.

### Subcommands (23)

| Subcommand | Description |
|-----------|-------------|
| `all` | Run complete flow (all stages sequentially) |
| `stage` | Run a single named stage |
| `status` | Show stage completion status (with `--details` for subnodes) |
| `report` | Detailed per-node report with setup dumps |
| `retrace` | Clear stamps to force rerun (with `--from` for partial retrace) |
| `clean` | Clean run directory (remove work files) |
| `validate` | Run validation checks on the current run |
| `logs` | View run logs (with `--tail`, `--level`, `--stage` filters) |
| `show-graph` | Visualize flow dependency graph |
| `list-nodes` | List all flow nodes and their types |
| `list-branches` | List flow branches |
| `release-info` | Show release information for the run |
| `targets` | List available make targets |
| `gen-makefile` | Regenerate Makefile from current config |
| `lsf-status` | Check LSF job queue status |
| `interactive` | Launch interactive EDA tool session |
| `email` | Send email notifications (delegates to email_cmd.py) |
| `autoppt` | Generate run summary PPT/HTML (delegates to autoppt_cmd.py) |
| `checklist` | Run exit milestone checklist (delegates to checklist_cmd.py) |
| `help` | Show detailed help with examples |
| `add-node` | Add a custom node to the flow |
| `delete-node` | Delete a custom node from the flow |
| `create-branch` | Create a flow branch |
| `delete-branch` | Delete a flow branch |
| `update` | Update run to workspace release or specific version |

### Usage Examples

```bash
cbflow run all                                    # Run complete flow
cbflow run all --lsf --queue XL                   # Submit to LSF with XL queue
cbflow run stage --name place                     # Run placement stage
cbflow run status --details                       # Show detailed progress
cbflow run retrace --from cts --run               # Retrace from CTS and rerun
cbflow run report --node place1                   # Report for specific node
cbflow run logs --tail 50 --level ERROR           # View recent errors
cbflow run show-graph --detail                    # Visualize flow graph
cbflow run add-node --node eco1 --type export_data --dep signoff
cbflow run checklist --milestone BTO --phase P3   # Run exit checklist
cbflow run email --to user@co.com --template run-status
cbflow run autoppt                                # Generate summary PPT/HTML
```

### Key Options (all/stage)

| Option | Description |
|--------|-------------|
| `--validate` | Enable pre/post validation |
| `--lsf` | Submit stages via LSF |
| `--queue` | LSF queue override (S, M, L, XL, ultra) |
| `--collect-metrics` | Collect run metrics after completion |

---

## workspace_cmd.py

Manages workspace initialization and status.

### Subcommands (2)

| Subcommand | Description |
|-----------|-------------|
| `create` | Initialize a new workspace with project structure |
| `status` | Show workspace status, active runs, and release info |

### Usage

```bash
cbflow workspace create --project <name> --tech-node <node>
cbflow workspace status
```

---

## checklist_cmd.py

Exit milestone checklist generation, status tracking, sign-off, and waiver management.

### Subcommands (8)

| Subcommand | Description |
|-----------|-------------|
| `generate` | Generate a formatted checklist for a milestone |
| `status` | Check milestone status against a run directory |
| `sign-off` | Record a sign-off for a milestone |
| `list` | List all available milestones |
| `list-checks` | List all checks in a milestone |
| `add-check` | Add a check to a milestone |
| `remove-check` | Remove a check from a milestone |
| `waiver` | Manage waivers (list, add, revoke) |

### Usage

```bash
cbflow checklist generate --milestone BTO --phase P3
cbflow checklist status --milestone BTO --run-dir /path/to/run
cbflow checklist sign-off --milestone BTO --user <name>
cbflow checklist list
cbflow checklist list-checks --milestone BTO
cbflow checklist add-check --milestone BTO --name <check> --type threshold --metric WNS
cbflow checklist remove-check --milestone BTO --name <check>
cbflow checklist waiver --action add --milestone BTO --check <name> --reason <reason>
```

---

## email_cmd.py

Email notification system using Python stdlib (smtplib + email). Supports 6 templates, preview mode, and file attachments.

### Templates (6)

| Template | Description |
|----------|-------------|
| `run-creation` | Notification when a new run is created |
| `run-status` | Current run status summary |
| `run-summary` | Comprehensive run summary with QoR data |
| `checklist` | Checklist results summary |
| `reminder` | Configurable reminder with due date |
| `release-update` | Release update notification |

### Usage

```bash
cbflow run email --to user@co.com --template run-status
cbflow run email --to user@co.com --template checklist --milestone BTO
cbflow run email --to user@co.com --template reminder --message "CTS review" --due 2026-06-01
cbflow run email --preview --template run-summary         # Preview without sending
cbflow run email --to user@co.com --template run-status --attach report.html
```

### Configuration

Reads email settings from `flow_config.tcl` (`flow(email,*)` variables) or environment variables (`CBFLOW_SMTP_SERVER`, `CBFLOW_SMTP_PORT`, `CBFLOW_EMAIL_FROM`, etc.).

---

## autoppt_cmd.py

Automated PowerPoint / HTML summary generator matching the PD Run Summary Template layout. Uses `python-pptx` if available; falls back to HTML slide deck.

### Output Formats

| Format | Requirement |
|--------|-------------|
| `html` | Default, no external dependencies |
| `pptx` | Requires `python-pptx` package |

### Slides (5)

| Slide | Content |
|-------|---------|
| **Summary** | 19-column QoR table across all stages + image placeholders + metadata |
| **Place** | Placement timing QoR + images + summary |
| **CTS** | CTS timing QoR + clock skew table + summary |
| **ctsOpt** | Post-CTS optimization timing QoR + images + summary |
| **routeOpt** | Route optimization timing QoR + images + summary |

### Stage Mapping

| CBflow Node | PPT Display Name | FC Block Name |
|-------------|-----------------|---------------|
| init_design1 | Initial | init_design |
| synthesis1 | compile | compile |
| place1 | place | place_opt |
| cts1 | cts | clock_opt_cts |
| cts_opt1 | ctsOpt | clock_opt_opto |
| route1 | route | route_auto |
| pro1 | routeOpt | route_opt |
| signoff1 | chipFinish | chip_finish |

### Usage

```bash
cbflow run autoppt                          # Generate with default format (html)
cbflow run autoppt --format pptx            # Generate PowerPoint
cbflow run autoppt --format html --output summary.html
```

---

## release_cmd.py

Manages system releases (create, list, info).

```bash
cbflow release create --version <version> --description <desc>
cbflow release list
cbflow release info --version <version>
```

---

## version_cmd.py

Directory-based versioning (copy, edit, set-current via symlink).

```bash
cbflow version copy --dir <dir> --from <version> --to <version>
cbflow version set-current --dir <dir> --version <version>
cbflow version list --dir <dir>
cbflow version diff --dir <dir> --v1 <version> --v2 <version>
cbflow version create --dir <dir> --version <version>
```

---

## flow_cmd.py

Controls flow execution across all 12 supported flows.

```bash
cbflow flow execute --flow <FLOW> --run <name> [--local] [--lsf-tier <tier>]
cbflow flow status --flow <FLOW> --run <name>
cbflow flow stop --flow <FLOW> --run <name>
cbflow flow resume --flow <FLOW> --run <name>
```

---

## config_cmd.py

Manages CBflow configuration settings.

```bash
cbflow config show [--key <key>]
cbflow config set --key <key> --value <value>
cbflow config validate
```

---

## project_cmd.py

Manages project-level settings and release associations.

```bash
cbflow project list
cbflow project info --name <project>
cbflow project set --name <project> --key <key> --value <value>
```

---

## lsf_cmd.py

LSF job submission and status monitoring.

```bash
cbflow lsf submit --flow <FLOW> --stage <stage> --queue <tier>
cbflow lsf status [--job-id <id>]
cbflow lsf kill --job-id <id>
```

---

## lsf_manager_cmd.py

LSF queue and resource management, including queue tier configuration.

```bash
cbflow lsf-manager show-queues
cbflow lsf-manager show-mapping --flow <FLOW>
cbflow lsf-manager set-mapping --flow <FLOW> --stage <stage> --queue <tier>
```

---

## library_manager_cmd.py

Manages standard cell and IP libraries with multi-track support (9T, 7.5T, 6.75T).

```bash
cbflow library scan --tech-node <node>
cbflow library create --name <name> --track <track>
cbflow library check --track <track>
cbflow library list [--track <track>]
cbflow library generate-mmmc --views <views|all>
```

---

## mmmc_manager_cmd.py

MMMC configuration management -- scenario sets, analysis views, per-node assignments.

```bash
cbflow mmmc list-sets
cbflow mmmc list-views
cbflow mmmc list-nodes
cbflow mmmc show-node --name <node>
cbflow mmmc validate
```

---

## log_viewer.py

Log file viewing and search with filtering.

```bash
cbflow logs show --stage <stage> [--level ERROR] [--tail 50]
cbflow logs search --pattern <regex>
```

---

## makefile_generator.py

Generates Makefiles for flow execution based on node config (stages, dependencies, subnodes). Called internally by `cbflow run gen-makefile` and during run creation.

---

## validation_cmd.py

Validates configurations and setup before flow execution.

```bash
cbflow validate config --dir <dir>
cbflow validate setup --flow <FLOW>
cbflow validate mmmc
cbflow validate libraries
```

---

## qor_report_cmd.py

QoR (Quality of Results) report generation and comparison.

```bash
cbflow qor-report generate --flow <FLOW> --run <name> [--format html|text|json]
cbflow qor-report compare --flow <FLOW> --run1 <name> --run2 <name>
cbflow qor-report summary --flow <FLOW>
```

---

## dashboard_cmd.py

Status dashboard display for workspace overview.

```bash
cbflow dashboard show [--refresh <seconds>]
cbflow dashboard summary
```

---

## trending_cmd.py

Tracks QoR metrics across multiple runs over time.

```bash
cbflow trending show --flow <FLOW> [--metric <metric>]
cbflow trending export --flow <FLOW> --format csv|json
```

---

## metrics_cmd.py

Collects design metrics from flow outputs.

```bash
cbflow metrics collect --flow <FLOW> --run <name>
cbflow metrics show --flow <FLOW> --run <name>
cbflow metrics export --flow <FLOW> --run <name> --format json
```

---

## tcl_config_parser.py

Library module for parsing TCL configuration files. Provides `get_flow_types()`, `parse_config()`, `clear_cache()`, and other utilities for reading CBflow TCL configs from Python.

---

## logging_config.py

Library module for unified logging configuration. Provides `configure_logging(name)` and `get_logger(name)` for consistent log formatting across all CLI modules.

---

## node_manager.py

Library module for flow node and stage management. Handles node creation, deletion, dependency resolution, and branch operations used by `cbflow run add-node`, `delete-node`, `create-branch`, etc.

---

## graph_renderer.py

Library module for flow graph visualization. Renders stage dependency graphs used by `cbflow run show-graph`.

---

## start_run.py

Library module for run initialization and bootstrapping. Handles run directory creation, environment file generation, Makefile setup, and config sourcing during `cbflow workspace create` and run creation.

---

## plugin_cmd.py

Manages CBflow plugins for custom extensions.

```bash
cbflow plugin list
cbflow plugin install --path <path>
cbflow plugin enable --name <name>
cbflow plugin disable --name <name>
```

---

## Exit Codes (All Modules)

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Invalid arguments or usage error |
| 2 | Configuration error |
| 3 | Flow execution error |
| 4 | Resource not found |
| 5 | Validation failure |

---

**See also:**
- [Configuration Reference](configuration-reference.md) -- Config file details
- [LSF Reference](lsf-reference.md) -- LSF integration details
- [MMMC Reference](mmmc-reference.md) -- MMMC configuration details
- [System Design](../04-architecture/system-design.md) -- Architecture
- [Examples](../06-examples/basic-workflows.md) -- Workflow examples
