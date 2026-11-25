# Floorplan — reference

## FP keys (PD/config/flow/v1.0.0/node_configs/FP_openroad_config.tcl; per run in the uc)
| Key | Meaning |
|---|---|
| `fp(oss,fp,die_area)` `{x0 y0 x1 y1}` | fixed die (µm); core = die − `core_margin` |
| `fp(oss,fp,core_utilization)` / `aspect_ratio` | sizing when no die is given |
| `fp(oss,fp,core_margin)` | 10 µm (snapped: x 22 sites = 10.12, y 4 rows = 10.88) |
| `fp(oss,fp,macro_channel)` | 60 µm between macros |
| `fp(oss,macro,halo)` | 10 µm keep-out around macros (also tapcell halo) |
| `fp(oss,macro,placement)` | `{inst x y orient …}` explicit · `row` · "" = `rtl_macro_placer -min_channel_size <halo>` |
| `fp(oss,macro,blockage_sides)` | hard placement blockages from the macro to the core edge on those sides |
| `fp(oss,pins,constraints)` | `{{region pin_glob …} …}` — each group together in its region (`top:100-400`, `left:*`) |
| `fp(oss,pins,region)` | region for pins no group took ("" = all edges) |
| `fp(oss,probe,enable)` / `density` | probe1 step (quick GPL + GRT, nothing saved) / its GPL density (0.6) |
| `project(pdn,enable)` | false = no grid (bring-up) |

## Rules (fp_check.py)
- Macros fully in the core; origin x on the **site grid** (0.46) and y on the **row grid** (2.72) from the core origin.
- **DL2 children** (blocks with children) at y = k × rail pitch (54.4 µm = strap pitch / 2 × rail nets) and **R0** only (`oss_bridge_rails`).
- No overlaps; facing macros ≥ `macro_channel` apart; abut the core edge on the sides away from the logic.
- **Pins face the logic:** the macro side carrying most signal pins (LEF, after orientation) must point into the core with ≥ halo of room, never at the die edge. Orientation R0 / MX / MY / R180 only.
- **Blockages** on the declared sides (rows beside / under a macro would otherwise take std cells the macro's pins cannot reach).
- **Rows beside the macro:** keep a ≥ 2×halo strip next to the macro row so the rows (and global placement's core) span the macro height.
- **IO pins** on the die edge, on their group's side; ≈ 2 met2/met3 tracks per pin (1.36 µm) of edge.

## sky130 hd numbers
site 0.46 × row 2.72 µm, manufacturing grid 0.005 µm. Routing (direction, pitch µm):
met1 H 0.34 · met2 V 0.46 · met3 H 0.68 · met4 V 0.92 · met5 H 3.4.
Straps: met4 V 1.6 µm / 27.14 pitch, met5 H 1.6 / 27.2. met1 rails 0.48 per row.
Signal layers per level (`oss_signal_layers`): leaf → up to met4; middle → up to met4; top → met1..met5.

## Analytic estimate (fp_estimate.py)
- std-cell wirelength ≈ k · cells · √(logic area / cells), k = 1.5 (calibrate);
- macro-pin nets: pins × (halo + band/2) across the band + pins × span/4 along it;
- supply per direction = Σ layers area / pitch × usable (met1 0.5, strap layers 1 − width/pitch, others 0.9).
**Calibration (ai_subsys P1, 841 mac_array pins):** the model's % is not the global
router's average usage (model 48 % H where GRT averaged 2.2 %), but its band sizing at the
50 % target landed at the clean edge: band 155 µm → overflow 0; minimum band 54 µm →
overflow 6834 (local, at the macro-pin edge); hand-made 500 µm → 0. Use the model to size
and rank; the probe decides; probe one candidate below the model's band to find the edge.

## Probe metrics (probe.rpt)
| Metric | Good |
|---|---|
| Total overflow | **0** (any overflow → grow / move) |
| Total routing usage | ≤ ~50 % at FP (PNR adds clock, buffers, detours) |
| Per-layer usage | no single layer ≫ the others (≤ ~70 %) |
| Placement overflow | ≤ 0.1 (GPL converged) |
Results so far: gcd P2 (2 SRAMs) usage 4.2 %, overflow 26 at util 10; ai_subsys P1 band
54 µm → 7.6 %, overflow 6834; band 155 µm → 2.2 %, 0 (−7.8 % die vs hand-made); hand-made
band 500 µm → 1.1 %, 0. Low average usage with overflow = a local hotspot (macro pin edge).

## uc template (probe candidate)
```tcl
# copy of workarea/<block>/uc_FP_openroad_<P>.tcl, then:
set flow(run_name)               "<p>_fp<cand>"
set flow(use_xterm)              "false"
set fp(oss,fp,die_area)          {0 0 <x1> <y1>}
set fp(oss,macro,placement)      {<inst> <x> <y> <orient> ...}
set fp(oss,macro,blockage_sides) {<sides>}
set fp(oss,pins,constraints)     {<from fp_pins.py>}
set fp(oss,probe,enable)         true
```
The chosen candidate's keys go into the block's `uc_FP_openroad_<P>.tcl` for the real
FP run (probe off) — that edit, the FP_EXIT release and publishing are the user's call.
