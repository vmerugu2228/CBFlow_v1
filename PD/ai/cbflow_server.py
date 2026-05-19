#!/usr/bin/env python3
"""
CBflow SmartGenie Server — Central AI server for multi-user enterprise deployment.

Architecture:
    ┌─────────────────────────────────────────────────────────────┐
    │                    On-Premise Server                         │
    │                                                             │
    │  ┌──────────┐  ┌────────────────┐  ┌──────────────────┐   │
    │  │  Ollama   │  │  Central       │  │  SmartGenie      │   │
    │  │  (LLM)   │  │  ChromaDB      │  │  HTTP Server     │   │
    │  │          │  │                │  │  (this script)   │   │
    │  │ qwen2.5  │  │ shared_docs    │  │                  │   │
    │  │ llama3   │  │ shared_code    │  │  /api/chat       │   │
    │  │          │  │ shared_exp     │  │  /api/knowledge  │   │
    │  │          │  │ user_<name>    │  │  /api/learn      │   │
    │  └──────────┘  └────────────────┘  │  /api/status     │   │
    │                                     └──────────────────┘   │
    └─────────────────────────────────────────────────────────────┘
              ▲              ▲              ▲
              │              │              │
    ┌─────────┼──────────────┼──────────────┼─────────┐
    │         │              │              │         │
  User A   User B         User C        User D    User E
  (cbflow   (cbflow       (cbflow       (cbflow   (cbflow
  smartgenie smartgenie   smartgenie    smartgenie smartgenie
  --server)  --server)    --server)     --server)  --server)

Knowledge Flow:
    User solves problem → learn() → shared_experience collection
                                  → user_<name> collection (private notes)
    Other user has same problem → search() → finds shared fix instantly

Usage:
    # On the server:
    python cbflow_server.py --port 8091 --host 0.0.0.0

    # On each user's machine:
    cbflow smartgenie --server http://server-ip:8091 "run SYNTH_PNR"

    # Or set env:
    export SMARTGENIE_SERVER=http://server-ip:8091
    cbflow smartgenie "run all flows"
"""

import http.server
import json
import os
import re
import subprocess
import sys
import threading
import time
from datetime import datetime
from urllib.parse import urlparse, parse_qs

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
CBFLOW_CORE = os.path.dirname(SCRIPT_DIR)

# Server config
DEFAULT_PORT = 8091
OLLAMA_URL = os.environ.get('OLLAMA_URL', 'http://localhost:11434')
MODEL = os.environ.get('CBFLOW_MODEL', 'qwen2.5:7b')

# ═══════════════════════════════════════════════════════════════════════════════
# CENTRAL KNOWLEDGE ENGINE (multi-user)
# ═══════════════════════════════════════════════════════════════════════════════

