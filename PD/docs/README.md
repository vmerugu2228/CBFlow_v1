# CBflow Documentation

Documentation index for **CBflow v2.0.0** — a multi-discipline design
automation framework: 33 flows across Physical Design (PD, 12), Design-for-Test
(DFT, 7), RTL Design Verification (DV, 9) and RTL design quality (RTL, 5), on
one Python RACE DAG engine with SQLite status tracking, per-discipline run
dashboards, SmartGrid project dashboard and an exit-release model.

Repository layout (paths relative to `$CBFLOW_ROOT`): `global/` (shared CLI,
engine, Tcl runtime, registry, project / tech / exit configs), `PD/`, `DFT/`,
`DV/`, `RTL/` (per-discipline configs, commands, docs), `workarea/`. The
one-page framework summary is [`CLAUDE.md`](../../CLAUDE.md); changes are in
[`RELEASE_NOTES.md`](../../RELEASE_NOTES.md).

> **Recent (2026-11)**: spec-to-GDS on the open-source stack — RTL_SPEC →
> RTL_LINT / RTL_CDC / UPF_CHECK → UVM on Verilator → SYNTH / FP / PNR / signoff
> → scan / ATPG / GLS, driven by `project(signoff_chain,<phase>)` and
> `workarea/run_spec2gds.sh`, with a SmartGrid chain page; library-manager
> `check --lib_tag / --design`; DFT scandef handoff; floorplan / drc-fix /
> timing-eco Claude Code skills (`.claude/skills/`).

## Start here

1. [Kickstart](00-kickstart/KICKSTART.md) — set `CBFLOW_ROOT`, PATH, first run
2. [Multi-Discipline Kickoff](00-kickstart/multi-discipline-kickoff.md) — PD / DFT / DV / RTL on one install
3. [Quick Start](01-quick-start/README.md) — [installation](01-quick-start/installation.md), [system requirements](01-quick-start/system-requirements.md), [first version](01-quick-start/first-version.md)
4. [User Guide index](02-user-guide/README.md)

## 02. User Guides (PD/docs/02-user-guide)

| Guide | Topic |
|---|---|
| [Complete User Guide](02-user-guide/cbflow-complete-user-guide.md) | Full walkthrough |
| [Flow User Guide](02-user-guide/cbflow-flow-user-guide.md) | Flows and stages |
| [GUI User Guide](02-user-guide/cbflow-gui-user-guide.md) | Run dashboard: DAG, config editor, branches, MMMC dialog, release form |
| [Dashboard Daemon](02-user-guide/dashboard-daemon-guide.md) | Per-user run dashboard daemon, ports per discipline |
| [SmartGrid / Project Dashboard](02-user-guide/project-dashboard-guide.md) | Published runs, releases page, waivers, chain page |
| [Exit Release Guide](02-user-guide/exit-release-guide.md) | Exit releases, source-stage exits, set-dep, clone, exit-order gates |
| [Open-Source Flow Guide](02-user-guide/opensource-flow-guide.md) | sky130 RTL-to-GDS: Yosys / OpenROAD / OpenSTA / KLayout / Magic / Netgen via `cbflow-oss` |
| [Spec-to-GDS Guide](02-user-guide/spec-to-gds-guide.md) | One block from YAML spec to signed-off GDS across all disciplines |
| [Library Manager](02-user-guide/library-manager-user-guide.md) | Library tags, `add --category block|memory`, `check` |
| [MMMC Manager](02-user-guide/mmmc-manager-user-guide.md) | MMMC scenarios and views |
| [SmartGenie](02-user-guide/smartgenie-user-guide.md) | AI assistant (local / cloud / Claude Code) |
| [Release Management](02-user-guide/release-management.md) | Framework (CBflow) releases |
| [Versioning Workflow](02-user-guide/versioning-workflow.md) | Copy / edit / set-current |
| [Changelog System](02-user-guide/changelog-system.md) | Framework change tracking |
| [Troubleshooting](02-user-guide/troubleshooting.md) | Common issues |

## Discipline guides

| Discipline | Guides |
|---|---|
| RTL | [RTL README](../../RTL/docs/README.md) · [Open-Source RTL Guide](../../RTL/docs/opensource-rtl-guide.md) (RTL_SPEC, RTL_LINT, RTL_CDC, UPF_CHECK) |
| DV  | [Open-Source DV Guide](../../DV/docs/opensource-dv-guide.md) (UVM on Verilator: TB_SETUP, M1–M4_EXEC, DV_SIGNOFF) |
| DFT | [DFT README](../../DFT/docs/README.md) · [Open-Source DFT Guide](../../DFT/docs/opensource-dft-guide.md) · [DFT Flow Reference](../../DFT/docs/DFT_Flow_Reference.md) · [DFT Insert](../../DFT/docs/DFT_Insert_Guide.md) · [Scan Insert](../../DFT/docs/Scan_Insert_Guide.md) · [ATPG](../../DFT/docs/ATPG_Guide.md) · [GLS Verification](../../DFT/docs/GLS_Verification_Guide.md) |
| Exits | [Exit milestone configs](../../global/config/exit/v1.0.0/README.md) |

## 03. Reference (PD/docs/03-reference)

