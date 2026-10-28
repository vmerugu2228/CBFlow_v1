#!/usr/bin/env python3
"""
CBflow MCP Server — Exposes CBflow CLI as MCP tools for AI agents.

Usage:
    python cbflow_mcp_server.py                    # stdio transport (for Claude Desktop/Code)
    python cbflow_mcp_server.py --http --port 8090 # HTTP transport (for remote agents)

Tools provided:
    cbflow_run_command    — Execute any cbflow CLI command
    cbflow_read_file      — Read any file in the project
    cbflow_write_file     — Write/modify config files
    cbflow_query_race_db  — SQL query against RACE SQLite DB
    cbflow_list_workspace — List all runs in a workspace
    cbflow_get_run_status — Structured JSON run status
    cbflow_parse_tcl      — Parse TCL config into JSON dict
    cbflow_analyze_log    — Parse log file for errors/warnings
"""

import json
import os
import re
import shlex
import sqlite3
import subprocess
import sys
from pathlib import Path

# Determine paths
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
CBFLOW_CORE = os.path.dirname(SCRIPT_DIR)
CBFLOW_BIN = os.path.join(CBFLOW_CORE, 'bin', 'cbflow')
DEFAULT_WORKSPACE = os.path.join(os.path.dirname(CBFLOW_CORE), 'workarea_test')


# ═══════════════════════════════════════════════════════════════════════════════
# SECURITY — containment helpers
# ═══════════════════════════════════════════════════════════════════════════════
# Pre-fix the MCP server was pre-auth RCE: shell=True on any command,
# arbitrary file read/write with no base-dir containment, and
# `conn.execute(query)` taking any SQL (not just SELECT). HTTP transport
# bound 0.0.0.0 with no auth token. These helpers lock each attack
# surface down.

# Allow-list of containment roots. Any path must resolve inside one of
# these (via realpath) or the tool rejects. CBFLOW_CORE is the install
# tree; DEFAULT_WORKSPACE is the user's workarea root. Operators can
# extend via CBFLOW_MCP_EXTRA_ROOTS=":" separated absolute paths.
def _containment_roots() -> list:
    roots = [os.path.realpath(CBFLOW_CORE), os.path.realpath(DEFAULT_WORKSPACE)]
    extra = os.environ.get('CBFLOW_MCP_EXTRA_ROOTS', '')
    for p in extra.split(os.pathsep):
        if p and os.path.isdir(p):
            roots.append(os.path.realpath(p))
    return roots


def _path_contained(path: str) -> tuple:
    """Resolve path and check it lives inside a containment root.

    Returns (abs_path, None) on success or (None, error_msg) on refusal.
    Resolves symlinks via realpath so a symlink inside the root pointing
    outside is caught.
    """
    try:
        abs_path = path if os.path.isabs(path) else os.path.join(CBFLOW_CORE, path)
        real = os.path.realpath(abs_path)
    except OSError as e:
        return None, f'path resolve failed: {e}'
    roots = _containment_roots()
    for root in roots:
        if real == root or real.startswith(root + os.sep):
            return real, None
    return None, f'path outside allowed roots: {real}'


# Only commands beginning with the cbflow launcher are allowed. The
# command string is parsed with shlex (no shell=True) and must have
# "cbflow" (or an absolute path to it) as argv[0]. Pre-fix: shell=True
# on raw command meant any attacker-reachable MCP client could run
# arbitrary shell.
def _is_allowed_command(command: str) -> tuple:
    """Return (argv, None) if allowed; (None, error_msg) otherwise."""
    try:
        argv = shlex.split(command)
    except ValueError as e:
        return None, f'command parse failed: {e}'
    if not argv:
        return None, 'empty command'
    head = os.path.basename(argv[0])
    # Only the cbflow family of launchers is allowed. Operators can
    # extend via CBFLOW_MCP_EXTRA_BINS as a colon-sep list of basenames.
    allowed = {'cbflow', 'cbflow-pd', 'cbflow-dft', 'cbflow-dv',
               'cbflow-flow', 'cbflow-run', 'cbflow-bundle',
               'cbflow-workspace', 'cbflow-migrate', 'cbflow-test',
               'cbflow-project'}
    for p in os.environ.get('CBFLOW_MCP_EXTRA_BINS', '').split(os.pathsep):
        if p:
            allowed.add(p)
    if head not in allowed:
        return None, (f'command not allowed (must start with one of: '
                      f'{sorted(allowed)}); got {head!r}')
    return argv, None