class CentralKnowledge:
    """Multi-user knowledge base with shared + per-user collections."""

    def __init__(self):
        import chromadb
        db_dir = os.path.join(SCRIPT_DIR, '.central_knowledge_db')
        self.client = chromadb.PersistentClient(path=db_dir)

        # Shared collections (all users read/write)
        self.shared_docs = self.client.get_or_create_collection("shared_docs")
        self.shared_code = self.client.get_or_create_collection("shared_code")
        self.shared_experience = self.client.get_or_create_collection("shared_experience")
        self.shared_eda = self.client.get_or_create_collection("shared_eda")

    def _get_user_collection(self, username: str):
        """Get or create a per-user private collection."""
        return self.client.get_or_create_collection(f"user_{username}")

    def search(self, query: str, username: str = None, n_results: int = 5) -> list:
        """Search shared knowledge + user's private collection."""
        results = []
        for coll in [self.shared_experience, self.shared_docs, self.shared_code, self.shared_eda]:
            try:
                r = coll.query(query_texts=[query], n_results=min(n_results, 3))
                if r and r['documents']:
                    for i, doc in enumerate(r['documents'][0]):
                        meta = r['metadatas'][0][i] if r['metadatas'] else {}
                        results.append({
                            'text': doc,
                            'source': meta.get('source', ''),
                            'collection': coll.name,
                            'user': meta.get('user', 'system'),
                            'distance': r['distances'][0][i] if r['distances'] else 0,
                        })
            except Exception:
                continue

        # Also search user's private collection
        if username:
            try:
                user_coll = self._get_user_collection(username)
                r = user_coll.query(query_texts=[query], n_results=min(n_results, 2))
                if r and r['documents']:
                    for i, doc in enumerate(r['documents'][0]):
                        meta = r['metadatas'][0][i] if r['metadatas'] else {}
                        results.append({
                            'text': doc, 'source': meta.get('source', ''),
                            'collection': f'user_{username}',
                            'user': username, 'distance': r['distances'][0][i],
                        })
            except Exception:
                pass

        results.sort(key=lambda x: x['distance'])
        return results[:n_results]

    def learn(self, content: str, category: str, username: str,
              private: bool = False) -> dict:
        """Record experience. Shared by default, private if requested."""
        import hashlib
        doc_id = hashlib.md5(f"{content}:{datetime.now().isoformat()}".encode()).hexdigest()[:12]
        meta = {
            "category": category,
            "user": username,
            "timestamp": datetime.now().isoformat(),
            "type": "experience",
        }

        if private:
            coll = self._get_user_collection(username)
            coll.add(ids=[doc_id], documents=[content], metadatas=[meta])
            return {"stored": "private", "user": username, "id": doc_id}
        else:
            self.shared_experience.add(ids=[doc_id], documents=[content], metadatas=[meta])
            return {"stored": "shared", "user": username, "id": doc_id,
                    "available_to": "all_users"}

    def stats(self) -> dict:
        """Collection sizes."""
        s = {
            "shared_docs": self.shared_docs.count(),
            "shared_code": self.shared_code.count(),
            "shared_experience": self.shared_experience.count(),
            "shared_eda": self.shared_eda.count(),
        }
        # Count user collections
        all_colls = self.client.list_collections()
        user_colls = [c for c in all_colls if c.name.startswith("user_")]
        s["user_collections"] = len(user_colls)
        s["total"] = sum(v for k, v in s.items() if k != "user_collections")
        for uc in user_colls:
            s[uc.name] = uc.count()
            s["total"] += uc.count()
        return s

    def ingest_shared(self):
        """Ingest CBflow docs + code into shared collections."""
        from cbflow_knowledge import KnowledgeEngine
        local = KnowledgeEngine()
        # Copy from local KB to central shared
        for local_name, central_coll in [
            ('cbflow_docs', self.shared_docs),
            ('cbflow_code', self.shared_code),
            ('eda_guides', self.shared_eda),
            ('web_content', self.shared_eda),
        ]:
            local_coll = local.collections.get(local_name)
            if local_coll and local_coll.count() > 0:
                data = local_coll.get(include=['documents', 'metadatas'])
                if data['ids']:
                    central_coll.upsert(
                        ids=data['ids'],
                        documents=data['documents'],
                        metadatas=data['metadatas'],
                    )
        return self.stats()


# ═══════════════════════════════════════════════════════════════════════════════
# OLLAMA PROXY
# ═══════════════════════════════════════════════════════════════════════════════

def ollama_chat(messages: list, model: str = MODEL) -> str:
    """Forward chat to Ollama."""
    import requests
    try:
        resp = requests.post(
            f"{OLLAMA_URL}/api/chat",
            json={"model": model, "messages": messages, "stream": False,
                  "options": {"temperature": 0.1, "num_predict": 4096}},
            timeout=120,
        )
        return resp.json().get("message", {}).get("content", "")
    except Exception as e:
        return f"ERROR: {e}"


# ═══════════════════════════════════════════════════════════════════════════════
# HTTP SERVER
# ═══════════════════════════════════════════════════════════════════════════════

