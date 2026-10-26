# CBflow Flow Procedures Reference

## Overview

`flow_procs` are registered steps within each stage command file. They represent discrete, named design operations that execute sequentially in definition order via `flow_exec_all`. Each flow_proc encapsulates a single logical operation (e.g., reading a design, running placement, generating reports).

### Key Concepts

- **Registration**: Each flow_proc is registered with `flow_proc_register` in the stage command file
- **Execution**: All registered flow_procs execute in order via `flow_exec_all`
- **Hooks**: Users can add `prepend`/`append` hooks to any flow_proc for customization without modifying source
- **Skip**: Individual flow_procs can be skipped via `flow_proc_skip` in user config
- **Logging**: Each flow_proc execution is logged with start/end timestamps and status

### Hook Mechanism

```tcl
# In user_config or override_config:
flow_proc_prepend "run_compile" {
    # Custom commands before compile
    set_app_options -name compile.flow.enable_multithreading -value true
}

flow_proc_append "generate_reports" {
    # Additional custom reports after standard reports
    report_power -scenarios [all_scenarios] > custom_power.rpt
}
```

---

## SYNTH_PNR Flow -- Fusion Compiler (FC)

The SYNTH_PNR flow combines synthesis and physical implementation into a unified Fusion Compiler flow. It consists of 9 stages executed sequentially, each containing multiple flow_procs.

---

### init_design_fc.tcl (19 flow_procs)

The init_design stage establishes the design environment: creates libraries, reads RTL, sets up the floorplan, configures MCMM scenarios, and prepares the design for synthesis.

| # | flow_proc | Purpose | Key FC Commands | When to Customize |
|---|-----------|---------|-----------------|-------------------|
| 1 | create_design_library | Creates NDM design library with technology and reference libs | `create_lib`, `create_fusion_reference_library` | Add custom reference libraries |
| 2 | read_design | Reads RTL (Verilog/SystemVerilog), elaborates top module, links design | `read_verilog`, `read_sverilog`, `elaborate`, `link_block` | Change RTL format or elaborate options |
| 3 | setup_technology | Sets technology node, sources tech setup script, reads physical routing rules | `set_technology`, `read_physical_rules` | Custom routing rules or layer modifications |
| 4 | load_floorplan | Loads floorplan from TCL script or DEF file, resolves PG net names | `read_def`, `source`, `resolve_pg_nets` | Custom floorplan scripts or partial DEF |
| 5 | initialize_floorplan | Initializes floorplan if no existing one loaded (utilization, aspect ratio, core offset) | `initialize_floorplan` | Override default utilization/aspect ratio |
| 6 | insert_physical_cells | Inserts tap cells, endcap cells, power switches, boundary cells, spare cells | `create_tap_cells`, `compile_boundary_cells` | Custom spare cell scripts or tap spacing |
| 7 | setup_design_checks | Uniquifies design hierarchy, checks for port mismatches, removes duplicate logic | `uniquify`, `check_design` | Usually not customized |
| 8 | setup_mcmm | Creates full MCMM setup: modes from operating_modes, corners from analysis_views, scenarios from PVT matrix, loads UPF power intent | `create_mode`, `create_corner`, `create_scenario`, `load_upf` | Add modes/corners or custom scenario filtering |
| 9 | setup_timing_variations | Configures POCV/AOCV/OCV timing derating for statistical timing analysis | `set_app_options` (timing.ocv.*) | Switch between OCV/AOCV/POCV modes |
| 10 | setup_lib_cell_purpose | Sets dont_use, CTS-only, hold-only, size-only cell restrictions from tech config | `set_lib_cell_purpose` | Custom cell restrictions per design |
| 11 | setup_clock_ndr | Establishes clock NDR (non-default routing) rules and via ladder definitions | `source` (CTS NDR file) | Custom clock routing rules or shielding |
| 12 | setup_placement_constraints | Sources placement constraint files for cell spacing, keepouts, abutment rules | `source` (placement constraint files) | Custom spacing/abutment/blockage rules |
| 13 | setup_power_activity | Sets SAIF-based switching activity for power-driven optimization | `read_saif`, `saif_map` | Custom switching activity or toggle rates |
| 14 | setup_dft | Loads DFT port configuration and test mode setup | `source` (DFT config) | DFT port customization or scan config |
| 15 | connect_power_ground | Connects PG nets automatically or via user-provided script | `connect_pg_net` | Custom PG connections for multi-supply |
| 16 | set_qor_strategy_init | Sets initial QoR strategy targeting timing/area/power balance | `set_qor_strategy` | Change optimization priority for init |
| 17 | run_floorplan_checks | Validates floorplan rules: overlap, boundary, connectivity | `check_floorplan_rules` | Add custom floorplan validation rules |
| 18 | save_design | Saves UPF, library, block with labeling for downstream stages | `save_upf`, `save_lib`, `save_block` | Usually not customized |
| 19 | generate_reports | Generates QoR, timing, design, utilization, and constraint reports | `report_qor`, `report_timing`, `report_design`, `report_utilization` | Custom report paths or additional reports |

---

### synthesis_fc.tcl (11 flow_procs)

The synthesis stage performs logic compilation: maps RTL to gates, optimizes for timing/area/power, and performs initial placement within the Fusion Compiler unified flow.