[Index](03-reference/README.md) ·
[Configuration](03-reference/configuration-reference.md) ·
[Python Scripts](03-reference/python-scripts-reference.md) ·
[RACE Engine Commands](03-reference/makefile-reference.md) ·
[LSF](03-reference/lsf-reference.md) ·
[LSF Coverage Checks](03-reference/lsf-checks.md) ·
[MMMC](03-reference/mmmc-reference.md) ·
[MSCTS / Multipoint CTS](03-reference/mscts-mpcts-reference.md) ·
[Git Reference](03-reference/git-reference.md) ·
[Production Git Setup](03-reference/production-git-setup.md) ·
[Production Dashboard Setup](03-reference/dashboard-production-setup.md)

Topic references in `PD/docs/`: [Flow Procs](Flow_Procs_Reference.md) ·
[Stage Variables](Stage_Variables_Reference.md) ·
[MMMC Setup](MMMC_Setup_Guide.md) ·
[Timing Corners](timing_corners_list.md) ·
[Checklist Guide — SYNTH_PNR](Checklist_Guide_SYNTH_PNR.md) ·
[Checklist Guide — Other Flows](Checklist_Guide_Other_Flows.md)

## 04. Architecture (PD/docs/04-architecture)

- [Index](04-architecture/README.md)
- [System Design](04-architecture/system-design.md) — layout, launchers, config cascade, RACE, handlers, `cbflow-oss`, command files, releases, handshakes, exits, dashboards
- [Data Flow](04-architecture/data-flow.md) — workspace → run → handshake → release → SmartGrid
- [Component Design](04-architecture/component-design.md) — module map
- [Versioning Strategy](04-architecture/git-strategy.md)

## 05. Developer Guide (PD/docs/05-developer)

- [Index](05-developer/README.md)
- [Extending CBflow](05-developer/extending.md) — flows, subcommands, open-source tool overlays, handshakes, exit milestones
- [Contributing](05-developer/contributing.md)
- [Test Suite](05-developer/test-suite.md) — `cbflow test --static | --e2e | --cli-smoke | --integration | --hardcode`
- [Release 2026-07-10 Features](05-developer/release-2026-07-10-features.md) (historical)

## 06. Examples (PD/docs/06-examples)

[Index](06-examples/README.md) · [Basic Workflows](06-examples/basic-workflows.md) ·
[Release Workflows](06-examples/release-workflows.md) ·
[Advanced Scenarios](06-examples/advanced-scenarios.md)

## AI

[SmartGenie agent](../ai/README.md) · [Fine-tuning](../ai/fine_tune/README.md) ·
[AI Agent Plan](CBflow_AI_Agent_Plan.md) · Claude Code skills:
`.claude/skills/floorplan/`, `.claude/skills/drc-fix/`, `.claude/skills/timing-eco/`

## Feature documents and history

[v2.1.1 Feature Document](CBflow_v2.1.1_Feature_Document.md) ·
[v2.0.0 Feature Document](CBflow_v2.0.0_Feature_Document.md) ·
[Training Presentation](CBflow_Training_Presentation.md) ·
[Future Development Scope](FUTURE_DEVELOPMENT_SCOPE.md) ·
[Session Report 2026-05-18](SESSION_REPORT_2026-05-18.md).
Superseded material is in `archive/`.

## Command quick reference

| Command | Purpose |
|---|---|
| `cbflow workspace create --config uc_<FLOW>.tcl` | Create a run dir (from `workarea/<block>/`) |
| `cbflow run all` / `cbflow run stage --name <node>` | Run the flow / one node |
| `cbflow run status --details` | Progress from the RACE DB |
| `cbflow run retrace --from <node>` | Re-run a node and downstream |
| `cbflow run bypass --stages a,b` / `force --stages a` / `forcevalidate --node a` | Skip / re-run only / mark done |
| `cbflow run add-node --node <n> --type <t> --dep <d>` | Add a node |
| `cbflow run set-dep --node <n> --deps a,b [--reset]` | Rewire dependencies |
| `cbflow run create-branch --branch <b> --from <node>` | Branch the DAG |
| `cbflow run gen-makefile` | Verify the engine DAG (historical name) |
| `cbflow run release [--from-run <run>] [--node <n>] [--clone-from <exit> --tag <exit>] [--publish]` | Exit release / clone / publish |
| `cbflow run gui` | Run dashboard (per-user daemon; PD 9000 + uid%300) |
| `cbflow run db-manage status|backup|query|export` | RACE DB management |
| `cbflow smartgrid start --project <p>` | SmartGrid |
| `cbflow flow types` / `info --flow <F>` / `nodes --flow <F>` | Flow catalogue |
| `cbflow flow checklist list|list-checks|generate|status|sign-off|add-check|waiver` | Exit checklists |
| `cbflow flow library-manager …` / `mmmc-manager …` | PD tools (via `cbflow-pd`) |
| `cbflow test --static` / `--e2e --flow <F>` | Test suite |
| `cbflow-oss check` | Open-source tool container |

Shell completion: `source $CBFLOW_ROOT/PD/completions/cbflow.bash` (bash) or
add `$CBFLOW_ROOT/PD/completions` to `fpath` (zsh, `_cbflow`).

---

**Last Updated**: 2026-11-26