# ═══════════════════════════════════════════════════════════════════════════════
# TOOL IMPLEMENTATIONS
# ═══════════════════════════════════════════════════════════════════════════════

def tool_run_command(command: str, cwd: str = None, timeout: int = 300) -> dict:
    """Execute a cbflow CLI command.

    Pre-fix: subprocess.run(command, shell=True) on attacker-controlled
    command string was pre-auth RCE. Now parsed with shlex (no shell),
    argv[0] must be a cbflow launcher, cwd must be in a containment
    root, and timeout is capped at 1 hour.
    """
    if not cwd:
        cwd = DEFAULT_WORKSPACE
    real_cwd, err = _path_contained(cwd)
    if err:
        return {"error": f"cwd: {err}", "success": False}
    argv, err = _is_allowed_command(command)
    if err:
        return {"error": err, "success": False}
    # Cap timeout to 1 hour to limit DoS surface.
    try:
        timeout = max(1, min(int(timeout), 3600))
    except (TypeError, ValueError):
        timeout = 300
    try:
        result = subprocess.run(
            argv, shell=False, cwd=real_cwd,
            capture_output=True, text=True, timeout=timeout,
            encoding='utf-8', errors='replace',
        )
        return {
            "exit_code": result.returncode,
            "stdout": result.stdout[-5000:] if len(result.stdout) > 5000 else result.stdout,
            "stderr": result.stderr[-2000:] if len(result.stderr) > 2000 else result.stderr,
            "success": result.returncode == 0,
        }
    except subprocess.TimeoutExpired:
        return {"error": f"Command timed out after {timeout}s", "success": False}
    except Exception as e:
        return {"error": str(e), "success": False}


# Hard cap on bytes we'll return from tool_read_file to prevent OOM via
# a malicious caller asking for 10M lines. 2 MiB is comfortable for
# config files and reasonable log tails.
_MAX_READ_BYTES = 2 * 1024 * 1024

def tool_read_file(path: str, offset: int = 0, limit: int = 500) -> dict:
    """Read a file with optional offset/limit.

    Pre-fix accepted any absolute path (including /etc/passwd, SSH keys,
    cloud creds). Now rejects anything outside the containment roots.
    """
    real, err = _path_contained(path)
    if err:
        return {"error": err}
    try:
        # Cap total bytes read to avoid OOM on huge files.
        with open(real, encoding='utf-8', errors='replace') as f:
            buf = f.read(_MAX_READ_BYTES + 1)
        truncated_by_size = len(buf) > _MAX_READ_BYTES
        if truncated_by_size:
            buf = buf[:_MAX_READ_BYTES]
        lines = buf.splitlines(keepends=True)
        total = len(lines)
        try:
            offset = max(0, int(offset))
            limit = max(0, min(int(limit), 10000))
        except (TypeError, ValueError):
            offset, limit = 0, 500
        selected = lines[offset:offset + limit]
        return {
            "path": real,
            "total_lines": total,
            "offset": offset,
            "lines_returned": len(selected),
            "truncated_by_size": truncated_by_size,
            "content": ''.join(selected),
        }
    except OSError as e:
        return {"error": str(e)}


def tool_write_file(path: str, content: str = None, edits: list = None) -> dict:
    """Write or edit a file.

    Pre-fix accepted any absolute path and could overwrite SSH keys /
    bashrc / etc. Also non-atomic. Now: containment + atomic_write.
    """
    real, err = _path_contained(path)
    if err:
        return {"error": err}
    try:
        # Lazy-import to avoid hard dependency when the MCP server
        # runs standalone (e.g. for testing without the full tree).
        try:
            sys.path.insert(0, os.path.join(CBFLOW_CORE, 'utils', 'core'))
            from paths import atomic_write
        finally:
            try:
                sys.path.remove(os.path.join(CBFLOW_CORE, 'utils', 'core'))
            except ValueError:
                pass
        if content is not None:
            atomic_write(real, content)
            return {"written": real, "size": len(content)}
        elif edits:
            with open(real, encoding='utf-8') as f:
                text = f.read()
            for edit in edits:
                text = text.replace(edit["old"], edit["new"])
            atomic_write(real, text)
            return {"edited": real, "edits_applied": len(edits)}
        else:
            return {"error": "Provide content or edits"}
    except OSError as e:
        return {"error": str(e)}


# Allow only SELECT / EXPLAIN / PRAGMA (reflection) in SQL queries;
# refuse anything that could mutate the DB or ATTACH another file.
_READONLY_SQL_RE = re.compile(r'^\s*(SELECT|WITH|EXPLAIN|PRAGMA)\b', re.IGNORECASE)

