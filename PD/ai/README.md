# CBflow SmartGenie — AI Agent

100% private AI agent for autonomous Physical Design flow orchestration.

## Files

| File | Description |
|------|-------------|
| `cbflow_local_agent.py` | Local agent (Ollama, 100% private) |
| `cbflow_agent.py` | Cloud agent (Anthropic API, optional) |
| `cbflow_server.py` | Central server for multi-user enterprise |
| `cbflow_knowledge.py` | Knowledge engine (ChromaDB vector DB) |
| `cbflow_mcp_server.py` | MCP server (for Claude Desktop/Code integration) |

## Quick Start

```bash
# Setup
brew install ollama && ollama serve && ollama pull qwen2.5:7b
cbflow smartgenie ingest --all
cbflow smartgenie setup

# Use
cbflow smartgenie "create and run SYNTH_PNR"
cbflow smartgenie   # Interactive

# Enterprise
cbflow smartgenie serve                              # Server
export SMARTGENIE_SERVER=http://server:8091           # Clients
cbflow smartgenie "run regression"
```

## Privacy

All inference runs locally. Knowledge stored on-premise. No cloud, no API keys, no data leakage.

See [SmartGenie User Guide](../docs/02-user-guide/smartgenie-user-guide.md) for full documentation.
