# Extending CBflow

How-tos for the common extensions. Paths are relative to `$CBFLOW_ROOT`.
Architecture background: [System Design](../04-architecture/system-design.md).

Ground rules (enforced by review and by `cbflow test --static`):

- Configs are data only — no procs (procs go in `global/utils/utilities/v1.0.0/utils.tcl` or a discipline `utils/utilities/` file).
- No hardcoded defaults or fallbacks in code — read the value from config (`cbflow_require <arr> <key>`) and error when it is missing.
- One variable, one place. A flow uses one array (`pnr()`, `rtl_lint()`, …); tool settings live in the flow array, not a tool array.

---

## 1. Hooking a flow_proc (no command-file edit)

Put hooks in `<run>/setup/override_setup.tcl`, `override_setup.<stage>.tcl`
or `override_setup.<node>.tcl` (or the project / common setup trees under
`<DISC>/config/setup/`):

```tcl
# <run>/setup/override_setup.place.tcl
flow_proc_prepend global_detailed_place { handle_info "before placement" }
flow_proc_append  global_detailed_place { report_design_area }
```

`setup.tcl` is sourced **before** the command file defines its flow_procs, so
prepend / append always apply but a `flow_proc_replace` from a setup file is
overwritten by the command file's own definition. To change a body, add a new
command-file version (see [Contributing](contributing.md)).

## 2. Overriding tool selection

```tcl
# user_config.tcl
set pnr(tool,name)  "innovus"     ;# overlay PNR_innovus_config.tcl is loaded
set lec(tool,name)  "yosys"       ;# open-source LEC (not in project(default_tools))
```

`<FLOW>_config.tcl` loads the overlay of `default_tool`; after user_config,
`cbflow_reload_tool_overlay` (`tool_overlay.tcl`) loads the selected tool's
overlay and re-sources user_config, so the overlay's `tool,vendor`,
`tool,version`, `mandatory_outputs`, … follow the tool. The tool must be in the
flow's `supported_tools`.

## 3. Adding a discipline-owned subcommand

Example: `cbflow flow waiver-manager` owned by RTL.

1. Register the owner in `global/config/cli/discipline_commands.tcl` (one line, quoted value — the router greps it):
   ```tcl
   set cli(discipline,waiver-manager) "RTL"
   ```
2. Add it to the launcher's array in `RTL/bin/cbflow-rtl`:
   ```bash
   RTL_FLOW_SUBCOMMANDS=(waiver-manager)
   ```
3. Add the dispatch case in the same launcher (replace the "declared but no handler" error block):
   ```bash
   if [[ "${1:-}" == "flow" && $# -ge 2 ]] && _rtl_owns_flow_subcmd "$2"; then
       subcmd="$2"; shift 2
       case "$subcmd" in
           waiver-manager) exec python3 "$CBFLOW_RTL_DIR/utils/commands/waiver_manager_cmd.py" "$@" ;;
       esac
   fi
   ```
   (`PD/bin/cbflow-pd` is the reference.)
4. Drop the handler at `RTL/utils/commands/waiver_manager_cmd.py`.

`cbflow flow waiver-manager …` then reaches it: `global/bin/cbflow-flow` sends
any unknown `flow` subcommand to `$CBFLOW_ROOT/<DISC>/bin/cbflow-<disc>` named
by the registry. Check with `bin/cbflow flow waiver-manager -h` and
`cbflow test --cli-smoke`.

## 4. Adding a new flow

Example: `MYFLOW` in the RTL discipline, tool `mytool`.

1. **Registry** — `global/config/flow/v1.0.0/flow_registry.tcl`: add `MYFLOW`
   to `flow(types)`, `set flow(discipline,MYFLOW) "RTL"`,
   `set flow(color,MYFLOW) "#…"`; add a description line to
   `descriptions_config.tcl`.
2. **Discipline flow config** — `RTL/config/flow/v1.0.0/flow_config.tcl`:
   `set flow(mandatory_vars,MYFLOW) {default_tool}` (the file already sources
   `node_configs/${CBFLOW_FLOW_TYPE}_config.tcl`).
3. **Run-dir layout** — `RTL/config/flow/v1.0.0/dir_config.tcl`:
   ```tcl
   set directory(MYFLOW) { "logs" "setup" "work" "work/MYFLOW" }
   ```
