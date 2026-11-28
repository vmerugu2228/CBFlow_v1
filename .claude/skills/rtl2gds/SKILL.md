---
name: rtl2gds
description: Take a CBflow project's blocks from RTL to signed-off, released GDS on the open-source flow — given the release tag to reach (PRO_EXIT, BTO, MTO …), plan the hierarchy bottom-up, generate each run's user config, launch SYNTH -> FP -> PNR -> signoff (STA / PV / LEC) for every block with parallelism, release each exit, run the exit checklist, lock each child's exit and roll its release into a new project library tag for its parent, and stream live progress. Calls the library-manager, checklist, mmmc-manager, floorplan, timing-eco and drc-fix skills when a step needs them. Use when the user asks to run the backend, RTL-to-GDS, implement / sign off / release blocks or the chip, or reach an exit milestone across the hierarchy.
---

# RTL to GDS (backend orchestration)

You ask for **the release tag**; the rest is derived. `scripts/r2g.py` plans,
launches and tracks the runs. You run the preflight, watch the run, diagnose
failures (with the right skill) and report. Read [reference.md](reference.md)
for the step graph, the user-config derivation and the failure playbook.

`R=.claude/skills/rtl2gds/scripts/r2g.py` (executable; call `$R …` from the repo root — works in zsh and bash).

## 1. Ask (one batch, AskUserQuestion)
- **Release tag** to reach: an exit of the phase, from `project(phase_exits)`
  (e.g. PRO_EXIT, BTO, MTO). This is the only thing you must ask.
- Confirm the defaults, and change only what the user changes:
  - phase: `project(current_phase)`, or the newest phase with RTL;
  - blocks: the whole hierarchy, or `--top <b>` for a subtree, or `--blocks …`;
  - signoff: STA, PV and LEC;
  - library tag of the bottom level: `project(lib_config_tag)`;
  - base tag for the new project tags: the current project tag's base;
  - lock child exits: yes;
  - publish to SmartGrid: no.

## 2. Preflight (fix or report before launching)
1. `$R plan --project <p> --phase <P> --exit <TAG> [...]`. It prints the levels,
   the library tag per level, and PROBLEM / NOTE lines.
   - PROBLEM must be resolved: a locked exit the plan would re-release (ask the
     user to unlock, or drop the block), a missing tag, a missing template.
   - NOTE: a config borrowed from another block. Show it.
2. Tags and dependencies: run the checklist skill's
   `scripts/tag_audit.py --project <p> --phase <P> --blocks <…>`. Stale or missing
   inputs that this plan doesn't rebuild must be fixed first (rebuild plan).
3. Library: the library-manager skill's
   `library-manager check --lib_tag <bottom tag>`, plus
   `scripts/port_compat.py` for parents whose children come from the tag.
4. MMMC: `mmmc-manager validate --tech <t> --project <p> --lib-tag <tag>`
   (mmmc-manager skill). Signoff corners must PASS.
5. Disk: `cbflow flow release disks --project <p>`; each block needs space for
   about 4 releases.

Show the plan (levels, steps, tags) and the preflight result. **Launch only on
the user's yes.**

## 3. Launch and stream
```bash
$R run --plan <plan dir> --max-parallel <n>        # Bash run_in_background
```
Then start a **Monitor** on `<plan dir>/events.txt`, filtered to
`DONE|FAILED|blocked|finished|Traceback`, so every step result reaches the user
live. Re-arm it when it expires. When the user asks for status, print
`$R board --plan <plan dir>`: the grid of blocks × stages with running time,
signoff verdicts and the last events. Relay each completed level briefly; don't
echo every line.

Runs use the project's launch settings (xterm / LSF). The run dashboard
(`cbflow run gui` in a run dir) and SmartGrid show detail.

## 4. On a failure (the dependents wait; other blocks continue)
Read the step's log (`<plan dir>/logs/<block>_<FLOW>.log`, then the run's
`work/<FLOW>/<node>/run/*.log`), find the first error, and pick the playbook in
reference.md:
- **FP** (congestion, die size, macros) → floorplan skill.
- **PNR** timing / DRV at PRO → timing-eco skill after signoff STA.
- **STA verdict FAIL** → timing-eco skill.
- **PV verdict FAIL** (DRC / LVS) → drc-fix skill.
- **Checklist BLOCKED** → checklist skill (triage, fixes, waivers within policy).
- **Library / tag** (missing block view, port mismatch) → library-manager skill.
- A config problem → propose the user-config change and show it.

After the fix: `$R run --plan <dir> --resume`. Done steps are kept; failed and
blocked steps run again.

**Gating is strict by default.** A signoff release whose verdict isn't PASS (or
has none), a checklist that is BLOCKED / FAIL, or issues deferred to this block
by its children all fail the step. Then the block's lock and its roll-up into the
parent's library wait. `--allow-signoff-fail` only records verdicts, for
exploration runs; never use it for a release others build on.

**Known issues the user accepts:** fix nothing, and use a gate waiver (ask the user
first; it needs their reason, an expiry and an approver):
```bash
bin/cbflow flow release waive --project P --phase PH --block B --exit X --check STA|PV|LEC|CHECKLIST \
    --reason "…" --expires YYYY-MM-DD [--defer-to <parent>]       # a lead requests
bin/cbflow flow release waive --project P --phase PH --block B --approve W<n>   # the chip lead approves
bin/cbflow flow release waivers --project P [--phase PH]                     # list; --deferred-to <parent>
```
- **BTO / MTO waivers must be deferred to a parent** (waiver policy). That
  parent's checklist step then fails while the issue is open.
- **Once the parent's own signoff covers it** (for example the parent's STA
  passes over the child's ports), its lead closes the item with
  `bin/cbflow flow release unwaive --id W<n> --reason "…"`.
- **Top-level blocks can't defer**, so nothing reaches tape-out silently.

After approval, `--resume`: the step passes as WAIVED and the board shows it.

## 5. Finish
1. **Report** (from the board + state.json):
   - per block: releases produced, signoff verdicts, checklist verdict;
   - locks set;
   - library tags created and what they contain;
   - anything waived or deferred.
2. **Verify:** run `tag_audit.py` again. The result must have no STALE / MISSING
   in the plan's blocks.
3. **Offer next steps:**
   - publish (`cbflow run release --from-run <run> --publish`);
   - `project-tag freeze` on the final tag;
   - the next exit.
