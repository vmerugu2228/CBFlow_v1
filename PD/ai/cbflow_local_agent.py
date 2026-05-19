#!/usr/bin/env python3
"""
CBflow LOCAL AI Agent — 100% Private, Zero Data Leakage.

Runs entirely on your machine using Ollama (local LLM).
No API keys. No cloud. No data leaves your network.

Architecture:
    User Prompt → Local LLM (Ollama) → Tool calls → cbflow CLI
                                     ↕
                              ChromaDB Knowledge Base (local)

Supported models (via Ollama):
    qwen2.5:7b        — Best for code/tool use on 16GB (recommended)
    llama3.1:8b       — Strong general reasoning
    deepseek-coder:6.7b — Code-specialized
    mistral:7b        — Fast, good for simple tasks
    codellama:7b      — Code-focused

Usage:
    # Install Ollama first: https://ollama.com/download
    ollama pull qwen2.5:7b

    # Run agent
    python cbflow_local_agent.py "Create and run SYNTH_PNR"
    python cbflow_local_agent.py   # Interactive mode

Requirements:
    pip install requests chromadb
    Ollama running locally (ollama serve)
"""

import json
import os
import re
import sqlite3
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

# ═══════════════════════════════════════════════════════════════════════════════
# CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════════

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
CBFLOW_CORE = os.path.dirname(SCRIPT_DIR)
CBFLOW_BIN = os.path.join(CBFLOW_CORE, 'bin', 'cbflow')
DEFAULT_WORKSPACE = os.path.join(os.path.dirname(CBFLOW_CORE), 'workarea_test')

OLLAMA_URL = os.environ.get('OLLAMA_URL', 'http://localhost:11434')
SMARTGENIE_SERVER = os.environ.get('SMARTGENIE_SERVER', '')
MODEL = os.environ.get('CBFLOW_MODEL', 'qwen2.5:7b')
USERNAME = os.environ.get('USER', 'anonymous')
MAX_TURNS = 30
TIMEOUT_PER_COMMAND = 600

SYSTEM_PROMPT = f"""You are the CBflow AI Agent — an autonomous Physical Design flow orchestrator running LOCALLY on the user's machine. All data stays private.

## Environment
- CBflow binary: {CBFLOW_BIN}
- Workspace: {DEFAULT_WORKSPACE}
- Core: {CBFLOW_CORE}

## Available Tools
You MUST respond with tool calls in this JSON format when you need to take action:
```json
{{"tool": "tool_name", "args": {{"key": "value"}}}}
```

Available tools:
1. bash - Execute shell command: {{"tool": "bash", "args": {{"command": "cbflow run status", "cwd": "/path"}}}}
2. read_file - Read a file: {{"tool": "read_file", "args": {{"path": "/path/to/file"}}}}
3. write_file - Write a file: {{"tool": "write_file", "args": {{"path": "/path", "content": "..."}}}}
4. search_kb - Search knowledge base: {{"tool": "search_kb", "args": {{"query": "how to fix hold violations"}}}}
5. learn - Record experience: {{"tool": "learn", "args": {{"content": "...", "category": "fix"}}}}

## CBflow Commands
- cbflow workspace create --config <file>
- cbflow run all / status / retrace --from <stage>
- cbflow run add-node --node <n> --type <t> --dep <d>
- cbflow run create-branch --branch <name> --from <stage>
- cbflow run release --tag <TAG>
- cbflow flow types / stages --flow <FLOW>

## User configs: uc_SYNTH.tcl, uc_PNR.tcl, uc_SYNTH_PNR.tcl, uc_STA.tcl, uc_LEC.tcl, uc_CLP.tcl

## Rules
- Always cd to correct directory first
- For run commands: cd into P0_run_<FLOW>_test1/
- Check status after running flows
- When unsure, search_kb first
- After solving problems, use learn to record the fix

Respond with tool calls OR text. Be concise."""

# ═══════════════════════════════════════════════════════════════════════════════
# TOOL EXECUTION (same as cloud agent — reused)
# ═══════════════════════════════════════════════════════════════════════════════

