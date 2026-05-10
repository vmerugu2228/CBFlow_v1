# Installation & Setup

Complete setup guide for CBflow v2.0.0.

## Prerequisites

| Requirement | Version | Notes |
|-------------|---------|-------|
| Python | 3.6+ | Stdlib only -- no pip install needed |
| Bash or Zsh | 4.0+ | CLI dispatcher and completions |
| Tcl/Tclsh | 8.5+ | Config files and flow_proc engine |

Note: GNU Make is NOT required. CBflow v2.0.0 uses the RACE (Run Automation & Control Engine) for all flow execution and status tracking.

## Installation

```bash
# 1. Copy CBflow to target location
tar xzf cbflow-v2.0.0.tar.gz -C /opt/cbflow
# OR
rsync -avz CBflow_clone/PD/ server:/opt/cbflow/

# 2. Set environment
export CBFLOW_HOME=/opt/cbflow
export PATH=$CBFLOW_HOME/bin:$PATH

# 3. Enable tab completion
# Bash:
source $CBFLOW_HOME/completions/cbflow.bash
# Zsh:
fpath=($CBFLOW_HOME/completions $fpath)
autoload -Uz compinit && compinit

# 4. Add to ~/.bashrc or ~/.zshrc for persistence
echo 'export CBFLOW_HOME=/opt/cbflow' >> ~/.bashrc
echo 'export PATH=$CBFLOW_HOME/bin:$PATH' >> ~/.bashrc
echo 'source $CBFLOW_HOME/completions/cbflow.bash' >> ~/.bashrc
```

## Verify Installation

```bash
cbflow --version                    # Should show v2.0.0
bin/cbflow-test-suite               # 994 tests, ALL PASS
bin/cbflow-healthcheck              # System health check
bin/cbflow-verify                   # Production verification
```

## RACE Engine

CBflow v2.0.0 uses RACE (Run Automation & Control Engine) as the sole dispatcher. Key points:

- **No Makefile**: RACE builds the execution DAG directly from `node_config.tcl` at runtime.
- **SQLite DB status**: Each run tracks node status in `.race_<uid>.db` instead of stamp files.
- **DB path**: `$project(race,db_path)/$project/$domain/$flow/$user_$run_$uid.db`
- **File change detection**: Edit an input file and RACE auto-retraces downstream nodes (VOV-like).
- **Parallel execution**: Independent subnodes (e.g., PV drc/lvs/erc/perc/xor) run in parallel.
- **Dynamic subnodes**: STA per-corner subnodes generated from user_config at runtime.
- **Configuration**: `set flow(dispatcher) "race"` in flow_config.tcl

## EDA Tool Setup

CBflow expects EDA tools in `$PATH`. Configure via `module load` or equivalent:

```bash
module load synopsysFusionCompiler/2025.06
module load synopsysPrimeTime/2025.06
module load cadenceInnovus/23.1
# etc.
```

Tool-to-module mappings are in `config/flow/v1.0.0/tool_launch_config.tcl`.

## Project Setup

Create or edit your project config:

```tcl
# config/project/<name>/v1.0.0/<name>_config.tcl
set project(name)               "my_project"
set project(cbflow_release)     "v1.0.0"        ;# MANDATORY
set project(release,path)       "/proj/releases" ;# Where releases go
set project(release,phase)      "P0"             ;# P0/P1/P2/P3
set project(release,block_name) "top_chip"       ;# Block name
set project(release,tag)        "v1.0.0"         ;# Release tag
```

## Technology Setup

CBflow ships with 3 tech configs (no hardcoded paths):

| Config | Technology | Tracks |
|--------|-----------|--------|
| `gf_22nm` | GlobalFoundries 22FDX | 9T, 7.5T, 8T |
| `tsmc_7nm` | TSMC N7 | 7T, 7.5T, 6T |
| `tsmc_5nm` | TSMC N5 | 5T, 6T, 7T |

Edit paths in `config/tech/<tech>/v1.0.0/tech_config.tcl` to point to your foundry libraries.

## LSF Setup (Optional)

If using LSF for batch job submission:

```tcl
# config/flow/v1.0.0/tool_launch_config.tcl
set lsf(bsub,queue)     "normal_rhel8"
set lsf(bsub,project)   "ASIC_TEAM"
```

Queue tiers: S (8GB), M (16GB), L (32GB), XL (64GB), ultra (128GB).

---

**Next**: [System Requirements](system-requirements.md) for detailed tool versions.
