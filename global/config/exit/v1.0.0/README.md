# CBflow Exit Milestones — centrally declared

This directory holds every exit milestone across every discipline (PD, DFT, DV, RTL).
Each milestone config declares its owning discipline via
`set milestone_info(discipline) "PD" | "DFT" | "DV" | "RTL"` — the checklist CLI's
`--discipline <X>` flag filters to that owner.

Pre 2026-11-03 these configs lived at `PD/config/exit/v1.0.0/` and the
checklist system was PD-only. The move to `global/` reflects the architectural
decision that phases are shared across disciplines but exit milestones are
discipline-owned yet centrally declared.

## Current coverage

| Discipline | Milestones | Status |
|---|---|---|
| **PD** | FP_EXIT, PLACE_EXIT, CTS_EXIT, PRO_EXIT, BTO, MTO | Production — full check library (182+ library checks) |
| **DFT** | CORE_DFT_EXIT, TOP_DFT_EXIT, EDT_OCC_EXIT, SCAN_INSERT_EXIT, ATPG_PREPD_EXIT, ATPG_POSTPD_EXIT | Seeded — mandatory_files + file-exists checks only; owner-team adds metric-threshold checks over time |
| **DV** | SPEC_RAMP_EXIT, PLANNING_EXIT, TB_SETUP_EXIT, M1_EXIT, M2_EXIT, M3_EXIT, M4_EXIT, ECO_EXEC_EXIT, DV_SIGNOFF_EXIT | Review-gate checks; the open-source UVM flows (tool verilator) add sign-off status + pass-rate / coverage / vPlan metric checks (targets: `project(dv,targets,M<n>)`) |
| **RTL** | SPEC_EXIT, LINT_SIGNOFF, CDC_SIGNOFF, UPF_SIGNOFF | Open-source RTL flows — spec errors / IP-XACT / ports; open errors / warnings, expired waivers |

Plus `STA_SIGNOFF` (checklist published with every STA run). Exits per phase: `project(phase_exits)` (PD) and
`project(phase_exits,<DISC>)` (e.g. DV) in the project config; the exit-order gate orders each discipline's plan.

## Adding a new milestone

1. Create `<MILESTONE_NAME>_config.tcl` in this directory.
2. First four lines MUST set `milestone_info(name|discipline|stage|description)`.
3. Follow an existing config of the same discipline as a template.
4. The file is picked up automatically — no registry edit needed.

## Adding a new discipline

The checklist CLI's `--discipline` choices come from `flow(disciplines)` in
`global/config/flow/v1.0.0/flow_registry.tcl`. Adding a new discipline requires:
1. Add it to `flow(disciplines)` (and its flows / `flow(discipline_dir,*)`) in the flow registry.
2. Declare milestones here with `milestone_info(discipline) "<NEW>"`.
