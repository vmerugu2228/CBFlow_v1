# CBflow AI Agent — Semiconductor-Specialized Private Assistant

## Context

CBflow v2.0.0 is a comprehensive ASIC PD automation framework with 12 design flows, RACE engine, and FlowTracer GUI. The goal is to build a **private, secure AI agent** specialized in semiconductor physical design that integrates directly into CBflow. The agent uses Claude as the LLM backend, operates entirely within customer infrastructure, and provides domain-expert assistance for PD flow management, timing closure, QoR analysis, and debug.

**Why:** Engineers currently need deep expertise to interpret timing reports, debug flow failures, optimize MMMC scenarios, and make config decisions. An AI agent with semiconductor domain knowledge + direct access to CBflow's RACE DB, QoR metrics, and configs can dramatically accelerate these tasks.

## Architecture

```
CUSTOMER INFRASTRUCTURE
┌────────────────────────────────────────────────────────┐
│                                                        │
│  cbflow agent ask "why did CTS fail?"                  │
│  cbflow agent chat (interactive REPL)                  │
│  cbflow agent diagnose (auto-diagnosis)                │
│  GUI Chat Panel (WebSocket in dashboard)               │
│         │                                              │
│         ▼                                              │
│  ┌─────────────────────────────────────────┐           │
│  │  AGENT CORE (PD/utils/agent/)           │           │
│  │  agent_core.py — message loop + tools   │           │
│  │  agent_tools.py — 13 tool definitions   │           │
│  │  agent_prompts.py — PD domain knowledge │           │
│  │  agent_security.py — data sanitization  │           │
│  └──────────┬──────────────────────────────┘           │
│             │ queries                                   │
│  ┌──────────▼──────────────────────────────┐           │
│  │  EXISTING CBFLOW                        │           │
│  │  race_engine.py (StatusDB, DAG)         │           │
│  │  qor_report_cmd.py (timing/power/area)  │           │
│  │  mmmc_manager_cmd.py (scenarios)        │           │
│  │  trending_cmd.py (cross-run metrics)    │           │
│  │  tcl_config_parser.py (configs)         │           │
│  └─────────────────────────────────────────┘           │
│                                                        │
└───────────────────┬────────────────────────────────────┘
                    │ HTTPS (summaries only, never design data)
                    ▼
         ┌─────────────────────┐
         │  Claude API Backend │
         │  Option A: Bedrock  │  (VPC-isolated, PrivateLink)
         │  Option B: Direct   │  (ZDR, no training)
         └─────────────────────┘
```

**Key Security Principle:** "Summaries up, never data out" — tools extract metrics/status and send only summarized numbers to Claude. Raw design files (netlist, GDS, DEF) are never included in prompts.

## Deployment Options (Customer Choice)

| Option | Privacy Level | Requirement |
|--------|-------------|-------------|
| AWS Bedrock + PrivateLink | Highest — data never leaves VPC | AWS account |
| Google Vertex AI | High — GCP isolation | GCP account |
| Direct API + ZDR | Good — zero data retention | API key only |

## CLI Commands

```
cbflow agent ask "why did CTS fail?"              # Single question
cbflow agent chat                                   # Interactive session
cbflow agent diagnose                               # Auto-diagnose failures
cbflow agent review --milestone CTS_EXIT            # Check exit criteria
cbflow agent compare --run1 run1 --run2 run2        # Compare runs
cbflow agent suggest --stage cts1                   # Optimization tips
```

## Files to Create

```
PD/utils/agent/
├── __init__.py
├── agent_cmd.py          # CLI entry (argparse, dispatches to handlers)
├── agent_core.py         # Message loop, tool dispatch, session management
├── agent_tools.py        # 13 tool definitions (JSON Schema) + handlers
├── agent_prompts.py      # System prompt: PD domain knowledge + run context
├── agent_security.py     # Content filtering, path containment, audit log
├── agent_config.py       # API client factory (Bedrock/Vertex/Direct)
├── agent_rag.py          # RAG retrieval (Phase 3, optional)
└── agent_websocket.py    # WebSocket for GUI chat panel (Phase 3)

PD/config/agent/v1.0.0/
└── agent_config.tcl      # Backend, model, security settings
```

## Files to Modify

| File | Change |
|------|--------|
| `PD/bin/cbflow` | Add `agent)` case to dispatcher (~3 lines) |
| `PD/completions/cbflow.bash` | Add agent subcommand completions |
| `PD/utils/dashboard/race_dashboard.py` | Add `/ws/agent` WebSocket (Phase 3) |
| `PD/utils/dashboard/templates/dashboard.html` | Add chat panel UI (Phase 3) |

## 13 Agent Tools

### Query Tools (read-only, always safe)
1. **query_run_status** — RACE DB status via `StatusProvider`
2. **query_qor_metrics** — Timing/power/area via `ReportParser`
3. **query_dag_structure** — DAG topology via `DagBuilder`
4. **query_trending** — Historical metrics via `TrendingDB`
5. **compare_runs** — Side-by-side QoR comparison
6. **check_milestone** — Exit criteria evaluation

