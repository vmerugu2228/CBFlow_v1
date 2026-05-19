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
MODEL = os.environ.get('CBFLOW_MODEL', 'qwen2.5:14b')
USERNAME = os.environ.get('USER', 'anonymous')
MAX_TURNS = 5  # Strict limit — prevents runaway loops
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

## CRITICAL RULES
1. ANSWER FROM KNOWLEDGE FIRST. The "Relevant Knowledge" section below contains CBflow docs, code, and past experience. If it has the answer, respond directly in plain text WITHOUT using any tools.
2. Only use bash/tools when the user explicitly asks to RUN, CREATE, EXECUTE, DELETE, or MODIFY something.
3. For questions like "list flows", "what stages does PNR have", "how to configure CTS" — answer from knowledge, do NOT run commands.
4. Never show raw JSON tool calls or bash commands to the user. Just give clean answers.
5. When you must run commands: cd to correct directory first, run commands in P0_run_<FLOW>_test1/.
6. After solving a problem, use learn tool to record the fix for future reference.

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
            _srv = os.environ.get('SMARTGENIE_SERVER', '') or SMARTGENIE_SERVER
            if _srv:
                import requests
                resp = requests.post(f"{_srv}/api/knowledge/search",
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
            _srv = os.environ.get('SMARTGENIE_SERVER', '') or SMARTGENIE_SERVER
            if _srv:
                import requests
                resp = requests.post(f"{_srv}/api/knowledge/learn",
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

    # Re-read env in case it was set after import
    server = os.environ.get('SMARTGENIE_SERVER', '') or SMARTGENIE_SERVER

    if server:
        # Route through central server (shared knowledge auto-injected)
        try:
            resp = requests.post(
                f"{server}/api/chat",
                json={"messages": messages, "model": model, "user": USERNAME},
                timeout=120,
            )
            data = resp.json()
            return data.get("response", data.get("error", "No response"))
        except requests.ConnectionError:
            return f"ERROR: Cannot connect to SmartGenie server at {server}"
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
    from cli_ui import (banner, prompt_input, agent_text, tool_start, tool_result,
                        Spinner, turn_indicator, goodbye, error, success, info,
                        separator, help_text, dim, cyan, green, yellow)

    # Check connectivity
    if SMARTGENIE_SERVER:
        try:
            requests.get(f"{SMARTGENIE_SERVER}/api/status", timeout=5)
        except requests.ConnectionError:
            error(f"Cannot connect to SmartGenie server at {SMARTGENIE_SERVER}")
            info("Check the server is running: cbflow smartgenie serve")
            sys.exit(1)
    else:
        try:
            requests.get(f"{OLLAMA_URL}/api/tags", timeout=5)
        except requests.ConnectionError:
            error("Ollama is not running.")
            info("Install: https://ollama.com/download")
            info("Start:   ollama serve")
            info(f"Pull:    ollama pull {MODEL}")
            info(f"Or connect to a server: export SMARTGENIE_SERVER=http://server:8091")
            sys.exit(1)

    banner(MODEL, SMARTGENIE_SERVER, USERNAME, DEFAULT_WORKSPACE)

    messages = [{"role": "system", "content": SYSTEM_PROMPT}]

    def _inject_knowledge(msgs, query):
        """Search KB and add relevant context to the system message."""
        if not query:
            return msgs
        try:
            kb_result = execute_tool("search_kb", {"query": query, "n": 3})
            if kb_result and "No results" not in kb_result and "error" not in kb_result.lower():
                # Update system message with relevant knowledge
                kb_snippet = kb_result[:2000]
                for m in msgs:
                    if m["role"] == "system":
                        # Remove old knowledge injection, add fresh one
                        base = m["content"].split("\n\n## Relevant Knowledge")[0]
                        m["content"] = base + f"\n\n## Relevant Knowledge (from docs/code/experience):\n{kb_snippet}"
                        break
        except Exception:
            pass
        return msgs

    # Action keywords — if user prompt contains these, allow tool use
    ACTION_WORDS = {'create', 'run', 'execute', 'delete', 'remove', 'retrace',
                    'add', 'branch', 'release', 'clean', 'modify', 'change',
                    'set', 'configure', 'update', 'build', 'make', 'start'}

    def _is_action_request(text):
        """Detect if user wants to DO something (vs just asking a question)."""
        words = set(text.lower().split())
        return bool(words & ACTION_WORDS)

    def _answer_from_knowledge(messages, query):
        """Answer directly from KB without LLM tool calling."""
        kb_result = execute_tool("search_kb", {"query": query, "n": 5})
        if not kb_result or "No results" in kb_result or "error" in kb_result.lower():
            return None  # No knowledge found, fall back to LLM

        # Ask LLM to synthesize the knowledge into an answer (NO tools)
        synth_messages = [
            {"role": "system", "content": "You are a helpful VLSI/EDA expert. Answer the user's question using ONLY the provided knowledge. Do NOT use any tools. Give a clean, formatted answer."},
            {"role": "user", "content": f"Knowledge:\n{kb_result[:3000]}\n\nQuestion: {query}\n\nAnswer clearly and concisely:"}
        ]
        spinner = Spinner("Searching knowledge")
        spinner.start()
        t0 = time.time()
        response = ollama_chat(synth_messages)
        elapsed = time.time() - t0
        spinner.stop()

        # Strip any tool call attempts from the response
        clean = re.sub(r'\{["\']tool["\'].*?\}', '', response, flags=re.DOTALL).strip()
        clean = re.sub(r'```json.*?```', '', clean, flags=re.DOTALL).strip()
        return clean if clean and len(clean) > 20 else None

    def _agent_turn(messages, turn_num):
        """Single agent turn — think, tool call or respond."""
        spinner = Spinner("Thinking")
        spinner.start()
        t0 = time.time()

        # Inject knowledge
        last_user = ""
        for m in reversed(messages):
            if m["role"] == "user" and not m["content"].startswith("Tool result:"):
                last_user = m["content"]
                break
        if last_user:
            messages = _inject_knowledge(messages, last_user)

        response = ollama_chat(messages)
        elapsed = time.time() - t0
        spinner.stop()
        turn_indicator(turn_num, elapsed)

        if response.startswith("ERROR:"):
            error(response)
            return messages, True

        tool_name, tool_args = parse_tool_call(response)

        if tool_name:
            info(f"Running {tool_name}...")
            result = execute_tool(tool_name, tool_args)
            messages.append({"role": "assistant", "content": response})
            messages.append({"role": "user", "content": f"Tool result:\n{result[-3000:]}\n\nGive a clean answer. Do NOT call any more tools. Just summarize the result."})
            return messages, False
        else:
            clean = re.sub(r'\{["\']tool["\'].*?\}', '', response, flags=re.DOTALL).strip()
            clean = re.sub(r'```json.*?```', '', clean, flags=re.DOTALL).strip()
            if clean:
                separator()
                agent_text(clean)
                print()
            messages.append({"role": "assistant", "content": response})
            return messages, True  # Always done after a text response

    def _handle_prompt(messages, user_input):
        """Handle a user prompt — question answered from KB, action uses tools."""
        if _is_action_request(user_input):
            # Action: use full agent with tools
            messages.append({"role": "user", "content": user_input})
            for turn in range(MAX_TURNS):
                messages, done = _agent_turn(messages, turn + 1)
                if done:
                    break
        else:
            # Question: try KB first, fall back to LLM
            answer = _answer_from_knowledge(messages, user_input)
            if answer:
                separator()
                agent_text(answer)
                print()
                messages.append({"role": "user", "content": user_input})
                messages.append({"role": "assistant", "content": answer})
            else:
                # No KB match — use LLM (single turn, no tools)
                messages.append({"role": "user", "content": user_input})
                messages, _ = _agent_turn(messages, 1)
        return messages

    # Run initial prompt (skip if None — interactive mode waits for user)
    if prompt is not None:
        messages = _handle_prompt(messages, prompt)
    else:
        info("Type your question or command. Type /help for options.")
        print()

    if interactive:
        while True:
            try:
                user_input = prompt_input()
                if not user_input:
                    continue
                if user_input.lower() in ('exit', 'quit', 'q'):
                    break
                if user_input == '/help':
                    help_text(); continue
                if user_input == '/clear':
                    messages = [{"role": "system", "content": SYSTEM_PROMPT}]
                    success("Conversation cleared."); continue
                if user_input.startswith('/status'):
                    result = execute_tool("bash", {"command": f"{CBFLOW_BIN} run status"})
                    tool_result(result); continue
                if user_input.startswith('/flows'):
                    result = execute_tool("bash", {"command": f"{CBFLOW_BIN} flow types"})
                    tool_result(result); continue
                if user_input.startswith('/search '):
                    result = execute_tool("search_kb", {"query": user_input[8:]})
                    tool_result(result); continue
                if user_input == '/stats':
                    result = execute_tool("search_kb", {"query": "__stats__"})
                    tool_result(result); continue

                messages = _handle_prompt(messages, user_input)
            except (KeyboardInterrupt, EOFError):
                break

    goodbye()


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
        # Interactive mode — wait for user's first prompt
        run_agent(None, interactive=True)