| # | flow_proc | Purpose | Key FC Commands | When to Customize |
|---|-----------|---------|-----------------|-------------------|
| 1 | load_design | Opens library, copies block from init_design label, links for synthesis | `open_lib`, `copy_block`, `link_block` | Usually not customized |
| 2 | set_active_scenarios | Activates synthesis-relevant scenarios (typically setup corners) | `set_scenario_status` | Override scenario selection for synthesis |
| 3 | set_qor_strategy | Applies QoR strategy targeting timing/power/area metric with ignored layers | `set_qor_strategy`, `set_ignored_layers` | Change optimization target or layer constraints |
| 4 | configure_compile | Sets cell prefix, cell purpose, multi-Vt optimization, CTS reference corner | `set_app_options` (compile.*) | Multi-Vt strategy or cell naming |
| 5 | pre_compile_setup | SVF setup, pre-compile script, test model insertion, MV cell creation, spare cell marking, clock tree marking | `set_svf`, `create_mv_cells`, `mark_clock_trees` | Add pre-compile ECO or custom constraints |
| 6 | run_compile | Main compile execution: unified `compile_fusion` or staged flow (pre_map, map, logic_opto, dft_insertion, place, drc_fix, opto, final_opto) | `compile_fusion` | Customize compile strategy or passes |
| 7 | post_compile | Post-compile script, spare cell connection, PG net reconnection | `source` (post-script), `connect_pg_net` | Post-compile fixes or spare cell wiring |
| 8 | finalize_netlist | Applies name rules, writes ASCII output files, generates SAIF mapping | `define_name_rules`, `write_ascii_files` | Custom naming conventions |
| 9 | create_abstracts | Creates abstract and frame views for hierarchical integration | `create_abstract`, `create_frame` | Usually for hierarchical flows only |
| 10 | save_design | Saves UPF, SSF (scan stitching), block with compile label | `save_upf`, `save_block` | Usually not customized |
| 11 | generate_reports | QoR summary, timing (setup/hold), power, congestion, multi-Vt distribution | `report_qor`, `report_timing`, `report_power`, `report_congestion` | Custom report formats or thresholds |

---

### place_fc.tcl (9 flow_procs)

The placement stage performs detailed cell placement optimization: legalizes cells, optimizes timing through placement, and prepares the design for clock tree synthesis.

| # | flow_proc | Purpose | Key FC Commands | When to Customize |
|---|-----------|---------|-----------------|-------------------|
| 1 | load_design | Opens library, copies block from compile label, links | `open_lib`, `copy_block`, `link_block` | Usually not customized |
| 2 | set_active_scenarios | Activates placement scenarios (setup + congestion corners) | `set_scenario_status` | Custom scenario weighting for placement |
| 3 | set_qor_strategy | Applies QoR strategy for placement optimization phase | `set_qor_strategy` | Adjust congestion vs timing priority |
| 4 | configure_place_opt | Sets cell prefix, freezes IO ports, marks ideal clocks, configures SPG | `set_app_options`, `set_freeze_port` | Custom placement constraints or SPG mode |
| 5 | run_place_opt | Placement optimization: SPG mode or two-pass flow (initial placement, DRC fix, incremental, final) | `place_opt` | Customize placement passes or effort |
| 6 | post_place_opt | Post-placement script, spare cell tie-off, PG reconnection | `source` (post-script), `connect_pg_net` | Post-place scan reorder or spare cells |
| 7 | create_abstracts | Creates abstract view for hierarchical timing budgeting | `create_abstract` | Hierarchical flows only |
| 8 | save_design | Saves block with place_opt label | `save_block` | Usually not customized |
| 9 | generate_reports | Timing (setup/hold), QoR, congestion maps, legality checks | `report_timing`, `report_qor`, `check_legality` | Custom congestion thresholds |

---

### cts_fc.tcl (10 flow_procs)

The CTS (Clock Tree Synthesis) stage builds balanced clock distribution networks, routes clock nets, and performs initial clock-aware optimization.

| # | flow_proc | Purpose | Key FC Commands | When to Customize |
|---|-----------|---------|-----------------|-------------------|
| 1 | load_design | Opens library, copies block from place_opt label | `open_lib`, `copy_block` | Usually not customized |
| 2 | set_active_scenarios | Activates CTS scenarios (emphasizes hold corners for CCD optimization) | `set_scenario_status` | Custom hold scenario emphasis |
| 3 | set_qor_strategy | Applies QoR strategy for clock tree building phase | `set_qor_strategy` | Skew vs power optimization target |
| 4 | configure_cts | CTS sidefile, NDR application, antenna rules, MSCTS mesh clock configuration | `set_app_options` (cts.*), `process_antenna_rules` | Custom CTS specs or mesh clocks |
| 5 | build_clock_trees | Builds clock trees: buffer/inverter insertion, balancing, CCD skew scheduling | `clock_opt` (build_clock phase) | Rarely customized directly |
| 6 | route_clock_nets | Routes clock nets with NDR rules, shielding, via optimization | `clock_opt` (route_clock phase) | Custom clock routing layers |
| 7 | post_cts_optimization | Redundant via insertion on clock nets, AOCV update, shield insertion | `add_redundant_vias`, `create_shields` | Custom shield rules or via patterns |
| 8 | connect_power_ground | PG reconnection after CTS, route integrity check | `connect_pg_net`, `check_routes` | Usually not customized |
| 9 | save_design | Saves block with clock_opt_cts label | `save_block` | Usually not customized |
| 10 | generate_reports | Clock tree QoR, timing, skew distribution, power consumption | `report_clock_qor`, `report_clock_timing`, `report_power` | Custom clock group reports |

---

### cts_opt_fc.tcl (8 flow_procs)

The CTS optimization stage performs post-clock-tree timing optimization: fixes setup/hold violations with real clock propagation, applies global route estimation.

