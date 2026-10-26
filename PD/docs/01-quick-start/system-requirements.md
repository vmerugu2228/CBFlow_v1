# CBflow v2.0.0 -- System Requirements

---

## 1. Core Runtime

| Tool | Minimum | Purpose |
|------|---------|---------|
| **Python** | 3.6+ | CLI commands, RACE engine, metrics, reports |
| **Tcl/Tclsh** | 8.5+ | Flow configs, command files, flow_proc engine |
| **Bash/Zsh** | 4.0+ | CLI dispatcher, shell completions |

### Python -- Stdlib Only (No pip install)

CBflow uses only Python standard library modules:

| Module | Purpose |
|--------|---------|
| `argparse` | CLI parsing for all 25 command modules |
| `subprocess` | Tool and process execution |
| `json` | Config/report I/O |
| `sqlite3` | Metrics DB, trending, QoR history |
| `re` | TCL config parsing, library filename parsing |
| `logging` | Unified logging with file rotation |
| `pathlib` / `os` / `shutil` | File system operations |
| `csv` | Metrics and QoR export |
| `dataclasses` | Structured types (LibraryFile, QoRMetrics) |
| `http.server` | Web dashboard (lightweight, no Flask) |
| `collections` | defaultdict, OrderedDict |
| `datetime` | Timestamps, duration tracking |
| `getpass` | Username detection for workspaces |
| `signal` | Process signal handling |

### TCL Features Required

| Feature | Min Version | Usage |
|---------|:-----------:|-------|
| `dict` | 8.5 | MMMC config, analysis views |
| `{*}` expansion | 8.5 | CBFLOW_BSUB_CMD in handlers |
| `namespace eval` | 8.0 | LSF, XTerm, flow utilities |
| `array set` | 8.0 | All config files |
| `file normalize` | 8.4 | Path resolution |

### Make Features Required

| Feature | Usage |
|---------|-------|
| `-include` | Dynamic MMMC timing targets |
| `$(foreach)` | Per-scenario stamp expansion |
| `-j` parallel | Multi-scenario STA execution |
| `.PHONY` | Stage/subnode targets |

---

## 2. EDA Tools

Only tools for your selected flows are needed. CBflow supports 12 flows across three vendor tool suites.

### Supported Flows (12)

SYNTH, FP, PNR, STA, LEC, EMIR, PV, ECO, CLP, POPT, FCFP, SYNTH_PNR.

### Synopsys

| Tool | Binary | Flows | Min Version |
|------|--------|-------|:-----------:|
| Fusion Compiler | `fc_shell` | SYNTH, FP, PNR, ECO, FCFP, SYNTH_PNR | 2025.06+ |
| PrimeTime | `pt_shell` | STA, POPT | W-2024.09+ |
| Formality | `formality` | LEC | 2025.06+ |
| IC Validator | `icv` | PV | V-2023.12+ |
| RedHawk | `redhawk` | EMIR | 2025.06+ |
| VC LP | `vc_lp` | CLP | 2025.06+ |

### Cadence

| Tool | Binary | Flows | Min Version |
|------|--------|-------|:-----------:|
| Genus | `genus` | SYNTH | 23.1+ |
| Innovus | `innovus` | FP, PNR, FCFP | 23.1+ |
| Tempus | `tempus` | STA | 23.1+ |
| Conformal LP | `conformal_lp` | CLP | 23.1+ |
| Voltus | `voltus` | EMIR | 23.1+ |

### Mentor/Siemens

| Tool | Binary | Flows | Min Version |
|------|--------|-------|:-----------:|
| Calibre | `calibre` | PV (alternative) | 2023.1+ |

Tools must be in `$PATH` with valid licenses. CBflow does not manage tool installation. Use `module load` or equivalent to make tools available.

---

## 3. LSF (Optional)

| Component | Minimum Version | Purpose |
|-----------|:-----------:|---------|
| LSF | 10.1+ | Batch job management |

### LSF Commands Used

| Command | Purpose |
|---------|---------|
| `bsub` | Job submission |
| `bjobs` | Job status |
| `bqueues` | Queue info |
| `bhosts` | Host info |
| `bkill` | Job kill |

**LSF is not required.** CBflow runs locally without it. Three integration levels available:
- Config-driven queue mapping (automatic)
- `cbflow run lsf-submit` (CLI control)
- `CBFLOW_BSUB_CMD` env var (direct bsub bypass)

---

## 4. Compute Resources

### Per-Stage Recommendations

| Stage Type | Memory | CPU | Disk |
|------------|-------:|----:|-----:|
| Inputs / Export / Release | 4-8 GB | 2-4 | 1 GB |
| Synthesis | 16-32 GB | 4-8 | 10 GB |
| Floorplan / Powerplan | 16-32 GB | 4-8 | 10 GB |
| Placement / CTS | 32-64 GB | 8-16 | 20 GB |
| Routing | 64-128 GB | 16-32 | 50 GB |
| STA (per scenario) | 32-64 GB | 8-16 | 10 GB |
| PV (DRC/LVS) | 32-64 GB | 8-16 | 30 GB |
| EMIR (IR Drop/Thermal) | 64-128 GB | 16-32 | 40 GB |

