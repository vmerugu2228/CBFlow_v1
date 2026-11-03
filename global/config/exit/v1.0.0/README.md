# CBflow Exit Milestones — centrally declared

This directory holds every exit milestone across every discipline (PD, DFT, DV).
Each milestone config declares its owning discipline via
`set milestone_info(discipline) "PD" | "DFT" | "DV"` — the checklist CLI's
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
| **DV** | — | Empty — owner-team seeds when DV flows mature (would land as LINT_EXIT, CDC_EXIT, RDC_EXIT, SIM_EXIT, COV_EXIT, FORMAL_EXIT, UPF_EXIT or similar) |

## Adding a new milestone

1. Create `<MILESTONE_NAME>_config.tcl` in this directory.
2. First four lines MUST set `milestone_info(name|discipline|stage|description)`.
3. Follow the existing PD or DFT configs as a template.
4. The file is picked up automatically — no registry edit needed.

## Adding a new discipline

The CLI's `_DISC_CHOICES` list (checklist_cmd.py) is `['PD', 'DFT', 'DV']`.
Adding a new discipline requires:
1. Append to `_DISC_CHOICES` in `PD/utils/commands/checklist_cmd.py`.
2. Declare milestones here with `milestone_info(discipline) "<NEW>"`.
3. (Nothing else — the discipline filter is a simple string match.)