| # | flow_proc | Purpose | Key FC Commands | When to Customize |
|---|-----------|---------|-----------------|-------------------|
| 1 | load_design | Opens library, copies block from clock_opt_cts label | `open_lib`, `copy_block` | Usually not customized |
| 2 | set_active_scenarios | Activates post-CTS scenarios, propagates all clocks for real timing | `set_scenario_status` | Custom scenario propagation |
| 3 | set_qor_strategy | Applies QoR strategy for post-CTS optimization, enables GRE (Global Route Estimation) | `set_qor_strategy` | Adjust GRE accuracy vs runtime |
| 4 | configure_opto | IRDP (IR-aware dynamic power) settings, cell purpose for hold fixing, sidefile | `set_app_options` (clock_opt.opto.*) | Custom hold cell library or IRDP config |
| 5 | run_clock_opt_opto | Post-CTS timing optimization: hold fixing, setup recovery, CCD refinement | `clock_opt` (final_opto phase) | Rarely customized directly |
| 6 | post_opto | Post-optimization script, PG reconnection | `source` (post-script), `connect_pg_net` | Post-CTS ECO or constraint updates |
| 7 | save_design | Saves block with clock_opt_opto label | `save_block` | Usually not customized |
| 8 | generate_reports | Timing (setup+hold), clock QoR, power with real clocks | `report_timing`, `report_clock_qor`, `report_power` | Custom slack histogram reports |

---

### route_fc.tcl (10 flow_procs)

The routing stage performs global and detailed signal routing, applies antenna fixes, and sets up parasitic extraction for post-route timing analysis.

| # | flow_proc | Purpose | Key FC Commands | When to Customize |
|---|-----------|---------|-----------------|-------------------|
| 1 | load_design | Opens library, copies block from clock_opt_opto label | `open_lib`, `copy_block` | Usually not customized |
| 2 | set_active_scenarios | Activates routing scenarios (all corners for DRC convergence) | `set_scenario_status` | Custom scenario subset for routing |
| 3 | set_qor_strategy | Applies QoR strategy for routing phase, sets routing effort | `set_qor_strategy` | Adjust routing effort vs convergence |
| 4 | configure_route | Layer constraints, min/max layers, antenna rule processing, routing sidefile | `set_ignored_layers`, `process_antenna_rules` | Custom layer restrictions or via rules |
| 5 | run_route_auto | Global routing, track assignment, detailed routing + initial route_opt for DRC | `route_auto`, `route_opt` | Custom routing passes or effort |
| 6 | post_route_auto | Redundant via insertion, shield creation, post-route script | `add_redundant_vias`, `create_shields` | Custom via rules or post-route fixes |
| 7 | setup_starrc_extraction | Configures StarRC in-design parasitic extraction (nxtgrd/TLU+) | `set_starrc_in_design` | Custom extraction settings or corners |
| 8 | setup_virtual_metal_fill | Enables virtual metal fill for accurate capacitance estimation | `set_extraction_options` | Custom fill density or rules |
| 9 | save_design | Saves block with route_auto label | `save_block` | Usually not customized |
| 10 | generate_reports | Timing with parasitics, routing DRC, congestion, SI, power | `report_timing`, `check_routes`, `report_power` | Custom DRC waiver reports |

---

### pro_fc.tcl (8 flow_procs)

The post-route optimization (PRO) stage performs timing closure with extracted parasitics: fixes setup/hold with real RC, applies SI-aware optimization, and achieves final timing targets.

| # | flow_proc | Purpose | Key FC Commands | When to Customize |
|---|-----------|---------|-----------------|-------------------|
| 1 | load_design | Opens library, copies block from route_auto label | `open_lib`, `copy_block` | Usually not customized |
| 2 | set_active_scenarios | Activates post-route optimization scenarios (all signoff corners) | `set_scenario_status` | Custom scenario prioritization |
| 3 | set_qor_strategy | Applies QoR strategy for post-route phase, enables SI optimization | `set_qor_strategy` | Adjust SI effort or timing targets |
| 4 | configure_route_opt | Extraction mode (StarRC/virtual), VMF settings, PBA mode, IRD-CCD | `set_starrc_in_design`, `set_app_options` | Custom PBA settings or extraction |
| 5 | run_route_opt | Post-route timing optimization: `hyper_route_opt` or iterative `route_opt` with PBA and IRD-CCD | `hyper_route_opt`, `route_opt` | Customize iteration count or PBA mode |
| 6 | post_route_opt | Redundant via insertion, DRC fix routing, FuSa tap insertion | `add_redundant_vias`, `route_detail` | Custom via patterns or DRC waivers |
| 7 | run_endpoint_opt | Targeted PBA-CCD endpoint optimization for remaining violators (optional, controlled by config) | `targeted_ep_ropt_pba_ccd` | Enable/disable or set endpoint list |
| 8 | generate_reports | Final timing with SI crosstalk, QoR summary, power, DRC status | `report_timing -crosstalk_delta`, `report_qor`, `report_power` | Custom signoff-quality reports |

---

### signoff_fc.tcl (8 flow_procs)

The signoff stage performs final physical verification: inserts filler/decap cells, runs in-design DRC with ICV, creates metal fill, and produces final signoff-quality checks.

| # | flow_proc | Purpose | Key FC Commands | When to Customize |
|---|-----------|---------|-----------------|-------------------|
| 1 | load_design | Opens library, copies block from route_opt label | `open_lib`, `copy_block` | Usually not customized |
| 2 | set_active_scenarios | Activates all signoff scenarios for final verification | `set_scenario_status` | Usually all scenarios active |
| 3 | insert_filler_cells | Inserts stdcell fillers and decap cells using foundry-provided sidefile | `create_stdcell_fillers` | Custom filler sizing or decap strategy |
| 4 | fix_signal_em | Signal electromigration analysis: reads EM constraints, optionally fixes violations | `read_signal_em_constraints`, `fix_signal_em` | Enable/disable EM fixing or set limits |
| 5 | run_signoff_drc | ICV in-design signoff DRC check, auto-fix DRC violations, insert antenna diodes | `signoff_check_drc`, `signoff_fix_drc` | Custom DRC runset or waiver rules |
| 6 | create_metal_fill | Metal fill insertion: runset-based (ICV) or track-based fill | `signoff_create_metal_fill` | Custom fill density or exclusion regions |
| 7 | post_signoff | Post-signoff script, final PG connection, route integrity verification | `connect_pg_net`, `check_routes` | Final custom checks or fixes |
| 8 | generate_reports | Final signoff reports: timing, DRC summary, legality, SI, LVS-ready status, power | `signoff_check_drc`, `check_legality`, `report_timing`, `report_power` | Custom signoff criteria reports |

