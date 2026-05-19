#!/usr/bin/env python3
"""
CBflow AI Agent — Autonomous PD flow orchestrator powered by Claude.

Takes natural language prompts, drives CBflow CLI, analyzes results,
modifies configs, runs regressions, and makes intelligent decisions.

Usage:
    python cbflow_agent.py "Create and run a SYNTH_PNR test"
    python cbflow_agent.py "Run all 6 flows and report results"
    python cbflow_agent.py "Why did place1 fail in the last run?"
    python cbflow_agent.py   # Interactive mode

Requirements:
    pip install anthropic
    export ANTHROPIC_API_KEY=your-key
"""

import anthropic
import json
import os
import re
import sqlite3
import subprocess
import sys
from datetime import datetime
from pathlib import Path

# ═══════════════════════════════════════════════════════════════════════════════
# CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════════

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
CBFLOW_CORE = os.path.dirname(SCRIPT_DIR)
CBFLOW_BIN = os.path.join(CBFLOW_CORE, 'bin', 'cbflow')
DEFAULT_WORKSPACE = os.path.join(os.path.dirname(CBFLOW_CORE), 'workarea_test')

MODEL = "claude-sonnet-4-6"  # Fast + capable. Use claude-opus-4-6 for complex reasoning.
MAX_TOKENS = 8192
MAX_TURNS = 50  # Safety limit on agent loop iterations

SYSTEM_PROMPT = f"""You are the CBflow AI Agent — an autonomous Physical Design flow orchestrator.

## Your Environment
- CBflow binary: {CBFLOW_BIN}
- Workspace: {DEFAULT_WORKSPACE}
- CBflow core: {CBFLOW_CORE}
- Config dir: {CBFLOW_CORE}/config/flow/v1.0.0/

## Available Flows
SYNTH, PNR, SYNTH_PNR, FP, FCFP, STA, LEC, CLP, PV, EMIR, POPT, ECO

## User Configs (in workspace)
uc_SYNTH.tcl, uc_PNR.tcl, uc_SYNTH_PNR.tcl, uc_STA.tcl, uc_LEC.tcl, uc_CLP.tcl

## Key Commands
- cbflow workspace create --config <file>    Create a run
- cbflow run all                              Execute complete flow
- cbflow run status                           Check progress
- cbflow run retrace --from <stage>           Re-run from stage
- cbflow run add-node --node <n> --type <t> --dep <d>
- cbflow run create-branch --branch <name> --from <stage>
- cbflow run release --tag <TAG>              Milestone release
- cbflow run release-check --tag <TAG> --project <p>

## Decision Framework
1. SAFE (do automatically): read status, list runs, read configs, analyze logs
2. CONFIRM (describe then do): create workspaces, run flows, modify configs
3. DANGEROUS (warn first): delete runs, retrace, clean, release

## Rules
- Always cd to the correct directory before running cbflow commands
- For run commands: cd into the P0_run_<FLOW>_test1 directory first
- For workspace commands: cd to the workspace directory
- Check status after running a flow to confirm it passed
- When creating configs, use the existing uc_*.tcl files as templates
- Report results clearly with stage counts and pass/fail status
- If a flow fails, read the log and diagnose before retrying

## Output Format
Be concise. Report actions taken and results. Use tables for multi-flow status.
"""

# ═══════════════════════════════════════════════════════════════════════════════
# TOOL DEFINITIONS (for Anthropic API)
# ═══════════════════════════════════════════════════════════════════════════════

TOOLS = [
    {
        "name": "bash",
        "description": "Execute a shell command. Use for cbflow CLI, file operations, directory navigation. Always use full paths or cd first.",
        "input_schema": {
            "type": "object",
            "properties": {
                "command": {"type": "string", "description": "Shell command to execute"},
                "cwd": {"type": "string", "description": f"Working directory (default: {DEFAULT_WORKSPACE})"},
            },
            "required": ["command"],
        },
    },
    {
        "name": "read_file",
        "description": "Read a file. Use for configs, logs, reports, manifests.",
        "input_schema": {
            "type": "object",
            "properties": {
                "path": {"type": "string", "description": "Absolute file path"},
                "offset": {"type": "integer", "description": "Start line (0-indexed)"},
                "limit": {"type": "integer", "description": "Max lines (default: 200)"},
            },
            "required": ["path"],
        },
    },
    {
        "name": "write_file",
        "description": "Write content to a file. Use for creating/modifying user configs.",
        "input_schema": {
            "type": "object",
            "properties": {
                "path": {"type": "string", "description": "Absolute file path"},
                "content": {"type": "string", "description": "File content to write"},
            },
            "required": ["path", "content"],
        },
    },
    {
        "name": "query_db",
        "description": "SQL query against a run's RACE SQLite DB (.race_*.db). Tables: jobs (job_name, stage, status, runtime_sec, exit_code), run_info (key, value), job_order (job_name, seq, stage, job_type).",
        "input_schema": {
            "type": "object",
            "properties": {
                "run_dir": {"type": "string", "description": "Run directory path"},
                "sql": {"type": "string", "description": "SQL SELECT query"},
            },
            "required": ["run_dir", "sql"],
        },
    },
]

# ═══════════════════════════════════════════════════════════════════════════════
# TOOL EXECUTION
# ═══════════════════════════════════════════════════════════════════════════════

