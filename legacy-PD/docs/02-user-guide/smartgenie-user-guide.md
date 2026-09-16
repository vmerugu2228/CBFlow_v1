# CBflow SmartGenie — AI Agent User Guide

## Overview

SmartGenie is CBflow's built-in AI agent that drives Physical Design flows autonomously. It runs 100% on-premise — no data leaves your network.

```
cbflow smartgenie "create and run SYNTH_PNR"
cbflow smartgenie "why did place1 fail?"
cbflow smartgenie "run all 6 flows and report results"
```

---

## 1. Quick Start

### Single User (Local)

```bash
# Install Ollama (one time)
brew install ollama       # macOS
# or: curl -fsSL https://ollama.com/install.sh | sh  # Linux

# Start Ollama and pull model
ollama serve &
ollama pull qwen2.5:7b

# Build knowledge base (one time)
cbflow smartgenie ingest --all

# Verify setup
cbflow smartgenie setup

# Run
cbflow smartgenie                           # Interactive mode
cbflow smartgenie "run SYNTH_PNR test"      # One-shot
```

### Multi-User (Enterprise)

```bash
# On the server (one machine with GPU or Apple Silicon):
ollama serve &
ollama pull qwen2.5:7b
cbflow smartgenie serve --port 8091

# On every user's machine:
export SMARTGENIE_SERVER=http://server-ip:8091
cbflow smartgenie "your prompt"
```

---

## 2. Commands Reference

### Agent Commands

| Command | Description |
|---------|-------------|
| `cbflow smartgenie` | Interactive AI agent (local LLM) |
| `cbflow smartgenie "prompt"` | One-shot command |
| `cbflow smartgenie setup` | Check Ollama + model + knowledge base |
| `cbflow smartgenie cloud "prompt"` | Use Claude API (needs ANTHROPIC_API_KEY) |

### Knowledge Commands

| Command | Description |
|---------|-------------|
| `cbflow smartgenie ingest` | Ingest CBflow docs + code |
| `cbflow smartgenie ingest --all` | Ingest docs + code + EDA guides + web |
| `cbflow smartgenie search "query"` | Search knowledge base |
| `cbflow smartgenie stats` | Show knowledge base sizes |
| `cbflow smartgenie learn --category fix --content "..."` | Record experience |

### Server Commands (Enterprise)

| Command | Description |
|---------|-------------|
| `cbflow smartgenie serve` | Start central server (default port 8091) |
| `cbflow smartgenie serve --port 9090` | Custom port |
| `cbflow smartgenie --server http://ip:8091 "prompt"` | Connect to server |

---

## 3. Architecture

### Single User

```
You → cbflow smartgenie → Ollama (local) → Tool calls → cbflow CLI
                              ↕
                        ChromaDB (local)
                        ├── cbflow_docs (734 chunks)
                        ├── cbflow_code (3475 chunks)
                        ├── eda_guides
                        └── experience (grows over time)
```

### Enterprise Multi-User

```
┌──────────────────────────────────────────────────────┐
│                ON-PREMISE SERVER                      │
│                                                      │
│  Ollama (LLM)  ←→  SmartGenie Server  ←→  Central   │
│  qwen2.5:7b         port 8091             ChromaDB   │
│                                                      │
│  Shared Collections:                                 │
│    shared_docs         CBflow documentation          │
│    shared_code         Command files + configs       │
│    shared_experience   Team knowledge (auto-shared)  │
│    shared_eda          EDA tool guides               │
│                                                      │
│  Per-User Collections:                               │
│    user_alice          Alice's private notes          │
│    user_bob            Bob's private notes            │
│                                                      │
│  Dashboard: http://server:8091/                      │
└──────────┬──────────┬──────────┬─────────────────────┘
           │          │          │
        Alice       Bob       Charlie
```

### Knowledge Flow

1. **Alice** fixes a hold violation → `learn("Hold fix: enable AOCV after CTS", "fix")`
   → Stored in **shared_experience**
2. **Bob** hits same issue next week → `search("hold violation CTS")`
   → Finds Alice's fix **instantly**
