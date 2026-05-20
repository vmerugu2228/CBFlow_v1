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
ANTHROPIC_API_KEY = os.environ.get('ANTHROPIC_API_KEY', '')
CLAUDE_MODEL = os.environ.get('CLAUDE_MODEL', 'claude-sonnet-4-6')
HYBRID_MODE = os.environ.get('SMARTGENIE_HYBRID', '').lower() in ('1', 'true', 'yes')
USERNAME = os.environ.get('USER', 'anonymous')
MAX_TURNS = 5
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
1. When user asks you to DO something (create, run, execute, delete, build, set up) — USE TOOLS IMMEDIATELY. Do NOT explain steps. Do NOT show instructions. Just DO IT by calling bash tool.
2. When user asks a QUESTION (what, how, explain, list, describe) — answer briefly from knowledge. Max 10 lines.
3. NEVER give step-by-step instructions. NEVER show "example commands". Just execute them.
4. NEVER say "consult the guide" or "Would you like me to proceed". Just DO it.
5. Keep answers SHORT. Max 10 lines for questions. For actions, just execute and report result.
6. When you must run commands: cd to correct directory first.
7. "yes" means proceed with whatever was discussed. Remember context.

Respond with tool calls for actions, short text for questions."""

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

def claude_chat(messages: list) -> str:
    """Send chat to Claude API and LEARN the response to ChromaDB."""
    api_key = os.environ.get('ANTHROPIC_API_KEY', '') or ANTHROPIC_API_KEY
    if not api_key:
        return None  # No API key — fall back to local

    try:
        import anthropic
        client = anthropic.Anthropic(api_key=api_key)

        # Convert messages format (remove system from messages, pass separately)
        system_msg = ""
        api_messages = []
        for m in messages:
            if m["role"] == "system":
                system_msg = m["content"]
            else:
                api_messages.append(m)

        claude_model = os.environ.get('CLAUDE_MODEL', '') or CLAUDE_MODEL
        response = client.messages.create(
            model=claude_model,
            max_tokens=4096,
            system=system_msg if system_msg else "You are a VLSI/EDA expert and CBflow automation assistant.",
            messages=api_messages,
        )

        # Extract text response
        answer = ""
        for block in response.content:
            if hasattr(block, 'text'):
                answer += block.text

        # LEARN: save Claude's response to ChromaDB for future offline use
        if answer and len(answer) > 50:
            try:
                user_query = ""
                for m in reversed(api_messages):
                    if m["role"] == "user" and not m.get("content", "").startswith("Tool result:"):
                        user_query = m["content"][:200]
                        break

                from cbflow_knowledge import KnowledgeEngine
                engine = KnowledgeEngine()
                engine.learn(
                    f"Q: {user_query}\nA: {answer}",
                    category="claude_learned",
                    context={"source": "claude_api", "model": claude_model, "user": USERNAME}
                )
            except Exception:
                pass  # Don't fail if learning fails

        return answer

    except ImportError:
        return None  # anthropic not installed
    except Exception as e:
        return f"ERROR: Claude API: {e}"


def ollama_chat(messages: list, model: str = MODEL) -> str:
    """Send chat — hybrid mode tries Claude first, falls back to local."""
    import requests

    # HYBRID MODE: try Claude API first (learns to ChromaDB), fall back to local
    hybrid = os.environ.get('SMARTGENIE_HYBRID', '').lower() in ('1', 'true', 'yes') or HYBRID_MODE
    if hybrid:
        claude_response = claude_chat(messages)
        if claude_response and not claude_response.startswith("ERROR:"):
            return claude_response
        # Claude failed or unavailable — fall back to local

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

    hybrid = os.environ.get('SMARTGENIE_HYBRID', '').lower() in ('1', 'true', 'yes') or HYBRID_MODE
    if hybrid:
        info("HYBRID MODE: Claude API (online) + local knowledge learning")
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

    def _detect_file_path(text):
        """Detect if user input contains a file path."""
        # Match absolute paths or ~/paths
        m = re.search(r'(/[\w./ -]+\.\w+|~/[\w./ -]+\.\w+)', text)
        if m:
            path = os.path.expanduser(m.group(1))
            if os.path.exists(path):
                return path
        return None

    def _ingest_file(filepath):
        """Auto-ingest a file (PDF/text/TCL) into ChromaDB and return summary."""
        info(f"Reading: {os.path.basename(filepath)}")
        try:
            from cbflow_knowledge import KnowledgeEngine
            engine = KnowledgeEngine()
            n = engine.ingest_file(filepath, 'eda_guides', {"type": "user_uploaded"})
            if n > 0:
                success(f"Ingested {n} chunks from {os.path.basename(filepath)}")
                # Read first part for immediate context
                ext = os.path.splitext(filepath)[1].lower()
                if ext == '.pdf':
                    text = engine._read_pdf(filepath)
                else:
                    with open(filepath, errors='ignore') as f:
                        text = f.read()
                return text[:5000]  # Return first 5000 chars for immediate use
            else:
                error(f"Could not extract text from {os.path.basename(filepath)}")
                return None
        except Exception as e:
            error(f"Ingest failed: {e}")
            return None

    def _is_action_request(text):
        """Detect if user wants to DO something (vs just asking a question)."""
        words = set(text.lower().split())
        return bool(words & ACTION_WORDS)

    def _parse_action_intent(user_input):
        """Parse user's natural language into exact cbflow commands.
        Returns list of (description, command) tuples, or None if can't parse."""
        text = user_input.lower()
        cbflow = CBFLOW_BIN
        ws = DEFAULT_WORKSPACE

        # Extract parameters from natural language
        flow_type = None
        for ft in ['SYNTH_PNR', 'SYNTH_FP_PNR', 'SYNTH', 'PNR', 'STA', 'LEC', 'CLP', 'PV', 'EMIR', 'FP', 'FCFP', 'POPT', 'ECO']:
            if ft.lower() in text or ft.lower().replace('_', ' ') in text:
                flow_type = ft
                break
        # Common aliases
        if not flow_type:
            if 'synth' in text and 'pnr' in text: flow_type = 'SYNTH_PNR'
            elif 'synth' in text: flow_type = 'SYNTH'
            elif 'place' in text and 'route' in text: flow_type = 'PNR'
            elif 'timing' in text or 'sta' in text: flow_type = 'STA'
            elif 'verification' in text or 'drc' in text or 'lvs' in text: flow_type = 'PV'

        # Extract run name
        run_name = None
        import re as _re
        m = _re.search(r'(?:run\s+name|named?)\s+(\w+)', text)
        if m: run_name = m.group(1)
        m = _re.search(r'name\s+(?:as\s+)?(\w+)', text)
        if m and not run_name: run_name = m.group(1)

        # Extract block/design name
        block_name = None
        m = _re.search(r'(?:block|design)\s+(?:name\s+)?(?:as\s+)?(\w+)', text)
        if m: block_name = m.group(1)

        # ── CREATE A RUN ──
        if ('create' in text or 'set up' in text or 'make' in text) and ('run' in text or 'workspace' in text or 'flow' in text):
            if not flow_type:
                return None  # Can't determine flow type

            # Check if a matching user config exists
            uc_file = f"uc_{flow_type}.tcl"
            uc_path = os.path.join(ws, uc_file)

            commands = []

            if run_name or block_name:
                # Need to create a custom user config
                config_name = f"uc_{flow_type}_{run_name or 'custom'}.tcl"
                arr = flow_type.lower().replace('_', '_')
                config_content = f'set project(name) "ravendrive"\\n'
                config_content += f'set project(phase) "P0"\\n'
                config_content += f'set flow(type) "{flow_type}"\\n'
                config_content += f'set flow(design_name) "{block_name or "cpu_core"}"\\n'
                config_content += f'set flow(run_name) "{run_name or "run1"}"\\n'
                config_content += f'set flow(test_mode) "true"\\n'

                # Add flow-specific inputs from existing config
                if os.path.exists(uc_path):
                    with open(uc_path) as f:
                        for line in f:
                            if 'input,' in line and 'set ' in line:
                                config_content += line.strip() + '\\n'

                commands.append((
                    f"Creating config: {config_name}",
                    f'printf "{config_content}" > {ws}/{config_name}'
                ))
                commands.append((
                    f"Creating {flow_type} run '{run_name or 'run1'}' for {block_name or 'cpu_core'}",
                    f'{cbflow} workspace create --config {config_name}'
                ))
            elif os.path.exists(uc_path):
                commands.append((
                    f"Creating {flow_type} run using {uc_file}",
                    f'{cbflow} workspace create --config {uc_file}'
                ))
            else:
                return None
            return commands

        # ── RUN A FLOW ──
        if 'run' in text and ('all' in text or 'flow' in text or 'execute' in text):
            if flow_type:
                # Find the run directory
                run_dirs = [d for d in os.listdir(ws) if f'_run_{flow_type}_' in d and os.path.isdir(os.path.join(ws, d))]
                if run_dirs:
                    run_dir = os.path.join(ws, sorted(run_dirs)[-1])
                    return [
                        (f"Running {flow_type} flow", f'cd {run_dir} && {cbflow} run all')
                    ]
            return None

        # ── CHECK STATUS ──
        if 'status' in text:
            if flow_type:
                run_dirs = [d for d in os.listdir(ws) if f'_run_{flow_type}_' in d]
                if run_dirs:
                    run_dir = os.path.join(ws, sorted(run_dirs)[-1])
                    return [(f"Checking {flow_type} status", f'cd {run_dir} && {cbflow} run status')]
            return [(f"Listing all runs", f'cd {ws} && {cbflow} workspace status')]

        # ── ADD NODE ──
        if 'add' in text and 'node' in text:
            m = _re.search(r'node\s+(\w+)', text)
            node_name = m.group(1) if m else None
            m = _re.search(r'type\s+(\w+)', text)
            node_type = m.group(1) if m else None
            m = _re.search(r'(?:dep|after|from)\s+(\w+)', text)
            dep = m.group(1) if m else None
            if node_type and dep:
                if flow_type:
                    run_dirs = [d for d in os.listdir(ws) if f'_run_{flow_type}_' in d]
                    if run_dirs:
                        run_dir = os.path.join(ws, sorted(run_dirs)[-1])
                        cmd = f'cd {run_dir} && {cbflow} run add-node'
                        if node_name: cmd += f' --node {node_name}'
                        cmd += f' --type {node_type} --dep {dep}'
                        return [(f"Adding node {node_name or node_type} after {dep}", cmd)]
            return None

        # ── CREATE BRANCH ──
        if 'branch' in text and ('create' in text or 'make' in text):
            m = _re.search(r'branch\s+(?:named?\s+)?(\w+)', text)
            branch_name = m.group(1) if m else None
            m = _re.search(r'from\s+(\w+)', text)
            from_stage = m.group(1) if m else None
            if branch_name and from_stage and flow_type:
                run_dirs = [d for d in os.listdir(ws) if f'_run_{flow_type}_' in d]
                if run_dirs:
                    run_dir = os.path.join(ws, sorted(run_dirs)[-1])
                    return [(f"Creating branch '{branch_name}' from {from_stage}",
                             f'cd {run_dir} && {cbflow} run create-branch --branch {branch_name} --from {from_stage}')]
            return None

        # ── RETRACE ──
        if 'retrace' in text or 'rerun' in text or 're-run' in text:
            m = _re.search(r'from\s+(\w+)', text)
            from_stage = m.group(1) if m else None
            if from_stage and flow_type:
                run_dirs = [d for d in os.listdir(ws) if f'_run_{flow_type}_' in d]
                if run_dirs:
                    run_dir = os.path.join(ws, sorted(run_dirs)[-1])
                    return [(f"Retracing from {from_stage}", f'cd {run_dir} && {cbflow} run retrace --from {from_stage}')]
            return None

        # ── RELEASE ──
        if 'release' in text:
            tag = None
            for t in ['FP_EXIT', 'PLACE_EXIT', 'CTS_EXIT', 'PRO_EXIT', 'BTO', 'MTO']:
                if t.lower() in text: tag = t; break
            if tag:
                return [(f"Release {tag}", f'cd {ws} && {cbflow} run release --tag {tag}')]
            return [(f"Release check", f'cd {ws} && {cbflow} run release --dry-run')]

        # ── DELETE / CLEAN ──
        if 'delete' in text or 'clean' in text or 'remove' in text:
            if flow_type:
                run_dirs = [d for d in os.listdir(ws) if f'_run_{flow_type}_' in d]
                if run_dirs:
                    return [(f"Removing {flow_type} runs", f'rm -rf {ws}/{run_dirs[-1]}')]
            return None

        return None  # Can't parse — fall back to LLM

    def _answer_from_knowledge(messages, query):
        """Answer directly from KB without LLM tool calling."""
        # Show search progress
        from cli_ui import dim, cyan
        spinner = Spinner("Searching knowledge base")
        spinner.start()

        kb_result = execute_tool("search_kb", {"query": query, "n": 8})
        spinner.stop()

        if not kb_result or "No results" in kb_result or "error" in kb_result.lower():
            info("No matching knowledge found — using LLM reasoning")
            return None

        # Show what was found
        result_lines = kb_result.strip().split('\n')
        sources = [l.strip() for l in result_lines if l.strip().startswith('[')]
        if sources:
            info(f"Found {len(sources)} relevant sources:")
            for s in sources[:4]:
                print(f"    {dim(s[:80])}")

        # Ask LLM to synthesize — SHORT answer
        synth_messages = [
            {"role": "system", "content": "You are a VLSI/EDA expert. Answer the question using the provided knowledge. Be BRIEF — max 10 lines. Use bullet points. No lengthy explanations."},
            {"role": "user", "content": f"Knowledge:\n{kb_result[:4000]}\n\nQuestion: {query}\n\nAnswer in max 10 lines:"}
        ]
        spinner = Spinner("Thinking")
        spinner.start()
        t0 = time.time()
        response = ollama_chat(synth_messages)
        elapsed = time.time() - t0
        spinner.stop()

        # Strip any tool call attempts
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
        """Handle a user prompt — file ingest, question from KB, or action with tools."""

        # Check if user provided a file path — auto-ingest it
        filepath = _detect_file_path(user_input)
        if filepath:
            file_content = _ingest_file(filepath)
            if file_content:
                # Extract the question part (remove file path from input)
                question = re.sub(r'/[\w./ -]+\.\w+|~/[\w./ -]+\.\w+', '', user_input).strip(' -')
                if not question or len(question) < 5:
                    question = f"summarize the contents of {os.path.basename(filepath)}"

                # Answer using the ingested content + KB
                info(f"Answering from ingested content...")
                synth_messages = [
                    {"role": "system", "content": "You are a VLSI/EDA expert. Answer using the document content provided. Be thorough and specific. Include command syntax and examples."},
                    {"role": "user", "content": f"Document ({os.path.basename(filepath)}):\n{file_content[:4000]}\n\nQuestion: {question}\n\nAnswer comprehensively:"}
                ]
                spinner = Spinner("Analyzing document")
                spinner.start()
                response = ollama_chat(synth_messages)
                spinner.stop()
                clean = re.sub(r'\{["\']tool["\'].*?\}', '', response, flags=re.DOTALL).strip()
                clean = re.sub(r'```json.*?```', '', clean, flags=re.DOTALL).strip()
                if clean:
                    separator()
                    agent_text(clean)
                    print()
                messages.append({"role": "user", "content": user_input})
                messages.append({"role": "assistant", "content": clean or response})
                return messages

        if _is_action_request(user_input):
            # Action: parse intent and execute EXACT commands — don't trust LLM to build commands
            commands = _parse_action_intent(user_input)
            if commands:
                for cmd_desc, cmd in commands:
                    info(f"{cmd_desc}")
                    result = execute_tool("bash", {"command": cmd, "cwd": DEFAULT_WORKSPACE})
                    lines = result.strip().split('\n')
                    for l in lines[:8]:
                        if 'ERROR' in l or 'FAIL' in l:
                            from cli_ui import red
                            print(f"    {red(l[:120])}")
                        elif 'PASS' in l or 'SUCCESS' in l or 'Created' in l or 'Directory' in l:
                            from cli_ui import green
                            print(f"    {green(l[:120])}")
                        elif l.strip():
                            from cli_ui import dim
                            print(f"    {dim(l[:120])}")
                    if len(lines) > 8:
                        from cli_ui import dim
                        print(f"    {dim(f'... ({len(lines)-8} more lines)')}")
                separator()
                success("Done.")
                print()
                messages.append({"role": "user", "content": user_input})
                messages.append({"role": "assistant", "content": f"Executed: {'; '.join(c[0] for c in commands)}"})
            else:
                # Can't parse — fall back to LLM with tool calling
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