knowledge = None  # Initialized at startup
tracker = None    # Usage tracker

class SmartGenieHandler(http.server.BaseHTTPRequestHandler):

    def do_POST(self):
        body = self._read_body()
        path = urlparse(self.path).path

        try:
            if path == '/api/chat':
                result = self._handle_chat(body)
            elif path == '/api/knowledge/search':
                result = self._handle_search(body)
            elif path == '/api/knowledge/learn':
                result = self._handle_learn(body)
            elif path == '/api/knowledge/ingest':
                result = self._handle_ingest(body)
            else:
                self._json({"error": f"Unknown endpoint: {path}"}, 404)
                return
            self._json(result)
        except Exception as e:
            self._json({"error": str(e)}, 500)

    def do_GET(self):
        path = urlparse(self.path).path
        if path == '/api/status':
            self._json({
                "server": "CBflow SmartGenie",
                "model": MODEL,
                "ollama": OLLAMA_URL,
                "knowledge": knowledge.stats() if knowledge else {},
                "uptime": time.time(),
            })
        elif path == '/api/knowledge/stats':
            self._json(knowledge.stats() if knowledge else {})
        elif path == '/api/usage/stats':
            self._json(tracker.get_token_summary() if tracker else {})
        elif path == '/api/usage/leaderboard':
            self._json(tracker.get_leaderboard() if tracker else [])
        elif path.startswith('/api/usage/user/'):
            username = path.split('/')[-1]
            stats = tracker.get_user_stats(username) if tracker else []
            badge = tracker.get_maturity_badge(username) if tracker else {}
            self._json({"stats": stats, "maturity": badge})
        elif path == '/api/usage/daily':
            self._json(tracker.get_daily_stats() if tracker else [])
        elif path == '/api/usage/report':
            self._json({"report": tracker.format_stats_report() if tracker else "No data"})
        elif path == '/':
            self._html_dashboard()
        else:
            self._json({"error": "Not found"}, 404)

    def _handle_chat(self, body):
        messages = body.get("messages", [])
        user = body.get("user", "anonymous")
        model = body.get("model", MODEL)

        # Inject knowledge context
        query = messages[-1]["content"] if messages else ""
        if query and knowledge:
            context = knowledge.search(query, username=user, n_results=3)
            if context:
                kb_text = "\n".join(f"[{r['collection']}] {r['text'][:300]}" for r in context)
                # Prepend knowledge to system message
                if messages and messages[0]["role"] == "system":
                    messages[0]["content"] += f"\n\n## Relevant Knowledge:\n{kb_text}"
                else:
                    messages.insert(0, {"role": "system", "content": f"## Relevant Knowledge:\n{kb_text}"})

        response = ollama_chat(messages, model)

        # Track usage
        if tracker:
            tokens_in = sum(len(m.get("content", "")) // 4 for m in messages)
            tokens_out = len(response) // 4
            tracker.record(user, "chat", query[:100], tokens_in, tokens_out)

        return {"response": response, "user": user, "model": model}

    def _handle_search(self, body):
        query = body.get("query", "")
        user = body.get("user", "anonymous")
        n = body.get("n_results", 5)
        results = knowledge.search(query, username=user, n_results=n)
        return {"results": results, "count": len(results)}

    def _handle_learn(self, body):
        content = body.get("content", "")
        category = body.get("category", "general")
        user = body.get("user", "anonymous")
        private = body.get("private", False)
        if not content:
            return {"error": "content required"}
        result = knowledge.learn(content, category, user, private)
        if tracker:
            tracker.record(user, "learn_shared" if not private else "learn_private", content[:100])
        return result

    def _handle_ingest(self, body):
        return knowledge.ingest_shared()

    def _html_dashboard(self):
        stats = knowledge.stats() if knowledge else {}
        html = f"""<!DOCTYPE html>
<html><head><title>CBflow SmartGenie Server</title>
<style>body{{font-family:monospace;max-width:800px;margin:40px auto;padding:0 20px}}
h1{{color:#1565c0}}table{{border-collapse:collapse;width:100%}}
td,th{{border:1px solid #ddd;padding:8px;text-align:left}}
th{{background:#f5f5f5}}.ok{{color:green}}</style></head>
<body>
<h1>CBflow SmartGenie Server</h1>
<p>Model: <b>{MODEL}</b> | Ollama: {OLLAMA_URL}</p>
<h2>Knowledge Base</h2>
<table><tr><th>Collection</th><th>Chunks</th><th>Type</th></tr>
{''.join(f"<tr><td>{k}</td><td>{v}</td><td>{'shared' if 'shared' in k else 'private' if 'user' in k else 'meta'}</td></tr>" for k, v in stats.items())}
</table>
<h2>API Endpoints</h2>
<table>
<tr><td>POST /api/chat</td><td>Chat with AI (auto-injects knowledge)</td></tr>
<tr><td>POST /api/knowledge/search</td><td>Search knowledge base</td></tr>
<tr><td>POST /api/knowledge/learn</td><td>Record experience</td></tr>
<tr><td>GET /api/status</td><td>Server status</td></tr>
<tr><td>GET /api/knowledge/stats</td><td>Knowledge stats</td></tr>
</table>
<h2>Client Setup</h2>
<pre>export SMARTGENIE_SERVER=http://this-server:8091
cbflow smartgenie "your prompt here"</pre>
</body></html>"""
        self.send_response(200)
        self.send_header('Content-Type', 'text/html')
        self.end_headers()
        self.wfile.write(html.encode())

    def _read_body(self):
        length = int(self.headers.get('Content-Length', 0))
        return json.loads(self.rfile.read(length)) if length else {}

    def _json(self, data, code=200):
        body = json.dumps(data, default=str).encode()
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        user = "?"
        sys.stderr.write(f"[{datetime.now().strftime('%H:%M:%S')}] {args[0] if args else ''}\n")


# ═══════════════════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════════════════

def main():
    global knowledge, tracker

    port = DEFAULT_PORT
    host = '0.0.0.0'

    for i, arg in enumerate(sys.argv):
        if arg == '--port' and i + 1 < len(sys.argv): port = int(sys.argv[i + 1])
        if arg == '--host' and i + 1 < len(sys.argv): host = sys.argv[i + 1]

    # Initialize central knowledge
    print(f"\n  CBflow SmartGenie Server")
    print(f"  {'=' * 50}")
    print(f"  Initializing knowledge base...")
    knowledge = CentralKnowledge()
    stats = knowledge.stats()
    print(f"  Knowledge: {stats.get('total', 0)} chunks ({stats.get('user_collections', 0)} user collections)")

    if stats.get('total', 0) == 0:
        print(f"  First run — ingesting from local knowledge base...")
        knowledge.ingest_shared()
        stats = knowledge.stats()
        print(f"  Ingested: {stats.get('total', 0)} chunks")

    # Initialize usage tracker
    from usage_tracker import UsageTracker
    tracker = UsageTracker()
    print(f"  Usage tracker: {tracker.db_path}")
    print(f"  Model: {MODEL}")
    print(f"  Ollama: {OLLAMA_URL}")
    print(f"  {'=' * 50}")
    print(f"  Server: http://{host}:{port}")
    print(f"  Dashboard: http://{host}:{port}/")
    print(f"  {'=' * 50}")
    print(f"  Client setup:")
    print(f"    export SMARTGENIE_SERVER=http://<this-ip>:{port}")
    print(f"    cbflow smartgenie \"your prompt\"")
    print(f"  {'=' * 50}")
    print(f"  Press Ctrl+C to stop\n")

    server = http.server.HTTPServer((host, port), SmartGenieHandler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n  Server stopped.")
        server.shutdown()


if __name__ == '__main__':
    main()