def execute_tool(name: str, args: dict) -> str:
    """Execute a tool and return result."""
    if name == "bash":
        cmd = args.get("command", "")
        cwd = args.get("cwd", DEFAULT_WORKSPACE)
        try:
            result = subprocess.run(
                cmd, shell=True, cwd=cwd,
                capture_output=True, text=True, timeout=TIMEOUT_PER_COMMAND
            )
            output = ""
            if result.stdout: output += result.stdout[-3000:]
            if result.stderr: output += "\n[STDERR]\n" + result.stderr[-1000:]
            return output or f"(exit code: {result.returncode})"
        except subprocess.TimeoutExpired:
            return "ERROR: Command timed out"
        except Exception as e:
            return f"ERROR: {e}"

    elif name == "read_file":
        try:
            path = args["path"]
            limit = args.get("limit", 200)
            with open(path) as f:
                lines = f.readlines()[:limit]
            return ''.join(lines)
        except Exception as e:
            return f"ERROR: {e}"

    elif name == "write_file":
        try:
            os.makedirs(os.path.dirname(args["path"]), exist_ok=True)
            with open(args["path"], 'w') as f:
                f.write(args["content"])
            return f"Written to {args['path']}"
        except Exception as e:
            return f"ERROR: {e}"

    elif name == "search_kb":
        try:
            if SMARTGENIE_SERVER:
                import requests
                resp = requests.post(f"{SMARTGENIE_SERVER}/api/knowledge/search",
                    json={"query": args["query"], "user": USERNAME, "n_results": args.get("n", 5)}, timeout=30)
                results = resp.json().get("results", [])
            else:
                from cbflow_knowledge import KnowledgeEngine
                engine = KnowledgeEngine()
                results = engine.search(args["query"], n_results=args.get("n", 5))
            output = []
            for r in results:
                output.append(f"[{r.get('collection', '')}] {r.get('user', '')} {r.get('source', '')[:50]}")
                output.append(f"  {r['text'][:300]}")
            return '\n'.join(output) or "No results."
        except Exception as e:
            return f"Knowledge search error: {e}"

    elif name == "learn":
        try:
            if SMARTGENIE_SERVER:
                import requests
                resp = requests.post(f"{SMARTGENIE_SERVER}/api/knowledge/learn",
                    json={"content": args["content"], "category": args.get("category", "general"),
                          "user": USERNAME}, timeout=30)
                return json.dumps(resp.json())
            else:
                from cbflow_knowledge import KnowledgeEngine
                engine = KnowledgeEngine()
                engine.learn(args["content"], args.get("category", "general"))
            return "Learned and stored (shared with all users)."
        except Exception as e:
            return f"Learn error: {e}"

    return f"Unknown tool: {name}"


# ═══════════════════════════════════════════════════════════════════════════════
# OLLAMA CLIENT
# ═══════════════════════════════════════════════════════════════════════════════

def ollama_chat(messages: list, model: str = MODEL) -> str:
    """Send chat to local Ollama or central SmartGenie server."""
    import requests

    if SMARTGENIE_SERVER:
        # Route through central server (shared knowledge auto-injected)
        try:
            resp = requests.post(
                f"{SMARTGENIE_SERVER}/api/chat",
                json={"messages": messages, "model": model, "user": USERNAME},
                timeout=120,
            )
            data = resp.json()
            return data.get("response", data.get("error", "No response"))
        except requests.ConnectionError:
            return f"ERROR: Cannot connect to SmartGenie server at {SMARTGENIE_SERVER}"
        except Exception as e:
            return f"ERROR: Server error: {e}"

    # Local Ollama
    try:
        resp = requests.post(
            f"{OLLAMA_URL}/api/chat",
            json={
                "model": model,
                "messages": messages,
                "stream": False,
                "options": {"temperature": 0.1, "num_predict": 4096},
            },
            timeout=120,
        )
        resp.raise_for_status()
        return resp.json().get("message", {}).get("content", "")
    except requests.ConnectionError:
        return "ERROR: Cannot connect to Ollama. Run: ollama serve"
    except Exception as e:
        return f"ERROR: Ollama error: {e}"


