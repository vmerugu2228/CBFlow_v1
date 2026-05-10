# Configuration Reference

Complete reference for all CBflow v2.0.0 configuration files.

## Configuration Hierarchy

```
flow_config.tcl                (top-level: flow types, email, autoppt, MMMC, logging, makefile)
  node_configs/                (per-flow: 12 files, one per flow type)
  tool_launch_config.tcl       (module loads, tool shells, bsub defaults, queue types)
  release_config.tcl           (release_exit_files, phase_criteria, milestone_flow_map, flow_input_handshake)
  mmmc_config.tcl              (analysis views, library sets, scenario sets, per-node assignments)
  tech_config.tcl              (technology: libraries, routing layers, NDM, tracks)
  project_config.tcl           (project-level overrides and release settings)
  exit/                        (6 milestone configs + waivers + thresholds + remediation)
```

Settings cascade downward. A node config inherits from flow_config and can override any value. MMMC, tech, and tool launch configs are referenced by node configs and subnode handlers.

---

## flow_config.tcl

### Location

```
config/flow/v1.0.0/flow_config.tcl
```

### Purpose

Top-level configuration defining project-wide settings, all 12 supported flow types, project phases, email notifications, AutoPPT generation, MMMC integration, logging, and makefile generation. Sources node configs from `node_configs/` subdirectory.

### Flow Types (12)

```tcl
set flow(types) {SYNTH FP PNR STA LEC EMIR PV ECO CLP POPT FCFP SYNTH_PNR}
```

FCT and PHYV were removed in v2.0.0 (merged into STA and PV respectively).

### Core Settings

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `flow(project_name)` | string | `"ravendrive"` | Project name (loads `<project_name>_config.tcl`) |
| `flow(tech_node)` | string | `"gf_22nm"` | Technology node (loads `<tech_node>_config.tcl`) |
| `flow(type)` | string | `"SYNTH"` | Current active flow type |
| `flow(types)` | list | 12 flows | All supported flow types |
| `flow(default_type)` | string | `"SYNTH"` | Default flow type when not specified |
| `flow(design_name)` | string | `"default_design"` | Top-level design name (must override in user config) |
| `flow(run_name)` | string | `"default_run"` | Run identifier (usually overridden in user config) |
| `flow(use_lsf)` | string | `"true"` | Auto-submit stages to LSF |
| `flow(use_xterm)` | string | `"true"` | Launch tool in xterm window |
| `flow(test_mode)` | string | `"false"` | Skip EDA tool execution (dry run) |
| `flow(track_variant)` | string | `""` | Override tech default track (9T, 7.5T, 6.75T) |
| `flow(mode)` | string | `"default"` | `"default"` or `"merged"` (SYNTH+PNR merge into SYNTH_PNR) |
| `flow(run_type)` | string | `"node"` | `"node"` (individual) or `"flat"` (merged execution) |
| `flow(phases)` | list | `{P0 P1 P2 P3}` | Available project phases |
| `flow(exit_milestones)` | list | 6 milestones | FP_EXIT, PLACE_EXIT, CTS_EXIT, PRO_EXIT, BTO, MTO |

### Email Configuration

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `flow(email,enabled)` | boolean | `true` | Enable email notifications |
| `flow(email,smtp_server)` | string | `"localhost"` | SMTP server hostname |
| `flow(email,smtp_port)` | integer | `25` | SMTP server port (25=plain, 587=TLS) |
| `flow(email,smtp_tls)` | boolean | `false` | Enable STARTTLS encryption |
| `flow(email,smtp_auth)` | boolean | `false` | Require SMTP authentication |
| `flow(email,smtp_user)` | string | `""` | SMTP username (if auth enabled) |
| `flow(email,smtp_password)` | string | `""` | SMTP password (if auth enabled) |
| `flow(email,from)` | string | `""` | Sender email address (default: user@hostname) |
| `flow(email,cc)` | string | `""` | Default CC recipients |
| `flow(email,reply_to)` | string | `""` | Reply-To address |
| `flow(email,recipients)` | string | `""` | Default recipients (comma-separated) |
| `flow(email,signature)` | string | `"CBflow Automation"` | Email footer signature |
| `flow(email,on_run_create)` | boolean | `false` | Send email on run creation |
| `flow(email,on_run_complete)` | boolean | `false` | Send email on run completion |
| `flow(email,on_stage_fail)` | boolean | `false` | Send email on stage failure |
| `flow(email,on_checklist)` | boolean | `false` | Send email after checklist run |

