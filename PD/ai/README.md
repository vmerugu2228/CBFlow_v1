# CBflow AI Agent

Autonomous Physical Design flow orchestrator powered by Claude.

## Quick Start

### 1. Install dependencies
```bash
pip install anthropic
export ANTHROPIC_API_KEY=sk-ant-...
```

### 2. Run the agent
```bash
# One-shot command
python PD/ai/cbflow_agent.py "Create and run a SYNTH_PNR test"

# Interactive mode
python PD/ai/cbflow_agent.py

# Regression
python PD/ai/cbflow_agent.py "Run all 6 flows and report results"

# Debug
python PD/ai/cbflow_agent.py "Why did place1 fail in the last SYNTH_PNR run?"
```

### 3. MCP Server (for Claude Desktop / Claude Code)
```bash
# Start MCP server
python PD/ai/cbflow_mcp_server.py

# Or configure in Claude Desktop settings:
# ~/.claude/settings.json
{
  "mcpServers": {
    "cbflow": {
      "command": "python",
      "args": ["/path/to/PD/ai/cbflow_mcp_server.py"]
    }
  }
}
```

### 4. Claude Code integration
The project root has a `CLAUDE.md` that gives Claude Code full context about CBflow. Just open Claude Code in the project directory and ask it to run flows.

## Architecture

```
User Prompt → cbflow_agent.py (Anthropic API + tool loop)
                  ↓ tool_use
              bash / read_file / write_file / query_db
                  ↓
              cbflow CLI → RACE engine → EDA tools
```

## Agent Capabilities

| Capability | Example Prompt |
|------------|---------------|
| Create runs | "Create a SYNTH_PNR workspace and run it" |
| Auto-config | "Set up STA to read from the SYNTH_PNR run" |
| Regression | "Run all 6 flows, report pass/fail" |
| Debug | "The PNR run failed at route1, investigate" |
| Branch | "Create a timing fix branch from cts1 and re-run" |
| Release | "Check if we're ready for BTO release" |
| Compare | "Compare QoR between run1 and run2" |

## Safety

- Agent will not delete production data without explicit confirmation
- All destructive operations (clean, delete, retrace) require user approval
- Read-only operations (status, logs, configs) are always safe
- Max 50 turns per session to prevent runaway execution
- 600s timeout per command