### Read Tools (file access, read-only, capped)
7. **read_log_errors** — Error/warning extraction from logs
8. **read_config** — Parse TCL configs (structured, not raw)
9. **read_mmmc_scenarios** — MMMC corner/mode/scenario data
10. **read_report_excerpt** — Truncated report content (200 line cap)

### Action Tools (mutating, require confirmation)
11. **execute_cbflow_command** — Whitelisted cbflow commands only
12. **modify_config_setting** — Update override configs (with backup)
13. **suggest_mmmc_change** — Propose scenario changes (returns diff, no auto-apply)

## System Prompt Structure

**Layer 1 — Domain Knowledge (~6K tokens, cached):**
- PD flow methodology (synthesis → place → CTS → route → signoff)
- Timing closure: WNS/TNS interpretation, MMMC, OCV, clock gating
- QoR thresholds per milestone (FP_EXIT, PLACE_EXIT, CTS_EXIT, MTO)
- Common failure patterns and fixes
- Tool-specific knowledge (FC-RM, PT, ICV commands)

**Layer 2 — Run Context (~2K tokens, dynamic):**
- Current run directory, flow type, project, phase
- Stage statuses with runtimes
- Recent failures with exit codes

**Layer 3 — Tool Instructions (~1K tokens):**
- When to use which tool
- Always check status before diagnosing
- Never execute without confirmation

## Security

| Data Type | Sent to Claude? |
|-----------|----------------|
| RTL/netlist/GDS/DEF | Never |
| QoR metrics (WNS, TNS) | Yes |
| Run status (DONE/FAIL) | Yes |
| Error log excerpts | Yes (truncated) |
| Config key-values | Yes |
| Cell library names | Redacted |
| Absolute paths | Converted to relative |

**Guardrails:**
- 13 whitelisted tools only — no arbitrary code execution
- Path containment — files only within `$CBFLOW_ROOT` or `$run_dir`
- Command whitelist — only predefined cbflow subcommands
- Output caps — 200 lines max per tool result
- Audit log — every tool call logged with user, timestamp, parameters

## Existing Code to Reuse (import, not modify)

| Module | Agent Usage |
|--------|-------------|
| `status_provider.py` | `StatusProvider.get_all_status()` |
| `qor_report_cmd.py` | `ReportParser.extract_timing()`, `.extract_power()` |
| `trending_cmd.py` | `TrendingDB.query_metric_history()` |
| `race_engine.py` | `DagBuilder.build()`, `RaceEngine` |
| `tcl_config_parser.py` | `get_flow_stages()`, `get_subnodes()` |
| `mmmc_manager_cmd.py` | MMMC config parsing |
| `checklist_cmd.py` | Milestone threshold evaluation |
| `node_manager.py` | DAG topology queries |

## Implementation Phases

### Phase 1: Foundation (Weeks 1-3)
- `agent_config.py` — API client factory (Bedrock/Direct)
- `agent_prompts.py` — Domain knowledge + context builder
- `agent_tools.py` — All 13 tool definitions, read-only handlers (1-10)
- `agent_core.py` — Message loop with tool dispatch
- `agent_cmd.py` — `cbflow agent ask` and `cbflow agent chat`
- `agent_security.py` — Path containment, content filtering, audit
- Wire into `bin/cbflow`

**Test:** `cbflow agent ask "what is the current run status?"` returns accurate answer from RACE DB.

### Phase 2: Actions + Diagnosis (Weeks 4-5)
- Action tool handlers (11-13) with confirmation
- `cbflow agent diagnose` — automated failure analysis
- `cbflow agent review --milestone` — exit criteria check
- `cbflow agent compare` — multi-run comparison
- `cbflow agent suggest` — optimization recommendations

**Test:** `cbflow agent diagnose` after CTS failure identifies root cause and suggests fix.

### Phase 3: GUI + RAG (Weeks 6-8)
- WebSocket chat in dashboard (`/ws/agent`)
- Chat panel UI in `dashboard.html`
- ChromaDB RAG for EDA tool documentation
- Contextual retrieval for design methodology docs

**Test:** Dashboard chat panel answers "how do I fix congestion?" with FC-RM command references.

### Phase 4: Advanced (Weeks 9-12)
- Proactive monitoring (auto-flag QoR regressions)
- Email integration (AI-generated run summaries)
- AutoPPT commentary generation
- MCP server mode for Claude Desktop

## Dependencies

- `anthropic` Python SDK (pip install anthropic)
- `websockets` (Phase 3 only)
- `chromadb` (Phase 3 only, optional)
- Everything else is Python stdlib (already required by CBflow)

## Verification

1. `cbflow agent ask "show run status"` — queries RACE DB, returns formatted status
2. `cbflow agent ask "why did place1 fail?"` — reads logs, identifies error, suggests fix
3. `cbflow agent diagnose` — auto-analyzes all failures, produces structured report
4. `cbflow agent review --milestone CTS_EXIT` — evaluates QoR against thresholds
5. `cbflow agent chat` — multi-turn conversation maintaining context
6. Security: verify no design file content appears in API request logs
7. Audit: verify `agent_audit.log` captures all tool invocations
8. Bedrock: verify agent works with `ANTHROPIC_API_KEY` unset when Bedrock configured