### AutoPPT Configuration

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `flow(autoppt,enabled)` | boolean | `true` | Enable AutoPPT generation |
| `flow(autoppt,format)` | string | `"html"` | Default format: `html` or `pptx` |
| `flow(autoppt,auto_generate)` | boolean | `false` | Auto-generate on run completion |
| `flow(autoppt,include_power)` | boolean | `true` | Include power analysis slides |
| `flow(autoppt,include_clock)` | boolean | `true` | Include clock QoR slides |
| `flow(autoppt,include_drc)` | boolean | `true` | Include DRC summary slides |

### MMMC Settings

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `flow(mmmc,enabled)` | boolean | `true` | Enable multi-mode multi-corner analysis |
| `flow(mmmc,config_file)` | string | `"mmmc_config.tcl"` | MMMC configuration file name |

### Logging Configuration

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `flow(log,level)` | string | `"INFO"` | Log level |
| `flow(log,rotation_size)` | string | `"100MB"` | Log rotation size |
| `flow(log,retention_days)` | integer | `30` | Log retention in days |
| `flow(log,categories)` | list | 7 categories | `{INIT CONFIG STAGE TOOL ERROR WARNING DEBUG}` |

### Makefile Configuration

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `flow(makefile,include_colors)` | boolean | `true` | Color output in make |
| `flow(makefile,parallel_jobs)` | integer | `4` | Parallel make jobs |
| `flow(makefile,verbose_output)` | boolean | `false` | Verbose make output |
| `flow(makefile,default_targets)` | list | 5 targets | `{all help status clean retrace}` |

### Example

```tcl
set flow(project_name)  "ravendrive"
set flow(tech_node)     "gf_22nm"
set flow(types)         {SYNTH FP PNR STA LEC EMIR PV ECO CLP POPT FCFP SYNTH_PNR}
set flow(phases)        {P0 P1 P2 P3}
set flow(mode)          "default"
set flow(run_type)      "node"
set flow(use_lsf)       "true"
set flow(use_xterm)     "true"

# Email
set flow(email,smtp_server)     "smtp.company.com"
set flow(email,smtp_port)       587
set flow(email,smtp_tls)        true
set flow(email,smtp_auth)       true
set flow(email,from)            "cbflow@company.com"
set flow(email,cc)              "lead@company.com"
set flow(email,recipients)      "team@company.com"
set flow(email,on_run_create)   true
set flow(email,on_run_complete) true
set flow(email,on_stage_fail)   true
```

---

## tool_launch_config.tcl

### Location

```
config/flow/v1.0.0/tool_launch_config.tcl
```

### Purpose

Module load commands, tool shell commands, LSF bsub defaults, xterm settings, queue type resources, and flow-to-queue mappings. Sourced by all subnode handlers for tool execution.

### Module Load Commands (9 tools)

| Tool Key | Module Load Command |
|----------|-------------------|
| `fc` | `module load synopsysFusionCompiler/2025.06-SP2` |
| `pt` | `module load synopsysPrimeTime/2025.06` |
| `fm` | `module load synopsysFormality/2025.06` |
| `vc_lp` | `module load synopsysVCLP/2025.06` |
| `icv` | `module load synopsysICV/2025.06` |
| `redhawk` | `module load synopsysRedHawk/2025.06` |
| `genus` | `module load cadenceGenus/23.1` |
| `innovus` | `module load cadenceInnovus/23.1` |
| `tempus` | `module load cadenceTempus/23.1` |