def parse_tool_call(text: str) -> tuple:
    """Extract tool call JSON from LLM response. Returns (tool_name, args) or (None, None)."""
    # Look for JSON tool call pattern
    patterns = [
        r'\{"tool":\s*"(\w+)",\s*"args":\s*(\{[^}]+\})\}',
        r'```json\s*\n?\{"tool":\s*"(\w+)",\s*"args":\s*(\{.*?\})\}\s*\n?```',
    ]
    for pat in patterns:
        m = re.search(pat, text, re.DOTALL)
        if m:
            try:
                args = json.loads(m.group(2))
                return m.group(1), args
            except json.JSONDecodeError:
                continue

    # Try parsing entire response as JSON
    try:
        data = json.loads(text.strip())
        if "tool" in data:
            return data["tool"], data.get("args", {})
    except (json.JSONDecodeError, KeyError):
        pass

    return None, None


# ═══════════════════════════════════════════════════════════════════════════════
# AGENT LOOP
# ═══════════════════════════════════════════════════════════════════════════════

def run_agent(prompt: str, interactive: bool = False):
    """Run the local agent loop."""

    import requests

    # Check connectivity — server OR local Ollama
    if SMARTGENIE_SERVER:
        try:
            requests.get(f"{SMARTGENIE_SERVER}/api/status", timeout=5)
        except requests.ConnectionError:
            print(f"\n  ERROR: Cannot connect to SmartGenie server at {SMARTGENIE_SERVER}")
            print(f"  Check the server is running: cbflow smartgenie serve")
            sys.exit(1)
    else:
        try:
            requests.get(f"{OLLAMA_URL}/api/tags", timeout=5)
        except requests.ConnectionError:
            print("\n  ERROR: Ollama is not running.")
            print("  Install: https://ollama.com/download")
            print("  Start:   ollama serve")
            print(f"  Pull:    ollama pull {MODEL}")
            print(f"\n  Or connect to a server: export SMARTGENIE_SERVER=http://server:8091")
            sys.exit(1)

    print(f"\n{'=' * 60}")
    print(f"  CBflow SmartGenie (100% Private)")
    if SMARTGENIE_SERVER:
        print(f"  Server: {SMARTGENIE_SERVER}")
        print(f"  User: {USERNAME}")
        print(f"  Mode: Enterprise (shared knowledge)")
    else:
        print(f"  Model: {MODEL} (via Ollama)")
        print(f"  Mode: Local (standalone)")
    print(f"  Data: NEVER leaves your network")
    print(f"  Workspace: {DEFAULT_WORKSPACE}")
    print(f"{'=' * 60}\n")

    messages = [
        {"role": "system", "content": SYSTEM_PROMPT},
        {"role": "user", "content": prompt},
    ]

    for turn in range(MAX_TURNS):
        print(f"  [Turn {turn + 1}] Thinking...", end="", flush=True)
        t0 = time.time()

        response = ollama_chat(messages)
        elapsed = time.time() - t0
        print(f" ({elapsed:.1f}s)")

        if response.startswith("ERROR:"):
            print(f"  {response}")
            break

        # Check for tool call
        tool_name, tool_args = parse_tool_call(response)

        if tool_name:
            print(f"  Tool: {tool_name}({json.dumps(tool_args)[:80]}...)")
            result = execute_tool(tool_name, tool_args)

            # Print abbreviated result
            lines = result.strip().split('\n')
            if len(lines) > 3:
                print(f"  Result: {lines[0]}... ({len(lines)} lines)")
            else:
                for l in lines[:3]:
                    print(f"  Result: {l[:100]}")

            # Feed result back to LLM
            messages.append({"role": "assistant", "content": response})
            messages.append({"role": "user", "content": f"Tool result:\n{result[-3000:]}\n\nContinue with the task. Use another tool call or provide your final answer."})

        else:
            # Text response — print and check if done
            # Strip any partial JSON that wasn't a valid tool call
            clean = re.sub(r'```json.*?```', '', response, flags=re.DOTALL).strip()
            if clean:
                print(f"\n  Agent: {clean}\n")
            messages.append({"role": "assistant", "content": response})

            # If no tool call and reasonable length, probably done
            if len(response) > 50 and not any(kw in response.lower() for kw in ['let me', 'i will', 'next step']):
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

                for turn in range(MAX_TURNS):
                    response = ollama_chat(messages)
                    tool_name, tool_args = parse_tool_call(response)
                    if tool_name:
                        print(f"  Tool: {tool_name}")
                        result = execute_tool(tool_name, tool_args)
                        print(f"  Result: {result[:100]}{'...' if len(result) > 100 else ''}")
                        messages.append({"role": "assistant", "content": response})
                        messages.append({"role": "user", "content": f"Tool result:\n{result[-3000:]}\n\nContinue."})
                    else:
                        clean = re.sub(r'```json.*?```', '', response, flags=re.DOTALL).strip()
                        if clean:
                            print(f"\n  Agent: {clean}\n")
                        messages.append({"role": "assistant", "content": response})
                        break
            except (KeyboardInterrupt, EOFError):
                break

    print("\n  Session ended. All data stayed local.\n")


