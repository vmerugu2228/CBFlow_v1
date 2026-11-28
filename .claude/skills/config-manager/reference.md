# config-manager reference

## Cascade (what `files` / `where` / `show` walk, in order)
1. `global/config/project/<p>/v1.0.0/<p>_config.tcl`: identity, hierarchy, phases, exits.
2. `<DISC>/config/project/<p>/v1.0.0/<p>_<disc>_config.tcl`: discipline overlays
   (PD: workarea, release, LSF, lib root / tag).
3. `global/config/tech/<tech>/v1.0.0/tech_config.tcl`, which sources the library
   tag's `lib_config.tcl`.
4. `global/config/flow/v1.0.0/flow_registry.tcl`: flow types, disciplines,
   framework release / dashboard defaults.
5. `<DISC>/config/flow/v1.0.0/flow_config.tcl` (+ PD `release_config.tcl`,
   `lsf_config.tcl`, …).
6. `<DISC>/config/flow/v1.0.0/node_configs/<FLOW>_config.tcl` +
   `<FLOW>_<tool>_config.tcl`.
7. `global/config/project/<p>/v1.0.0/mmmc_config.tcl` (+ `mmmc_node_scenarios.tcl`).
8. Run: `<run>/setup/user_config.tcl`, then `override_config.tcl` → `.<stage>` →
   `.<branch>` → `.<node>`.

`global/config/exit/v1.0.0/*` holds the exit milestones (checklists, waivers).

The last writer wins, except keys guarded with `if {![info exists …]}`, where the
first writer wins.

**What the tools read:**
- `where` reads `set` statements and `array set <arr> { key value … }` blocks.
- `show` sources the cascade the way a run does: `flow(type)` is set, and an `exit`
  inside a config is caught. It reports each file that changed the value.

## Scopes and owners (`set --apply`)
| Scope | Files | May apply |
|---|---|---|
| project-global | `global/config/project/<p>/**` | chip lead |
| project-PD / project-DFT | `PD|DFT/config/project/<p>/**` | backend owner, chip lead |
| project-RTL | `RTL/config/project/<p>/**` | frontend owner, chip lead |
| project-DV | `DV/config/project/<p>/**` | verification owner, chip lead |
| framework | `<DISC>/config/flow/**` (flow / node configs) | with `--framework` (the user's explicit go-ahead; affects every project) |
| tech | `global/config/tech/**` | with `--framework` |
| exit | `global/config/exit/**` | with `--framework` |
| registry | `global/config/flow/**`, `master_projects.json` | with `--framework` |
| run | `<run>/setup/*.tcl` | the run owner (RACE `run_info.owner`) |

**Where owners come from:** `global/config/master_projects.json`. Each project
has `chip_lead` and `flow_owners.{frontend, backend, verification}`, with logins
compared to `$USER`. An owner of `NA` / `Not specified` falls back to the chip
lead. A project can name owners explicitly:
`"config_owners": {"global": ["login"], "PD": ["login", …], …}`.

Owners stored as display names instead of logins (e.g. `india`) make the project
read-only for everyone. Fix the registry entry (chip lead) to unlock it.

**Restricted variables:** `PD/config/flow/v1.0.0/edit_restricted_config.tcl`
(flow types, phases, tech identity, supported tools, …). These need
`--restricted` as well.

## Safety
| Step | Behaviour |
|---|---|
| backup | `<dir>/backup/<file>.<YYYYmmdd-HHMMSS>.bak` (the existing backup convention) |
| edit | only the named statement is rewritten (braced / quoted / bare value, multi-line OK); `--add` appends a new one |
| check | the file must source alone; for project configs, the project cascade (project + overlays + tech) must source too |
| revert | on a failed check the backup is restored and the command errors |
| log | `<dir>/backup/CHANGELOG.jsonl`: at, user, file, key, old, new, reason, backup |

## Values
Write values as Tcl, exactly as they should appear: `'"OSS4"'`, `'{a b c}'`,
`0.25`, `'[list x y]'`. The shell quotes are the outer layer.

## Config principles (CLAUDE.md)
- No hardcoded defaults and no fallbacks: a missing mandatory value is an error.
  Don't "fix" an error by adding a default to a framework file.
- One variable lives in one place: before adding a key, `where` it.
- Configs hold data only, no procs.
