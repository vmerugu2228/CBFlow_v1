# CBflow Stage Variables Reference

This document provides a comprehensive reference for all stage variables across CBflow's supported design flows. Each variable follows the naming convention `<flow_array>(<category>,<variable_name>)` and is resolved through the config cascade during execution.

---

## Table of Contents

1. [SYNTH_PNR Flow (Fusion Compiler)](#synth_pnr-flow-fusion-compiler)
2. [STA Flow](#sta-flow)
3. [LEC Flow](#lec-flow)
4. [CLP Flow](#clp-flow)
5. [PV Flow](#pv-flow)
6. [EMIR Flow](#emir-flow)
7. [PNR Flow](#pnr-flow)
8. [SYNTH Flow](#synth-flow)
9. [FP Flow](#fp-flow)
10. [ECO Flow](#eco-flow)

---

## SYNTH_PNR Flow (Fusion Compiler)

### Stages

```
rtl1 → sdc1 → upf1 → init_design1 → synthesis1 → place1 → cts1 → cts_opt1 → route1 → pro1 → signoff1 → export_data1 → release_data1
```

### Input Variables

| Variable | Expected Value | Stage | Description |
|----------|---------------|-------|-------------|
| `synth_pnr(input,rtl_filelist)` | File path (string) | rtl1, init_design1 | Path to RTL filelist containing all design source files |
| `synth_pnr(input,rtl_format)` | `"sverilog"` | rtl1, init_design1 | RTL source format (sverilog, verilog, vhdl) |
| `synth_pnr(input,sdc_func_file)` | File path (string) | sdc1, init_design1 | Primary timing constraint file for functional mode |
| `synth_pnr(input,upf_file)` | File path (string) | upf1, init_design1 | Unified Power Format file for power intent |
| `synth_pnr(input,def_file)` | File path (string) | init_design1 | DEF floorplan file for physical initialization |
| `synth_pnr(input,fp_tcl)` | File path (string) | init_design1 | TCL-based floorplan script (alternative to DEF) |
| `synth_pnr(input,scan_def)` | File path (string) | init_design1 | Scan chain DEF for DFT integration |

### Common Variables (used across stages)

| Variable | Expected Value | Description |
|----------|---------------|-------------|
| `synth_pnr(common,design_name)` | String | Top-level design module name |
| `synth_pnr(common,design_lib_name)` | String | Design library name for tool database |
| `synth_pnr(common,compile,qor_mode)` | `"timing"` \| `"leakage_power"` \| `"total_power"` | QoR optimization priority mode |
| `synth_pnr(common,compile,qor_metric)` | `"timing"` | Primary QoR metric for compile optimization |
| `synth_pnr(common,compile,qor_version)` | `""` (string) | QoR recipe version (empty for default) |
| `synth_pnr(common,compile,reduced_effort)` | `"false"` | Enable reduced compile effort for faster turnaround |
| `synth_pnr(common,compile,high_effort_timing)` | `"true"` | Enable high-effort timing optimization |
| `synth_pnr(common,compile,congestion_effort)` | `"medium"` \| `"high"` \| `"low"` \| `"ultra"` | Congestion-aware optimization effort level |
| `synth_pnr(common,upf_mode)` | `"prime"` \| `"golden"` \| `"none"` | UPF handling mode for power domains |
| `synth_pnr(common,lib_cell_purpose_file)` | File path (string) | Library cell purpose mapping file |
| `synth_pnr(common,multi_vt_constraint_file)` | File path (string) | Multi-Vt cell usage constraint file |
| `synth_pnr(common,cts_primary_corner)` | String | Primary corner for CTS balancing |
| `synth_pnr(common,connect_pg_net_script)` | File path (string) | Power/ground net connection script |
| `synth_pnr(common,route_max_layer)` | String (metal layer) | Maximum routing layer constraint |
| `synth_pnr(common,route_min_layer)` | String (metal layer) | Minimum routing layer constraint |
| `synth_pnr(common,analysis,max_paths)` | `100` (integer) | Maximum paths for timing analysis reports |
| `synth_pnr(common,output,block_labeling)` | `"true"` \| `"false"` | Enable block labeling in output databases |
| `synth_pnr(common,non_persistent_script)` | File path (string) | Script applied per-session (non-persistent settings) |
| `synth_pnr(common,mcmm_adjustment_file)` | File path (string) | MCMM scenario adjustment overrides |
| `synth_pnr(common,saif_file)` | File path (string) | Switching Activity Interchange Format file for power |
| `synth_pnr(common,saif_power_scenario)` | String | Scenario name for SAIF-based power analysis |
| `synth_pnr(common,enable_fusa)` | `"true"` \| `"false"` | Enable functional safety (FuSa) features |
| `synth_pnr(common,route_opt,starrc_config)` | File path (string) | StarRC extraction configuration file |
| `synth_pnr(common,route_opt,starrc_options)` | String | Additional StarRC extraction options |
| `synth_pnr(common,route_opt,vmf_parameter_file)` | File path (string) | Via Metal Fill parameter file |
| `synth_pnr(common,route_opt,enable_advanced_vmf)` | `"true"` \| `"false"` | Enable advanced via metal fill during route_opt |

### Per-Stage Variables

#### init_design1

| Variable | Expected Value | Description |
|----------|---------------|-------------|
| `synth_pnr(fp,core_utilization)` | `"0.7"` (float string) | Target core area utilization ratio |
| `synth_pnr(fp,aspect_ratio)` | `"1.0"` (float string) | Core aspect ratio (height/width) |
| `synth_pnr(fp,core_offset)` | String (microns) | Core-to-die edge offset spacing |
| `synth_pnr(init_design,fp_tap_cell_distance)` | String (microns) | Maximum distance between tap cells |

#### synthesis1

| Variable | Expected Value | Description |
|----------|---------------|-------------|
| `synth_pnr(synthesis,compile,unified_flow)` | `"true"` | Enable unified compile flow (FC recommended) |
| `synth_pnr(synthesis,compile,enable_spg)` | `"true"` \| `"false"` | Enable SPG (Synopsys Physical Guidance) during compile |
| `synth_pnr(synthesis,compile,active_scenarios)` | List (string) | Scenarios active during synthesis compile |
| `synth_pnr(synthesis,dft_insert_enable)` | `"true"` \| `"false"` | Enable DFT scan chain insertion |
| `synth_pnr(synthesis,dft_setup_file)` | File path (string) | DFT configuration and setup file |
| `synth_pnr(synthesis,compile_pre_script)` | File path (string) | Script executed before compile |
| `synth_pnr(synthesis,compile_post_script)` | File path (string) | Script executed after compile |

#### place1

| Variable | Expected Value | Description |
|----------|---------------|-------------|
| `synth_pnr(place,opt_active_scenarios)` | List (string) | Active scenarios for placement optimization |
| `synth_pnr(place,place_opt,high_utilization_flow)` | `"true"` \| `"false"` | Enable high-utilization placement flow |
| `synth_pnr(place,place_opt_pre_script)` | File path (string) | Script executed before place_opt |
| `synth_pnr(place,place_opt_post_script)` | File path (string) | Script executed after place_opt |

#### cts1

| Variable | Expected Value | Description |
|----------|---------------|-------------|
| `synth_pnr(cts,clock_opt_cts,active_scenarios)` | List (string) | Active scenarios for CTS optimization |
| `synth_pnr(cts,clock_opt_cts,enable_aocv)` | `"true"` | Enable AOCV during CTS |
| `synth_pnr(cts,cts_sidefile)` | File path (string) | CTS sidefile for additional clock tree constraints |
| `synth_pnr(cts,cts_ndr_file)` | File path (string) | Non-default routing rules for clock nets |
| `synth_pnr(cts,cts,enable_shields)` | `"true"` \| `"false"` | Enable shielding on clock nets |
| `synth_pnr(cts,redundant_via)` | `"true"` \| `"false"` | Insert redundant vias on clock nets |
| `synth_pnr(cts,cts_pre_script)` | File path (string) | Script executed before CTS |
| `synth_pnr(cts,cts_post_script)` | File path (string) | Script executed after CTS |
| `synth_pnr(cts,mscts_mesh_routing_script)` | File path (string) | Mesh clock routing script for MSCTS |

#### route1

| Variable | Expected Value | Description |
|----------|---------------|-------------|
| `synth_pnr(route,route_sidefile)` | File path (string) | Route sidefile for additional routing constraints |
| `synth_pnr(route,route_auto,active_scenarios)` | List (string) | Active scenarios for route_auto |
| `synth_pnr(route,route_auto,enable_redundant_via)` | `"true"` \| `"false"` | Enable redundant via insertion during routing |
| `synth_pnr(route,route_pre_script)` | File path (string) | Script executed before routing |
| `synth_pnr(route,route_post_script)` | File path (string) | Script executed after routing |

#### pro1 (Post-Route Optimization)

| Variable | Expected Value | Description |
|----------|---------------|-------------|
| `synth_pnr(pro,opt_active_scenarios)` | List (string) | Active scenarios for post-route optimization |
| `synth_pnr(pro,route_opt_sidefile)` | File path (string) | Sidefile for route_opt customization |
| `synth_pnr(pro,route_opt,extraction_mode)` | `"fusion_adv"` \| `"in_design"` \| `"none"` | Parasitic extraction mode during route_opt |
| `synth_pnr(pro,route_opt,pba_mode)` | `"path"` \| `"exhaustive"` \| `"incremental"` | Path-based analysis mode |
| `synth_pnr(pro,route_opt,enable_irdccd)` | `"true"` \| `"false"` | Enable IR-drop/CCD aware optimization |
| `synth_pnr(pro,route_opt,enable_hyper)` | `"true"` \| `"false"` | Enable hyper optimization mode |
| `synth_pnr(pro,route_opt,redundant_via)` | `"true"` \| `"false"` | Insert redundant vias during route_opt |
| `synth_pnr(pro,route_opt,enable_endpoint_opt)` | `"true"` \| `"false"` | Enable endpoint-focused optimization |
| `synth_pnr(pro,endpoint_opt,auto_metric)` | `"setup"` \| `"hold"` | Endpoint optimization target metric |
| `synth_pnr(pro,endpoint_opt,max_paths)` | `1000` (integer) | Maximum paths for endpoint optimization |
| `synth_pnr(pro,endpoint_opt,slack_threshold)` | `"-0.010"` (float string, ns) | Slack threshold for endpoint opt targeting |
| `synth_pnr(pro,endpoint_opt,loop_count)` | `3` (integer) | Number of endpoint optimization iterations |
| `synth_pnr(pro,route_opt_pre_script)` | File path (string) | Script executed before route_opt |
| `synth_pnr(pro,route_opt_post_script)` | File path (string) | Script executed after route_opt |

#### signoff1

| Variable | Expected Value | Description |
|----------|---------------|-------------|
| `synth_pnr(signoff,active_scenarios)` | List (string) | Active scenarios for signoff analysis |
| `synth_pnr(signoff,insert_filler)` | `"true"` | Insert filler cells for DRC closure |
| `synth_pnr(signoff,insert_decap)` | `"true"` \| `"false"` | Insert decap cells for power integrity |
| `synth_pnr(signoff,drc_runset)` | File path (string) | DRC rule deck for in-design DRC |
| `synth_pnr(signoff,fix_drc)` | `"true"` \| `"false"` | Enable automatic DRC fixing |
| `synth_pnr(signoff,insert_diodes)` | `"true"` \| `"false"` | Insert antenna diodes |
| `synth_pnr(signoff,metal_fill)` | `"true"` \| `"false"` | Enable metal fill insertion |
| `synth_pnr(signoff,metal_fill_track_based)` | `"true"` \| `"false"` | Use track-based metal fill methodology |
| `synth_pnr(signoff,metal_fill_parameter_file)` | File path (string) | Metal fill parameter/recipe file |
| `synth_pnr(signoff,em_saif)` | File path (string) | SAIF file for EM analysis |
| `synth_pnr(signoff,em_scenario)` | String | Scenario for electromigration analysis |
| `synth_pnr(signoff,em_fixing)` | `"true"` \| `"false"` | Enable automatic EM violation fixing |

#### export_data1

| Variable | Expected Value | Description |
|----------|---------------|-------------|
| `synth_pnr(export_data,write_gds)` | `"true"` | Write GDS stream output |
| `synth_pnr(export_data,write_oasis)` | `"false"` | Write OASIS stream output |
| `synth_pnr(export_data,name_rules)` | String | Layer name mapping rules for stream out |
| `synth_pnr(export_data,pre_script)` | File path (string) | Script executed before data export |
| `synth_pnr(export_data,post_script)` | File path (string) | Script executed after data export |

### MMMC Variables

| Variable | Expected Value | Description |
|----------|---------------|-------------|
| `synth_pnr(mmmc,enabled)` | `"true"` | Enable multi-mode multi-corner analysis |
| `synth_pnr(mmmc,default_scenario_set)` | `"signoff"` | Default scenario set when not overridden |
| `synth_pnr(mmmc,scenario_set)` | `"signoff"` | Active scenario set for current run |
| `synth_pnr(mmmc,multi_corner_compile)` | `"true"` | Enable multi-corner aware compilation |

---

## STA Flow

### Stages

```
timing1 (with dynamic per-scenario subnodes)
```

Each scenario runs as a parallel subnode with naming: `timing1_<mode>_<pvt>_<voltage>_<rc_corner>_<temperature>`

### Input Variables

| Variable | Expected Value | Stage | Description |
|----------|---------------|-------|-------------|
| `sta(input,netlist)` | File path (string) | timing1 | Gate-level netlist for timing analysis |
| `sta(input,def_file)` | File path (string) | timing1 | DEF file for physical-aware STA |
| `sta(input,sdc,func)` | File path (string) | timing1 | SDC constraints for functional mode |
| `sta(input,sdc,test)` | File path (string) | timing1 | SDC constraints for test/scan mode |
| `sta(input,from_run)` | Directory path (string) | timing1 | Path to upstream run for auto-handoff via output_manifest |
| `sta(input,release_tag)` | String | timing1 | Release tag for fetching inputs from release directory |

### Analysis Variables

| Variable | Expected Value | Description |
|----------|---------------|-------------|
| `sta(analysis,max_paths)` | `100` (integer) | Maximum paths per endpoint for timing reports |
| `sta(analysis,setup_margin)` | `"0.0"` (float string, ns) | Additional setup margin derating |
| `sta(analysis,hold_margin)` | `"0.0"` (float string, ns) | Additional hold margin derating |
| `sta(analysis,ocv_mode)` | `"aocv"` | OCV analysis mode (aocv, socv, flat) |
| `sta(analysis,si_aware)` | `"true"` | Enable signal integrity (crosstalk) aware analysis |
| `sta(analysis,report_power)` | `"true"` | Enable power reporting during STA |
| `sta(analysis,pba_mode)` | `"exhaustive"` | Path-based analysis mode (exhaustive, path, none) |

### Tool-Specific Variables (Tempus)

| Variable | Expected Value | Description |
|----------|---------------|-------------|
| `sta(tool,cpu_count)` | `8` (integer) | Number of CPUs for multi-threaded analysis |
| `sta(timing,si_aware)` | `"true"` | Enable SI-aware timing in Tempus |
| `sta(timing,pba_nworst)` | `2` (integer) | Number of worst paths per endpoint for PBA |
| `sta(timing,pba_max_paths)` | `1000` (integer) | Maximum paths for PBA analysis |
| `sta(timing,epba_max_paths)` | `10000` (integer) | Maximum paths for exhaustive PBA |

### MMMC Variables

| Variable | Expected Value | Description |
|----------|---------------|-------------|
| `sta(mmmc,enabled)` | `"true"` | Enable MMMC scenario-based analysis |
| `sta(mmmc,dynamic_scenarios)` | `"true"` | Enable dynamic scenario resolution per node |
| `sta(mmmc,parallel_scenarios)` | `"true"` | Run scenarios in parallel as subnodes |
| `sta(mmmc,scenario_set)` | `"signoff"` | Scenario set filter (signoff, setup, hold, all, power) |

---

## LEC Flow

### Stages

```
compare1
```

### Input Variables

| Variable | Expected Value | Stage | Description |
|----------|---------------|-------|-------------|
| `lec(input,netlist_golden)` | File path (string) | compare1 | Reference (golden) netlist for comparison |
| `lec(input,netlist_revised)` | File path (string) | compare1 | Revised netlist to verify against golden |
| `lec(input,constraints)` | File path (string) | compare1 | Constraint file for equivalence checking setup |

### Compare Variables

| Variable | Expected Value | Description |
|----------|---------------|-------------|
| `lec(compare,effort)` | `"high"` | Verification effort level (low, medium, high) |
| `lec(compare,flatten_design)` | `"true"` | Flatten hierarchy before comparison |
| `lec(compare,datapath_verify)` | `"true"` | Enable datapath-specific verification techniques |

---

## CLP Flow

### Stages

```
check1
```

### Input Variables

| Variable | Expected Value | Stage | Description |
|----------|---------------|-------|-------------|
| `clp(input,netlist)` | File path (string) | check1 | Gate-level netlist for power verification |
| `clp(input,upf_file)` | File path (string) | check1 | UPF power intent specification |
| `clp(input,power_spec)` | File path (string) | check1 | Additional power specification file |

### Check Variables

| Variable | Expected Value | Description |
|----------|---------------|-------------|
| `clp(check,isolation)` | `"true"` | Verify isolation cell insertion and connectivity |
| `clp(check,retention)` | `"true"` | Verify retention register implementation |
| `clp(check,level_shifter)` | `"true"` | Verify level shifter insertion between voltage domains |
| `clp(check,power_domain)` | `"true"` | Verify power domain boundary correctness |
| `clp(check,always_on)` | `"true"` | Verify always-on logic connectivity and placement |

---

## PV Flow

### Stages

```
drc1 → lvs1 → fill1
```

### Input Variables

| Variable | Expected Value | Stage | Description |
|----------|---------------|-------|-------------|
| `pv(input,netlist)` | File path (string) | lvs1 | Gate-level netlist for LVS comparison |
| `pv(input,def_file)` | File path (string) | drc1, lvs1 | DEF file for physical data |
| `pv(input,gds)` | File path (string) | drc1, lvs1, fill1 | GDS/OASIS layout for physical verification |

### DRC Variables

| Variable | Expected Value | Description |
|----------|---------------|-------------|
| `pv(drc,runset)` | File path (string) | DRC rule deck (Calibre/ICV format) |
| `pv(drc,num_cpus)` | `8` (integer) | Number of CPUs for DRC execution |
| `pv(drc,error_limit)` | `1000` (integer) | Maximum DRC errors to report before stopping |

### LVS Variables

| Variable | Expected Value | Description |
|----------|---------------|-------------|
| `pv(lvs,runset)` | File path (string) | LVS rule deck (Calibre/ICV format) |
| `pv(lvs,num_cpus)` | `8` (integer) | Number of CPUs for LVS execution |

### Fill Variables

| Variable | Expected Value | Description |
|----------|---------------|-------------|
| `pv(fill,feol_runset)` | File path (string) | FEOL (front-end-of-line) fill rule deck |
| `pv(fill,beol_runset)` | File path (string) | BEOL (back-end-of-line) fill rule deck |

---

## EMIR Flow

### Stages

```
power_analysis1 → ir_drop1 → em_analysis1
```

### Input Variables

| Variable | Expected Value | Stage | Description |
|----------|---------------|-------|-------------|
| `emir(input,netlist)` | File path (string) | power_analysis1 | Gate-level netlist for power grid analysis |
| `emir(input,def_file)` | File path (string) | power_analysis1 | DEF file with power grid geometry |
| `emir(input,spef)` | File path (string) | power_analysis1 | SPEF parasitic data for power network |

### IR Drop Variables

| Variable | Expected Value | Description |
|----------|---------------|-------------|
| `emir(ir_drop,threshold)` | `"30"` (mV string) | IR drop violation threshold in millivolts |
| `emir(ir_drop,enable)` | `"true"` | Enable static/dynamic IR drop analysis |

### Thermal Variables

| Variable | Expected Value | Description |
|----------|---------------|-------------|
| `emir(thermal,enable)` | `"true"` | Enable thermal-aware analysis |
| `emir(thermal,max_temperature)` | `"125"` (degrees C) | Maximum junction temperature for analysis |

### Power Variables

| Variable | Expected Value | Description |
|----------|---------------|-------------|
| `emir(power,analysis_mode)` | `"vectorless"` | Power analysis mode (vectorless, vector-based) |

---

## PNR Flow

### Stages

```
init_design1 → place1 → cts1 → cts_opt1 → route1 → pro1 → signoff1 → export_data1 → release_data1
```

The PNR flow is similar to SYNTH_PNR but starts from a synthesized netlist (no RTL/synthesis stages). All variables use the `pnr()` array.

### Input Variables

| Variable | Expected Value | Stage | Description |
|----------|---------------|-------|-------------|
| `pnr(input,netlist)` | File path (string) | init_design1 | Synthesized gate-level netlist |
| `pnr(input,sdc_func_file)` | File path (string) | init_design1 | Timing constraints for functional mode |
| `pnr(input,upf_file)` | File path (string) | init_design1 | UPF power intent file |
| `pnr(input,def_file)` | File path (string) | init_design1 | DEF floorplan file |
| `pnr(input,fp_tcl)` | File path (string) | init_design1 | TCL-based floorplan script |
| `pnr(input,scan_def)` | File path (string) | init_design1 | Scan chain DEF for DFT |
| `pnr(input,from_run)` | Directory path (string) | init_design1 | Path to upstream synthesis run |

### Common Variables

| Variable | Expected Value | Description |
|----------|---------------|-------------|
| `pnr(common,design_name)` | String | Top-level design module name |
| `pnr(common,design_lib_name)` | String | Design library name |
| `pnr(common,upf_mode)` | `"prime"` \| `"golden"` \| `"none"` | UPF handling mode |
| `pnr(common,route_max_layer)` | String (metal layer) | Maximum routing layer |
| `pnr(common,route_min_layer)` | String (metal layer) | Minimum routing layer |
| `pnr(common,cts_primary_corner)` | String | Primary corner for CTS |
| `pnr(common,connect_pg_net_script)` | File path (string) | PG net connection script |
| `pnr(common,analysis,max_paths)` | `100` (integer) | Max paths for timing reports |

### Per-Stage Variables

#### init_design1

| Variable | Expected Value | Description |
|----------|---------------|-------------|
| `pnr(fp,core_utilization)` | `"0.7"` (float string) | Target core utilization |
| `pnr(fp,aspect_ratio)` | `"1.0"` (float string) | Core aspect ratio |
| `pnr(fp,core_offset)` | String (microns) | Core-to-die offset |

#### place1

| Variable | Expected Value | Description |
|----------|---------------|-------------|
| `pnr(place,opt_active_scenarios)` | List (string) | Active scenarios for placement |
| `pnr(place,place_opt,high_utilization_flow)` | `"true"` \| `"false"` | High-utilization placement mode |
| `pnr(place,place_opt_pre_script)` | File path (string) | Pre-placement script |
| `pnr(place,place_opt_post_script)` | File path (string) | Post-placement script |

#### cts1

| Variable | Expected Value | Description |
|----------|---------------|-------------|
| `pnr(cts,clock_opt_cts,active_scenarios)` | List (string) | Active CTS scenarios |
| `pnr(cts,clock_opt_cts,enable_aocv)` | `"true"` | Enable AOCV in CTS |
| `pnr(cts,cts_sidefile)` | File path (string) | CTS constraint sidefile |
| `pnr(cts,cts_ndr_file)` | File path (string) | Clock NDR rules |
| `pnr(cts,cts_pre_script)` | File path (string) | Pre-CTS script |
| `pnr(cts,cts_post_script)` | File path (string) | Post-CTS script |

#### route1

| Variable | Expected Value | Description |
|----------|---------------|-------------|
| `pnr(route,route_sidefile)` | File path (string) | Route constraint sidefile |
| `pnr(route,route_auto,active_scenarios)` | List (string) | Active routing scenarios |
| `pnr(route,route_auto,enable_redundant_via)` | `"true"` \| `"false"` | Redundant via during routing |
| `pnr(route,route_pre_script)` | File path (string) | Pre-route script |
| `pnr(route,route_post_script)` | File path (string) | Post-route script |

#### pro1 (Post-Route Optimization)

| Variable | Expected Value | Description |
|----------|---------------|-------------|
| `pnr(pro,opt_active_scenarios)` | List (string) | Active PRO scenarios |
| `pnr(pro,route_opt,extraction_mode)` | `"fusion_adv"` \| `"in_design"` \| `"none"` | Extraction mode |
| `pnr(pro,route_opt,pba_mode)` | `"path"` \| `"exhaustive"` \| `"incremental"` | PBA mode |
| `pnr(pro,route_opt,enable_irdccd)` | `"true"` \| `"false"` | IR-drop/CCD optimization |
| `pnr(pro,route_opt_pre_script)` | File path (string) | Pre-PRO script |
| `pnr(pro,route_opt_post_script)` | File path (string) | Post-PRO script |

#### signoff1

| Variable | Expected Value | Description |
|----------|---------------|-------------|
| `pnr(signoff,active_scenarios)` | List (string) | Active signoff scenarios |
| `pnr(signoff,insert_filler)` | `"true"` | Insert filler cells |
| `pnr(signoff,insert_decap)` | `"true"` \| `"false"` | Insert decap cells |
| `pnr(signoff,metal_fill)` | `"true"` \| `"false"` | Enable metal fill |

#### export_data1

| Variable | Expected Value | Description |
|----------|---------------|-------------|
| `pnr(export_data,write_gds)` | `"true"` | Write GDS output |
| `pnr(export_data,write_oasis)` | `"false"` | Write OASIS output |

### MMMC Variables

| Variable | Expected Value | Description |
|----------|---------------|-------------|
| `pnr(mmmc,enabled)` | `"true"` | Enable MMMC |
| `pnr(mmmc,scenario_set)` | `"signoff"` | Active scenario set |

---

## SYNTH Flow

### Stages

```
rtl1 → sdc1 → upf1 → init_design1 → synthesis1 → export_data1 → release_data1
```

The SYNTH flow covers RTL-to-netlist synthesis only. All variables use the `synth()` array.

### Input Variables

| Variable | Expected Value | Stage | Description |
|----------|---------------|-------|-------------|
| `synth(input,rtl_filelist)` | File path (string) | rtl1, init_design1 | Path to RTL filelist |
| `synth(input,rtl_format)` | `"sverilog"` | rtl1, init_design1 | RTL source format |
| `synth(input,sdc_func_file)` | File path (string) | sdc1, init_design1 | Functional mode SDC |
| `synth(input,upf_file)` | File path (string) | upf1, init_design1 | UPF power intent |

### Common Variables

| Variable | Expected Value | Description |
|----------|---------------|-------------|
| `synth(common,design_name)` | String | Top-level design name |
| `synth(common,design_lib_name)` | String | Design library name |
| `synth(common,compile,qor_mode)` | `"timing"` \| `"leakage_power"` \| `"total_power"` | QoR optimization mode |
| `synth(common,compile,qor_metric)` | `"timing"` | Primary QoR metric |
| `synth(common,compile,high_effort_timing)` | `"true"` | High-effort timing optimization |
| `synth(common,compile,congestion_effort)` | `"medium"` \| `"high"` \| `"low"` \| `"ultra"` | Congestion effort |
| `synth(common,upf_mode)` | `"prime"` \| `"golden"` \| `"none"` | UPF mode |
| `synth(common,lib_cell_purpose_file)` | File path (string) | Cell purpose mapping |
| `synth(common,multi_vt_constraint_file)` | File path (string) | Multi-Vt constraints |

### Synthesis Variables

| Variable | Expected Value | Description |
|----------|---------------|-------------|
| `synth(synthesis,compile,unified_flow)` | `"true"` | Enable unified compile flow |
| `synth(synthesis,compile,enable_spg)` | `"true"` \| `"false"` | Enable SPG |
| `synth(synthesis,compile,active_scenarios)` | List (string) | Active compile scenarios |
| `synth(synthesis,dft_insert_enable)` | `"true"` \| `"false"` | Enable DFT insertion |
| `synth(synthesis,dft_setup_file)` | File path (string) | DFT setup file |
| `synth(synthesis,compile_pre_script)` | File path (string) | Pre-compile script |
| `synth(synthesis,compile_post_script)` | File path (string) | Post-compile script |

### Export Variables

| Variable | Expected Value | Description |
|----------|---------------|-------------|
| `synth(export_data,write_netlist)` | `"true"` | Write synthesized netlist |
| `synth(export_data,pre_script)` | File path (string) | Pre-export script |
| `synth(export_data,post_script)` | File path (string) | Post-export script |

### MMMC Variables

| Variable | Expected Value | Description |
|----------|---------------|-------------|
| `synth(mmmc,enabled)` | `"true"` | Enable MMMC |
| `synth(mmmc,scenario_set)` | `"signoff"` | Active scenario set |
| `synth(mmmc,multi_corner_compile)` | `"true"` | Multi-corner compile |

---

## FP Flow

### Stages

```
init_design1 → floorplan1 → export_data1 → release_data1
```

The FP flow is focused on floorplan creation and exploration. All variables use the `fp()` array.

### Input Variables

| Variable | Expected Value | Stage | Description |
|----------|---------------|-------|-------------|
| `fp(input,netlist)` | File path (string) | init_design1 | Gate-level netlist for floorplanning |
| `fp(input,def_file)` | File path (string) | init_design1 | Initial DEF file (if available) |
| `fp(input,sdc_func_file)` | File path (string) | init_design1 | Timing constraints for placement guidance |
| `fp(input,upf_file)` | File path (string) | init_design1 | UPF for power domain floorplanning |
| `fp(input,macro_placement_file)` | File path (string) | floorplan1 | Macro placement constraint file |
| `fp(input,io_constraint_file)` | File path (string) | floorplan1 | I/O pad placement constraint file |

### Floorplan Variables

| Variable | Expected Value | Description |
|----------|---------------|-------------|
| `fp(fp,core_utilization)` | `"0.7"` (float string) | Target core area utilization |
| `fp(fp,aspect_ratio)` | `"1.0"` (float string) | Core aspect ratio |
| `fp(fp,core_offset)` | String (microns) | Core-to-die offset |

---

## ECO Flow

### Stages

```
init_design1 → eco_implement1 → eco_route1 → signoff1 → export_data1 → release_data1
```

The ECO flow implements engineering change orders on a post-route database. All variables use the `eco()` array.

### Input Variables

| Variable | Expected Value | Stage | Description |
|----------|---------------|-------|-------------|
| `eco(input,netlist)` | File path (string) | init_design1 | Current gate-level netlist |
| `eco(input,def_file)` | File path (string) | init_design1 | Current physical DEF |
| `eco(input,sdc_func_file)` | File path (string) | init_design1 | Timing constraints |
| `eco(input,change_file)` | File path (string) | eco_implement1 | ECO change specification file (netlist diff or script) |
| `eco(input,reference_database)` | Directory path (string) | eco_implement1 | Reference database for ECO comparison |

### ECO Implementation Variables

| Variable | Expected Value | Description |
|----------|---------------|-------------|
| `eco(eco,mode)` | `"freeze_silicon"` \| `"spare_cell"` \| `"metal_only"` | ECO implementation strategy |
| `eco(eco,max_displace)` | String (microns) | Maximum cell displacement for ECO placement |
| `eco(eco,opt_active_scenarios)` | List (string) | Active scenarios during ECO optimization |

### Signoff Variables

| Variable | Expected Value | Description |
|----------|---------------|-------------|
| `eco(signoff,active_scenarios)` | List (string) | Active scenarios for post-ECO signoff |
| `eco(signoff,insert_filler)` | `"true"` | Re-insert fillers after ECO |

### Export Variables

| Variable | Expected Value | Description |
|----------|---------------|-------------|
| `eco(export_data,write_gds)` | `"true"` | Write updated GDS |
| `eco(export_data,write_oasis)` | `"false"` | Write updated OASIS |

---

## Variable Naming Conventions

All CBflow variables follow a consistent naming pattern:

```
<flow_array>(<category>,<sub_category>,<variable_name>)
```

### Categories

| Category | Description |
|----------|-------------|
| `input` | Design inputs (files, paths, references) |
| `common` | Variables shared across multiple stages |
| `fp` | Floorplan-specific settings |
| `synthesis` | Synthesis stage settings |
| `place` | Placement stage settings |
| `cts` | Clock tree synthesis settings |
| `route` | Routing stage settings |
| `pro` | Post-route optimization settings |
| `signoff` | Signoff stage settings |
| `export_data` | Data export settings |
| `mmmc` | Multi-mode multi-corner configuration |
| `analysis` | Analysis/reporting settings |
| `tool` | Tool-specific runtime settings |

### Value Types

| Type | Format | Examples |
|------|--------|----------|
| Boolean | `"true"` / `"false"` | `synth_pnr(signoff,insert_filler)` |
| String | Quoted string | `synth_pnr(common,design_name)` |
| Integer | Unquoted number | `sta(analysis,max_paths)` |
| Float string | Quoted decimal | `synth_pnr(pro,endpoint_opt,slack_threshold)` |
| File path | Absolute or relative path | `synth_pnr(input,rtl_filelist)` |
| List | Space-separated TCL list | `synth_pnr(synthesis,compile,active_scenarios)` |
| Enum | One of listed values | `synth_pnr(common,compile,qor_mode)` |

---

## Config Cascade Resolution Order

Variables are resolved in the following order (later overrides earlier):

1. `project_init` - Project initialization defaults
2. `project` - Project-level settings
3. `team` - Team-specific overrides
4. `tech` - Technology node settings
5. `flow` - Flow-level configuration
6. `node_common` - Flow-specific common node config
7. `node_tool` - Tool-specific node config
8. `mmmc` - MMMC auto-generated scenarios
9. `user` - User-level overrides (`user_config.tcl`)
10. `overrides` - Per-node override config (`override_config.<node>.tcl`)

---

## Notes

- All variables are mandatory unless documented otherwise. Missing variables will cause a runtime error with a clear message.
- No hardcoded defaults exist in the engine. All values must be explicitly set in the config cascade.
- Per-node scenario overrides can be applied via `override_config.<node>.tcl` in the run directory.
- MMMC scenarios are auto-generated from PVT building blocks defined in `mmmc_config.tcl`.
- Pre/post scripts are optional file paths; if not set, the corresponding hook is skipped.