3. **Charlie** joins the team → all accumulated knowledge available from **day 1**

---

## 4. What SmartGenie Can Do

### Flow Execution

```
You: "Create a SYNTH_PNR workspace and run it"

Agent: Creating workspace...
  Tool: bash(cbflow workspace create --config uc_SYNTH_PNR.tcl)
  Result: Run Directory: P0_run_SYNTH_PNR_test1

Agent: Running flow...
  Tool: bash(cd P0_run_SYNTH_PNR_test1 && cbflow run all)
  Result: Run completed: target=all result=PASS

Agent: All 13 stages completed successfully.
  Stages: rtl1 → sdc1 → upf1 → init_design1 → synthesis1 →
          place1 → cts1 → cts_opt1 → route1 → pro1 →
          signoff1 → export_data1 → release_data1
```

### Auto-Configuration

```
You: "Set up STA to read from the SYNTH_PNR run"

Agent: I'll configure STA with from_run pointing to SYNTH_PNR.
  Tool: write_file(path=uc_STA_auto.tcl, content=...)
  Tool: bash(cbflow workspace create --config uc_STA_auto.tcl)
  Result: STA run created with auto-resolved inputs:
    sta(input,netlist) = .../outputs/cpu_core.pt.v
    sta(input,sdc)     = .../outputs/cpu_core.sdc
    sta(input,spef)    = .../outputs/cpu_core.spef
```

### Regression

```
You: "Run all 6 flows and report results"

Agent: Running regression across all flows...

  Flow         Stages  Result   Time
  ──────────────────────────────────
  SYNTH_PNR    13/13   PASS     45s
  PNR          13/13   PASS     38s
  SYNTH         7/7    PASS     22s
  STA           8/8    PASS     28s
  LEC           5/5    PASS     15s
  CLP           4/4    PASS     12s
  ──────────────────────────────────
  TOTAL: 6/6 PASS
```

### Debugging

```
You: "Why did place1 fail in the last SYNTH_PNR run?"

Agent: Let me investigate...
  Tool: search_kb("place_opt failure common causes")
  Tool: bash(cbflow run status --details)
  Tool: read_file(.../work/SYNTH_PNR/place1/run/place1.log)

Agent: Place1 failed due to high congestion (>85% utilization).
  The log shows: "ERROR: Cannot legalize 342 cells"

  Recommended fix:
  1. Reduce utilization target: set synth_pnr(place,max_util) "0.75"
  2. Enable congestion-driven placement: set synth_pnr(place,congestion_effort) "high"

  Tool: learn(content="Place1 legalization failure at >85% util.
    Fix: reduce max_util to 0.75 + set congestion_effort high", category="fix")

  Stored fix for future reference.
```

### Release Readiness

```
You: "Check if we're ready for BTO release"

Agent:
  Tool: bash(cbflow run release-check --tag BTO --project bumblebee --phase P2)

  Block          SYNTH_PNR  PNR        STA        PV         Status
  ───────────────────────────────────────────────────────────────
  cpu_core       PASS(18)   PASS(13)   PASS(5)    MISS       [INCOMPLETE]
  memory_ctrl    MISS       MISS       MISS       MISS       [INCOMPLETE]
  io_ctrl        MISS       MISS       MISS       MISS       [INCOMPLETE]

  NOT READY: PV flow missing for cpu_core, 2 blocks not started.
```

---

## 5. Knowledge Base

### What Gets Ingested

| Source | Chunks | Content |
|--------|--------|---------|
| CBflow docs | ~734 | User guides, architecture, reference, troubleshooting |
| CBflow code | ~3475 | All TCL command files, configs, Python handlers |
| EDA guides | varies | PDF/HTML tool guides (user-provided) |
| Web content | varies | EDA vendor documentation |
| Experience | grows | Team's learned fixes, patterns, errors |

### Adding EDA Tool Guides

```bash
# Create guide directory
mkdir -p PD/ai/eda_guides

# Copy your tool manuals
cp /path/to/fc_user_guide.pdf PD/ai/eda_guides/
cp /path/to/pt_reference.pdf PD/ai/eda_guides/
cp /path/to/innovus_manual.html PD/ai/eda_guides/

# Re-ingest
cbflow smartgenie ingest --all
```