### Tool Shell Commands (9 tools)

| Tool Key | Shell Command |
|----------|--------------|
| `fc` | `fc_shell` |
| `pt` | `pt_shell` |
| `fm` | `fm_shell` |
| `vc_lp` | `vc_lp_shell` |
| `icv` | `icv` |
| `redhawk` | `redhawk` |
| `genus` | `genus` |
| `innovus` | `innovus` |
| `tempus` | `tempus` |

### Wrapper Shell

```tcl
set lsf(tool_wrapper_shell) "/bin/csh -f"
```

### LSF bsub Defaults

| Setting | Value | Description |
|---------|-------|-------------|
| `lsf(bsub,command)` | `"bsub"` | bsub executable |
| `lsf(bsub,project)` | `"RD"` | LSF project code |
| `lsf(bsub,queue)` | `"normal_rhel8"` | Default queue |
| `lsf(bsub,affinity)` | `"affinity[core(1):cpubind=socket:membind=localonly]"` | CPU affinity |

### XTerm Settings

| Setting | Value |
|---------|-------|
| `lsf(xterm,enabled)` | `"true"` |
| `lsf(xterm,command)` | `"xterm"` |
| `lsf(xterm,geometry)` | `"200x50"` |

### Queue Type Resources (5 tiers)

| Tier | Memory | CPUs | Runtime Limit |
|------|--------|------|---------------|
| **S** | 8GB | 4 | 2:00 |
| **M** | 16GB | 8 | 4:00 |
| **L** | 32GB | 16 | 8:00 |
| **XL** | 64GB | 32 | 12:00 |
| **ultra** | 128GB | 64 | 24:00 |

```tcl
set lsf(queue_types,S,memory)         "8GB"
set lsf(queue_types,S,cpu)            "4"
set lsf(queue_types,S,runtime_limit)  "2:00"
```

### Flow-to-Queue Mappings

Maps each flow stage to a queue type. All 12 flows have mappings defined.

**SYNTH_PNR:**

| Stage | Queue |
|-------|-------|
| init_design | S |
| synthesis | M |
| place | L |
| cts | L |
| cts_opt | L |
| route | XL |
| pro | L |
| signoff | M |
| export_data | S |
| release_data | S |

**PNR:**

| Stage | Queue |
|-------|-------|
| place | L |
| cts | L |
| cts_opt | L |
| route | XL |
| pro | L |
| signoff | L |
| export_data | M |
| release_data | S |

**STA:**

| Stage | Queue |
|-------|-------|
| extraction | L |
| timing | L |
| reporting | M |
| export_data | S |
| release_data | S |

**EMIR:**

| Stage | Queue |
|-------|-------|
| power_analysis | L |
| ir_drop | L |
| thermal_analysis | XL |

**PV:**

| Stage | Queue |
|-------|-------|
| drc | L |
| lvs | L |
| erc | M |
| perc | M |
| fill | L |
| xor | M |
| merge_data | S |
| release_data | S |

---

## release_config.tcl

### Location

```
config/flow/v1.0.0/release_config.tcl
```

### Purpose

Defines release exit files per flow/phase/milestone, milestone-to-flow mappings, phase criteria thresholds, flow input handshake requirements, and input release path resolution. Controls what must be delivered at each project phase and exit milestone.

### Section 1: release_exit_files

Keyed by `{FLOW},{MILESTONE},{PHASE}` or `{FLOW},{PHASE}` for flows without stage exits. Defines the report and output files that must exist at each milestone.

**Flows with milestone-keyed exit files:**
- **SYNTH_PNR** -- FP_EXIT (P0/P1), PLACE_EXIT (P0/P1/P2), CTS_EXIT (P0/P1/P2), PRO_EXIT (P0/P1/P2), BTO (P3), MTO (P3)
- **PNR** -- PLACE_EXIT (P0/P1), CTS_EXIT (P0/P1), PRO_EXIT (P0/P1/P2), BTO (P3)
- **FP** -- FP_EXIT (P0/P1/P2)
- **FCFP** -- FP_EXIT (P0/P1/P2)
- **EMIR** -- phase-keyed (P0/P1), BTO (P2/P3)
- **PV** -- phase-keyed (P0/P1), BTO (P2/P3)
- **STA** -- phase-keyed (P0/P1/P2), BTO (P3)