---

### export_data_fc.tcl (9 flow_procs)

The export stage generates all deliverable output files: multiple netlist variants, physical data (GDS/OASIS/DEF), parasitics (SPEF), constraints (SDC), and power intent (UPF).

| # | flow_proc | Purpose | Key FC Commands | When to Customize |
|---|-----------|---------|-----------------|-------------------|
| 1 | load_design | Opens library, copies block from chip_finish (signoff) label | `open_lib`, `copy_block` | Usually not customized |
| 2 | change_names | Applies Verilog naming rules to ensure tool-compatible net/cell names | `define_name_rules`, `change_names` | Custom naming for specific tools |
| 3 | write_netlist | Writes 6 netlist variants: logic (generic), DC (synthesis), PT (timing), FM (formal), LVS (physical), VC_LP (low-power) | `write_verilog` (with different options per variant) | Add custom netlist variants |
| 4 | write_gds_output | Exports GDS-II, OASIS, and LEF (abstract) physical data | `write_gds`, `write_oasis`, `write_lef` | Custom layer mapping or GDS merge |
| 5 | write_def_output | Exports DEF (full and incremental) and floorplan TCL | `write_def`, `write_floorplan` | Custom DEF version or sections |
| 6 | write_parasitics_output | Exports SPEF parasitic data per corner for STA handoff | `write_parasitics` | Custom SPEF precision or corners |
| 7 | write_sdc_output | Exports SDC per scenario, routing constraints, FC/PT tool scripts | `write_sdc`, `write_script` | Custom SDC filtering or clock groups |
| 8 | write_upf_output | Exports UPF power intent, SAIF activity maps, SSF scan data | `save_upf`, `saif_map` | Custom UPF version or scope |
| 9 | generate_reports | Final QoR snapshot capturing design metrics at export | `report_qor` | Custom metrics for tracking |

---

## SYNTH_PNR Flow -- Innovus (Cadence)

The Innovus-based SYNTH_PNR flow uses Genus for synthesis and Innovus for physical implementation.

---

### init_design_innovus.tcl (14 flow_procs)

| # | flow_proc | Purpose | Key Innovus Commands | When to Customize |
|---|-----------|---------|---------------------|-------------------|
| 1 | set_threading | Configure CPU threading for parallel operations | `set_multi_cpu_usage` | Adjust CPU count per job |
| 2 | read_physical_data | Read LEF files (tech LEF + cell LEFs) | `read_lef` | Add custom LEF libraries |
| 3 | read_design | Read gate-level netlist, set top module | `read_verilog`, `set_top_module` | Custom netlist format |
| 4 | read_power_intent | Read UPF/CPF power intent | `read_power_intent` | Custom power domain setup |
| 5 | setup_mmmc | Create library sets, RC corners, delay corners, constraint modes, analysis views | `create_library_set`, `create_rc_corner`, `create_delay_corner`, `create_constraint_mode`, `create_analysis_view` | Add views or custom MMMC |
| 6 | load_floorplan | Read floorplan DEF or Innovus floorplan file | `read_def`, `load_floorplan` | Custom floorplan source |
| 7 | setup_power_grid | Define power grid: rings, stripes, vias | `add_rings`, `add_stripes`, `add_special_route` | Custom PG topology |
| 8 | insert_physical_cells | Insert endcaps, tapcells, tie cells | `add_endcap`, `add_well_tap` | Custom cell spacing |
| 9 | setup_timing | Set analysis mode, propagate clocks, OCV settings | `set_analysis_mode`, `set_propagated_clock` | Custom OCV/AOCV setup |
| 10 | setup_lib_cell_purpose | Set dont_use, size_only, clock_only attributes | `set_dont_use`, `set_dont_touch` | Custom cell restrictions |
| 11 | connect_global_nets | Connect VDD/VSS global nets to pins | `connect_global_net` | Multi-supply connections |
| 12 | run_floorplan_checks | Check placement blockages, pin access, routing tracks | `check_floorplan` | Custom DRC rules |
| 13 | save_design | Save design database | `save_design` | Usually not customized |
| 14 | generate_reports | Design summary, floorplan utilization | `report_design_summary` | Custom reports |

---

### place_innovus.tcl (9 flow_procs)

| # | flow_proc | Purpose | Key Innovus Commands | When to Customize |
|---|-----------|---------|---------------------|-------------------|
| 1 | load_design | Restore design from init_design | `restore_design` | Usually not customized |
| 2 | set_active_scenarios | Set active analysis views for placement | `set_analysis_view` | Custom view selection |
| 3 | configure_place | Place mode, density target, congestion effort | `set_place_mode` | Custom density/effort |
| 4 | run_place_design | Execute placement: global + detailed + optimization | `place_design` | Custom placement mode |
| 5 | run_in_place_opt | In-place timing optimization | `opt_design -pre_cts` | Custom optimization effort |
| 6 | post_place | Post-placement script, tie cell insertion | `source`, `add_tieoffs` | Custom post-place fixes |
| 7 | connect_global_nets | Reconnect global nets after placement changes | `connect_global_net` | Usually not customized |
| 8 | save_design | Save placed design | `save_design` | Usually not customized |
| 9 | generate_reports | Timing, congestion, density reports | `report_timing`, `report_congestion` | Custom reports |

---

### cts_innovus.tcl (9 flow_procs)

