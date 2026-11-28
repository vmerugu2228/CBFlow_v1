# CBflow API Study — Where Claude and Other APIs Can Make CBflow Work Better

*Research note, 2026-11-28. Research only: no code or config was changed. All prices are public list prices on that date. Check them again before you budget.*

---

## 1. Executive summary — top recommendations, ranked by value / effort

| # | Recommendation | Value | Effort | Privacy mode |
|---|---|---|---|---|
| 1 | **Add prompt caching to SmartGenie cloud / hybrid** (`PD/ai/cbflow_agent.py`, `cbflow_local_agent.py`). The static `SYSTEM_PROMPT` + `TOOLS` are re-billed on every turn today. | High | Hours | Unchanged. Caching is Legacy-ZDR eligible. |
| 2 | **Failed-stage log triage on FAIL** (RACE engine hook). A Haiku 5.5 call with a strict JSON schema classifies the failure (license, tool crash, missing input, QoR, config), gives a fix suggestion, and writes the result to `run_logs` / the dashboard. | High | 1–2 days | Sends only the log excerpt. Local Ollama fallback. |
| 3 | **Nightly regression digest via the Message Batches API** (50 % off). One request per failed or regressed run is submitted at night; the digest is ready by morning. | High | 2–3 days | Not ZDR (batches kept 29 days). Use summarized metrics, not raw netlists. |
| 4 | **Slack / Teams notifications** next to the existing SMTP email (`PD/utils/commands/email_cmd.py`). | Medium-High | 1 day | Message text only |
| 5 | **Checklist triage + sign-off / release-note drafting** using structured outputs on the `checklist` skill flow. Drafts go into the release dir for a human to approve. | High | 3–5 days | Checklist rows + report excerpts |
| 6 | **Model routing + cost guardrails.** Haiku for classify/extract, Sonnet for reports, Opus for agentic ECO. Add token counting, Admin usage/cost reports, a workspace spend limit, and a SmartGrid "AI spend" tile. | Medium | 2–3 days | n/a |
| 7 | **Observability stack**: Prometheus + Grafana, the FlexLM exporter for EDA licenses, and OpenTelemetry spans for RACE jobs. Gives AI triage real signals ("license denied at 02:13"). | Medium-High | 1 week | All on-site |
| 8 | **Knowledge-base upgrade**: Docling for spec / PDF ingestion and pgvector or Qdrant for retrieval. Optionally use Voyage `voyage-code-4` embeddings, or stay with local embeddings for IP. | Medium | 1 week | Local by default |
| 9 | **Managed Agents with a self-hosted sandbox** for scheduled nightly ECO / DRC / timing loops. Uses *outcomes* (a rubric = the no-regression gate), *scheduled deployments* and *session budgets*. | High (long-term) | 2–4 weeks | Tool execution stays on-site, but tool I/O goes to Anthropic. Not ZDR. |
| 10 | **Ticketing** (Jira Cloud REST v3 / Linear GraphQL) for checklist FAILs that recur across runs, and **Slurm / cloud batch** as a second job backend after LSF. | Medium | 1–3 weeks | Ticket text only |

The thread through all of these: CBflow already has the hard parts — a structured run DB, checklists with IDs and thresholds, skills that encode ECO / DRC / floorplan know-how, and an MCP server. The cheapest gains come from calling Claude **on events the engine already has** (FAIL, release, nightly), with **caching, batching and model routing** on from day one.

---

## 2. Where CBflow stands today

| Area | Current state (from the repo) |
|---|---|
| SmartGenie | `PD/ai/README.md`. Four modes: **local** (Ollama, `qwen2.5:14b`, ChromaDB, fully private), **hybrid** (`--hybrid`: Claude answers, local learning), **cloud** (`cbflow_agent.py`: Claude tool-use loop with bash/read/write/query_db/search_knowledge/learn_experience), **code** (Claude Code + the SmartGenie MCP tools). |
| Claude call shape | `cbflow_agent.py::_create`: `client.beta.messages.create(model="claude-opus-5-5", output_config={"effort": "high"}, betas=["server-side-fallback-2026-07-01"], fallbacks="default", max_tokens=16000)`. **No `cache_control`, no structured outputs, no batches, no token counting.** |
| MCP server | `PD/ai/cbflow_mcp_server.py`: stdio, or HTTP bound to `127.0.0.1` (a `--public` mode needs `CBFLOW_MCP_TOKEN` and binds `0.0.0.0`). Tools: run_command (allow-listed), read/write_file (contained to the install root), query_race_db (SELECT-only), list_workspace, get_run_status, parse_tcl, analyze_log, search_knowledge, learn_experience. |
| Agentic skills | `.claude/skills/{floorplan,timing-eco,drc-fix,library-manager,checklist,mmmc-manager}/SKILL.md`. They are used interactively from Claude Code. |
| Knowledge | ChromaDB (`cbflow_knowledge.py`) over ~200 `PD/ai/eda_guides/*.md` + CBflow docs/code. A LoRA fine-tune path exists in `PD/ai/fine_tune/`. |
| Notifications | SMTP email only (`PD/utils/commands/email_cmd.py`). No Slack/Teams/Jira code found. |
| Jobs | LSF `bsub` (`lsf_config.tcl`, `PD/utils/commands/lsf_cmd.py`, `global/utils/utilities/v1.0.0/launch_utils.tcl`), local, xterm. No Slurm or cloud batch. |
| Run data | RACE SQLite DB with 13 tables (`jobs`, `run_logs`, `checklist_results`, `release_info`, `metrics_snapshot`, …), the run dashboard and SmartGrid. |
| Metrics | `PD/utils/commands/metrics_cmd.py` (JSON export), `trending_cmd.py`, `qor_report_cmd.py`. No Prometheus/OTel. |

