---
name: flow-manager
description: Maintain CBflow framework (flow) releases — see which flow release each project runs and whether it is current, detect released components edited since release (drift) and what a new release would capture (stale), cut releases, patch one component (e.g. a tool's command files) in a new version and retag a project to a release that carries it, watch for newer releases and framework commits, and surface flow issues (failing jobs grouped by flow / stage / error, command-file gaps). Use when the user asks about flow / framework releases or versions, tagging a project to a flow release, updating part of the flow for a project, release drift, new releases, or recurring flow failures.
---

# Flow releases (CBflow framework)

`F=.claude/skills/flow-manager/scripts/flowm.py` (executable; call it from the
repo root). Read [reference.md](reference.md) for the release model, how a run
picks its versions, and the patch / retag recipe.

## 1. Where things stand
```bash
$F status                 # releases, current, each project's project(cbflow_release)
$F drift  [--release vX]  # released components edited since the release (hash; git history for old releases)
$F stale  [--release vX]  # components on disk that a new release would add / move
$F watch  --project <p>   # newer releases + framework commits since the project's release
```
Explain the result in plain words:
- which projects run which release;
- whether that release still describes what runs (drift);
- what has changed since.

## 2. Flow issues
`$F issues [--project <p>] [--days N] [--audit]` lists failing jobs from the RACE
databases, grouped by flow / stage / first error line, plus the command-file
audit (cmd-manager). For each group:
- decide whether it's a **flow** issue (command file, handler, utility, tool
  config) or a **design / run** issue (inputs, constraints, QoR);
- send flow issues to the fix: the cmd-manager or config-manager skill, or a code
  fix. For design / run issues, point to the run and the skill that owns it
  (rtl2gds, timing-eco, drc-fix, checklist).

## 3. Cut a release
```bash
cbflow flow release create --type patch|minor|major --desc "<what changed>"   # or --version vX.Y.Z
```
- It captures every versioned component of PD / DFT / DV / RTL / global, each
  with a content hash.
- It doesn't lock or commit unless asked. Add `--lock` only when the user wants
  released versions permanently read-only. **Locking is irreversible, and the
  framework develops in place in its v1.0.0 directories.** Add `--git` to commit
  the release directory.
- Before cutting: `$F stale` to show what goes in, `$F drift` on the previous
  release, and `bin/cbflow test --static` plus the e2e for the flows that changed.
- Get the user's yes, then `cbflow flow release set-current --version vX` if it
  should become the default.

## 4. Patch part of the flow for a project, then retag
Example: a fixed PNR open-source command file for one project only.
1. Branch the component: `$F patch --component cmds.PNR.opensource.openroad --to v1.0.1`
   (dry run; `--apply` on the user's yes). It copies the current version dir. The
   released one stays as released, and projects on the old release keep it.
2. Edit the files in the new version directory: cmd-manager skill (lint), or
   config-manager for configs.
3. Test: e2e for the flow, plus a sandbox run (rtl2gds `--release-path`). Pin the
   test run with `set <arr>(tool,version) "v1.0.1"` in its user config.
4. Cut the release (step 3). It captures v1.0.1 as the newest version of that
   component, as `CMDS_<FLOW>_<VENDOR>_<TOOL>_VERSION` in `release_versions.tcl`.
5. Retag the project: `$F pin --project <p> --release vX --reason "…"` is a dry run;
   `--apply` sets `project(cbflow_release)` through config-manager, so the ownership
   gate (chip lead), backup and log apply.
6. New runs of the project get the pin. Workspace create appends
   `<arr>(tool,version)` to the run's user config. Existing runs keep their
   environment; retrace or recreate them to pick it up.

## Rules
- **Approvals:** releases, patches and pins are framework / project changes. Get
  the user's explicit yes for each. A project pin goes through config-manager
  (owners only).
- **Drift:** never "fix" drift by editing a released version in place. Branch a
  new version instead.
- **No auto git:** nothing commits or pushes unless the user asks (`--git`).
