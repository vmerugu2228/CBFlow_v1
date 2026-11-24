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
DEFAULT_WORKSPACE = os.path.join(os.path.dirname(CBFLOW_CORE), 'workarea')

# Claude model (CLAUDE_MODEL overrides); effort SMARTGENIE_EFFORT (own name:
# a generic CLAUDE_EFFORT may be set by other Claude tools). High: multi-step tool use.
MODEL = os.environ.get("CLAUDE_MODEL", "") or "claude-opus-5-5"
EFFORT = os.environ.get("SMARTGENIE_EFFORT", "") or "high"   # low | medium | high | xhigh | max
MAX_TOKENS = 16000
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

## Knowledge Base
You have a knowledge base (ChromaDB) containing CBflow docs, command files, EDA tool guides, and past experience.
- Use search_knowledge FIRST when you're unsure about a command, config, or EDA concept
- After solving a problem, use learn_experience to record the pattern for future reference
- Categories for learning: "fix" (bug fixes), "pattern" (usage patterns), "config" (config tricks), "error" (error meanings)

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
    {
        "name": "search_knowledge",
        "description": "Search the knowledge base (CBflow docs, code, EDA guides, past experience). Use this when unsure about commands, configs, EDA concepts, or error patterns.",
        "input_schema": {
            "type": "object",
            "properties": {
                "query": {"type": "string", "description": "Natural language search query"},
                "n_results": {"type": "integer", "description": "Number of results (default: 5)"},
                "collections": {
                    "type": "array",
                    "description": "Collections to search: cbflow_docs, cbflow_code, eda_guides, web_content, experience",
                    "items": {"type": "string"},
                },
            },
            "required": ["query"],
        },
    },
    {
        "name": "learn_experience",
        "description": "Record a learned pattern, fix, or insight for future reference. Call this after solving a problem or discovering a useful pattern.",
        "input_schema": {
            "type": "object",
            "properties": {
                "content": {"type": "string", "description": "What was learned (be specific and actionable)"},
                "category": {"type": "string", "description": "Category: fix, pattern, config, error, optimization"},
            },
            "required": ["content", "category"],
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
            # .race_db_pointer into the race area (core.db), else legacy .race_*.db
            _gu = os.path.join(os.path.dirname(CBFLOW_CORE), 'global', 'utils')
            if _gu not in sys.path:
                sys.path.insert(0, _gu)
            from core.db import find_race_db_from_run_dir
            db_path = find_race_db_from_run_dir(args["run_dir"])
            if not db_path:
                return "ERROR: No RACE DB found"
            conn = sqlite3.connect(db_path)
            conn.row_factory = sqlite3.Row
            rows = [dict(r) for r in conn.execute(args["sql"]).fetchall()]
            conn.close()
            return json.dumps(rows, indent=2, default=str)
        except Exception as e:
            return f"ERROR: {e}"

    elif name == "search_knowledge":
        try:
            from cbflow_knowledge import KnowledgeEngine
            engine = KnowledgeEngine()
            results = engine.search(
                args["query"],
                n_results=args.get("n_results", 5),
                collections=args.get("collections"),
            )
            output = []
            for i, r in enumerate(results):
                output.append(f"[{i+1}] ({r['collection']}) {r.get('filename', '')}")
                output.append(f"    {r['text'][:500]}")
                output.append("")
            return '\n'.join(output) if output else "No results found."
        except ImportError:
            return "Knowledge base not available. Run: pip install chromadb && python PD/ai/cbflow_knowledge.py ingest"
        except Exception as e:
            return f"Knowledge search error: {e}"

    elif name == "learn_experience":
        try:
            from cbflow_knowledge import KnowledgeEngine
            engine = KnowledgeEngine()
            doc_id = engine.learn(args["content"], args.get("category", "general"))
            return f"Learned and stored (id={doc_id}, category={args.get('category', 'general')})"
        except Exception as e:
            return f"Learn error: {e}"

    return f"ERROR: Unknown tool: {name}"


# ═══════════════════════════════════════════════════════════════════════════════
# AGENT LOOP
# ═══════════════════════════════════════════════════════════════════════════════

def _create(client, messages):
    """One Messages request. Server-side fallback re-runs a refused turn on
    the fallback model in the same call (fallbacks "default")."""
    return client.beta.messages.create(
        model=MODEL,
        max_tokens=MAX_TOKENS,
        system=SYSTEM_PROMPT,
        tools=TOOLS,
        messages=messages,
        output_config={"effort": EFFORT},
        betas=["server-side-fallback-2026-07-01"],
        fallbacks="default",
    )


def _agent_turns(client, messages, verbose=True):
    """Run tool-use turns until Claude ends its turn (or MAX_TURNS). The
    assistant turn is appended exactly as returned (thinking / fallback
    blocks included — they must be passed back unchanged)."""
    for turn in range(MAX_TURNS):
        if verbose:
            print(f"  [Turn {turn + 1}] Working...", end="", flush=True)
        try:
            response = _create(client, messages)
        except anthropic.AuthenticationError:
            print("\n  ERROR: Claude credentials rejected — set ANTHROPIC_API_KEY or run `ant auth login`")
            return False
        except anthropic.RateLimitError:
            print("\n  ERROR: rate limited by the Claude API — retry shortly")
            return False
        except anthropic.APIStatusError as e:
            print(f"\n  ERROR: Claude API {e.status_code}: {e.message}")
            return False
        except anthropic.APIConnectionError:
            print("\n  ERROR: cannot reach the Claude API (network)")
            return False
        if verbose:
            print(f" ({response.stop_reason})")

        messages.append({"role": "assistant", "content": response.content})
        tool_results = []
        for block in response.content:
            if block.type == "text" and block.text.strip():
                print(f"\n  Agent: {block.text}\n")
            elif block.type == "fallback":
                print(f"  (served by {block.to.model} after {block.from_.model} declined)")
            elif block.type == "tool_use" and response.stop_reason == "tool_use":
                print(f"  Tool: {block.name}({json.dumps(block.input)[:100]}...)")
                result = execute_tool(block.name, block.input)
                lines = result.strip().split('\n')
                if len(lines) > 5:
                    print(f"  Result: {lines[0]}... ({len(lines)} lines)")
                else:
                    for line in lines[:5]:
                        print(f"  Result: {line}")
                tool_results.append({
                    "type": "tool_result",
                    "tool_use_id": block.id,
                    "content": result[-8000:],  # Limit context size
                    "is_error": result.startswith("ERROR"),
                })

        if response.stop_reason == "refusal":
            cat = response.stop_details.category if response.stop_details else None
            print(f"  Agent declined this request (category: {cat}).")
            return False
        if tool_results:
            messages.append({"role": "user", "content": tool_results})
            continue
        if response.stop_reason == "max_tokens":
            # a tool call cut off by max_tokens is not run (its input may be truncated)
            print("  (response hit max_tokens — ask it to continue)")
        if response.stop_reason != "pause_turn":
            return True
    print(f"  Stopped after {MAX_TURNS} turns (MAX_TURNS).")
    return True


def run_agent(prompt: str, interactive: bool = False):
    """Run the autonomous agent loop (one-shot, then optionally interactive).
    Credentials: ANTHROPIC_API_KEY, ANTHROPIC_AUTH_TOKEN or an `ant auth login`
    profile — resolved by the SDK."""
    client = anthropic.Anthropic()

    print(f"\n{'=' * 60}")
    print(f"  CBflow AI Agent")
    print(f"  Model: {MODEL} (effort {EFFORT})")
    print(f"  Workspace: {DEFAULT_WORKSPACE}")
    print(f"{'=' * 60}\n")

    messages = [{"role": "user", "content": prompt}]
    _agent_turns(client, messages)

    if interactive:
        while True:
            try:
                user_input = input("\n  You: ").strip()
                if user_input.lower() in ('exit', 'quit', 'q'):
                    break
                if not user_input:
                    continue
                messages.append({"role": "user", "content": user_input})
                _agent_turns(client, messages, verbose=False)
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