---

## 3. Claude API opportunities mapped to CBflow pain points

Model facts and prices used below:

| Model (alias) | Input / Output $/MTok | Cache read | Batch in/out | Notes |
|---|---|---|---|---|
| Claude Opus 5.5 (`claude-opus-5-5`) | $4 / $20 | $0.20 (0.05x) | $2 / $10 | 1M ctx, 128K out. Thinking always on; **effort** is the control (default `medium`). **Forced `tool_choice` returns 400** (use `auto` + `strict: true` or structured outputs). |
| Claude Sonnet 5.5 (`claude-sonnet-5-5`) | $2 / $10 | $0.10 (pricing page; the bundled skill says $0.20, so treat as uncertain) | $1 / $5 | 1M ctx. Effort default `high`. Forced `tool_choice` 400s. |
| Claude Haiku 5.5 (`claude-haiku-5-5`) | $0.10 / $0.50 (≤100K prompt); $0.50 / $2.50 above | $0.01 | $0.05 / $0.25 | 1M ctx. Classification / extraction / routing. **No server-side fallback.** |
| Claude Fable 5.1 (`claude-fable-5-1`) | $10 / $50 | $0.25 | $5 / $25 | Top tier. **Covered Model: 30-day retention required, not available under Legacy ZDR.** The pricing page also lists a newer *Fable 5.2* ($8 / $40) that the bundled skill does not yet document. |

Cache writes cost 1.25x base input (5-minute TTL) or 2x (1-hour TTL). Batch, cache and data-residency multipliers stack. `inference_geo: "us"` adds 1.1x. Sources: pricing page and `claude-api/shared/models.md`.

**Data-handling facts that drive every design choice** (from *API and data retention*):

- Messages API, prompt caching, structured outputs, token counting, citations, PDF input (inline) and the web search/fetch tools (without dynamic filtering) are **Legacy-ZDR eligible**.
- **Not ZDR**: Batch API (29-day retention), Files API (kept until deleted), MCP connector, Agent Skills API, code execution / programmatic tool calling (≤30 days), and Managed Agents (transcripts persist until deleted). The one exception is **self-hosted** Managed Agents under Legacy ZDR.
- Retained data is not used for training without express permission. Flagged content may be kept up to 2 years.
- CBflow's **local mode** is the only path where nothing leaves the site.

### 3.1 Failed-stage log triage (quick win)

- **What it does.** When a RACE job ends FAIL (or `handler_validate` rejects outputs), the engine takes the tail plus the error-pattern hits of `work/<FLOW>/<node>/run/<job>.log`. It reuses the regex extractor already in `cbflow_mcp_server.py::tool_analyze_log`, adds stage, tool and config keys, and asks Haiku 5.5 for a structured verdict: `{category, root_cause, evidence_lines, suggested_fix, rerun_safe, confidence}`.
- **Plugs into.** `global/utils/commands/race_engine.py` (job-completion path → new `ai_triage` column/table next to `run_logs`), the run dashboard node tooltip (`global/utils/dashboard/`), and `cbflow run status --details`.
- **Why it beats today.** Users read raw logs or ask SmartGenie interactively. This is automatic, cheap, and lands where the failure is shown. Structured outputs make it machine-usable, e.g. auto-retry when `category == license_unavailable`.
- **Cost.** About 8K input / 500 output tokens per failure on Haiku 5.5 is roughly **$0.001**. Even 1,000 failures/month costs about $1. Effort: 1–2 days.
- **Risks.** Log lines can contain design names, paths and cell names. Send excerpts only, add a redaction pass for hierarchy names if needed, and keep `CBFLOW_AI_MODE=local` as an Ollama fallback. With Opus/Sonnet 5.5 you cannot force a tool call, so use `output_config.format` (JSON schema).
- **Sketch.**
  ```python
  resp = client.messages.create(
      model="claude-haiku-5-5", max_tokens=1500,
      system=[{"type": "text", "text": TRIAGE_RULES, "cache_control": {"type": "ephemeral"}}],
      messages=[{"role": "user", "content": excerpt}],
      output_config={"format": {"type": "json_schema", "schema": TRIAGE_SCHEMA}})
  db.execute("INSERT INTO ai_triage ...", json.loads(resp.content[0].text))
  ```

