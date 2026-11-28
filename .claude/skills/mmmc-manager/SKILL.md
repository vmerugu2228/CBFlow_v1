---
name: mmmc-manager
description: Prepare and right-size the MMMC scenarios of a CBflow block on the open-source flow (sky130 opensky) — inventory what the project declares (mmmc_config PVT / RC corners / modes / views / scenario sets, mmmc_node_scenarios per-node setup / hold, the library tag's lib sets and child-block timing models, per-run overrides), analyze timing QoR across scenarios from STA / PNR runs and releases (setup / hold WNS · TNS · NVP, DRV, leakage / power per scenario; dominant, redundant and missing scenarios), propose STA validation runs for candidate critical corners, and recommend the scenario sets for PNR optimization, signoff STA and power. Use when the user asks which corners / scenarios / views to use, to prepare or review MMMC, to find the critical or worst corners, to analyze timing across corners, to add or drop scenarios, or why a scenario is missing or fails.
---

# MMMC scenarios (CBflow mmmc-manager)

You turn a project's MMMC declaration plus real timing results into a
justified scenario recommendation — or a clear list of what blocks one
(lib set missing from the tag, child block without a timing model).
**Everything that runs work is a `bin/cbflow` command; the scripts in
`scripts/` only read.** Never edit `mmmc_config.tcl`, `mmmc_node_scenarios.tcl`
or any framework config, and never run `mmmc-manager set-node | add-* | remove-* |
generate*` — those rewrite configs; show the commands, the user runs them.
Read [reference.md](reference.md) (files, keys, how scenarios reach each flow, pitfalls) first.

`$SK` = `.claude/skills/mmmc-manager`, `$CB` = repo root, `<work>` = `workarea/<block>/mmmc/<n>/`.

## 1. Inventory — what is declared, what the tag can time
```bash
$CB/bin/cbflow flow mmmc-manager show     --project <p>     # modes, PVT, RC corners, sets, node assignments
$CB/bin/cbflow flow mmmc-manager validate --project <p>     # names consistent (not: libs in the tag)
$CB/bin/cbflow flow mmmc-manager list-scenarios --set signoff --project <p>
python3 $SK/scripts/mmmc_inventory.py --project <p> --run <sta or pnr run> -o <work>/inventory.json
```
(`--design <b> --lib-tag <TAG>` instead of `--run` when there is no run yet.)
Report the declared signoff / setup / hold / power sets, the per-node
assignments, and every `checks` entry: **ERROR** = a view the flow will fail on
(lib set not in the tag, no memory map entry, child block without a model at a
signoff lib set); **WARN** = a run override nothing reads, a child model missing
for a non-signoff view, a mode without a setup / hold view; **INFO** = coverage
(a process corner never signed off, power view not typical, spare tag lib sets).

## 2. QoR across scenarios
```bash
python3 $SK/scripts/mmmc_qor.py <sta run> [<sta release> <pnr run> <pnr release>] \
    --inventory <work>/inventory.json -o <work>/qor.json      # PNR: --stage signoff|pro|route|cts_opt|cts|place
```
Show the table per source: setup / hold WNS · TNS · NVP, DRV, tran slack,
leakage / total power, and what each scenario limits. Call out
- the dominant setup and hold scenarios (and TNS / tran-slack / power owners);
- `REDUNDANT` scenarios (limit nothing; margin to the worst setup / hold);
- temperature inversion (cold slow view worse than hot) — keep the cold view;
- RC-corner spread (only measurable when one PVT is timed at several RC corners);
- `GAP` lines: declared signoff views not timed, process corners / the power
  view never timed, timed views outside the signoff set.
Older runs of the same block (other phases, a full-cartesian run) are extra evidence.

## 3. Recommend
```bash
python3 $SK/scripts/mmmc_recommend.py --qor <work>/qor.json [--qor <older qor.json>] \
    --inventory <work>/inventory.json -o <work>/recommend.json
```
Present: PNR setup / hold sets (dominant + within `--near` ns), signoff STA set
(declared + limiting — redundant views stay in signoff, they only leave PNR),
power views (typical for power analysis, worst total / leakage for EMIR),
the timing models a parent needs from this block's PNR `signoff` node, and the
validation candidates (runnable or BLOCKED + why). The `PROPOSAL` block is
text for the user; nothing is written.

## 4. Validate — only after the user approves
A new STA run on the same release, so the signoff run and its exit release stay
untouched. From `workarea/<block>/`, copy the STA run's `setup/user_config.tcl`
to `uc_STA_<phase>_mmmc<n>.tcl`, set a new `flow(run_name)`,
`flow(use_xterm) "false"`, and append the PROPOSAL's
`sta(mmmc,setup_scenarios)` / `sta(mmmc,hold_scenarios)` lines. Then:
```bash
$CB/bin/cbflow workspace create --config uc_STA_<phase>_mmmc<n>.tcl
cd <phase>_run_STA_<block>_<run_name>
$CB/bin/cbflow run bypass --stages release_data1     # never publish an exploration run
$CB/bin/cbflow run all
$CB/bin/cbflow run status --details
```
Re-run one scenario (after a fix, or a failed one):
`$CB/bin/cbflow run force --stages timing1:<scenario>` then `$CB/bin/cbflow run all`.
A failing scenario: `work/STA/timing1/<scenario>/run/<scenario>.log` (missing
lib set / child model / SPEF — the inventory ERRORs predict these).
Adding scenarios to an existing run (`setup/override_config.timing1.tcl`,
see reference.md) changes that run and its release — only on the user's explicit yes.

Then repeat step 2 on the new run (+ the old one as `--qor` history) and step 3.

## 5. Hand over
Final table (scenario × setup / hold WNS · TNS, DRV, power, limits), the
recommended sets with one-line reasons, BLOCKED candidates and what unblocks
them (child signoff covering the lib set + `library-manager` tag refresh), and
the PROPOSAL snippets. Applying them is the user's call:
`cbflow flow mmmc-manager set-node --node <n> --setup "…" --hold "…"` for
`mmmc_node_scenarios.tcl`, the scenario sets in `mmmc_config.tcl` by hand
(then `mmmc-manager validate`), or a one-run override (reference.md).