**Flows with phase-only keys:**
- **SYNTH** -- P0, P1, P2
- **LEC** -- P0, P1, P2, P3
- **CLP** -- P0, P1, P2, P3
- **ECO** -- P1, P2, P3
- **POPT** -- P0, P1, P2

### Section 2: milestone_flow_map

Maps each milestone to required flows that must complete for sign-off:

```tcl
array set milestone_flow_map {
    FP_EXIT    {FP FCFP SYNTH_PNR}
    PLACE_EXIT {SYNTH_PNR PNR}
    CTS_EXIT   {SYNTH_PNR PNR}
    PRO_EXIT   {SYNTH_PNR PNR}
    BTO        {SYNTH_PNR PNR PV STA LEC CLP EMIR}
    MTO        {SYNTH_PNR PNR PV STA LEC CLP EMIR}
}
```

### Section 3: phase_criteria

Threshold values per `{MILESTONE},{PHASE},{METRIC}`. Metrics include `setup_wns`, `hold_wns`, `setup_tns`, `utilization_min`, `max_skew`, `drc_count`, `lvs_match`, `antenna_violations`, `em_violations`, `gds_errors`.

Example thresholds:

| Milestone | Phase | setup_wns | hold_wns | drc_count |
|-----------|-------|-----------|----------|-----------|
| FP_EXIT | P0 | -500 | -- | -- |
| PLACE_EXIT | P1 | -80 | -200 | -- |
| CTS_EXIT | P2 | -10 | -5 | -- |
| PRO_EXIT | P2 | 0 | 0 | 0 |
| BTO | P3 | 0 | 0 | 0 |
| MTO | P3 | 0 | 0 | 0 |

### Section 4: flow_input_handshake

Maps downstream flow inputs to upstream flow outputs. Keyed by `{DOWNSTREAM_FLOW},{input_type}` with value `{UPSTREAM_FLOW subdir filename_pattern}`.

```tcl
array set flow_input_handshake {
    PNR,netlist           {SYNTH    netlist   "${design_name}.v"}
    PNR,sdc               {SYNTH    sdc       "${design_name}.sdc"}
    PNR,def               {FP       def       "${design_name}.def"}
    STA,netlist           {SYNTH_PNR netlist  "${design_name}.pt.v"}
    STA,spef              {SYNTH_PNR spef    "${design_name}.spef"}
    PV,gds                {SYNTH_PNR gds     "${design_name}.gds"}
    PV,netlist            {SYNTH_PNR netlist  "${design_name}.lvs.v"}
    LEC,netlist_golden    {SYNTH    netlist   "${design_name}.v"}
    LEC,netlist_revised   {SYNTH_PNR netlist  "${design_name}.v"}
    CLP,netlist           {SYNTH_PNR netlist  "${design_name}.v"}
    EMIR,def              {SYNTH_PNR def     "${design_name}.def"}
    ECO,netlist           {SYNTH_PNR netlist  "${design_name}.v"}
    POPT,netlist          {SYNTH_PNR netlist  "${design_name}.pt.v"}
}
```

All 12 flows have handshake entries. SYNTH and SYNTH_PNR consume from INPUTS (rtl, sdc, upf). FP consumes from SYNTH.

---

## mmmc_config.tcl

### Location

```
config/flow/v1.0.0/mmmc_config.tcl
```

### Purpose

Defines process corners, operating modes, RC corners, analysis views, predefined scenario sets, and per-node MMMC scenario assignments. Uses TCL arrays (`mmmc_config`, `process_corners`, `operating_modes`, `rc_corners`, `analysis_views`, `mmmc_scenario_sets`, `mmmc`).