### Storage

| Item | Size |
|------|-----:|
| CBflow framework | ~50 MB |
| Per-run work data | 5-100 GB |
| Metrics database | 1-10 MB |
| Logs per run | 100 MB - 1 GB |

---

## 5. CBflow Framework Inventory

### Python Modules (25)

| Module | Lines | Purpose |
|--------|------:|---------|
| `workspace_cmd.py` | 1,429 | Workspace init, create, status |
| `run_cmd.py` | 1,500+ | Run execution, logs, validation |
| `race_engine.py` | 800+ | RACE DAG executor with SQLite tracking |
| `mmmc_manager_cmd.py` | 1,670 | MMMC create, validate, view-def |
| `qor_report_cmd.py` | 1,456 | QoR report, compare, summary |
| `release_cmd.py` | 1,223 | Release create, list, diff |
| `library_manager_cmd.py` | 1,019 | Library scan, verify, create, MMMC gen |
| `checklist_cmd.py` | 832 | Exit checklists, sign-off, waivers |
| `node_manager.py` | 700+ | Custom node management |
| `trending_cmd.py` | 639 | Trending, baselines, regression |
| `tcl_config_parser.py` | 600+ | TCL config to Python parser |
| `metrics_cmd.py` | 555 | Metrics collect, report, export |
| `validation_cmd.py` | 528 | Pre/post-stage validation |
| `start_run.py` | 500+ | Run initialization |
| `lsf_cmd.py` | 450+ | LSF submit, run, status, cost |
| `plugin_cmd.py` | 400+ | Plugin scaffold, register |
| `version_cmd.py` | 320+ | Version copy, set-current, diff |
| `flow_cmd.py` | 300+ | Flow types, info, stages |
| `graph_renderer.py` | 300+ | Dependency visualization |
| `config_cmd.py` | 200+ | Config management |
| `log_viewer.py` | 200+ | Log viewing and analysis |
| `color_utils.py` | 200+ | Colorized output |
| `project_cmd.py` | 200+ | Project management |
| `logging_config.py` | 150+ | Unified logging setup |
| `workspace_manager.py` | 140 | Version directory ops |
| **Total** | **~16,700** | |

### EDA Command Files

| Vendor | Files | Lines |
|--------|:-----:|------:|
| Synopsys (6 tools) | 83 | ~16,000 |
| Cadence (5 tools) | 50 | ~12,800 |
| Mentor/Siemens (1 tool) | 5 | ~1,200 |
| **Total** | **138** | **~30,000** |

### Subnode Handlers

| Type | Count |
|------|:-----:|
| Tool execution (with CBFLOW_BSUB_CMD) | 70 |
| Infrastructure (inputs/export/release) | ~80 |
| **Total** | **~150** |

### Configuration Files

| Category | Count |
|----------|:-----:|
| Core flow configs | 5 |
| Node configs (per flow) | 13 |
| Tech configs (per node) | 2+ |
| Exit milestone configs | 6 |
| Exit support (waiver/threshold/remediation) | 3 |
| Project configs | 2+ |
| **Total** | **~35** |

### Documentation

| Section | Files | Lines |
|---------|:-----:|------:|
| Quick Start | 4 | ~1,000 |
| User Guide | 7 | ~4,000 |
| Reference | 7 | ~2,500 |
| Architecture | 5 | ~1,200 |
| Developer | 3 | ~600 |
| Examples | 4 | ~700 |
| **Total** | **30** | **~10,000** |

### Grand Total

| Category | Files | Lines |
|----------|:-----:|------:|
| Python modules | 25 | 16,700 |
| Command files (Synopsys + Cadence + Mentor) | 138 | 30,000 |
| Subnode handlers | 150 | 12,000 |
| TCL utilities | 15 | 3,000 |
| Config files | 35 | 8,000 |
| Documentation | 30 | 10,000 |
| Shell scripts | 10 | 1,000 |
| **Grand Total** | **~400** | **~81,000** |

---

## 6. Verification

```bash
# Core tools
python3 --version                          # 3.6+
tclsh <<< 'puts [info patchlevel]'         # 8.5+
bash --version | head -1                   # 4.0+

# Python stdlib check (zero external deps)
python3 -c "import sqlite3, json, argparse, logging, subprocess, csv, dataclasses; print('OK')"

# CBflow
cbflow --version
cbflow flow types                          # 12 flows
cbflow flow check                          # Tool availability

# EDA tools (check what you need)
which fc_shell pt_shell innovus genus tempus 2>/dev/null

# LSF (optional)
which bsub 2>/dev/null && bqueues

# Test suite
bin/cbflow-test-suite
```

---

**Documentation Version**: 2.0.0