def tool_query_race_db(run_dir: str, query: str) -> dict:
    """Execute a SELECT query against a RACE SQLite database.

    Pre-fix: ran arbitrary SQL — ATTACH, DROP, UPDATE, DELETE all passed.
    Also no run_dir containment, so cross-project reads worked. Now:
    containment + statement-prefix allow-list + conn opened read-only
    via URI; row cap at 10k; one statement only (sqlite3's `execute`
    enforces that but the regex rejects compound inputs).
    """
    real_dir, err = _path_contained(run_dir)
    if err:
        return {"error": err}
    if not _READONLY_SQL_RE.match(query or ''):
        return {"error": "query must begin with SELECT, WITH, EXPLAIN, or PRAGMA"}
    if ';' in query.rstrip(';'):
        return {"error": "compound statements (;) not allowed"}
    try:
        db_files = list(Path(real_dir).glob('.race_*.db'))
        if not db_files:
            return {"error": f"No RACE DB found in {real_dir}"}
        db_path = str(db_files[0])
        # Open read-only via URI so DML/DDL cannot mutate the DB even
        # if the regex is bypassed by a cornercase.
        uri = f'file:{db_path}?mode=ro'
        conn = sqlite3.connect(uri, uri=True, timeout=10)
        try:
            conn.row_factory = sqlite3.Row
            cur = conn.execute(query)
            rows = []
            for r in cur:
                rows.append(dict(r))
                if len(rows) >= 10000:
                    break
        finally:
            conn.close()
        return {"db": db_path, "rows": rows, "count": len(rows)}
    except (sqlite3.Error, OSError) as e:
        return {"error": str(e)}


def tool_list_workspace(workspace: str = None) -> dict:
    """List all runs in a workspace with basic status."""
    ws = workspace or DEFAULT_WORKSPACE
    try:
        runs = []
        for d in sorted(os.listdir(ws)):
            if '_run_' in d and os.path.isdir(os.path.join(ws, d)):
                env_file = os.path.join(ws, d, '.run.cbflow.env')
                info = {"name": d, "flow_type": "", "design": "", "phase": ""}
                if os.path.exists(env_file):
                    with open(env_file) as f:
                        for line in f:
                            if 'CBFLOW_FLOW_TYPE' in line:
                                m = re.search(r'"([^"]*)"', line)
                                if m: info["flow_type"] = m.group(1)
                            elif 'CBFLOW_DESIGN_NAME' in line:
                                m = re.search(r'"([^"]*)"', line)
                                if m: info["design"] = m.group(1)
                runs.append(info)
        return {"workspace": ws, "runs": runs, "count": len(runs)}
    except Exception as e:
        return {"error": str(e)}


def tool_get_run_status(run_dir: str) -> dict:
    """Get structured status of a run from RACE DB."""
    try:
        db_files = list(Path(run_dir).glob('.race_*.db'))
        if not db_files:
            return {"error": "No RACE DB found"}
        conn = sqlite3.connect(str(db_files[0]))
        # Get job status summary
        cur = conn.execute("""
            SELECT j.stage, j.job_type, j.status, j.runtime_sec, j.exit_code
            FROM jobs j
            INNER JOIN (SELECT job_name, MAX(id) as mid FROM jobs GROUP BY job_name) g
            ON j.job_name = g.job_name AND j.id = g.mid
            INNER JOIN job_order o ON j.job_name = o.job_name
            WHERE j.job_type = 'stage'
            ORDER BY o.seq
        """)
        stages = []
        for row in cur:
            stages.append({
                "stage": row[0], "status": row[2] or "READY",
                "runtime": round(row[3] or 0, 1), "exit_code": row[4]
            })
        done = sum(1 for s in stages if s["status"] in ("DONE", "BYPASSED", "FORCE_VALIDATED"))
        failed = sum(1 for s in stages if s["status"] == "FAIL")
        conn.close()
        return {
            "run_dir": run_dir,
            "stages": stages,
            "total": len(stages),
            "done": done,
            "failed": failed,
            "result": "PASS" if done == len(stages) else ("FAIL" if failed > 0 else "IN_PROGRESS"),
        }
    except Exception as e:
        return {"error": str(e)}