def execute_tool(name: str, args: dict) -> str:
    """Execute a tool call and return the result as string."""

    if name == "bash":
        cmd = args["command"]
        cwd = args.get("cwd", DEFAULT_WORKSPACE)
        try:
            result = subprocess.run(
                cmd, shell=True, cwd=cwd,
                capture_output=True, text=True, timeout=600
            )
            output = ""
            if result.stdout:
                output += result.stdout[-4000:]
            if result.stderr:
                output += "\n[STDERR]\n" + result.stderr[-2000:]
            if not output.strip():
                output = f"(exit code: {result.returncode})"
            return output
        except subprocess.TimeoutExpired:
            return "ERROR: Command timed out after 600s"
        except Exception as e:
            return f"ERROR: {e}"

    elif name == "read_file":
        try:
            with open(args["path"]) as f:
                lines = f.readlines()
            offset = args.get("offset", 0)
            limit = args.get("limit", 200)
            selected = lines[offset:offset + limit]
            return ''.join(selected)
        except Exception as e:
            return f"ERROR: {e}"

    elif name == "write_file":
        try:
            os.makedirs(os.path.dirname(args["path"]), exist_ok=True)
            with open(args["path"], 'w') as f:
                f.write(args["content"])
            return f"Written {len(args['content'])} bytes to {args['path']}"
        except Exception as e:
            return f"ERROR: {e}"

    elif name == "query_db":
        try:
            db_files = list(Path(args["run_dir"]).glob('.race_*.db'))
            if not db_files:
                return "ERROR: No RACE DB found"
            conn = sqlite3.connect(str(db_files[0]))
            conn.row_factory = sqlite3.Row
            rows = [dict(r) for r in conn.execute(args["sql"]).fetchall()]
            conn.close()
            return json.dumps(rows, indent=2, default=str)
        except Exception as e:
            return f"ERROR: {e}"

    return f"ERROR: Unknown tool: {name}"


# ═══════════════════════════════════════════════════════════════════════════════
# AGENT LOOP
# ═══════════════════════════════════════════════════════════════════════════════

def run_agent(prompt: str, interactive: bool = False):
    """Run the autonomous agent loop."""

    api_key = os.environ.get("ANTHROPIC_API_KEY", "")
    if not api_key:
        print("ERROR: Set ANTHROPIC_API_KEY environment variable")
        print("  export ANTHROPIC_API_KEY=sk-ant-...")
        sys.exit(1)

    client = anthropic.Anthropic(api_key=api_key)

    print(f"\n{'=' * 60}")
    print(f"  CBflow AI Agent")
    print(f"  Model: {MODEL}")
    print(f"  Workspace: {DEFAULT_WORKSPACE}")
    print(f"{'=' * 60}\n")

    messages = [{"role": "user", "content": prompt}]

    for turn in range(MAX_TURNS):
        print(f"  [Turn {turn + 1}] Thinking...", end="", flush=True)

        response = client.messages.create(
            model=MODEL,
            max_tokens=MAX_TOKENS,
            system=SYSTEM_PROMPT,
            tools=TOOLS,
            messages=messages,
        )

        print(f" ({response.stop_reason})")

        # Process response content
        assistant_content = []
        tool_results = []

        for block in response.content:
            if block.type == "text":
                print(f"\n  Agent: {block.text}\n")
                assistant_content.append(block)

            elif block.type == "tool_use":
                tool_name = block.name
                tool_input = block.input
                print(f"  Tool: {tool_name}({json.dumps(tool_input)[:100]}...)")

                result = execute_tool(tool_name, tool_input)
                # Print abbreviated result
                lines = result.strip().split('\n')
                if len(lines) > 5:
                    print(f"  Result: {lines[0]}... ({len(lines)} lines)")
                else:
                    for line in lines[:5]:
                        print(f"  Result: {line}")

                assistant_content.append(block)
                tool_results.append({
                    "type": "tool_result",
                    "tool_use_id": block.id,
                    "content": result[-8000:],  # Limit context size
                })

        # Add assistant message
        messages.append({"role": "assistant", "content": assistant_content})

        # If there were tool calls, send results back
        if tool_results:
            messages.append({"role": "user", "content": tool_results})
        elif response.stop_reason == "end_turn":
            break

    if interactive:
        while True:
            try:
                user_input = input("\n  You: ").strip()
                if user_input.lower() in ('exit', 'quit', 'q'):
                    break
                if not user_input:
                    continue
                messages.append({"role": "user", "content": user_input})
                # Continue the loop
                for turn in range(MAX_TURNS):
                    response = client.messages.create(
                        model=MODEL, max_tokens=MAX_TOKENS,
                        system=SYSTEM_PROMPT, tools=TOOLS, messages=messages,
                    )
                    assistant_content = []
                    tool_results = []
                    for block in response.content:
                        if block.type == "text":
                            print(f"\n  Agent: {block.text}\n")
                            assistant_content.append(block)
                        elif block.type == "tool_use":
                            print(f"  Tool: {block.name}")
                            result = execute_tool(block.name, block.input)
                            lines = result.strip().split('\n')
                            print(f"  Result: {lines[0]}{'...' if len(lines) > 1 else ''}")
                            assistant_content.append(block)
                            tool_results.append({
                                "type": "tool_result",
                                "tool_use_id": block.id,
                                "content": result[-8000:],
                            })
                    messages.append({"role": "assistant", "content": assistant_content})
                    if tool_results:
                        messages.append({"role": "user", "content": tool_results})
                    elif response.stop_reason == "end_turn":
                        break
            except (KeyboardInterrupt, EOFError):
                break

    print("\n  Agent session ended.\n")


# ═══════════════════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════════════════

if __name__ == "__main__":
    if len(sys.argv) > 1:
        prompt = " ".join(sys.argv[1:])
        run_agent(prompt)
    else:
        # Interactive mode
        print("\n  CBflow AI Agent — Interactive Mode")
        print("  Type your prompt, or 'exit' to quit.\n")
        try:
            initial = input("  You: ").strip()
            if initial and initial.lower() not in ('exit', 'quit'):
                run_agent(initial, interactive=True)
        except (KeyboardInterrupt, EOFError):
            pass
