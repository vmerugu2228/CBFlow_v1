# rtl2gds reference

## Step graph (per block; children before parents)
```
[children's LIB] -> SYNTH -> FP -> PNR -> STA ┐
                                      -> PV  ├-> (MTO clone) -> CKL
                                      -> LEC ┘
                     (block with a planned parent:)  PNR + signoff -> LOCK -> LIB
```
| Step | What | Passes when |
|---|---|---|
| SYNTH | yosys; releases `<PH>_SYNTH_<run>`; RTL from the phase's `RTL_LINT/LINT_SIGNOFF/rtl/<b>.f` when released, else the template's filelist | `result=PASS` and RELEASE_COMPLETE newer than the step start |
| FP | OpenROAD floorplan from the SYNTH tag; releases FP_EXIT | same |
| PNR | OpenROAD from the SYNTH tag + `def_file_release_tag FP_EXIT`; releases the phase's exits up to `min(target, BTO)` (`pnr_exit`) | same, for `pnr_exit` |
| STA / PV / LEC | signoff on the `pnr_exit` release (LEC golden = the SYNTH tag) | same; the verdict is read from the release's `metrics.rpt` Status (recorded, not fatal) |
| MTO | `run release --clone-from BTO --tag MTO` when the target is MTO | clone OK |
| CKL | `cbflow flow checklist status --run-dir <PNR run>` (milestone auto-detected) | always recorded, never fatal |
| LOCK | `cbflow flow release lock --exit <pnr_exit>`, so the parent's input can't change | lock set (or already set) |
| LIB | new project tag for the parent's level (`project-tag create --base <B> [--from <previous project tag>]`), then `library-manager add --category block --path <release>/<PH>/<b>/PNR/<pnr_exit>` (`--pv-pending` without a PV release) | add OK |

**Library tags per level:**
- Level 1 (the leaves) uses `--lib-tag`.
- Level n+1 uses `<PROJ>_<PH>_<RUN>_L<n+1>`. That is the previous project tag,
  plus the releases of the level-n blocks.
- Parents' user configs name the tag of their level.

**Failure handling:**
- A failed step makes its dependents `blocked`; independent blocks continue.
- `--resume` reruns failed and blocked steps. A flow step whose run directory
  exists is retraced from its first node (`cbflow run retrace`) and run again.

## User config derivation (`<plan>/ucs/<block>/uc_<FLOW>_<tool>_<PH>_<run>.tcl`)
**Template, in order:**
1. `workarea/<b>/uc_<FLOW>[_<tool>|_signoff]_<PH>.tcl` (tuned for the phase);
2. `workarea/<b>/uc_<FLOW>_<tool>.tcl` / `uc_<FLOW>_signoff.tcl` (generic);
3. the generic template of a block of the same kind (leaf / parent), renamed
   (NOTE).

**Set in every config:**
- `flow(design_name)`, `flow(run_name)`;
- `project(phase)`, `project(release,phase)`;
- `project(lib_config_tag)` (the level's tag);
- `flow(test_mode) false`.

Input tags are rewritten per flow: earlier `*release_tag` keys are removed, then
the plan's tags are set. `--release-path` (sandbox) also sets
`project(release,path)`.

Run directory: `workarea/<b>/<PH>_run_<FLOW>_<b>_<run>`.

## Files
| Path | What |
|---|---|
| `<plan>/plan.json` | steps, dependencies, configs, tags |
| `<plan>/state.json` | per step: status, start / end, message, verdict |
| `<plan>/events.txt` | one line per event (Monitor source) |
| `<plan>/logs/<b>_<FLOW>.log` | the commands and their output |

Default plan dir: `workarea/.rtl2gds/<PH>_<TAG>_<id>/`.

## Failure playbook
| Symptom | First look | Skill / action |
|---|---|---|
| workspace create fails | log: mandatory inputs, missing release tag, lib tag | fix the input tag / release the upstream; library-manager if a block view is missing |
| SYNTH fails | yosys log: syntax, missing module | spec2rtl / RTL owner; child module missing → library tag |
| FP fails / congestion | floorplan reports | floorplan skill (die size, macro placement, probe) |
| PNR fails in global route / detail route | `work/PNR/route*/` logs, congestion | floorplan skill (utilization), or density in the config |
| PNR passes, release missing | the release node log (exit order gate: earlier exits not released) | release the earlier exit first, or check `project(phase_exits)` |
| STA verdict FAIL | `release metrics.rpt`, `reports/sta/<scenario>/setup.rpt` | timing-eco skill; mmmc-manager skill for corner choice |
| PV verdict FAIL | DRC / LVS report in the PV release | drc-fix skill |
| LEC FAIL | LEC report | netlist mismatch: check that LEC golden = the SYNTH tag the PNR used |
| CKL BLOCKED | checklist status JSON | checklist skill (triage, fixes, waivers within policy) |
| LOCK fails | the exit is locked by someone else | ask the locker / chip lead |
| LIB fails | library-manager log (port mismatch, missing view) | library-manager skill (`port_compat.py`) |

## Rules
- Only the user's yes launches runs. Re-releasing a locked exit is refused by the
  framework: never unlock without the user.
- Use cbflow commands only (workspace create / run / release / library-manager
  / checklist). Don't edit framework or project config. Show proposed user-config
  changes and apply them only with the user's yes.
- A sandbox (`--release-path <scratch>`) is for trials: its releases and tags
  aren't the project's.