def tool_parse_tcl(config_file: str) -> dict:
    """Parse a TCL config file into a JSON dict."""
    try:
        # Containment check — matches tool_read_file/tool_write_file posture.
        # Pre-fix: tool_parse_tcl accepted any absolute path, including
        # /etc/shadow or ~/.ssh/id_rsa, and returned matching `set …`
        # lines in the response, undermining the whole _containment_roots
        # allowlist for the public MCP endpoint.
        real, err = _path_contained(config_file)
        if err:
            return {"error": err}
        abs_path = real
        with open(abs_path) as f:
            content = f.read()
        variables = {}
        # Parse: set var(key) "value"
        for m in re.finditer(r'set\s+(\w+\([^)]+\))\s+"([^"]*)"', content):
            variables[m.group(1)] = m.group(2)
        # Parse: set var "value"
        for m in re.finditer(r'set\s+(\w+)\s+"([^"]*)"', content):
            if '(' not in m.group(1):
                variables[m.group(1)] = m.group(2)
        return {"file": abs_path, "variables": variables, "count": len(variables)}
    except Exception as e:
        return {"error": str(e)}


def tool_analyze_log(log_file: str, patterns: list = None) -> dict:
    """Parse a log file for errors, warnings, and key metrics."""
    try:
        # Containment check — pre-fix a public MCP client could pass
        # /etc/shadow or any system file and receive matching lines in
        # the `errors` / `warnings` arrays, bypassing the containment
        # allowlist that tool_read_file enforces.
        real, err = _path_contained(log_file)
        if err:
            return {"error": err}
        abs_path = real
        with open(abs_path) as f:
            lines = f.readlines()
        if patterns is None:
            patterns = [r'ERROR', r'FATAL', r'FAIL', r'WARNING', r'WARN']
        errors = []
        warnings = []
        for i, line in enumerate(lines):
            for pat in patterns[:3]:  # first 3 = errors
                if re.search(pat, line, re.IGNORECASE):
                    errors.append({"line": i + 1, "text": line.strip()[:200]})
                    break
            for pat in patterns[3:]:  # rest = warnings
                if re.search(pat, line, re.IGNORECASE):
                    warnings.append({"line": i + 1, "text": line.strip()[:200]})
                    break
        return {
            "file": abs_path,
            "total_lines": len(lines),
            "errors": errors[:50],
            "warnings": warnings[:50],
            "error_count": len(errors),
            "warning_count": len(warnings),
        }
    except Exception as e:
        return {"error": str(e)}


# ═══════════════════════════════════════════════════════════════════════════════
# MCP SERVER PROTOCOL (JSON-RPC over stdio)
# ═══════════════════════════════════════════════════════════════════════════════

TOOLS = [
    {
        "name": "cbflow_run_command",
        "description": "Execute a cbflow CLI command (e.g., 'cbflow workspace create --config uc.tcl', 'cbflow run all'). Use this for any cbflow operation.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "command": {"type": "string", "description": "Full shell command to execute"},
                "cwd": {"type": "string", "description": "Working directory (default: workarea_test)"},
                "timeout": {"type": "integer", "description": "Timeout in seconds (default: 300)"},
            },
            "required": ["command"],
        },
    },
    {
        "name": "cbflow_read_file",
        "description": "Read a file from the CBflow project. Use relative paths from PD/ or absolute paths.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "path": {"type": "string", "description": "File path (relative to PD/ or absolute)"},
                "offset": {"type": "integer", "description": "Start line (0-indexed, default: 0)"},
                "limit": {"type": "integer", "description": "Max lines to read (default: 500)"},
            },
            "required": ["path"],
        },
    },
    {
        "name": "cbflow_write_file",
        "description": "Write or edit a file. Provide 'content' for full write, or 'edits' for find-replace.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "path": {"type": "string", "description": "File path"},
                "content": {"type": "string", "description": "Full file content (overwrites)"},
                "edits": {
                    "type": "array",
                    "description": "List of {old, new} replacements",
                    "items": {
                        "type": "object",
                        "properties": {
                            "old": {"type": "string"},
                            "new": {"type": "string"},
                        },
                    },
                },
            },
            "required": ["path"],
        },
    },
    {
        "name": "cbflow_query_race_db",
        "description": "Run a SQL query against a run's RACE SQLite database. Tables: jobs, run_info, job_order, stage_metrics.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "run_dir": {"type": "string", "description": "Path to run directory"},
                "query": {"type": "string", "description": "SQL SELECT query"},
            },
            "required": ["run_dir", "query"],
        },
    },
    {
        "name": "cbflow_list_workspace",
        "description": "List all CBflow runs in a workspace directory.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "workspace": {"type": "string", "description": "Workspace path (default: workarea_test)"},
            },
        },
    },
    {
        "name": "cbflow_get_run_status",
        "description": "Get structured status (stages, done/failed counts, result) from a run's RACE DB.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "run_dir": {"type": "string", "description": "Path to run directory"},
            },
            "required": ["run_dir"],
        },
    },
    {
        "name": "cbflow_parse_tcl",
        "description": "Parse a TCL configuration file into a JSON dictionary of variable names and values.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "config_file": {"type": "string", "description": "Path to TCL config file"},
            },
            "required": ["config_file"],
        },
    },
    {
        "name": "cbflow_analyze_log",
        "description": "Analyze a log file for errors and warnings. Returns counts and matching lines.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "log_file": {"type": "string", "description": "Path to log file"},
                "patterns": {
                    "type": "array",
                    "description": "Regex patterns (first 3=errors, rest=warnings). Default: ERROR,FATAL,FAIL,WARNING,WARN",
                    "items": {"type": "string"},
                },
            },
            "required": ["log_file"],
        },
    },
    {
        "name": "cbflow_search_knowledge",
        "description": "Search the CBflow knowledge base (docs, code, EDA guides, experience).",
        "inputSchema": {
            "type": "object",
            "properties": {
                "query": {"type": "string", "description": "Search query"},
                "n_results": {"type": "integer", "description": "Max results (default: 5)"},
                "collections": {"type": "array", "description": "Filter collections", "items": {"type": "string"}},
            },
            "required": ["query"],
        },
    },
    {
        "name": "cbflow_learn_experience",
        "description": "Record a learned pattern or fix for future retrieval.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "content": {"type": "string", "description": "What was learned"},
                "category": {"type": "string", "description": "Category (fix/pattern/config/error)"},
            },
            "required": ["content"],
        },
    },
]

