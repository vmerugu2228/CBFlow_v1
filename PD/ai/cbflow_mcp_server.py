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
# TOOL IMPLEMENTATIONS
# ═══════════════════════════════════════════════════════════════════════════════

def tool_run_command(command: str, cwd: str = None, timeout: int = 300) -> dict:
    """Execute a cbflow CLI command."""
    if not cwd:
        cwd = DEFAULT_WORKSPACE
    try:
        result = subprocess.run(
            command, shell=True, cwd=cwd,
            capture_output=True, text=True, timeout=timeout
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


def tool_read_file(path: str, offset: int = 0, limit: int = 500) -> dict:
    """Read a file with optional offset/limit."""
    try:
        abs_path = path if os.path.isabs(path) else os.path.join(CBFLOW_CORE, path)
        with open(abs_path) as f:
            lines = f.readlines()
        total = len(lines)
        selected = lines[offset:offset + limit]
        return {
            "path": abs_path,
            "total_lines": total,
            "offset": offset,
            "lines_returned": len(selected),
            "content": ''.join(selected),
        }
    except Exception as e:
        return {"error": str(e)}


def tool_write_file(path: str, content: str = None, edits: list = None) -> dict:
    """Write or edit a file. edits = [{"old": "...", "new": "..."}]"""
    try:
        abs_path = path if os.path.isabs(path) else os.path.join(CBFLOW_CORE, path)
        if content is not None:
            with open(abs_path, 'w') as f:
                f.write(content)
            return {"written": abs_path, "size": len(content)}
        elif edits:
            with open(abs_path) as f:
                text = f.read()
            for edit in edits:
                text = text.replace(edit["old"], edit["new"])
            with open(abs_path, 'w') as f:
                f.write(text)
            return {"edited": abs_path, "edits_applied": len(edits)}
        else:
            return {"error": "Provide content or edits"}
    except Exception as e:
        return {"error": str(e)}


def tool_query_race_db(run_dir: str, query: str) -> dict:
    """Execute SQL query against a RACE SQLite database."""
    try:
        # Find the DB file
        db_files = list(Path(run_dir).glob('.race_*.db'))
        if not db_files:
            return {"error": f"No RACE DB found in {run_dir}"}
        db_path = str(db_files[0])
        conn = sqlite3.connect(db_path)
        conn.row_factory = sqlite3.Row
        cur = conn.execute(query)
        rows = [dict(r) for r in cur.fetchall()]
        conn.close()
        return {"db": db_path, "rows": rows, "count": len(rows)}
    except Exception as e:
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
        abs_path = config_file if os.path.isabs(config_file) else os.path.join(CBFLOW_CORE, config_file)
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
        abs_path = log_file if os.path.isabs(log_file) else log_file
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
]

TOOL_HANDLERS = {
    "cbflow_run_command": lambda args: tool_run_command(args["command"], args.get("cwd"), args.get("timeout", 300)),
    "cbflow_read_file": lambda args: tool_read_file(args["path"], args.get("offset", 0), args.get("limit", 500)),
    "cbflow_write_file": lambda args: tool_write_file(args["path"], args.get("content"), args.get("edits")),
    "cbflow_query_race_db": lambda args: tool_query_race_db(args["run_dir"], args["query"]),
    "cbflow_list_workspace": lambda args: tool_list_workspace(args.get("workspace")),
    "cbflow_get_run_status": lambda args: tool_get_run_status(args["run_dir"]),
    "cbflow_parse_tcl": lambda args: tool_parse_tcl(args["config_file"]),
    "cbflow_analyze_log": lambda args: tool_analyze_log(args["log_file"], args.get("patterns")),
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
        # HTTP mode for remote agents
        import http.server
        port = 8090
        for i, arg in enumerate(sys.argv):
            if arg == "--port" and i + 1 < len(sys.argv):
                port = int(sys.argv[i + 1])
        print(f"CBflow MCP Server (HTTP) on port {port}")

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_POST(self):
                length = int(self.headers.get('Content-Length', 0))
                body = json.loads(self.rfile.read(length)) if length else {}
                response = handle_request(body)
                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps(response or {}).encode())
            def log_message(self, *args): pass

        http.server.HTTPServer(('0.0.0.0', port), Handler).serve_forever()
    else:
        run_stdio()
