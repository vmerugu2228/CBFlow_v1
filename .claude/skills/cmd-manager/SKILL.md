---
name: cmd-manager
description: Audit, create, update and retire CBflow command files and subnode handlers (<DISC>/cmds/<FLOW>/<vendor>/<tool>/<version>/) — find node types of every flow / tool without a handler or command file, orphan handlers, and bootstrap / naming problems; scaffold a new stage's handler + command file from a sibling; edit command files safely (flow_proc hooks, lint after); retire unused ones reversibly; suggest what is missing. Use when the user asks to add / create / change / delete a command file or handler, add a stage or tool to a flow, check which command files are missing, or fix a command file.
---

# Command files (CBflow cmds)

`M=.claude/skills/cmd-manager/scripts/cmdm.py` (executable; call it from the
repo root). Read [reference.md](reference.md) for the layout, how the engine
finds handlers, and the command file rules.

## 1. Scope (ask)
- Which discipline(s) (PD / DFT / DV / RTL), flow(s) and tool(s)?
- What does the user want: an audit, a new stage, a change to a stage, a new
  tool, or retiring something?

## 2. Audit / suggest
```bash
$M audit [--disc PD …] [--flow F] [--tool T] [--json out.json]
$M list  --flow F --tool T            # stage -> node type -> handler / command present
$M lint  --file <cmd or handler>
```
Node types are resolved by sourcing the node config with the tool selected, as
the engine does. Report:
- **MISS:** a node type without a handler or command file. A run of that
  flow / tool fails at that stage.
- **orphan:** a handler that no stage uses.
- **lint:** bootstrap or naming problems.

Rank them: open-source and default tools first, then tools that projects use
(`project(default_tools)`), then scaffold-only commercial tools. Give the
`suggest` commands.

## 3. New stage / tool
1. **Node config first.** The engine runs only stages in the node config
   (`<FLOW>_config.tcl` / `<FLOW>_<tool>_config.tcl`: `stages`,
   `node_types,<stage>`, `stage_types`, dependencies). Propose that change with
   the config-manager skill. Framework config needs the user's yes.
2. **Scaffold (dry run):** `$M new --flow F --tool T --stage <node_type> [--from <sibling>]`.
   - The handler is copied from a sibling node type with the stage substituted.
   - The command file gets the standard 14-line bootstrap plus a flow_proc
     skeleton (load_design / <op> / report / save_design).
3. **Write** with `--apply --framework`, only after the user's explicit go-ahead.
   Command files are framework code used by every project.
4. **Fill the flow_procs** following the sibling stages of the same tool. Use the
   flow's helpers (e.g. `oss_utils.tcl` for open-source: `oss_get`,
   `oss_stage_out`, `oss_report`).
5. **Lint:** `$M lint`.
6. **Test:** `bin/cbflow test --e2e --flows F` (test mode), then a real run on a
   small block (the rtl2gds skill with `--release-path` for a sandbox).

## 4. Change an existing command file
- **Per project or block:** prefer a hook over editing the shared file, e.g.
  `flow_proc_prepend` / `flow_proc_append` in setup hooks (`PD/config/setup/`).
  A `flow_proc_replace` from setup.tcl is overwritten by the command file (see
  CLAUDE.md).
- **A real framework fix:** edit the command file with the user's yes, lint it,
  and run the e2e for the flow plus `bin/cbflow test --static`. Keep the 14-line
  bootstrap untouched.

## 5. Retire
`$M retire --flow F --tool T --stage <node_type>` is a dry run. It's refused
while a stage still uses the node type. `--apply --framework` moves the files to
`<dir>/.retired/<ts>/`, which is reversible. Remove the stage from the node config
first (config-manager).

## Rules
- Command files and handlers are framework code: no write without the user's
  explicit yes (`--framework`).
- Never bypass the bootstrap (run_dir → .run.cbflow.tcl → utils.tcl → FLOW_TYPE /
  STAGE_NAME / NODE_NAME → config.tcl / setup.tcl → setup_dirs). Config stays data;
  procs go in utils.
- No hardcoded tool paths or values in command files. Read them from the flow
  array (`cbflow_require <arr> <key>` / `oss_get`). A missing value is an error,
  not a default.
