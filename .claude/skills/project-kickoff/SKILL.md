---
name: project-kickoff
description: Kick off a new CBflow project — gather the design and project details (name, technology, phases and exit plans, design hierarchy and top, release / workarea / race paths, library base tag, MMMC corners, tools and enabled flows, DFT / DV targets, owners and dates, per-block RTL / SDC / UPF), ask the user for anything missing, generate the full config set (global project config, PD / DFT / DV overlays, MMMC config, per-node scenarios, view definition, registry entry, workarea user configs per block and flow, project library tag) from a reference project, and validate that runs can launch (configs source, mmmc-manager validate, library-manager check, test-mode SYNTH smoke run). Use when the user asks to create / set up / kick off a new project, a new chip, or a new CBflow project structure.
---

# Project kickoff

Goal: a new project whose configs are **ready to launch runs**. You gather the
facts, the script writes the files. Read [reference.md](reference.md) first
(spec fields, what is generated, rules).

`$SK` = `.claude/skills/project-kickoff`, `$K` = `python3 $SK/scripts/kickoff.py`,
work files in the session scratch dir (not the repo).

## 1. Pick the reference and start the spec
The reference is an existing project on the same technology and tool vendor;
it supplies the defaults. Ask the user when more than one fits. Default for
open-source sky130: `opensky`.
```bash
$K template --like <ref> --name <new> --out <scratch>/spec.json
```

## 2. Ask for what is missing — never invent it
```bash
$K check --spec <scratch>/spec.json
```
- **ASK** lines are facts only the user knows: name, description, owner /
  contact / chip lead, top module, design hierarchy, workarea / release / race
  paths, library base tag, tapeout date, and each block's SYNTH inputs (RTL
  filelist, SDC, UPF). Ask for them in one batch. Use AskUserQuestion for
  choices (base tag, reference project, phases); ask in chat for free text (the
  hierarchy as a block tree, paths). Do not fill ASK items with guesses.
- **ASSUMED** lines came from the reference: technology, phases, phase exit
  plans per discipline, enabled flows, default tools, process (VT / track /
  metal stack), SDC modes, power nets, MMMC corners, DFT / DV targets, LSF. Show
  them as one compact summary and ask the user to confirm or change them.
- **INVALID** lines must be fixed before going on: unknown flow or exit, a tool
  without an overlay, an inconsistent hierarchy, paths inside the CBflow tree,
  a name that is taken, a missing input file, a combined (block-carrying) base tag.

Edit the spec with the answers. Repeat `check` until it reports
`0 to ask, 0 invalid`.

Library: the base tag holds the cells (stdcell / memory) and must exist. If
none fits, build one with the library-manager skill first. The project tag
(default `<NAME>_T1`) is created empty; blocks go into it after their first
releases.

## 3. Generate into a staging dir and review
```bash
$K generate --spec <scratch>/spec.json --stage <scratch>/stage
```
Show the user:
- the file list;
- the diff of the project config against the reference;
- every NOTE: input files still to supply for flows beyond SYNTH (TB, spec,
  waivers), and anything else to write by hand.

Nothing in the repo has changed yet.

## 4. Apply — only on the user's explicit yes
`apply` creates files in the repo (`global/`, `PD/`, `DFT/`, `DV/`,
`master_projects.json`), the workarea, the release / race dirs, the MMMC view
definition and the project library tag. It refuses to overwrite anything.
```bash
$K apply --stage <scratch>/stage
```
The list of everything it made is in `<stage>/APPLIED.json`. Use it to undo if
the user asks.

## 5. Validate
```bash
$K validate --project <new>          # [--smoke-block <b>] [--keep-smoke]
```
The checks:
- the project configs source cleanly;
- `cbflow flow project info`;
- `mmmc-manager validate` against the library tag;
- `library-manager check --lib_tag`;
- a test-mode SYNTH workspace + `run all` on a leaf block. The smoke run and
  its database are removed afterwards.

Fix every FAIL and re-run.

## 6. Hand over
Report:
- the project name and the files created (APPLIED.json);
- assumptions the user confirmed;
- open items (the NOTEs);
- the first real commands, for example:
  `cd <workarea>/<leaf> && cbflow workspace create --config uc_SYNTH_<tool>_<phase>.tcl && cd <run> && cbflow run all`.

Suggest next steps:
- write `project(signoff_chain,<phase>)` once the flows run;
- `schedule_config.tcl` exit dates;
- release disks (`project(release,disks)`);
- after the first block releases, `library-manager add --category block` into
  the project tag.

## Rules
- Never write into the repo before step 4's yes. Never overwrite an existing project.
- Config files are protected: change a generated file only through the spec plus a
  regenerate, or with the user's go-ahead.
- Paths for workarea / release / race must be absolute; release and race outside the
  CBflow tree; lib tags outside too.
- No hardcoded fallbacks: every value comes from the user or the confirmed reference.
