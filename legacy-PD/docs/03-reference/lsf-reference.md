# CBflow LSF and Tool Launch Reference

Complete reference for tool launch modes and LSF (Load Sharing Facility) integration in CBflow v2.0.0.

---

## Tool Launch Chain

Every EDA tool stage generates a wrapper script at:

```
work/<FLOW>/<stage>1/run/launch_<stage>.csh
```

The wrapper is a self-contained csh script that loads the tool module and runs the EDA shell:

```csh
#!/bin/csh -f
# CBFlow tool launch wrapper -- SYNTH_PNR place
module load synopsysFusionCompiler/2025.06-SP2
fc_shell -f place_fc.tcl -output_log_file logs/place.log
```

All 130 subnode handlers across 17 flow/tool directories use this unified launch chain.

---

## 4 Launch Modes

Launch mode is controlled by two settings in `user_config.tcl`:

```tcl
set flow(use_lsf)    "true"    ;# or "false"
set flow(use_xterm)  "true"    ;# or "false"
```

| `flow(use_lsf)` | `flow(use_xterm)` | Mode | What Happens |
|---|---|---|---|
| false | false | **Local** | `./launch_<stage>.csh` runs in the current terminal |
| false | true | **xterm (local)** | `xterm -geometry 200x50 -title "CBFlow SYNTH_PNR place" -e launch_<stage>.csh` |
| true | false | **LSF batch** | `bsub -P RD -J ... -q normal_rhel8 -n 16 -W 8:00 -R "rusage[mem=32GB] affinity[...]" launch_<stage>.csh` |
| true | true | **LSF + xterm** | `bsub -Is -P RD ... xterm -geometry 200x50 -title "CBFlow ..." -e launch_<stage>.csh` |

### LSF Auto-Enable

LSF is enabled through config (no environment variable is needed for normal operation):

```tcl
# In user_config.tcl:
set flow(use_lsf)    "true"
set flow(use_xterm)  "true"
```

Fallback: the `CBFLOW_USE_LSF=1` environment variable enables LSF when config is not set.

Override: the `CBFLOW_BSUB_CMD` environment variable replaces the entire constructed bsub command with a user-supplied one.

---

## How the bsub Command is Built

The bsub command is assembled in four steps:

1. **Queue type lookup** -- The stage's queue tier is resolved from `lsf(flow_mapping,<FLOW>,<stage>)`. For example, `lsf(flow_mapping,SYNTH_PNR,place)` returns `"L"`.

2. **Resource lookup** -- The queue type determines memory, CPU, and runtime from `lsf(queue_types,<tier>,*)`. For tier L: memory = 32GB, cpu = 16, runtime = 8:00.

3. **bsub settings from config** -- Fixed LSF parameters come from `tool_launch_config.tcl`:
   - `lsf(bsub,command)` = `bsub`
   - `lsf(bsub,queue)` = `normal_rhel8`
   - `lsf(bsub,project)` = `RD`
   - `lsf(bsub,affinity)` = `affinity[core(1):cpubind=socket:membind=localonly]`

4. **Assembled command** -- All parts combine into the final bsub invocation:

```
bsub -P RD -J cbflow_SYNTH_PNR_place -Is -q normal_rhel8 \
     -n 16 -W 8:00 \
     -R "rusage[mem=32GB] affinity[core(1):cpubind=socket:membind=localonly]" \
     -o logs/lsf_place_%J.log -e logs/lsf_place_%J.err \
     xterm -geometry 200x50 -e launch_place.csh
```

The `-Is` flag and `xterm` wrapper are included only when `flow(use_xterm)` is `"true"`.

---

## Queue Tiers (6 levels)

| Tier | Memory | CPU | Time Limit | Cost Factor | Typical Use |
|------|-------:|----:|:----------:|:-----------:|-------------|
| **XS** | 4 GB | 2 | 1:00 | 0.5x | gvim, log browsing, interactive editing |
| **S** | 8 GB | 4 | 2:00 | 1.0x | inputs, validation, export, release |
| **M** | 16 GB | 8 | 4:00 | 2.0x | synthesis, floorplan, basic PNR |
| **L** | 32 GB | 16 | 8:00 | 4.0x | placement, CTS, routing opt, DRC/LVS |
| **XL** | 64 GB | 32 | 12:00 | 8.0x | routing, hierarchical flows |
| **Ultra** | 128 GB | 64 | 24:00 | 16.0x | full chip signoff, massive designs |

Defined in: `config/flow/v1.0.0/tool_launch_config.tcl` (handler-sourced copy) and `config/flow/v1.0.0/lsf_config.tcl` (full management config).

---

## Per-Flow Queue Mappings

### SYNTH

| Stage | Queue Type | CPU | Memory | Runtime |
|-------|:----------:|----:|-------:|:-------:|
| inputs | S | 4 | 8 GB | 2:00 |
| synthesis | M | 8 | 16 GB | 4:00 |
| export_data | S | 4 | 8 GB | 2:00 |
| release_data | S | 4 | 8 GB | 2:00 |