| # | flow_proc | Purpose | Key Innovus Commands | When to Customize |
|---|-----------|---------|---------------------|-------------------|
| 1 | load_design | Restore design from placement | `restore_design` | Usually not customized |
| 2 | set_active_scenarios | Set views for CTS (hold emphasis) | `set_analysis_view` | Custom hold corners |
| 3 | configure_cts | CTS spec file, buffer/inverter lists, max skew targets | `set_ccopt_mode`, `create_ccopt_clock_tree_spec` | Custom CTS specs |
| 4 | run_ccopt | Execute CComOpt clock tree synthesis and optimization | `ccopt_design` | Custom CTS effort |
| 5 | run_post_cts_opt | Post-CTS timing optimization with propagated clocks | `opt_design -post_cts` | Custom hold fixing |
| 6 | post_cts | Post-CTS script, useful skew adjustment | `source` | Custom clock tweaks |
| 7 | connect_global_nets | Reconnect global nets after CTS buffer insertion | `connect_global_net` | Usually not customized |
| 8 | save_design | Save CTS design | `save_design` | Usually not customized |
| 9 | generate_reports | Clock tree QoR, skew, timing, power | `report_ccopt_clock_trees`, `report_timing` | Custom clock reports |

---

### route_innovus.tcl (9 flow_procs)

| # | flow_proc | Purpose | Key Innovus Commands | When to Customize |
|---|-----------|---------|---------------------|-------------------|
| 1 | load_design | Restore design from CTS | `restore_design` | Usually not customized |
| 2 | set_active_scenarios | Set views for routing (all corners) | `set_analysis_view` | Custom scenario subset |
| 3 | configure_route | Routing mode, layer constraints, via optimization, antenna | `set_route_mode`, `set_nanoroute_mode` | Custom layer/via rules |
| 4 | run_route_design | Execute global + detailed routing | `route_design` | Custom routing effort |
| 5 | run_post_route_opt | Post-route timing and SI optimization | `opt_design -post_route` | Custom SI settings |
| 6 | add_redundant_vias | Insert redundant vias for yield improvement | `add_redundant_vias` | Custom via rules |
| 7 | post_route | Post-route script, filler insertion | `source` | Custom post-route fixes |
| 8 | save_design | Save routed design | `save_design` | Usually not customized |
| 9 | generate_reports | Timing, DRC, connectivity, SI, power | `report_timing`, `verify_drc` | Custom DRC waivers |

---

### signoff_innovus.tcl (7 flow_procs)

| # | flow_proc | Purpose | Key Innovus Commands | When to Customize |
|---|-----------|---------|---------------------|-------------------|
| 1 | load_design | Restore design from routing | `restore_design` | Usually not customized |
| 2 | insert_filler_cells | Insert filler and decap cells | `add_fillers` | Custom filler strategy |
| 3 | run_signoff_drc | Run Calibre/ICV DRC from within Innovus | `verify_drc` | Custom DRC deck |
| 4 | create_metal_fill | Insert metal fill for density | `add_metal_fill` | Custom fill rules |
| 5 | post_signoff | Post-signoff fixes and verification | `source`, `verify_connectivity` | Custom checks |
| 6 | save_design | Save final design | `save_design` | Usually not customized |
| 7 | generate_reports | Final DRC, LVS-readiness, timing, power | `verify_drc`, `report_timing` | Custom signoff reports |

---

### export_data_innovus.tcl (8 flow_procs)

| # | flow_proc | Purpose | Key Innovus Commands | When to Customize |
|---|-----------|---------|---------------------|-------------------|
| 1 | load_design | Restore final design | `restore_design` | Usually not customized |
| 2 | change_names | Apply naming rules for downstream tools | `set_name_rule`, `change_names` | Custom naming conventions |
| 3 | write_netlist | Write Verilog netlists (multiple variants) | `write_netlist` | Custom netlist options |
| 4 | write_gds_output | Write GDS-II with layer mapping | `write_stream` | Custom stream mapping |
| 5 | write_def_output | Write DEF for LVS/DRC | `write_def` | Custom DEF sections |
| 6 | write_parasitics_output | Write SPEF per corner | `write_spef` | Custom RC corners |
| 7 | write_sdc_output | Write SDC per analysis view | `write_sdc` | Custom SDC options |
| 8 | generate_reports | Final export summary | `report_design_summary` | Usually not customized |

---

## STA Flow -- PrimeTime (PT)

The STA flow executes timing analysis per scenario as parallel subnodes. Each scenario (mode x corner x PVT) runs independently with its own timing_scenario command file.

---

### timing_scenario_pt.tcl (7 flow_procs)

Each scenario subnode (e.g., `timing1_func_ss_0p76v_rcmax_150c`) executes these flow_procs independently:

| # | flow_proc | Purpose | Key PT Commands | When to Customize |
|---|-----------|---------|-----------------|-------------------|
| 1 | read_libraries | Reads timing libraries (.db) for this specific PVT corner | `read_lib` | Custom library paths or CCS vs NLDM |
| 2 | read_design | Reads gate-level netlist, links top design | `read_verilog`, `link_design` | Custom netlist or black-box modules |
| 3 | read_constraints | Reads SDC timing constraints for this operating mode | `read_sdc` | Custom SDC per mode or exceptions |
| 4 | read_parasitics | Reads SPEF parasitic data for this RC corner | `read_parasitics` | Custom SPEF mapping or reduced models |
| 5 | setup_analysis | Configures OCV/AOCV/POCV derating, SI crosstalk settings, operating conditions | `set_operating_conditions`, `set_timing_derate` | Custom derating tables or SI severity |
| 6 | run_timing | Updates timing graph, runs PBA/EPBA exhaustive analysis | `update_timing`, `report_timing` (PBA) | Enable/disable PBA or set path count |
| 7 | generate_reports | Generates timing (setup/hold), constraint violations, clock, power reports | `report_timing`, `report_constraint`, `report_clock_timing`, `report_power` | Custom report formats or thresholds |

---

## STA Flow -- Tempus (Cadence)

The Tempus-based STA flow provides equivalent per-scenario timing analysis using Cadence infrastructure.

---

### timing_scenario_tempus.tcl (11 flow_procs)

