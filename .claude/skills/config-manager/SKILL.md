---
name: config-manager
description: Find, explain and change CBflow configs for a project and the disciplines the user works in (PD / DFT / DV / RTL / project-global) — where a key is set across the config cascade and which setting wins, the effective value for a flow / tool, text search, and safe edits with an ownership gate (only the project's owners edit its project configs; framework / tech / exit configs need explicit approval), restricted-variable protection, backups, a syntax + cascade check with automatic revert, and a change log. Use when the user asks to find / show / explain / change / update / add a config variable, asks why a value is what it is, or wants config history.
---

# Config manager

`C=.claude/skills/config-manager/scripts/cfgm.py` (executable; call `$C …` from
the repo root). Read [reference.md](reference.md) for the scopes, the owner
rules and the cascade.

## 1. Ask first (AskUserQuestion)
- **Which disciplines?** PD, DFT, DV, RTL, and/or global (project-wide). Search
  and edit only those (`--disc …`).
- **Which project?** And, when it matters, which flow / tool (for effective
  values) and which run (for run-level overrides).
- **For a change:** the key, the new value, and the reason. The reason is
  required and goes into the change log.

## 2. Find / explain
```bash
$C where  --project <p> --key '<arr>(<key>)' --disc <D…> [--flow F --tool T]   # every setter, the winner
$C show   --project <p> --key '<arr>(<key>)' --flow F [--tool T]               # effective value + who set it
$C grep   --project <p> --text '<regex>' --disc <D…>
$C files  --project <p> --disc <D…> [--flow F]                                 # the cascade, in order
```
Explain the answer in cascade terms:
- the file that wins;
- whether a run's `user_config.tcl` or `override_config*.tcl` changes it;
- whether a guard (`if {![info exists …]}`) means an earlier setter wins.

For run-level values, read `<run>/setup/user_config.tcl` and
`override_config[.<stage>|.<branch>|.<node>].tcl` (last writer wins; no
flow-name level).

## 3. Change — the right file, then the gate
1. **Pick the narrowest scope that does the job:**
   - a run override (`<run>/setup/override_config[.<node>].tcl`) for one run;
   - the user config (`workarea/<b>/uc_*.tcl`) for one block's runs;
   - the project discipline overlay for every run of the project;
   - framework / tech only for a real framework change.

   Say which you chose and why.
2. **Dry run:** `$C set --file <cfg> --key '<arr>(<key>)' --value '<tcl value>' --reason "<why>"`.
   Show the before → after.
3. **Apply only on the user's yes:** add `--apply`. The script enforces the
   rest; never work around a refusal:
   - **project configs:** only the scope's owners may apply (`$C owners --project <p>`);
   - **framework / tech / exit / registry:** needs `--framework`, given only when
     the user explicitly approves a change that affects every project;
   - **edit-restricted variables:** need `--restricted` and the user's explicit yes;
   - **run configs:** only the run owner may apply;
   - **checks:** the file must source, and for project configs so must the
     project cascade. A failure reverts the change.
4. **After a change:** re-run the matching validation:
   - `mmmc-manager validate` for MMMC keys;
   - `library-manager check` for library / tag keys;
   - `cbflow flow checklist list-checks` for exit configs;
   - `cbflow test --static` for framework configs.

## 4. Refused?
- **Not an owner:** say who owns the scope (`$C owners`) and offer a ready-to-send
  change request: file, key, old → new, reason. **Never edit the file another way**
  (Edit / sed) to get around the gate.

## 5. History
`$C history --project <p> [--file <part of path>]` lists every config-manager
change: who, when, old → new, reason, and the backup file to restore from.
