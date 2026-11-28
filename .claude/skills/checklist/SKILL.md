---
name: checklist
description: Run, triage and strengthen CBflow exit-milestone checklists (PD FP_EXIT…BTO/MTO, STA_SIGNOFF, DFT CORE_DFT_EXIT…ATPG_POSTPD_EXIT, DV TB_SETUP_EXIT…DV_SIGNOFF_EXIT, RTL SPEC_EXIT/LINT/CDC/UPF_SIGNOFF) for a run directory — evaluate the checklist with `cbflow flow checklist status`, rank the failures (blocking before optional, tape-out strictest, no-data apart) with report evidence, value vs threshold, cause and remediation, propose concrete fixes (run-local override snippets, reruns, ECOs; waivers only within policy), find checks the milestone is missing for what the run produces, and keep a per-tech / per-block learned store of recurring failures and fixes. Use when the user asks to run / generate / validate an exit checklist, asks why a milestone is BLOCKED, what to fix before an exit or tape-out, whether a waiver is possible, or which checks are missing.
---

# Exit checklist (CBflow checklist)

You evaluate with **`bin/cbflow flow checklist` commands** and read with the
scripts in `scripts/`; you **never edit framework configs** (`*/config/**/*.tcl`,
incl. `global/config/exit/`) or framework code. Fixes are proposals; a
run-local file (`<run>/setup/user_config.tcl`, `override_config.<node>.tcl`)
is written only after the user approves the exact snippet. Read
[reference.md](reference.md) (status semantics, data sources, policy, drill-down,
known framework gaps) first.

`$SK` = `.claude/skills/checklist`, `$CB` = repo root (run commands from it),
`<run>` = run directory, `<M>` = milestone.

## 1. Context and prior knowledge
```bash
python3 $SK/scripts/learn.py context <run>               # flow / phase / project / block / tech + store files
python3 $SK/scripts/learn.py read --run-dir <run> --summary
```
Read the matching `learned/<tech>/_tech.md` and `<block>.md` entries before
triage; recurring failures and fixes that worked come first in your advice.

