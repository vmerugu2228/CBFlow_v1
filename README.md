# CBflow Delivery Bundle — 2026-09-23

**Source of truth:** git branch `cbflow_global` in
https://github.com/vmerugu2228/CBFlow_v1

## What's in this folder

| File | Purpose |
|---|---|
| `CBflow_2026-09-23.tar.gz` | Portable source archive — extract + run |
| `bundle_test_report.json` | Test-suite output produced by extracting THIS bundle and running the suite against the extracted copy |
| `bundle_test_report.junit.xml` | JUnit XML for CI |
| `dashboard_snapshot.json` | Snapshot of dashboard-registered runs at bundle time |
| `COMMIT_SHA.txt` | Exact commit the source archive was generated from |
| `RECENT_COMMITS.txt` | Last 5 commits for context |
| `RELEASE_NOTES.md` | Human-readable summary of the release |
| `CHECKSUMS.sha256` | SHA-256 for every file in this folder |

## Highlights of this release (`cbflow_global`)

- **Multi-discipline:** framework now hosts **PD** (12 flows), **DFT**
  (5 flows scaffolded + full handler set), and **DV** (7 flows scaffolded)
  as first-class disciplines.
- **Global config layer:** cross-domain identity (tech, project, MMMC,
  flow catalog) lives under `global/`. Each discipline overlays its own
  physical/tool-specific bits.
- **New launcher structure:** `bin/cbflow` at the repo root — a universal
  launcher symlinked to `global/bin/cbflow`. Each discipline has its own
  launcher (`PD/bin/cbflow-pd`, `DFT/bin/cbflow-dft`, `DV/bin/cbflow-dv`)
  hosting subcommands specific to that discipline. Auto-dispatch means
  `cbflow flow library-manager …` still works from anywhere.
- **RACE DB enforced at workspace-create time:** every run has a DB +
  `.race_db_pointer` immediately after creation, not lazily on first
  `run all`.
- **Backwards compatible:** every existing `.run.cbflow.tcl`, workspace,
  user_config, and tool handler works unchanged.

See `RELEASE_NOTES.md` for the full change list and the docs at
`PD/docs/00-kickstart/multi-discipline-kickoff.md` for the fastest path
from checkout to running your first flow.

## Verify integrity

```bash
shasum -a 256 -c CHECKSUMS.sha256
```

## Deploy

```bash
tar xzf CBflow_2026-09-23.tar.gz
cd CBflow

# Static suite — 1338 PASS / 0 FAIL / 87 SKIP expected
bin/cbflow test --static

# Full end-to-end suite (~10 min) — 419 PASS / 0 FAIL expected
bin/cbflow test --e2e
```

## Environment

Only `CBFLOW_ROOT` is user-facing. Every other `CBFLOW_*` env var is
auto-derived by the launcher.

```
CBFLOW_ROOT         Umbrella install root
CBFLOW_CORE_DIR     Auto: $CBFLOW_ROOT/PD
CBFLOW_GLOBAL_DIR   Auto: $CBFLOW_ROOT/global
CBFLOW_DFT_DIR      Auto: $CBFLOW_ROOT/DFT       (if directory exists)
CBFLOW_DV_DIR       Auto: $CBFLOW_ROOT/DV        (if directory exists)
```

`bin/cbflow --version` prints the full derivation chain.

## First flow

```bash
cd /path/to/workarea/<design_name>
bin/cbflow workspace template --flow SYNTH_PNR > user_config.tcl
vi user_config.tcl
bin/cbflow workspace create --config user_config.tcl
cd LC1_run_SYNTH_PNR_run1
bin/cbflow run all
bin/cbflow run status --details
```

## Bundle test result (proof of deliverability)

`bundle_test_report.json` above was produced by:

1. Extracting `CBflow_2026-09-23.tar.gz` into a fresh scratch dir
2. Running `bin/cbflow test` against the extracted copy
3. Writing the JSON report

The bundle is proven-deliverable: extracting into a clean environment
produces a working CBflow install with the full test suite green.