### Adding Web Content

Edit `PD/ai/cbflow_knowledge.py` → `DEFAULT_URLS` list to add more documentation URLs, then re-ingest.

### Experience Categories

| Category | Use For |
|----------|---------|
| `fix` | Bug fixes, error resolutions |
| `pattern` | Common usage patterns, workflows |
| `config` | Configuration tips, variable tricks |
| `error` | Error message meanings, root causes |
| `optimization` | Performance tuning, QoR improvements |

---

## 6. Supported Models

| Model | Size | Best For | Command |
|-------|------|----------|---------|
| **qwen2.5:7b** | 4.4GB | Tool calling + code (recommended) | `ollama pull qwen2.5:7b` |
| llama3.1:8b | 4.7GB | General reasoning | `ollama pull llama3.1:8b` |
| deepseek-coder:6.7b | 3.8GB | Code-specialized | `ollama pull deepseek-coder:6.7b` |
| mistral:7b | 4.1GB | Fast, simple tasks | `ollama pull mistral:7b` |
| qwen2.5:14b | 8.9GB | Best quality (needs 32GB RAM) | `ollama pull qwen2.5:14b` |

Switch model:
```bash
export CBFLOW_MODEL=llama3.1:8b
cbflow smartgenie "your prompt"
```

---

## 7. Privacy & Security

- All AI inference runs **locally** via Ollama — no API calls to any cloud
- Knowledge base stored **on-premise** in ChromaDB (local filesystem)
- In enterprise mode, server runs on **your network** — no external traffic
- No telemetry, no data collection, no third-party dependencies for inference
- Model weights stored locally at `~/.ollama/models/`

### Cloud Fallback (Optional)

For complex reasoning tasks, use Claude API with zero-data-retention:
```bash
export ANTHROPIC_API_KEY=sk-ant-...
cbflow smartgenie cloud "complex analysis prompt"
```
This sends data to Anthropic's API. Use only when local model is insufficient.

---

## 8. Server Administration

### Starting the Server

```bash
# Basic
cbflow smartgenie serve

# Custom port + bind to all interfaces
cbflow smartgenie serve --port 9090 --host 0.0.0.0

# With specific model
CBFLOW_MODEL=qwen2.5:14b cbflow smartgenie serve
```

### Server Dashboard

Open `http://server-ip:8091/` in a browser to see:
- Knowledge base stats (collections, chunk counts)
- API endpoint reference
- Client setup instructions

### API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/chat` | POST | Chat with AI (auto-injects knowledge) |
| `/api/knowledge/search` | POST | Search knowledge base |
| `/api/knowledge/learn` | POST | Record experience |
| `/api/knowledge/ingest` | POST | Re-ingest from local KB |
| `/api/status` | GET | Server status + stats |
| `/api/knowledge/stats` | GET | Collection sizes |
| `/` | GET | Web dashboard |

### Client Configuration

```bash
# Option 1: Environment variable (recommended — add to .bashrc/.zshrc)
export SMARTGENIE_SERVER=http://server-ip:8091

# Option 2: Per-command flag
cbflow smartgenie --server http://server-ip:8091 "prompt"
```

---

## 9. Troubleshooting

### Ollama not found
```
brew install ollama     # macOS
curl -fsSL https://ollama.com/install.sh | sh   # Linux
```

### Ollama not running
```
ollama serve &          # Start in background
```

### Model not downloaded
```
ollama pull qwen2.5:7b  # Downloads 4.4GB, one time
```

### Knowledge base empty
```
cbflow smartgenie ingest --all
```

### Cannot connect to server
```
# Check server is running:
curl http://server-ip:8091/api/status

# Check firewall allows port 8091
```

### Slow responses
- Use a smaller model: `export CBFLOW_MODEL=mistral:7b`
- On Apple Silicon: ensure Ollama uses GPU (default on M1/M2/M3)
- On Linux: install NVIDIA drivers for GPU acceleration