| # | flow_proc | Purpose | Key Tempus Commands | When to Customize |
|---|-----------|---------|---------------------|-------------------|
| 1 | set_threading | Configure multi-CPU threading for timing analysis | `set_multi_cpu_usage` | Adjust CPU allocation |
| 2 | read_libraries | Read timing libraries (.lib) for this PVT corner | `read_lib` | Custom library format or paths |
| 3 | read_physical_data | Read LEF for physical-aware timing | `read_lef` | Custom LEF for extraction |
| 4 | read_design | Read gate-level netlist, set top module for analysis | `read_verilog`, `set_top_module` | Custom netlist or partitions |
| 5 | setup_mmmc | Create full MMMC: library_set, rc_corner, delay_corner, constraint_mode, analysis_view for this scenario | `create_library_set`, `create_rc_corner`, `create_delay_corner`, `create_constraint_mode`, `create_analysis_view` | Custom delay calculation mode |
| 6 | read_parasitics | Read SPEF parasitic data for this RC corner | `read_spef` | Custom SPEF format or reduced model |
| 7 | setup_si | Configure signal integrity / crosstalk analysis: SI-aware delay, glitch analysis | `set_delay_cal_mode -siAware`, `set_si_mode` | Custom SI aggressors or filtering |
| 8 | setup_pba | Configure path-based analysis: PBA/EPBA modes and exhaustive settings | `set_global timing_pba_*` | Custom PBA depth or path count |
| 9 | run_timing_update | Execute full timing update with current settings | `update_timing -full` | Custom incremental vs full update |
| 10 | generate_reports | Generate setup/hold timing, EPBA, QoR summary, clock timing reports | `report_timing`, `report_qor`, `report_clock_timing` | Custom slack groups or formats |
| 11 | generate_summary | Generate cross-corner summary aggregating worst slack across all scenarios | Custom aggregation proc | Custom summary metrics |

---

## LEC Flow -- Formality (Synopsys)

The LEC (Logic Equivalence Checking) flow verifies that the implementation netlist is functionally equivalent to the reference (golden) netlist.

---

### verify_formality.tcl (5 flow_procs)

| # | flow_proc | Purpose | Key Formality Commands | When to Customize |
|---|-----------|---------|------------------------|-------------------|
| 1 | read_golden | Read golden reference netlist into reference container | `read_verilog -container r`, `set_reference_design` | Custom golden source (RTL or gate) |
| 2 | read_revised | Read revised implementation netlist into implementation container | `read_verilog -container i`, `set_implementation_design` | Custom implementation source |
| 3 | setup_matching | Configure point matching strategy: name-based, signature-based, or hybrid | `set_reference_design`, `set_implementation_design`, `match` | Custom matching rules or black-boxes |
| 4 | run_verification | Execute formal equivalence verification | `verify` | Custom effort or abort limits |
| 5 | generate_reports | Generate equivalence status, failing points, unmatched points reports | `report_verification`, `report_unmatched_points` | Custom diagnosis depth |

---

## LEC Flow -- Conformal (Cadence)

---

### verify_conformal.tcl (5 flow_procs)

| # | flow_proc | Purpose | Key Conformal Commands | When to Customize |
|---|-----------|---------|------------------------|-------------------|
| 1 | read_golden | Read golden reference design | `read_design -golden` | Custom golden format |
| 2 | read_revised | Read revised implementation design | `read_design -revised` | Custom revised format |
| 3 | setup_matching | Configure mapping and matching rules | `set_mapping_method`, `map_key_points` | Custom mapping strategy |
| 4 | run_verification | Run formal comparison | `compare` | Custom comparison mode |
| 5 | generate_reports | Report equivalence results and diagnosis | `report_compare`, `diagnose` | Custom failing point analysis |

---

## PV Flow -- ICV (Synopsys)

The Physical Verification flow runs DRC, LVS, ERC, and PERC checks using ICV. Stages execute in parallel after metal fill insertion.

---

### fill_icv.tcl (3 flow_procs)

| # | flow_proc | Purpose | Key ICV Commands | When to Customize |
|---|-----------|---------|------------------|-------------------|
| 1 | setup_fill | Configure fill runset, input GDS/OASIS, layer mapping | `icv` setup options | Custom fill density rules |
| 2 | run_metal_fill | Execute FEOL + BEOL metal fill generation | `icv -runset <fill_runset>` | Custom fill exclusion regions |
| 3 | generate_reports | Fill density reports per layer | density analysis | Custom density targets |

---

### drc_icv.tcl (3 flow_procs)

| # | flow_proc | Purpose | Key ICV Commands | When to Customize |
|---|-----------|---------|------------------|-------------------|
| 1 | setup_drc | Configure DRC runset, input layout, layer mapping | `icv` setup options | Custom DRC deck selection |
| 2 | run_drc_check | Execute Design Rule Check against foundry rules | `icv -runset <drc_runset>` | Custom waivers or rule subsets |
| 3 | generate_reports | DRC violation summary, error database | DRC results parsing | Custom violation categorization |

---

### lvs_icv.tcl (3 flow_procs)

| # | flow_proc | Purpose | Key ICV Commands | When to Customize |
|---|-----------|---------|------------------|-------------------|
| 1 | setup_lvs | Configure LVS runset, source netlist, layout input | `icv` setup options | Custom LVS options or hcells |
| 2 | run_lvs_check | Execute Layout vs Schematic comparison | `icv -runset <lvs_runset>` | Custom device recognition |
| 3 | generate_reports | LVS match/mismatch summary | LVS results parsing | Custom short/open analysis |

---

### erc_icv.tcl (3 flow_procs)

