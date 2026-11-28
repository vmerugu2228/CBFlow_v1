---
name: timing-eco
description: Close setup / hold / max-transition violations of a routed CBflow block with a timing ECO on the open-source flow (OpenROAD / OpenSTA, sky130 opensky). Use when the user asks to fix timing, do a timing ECO, close STA violations, or fix setup / hold after an STA run. Starts from an STA run directory, proposes a minimal change list (resize, buffer, hold delay cells), runs it through the CBflow ECO flow and signoff STA, and accepts or rejects it against a no-regression gate.
---

# Timing ECO (open-source CBflow)

You turn an STA run with violations into a released, verified ECO — or a clear
statement that ECO is the wrong tool. **Everything that creates or runs work is
a `bin/cbflow` command** (`workspace create`, `run all`, `run status`,
`run retrace`). The scripts in `scripts/` only read reports. Never edit
framework configs; per-run settings go in the run's `uc_*.tcl`.

`$SK` = this skill's directory (`.claude/skills/timing-eco`), `$CB` = repo root
(`bin/cbflow`). Read [reference.md](reference.md) for the change-file commands,
the sky130 cell families and the safety rails before proposing fixes.

## The loop

### 1. Ingest — from the STA run
The user names a block / exit or an STA run dir (`workarea/<block>/<phase>_run_STA_<block>_<run>`).
The STA run's `setup/user_config.tcl` + `setup/resolved_inputs.tcl` say which
release it timed — the ECO must start from exactly that release.

```bash
python3 $SK/scripts/timing_summary.py <sta_run_dir> --paths 0 -o <work>/before.json
```
Report to the user: per-scenario setup / hold WNS · TNS · NVP and DRV counts,
the worst paths (start → end, the slow stages), and `source.release_tag` /
`release_dir` (e.g. `PRO_EXIT` → `test_releases/P1/ai_subsys/PNR/PRO_EXIT`).
Keep `<work>` = `workarea/<block>/eco/<tag>/` (the change files and JSONs live there).

### 2. Classify — is this an ECO?
- **Local**: a handful of endpoints, slow stages you can name (a `_1` cell
  driving far, a long wire, a missing hold margin) → ECO.
- **Systemic**: hundreds of endpoints, most of the clock period in a fixed
  cost (a macro's library setup time, a clock-period / constraint problem,
  >~20 % of the period short), or every path through the same macro pin with
  little logic → **stop**; say why and recommend the PNR / SYNTH / constraint
  change instead. Do not pile buffers on a systemic problem.
- Hold violations in FF corners after a setup ECO, or DRV (max_tran) counts,
  are part of the same decision.

### 3. Propose — minimal, under the caps
```bash
python3 $SK/scripts/candidate_fixes.py <work>/before.json -o <work>/candidates.json
```
It lists the legal options per violating path (upsize in the family, buffer a
high-fanout or slow net, hold delay cell at the capture pin), already filtered
by the post-route dont_use list. Pick the **smallest set** that should clear
the worst paths: prefer one fix that sits on many violating paths (`cells` in
before.json: `paths` count) over one per path; upsize before buffering;
never touch clock-tree cells or macros. Stay within the caps
(reference.md). Write `<work>/eco<n>_changes.tcl` — one command per line, a
`#` comment above each group saying which paths it targets and why.

**Show the change list and the rationale to the user and wait for approval
before running anything.**

### 4. Run — cbflow only
Write `workarea/<block>/uc_ECO_<phase>_<exit>_ECO<n>.tcl` from the template in
reference.md (project / phase / lib tag copied from the STA run's
user_config; `eco(input,release_tag)` = the STA's release tag for ECO1, the
last accepted `<EXIT>_ECO<k>` after that; `project(release,tag)` =
`<EXIT>_ECO<n>`), then from `workarea/<block>/`:
```bash
$CB/bin/cbflow workspace create --config uc_ECO_<phase>_<exit>_ECO<n>.tcl
cd <phase>_run_ECO_<block>_<run> && $CB/bin/cbflow run all
```
eco1 fails if the change file breaks a rule (unknown command, cap, dont_use,
missing instance) or the re-route leaves DRC — read `work/ECO/eco1/run/eco1_run.log`
and `reports/eco_changes.rpt`, fix the change file, `cbflow run retrace --from eco1`,
`cbflow run all`.

Then signoff STA on the ECO release — a copy of the STA run's user_config with
`flow(run_name)` new and `sta(input,release_tag) "<EXIT>_ECO<n>"`:
```bash
$CB/bin/cbflow workspace create --config uc_STA_<phase>_<exit>_ECO<n>.tcl
cd <phase>_run_STA_<block>_<run> && $CB/bin/cbflow run all
```

### 5. Verify — the gate
```bash
python3 $SK/scripts/timing_summary.py <new sta run> --paths 0 -o <work>/after_eco<n>.json
python3 $SK/scripts/compare_qor.py <work>/before.json <work>/after_eco<n>.json -o <work>/compare_eco<n>.json
```
Exit 0 = ACCEPT, 2 = REJECT (any WNS / TNS worse, NVP or DRV up, a new
violating endpoint), 3 = ACCEPT_UNVERIFIED (no regression seen, but the path
lists are cut below a scenario's NVP: rebuild with `--paths 0`; if the STA
reports themselves are cut, the user decides — never treat 3 as ACCEPT silently). Also required for ACCEPT:
- eco1 `Post-ECO detailed-route DRC violations: 0`, `eco_check_placement.rpt` clean;
- eco1 `eco_changes.rpt`: `Floating signal inputs : a -> a` (eco1 fails if it rises);
- LEC of the ECO netlist (reference.md) — read the verdict in
  `work/LEC/compare1/outputs/lec.rpt`: `result EQUIVALENT`. The LEC run itself
  can PASS with `result NOT EQUIVALENT` (`lec(oss,fail_on_violations)` false), so
  never accept on the run status alone.
A REJECT never becomes the starting point of the next iteration.

### 6. Iterate / report
Up to 3 iterations (ECO1..ECO3) unless the user asks for more; each starts
from the last ACCEPTed tag and its STA. Keep `<work>/eco_log.md`: per
iteration the source tag, the change file, the rationale, the verdict and the
before → after table. Finish with that table and the release dir
(`test_releases/<phase>/<block>/ECO/<EXIT>_ECO<n>`). Making the ECO the exit's
release (`cbflow run release … --tag <EXIT> --override`) or publishing is the
user's decision — offer it, do not do it.
