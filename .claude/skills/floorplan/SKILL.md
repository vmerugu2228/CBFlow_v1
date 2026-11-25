---
name: floorplan
description: Floorplan a CBflow block on the open-source flow (sky130 opensky) — area estimation and die sizing / resizing, rule-driven macro placement (corner / edge, halo, channels, pins facing the logic, rail pitch for DL2 children), port placement, partitioning advice, routing-track and early congestion estimation. Use when the user asks to floorplan a block, size or resize a die, place macros or ports, decide partitioning, or estimate congestion / tracks before committing to an area. Proposes candidates from the SYNTH release + library tag, probes the shortlist with a quick global placement + global route, checks every floorplan rule, and recommends the smallest clean floorplan.
---

# Floorplan (open-source CBflow)

You turn a synthesized block into a checked, probed floorplan proposal — or a
clear statement of what blocks it (missing child LEF, pins that cannot fit).
**Everything that creates or runs work is a `bin/cbflow` command**; the
scripts in `scripts/` only read. Per-run settings go in the run's `uc_FP_*.tcl`;
never edit framework configs or `project(design_hierarchy)`.
Read [reference.md](reference.md) (rules, numbers, keys, probe metrics) first.

`$SK` = `.claude/skills/floorplan`, `$CB` = repo root, `<work>` = `workarea/<block>/fp/<n>/`.

## 1. Ingest
```bash
python3 $SK/scripts/fp_inputs.py <block> --phase <P> -o <work>/inputs.json
```
Reads the block's `uc_FP_openroad_<P>.tcl` → SYNTH release (std-cell area,
cells, port bits), the library tag (child-block LEFs: size + which edge their
pins are on; memory LEFs), the hierarchy, the tech (site / row / grid, layer
directions + pitches, straps, rail pitch) and the FP defaults. Tell the user
the std-cell area, every hard macro (size, pin side, DL2 or not) and the IO count.
A child without a LEF in the tag → stop: the child must be released and added
to the tag (`cbflow flow library-manager add …`) first.

## 2. Partitioning (when asked, or when a child is tiny / dominant)
```bash
python3 $SK/scripts/fp_partition.py <work>/inputs.json --rtl inputs/opensky/<b>/[<P>/]<b>.f
```
Advice only (flatten candidates, keep-hard, RTL modules reused or register
heavy). The hierarchy is the user's decision.

## 3. Estimate a shortlist
```bash
python3 $SK/scripts/fp_estimate.py <work>/inputs.json -o <work>/estimate.json
```
Candidates = utilization × aspect × macro arrangement (`bottom_row` |
`left_column`), on the grids, macro pins facing the logic, the logic band
grown until the analytic H / V track use is within `--target` (50 %).
The analytic model is first order: its % is not the router's average usage,
but its band sizing tracks the clean edge (reference.md calibration) — it
sizes and ranks; the probe decides. Shortlist 2–3: the
recommended candidate, one smaller (`--target` higher or `--min-band-rows`
lower) and, when a hand-made floorplan exists, that one for comparison.
Ports per candidate:
```bash
python3 $SK/scripts/fp_pins.py <work>/inputs.json --die "<die>" --arrangement <arr> [--parent-def <parent FP DEF>]
```
Show the table (die, utilization, band, H/V %, macro placement, blockage
sides, pin sides) and **wait for the user's approval** before running.

## 4. Probe — cbflow only
Per candidate a uc from the block's `uc_FP_openroad_<P>.tcl` (template in
reference.md) with a new `flow(run_name)`, `fp(oss,fp,die_area)`,
`fp(oss,macro,placement)`, `fp(oss,macro,blockage_sides)`,
`fp(oss,pins,constraints)` and `fp(oss,probe,enable) true`, then
```bash
cd workarea/<block> && $CB/bin/cbflow workspace create --config uc_FP_<P>_<cand>.tcl
cd <P>_run_FP_<block>_<run> && $CB/bin/cbflow run all
```
`probe1` (off the release chain) writes `work/FP/probe1/reports/probe.rpt`:
per-layer usage / overflow, total overflow, wirelength — minutes, nothing saved.

## 5. Check and compare
```bash
python3 $SK/scripts/compare_fp.py <run> [<run> ...] --inputs <work>/inputs.json
```
Runs `fp_check.py` on each (macros in core, site / row grid, DL2 on the rail
pitch, no overlaps, channels, pins facing the logic, blockages on the
declared sides, IO pins on their constraint side, the flow's own floorplan
rules) and recommends the smallest die with **0 global-route overflow and
all rules PASS**.

## 6. Resize
Overflow 0 and lots of headroom → probe a smaller candidate; overflow > 0 →
grow the band / die (or move macros). Up to 3 rounds. Low average usage with overflow means a local
hotspot (usually the macro-pin edge) — grow the band there, not the die
everywhere.

## 7. Report
The chosen uc settings, the comparison table, the rule check, and what the
next step is (PNR from this floorplan). Releasing FP_EXIT
(`cbflow run release`, publish) is the user's call; the probe runs are
exploration only.