| # | flow_proc | Purpose | Key ICV Commands | When to Customize |
|---|-----------|---------|------------------|-------------------|
| 1 | setup_erc | Configure ERC runset, connectivity rules | `icv` setup options | Custom ERC rule selection |
| 2 | run_erc_check | Execute Electrical Rule Check (floating gates, antenna, well connectivity) | `icv -runset <erc_runset>` | Custom antenna ratios |
| 3 | generate_reports | ERC violation reports | ERC results parsing | Custom severity classification |

---

### perc_icv.tcl (3 flow_procs)

| # | flow_proc | Purpose | Key ICV Commands | When to Customize |
|---|-----------|---------|------------------|-------------------|
| 1 | setup_perc | Configure PERC runset for reliability checks | `icv` setup options | Custom reliability rules |
| 2 | run_perc_check | Execute Parasitic Electrical Rule Check (ESD, latch-up paths) | `icv -runset <perc_runset>` | Custom ESD protection rules |
| 3 | generate_reports | PERC reliability reports | PERC results parsing | Custom ESD path analysis |

---

## PV Flow -- Calibre (Mentor/Siemens)

---

### drc_calibre.tcl (3 flow_procs)

| # | flow_proc | Purpose | Key Calibre Commands | When to Customize |
|---|-----------|---------|----------------------|-------------------|
| 1 | setup_drc | Configure Calibre DRC rule file and inputs | `calibre` setup | Custom rule file selection |
| 2 | run_drc_check | Execute Calibre DRC | `calibre -drc` | Custom rule subsets or waivers |
| 3 | generate_reports | DRC results database and summary | RVE parsing | Custom violation filtering |

---

### lvs_calibre.tcl (3 flow_procs)

| # | flow_proc | Purpose | Key Calibre Commands | When to Customize |
|---|-----------|---------|----------------------|-------------------|
| 1 | setup_lvs | Configure Calibre LVS rule file, source netlist, layout | `calibre` setup | Custom hcells or device params |
| 2 | run_lvs_check | Execute Calibre LVS comparison | `calibre -lvs` | Custom extraction options |
| 3 | generate_reports | LVS comparison results | RVE parsing | Custom mismatch analysis |

---

## EMIR Flow -- RedHawk (Synopsys/ANSYS)

The EMIR flow performs power integrity analysis: static/dynamic IR drop, electromigration, and thermal analysis.

---

### emir_redhawk.tcl (6 flow_procs)

| # | flow_proc | Purpose | Key RedHawk Commands | When to Customize |
|---|-----------|---------|----------------------|-------------------|
| 1 | setup_design | Load design database: DEF, LEF, netlist, power grid definition | `read_def`, `read_verilog`, `setup_power_grid` | Custom power grid topology |
| 2 | run_power_analysis | Vectorless or SAIF-based power analysis per instance | `analyze_power` | Custom activity factors or SAIF |
| 3 | run_ir_drop | Static + dynamic IR drop analysis across power grid | `analyze_rail` | Custom IR limits or bump map |
| 4 | run_em_analysis | Electromigration current density analysis | `analyze_em` | Custom EM limits per technology |
| 5 | run_thermal | Thermal hotspot analysis and temperature map generation | `analyze_thermal` | Custom thermal constraints |
| 6 | generate_reports | Power maps, IR contours, EM violations, thermal reports | `report_power`, `report_rail`, `report_em` | Custom threshold reporting |

---

## EMIR Flow -- Voltus (Cadence)

---

### emir_voltus.tcl (6 flow_procs)

| # | flow_proc | Purpose | Key Voltus Commands | When to Customize |
|---|-----------|---------|---------------------|-------------------|
| 1 | setup_design | Read design (DEF/LEF/netlist), configure power grid | `read_design`, `set_pg_net` | Custom power domain mapping |
| 2 | run_power_analysis | Power analysis with activity propagation | `report_power` | Custom switching scenarios |
| 3 | run_ir_drop | Static and dynamic IR drop computation | `analyze_rail` | Custom voltage thresholds |
| 4 | run_em_analysis | EM lifetime and current density analysis | `analyze_em` | Custom EM rules |
| 5 | run_thermal | Thermal-aware power analysis | `analyze_thermal` | Custom thermal model |
| 6 | generate_reports | IR/EM/thermal violation reports and maps | `report_rail`, `report_em` | Custom map generation |

---

## ECO Flow

The ECO flow supports post-signoff engineering change orders for timing/functional fixes with minimal design disruption.

---

### eco_fc.tcl (7 flow_procs)

| # | flow_proc | Purpose | Key FC Commands | When to Customize |
|---|-----------|---------|-----------------|-------------------|
| 1 | load_design | Open design at signoff state | `open_lib`, `open_block` | Usually not customized |
| 2 | read_eco_changes | Read ECO change list (functional or timing) | `source` (ECO script), `eco_netlist` | Custom ECO source format |
| 3 | place_eco_cells | Place newly added ECO cells with minimal displacement | `place_eco_cells` | Custom placement constraints |
| 4 | route_eco_nets | Route ECO nets incrementally | `route_eco_nets` | Custom routing rules for ECO |
| 5 | run_eco_opt | Post-ECO timing optimization (optional) | `route_opt -eco` | Enable/disable ECO optimization |
| 6 | save_design | Save ECO'd design | `save_block` | Usually not customized |
| 7 | generate_reports | ECO impact: timing delta, DRC, area change | `report_timing`, `check_routes` | Custom ECO impact metrics |

---

## POPT Flow (Post-Route Optimization)

The POPT flow provides standalone post-route optimization for timing closure iterations outside the main flow.

---

### popt_fc.tcl (6 flow_procs)

| # | flow_proc | Purpose | Key FC Commands | When to Customize |
|---|-----------|---------|-----------------|-------------------|
| 1 | load_design | Open design from specified state | `open_lib`, `open_block` | Usually not customized |
| 2 | set_active_scenarios | Activate optimization scenarios | `set_scenario_status` | Custom scenario subset |
| 3 | configure_optimization | Set optimization mode, target endpoints, effort level | `set_app_options` | Custom targets or constraints |
| 4 | run_optimization | Execute targeted or global post-route optimization | `route_opt`, `hyper_route_opt` | Custom iteration strategy |
| 5 | save_design | Save optimized design | `save_block` | Usually not customized |
| 6 | generate_reports | Timing improvement delta, QoR comparison | `report_timing`, `report_qor` | Custom before/after comparison |

