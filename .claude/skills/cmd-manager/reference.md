# cmd-manager reference

## Layout and lookup
```
<DISC>/cmds/<FLOW>/<vendor>/<tool>/<version>/
    <node_type>_subnode_handler.tcl   run by the RACE engine per node: subnodes setup / run / validate / finish
    <node_type>_<tool>.tcl            the command file the handler names in cmd_file
    inputs_subnode_handler.tcl        shared by every input stage (stage_types "inputs")
```
- **DISC:** `flow(discipline,<FLOW>)` (global `flow_registry.tcl`). The engine
  searches that discipline's tree first.
- **vendor / version:** `<arr>(tool,vendor)` / `<arr>(tool,version)` in
  `node_configs/<FLOW>_<tool>_config.tcl`.
- **node type:** `<arr>(node_types,<stage>)`, else the stage name without its
  trailing digits. Custom nodes (`add-node`) keep their base type.
- **stages:** `<arr>(stages)` of the tool overlay when it declares one, else of
  the base node config. `cmdm.py` sources the configs to get them, so dynamic
  (foreach) stage lists resolve.

## Command file bootstrap (CLAUDE.md, 14 lines)
```tcl
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "<FLOW>"
set STAGE_NAME "<stage>"
set NODE_NAME [cbflow_node_name]

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME
```
After the bootstrap:
- `flow_proc <name> { … }` steps;
- `flow_exec_all` and `exit` at the end.

Open-source command files use `load_design`, `<op>`, `report` and `save_design`,
plus gates (`check_drc` / `check_lvs` / `verdict`). SYNTH uses `read_design` /
`synthesize` / `report` / `write_design` / `dft_insert`.

## Handler
A handler:
1. sources `handler_common.tcl` and `launch_utils.tcl`;
2. `handler_parse_args`, then `handler_load_configs $run_dir <FLOW>`;
3. sets `stage_name` and `cmd_file`;
4. calls `handler_dispatch <subnode> … $cmd_file $test_mode $tool`.

Dynamic-subnode stages (STA timing / extraction) call `handler_setup` /
`handler_validate` directly.

## Lint checks (`cmdm.py lint`)
| File | Check |
|---|---|
| command | braces balanced; the bootstrap lines present (`run_dir`, `.run.cbflow.tcl`, `utils.tcl`, `FLOW_TYPE`, `STAGE_NAME`, `NODE_NAME`, `config.tcl`, `setup.tcl`, `setup_dirs`); `FLOW_TYPE` = the path's flow; `STAGE_NAME` = the file's node type; `flow_exec_all` called when flow_procs are defined |
| handler | sources `handler_common.tcl`; calls `handler_dispatch` / `handler_setup` / `handler_validate`; `stage_name` = the file's node type; the `cmd_file` it names exists |

## Audit state (2026-11-28)
65 flow / tool pairs; 11 with missing files. All 11 are scaffold-only or
partial tools:
- ATPG pattern_signoff / timing_pattern_sim / zd_pattern_sim (fault command files
  missing; tessent / testmax handlers missing);
- POPT joules;
- RTL_CDC / RTL_RDC / RTL_LINT jaspergold;
- RTL_CDC / RTL_RDC spyglass;
- UPF_CHECK vc_lp / conformal_lp.

The open-source flows that run (SYNTH / FP / PNR / STA / PV / LEC / ECO / RTL /
DV / DFT) are complete.

## Tests
- `bin/cbflow test --static`: framework lints, hardcode scan, raw-read rules.
- `bin/cbflow test --e2e --flows <F>`: test-mode run of every flow fixture.
- A real run: the rtl2gds skill (sandbox `--release-path`) or `workspace create`
  + `run all`.