### FP (Floorplan)

| Stage | Queue Type | CPU | Memory | Runtime |
|-------|:----------:|----:|-------:|:-------:|
| inputs | S | 4 | 8 GB | 2:00 |
| import_design | M | 8 | 16 GB | 4:00 |
| floorplan | M | 8 | 16 GB | 4:00 |
| powerplan | L | 16 | 32 GB | 8:00 |
| post_floorplan | M | 8 | 16 GB | 4:00 |
| export_data | S | 4 | 8 GB | 2:00 |
| release_data | S | 4 | 8 GB | 2:00 |

### PNR (Place and Route)

| Stage | Queue Type | CPU | Memory | Runtime |
|-------|:----------:|----:|-------:|:-------:|
| inputs | S | 4 | 8 GB | 2:00 |
| place | L | 16 | 32 GB | 8:00 |
| cts | L | 16 | 32 GB | 8:00 |
| cts_opt | L | 16 | 32 GB | 8:00 |
| route | XL | 32 | 64 GB | 12:00 |
| pro | L | 16 | 32 GB | 8:00 |
| signoff | L | 16 | 32 GB | 8:00 |
| export_data | M | 8 | 16 GB | 4:00 |
| release_data | S | 4 | 8 GB | 2:00 |

### SYNTH_PNR

| Stage | Queue Type | CPU | Memory | Runtime |
|-------|:----------:|----:|-------:|:-------:|
| init_design | S | 4 | 8 GB | 2:00 |
| synthesis | M | 8 | 16 GB | 4:00 |
| place | L | 16 | 32 GB | 8:00 |
| cts | L | 16 | 32 GB | 8:00 |
| cts_opt | L | 16 | 32 GB | 8:00 |
| route | XL | 32 | 64 GB | 12:00 |
| pro | L | 16 | 32 GB | 8:00 |
| signoff | M | 8 | 16 GB | 4:00 |
| export_data | S | 4 | 8 GB | 2:00 |
| release_data | S | 4 | 8 GB | 2:00 |

### STA (Static Timing Analysis)

PT-RM W-2024.09 aligned with DMSA-style per-corner analysis. Each corner runs independently (no MMMC concept in PT/Tempus).

| Stage | Queue Type | CPU | Memory | Runtime |
|-------|:----------:|----:|-------:|:-------:|
| inputs | S | 4 | 8 GB | 2:00 |
| extraction | L | 16 | 32 GB | 8:00 |
| timing (per-corner) | L | 16 | 32 GB | 8:00 |
| reporting | M | 8 | 16 GB | 4:00 |
| release_data | S | 4 | 8 GB | 2:00 |

### PV (Physical Verification)

ICV-RM V-2023.12 aligned. Fill runs first (generates filled GDS), then DRC/LVS/PERC/ERC/XOR run in parallel.

| Stage | Queue Type | CPU | Memory | Runtime |
|-------|:----------:|----:|-------:|:-------:|
| inputs | S | 4 | 8 GB | 2:00 |
| fill | L | 16 | 32 GB | 8:00 |
| drc | L | 16 | 32 GB | 8:00 |
| lvs | L | 16 | 32 GB | 8:00 |
| perc | M | 8 | 16 GB | 4:00 |
| erc | M | 8 | 16 GB | 4:00 |
| xor | M | 8 | 16 GB | 4:00 |
| merge_data | S | 4 | 8 GB | 2:00 |
| release_data | S | 4 | 8 GB | 2:00 |

### EMIR (EM/IR Analysis)

| Stage | Queue Type | CPU | Memory | Runtime |
|-------|:----------:|----:|-------:|:-------:|
| inputs | S | 4 | 8 GB | 2:00 |
| power_analysis | L | 16 | 32 GB | 8:00 |
| ir_drop | L | 16 | 32 GB | 8:00 |
| thermal_analysis | XL | 32 | 64 GB | 12:00 |

### ECO

| Stage | Queue Type | CPU | Memory | Runtime |
|-------|:----------:|----:|-------:|:-------:|
| inputs | S | 4 | 8 GB | 2:00 |
| eco | L | 16 | 32 GB | 8:00 |
| export_db | M | 8 | 16 GB | 4:00 |

### CLP

| Stage | Queue Type | CPU | Memory | Runtime |
|-------|:----------:|----:|-------:|:-------:|
| inputs | S | 4 | 8 GB | 2:00 |
| clp | M | 8 | 16 GB | 4:00 |
| export_data | S | 4 | 8 GB | 2:00 |
| release_data | S | 4 | 8 GB | 2:00 |

### POPT (Power Optimization)

| Stage | Queue Type | CPU | Memory | Runtime |
|-------|:----------:|----:|-------:|:-------:|
| inputs | S | 4 | 8 GB | 2:00 |
| merge_timing | M | 8 | 16 GB | 4:00 |
| power_opt | L | 16 | 32 GB | 8:00 |
| post_merge | M | 8 | 16 GB | 4:00 |
| release_data | S | 4 | 8 GB | 2:00 |