# ═══════════════════════════════════════════════════════════════════════════════
# SETUP HELPER
# ═══════════════════════════════════════════════════════════════════════════════

def setup():
    """Interactive setup for the local agent."""
    print("\n  CBflow Local AI Agent — Setup")
    print("  ═════════════════════════════\n")

    # Check Ollama
    import shutil
    if shutil.which("ollama"):
        print("  [OK] Ollama installed")
    else:
        print("  [!!] Ollama not found")
        print("       Install from: https://ollama.com/download")
        print("       macOS: brew install ollama")
        return

    # Check Ollama running
    import requests
    try:
        resp = requests.get(f"{OLLAMA_URL}/api/tags", timeout=5)
        models = [m["name"] for m in resp.json().get("models", [])]
        print(f"  [OK] Ollama running ({len(models)} models)")
        if models:
            print(f"       Models: {', '.join(models[:5])}")
    except:
        print("  [!!] Ollama not running. Start: ollama serve")
        return

    # Check recommended model
    if any(MODEL.split(':')[0] in m for m in models):
        print(f"  [OK] Model {MODEL} available")
    else:
        print(f"  [!!] Model {MODEL} not found")
        print(f"       Pull: ollama pull {MODEL}")

    # Check ChromaDB
    try:
        import chromadb
        print("  [OK] ChromaDB installed")
    except ImportError:
        print("  [!!] ChromaDB not installed: pip3 install chromadb")

    # Check knowledge base
    if os.path.isdir(os.path.join(SCRIPT_DIR, '.knowledge_db')):
        try:
            from cbflow_knowledge import KnowledgeEngine
            engine = KnowledgeEngine()
            stats = engine.stats()
            total = sum(stats.values())
            print(f"  [OK] Knowledge base: {total} chunks")
        except:
            print("  [!!] Knowledge base error")
    else:
        print("  [!!] Knowledge base empty")
        print("       Run: python3 PD/ai/cbflow_knowledge.py ingest --all")

    print("\n  Ready! Run: python3 PD/ai/cbflow_local_agent.py \"your prompt\"")
    print("  Or interactive: python3 PD/ai/cbflow_local_agent.py\n")


# ═══════════════════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════════════════

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "setup":
        setup()
    elif len(sys.argv) > 1:
        prompt = " ".join(sys.argv[1:])
        run_agent(prompt)
    else:
        print("\n  CBflow LOCAL AI Agent — Interactive (100% Private)")
        print("  Type prompt, or 'exit' to quit.\n")
        try:
            initial = input("  You: ").strip()
            if initial and initial.lower() not in ('exit', 'quit'):
                run_agent(initial, interactive=True)
        except (KeyboardInterrupt, EOFError):
            pass