4. **Node config** — `RTL/config/flow/v1.0.0/node_configs/MYFLOW_config.tcl`
   (model: `RTL_SPEC_config.tcl`):
   ```tcl
   array set myflow {
       stages {inputs1 check1 release_data1}
       dependencies,inputs1        {}
       dependencies,check1         {inputs1}
       dependencies,release_data1  {check1}
   }
   foreach _s {check1 release_data1} {
       set myflow(subnodes,$_s) {setup run validate finish}
       set myflow(subnode_dependencies,${_s},setup)    {}
       set myflow(subnode_dependencies,${_s},run)      {setup}
       set myflow(subnode_dependencies,${_s},validate) {run}
       set myflow(subnode_dependencies,${_s},finish)   {validate}
   }
   array set myflow {
       stage_types,inputs1 "inputs"   stage_types,check1 "execution"   stage_types,release_data1 "release_data"
       node_types,inputs1  "inputs"   node_types,check1  "check"       node_types,release_data1  "release_data"
       runtime,timeout,inputs1 10     runtime,timeout,check1 30        runtime,timeout,release_data1 10
       mmmc,enabled false
       output,work_dir "work/MYFLOW"
       supported_tools {mytool}
       default_tool    "mytool"
   }
   set _node_config_dir [file dirname [info script]]
   set _tool_name [expr {[info exists myflow(tool,name)] ? $myflow(tool,name) : $myflow(default_tool)}]
   set _tool_config "$_node_config_dir/MYFLOW_${_tool_name}_config.tcl"
   if {[file exists $_tool_config]} { source $_tool_config } else {
       puts "ERROR: Tool config not found: $_tool_config"; exit 1
   }
   ```
   A per-scenario node adds `set myflow(subnodes,<node>) {dynamic}` with
   `set myflow(subnodes,<node>,dynamic_kind) scenario` (or `rc_corner`).
5. **Tool overlay** — `node_configs/MYFLOW_mytool_config.tcl`: `tool,vendor`,
   `tool,name`, `tool,version`, app settings, `mandatory_outputs,<node>`,
   `smartgrid,milestone` (section 5).
6. **Tool shell** — `lsf(tool_shell,mytool)` (+ `lsf(tool_short,mytool)`) in
   `RTL/config/flow/v1.0.0/tool_launch_config.tcl`; add `mytool <vendor>` to
   `vendor_for_tool` in `global/utils/generation/v1.0.0/generate_setup.tcl`.
7. **Handlers + command files** — `RTL/cmds/MYFLOW/<vendor>/mytool/v1.0.0/`:
   `inputs_subnode_handler.tcl`, `check_subnode_handler.tcl`,
   `check_mytool.tcl`, `release_data_subnode_handler.tcl`,
   `release_data_mytool.tcl` (templates in section 5).
8. **Inputs / release** — handshake entries for MYFLOW's inputs and for
   whoever consumes its release (section 6); an exit milestone if it signs
   something off (section 7).
9. **Project** — add the flow to the project's
   `enabled_flows_by_discipline` in `global/config/master_projects.json`.
10. **Verify** — `bin/cbflow flow info --flow MYFLOW`,
    `bin/cbflow flow nodes --flow MYFLOW`, `cbflow test --static`
    (category 19 checks open-source wiring), then a test-mode run
    (`flow(test_mode) "true"`) and `cbflow run gen-makefile` in it to verify the DAG.

> `cbflow flow plugin scaffold` predates this layout (it writes a Makefile
> generator template under `PD/plugins/` and a PD `cmds/` stub) — copy an
> existing flow instead.

## 5. Adding an open-source tool overlay

Example: an open-source `RTL_RDC` overlay with tool name `rdccheck` running
Tcl drivers in the container (`oss_tclsh`).

**a. Overlay** `RTL/config/flow/v1.0.0/node_configs/RTL_RDC_rdccheck_config.tcl`
(model: `RTL_LINT_verilator_config.tcl`, `RTL_SPEC_rtlcheck_config.tcl`):