### 3.2 Prompt caching for SmartGenie and large configs / reports (quick win)

- **What it does.** Marks the stable prefix (tools → system prompt → large static context such as `flow_registry.tcl`, the node config, the skill text) with `cache_control`. Later turns of an agent loop then read it at 0.05x on Opus 5.5.
- **Plugs into.** `PD/ai/cbflow_agent.py::_create` (`system=` as a block list with a breakpoint, or top-level automatic caching) and `cbflow_local_agent.py`'s Claude path.
- **Why.** A 50-turn agent loop that re-sends a 10–20K-token prefix pays full price 50 times today. Caching pays back after one read (5-minute TTL) or two reads (1-hour TTL).
- **Watch-outs** (from `shared/prompt-caching.md`):
  - Don't interpolate timestamps or the user name into the system prompt.
  - Keep tool order stable.
  - Don't change `effort` mid-conversation. It invalidates the cache.
  - Use the 1-hour TTL when a human pauses between turns.
- **Effort.** Hours. Verify with `usage.cache_read_input_tokens`.

### 3.3 Nightly regression analysis with the Batch API

- **What it does.** A nightly job (cron, or a CBflow `cbflow flow metrics` subcommand) collects every run that failed, regressed in WNS/TNS/DRC count/area/power versus its last published run (from `metrics_snapshot`, `qor_report_cmd.py`, `trending_cmd.py`), or newly FAILed a checklist row. It submits one batch request per run (Sonnet 5.5 at batch price) and posts a ranked digest by morning.
- **Batch facts.** Up to 100,000 requests / 256 MB per batch. Most finish within 1 hour, 24 hours max. Results are available for 29 days. All Messages features work (caching too). No tool loop inside a request, so pre-fetch inputs.
- **Cost.** 200 runs × 30K in / 2K out on Sonnet 5.5 batch is about **$8/night**, less with a cached shared rubric.
- **Risks.** Batch is **not ZDR**. Send metric tables and report excerpts, not netlists/DEF/GDS. Results go to SmartGrid / Slack (§4.2).

### 3.4 Checklist triage, fix proposals and sign-off / release-note generation

- **What it does.** Takes the `cbflow flow checklist status --milestone <M> --run-dir .` output (check ID, value, threshold, phase, blocking flag) plus the report snippets each check cites. Claude ranks failures, proposes run-local `override_config.<node>.tcl` snippets or reruns, says whether a waiver fits policy (`waiver_config.tcl`: ≤90 days, no BTO/MTO waivers), and drafts the **sign-off summary** and **release notes** for `cbflow run release`.
- **Plugs into.** The existing `checklist` skill logic. Promote it to a headless command (`cbflow flow checklist triage --ai`), writing `checklist_results` annotations plus a `RELEASE_NOTES.md` draft in the release dir. SmartGrid shows the draft for approval.
- **Why.** Today it needs an interactive Claude Code session. Headless plus structured output makes it part of every publish. **Citations** (ZDR-eligible) can tie each claim to a report line, so auditors see evidence.
- **Cost.** Sonnet 5.5, about 40K in / 4K out ≈ $0.12 per milestone. Effort: 3–5 days.
- **Risk.** It must never auto-apply waivers. Keep a human sign-off, which matches CBflow's ownership checks.

### 3.5 Timing / DRC ECO agents with outcome grading (Managed Agents)

- **What it does.** Turns the `timing-eco` and `drc-fix` skills into Managed Agents:
  - Create the **agent** once (model, system, tools, skills; `ant apply` keeps it versioned).
  - Each run is a **session** that starts with `user.define_outcome`. Its rubric is CBflow's no-regression gate: "setup WNS ≥ 0 in all signoff scenarios; hold TNS not worse; DRC count not higher; PV LVS clean". The grader iterates up to `max_iterations` (default 3, max 20).
  - **Scheduled deployments** (cron + timezone) run it nightly.
  - **Session budgets** put a hard dollar cap on each session.
  - **Self-hosted sandbox** (`config.type: "self_hosted"`, `EnvironmentWorker` / `ant beta:worker poll`) keeps OpenROAD/OpenSTA/KLayout execution and the files on CBflow hosts. Connectivity is outbound-only.
