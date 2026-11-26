# Advanced Scenarios

Complex use cases built from the commands in [Basic Workflows](basic-workflows.md). Examples use project
**opensky** (skywater_130nm, open-source tools) unless noted.

---

## 1. Hierarchical build: DL3 -> DL2 -> DL1 with library tags

`project(design_hierarchy)` declares DL3 `gcd`, `mac_array` -> DL2 `ctrl_subsys`, `ai_subsys` -> DL1 `opensky_chip`.
A parent sees its children through a **library tag** (`project(lib_config_tag)`, tags under
`<project(lib_tag_root)>/skywater_130nm/<TAG>/`).

```bash
cd workarea

# 1. DL3 blocks for phase P1: SYNTH -> FP -> PNR -> publish -> signoff
PHASE=P1 RUN=p1_b1 ./run_p1_dl3.sh

# 2. Put the released children into a tag (GDS / CDL from the PV release, SPEFs linked per RC corner)
for b in gcd mac_array; do
  cbflow flow library-manager add --tech skywater_130nm --project opensky --tag OSS1 \
      --category block --path <release,path>/P1/$b/PNR/PRO_EXIT
done
# PV not released yet? take GDS / CDL from the PNR release and record tech(block,<b>,pv_release) "PENDING":
#   ... --category block --path <release,path>/P1/gcd/PNR/PRO_EXIT --pv-pending

# 3. Check the tag, then the cells a parent instantiates against it
cbflow flow library-manager check --tech skywater_130nm --lib_tag OSS1
cbflow flow library-manager check --tech skywater_130nm --lib_tag OSS1 \
    --project opensky --design ctrl_subsys --netlist_tag P1_SYNTH_v1 --phase P1

# 4. DL2 parents on that tag (FROM=FP|PNR reuses earlier releases, UNTIL=FP|PNR stops early)
./run_p1_dl2.sh ctrl_subsys ai_subsys
```

---

## 2. Release several exits from one PNR run

Add one export / release pair per intermediate exit, run once, publish in exit order:

```bash
cd workarea/gcd/P2_run_PNR_gcd_b1
cbflow run add-node --node export_data2  --type export_data  --dep place1
cbflow run add-node --node release_data2 --type release_data --dep export_data2   # PLACE_EXIT
cbflow run add-node --node export_data3  --type export_data  --dep cts_opt1
cbflow run add-node --node release_data3 --type release_data --dep export_data3   # CTS_EXIT
cbflow run all
cbflow run release --from-run . --node release_data2 --publish
cbflow run release --from-run . --node release_data3 --publish
```

Releases before `pro` carry no SPEF; before `signoff` no timing models. `cts` and `route` have no exit.

---

## 3. Per-node overrides

Files in `<run>/setup/` apply in this order (last writer wins; there is no flow-name level):

```
override_config.tcl -> override_config.<stage>.tcl -> override_config.<branch>.tcl
  -> override_config.<node_type>.tcl -> override_config.<node>.tcl
```

```tcl
# setup/override_config.tcl — every node of the run
set pnr(oss,drv,max_fanout) 10

# setup/override_config.place2.tcl — only the added place2 node
set pnr(oss,place,density) 0.30
```

Then `cbflow run retrace --from place2 --run`.

---

## 4. flow_proc hooks

Command files define their steps with `flow_proc`. Extend a step from `setup/override_setup.tcl`
(or `override_setup.<stage>.tcl` / `override_setup.<node>.tcl`):

```tcl
flow_proc_prepend report { puts "INFO: extra reports before the standard ones" }
flow_proc_append  report { report_check_types -max_slew -max_capacitance -violators }
```

Prefer prepend / append for the open-source command files: they define their `flow_proc`s inline, so a
`flow_proc_replace` issued from setup is overwritten when the command file loads.

---

## 5. Restrict MMMC scenarios per node

```tcl
# setup/override_config.timing1.tcl (STA), or the run GUI: right-click timing1 -> MMMC Scenarios -> Save
set mmmc(timing1,setup_scenarios) "func_ss_1p60v_rc_max_100c"
set mmmc(timing1,hold_scenarios)  "func_ff_1p95v_rc_min_m40c"
```

Project-wide per-node assignments live in `global/config/project/<proj>/v1.0.0/mmmc_node_scenarios.tcl`
(`cbflow flow mmmc-manager set-node --node cts --setup "..." --hold "..."`).

---

## 6. Parallelism and memory

```tcl
set flow(max_parallel_jobs) 4     ;# cap concurrent local jobs (0 = unlimited)
```

`run_signoff.sh` passes it as `MAX_PARALLEL=<n>`. With LSF, `cbflow run add-node … --resource-tier XL` or
`cbflow run all --lsf --queue L` pick the resource tier.

---

## 7. Spec-to-GDS chain

`project(signoff_chain,<phase>)` lists the stages of a block's sign-off chain (RTL_SPEC -> RTL checks -> DV ->
SYNTH -> DFT -> PD -> signoff). Drive it with:

```bash
cd workarea
DRY=1 ./run_spec2gds.sh gcd P3          # print the plan
./run_spec2gds.sh gcd P3                # run it (FROM=<step> / UNTIL=<step> to cut)
```

SmartGrid shows progress on the project page's chain tile and on `/project/opensky/chain`. See the
[Spec-to-GDS guide](../02-user-guide/spec-to-gds-guide.md).

---

## 8. Debug a run's configuration

```bash
cbflow run debug --dump-resolved-cfg --key 'flow(use_lsf)'   # which file set it
cbflow run report --node place1 --dump-setup                  # setup.tcl / config.tcl of a node
cbflow run interactive --node place1                          # restore the node in the tool
```

---

## 9. Framework version rollback

```bash
cbflow flow version list --dir config/flow
cbflow flow version set-current --dir config/flow --version v1.0.0
cbflow flow version get-current --dir config/flow
```

See [Versioning Workflow](../02-user-guide/versioning-workflow.md).