```tcl
array set rtl_rdc {
    tool,vendor  "opensource"
    tool,name    "rdccheck"
    tool,version "v1.0.0"
    tool,args    ""
}
# binary per stage → lsf(tool_shell,<binary>) → cbflow-oss
array set rtl_rdc {
    oss,tool,rdc           "oss_tclsh"
    oss,tool,release_data  "oss_tclsh"
}
set rtl_rdc(mandatory_outputs,rdc1)          {violations.csv}
set rtl_rdc(mandatory_outputs,release_data1) {release.manifest}
set rtl_rdc(smartgrid,milestone)             "RDC_SIGNOFF"
set rtl_rdc(checklist,exit_node,RDC_SIGNOFF) rdc1
```

Add `rdccheck` to `supported_tools` in `RTL_RDC_config.tcl`, and
`rdccheck opensource` to `vendor_for_tool` (generate_setup.tcl).

**b. Handlers** `RTL/cmds/RTL_RDC/opensource/rdccheck/v1.0.0/<type>_subnode_handler.tcl`
— one per execution node type:

```tcl
#!/usr/bin/env tclsh
source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/handler_common.tcl"
source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/launch_utils.tcl"

lassign [handler_parse_args $argv $argc] subnode_name run_dir node_name
handler_load_configs $run_dir "RTL_RDC"

set ::flow_type "RTL_RDC"
set stage_name "rdc"
if {$node_name eq ""} { set node_name [cbflow_node_name] }

set _tool_ver [cbflow_require rtl_rdc tool,version]
set cmd_file "$::env(CBFLOW_RTL_DIR)/cmds/RTL_RDC/opensource/rdccheck/$_tool_ver/rdc_rdccheck.tcl"

set test_mode [handler_is_test_mode]
if {![info exists ::rtl_rdc(oss,tool,$stage_name)]} {
    puts "ERROR: rtl_rdc(oss,tool,$stage_name) not set — RTL_RDC_rdccheck_config.tcl not loaded?"
    exit 1
}
handler_dispatch $subnode_name $run_dir $::flow_type $node_name $stage_name \
                 $cmd_file $test_mode $::rtl_rdc(oss,tool,$stage_name)
```

The inputs handler is generic — copy
`RTL/cmds/RTL_LINT/opensource/verilator/v1.0.0/inputs_subnode_handler.tcl`
and change the flow name (it calls `handler_resolve_inputs` +
`handler_dispatch_inputs`). PD handlers point at
`$::env(FLOW_DIR)/PD/cmds/...`; DFT / DV / RTL at
`$::env(CBFLOW_<DISC>_DIR)/cmds/...`.

**c. Command files** `rdc_rdccheck.tcl`, `release_data_rdccheck.tcl`:

```tcl
#!/usr/bin/env tclsh
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "RTL_RDC"
set STAGE_NAME "rdc"
set NODE_NAME [cbflow_node_name]

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_utils.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_flow_utils.tcl"
set design_name [oss_get flow design_name]

flow_proc rdc {
    oss_run "$::REPORTS_DIR/rdc.log" python3 ...   ;# writes [oss_stage_out violations.csv]
}

oss_exec_all      ;# test mode lists the steps; the handler writes stub outputs
exit
```

A release command file sources `release_utils.tcl` and calls
`::CBFlow::Release::init $::FLOW_TYPE $design_name $::DIRS(run) [cbflow_run_phase]`,
`copy_file` / `copy_glob` (use `oss_release_name <CONSUMER> <input>` to take
category + filename from the handshake), `generate_manifest`,
`stamp_complete` (model: `RTL/cmds/RTL_SPEC/opensource/rtlcheck/v1.0.0/release_data_rtlcheck.tcl`).
PD open-source command files (yosys / openroad / opensta / magic) end with
`flow_exec_all` and use `oss_load_stage`, `oss_upstream_node`, …

**d. A new container binary** (only if the stage runs a program not already
wired): add it to the tool case in `global/bin/cbflow-oss`, to the
`foreach _oss_tool {…}` list in
`global/config/flow/v1.0.0/oss_launch_config.tcl` (gives
`lsf(tool_shell,<bin>)`), to `vendor_for_tool`, and an install script under
`global/utils/oss/` if it is not in the image.

**e. Check** — `cbflow test --static --category 19` verifies: overlay parses,
every execution node type has a handler and every stage a command file, every
`oss,tool,<stage>` binary has an `lsf(tool_shell,*)`, every input node has a
handshake.