---

## CLP Flow (Clock Planning)

---

### clp_fc.tcl (6 flow_procs)

| # | flow_proc | Purpose | Key FC Commands | When to Customize |
|---|-----------|---------|-----------------|-------------------|
| 1 | load_design | Open design with clock definitions | `open_lib`, `open_block` | Usually not customized |
| 2 | setup_clock_planning | Configure clock planning constraints and targets | `set_app_options` (cts.compile.*) | Custom skew budgets |
| 3 | run_clock_estimation | Estimate clock tree topology and resources | `synthesize_clock_trees -estimate` | Custom estimation modes |
| 4 | analyze_clock_structure | Analyze clock network: fanout, depth, skew groups | analysis commands | Custom clock group partitioning |
| 5 | save_design | Save clock planning results | `save_block` | Usually not customized |
| 6 | generate_reports | Clock planning QoR: estimated skew, latency, power | `report_clock_qor` | Custom clock budget reports |

---

## FP Flow (Floorplanning)

---

### fp_fc.tcl (8 flow_procs)

| # | flow_proc | Purpose | Key FC Commands | When to Customize |
|---|-----------|---------|-----------------|-------------------|
| 1 | load_design | Load elaborated design for floorplanning | `open_lib`, `open_block` | Usually not customized |
| 2 | define_die_area | Define die/core area, IO ring, bump map | `initialize_floorplan`, `create_die_area` | Custom die dimensions |
| 3 | place_macros | Place hard macros: memories, IPs, analog blocks | `create_placement_blockage`, `place_macro` | Custom macro placement strategy |
| 4 | create_power_grid | Build power grid: rings, stripes, mesh, vias | `create_pg_ring`, `create_pg_strap` | Custom PG topology per domain |
| 5 | place_io | Place IO pads/bumps according to pin assignment | `place_io`, `read_io_constraints` | Custom IO ordering or bump map |
| 6 | run_floorplan_checks | Validate floorplan: channel width, macro spacing, PG coverage | `check_floorplan_rules` | Custom rule thresholds |
| 7 | save_design | Save floorplan | `save_block` | Usually not customized |
| 8 | generate_reports | Floorplan utilization, macro placement, PG analysis | `report_utilization` | Custom floorplan metrics |

---

## Common Patterns Across All Flows

### Standard flow_proc Structure

Every flow_proc follows this pattern internally:

```tcl
flow_proc_register "<proc_name>" {
    flow_proc_header  ;# Logs start, checks skip conditions

    # --- Main operation ---
    <tool_commands>

    flow_proc_footer  ;# Logs completion, captures metrics
}
```

### Universal flow_procs

These flow_procs appear in nearly every stage across all flows:

| flow_proc | Pattern | Notes |
|-----------|---------|-------|
| load_design | First proc in every stage (except init_design) | Restores design from previous stage label |
| save_design | Second-to-last proc in every stage | Saves with stage-specific label for downstream |
| generate_reports | Last proc in every stage | Captures QoR metrics for tracking/comparison |

### Customization Priority

When customizing flow_procs, prefer this order:

1. **Config variables** -- Set variables in user_config that control flow_proc behavior
2. **Prepend/append hooks** -- Add commands before/after without modifying source
3. **Skip + replace** -- Skip a flow_proc and add your own replacement via hooks
4. **Override command file** -- Last resort: copy and modify the entire command file

---

## Quick Reference: flow_proc Counts by Stage

| Flow | Stage | Tool | flow_procs |
|------|-------|------|-----------|
| SYNTH_PNR | init_design | FC | 19 |
| SYNTH_PNR | synthesis | FC | 11 |
| SYNTH_PNR | place | FC | 9 |
| SYNTH_PNR | cts | FC | 10 |
| SYNTH_PNR | cts_opt | FC | 8 |
| SYNTH_PNR | route | FC | 10 |
| SYNTH_PNR | pro (post-route opt) | FC | 8 |
| SYNTH_PNR | signoff | FC | 8 |
| SYNTH_PNR | export_data | FC | 9 |
| SYNTH_PNR | init_design | Innovus | 14 |
| SYNTH_PNR | place | Innovus | 9 |
| SYNTH_PNR | cts | Innovus | 9 |
| SYNTH_PNR | route | Innovus | 9 |
| SYNTH_PNR | signoff | Innovus | 7 |
| SYNTH_PNR | export_data | Innovus | 8 |
| STA | timing_scenario | PT | 7 |
| STA | timing_scenario | Tempus | 11 |
| LEC | verify | Formality | 5 |
| LEC | verify | Conformal | 5 |
| PV | fill | ICV | 3 |
| PV | drc | ICV | 3 |
| PV | lvs | ICV | 3 |
| PV | erc | ICV | 3 |
| PV | perc | ICV | 3 |
| PV | drc | Calibre | 3 |
| PV | lvs | Calibre | 3 |
| EMIR | emir | RedHawk | 6 |
| EMIR | emir | Voltus | 6 |
| ECO | eco | FC | 7 |
| POPT | popt | FC | 6 |
| CLP | clp | FC | 6 |
| FP | fp | FC | 8 |
| **Total** | | | **~228** |

---

## See Also

- [Stage Variables Reference](Stage_Variables_Reference.md) -- Config variables that control flow_proc behavior
- [MMMC Setup Guide](MMMC_Setup_Guide.md) -- Multi-mode multi-corner scenario configuration
- [CBflow Feature Document](CBflow_v2.0.0_Feature_Document.md) -- Complete framework documentation