def tool_search_knowledge(query: str, n_results: int = 5, collections: list = None) -> dict:
    """Search the knowledge base."""
    try:
        from cbflow_knowledge import KnowledgeEngine
        engine = KnowledgeEngine()
        results = engine.search(query, n_results, collections)
        return {"results": results, "count": len(results)}
    except ImportError:
        return {"error": "chromadb not installed. pip install chromadb"}
    except Exception as e:
        return {"error": str(e)}


def tool_learn_experience(content: str, category: str = "general") -> dict:
    """Record a learned experience."""
    try:
        from cbflow_knowledge import KnowledgeEngine
        engine = KnowledgeEngine()
        doc_id = engine.learn(content, category)
        return {"stored": True, "id": doc_id, "category": category}
    except Exception as e:
        return {"error": str(e)}


TOOL_HANDLERS = {
    "cbflow_run_command": lambda args: tool_run_command(args["command"], args.get("cwd"), args.get("timeout", 300)),
    "cbflow_read_file": lambda args: tool_read_file(args["path"], args.get("offset", 0), args.get("limit", 500)),
    "cbflow_write_file": lambda args: tool_write_file(args["path"], args.get("content"), args.get("edits")),
    "cbflow_query_race_db": lambda args: tool_query_race_db(args["run_dir"], args["query"]),
    "cbflow_list_workspace": lambda args: tool_list_workspace(args.get("workspace")),
    "cbflow_get_run_status": lambda args: tool_get_run_status(args["run_dir"]),
    "cbflow_parse_tcl": lambda args: tool_parse_tcl(args["config_file"]),
    "cbflow_analyze_log": lambda args: tool_analyze_log(args["log_file"], args.get("patterns")),
    "cbflow_search_knowledge": lambda args: tool_search_knowledge(args["query"], args.get("n_results", 5), args.get("collections")),
    "cbflow_learn_experience": lambda args: tool_learn_experience(args["content"], args.get("category", "general")),
}


