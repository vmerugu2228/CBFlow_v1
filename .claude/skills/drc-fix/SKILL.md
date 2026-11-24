---
name: drc-fix
description: Clear DRC violations of a routed CBflow block on the open-source flow (sky130 opensky) — signoff DRC from the PV run (KLayout / Magic on the released GDS) first, plus the OpenROAD detailed-route markers. Use when the user asks to fix DRC, clean up DRC, repair PV DRC errors, or get a cleaner DRC run. Reads the DRC report, classifies each violation by rule and hotspot, maps it to the nets / cells under it, proposes a local repair (re-route the nets involved, padding / small moves, routing-layer adjustment, antenna repair, stream-out min-area patches), runs it through the CBflow ECO flow and re-checks with PV.
---

# DRC fix (open-source CBflow)

You turn a DRC report into a released, re-checked repair — local fixes only:
the nets and cells at each hotspot, never a new floorplan or placement.
**Everything that creates or runs work is a `bin/cbflow` command**; the
scripts in `scripts/` only read reports. Never edit framework configs —
per-run settings go in the run's `uc_*.tcl`. Read [reference.md](reference.md)
(rule → fix table, ECO DRC commands, route scopes) before proposing.

`$SK` = `.claude/skills/drc-fix`, `$CB` = repo root.

## 1. Ingest — PV first
Signoff DRC is the PV run of the exit (`workarea/<block>/<phase>_run_PV_<block>_<run>`,
`work/PV/drc1/outputs/drc.rpt` = total, `reports/drc_klayout.lyrdb` = every
violation). The router's markers (`work/PNR/route1/reports/route_drc.rpt`, an
ECO's `eco_route_drc.rpt`) are the second source.
```bash
python3 $SK/scripts/drc_summary.py <pv_run_dir> -o <work>/drc_before.json
```
`source` = the release the PV checked (`release_dir`, tag in the run's
`setup/user_config.tcl`) — the repair starts from exactly that release.
Tell the user: total, per rule / layer, the hotspots (rule, count, box, the
nets and cells under it). `<work>` = `workarea/<block>/eco/drc<n>/`.

## 2. Classify — per rule (reference.md table)
- **Stream-out class** (min area `m2.6 / m3.6 / m4.4…` on via pads the router
  reports clean): fix = `eco(oss,export,min_area_layers)` for those GDS
  layers, route scope `none`. No routing change.
- **Routing class** (spacing, short, width, via enclosure, end-of-line on
  signal metal): fix = `eco_reroute_nets` of the hotspot's nets, route scope
  `nets`; a dense hotspot also gets `set_global_routing_layer_adjustment` on
  that layer or `set_placement_padding` / `eco_move_inst` for the cells there.
- **Antenna** (`*.ant*`, router antenna): `repair_antennas_after_grt`.
- **Child-block violations** — hotspots with `scope: child` (`cell` = the
  child): KLayout reports them inside the child, in the child's coordinates.
  The parent's ECO cannot change them; fix the child (its own drc-fix run on
  its PV), release it, update the library tag (`cbflow flow library-manager add`)
  and re-stream the parent. A child count that changes between two parent runs
  means the child's library-tag view changed — say so, don't chase it here.
- **Not ECO-fixable** — stop and say so: violations inside a hard macro / std
  cell (rule on a cell's own geometry),
  power-grid (special net) geometry (fix the PDN / FP), FEOL rules (diff,
  poly, nwell, tap) from placement (fix in PNR), or hundreds of violations
  spread everywhere (congestion — PNR density / floorplan).
Note the source database: releases made before 2026-11-25 carry wiring
re-encoded by OpenRCX — the router rejects it (DRT-1010), so routing-class
repairs on them need scope `full` (the whole block re-routed); newer
releases can use `nets`.

## 3. Propose
Write `<work>/drc<n>_changes.tcl` (one command per line, a `#` comment per
hotspot: rule, count, why this fix) and the uc settings (scope,
min_area_layers, padding). Stay within the caps (reference.md). **Show the
plan and wait for the user's approval.**

## 4. Run — cbflow only
`workarea/<block>/uc_ECO_<phase>_<exit>_DRC<n>.tcl` (template in reference.md;
`eco(oss,mode) "drc"`, `eco(input,release_tag)` = the PV's release tag,
`project(release,tag)` = `<EXIT>_ECO<n>`), then
```bash
$CB/bin/cbflow workspace create --config uc_ECO_<phase>_<exit>_DRC<n>.tcl
cd <phase>_run_ECO_<block>_<run> && $CB/bin/cbflow run all
```
then PV on the repaired release (the PV run's user_config with a new run name
and `pv(input,release_tag) "<EXIT>_ECO<n>"`): `workspace create` + `run all`.

## 5. Verify — the gate
```bash
python3 $SK/scripts/drc_summary.py <new pv run> -o <work>/drc_after<n>.json
python3 $SK/scripts/compare_drc.py <work>/drc_before.json <work>/drc_after<n>.json
```
ACCEPT needs: compare_drc exit 0 (the block's own geometry: total down, no
rule up, no new rule; child-cell violations are listed, not gated) **and**
the new PV run's LVS `Circuits match uniquely` **and**, when anything was
re-routed or moved, timing not regressed (STA on the release + timing-eco's
`compare_qor.py` against the STA of the source release). Router DRC of eco1
must be 0 (eco1 fails otherwise).

## 6. Iterate / report
Up to 3 iterations, each from the last ACCEPTed release. `<work>/drc_log.md`:
per iteration the rules / hotspots targeted, the fixes, the verdict and the
before → after table. Promoting the repair to the exit release or publishing
is the user's call.
