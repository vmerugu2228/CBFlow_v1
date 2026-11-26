# CBflow SmartGenie — AI Agent

AI agent for CBflow flow orchestration. The default local mode is fully private (Ollama); hybrid, cloud and Claude Code modes use the Claude API and are opt-in.

## Files

| File | Description |
|------|-------------|
| `cbflow_local_agent.py` | Local agent (Ollama, 100% private) |
| `cbflow_agent.py` | Cloud agent (Anthropic API, optional) |
| `cbflow_server.py` | Central server for multi-user enterprise |
| `cbflow_knowledge.py` | Knowledge engine (ChromaDB vector DB) |
| `cbflow_mcp_server.py` | MCP server (SmartGenie tools for Claude Desktop / Claude Code; sandbox root = the whole install) |
| `cli_ui.py` | Terminal UI shared by the agents |
| `usage_tracker.py` | Per-user usage stats (`cbflow smartgenie usage`) |
| `eda_guides/` | EDA guide text ingested into the knowledge base |
| `fine_tune/` | Training-data generator for a fine-tuned local model ([README](fine_tune/README.md)) |

## Quick Start

```bash
# Setup (local model: CBFLOW_MODEL, default qwen2.5:14b; qwen2.5:7b for 16 GB machines)
brew install ollama && ollama serve && ollama pull qwen2.5:14b
cbflow smartgenie ingest --all
cbflow smartgenie setup

# Use
cbflow smartgenie "create and run SYNTH_PNR"
cbflow smartgenie   # Interactive
cbflow smartgenie --hybrid "prompt"                   # Claude API + local learning
cbflow smartgenie cloud "prompt"                      # Claude agent with CBflow tools
cbflow smartgenie code ["question"]                   # Claude Code at $CBFLOW_ROOT with the SmartGenie MCP tools

# Enterprise
cbflow smartgenie serve                              # Server
export SMARTGENIE_SERVER=http://server:8091           # Clients
cbflow smartgenie "run regression"
```

## Privacy

Local mode: inference runs on Ollama and the knowledge base (ChromaDB) stays
on-premise — no API keys. Hybrid / cloud / code modes send prompts and tool
results to the Claude API (credentials: `ANTHROPIC_API_KEY` or `ant auth login`;
model `CLAUDE_MODEL`, default claude-opus-5-5; cloud effort `SMARTGENIE_EFFORT`).
`cbflow smartgenie --help` lists every mode and variable.

See [SmartGenie User Guide](../docs/02-user-guide/smartgenie-user-guide.md) for full documentation.