### Global MMMC Settings

| Setting | Value |
|---------|-------|
| `enabled` | `true` |
| `version` | `"3.0"` |
| `timing_derate_early` | `0.95` |
| `timing_derate_late` | `1.05` |
| `clock_uncertainty` | `0.1` |
| `max_transition` | `0.5` |
| `max_capacitance` | `2.0` |
| `max_fanout` | `16` |

### Process Corners (3)

| Corner | Description | Setup-Critical | Hold-Critical |
|--------|-------------|:-:|:-:|
| **ss** | Slow NMOS, Slow PMOS | Yes | -- |
| **tt** | Typical NMOS, Typical PMOS | -- | -- |
| **ff** | Fast NMOS, Fast PMOS | -- | Yes |

### Operating Modes (2)

| Mode | Clock Freq | Constraint File |
|------|-----------|----------------|
| **func** | 1000 MHz | `ravendrive_func.sdc` |
| **test** | 100 MHz | `ravendrive_test.sdc` |

### RC Corners (3)

| RC Corner | Usage | Metal Multiplier |
|-----------|-------|-----------------|
| **rc_max** | Setup-critical | 1.15 |
| **rc_typ** | Nominal | 1.00 |
| **rc_min** | Hold-critical | 0.85 |

### Analysis Views (19 defined)

Naming convention: `<mode>_<corner>_<voltage>_<rc_corner>_<temperature>`

Example: `func_ss_0p76v_rcmax_150c` = Functional mode, SS corner, 0.76V, max RC, 150C

Each view maps to: corner, mode, voltage, temperature, RC corner, analysis_type, constraint_file, lib_set_ref.

### Predefined Scenario Sets (8)

| Set | Count | Description |
|-----|:-----:|-------------|
| `setup` | 4 | Setup-critical scenarios (SS corner, low voltage, hot/cold) |
| `hold` | 4 | Hold-critical scenarios (FF corner, high voltage, cold) |
| `power` | 3 | Power analysis scenarios (leakage + dynamic) |
| `signoff` | 10 | Complete signoff (setup + hold + nominal) |
| `all` | 17 | All available scenarios |
| `sta_setup` | 4 | STA setup-critical |
| `sta_hold` | 4 | STA hold-critical |
| `sta_signoff` | 10 | STA full signoff |

### Per-Node Scenario Assignments

The `mmmc` array assigns setup and hold scenarios to each PNR/synthesis node:

| Node | Setup Scenarios | Hold Scenarios |
|------|:-:|:-:|
| init_design | 1 | 1 |
| floorplan | 1 | 1 |
| powerplan | 1 | 1 |
| placement | 2 | 2 |
| cts | 3 | 3 |
| cts_opt | 4 | 3 |
| route | 3 | 3 |
| post_route | 4 | 4 |
| signoff | 6 | 6 |
| synthesis | 3 | 2 |

---

## Node Configs (12 files)

### Location

```
config/flow/v1.0.0/node_configs/<FLOW>_config.tcl
```

One config per flow type (12 files):

| File | Flow | Description |
|------|------|-------------|
| `SYNTH_config.tcl` | SYNTH | Logic synthesis |
| `FP_config.tcl` | FP | Floorplanning and power planning |
| `PNR_config.tcl` | PNR | Place and route |
| `STA_config.tcl` | STA | Static timing analysis (PT-RM W-2024.09) |
| `LEC_config.tcl` | LEC | Logical equivalence checking |
| `EMIR_config.tcl` | EMIR | EM/IR drop and thermal analysis |
| `PV_config.tcl` | PV | Physical verification (DRC/LVS/ERC/PERC/XOR/fill, ICV-RM V-2023.12) |
| `ECO_config.tcl` | ECO | Engineering change orders |
| `CLP_config.tcl` | CLP | Conformal low power verification |
| `POPT_config.tcl` | POPT | Power optimization |
| `FCFP_config.tcl` | FCFP | Fullchip floorplanning |
| `SYNTH_PNR_config.tcl` | SYNTH_PNR | Unified synthesis to signoff (FC-RM aligned) |