def handle_request(request: dict) -> dict:
    """Handle a JSON-RPC request."""
    method = request.get("method", "")
    req_id = request.get("id")

    if method == "initialize":
        return {"jsonrpc": "2.0", "id": req_id, "result": {
            "protocolVersion": "2024-11-05",
            "capabilities": {"tools": {}},
            "serverInfo": {"name": "cbflow-mcp-server", "version": "1.0.0"},
        }}

    elif method == "notifications/initialized":
        return None  # No response needed

    elif method == "tools/list":
        return {"jsonrpc": "2.0", "id": req_id, "result": {"tools": TOOLS}}

    elif method == "tools/call":
        tool_name = request["params"]["name"]
        tool_args = request["params"].get("arguments", {})
        handler = TOOL_HANDLERS.get(tool_name)
        if not handler:
            return {"jsonrpc": "2.0", "id": req_id, "result": {
                "content": [{"type": "text", "text": f"Unknown tool: {tool_name}"}],
                "isError": True,
            }}
        try:
            result = handler(tool_args)
            return {"jsonrpc": "2.0", "id": req_id, "result": {
                "content": [{"type": "text", "text": json.dumps(result, indent=2, default=str)}],
            }}
        except Exception as e:
            return {"jsonrpc": "2.0", "id": req_id, "result": {
                "content": [{"type": "text", "text": f"Error: {e}"}],
                "isError": True,
            }}

    return {"jsonrpc": "2.0", "id": req_id, "error": {"code": -32601, "message": f"Unknown method: {method}"}}


def run_stdio():
    """Run MCP server over stdio (for Claude Desktop / Claude Code)."""
    sys.stderr.write("CBflow MCP Server started (stdio)\n")
    buf = ""
    while True:
        try:
            line = sys.stdin.readline()
            if not line:
                break
            buf += line
            # Try to parse complete JSON-RPC messages
            try:
                request = json.loads(buf)
                buf = ""
                response = handle_request(request)
                if response:
                    sys.stdout.write(json.dumps(response) + "\n")
                    sys.stdout.flush()
            except json.JSONDecodeError:
                continue  # Incomplete message, keep buffering
        except KeyboardInterrupt:
            break


if __name__ == "__main__":
    if "--http" in sys.argv:
        # HTTP mode for remote agents.
        # Pre-fix: unconditionally bound 0.0.0.0 with NO authentication —
        # anyone on the LAN had pre-auth RCE via /api/cbflow_run_command.
        # Now binds 127.0.0.1 by default; opt into LAN exposure explicitly
        # with CBFLOW_MCP_PUBLIC=1 AND set CBFLOW_MCP_TOKEN=<secret> which
        # the HTTP handler enforces via Authorization: Bearer header.
        import http.server
        port = 8090
        for i, arg in enumerate(sys.argv):
            if arg == "--port" and i + 1 < len(sys.argv):
                port = int(sys.argv[i + 1])

        bind = '127.0.0.1'
        _public = os.environ.get('CBFLOW_MCP_PUBLIC', '').lower() in ('1','true','yes','on')
        _token = os.environ.get('CBFLOW_MCP_TOKEN', '')
        if _public:
            if not _token:
                print("ERROR: CBFLOW_MCP_PUBLIC=1 requires CBFLOW_MCP_TOKEN=<secret>.",
                      file=sys.stderr)
                sys.exit(2)
            bind = '0.0.0.0'
            print(f"WARNING: Binding 0.0.0.0 with Bearer-token auth. "
                  f"Any reachable attacker with the token has full access.",
                  file=sys.stderr)

        print(f"CBflow MCP Server (HTTP) on {bind}:{port}")

        _MAX_BODY = 1 * 1024 * 1024  # 1 MiB

        class Handler(http.server.BaseHTTPRequestHandler):
            def _reject(self, code, msg):
                body = json.dumps({'error': msg}).encode('utf-8')
                self.send_response(code)
                self.send_header('Content-Type', 'application/json')
                self.send_header('Content-Length', str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def do_POST(self):
                # Enforce Bearer token when running in --public mode.
                if _token:
                    auth = self.headers.get('Authorization', '')
                    expected = f'Bearer {_token}'
                    if auth != expected:
                        return self._reject(401, 'unauthorized')
                try:
                    raw_len = self.headers.get('Content-Length')
                    length = int(raw_len) if raw_len is not None else 0
                except (TypeError, ValueError):
                    return self._reject(400, 'invalid Content-Length')
                if length < 0:
                    return self._reject(400, 'negative Content-Length')
                if length > _MAX_BODY:
                    return self._reject(413, f'body too large (>{_MAX_BODY})')
                try:
                    body = json.loads(self.rfile.read(length).decode('utf-8')) if length else {}
                except (ValueError, UnicodeDecodeError):
                    return self._reject(400, 'invalid JSON body')
                try:
                    response = handle_request(body)
                except Exception as e:
                    return self._reject(500, f'handler error: {type(e).__name__}')
                payload = json.dumps(response or {}).encode('utf-8')
                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self.send_header('Content-Length', str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)
            def log_message(self, *args): pass

        http.server.HTTPServer((bind, port), Handler).serve_forever()
    else:
        run_stdio()