## 2. Pick the milestone and evaluate
```bash
bin/cbflow flow checklist list [--discipline PD|DFT|DV|RTL]
bin/cbflow flow checklist generate --milestone <M> --project <p> --phase <P>   # definition (text|json|html)
bin/cbflow flow checklist status --milestone <M> --run-dir <run>               # the verdict
```
`status` needs `--milestone` (PNR → FP/PLACE/CTS/PRO_EXIT, BTO, MTO; STA →
STA_SIGNOFF; ATPG → ATPG_PREPD/POSTPD_EXIT; M<n>_EXEC → M<n>_EXIT …; the
flow's exits are the `exit_node,<M>` keys of its tool map). It writes
`<run>/logs/checklist_status_<M>_<ts>.json` and the RACE DB
`checklist_results` rows (replacing the previous evaluation of that
milestone/phase) — both expected. Trust `status`, not `list-checks --run-dir`
(it skips the tool map, reference.md).

## 3. Triage
```bash
python3 $SK/scripts/checklist_triage.py <run> --milestone <M> [--all] [--json <f>]
```
Tiers: 1 mandatory FAIL, 2 missing mandatory file, 3 critical library FAIL,
4 mandatory not run, 5 non-blocking FAIL (TAPE-OUT REVIEW at BTO/MTO),
6 no data. Per item: report + evidence line, value vs check threshold, the
phase policy threshold, node state (BYPASSED / job status), cause, remediation
text, waiver eligibility, learned entries. Then confirm each tier 1–4 cause in
the run (drill-down table in reference.md): open the per-scenario / per-stage
report, the stage log, the DB job. Separate **design problems** (real QoR) from
**checklist problems** (wrong report, other flow's path, bypassed stage,
contradicting reports) — say which each blocker is.

## 4. Propose fixes (propose only)
Per blocker, one concrete action:
- **Design / QoR**: the flow action — rerun a stage, an ECO (skills
  `timing-eco` for setup / hold / DRV, `drc-fix` for DRC / antenna), a
  floorplan change (`floorplan`). Give the `bin/cbflow run …` commands for the
  user to run (`retrace --from`, `stage --name`, `bypass`…); do not run them.
- **Run settings**: a snippet for `<run>/setup/user_config.tcl` or
  `override_config.<node>.tcl`, using only keys that exist — find them first:
  `grep -n "<arr>(<key>" <disc>/config/flow/v1.0.0/node_configs/<FLOW>*_config.tcl`.
  Show file + lines; write it only after the user says yes, then give the
  retrace / stage commands.
- **Checklist definition gap** (tool map / milestone config wrong for this
  flow): describe the config change for the owner (file, key, value); never edit it.
- **Waiver**: only when the user decides, never at BTO/MTO
  (`allow_bto_waivers` / `allow_mto_waivers` false), expiry ≤ today + 90 days,
  named approver, reason, conditions. Command in reference.md; `waiver --action
  add` prints the Tcl entry for `waiver_config.tcl` — adding it is the owner's call.

## 5. Missing checks
```bash
python3 $SK/scripts/missing_checks.py <run> --milestone <M> [--max N] [--json <f>]
```
A lax checks (pass while the report says NOT MET / FAIL, vacuous `>= 0`,
two reports disagreeing), B peer-milestone gaps, C unchecked metrics
(violating values first), D library checks measurable but not applicable,
E unread exit-node reports. Filter to what matters for the block / flow / phase
(drop informational keys and duplicates of an existing check), and present the
shortlist with the exact `add-check` command (grep / file checks) or the config
change (metric thresholds: add-check cannot set them). `add-check` edits
`global/config/exit/` — it is the user's / owner's command to run.

## 6. Learn
After the session append one line per fact (observed in the run, or decided
by the user — nothing inferred):
```bash
python3 $SK/scripts/learn.py add --run-dir <run> --milestone <M> --check <check> --kind <kind> --text "<fact>"
python3 $SK/scripts/learn.py add --run-dir <run> --tech-wide --milestone <M> --check <check> --kind note --text "<tech-wide fact>"
```
kinds: `failure` (value, scenario), `cause` (confirmed root cause), `fix` /
`fix-failed` (what was applied, result), `waiver` (id, expiry, approver),
`missing-accepted` / `missing-rejected` (suggested check name + user reason),
`threshold`, `note`. Tech-wide (`_tech.md`) only for facts that hold for every
block on the node (library / PDK / tool behaviour).

## 6b. Tags and dependencies across the blocks
Before trusting a milestone, check that every release was built on the right
upstream versions — RTL tag, synthesis / floorplan / PNR tags, library tag,
children in the parent's library tag:
```bash
python3 $SK/scripts/tag_audit.py --project <p> [--phase <P>] [--blocks <b> …] [--quiet] [--json out.json]
```
It traces each release's inputs (its run's `<arr>(input,*release_tag)` /
release paths / `from_run` / `project(lib_config_tag)`) through the handshake
map and reports, per block: stale inputs (upstream re-released after the
consumer was built — transitive too), missing inputs, versions that are not
the exit's **release candidate** (latest release unless pinned with
`cbflow flow release candidate set`), RTL read outside a signed-off release,
library-tag mix along a chain / missing tag / newer tag, signoff flows of one
exit reading different implementation releases, and for parents: children
missing from the library tag, a tag copy older than the child's re-release,
a child version that is not the child's candidate, `pv_release PENDING`.
Then a **resolution plan**: the releases to rebuild in dependency order (run
dir + `retrace --from <first node>` + `run all`; spec-to-GDS blocks:
`run_spec2gds.sh FROM=`), and the config lines to change (`"<EXIT>@candidate"`,
library tag, new tag for a stale child) — show them; reruns, candidate pins and
config edits are the user's call. Exit 1 when any ERROR. Checks / codes:
reference.md → Tag audit.

## 7. Report
Verdict + counts; the ranked blockers (evidence, cause, design vs checklist
problem, proposed action); non-blocking items worth action (all of them at
BTO/MTO); tag / dependency audit result and its rebuild plan; missing-check shortlist with commands; what you recorded in the
learned store; any framework issue found (file + line) for the owner.