## 6. Adding a handshake

All handshakes — every discipline — are in
`PD/config/flow/v1.0.0/release_config.tcl` section 6:

```tcl
set flow_input_handshake(<DOWNSTREAM>,<input>) {<SOURCE_FLOW|ANY> <category> "<file pattern>"}
set flow_input_handshake(RTL_RDC,rtl)  {RTL_SPEC rtl "${design_name}.f"}
```

1. The downstream flow gets an inputs node per input
   (`stages` + `node_types,<input>1 "inputs"`); the user sets
   `<flow>(input,release_tag)` (or `<input>_release_tag`, or an explicit
   `<flow>(input,<input>)` path).
2. The upstream release must write `<category>/<file>` in its release dir
   (directly, or via `oss_release_name`).
3. `source_flow` is metadata for errors; `ANY` means any upstream that stages
   the canonical file. Signoff flows: `<flow>(release,exit_from)` names the
   input whose tag is the exit verified; list user-supplied inputs in
   `<flow>(release,exit_exempt_inputs)`.

## 7. Adding an exit milestone

1. Create `global/config/exit/v1.0.0/<NAME>_config.tcl` — picked up
   automatically (model: `LINT_SIGNOFF_config.tcl`):
   ```tcl
   set milestone_info(name)        "RDC_SIGNOFF"
   set milestone_info(discipline)  "RTL"
   set milestone_info(flow_type)   "RTL_RDC"
   set milestone_info(stage)       "rdc"
   set milestone_info(description) "..."
   set milestone_info(stage_node)  "rdc1"
   array set mandatory_checks {
       "rdc_open_errors" {
           "id" "RDC_0001" "script" "check_metric.tcl" "description" "No open errors"
           "criteria" "rdc_open_errors <= 0" "min_phase_index" "0"
           "metric_name" "rdc_open_errors" "unit" "" "operator" "<=" "default_threshold" "0"
       }
   }
   array set optional_checks {}
   set mandatory_files [list "outputs/violations_final.csv"]
   ```
2. In the flow's tool overlay, say where the data is:
   `<flow>(smartgrid,milestone) "<NAME>"`,
   `<flow>(checklist,exit_node,<NAME>) <node>`,
   `<flow>(checklist,metric,<check>) {regex (\d+)}` /
   `<flow>(checklist,grep,<check>)`, `<flow>(checklist,report[,<check>])`,
   `<flow>(checklist,mandatory_files,<NAME>)`.
3. Put the exit in the project's plan:
   `project(phase_exits)` or `project(phase_exits,<DISC>)` in
   `global/config/project/<proj>/v1.0.0/<proj>_config.tcl` — order there is
   the exit-order gate. A PD implementation exit also needs
   `MILESTONE_ORDER`, `MILESTONE_STAGE_MAPPING`, `milestone_flow_map` and
   `release_tags` in `PD/config/flow/v1.0.0/release_config.tcl`.
4. Check with `cbflow flow checklist list --discipline <DISC>` and
   `cbflow flow checklist list-checks --milestone <NAME>`.

Add a single check to an existing milestone from the CLI:

```bash
cbflow flow checklist add-check --milestone BTO --name drc_zero --type mandatory \
  --description "DRC violations must be zero" \
  --grep-file "work/SYNTH_PNR/signoff1/reports/signoff_check_drc.rpt" \
  --grep-pattern "Total.*0.*violation" --grep-pass-if found
cbflow flow checklist add-check --milestone BTO --name gds_exists --type file \
  --file-path 'outputs/${design_name}.gds'
```

> `--discipline` on the checklist CLI accepts `PD | DFT | DV` today
> (`_DISC_CHOICES` in `PD/utils/commands/checklist_cmd.py`); RTL milestones are
> listed when the flag is omitted.

## 8. Testing your change

```bash
cbflow test --static                    # static categories (excl. opt-in 18)
cbflow test --static --category 19      # open-source wiring (DFT / RTL / DV)
cbflow test --e2e --flow SYNTH_PNR      # one PD flow end to end in test mode
cbflow test --cli-smoke                 # every cbflow leaf command's --help
```

See [Test Suite Developer Guide](test-suite.md).