### Key Array Keys (Common to all node configs)

Each node config uses `array set <flow_name> { ... }` with these key patterns:

| Key Pattern | Type | Description |
|-------------|------|-------------|
| `stages` | list | Ordered stage names with numeric suffix (e.g., `synthesis1`, `place1`) |
| `subnodes,<stage>` | list | Ordered subnode list per stage (e.g., `{setup run validate finish}`) |
| `dependencies,<stage>` | list | Stage-level dependency list |
| `subnode_dependencies,<stage>,<subnode>` | list | Subnode-level dependency chains |
| `stage_types,<stage>` | string | Stage type: `inputs`, `execution`, `export_data`, `release_data` |
| `node_types,<stage>` | string | Node type name (e.g., `synthesis`, `place`, `cts`) |
| `subnode_work_dirs,<stage>,<subnode>` | string | Working directory for each subnode |
| `tool,vendor` | string | EDA vendor (`synopsys`, `cadence`) |
| `tool,name` | string | Tool name (`fc`, `pt`, `fm`, etc.) |
| `tool,version` | string | Tool config version |
| `tool,args` | string | Tool launch arguments |
| `mmmc,enabled` | boolean | Whether MMMC is active for this flow |
| `mmmc,default_scenario_set` | string | Default scenario set name |
| `runtime,timeout,<stage>` | integer | Timeout in minutes per stage |
| `release_types,<stage>,files` | list | Release deliverable file mappings |
| `mandatory_input_groups` | list | Grouped mandatory input validation |

### SYNTH_PNR Example (FC-RM aligned)

```tcl
array set synth_pnr {
    stages {inputs1 init_design1 synthesis1 place1 cts1 cts_opt1 route1 pro1 signoff1 export_data1 release_data1}
    dependencies,place1   {synthesis1}
    dependencies,cts1     {place1}
    dependencies,route1   {cts_opt1}
    tool,vendor  "synopsys"
    tool,name    "fc"
    mmmc,enabled true
    mmmc,default_scenario_set "signoff"
}
```

---

## Tech Configs (3 files)

### Location

```
config/tech/<tech_node>/v1.0.0/tech_config.tcl
```

### Available Tech Nodes

| Tech Node | Directory |
|-----------|-----------|
| GF 22nm (22FDX) | `config/tech/gf_22nm/v1.0.0/tech_config.tcl` |
| TSMC 7nm | `config/tech/tsmc_7nm/v1.0.0/tech_config.tcl` |
| TSMC 5nm | `config/tech/tsmc_5nm/v1.0.0/tech_config.tcl` |

### Purpose

Technology-specific settings including multi-track library support, routing layers, NDM paths, standard cell libraries, and process parameters.

### Multi-Track Support

| Track | Cell Height | Use Case |
|-------|-------------|----------|
| 9T | Standard | General logic, default |
| 7.5T | Reduced | Area-optimized blocks |
| 6.75T | Compact | High-density regions |

### Library Sets

Tech configs define library sets per PVT corner (e.g., `ss_0760v_150c`, `tt_0800v_25c`, `ff_0840v_m40c`) referenced by `lib_set_ref` in analysis views.

---

## Project Configs (2 files)

### Location

```
config/project/<project_name>/v1.0.0/<project_name>_config.tcl
```

### Available Projects

| Project | File |
|---------|------|
| **phoenix** | `config/project/phoenix/v1.0.0/phoenix_config.tcl` |
| **ravendrive** | `config/project/ravendrive/v1.0.0/ravendrive_config.tcl` |

### Purpose

Project-level overrides customizing CBflow behavior for a specific project. Includes design hierarchy, block lists, track variant selection, and release configuration.

### Key Settings