- **Plugs into.** `cbflow run add-node / retrace` and the ECO flow. The worker runs inside the `cbflow-oss` container environment. Skills can load from the repo's `.claude/skills`.
- **Why.** This replaces "engineer drives Claude Code by hand" with unattended loops that only stop when the gate passes or the budget is hit.
- **Cost.** Tokens at model rates plus **$0.08 per session-hour** of `running` time (idle doesn't count). No batch discount. A 1-hour Opus 5.5 ECO loop at ~2M cached input / 200K output costs roughly $5–10. Effort: 2–4 weeks.
- **Risks.** Managed Agents is **beta** and **not ZDR** except self-hosted under Legacy ZDR. Even self-hosted, *tool inputs/outputs* (command lines, report text) flow to Anthropic's control plane. Pilot on opensky / sky130 first, never on foundry-NDA PDK data, unless legal approves.

### 3.6 Natural-language queries over the RACE DB / SmartGrid

- **What it does.** "Which P1 runs of gcd failed PV this week and why?" Claude turns this into SELECT-only SQL against the RACE DB and the SmartGrid tracker DB (`global/utils/project_dashboard/tracker_db.py`), runs it locally, and summarizes.
- **Plugs into.** The existing `cbflow_query_race_db` MCP tool (already SELECT-restricted) plus a chat box in SmartGrid that calls the Messages API from the **server side**.
- **Why.** Leads get answers without SQL. The schema is cached (it's stable), and only result rows go to Claude.
- **Cost.** Haiku or Sonnet, cents per question.
- **Risk.** Results can name blocks or people. Restrict tables, and keep it inside the dashboard's ownership/403 rules.

### 3.7 Spec-to-RTL, testbench and DV assistance

- **What it does.** Builds on RTL_SPEC (`RTL/utils/oss/spec_tool.py`), uvmgen (`DV/utils/oss/uvmgen.py`) and `dv_tool.py`:
  - Draft user-owned `<d>_ref_model.sv` / `<d>_coverage.sv` / `<d>_tests.sv` from the YAML spec + SystemRDL + vPlan.
  - Explain coverage holes from the `covmerge` output.
  - Triage `dv_tool.py triage` failures.
  - **PDF input** (inline PDFs are ZDR-eligible) reads vendor IP datasheets for the spec.
- **Why.** It removes the most manual DV step. Verilator/slang lint is the deterministic checker, so a "re-run at higher effort on failure" pattern works well.
- **Cost / model.** Opus 5.5 at `medium`–`high` effort for RTL/TB generation, Haiku for triage.
- **Risk.** RTL is core IP. Use the Messages API (ZDR-eligible if the org has ZDR), not Files/Batch, for proprietary RTL.

### 3.8 Files API for large reports

- Upload once, reference by `file_id` across many calls. Limits: 500 MB per file, 100 GB per org. Upload/list/delete are free; content is billed as input tokens.
- Useful for big timing/DRC reports reused across a triage session or an outcome loop.
- **Not ZDR** (kept until deleted) and not on Bedrock/Vertex.
- For CBflow, it is usually better to **pre-digest reports locally** (the existing parsers in `oss_checkgrp_*.tcl`, `qor_report_cmd.py`) and send excerpts. Use Files only for Managed Agents session resources.

### 3.9 MCP connector to the existing CBflow MCP server

- The MCP connector (beta `mcp-client-2025-11-20`) lets the Messages API call a **remote** MCP server. Anthropic connects to it server-side, so the URL must be reachable from Anthropic.
- CBflow's server is stdio or `127.0.0.1` by default. Exposing it with `--public` would expose `run_command` / `write_file` to the internet behind one bearer token.
- **Recommendation:**
  - Keep the **client-side** pattern for cloud mode: SmartGenie runs the tools locally, as `cbflow_agent.py` does today.
  - Use MCP only via Claude Code / Claude Desktop (local stdio).
  - If a remote connector is ever needed, publish a **read-only subset server** (status, query_race_db, analyze_log, search_knowledge) behind TLS + auth.
  - MCP connector data is **not ZDR**. An "MCP tunnels" research preview exists; not evaluated here.

### 3.10 Web search / fetch for EDA and PDK lookups

- `web_search_20260209` / `web_fetch_20260209`, with dynamic filtering on Opus/Sonnet 5.5. Web search costs $10 per 1,000 searches; web fetch has no tool fee.
- Good for "what does OpenROAD error GRT-0116 mean" or "latest sky130 open_pdks release". Restrict with `allowed_domains` (github.com/The-OpenROAD-Project, skywater-pdk docs, readthedocs).
- Search and fetch are ZDR-eligible *without* dynamic filtering. Dynamic filtering is not.

### 3.11 Advisor tool (cost lever for agentic flows)

- A Sonnet 5.5 executor consults an Opus 5.5 (or Fable) advisor on hard decisions. Beta `advisor-tool-2026-03-01`, ZDR-eligible.
- Fits SmartGenie cloud mode: most turns are routine CLI calls, and a few are judgment calls (which ECO to try).
- The skill notes that this only pays if the executor actually consults. Benchmark it against Opus alone first.

### 3.12 Model choice per task

| Task | Model | Effort | Why |
|---|---|---|---|
| Log classification, check categorization, routing | Haiku 5.5 | low/medium | Lowest cost; schema output |
| Digest, release notes, checklist triage, NL→SQL | Sonnet 5.5 | medium/high | Strong writing at half the price of Opus |
| Agentic ECO / floorplan / DRC loops, RTL/TB generation | Opus 5.5 | medium→high | Long-horizon tool use; re-run failures at higher effort |
| Rare hardest analysis (multi-block hierarchical closure) | Fable 5.1 | — | Only if the org accepts 30-day retention |

### 3.13 Cost and governance APIs

- **Token counting** (`/v1/messages/count_tokens`, ZDR-eligible): pre-check before sending large reports.
- **Admin API usage/cost reports** (`/v1/organizations/usage_report/messages`, `/cost_report`; raw HTTP, Admin key): a SmartGrid "AI spend" tile per workspace/key.
- **Per-project workspaces/keys** make spend attributable (one per discipline).
- **Workspace spend limits** (spend-limit endpoints are early-access for Console orgs; the Console UI is the fallback).
- **Session budgets** for Managed Agents.
- **OpenTelemetry**: SDK spans (beta) for SmartGenie tracing. They join the observability stack in §4.4.

---

## 4. Non-Anthropic APIs by category

### 4.1 Compute / job scheduling

| API | What it adds to CBflow | Maturity | Cost / licence | Integration point |
|---|---|---|---|---|
| **IBM LSF**: native Python API (`lsf-python-api`, SWIG over the C API), Application Center REST, LSF Web Service (OpenAPI) | Programmatic submit/status instead of parsing `bsub`/`bjobs` text. Feeds the AI triage exact exit/pending reasons. | Mature. LWS is newer; check your version. | Part of the LSF licence | `PD/utils/commands/lsf_cmd.py`, `launch_utils.tcl::submit_job` |
| **Slurm REST** (`slurmrestd`, OpenAPI 3) | Second scheduler backend for sites or universities without LSF | Mature. JWT auth; SchedMD says don't expose it directly to the internet | GPL, free | New `flow(scheduler) slurm` branch in `launch_utils.tcl` |
| **AWS Batch** | Cloud burst for OSS flows (docker images already exist via `cbflow-oss`) | GA | No Batch fee; pay for EC2/Fargate | Container submit backend. Data leaves the site, so OSS/sky130 only unless approved. |
| **Google Cloud Batch** | Same, on GCP | GA | No Batch fee; pay for VMs/disks (logging/storage extra) | Same |

### 4.2 CI / VCS / releases

| API | Adds | Cost / licence | Integration |
|---|---|---|---|
| **GitHub REST** (releases, checks, Actions) | CI for CBflow itself (`cbflow-test` E2E in test_mode on PRs), tool releases | Hosted runners billed per minute (prices cut Jan 2026). A $0.002/min **self-hosted** fee announced for Mar 2026 was **postponed**; current status per third-party reports is still free (unverified on GitHub's page). | `.github/workflows` running `bin/cbflow test`. Keep **design** releases in CBflow's own release area, not Git. |
| **GitLab Releases API + Generic package registry** | Same, for on-prem GitLab (common at chip companies, keeps code on-site) | Self-managed GitLab | Release CBflow versions; link `cbflow run release` tags to a GitLab release for traceability |

### 4.3 Notifications / ticketing

| API | Adds | Notes | Integration |
|---|---|---|---|
| **Slack incoming webhooks / `chat.postMessage`** | Run-done/FAIL/release/digest messages to channels | Webhooks are simplest (one URL, cannot delete messages). `chat.postMessage` needs a bot token with `chat:write`, ~1 msg/s per channel. | New `notify_cmd.py` next to `email_cmd.py`, hooked on job end + release publish |
| **Microsoft Teams via Workflows (Power Automate) webhooks** | Same for Teams sites | The old Office 365 Connectors were retired (the final date moved several times in 2024–2026; latest notice MC1181996 said May 2026). Use **Workflows** webhooks. Exact current status not verified. | Same module, Adaptive Card payload |
| **Jira Cloud REST v3** (`POST /rest/api/3/issue`) | Auto-file a ticket when a checklist check FAILs in N consecutive runs, or a release is blocked; AI-drafted description with evidence | API token / OAuth; included in Jira Cloud plans | Checklist triage (§3.4) → ticket, ID stored in `checklist_results` |
| **Linear GraphQL** (`https://api.linear.app/graphql`, `issueCreate`) | Same for Linear users | API key or OAuth; webhooks available | Same |

### 4.4 Storage / observability

| Tool / API | Adds | Licence / cost | Integration |
|---|---|---|---|
| **S3 API** (AWS S3 or on-prem **MinIO**) | Versioned, immutable storage for releases and library tags; lifecycle rules for old run dirs | MinIO server is **AGPLv3** (commercial licence available); SDKs Apache-2.0 | `release_utils.tcl` publish step can mirror `<release>/<phase>/<block>/<FLOW>/<tag>` to a bucket |
| **Prometheus** (+ **Pushgateway** for batch jobs) | Time-series of stage runtimes, queue wait, pass/fail, QoR | Apache-2.0. Pushgateway's own docs limit it to *service-level batch-job outcomes*, which fits RACE job results. | Push at job end from `race_engine.py`; a SmartGrid exporter for project-level metrics |
| **flexlm_exporter** (lmutil lmstat → Prometheus, Grafana dashboard 3854) | **EDA licence** usage/denials (Synopsys/Cadence FlexNet). Explains "tool never ran" failures and feeds triage. | Open source (Go); check maintenance | Sidecar on the licence server; triage prompt can include "licence X saturated at failure time" |
| **Grafana** | Dashboards/alerts across runs, licences and LSF | Core **AGPLv3** | Complements SmartGrid (project view) with ops view |
| **OpenTelemetry** (Python SDK, OTLP exporters) | Traces per RACE run → job → tool invocation; correlate with Claude API spans | Apache-2.0; traces/metrics stable in Python | `race_engine.py`, `start_run.py`; Claude SDK spans (beta) join the same trace |
| BI: **Apache Superset** (Apache-2.0) / **Metabase** (AGPL core) | Ad-hoc analysis over exported RACE/SmartGrid data | Self-hosted | `metrics_cmd.py export` → Postgres → BI |

### 4.5 Knowledge / search / embeddings

| Tool / API | Adds | Licence / cost | Notes |
|---|---|---|---|
| **Voyage AI** (`voyage-4`, `voyage-code-4`, `voyage-context-4`, `rerank-3`) | Higher-quality retrieval over docs, TCL and command files for SmartGenie | Usage-based via MongoDB Atlas model API keys; free-tier tokens per Voyage docs (rates not verified here) | Anthropic has **no embedding model** and points to Voyage. `voyage-4-nano` is open-weight (Apache-2.0) and can run **on-site**, which suits IP. |
| **pgvector** (PostgreSQL licence) / **Qdrant** (Apache-2.0) / **Chroma** (Apache-2.0, used today) | Vector store | Self-hosted, free | Keep Chroma for single-user. Use pgvector if SmartGenie `serve` becomes multi-user, so it shares Postgres with BI. |
| **Docling** (IBM, MIT) | PDF → Markdown/JSON with table structure: foundry docs, IP datasheets, specs | Free, runs locally on CPU | Ingest into the KB and RTL_SPEC; much better than plain-text PDF extraction for tables |

### 4.6 EDA / PDK / IP data

| Item | Status | Use in CBflow |
|---|---|---|
| **Efabless** | **Shut down early 2025.** Assets acquired by **ChipFoundry** (Sep 2025), which restarted SkyWater 130 nm shuttles and adopted **LibreLane** | Don't build on Efabless platform APIs. ChipFoundry shuttle submission is a possible future "tapeout" target for opensky (no public API verified). |
| **LibreLane** (FOSSi; ex-OpenLane 2, released Jul 2025) | Active | Reference flow to benchmark CBflow's OSS PNR QoR; borrow configs |
| **ciel** (FOSSi; formerly volare) — PDK version manager | Active, PyPI | Pin and fetch `sky130A` by open_pdks commit. Record the PDK hash in the library tag / `tech_config.tcl` for reproducibility. |
| **SystemRDL / PeakRDL** | PeakRDL CLI LGPL-3.0; plugins licensed separately (e.g. PeakRDL-uvm GPL-3.0; PeakRDL-ipxact LGPL-3.0) | Already used by RTL_SPEC. Check plugin licences before redistribution. |
| **IP-XACT IEEE 1685-2022** (IEC 62014-4:2025) | Active standard; Accellera user guide (2023) | CBflow validates 1685-2014. Consider supporting 2022 schemas. |
| Commercial EDA vendor APIs (Synopsys/Cadence cloud, licence portals) | Not publicly documented | Not evaluated; vendor NDA |

No public API for foundry PDK data or for verification-coverage services was found that fits CBflow. Coverage stays inside the tools (Verilator/VCS/Questa), exported to `dv_tool.py covmerge`. *Uncertain — not exhaustively searched.*

---

## 5. Architecture sketch and privacy boundary

```
 ┌──────────────────────────── SITE / ON-PREM (never leaves) ───────────────────────────────┐
 │                                                                                          │
 │  EDA tools (FC/Innovus/PT/…; OSS in docker)   PDK/foundry data   netlists/DEF/GDS/SPEF   │
 │        │                                                                                 │
 │  RACE engine (race_engine.py) ──► RACE SQLite DB ──► Run dashboard / SmartGrid            │
 │        │  job end / FAIL / release / nightly events                                      │
 │        ▼                                                                                 │
 │  ┌───────────────── CBflow AI Gateway (new, small Python module) ─────────────────┐      │
 │  │ 1. extract + redact (log tails, metric tables, checklist rows — no layouts)    │      │
 │  │ 2. policy: per-project mode = local | cloud ; model router ; budgets           │      │
 │  │ 3. cache-aware prompt builder ; structured-output schemas ; audit log to DB    │      │
 │  └──────┬───────────────────────────────┬─────────────────────────────┬───────────┘      │
 │         │ local mode                     │ results                     │ worker (outbound │
 │         ▼                                ▼                             │  poll only)      │
 │  Ollama + ChromaDB/pgvector     Slack/Teams/Jira/email          Managed-Agents          │
 │  (SmartGenie local)             Prometheus/Grafana/OTel         self-hosted sandbox     │
 │                                 flexlm_exporter, MinIO          (runs cbflow-oss tools) │
 └─────────┬───────────────────────────────────────────────────────────────┬────────────────┘
           │ HTTPS: excerpts / metrics / prompts                           │ tool I/O text
 ══════════╪════════════════════ PRIVACY BOUNDARY ═════════════════════════╪═════════════════
           ▼                                                               ▼
   Claude API — Messages (ZDR-eligible), Batches / Files (not ZDR), Managed Agents control plane
   (not ZDR unless self-hosted + Legacy ZDR), web search/fetch, Admin usage/cost API
```

**What never leaves the site:**
- GDS/OASIS, DEF, full netlists, SPEF, LEF/lib from foundry PDKs.
- Licence files, proprietary RTL (unless the project opts in and the org has ZDR).
- RACE DB files themselves (only query *results*).
- Credentials.

**What may leave, per project policy:**
- Redacted log excerpts.
- Metric tables.
- Checklist rows.
- Report snippets.
- Open-source (sky130/opensky) design data.

Enforce this in one place, the gateway, with a per-project key such as `project(ai,mode) local|cloud` and `project(ai,allow_batch)`. That config change is *proposed only* and was not made.

---

## 6. Phased adoption plan

| Phase | Items | Exit criteria |
|---|---|---|
| **Quick wins (≤2 weeks)** | §3.2 caching in SmartGenie; §3.1 FAIL triage (Haiku, structured output, local fallback); Slack/Teams notifier; per-discipline API workspaces + spend limit; token counting on large prompts | Cache-read share >70 % of input on agent loops; triage visible on the dashboard for all FAILs; spend per workspace visible |
| **Medium (1–2 months)** | §3.3 nightly Batch digest; §3.4 checklist triage + release-note drafts; §3.6 NL queries in SmartGrid; Prometheus + Pushgateway + flexlm_exporter + Grafana; OTel spans in the RACE engine; Docling + pgvector KB; Jira/Linear auto-tickets | Morning digest in the channel; release notes drafted on every publish; licence-denial failures auto-labelled |
| **Long term (quarter+)** | §3.5 Managed Agents (self-hosted sandbox) for nightly timing/DRC ECO with outcomes + scheduled deployments + session budgets; advisor-tool routing in cloud mode; Slurm / cloud-batch backend; ChipFoundry/LibreLane interop for opensky; eval suite (golden failures → expected triage) to hill-climb prompts | ECO loop closes a known-violating opensky block unattended within budget; eval pass rate tracked per prompt version |

### Cost-control tips

1. **Cache first, always**: stable prefix order tools → system → static context. No timestamps or user names in the system prompt. 1-hour TTL for human-paced sessions.
2. **Batch anything nobody waits for**: 50 % off, and it stacks with caching. Not available for Managed Agents.
3. **Route by task** (§3.12). Re-run only the *failures* at higher effort or a bigger model, using a deterministic checker (lint, STA gate, checklist).
4. **Pre-digest locally**: parse reports with the existing TCL/Python parsers and send tables, not 50 MB logs.
5. **Budgets**: Managed Agents session budget (hard $ stop), workspace spend limit, `max_tokens` per call, a MAX_TURNS cap (already 50 in `cbflow_agent.py`).
6. **Measure**: log every `usage` object to the RACE DB (`ai_calls` table: model, cache_read, cache_write, input, output, $). Reconcile monthly with the Admin cost report.
7. **Avoid cache breakers**: changing `effort`/`thinking`, tools or model mid-conversation.

---

## 7. Uncertain or unverified

- Sonnet 5.5 cache-read price: the pricing page says $0.10/MTok, the bundled skill says $0.20.
- Claude Fable 5.2 appears on the pricing page but not in the bundled model catalog. Its ID and API changes were not verified.
- Admin spend-limit endpoints are early-access for Console orgs. Availability for this org is unknown.
- MCP tunnels (research preview) were not evaluated.
- Self-hosted Managed Agents pricing: "contact your account team".
- Voyage per-token rates: aggregator figures conflict; see the MongoDB billing page.
- GitHub self-hosted runner fee: postponed; current "free" status comes from a third-party report.
- Teams connector retirement final date: changed several times; check MC1181996.
- LSF Web Service: support for your LSF version not checked.
- flexlm_exporter: maintenance status not checked.
- No public ChipFoundry submission API was found.

---

## 8. Sources

**Repository files**
- `CLAUDE.md`; `PD/ai/README.md`; `PD/ai/cbflow_agent.py`; `PD/ai/cbflow_local_agent.py`; `PD/ai/cbflow_mcp_server.py`; `PD/ai/cbflow_knowledge.py`; `PD/ai/fine_tune/README.md`; `PD/ai/eda_guides/`
- `.claude/skills/{floorplan,timing-eco,drc-fix,library-manager,checklist,mmmc-manager}/SKILL.md`
- `global/utils/commands/race_engine.py`; `global/utils/dashboard/`; `global/utils/project_dashboard/`; `global/utils/utilities/v1.0.0/launch_utils.tcl`
- `PD/utils/commands/{email_cmd,lsf_cmd,metrics_cmd,trending_cmd,qor_report_cmd}.py`

**Bundled claude-api skill** (`/private/tmp/claude-501/bundled-skills/2.1.311/.../claude-api/`)
- `shared/models.md`, `shared/cost-optimization.md`, `shared/prompt-caching.md`, `shared/tool-use-concepts.md`, `shared/platform-availability.md`, `shared/admin-api.md`, `shared/live-sources.md`
- `shared/managed-agents-overview.md`, `-outcomes.md`, `-scheduled-deployments.md`, `-self-hosted-sandboxes.md`, `-core.md`, `-multiagent.md`
- `python/claude-api/batches.md`, `python/claude-api/files-api.md`

**Anthropic docs (fetched)**
- Pricing: https://platform.claude.com/docs/en/about-claude/pricing.md
- API and data retention / ZDR eligibility: https://platform.claude.com/docs/en/build-with-claude/api-and-data-retention
- Embeddings (Voyage): https://platform.claude.com/docs/en/build-with-claude/embeddings
- Commercial data retention: https://privacy.claude.com/en/articles/7996866-how-long-do-you-store-my-organization-s-data
- Referenced from live-sources: batch-processing, files, mcp-connector, managed-agents/overview, define-outcomes, self-hosted-sandboxes, usage-cost-api, structured-outputs, citations (platform.claude.com/docs/en/…)

**Non-Anthropic**
- Slurm REST: https://slurm.schedmd.com/rest.html, https://slurm.schedmd.com/rest_quickstart.html
- LSF: https://github.com/IBMSpectrumComputing/lsf-python-api, https://www.ibm.com/docs/SSZRJV_10.2.0/api_ref/pac_websvcs_python.html, https://community.ibm.com/community/user/blogs/bill-mcmillan1/2024/04/30/lsf-and-openapi
- AWS Batch pricing: https://aws.amazon.com/batch/pricing · GCP Batch pricing: https://cloud.google.com/batch/pricing
- GitHub Actions pricing: https://github.blog/changelog/2025-12-16-coming-soon-simpler-pricing-and-a-better-experience-for-github-actions/, https://runs-on.com/blog/github-self-hosted-runner-fee-2026/
- GitLab releases: https://docs.gitlab.com/user/project/releases/
- Slack: https://docs.slack.dev/messaging/sending-messages-using-incoming-webhooks/, https://docs.slack.dev/reference/methods/chat.postMessage/
- Teams connectors retirement: https://devblogs.microsoft.com/microsoft365dev/retirement-of-office-365-connectors-within-microsoft-teams/, https://mc.merill.net/message/MC1181996
- Jira REST v3: https://developer.atlassian.com/cloud/jira/platform/rest/v3/intro/, https://www.atlassian.com/blog/developer/creating-a-jira-cloud-issue-in-a-single-rest-call
- Linear: https://developers.linear.app/docs/graphql/working-with-the-graphql-api
- Prometheus Pushgateway: https://prometheus.io/docs/practices/pushing/, https://github.com/prometheus/pushgateway
- OpenTelemetry Python: https://opentelemetry.io/docs/languages/python/, https://opentelemetry.io/docs/languages/python/exporters/
- MinIO licence: https://github.com/minio/minio, https://www.min.io/blog/from-open-source-to-free-and-open-source-minio-is-now-fully-licensed-under-gnu-agplv3
- Grafana licence: https://grafana.com/licensing/ · BI licences: https://www.holistics.io/blog/best-open-source-bi-tools
- flexlm_exporter: https://hub.docker.com/r/mjtrangoni/flexlm_exporter/, https://grafana.com/grafana/dashboards/3854
- Voyage pricing: https://docs.voyageai.com/docs/pricing, https://www.mongodb.com/docs/voyageai/management/billing.md
- Vector DB licences (secondary): https://aquila-network.pages.dev/compare/best-self-hosted-vector-databases
- Docling: https://arxiv.org/abs/2408.09869, https://research.ibm.com/blog/docling-generative-AI
- Efabless / ChipFoundry / LibreLane: https://tinytapeout.com/news/efabless-shutsdown/, https://natlawreview.com/press-releases/chipfoundry-acquires-efabless-assets-propel-custom-silicon-innovation, https://www.eenewseurope.com/en/an-openlane-successor-for-open-source-chip-design/
- ciel / volare: https://pypi.org/project/ciel/, https://openlane2.readthedocs.io/en/dev/usage/about_pdks.html
- PeakRDL licensing: https://peakrdl.readthedocs.io/en/latest/licensing.html · IP-XACT 1685-2022: https://standards.ieee.org/ieee/1685/10583