### FCFP (FC Floorplan)

| Stage | Queue Type | CPU | Memory | Runtime |
|-------|:----------:|----:|-------:|:-------:|
| inputs | S | 4 | 8 GB | 2:00 |
| fc_floorplan | L | 16 | 32 GB | 8:00 |
| fc_powerplan | L | 16 | 32 GB | 8:00 |
| fc_post_floorplan | M | 8 | 16 GB | 4:00 |
| export_data | S | 4 | 8 GB | 2:00 |
| release_data | S | 4 | 8 GB | 2:00 |

---

## Tool Shell and Module Mapping

Each EDA tool has a corresponding module load command and shell executable:

| Tool | Module Load Command | Shell |
|------|---------------------|-------|
| Fusion Compiler | `module load synopsysFusionCompiler/2025.06-SP2` | `fc_shell` |
| PrimeTime | `module load synopsysPrimeTime/2025.06` | `pt_shell` |
| Formality | `module load synopsysFormality/2025.06` | `fm_shell` |
| VC LP | `module load synopsysVCLP/2025.06` | `vc_lp_shell` |
| ICV | `module load synopsysICV/2025.06` | `icv` |
| RedHawk | `module load synopsysRedHawk/2025.06` | `redhawk` |
| Genus | `module load cadenceGenus/23.1` | `genus` |
| Innovus | `module load cadenceInnovus/23.1` | `innovus` |
| Tempus | `module load cadenceTempus/23.1` | `tempus` |

All wrapper scripts use `/bin/csh -f` as the shell (`lsf(tool_wrapper_shell)`), which ensures module load commands work correctly.

---

## CBFLOW_BSUB_CMD Override

Setting the `CBFLOW_BSUB_CMD` environment variable replaces the entire constructed bsub command. This bypasses all queue type lookups and resource resolution from config.

```bash
# Override for all tool stages in the current session:
export CBFLOW_BSUB_CMD="bsub -q normal -n 8 -R 'rusage[mem=32768]'"
make route

# Inline override for a single make target:
CBFLOW_BSUB_CMD="bsub -q long -n 16 -W 8:00" make place

# Unset to return to config-driven behavior:
unset CBFLOW_BSUB_CMD
```

---

## Test Mode

When test mode is enabled (`flow(test_mode) = "true"` in `user_config.tcl`), wrapper scripts are generated but **not executed**. The handler reports which launch mode would be used:

```
INFO: [TEST MODE] Launch mode: LSF (interactive xterm)
```

This is useful for validating your launch configuration before committing compute resources.

---

## Configuration Files

| File | Purpose |
|------|---------|
| `config/flow/v1.0.0/tool_launch_config.tcl` | Module load commands, tool shells, bsub defaults, xterm settings, queue type resources, flow-to-queue mappings. Sourced by subnode handlers at runtime. |
| `config/flow/v1.0.0/lsf_config.tcl` | Full LSF management config: queue definitions with descriptions/priorities/cost factors, ML analytics settings, dynamic queue policies, cost optimization, monitoring and alerting, security and resource limits. |

### Key Settings in tool_launch_config.tcl

```tcl
# bsub defaults
set lsf(bsub,command)   "bsub"
set lsf(bsub,project)   "RD"
set lsf(bsub,queue)     "normal_rhel8"
set lsf(bsub,affinity)  "affinity[core(1):cpubind=socket:membind=localonly]"

# xterm defaults
set lsf(xterm,command)   "xterm"
set lsf(xterm,geometry)  "200x50"
```

---

## ML-Based Resource Optimization

The `lsf_config.tcl` includes ML analytics settings for intelligent queue selection:

- **Queue prediction** -- Random forest model using `design_size`, `flow_type`, `stage_type`, `historical_memory_usage`, `cpu_requirements`, `runtime_estimate`, `complexity_score`
- **Resource optimization** -- Neural network model using `current_utilization`, `pending_jobs`, `time_of_day`, `project_priority`, `cost_constraints`, `deadline_pressure`, `resource_availability`
- **Auto-scaling** -- Scales up at >80% utilization, scales down at <30%, with a 5-minute cooldown between operations
- **Dynamic queues** -- Auto-created when existing queues exceed 90% utilization; removed after 1 hour idle. Templates: `high_memory` (256GB/32CPU), `high_cpu` (64GB/128CPU), `emergency` (512GB/128CPU)

---

## Cost Tracking

| Parameter | Value |
|-----------|-------|
| CPU cost | $0.50/hr |
| Memory cost | $0.10/GB/hr |
| Budget warning threshold | 80% |
| Budget critical threshold | 95% |

---

## Resource Limits

| Parameter | Limit |
|-----------|-------|
| Max jobs per user | 50 |
| Max CPU hours per project | 10,000 |
| Max memory GB-hours per project | 50,000 |
| Max concurrent jobs | 100 |

---

**Documentation Version**: 2.0.0