| Setting | Type | Description |
|---------|------|-------------|
| `project(name)` | string | Project identifier |
| `project(version)` | string | Project version |
| `project(description)` | string | Project description |
| `project(owner)` | string | Project owner |
| `project(top_module)` | string | Top-level design module |
| `project(block_list)` | string | Space-separated block names |
| `project(track_variant)` | string | Track variant (9T, 7.5T, 6.75T) |
| `project(design_hierarchy)` | dict | Hierarchical design structure (DL1/DL2/DL3) |

### Release Settings

| Setting | Type | Description |
|---------|------|-------------|
| `project(release,path)` | string | Base release path (e.g., `/proj/ravendrive/releases`) |
| `project(release,phase)` | string | Current design phase (P0-P3) |
| `project(release,block_name)` | string | Block being released |
| `project(release,tag)` | string | Release tag version |
| `project(release,author)` | string | Release author |
| `project(release,organization)` | string | Organization name |
| `project(release,structure)` | list | Release subdirectories (netlist, sdc, def, gds, spef, upf, reports, data, db, docs) |
| `project(release,include_timestamp)` | boolean | Include timestamp in release |
| `project(release,generate_notes)` | boolean | Auto-generate release notes |
| `project(release,validate_mandatory)` | boolean | Validate mandatory files on release |

Release path structure: `$release_path/$phase/$block_name/$release_tag`

Example: `/proj/ravendrive/releases/P2/top_chip/v1.0.2`

---

## Exit Configs (6 milestone configs + 3 support files)

### Location

```
config/exit/v1.0.0/
    FP_EXIT_config.tcl
    PLACE_EXIT_config.tcl
    CTS_EXIT_config.tcl
    PRO_EXIT_config.tcl
    BTO_config.tcl
    MTO_config.tcl
    waiver_config.tcl
    threshold_overrides.tcl
    remediation_config.tcl
```

### Milestones (6)

| Milestone | Description | Key Checks |
|-----------|-------------|------------|
| **FP_EXIT** | Floorplan exit | Utilization, congestion, timing |
| **PLACE_EXIT** | Placement exit | Design ready for CTS |
| **CTS_EXIT** | CTS exit | Clock skew, design ready for routing |
| **PRO_EXIT** | Post-route exit | Design ready for finishing |
| **BTO** | Backend tapeout | PV+STA signoff, design ready for manufacturing |
| **MTO** | Manufacturing tapeout | Final design release, zero violations |

### Support Files

| File | Purpose |
|------|---------|
| `waiver_config.tcl` | Waiver definitions for specific check failures |
| `threshold_overrides.tcl` | Project-specific threshold overrides |
| `remediation_config.tcl` | Remediation actions for check failures |

FCT and PHYV exit configs do not exist -- those flows were removed in v2.0.0.

---

## Configuration File Summary

| Category | Count | Format | Location |
|----------|:-----:|--------|----------|
| Top-level flow config | 1 | TCL | `config/flow/v1.0.0/flow_config.tcl` |
| Tool launch config | 1 | TCL | `config/flow/v1.0.0/tool_launch_config.tcl` |
| Release config | 1 | TCL | `config/flow/v1.0.0/release_config.tcl` |
| MMMC config | 1 | TCL | `config/flow/v1.0.0/mmmc_config.tcl` |
| Node configs | 12 | TCL | `config/flow/v1.0.0/node_configs/<FLOW>_config.tcl` |
| Tech configs | 3 | TCL | `config/tech/<node>/v1.0.0/tech_config.tcl` |
| Project configs | 2 | TCL | `config/project/<project>/v1.0.0/<project>_config.tcl` |
| Exit configs | 9 | TCL | `config/exit/v1.0.0/` |

---

**See also:**
- [Python Scripts Reference](python-scripts-reference.md) -- CLI modules and subcommands
- [LSF Reference](lsf-reference.md) -- LSF integration details
- [MMMC Reference](mmmc-reference.md) -- MMMC configuration details
- [System Design](../04-architecture/system-design.md) -- Architecture
- [Examples](../06-examples/basic-workflows.md) -- Workflow examples
