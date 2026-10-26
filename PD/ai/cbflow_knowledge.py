#!/usr/bin/env python3
"""
CBflow Knowledge Engine — Vector DB + Experience Memory for AI Agent.

Ingests documentation, command files, configs, EDA tool guides, and web content
into a ChromaDB vector database. Agent searches at runtime for relevant context.
Learns from experience (errors, fixes, patterns) and stores back.

Usage:
    # Ingest all CBflow docs + code
    python cbflow_knowledge.py ingest

    # Ingest a specific file or URL
    python cbflow_knowledge.py add --file /path/to/doc.pdf
    python cbflow_knowledge.py add --url "https://docs.synopsys.com/fc/..."

    # Search knowledge
    python cbflow_knowledge.py search "how to fix hold violations in CTS"

    # Record experience (called by agent automatically)
    python cbflow_knowledge.py learn --category "fix" --content "Hold violation fix: ..."

Requirements:
    pip install chromadb anthropic
"""

import hashlib
import json
import os
import re
import sys
from datetime import datetime
from pathlib import Path

# ═══════════════════════════════════════════════════════════════════════════════
# CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════════

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
CBFLOW_CORE = os.path.dirname(SCRIPT_DIR)
CBFLOW_ROOT = os.path.dirname(CBFLOW_CORE)
DB_DIR = os.path.join(SCRIPT_DIR, '.knowledge_db')

# Collections in ChromaDB
COLLECTIONS = {
    'cbflow_docs': 'CBflow documentation (user guides, architecture, reference)',
    'cbflow_code': 'CBflow command files, configs, handlers (TCL/Python)',
    'eda_guides': 'EDA tool user guides (FC, PT, Innovus, ICV, etc.)',
    'web_content': 'Web-scraped EDA documentation and tutorials',
    'experience': 'Agent learned knowledge (errors, fixes, patterns, decisions)',
}

CHUNK_SIZE = 1500  # chars per chunk
CHUNK_OVERLAP = 200


# ═══════════════════════════════════════════════════════════════════════════════
# KNOWLEDGE ENGINE
# ═══════════════════════════════════════════════════════════════════════════════

class KnowledgeEngine:
    """Vector DB knowledge store using ChromaDB."""

    def __init__(self):
        try:
            import chromadb
            self.client = chromadb.PersistentClient(path=DB_DIR)
        except ImportError:
            print("ERROR: pip install chromadb")
            sys.exit(1)
        self.collections = {}
        for name, desc in COLLECTIONS.items():
            self.collections[name] = self.client.get_or_create_collection(
                name=name,
                metadata={"description": desc},
            )

    def _chunk_text(self, text: str, chunk_size=CHUNK_SIZE, overlap=CHUNK_OVERLAP) -> list:
        """Split text into overlapping chunks."""
        chunks = []
        lines = text.split('\n')
        current = []
        current_len = 0
        for line in lines:
            current.append(line)
            current_len += len(line) + 1
            if current_len >= chunk_size:
                chunks.append('\n'.join(current))
                # Keep overlap
                overlap_lines = []
                overlap_len = 0
                for l in reversed(current):
                    overlap_lines.insert(0, l)
                    overlap_len += len(l) + 1
                    if overlap_len >= overlap:
                        break
                current = overlap_lines
                current_len = overlap_len
        if current:
            chunks.append('\n'.join(current))
        return chunks

    def _doc_id(self, source: str, chunk_idx: int) -> str:
        """Generate deterministic document ID."""
        h = hashlib.md5(f"{source}:{chunk_idx}".encode()).hexdigest()[:12]
        return f"{h}_{chunk_idx}"

    # ── INGEST METHODS ──────────────────────────────────────────────────────

    def ingest_file(self, filepath: str, collection_name: str, metadata: dict = None):
        """Ingest a single file into a collection."""
        filepath = os.path.abspath(filepath)
        if not os.path.exists(filepath):
            print(f"  SKIP (not found): {filepath}")
            return 0

        ext = os.path.splitext(filepath)[1].lower()
        try:
            if ext == '.pdf':
                text = self._read_pdf(filepath)
            elif ext in ('.html', '.htm'):
                text = self._read_html(filepath)
            else:
                with open(filepath, errors='ignore') as f:
                    text = f.read()
        except Exception as e:
            print(f"  SKIP (read error): {filepath}: {e}")
            return 0

        if not text.strip():
            return 0

        chunks = self._chunk_text(text)
        collection = self.collections[collection_name]

        ids = []
        documents = []
        metadatas = []
        for i, chunk in enumerate(chunks):
            doc_id = self._doc_id(filepath, i)
            meta = {
                "source": filepath,
                "filename": os.path.basename(filepath),
                "chunk": i,
                "total_chunks": len(chunks),
                "ingested_at": datetime.now().isoformat(),
            }
            if metadata:
                meta.update(metadata)
            ids.append(doc_id)
            documents.append(chunk)
            metadatas.append(meta)

        if ids:
            collection.upsert(ids=ids, documents=documents, metadatas=metadatas)

        return len(chunks)

    def ingest_url(self, url: str, collection_name: str = 'web_content'):
        """Fetch and ingest a web page."""
        try:
            import urllib.request
            req = urllib.request.Request(url, headers={'User-Agent': 'CBflow-Agent/1.0'})
            with urllib.request.urlopen(req, timeout=30) as resp:
                html = resp.read().decode('utf-8', errors='ignore')
            text = self._html_to_text(html)
            if not text.strip():
                return 0
            # Write to temp file and ingest
            import tempfile
            with tempfile.NamedTemporaryFile(mode='w', suffix='.txt', delete=False) as f:
                f.write(text)
                tmp = f.name
            count = self.ingest_file(tmp, collection_name, {"url": url, "type": "web"})
            os.unlink(tmp)
            return count
        except Exception as e:
            print(f"  SKIP (fetch error): {url}: {e}")
            return 0

    def ingest_cbflow_docs(self):
        """Ingest all CBflow documentation."""
        print("\n  Ingesting CBflow documentation...")
        docs_dir = os.path.join(CBFLOW_ROOT, 'PD', 'docs')
        feature_doc = os.path.join(CBFLOW_ROOT, 'docs', 'CBflow_v2.0.0_Feature_Document.md')
        count = 0

        # All markdown docs
        for md in Path(docs_dir).rglob('*.md'):
            n = self.ingest_file(str(md), 'cbflow_docs', {"type": "documentation"})
            if n: print(f"    {md.relative_to(CBFLOW_ROOT)}: {n} chunks")
            count += n

        # Feature document
        if os.path.exists(feature_doc):
            n = self.ingest_file(feature_doc, 'cbflow_docs', {"type": "feature_doc"})
            if n: print(f"    docs/Feature_Document: {n} chunks")
            count += n

        # CLAUDE.md
        claude_md = os.path.join(CBFLOW_ROOT, 'CLAUDE.md')
        if os.path.exists(claude_md):
            n = self.ingest_file(claude_md, 'cbflow_docs', {"type": "agent_context"})
            count += n

        print(f"  Total docs: {count} chunks")
        return count

    def ingest_cbflow_code(self):
        """Ingest CBflow command files, configs, and handlers."""
        print("\n  Ingesting CBflow code...")
        count = 0

        # Config files
        config_dir = os.path.join(CBFLOW_CORE, 'config', 'flow', 'v1.0.0')
        for tcl in Path(config_dir).rglob('*.tcl'):
            n = self.ingest_file(str(tcl), 'cbflow_code', {"type": "config"})
            if n: count += n

        # Command files (representative *_fc.tcl from each flow)
        cmds_dir = os.path.join(CBFLOW_CORE, 'cmds')
        for fc in Path(cmds_dir).rglob('*_fc.tcl'):
            n = self.ingest_file(str(fc), 'cbflow_code', {"type": "cmd_file"})
            count += n

        # Subnode handlers (representative)
        for handler in Path(cmds_dir).rglob('*_subnode_handler.tcl'):
            n = self.ingest_file(str(handler), 'cbflow_code', {"type": "handler"})
            count += n

        # Python commands
        py_dir = os.path.join(CBFLOW_CORE, 'utils', 'commands')
        for py in Path(py_dir).glob('*.py'):
            n = self.ingest_file(str(py), 'cbflow_code', {"type": "python_cmd"})
            count += n

        # Utilities
        util_dir = os.path.join(CBFLOW_CORE, 'utils', 'utilities', 'v1.0.0')
        for tcl in Path(util_dir).glob('*.tcl'):
            n = self.ingest_file(str(tcl), 'cbflow_code', {"type": "utility"})
            count += n

        print(f"  Total code: {count} chunks")
        return count

    def ingest_eda_guides(self, guides_dir: str = None):
        """Ingest EDA tool user guides (PDF/HTML/TXT)."""
        if not guides_dir:
            guides_dir = os.path.join(SCRIPT_DIR, 'eda_guides')
        if not os.path.isdir(guides_dir):
            print(f"\n  No EDA guides dir found at {guides_dir}")
            print(f"  Create it and add PDF/HTML tool guides:")
            print(f"    mkdir -p {guides_dir}")
            print(f"    cp /path/to/fc_user_guide.pdf {guides_dir}/")
            return 0

        print(f"\n  Ingesting EDA guides from {guides_dir}...")
        count = 0
        for f in Path(guides_dir).rglob('*'):
            if f.suffix.lower() in ('.pdf', '.html', '.htm', '.txt', '.md', '.rst'):
                n = self.ingest_file(str(f), 'eda_guides', {"type": "eda_guide", "tool": f.stem})
                if n: print(f"    {f.name}: {n} chunks")
                count += n
        print(f"  Total EDA guides: {count} chunks")
        return count

    def ingest_urls(self, urls: list):
        """Ingest web pages."""
        print(f"\n  Ingesting {len(urls)} URLs...")
        count = 0
        for url in urls:
            n = self.ingest_url(url)
            if n: print(f"    {url[:60]}...: {n} chunks")
            count += n
        print(f"  Total web: {count} chunks")
        return count

    # ── SEARCH ──────────────────────────────────────────────────────────────

    def search(self, query: str, n_results: int = 10, collections: list = None) -> list:
        """Search across collections. Returns list of {text, source, score, collection}."""
        if collections is None:
            collections = list(COLLECTIONS.keys())

        all_results = []
        for coll_name in collections:
            coll = self.collections.get(coll_name)
            if not coll:
                continue
            try:
                results = coll.query(query_texts=[query], n_results=min(n_results, 5))
                if results and results['documents']:
                    for i, doc in enumerate(results['documents'][0]):
                        meta = results['metadatas'][0][i] if results['metadatas'] else {}
                        dist = results['distances'][0][i] if results['distances'] else 0
                        all_results.append({
                            'text': doc,
                            'source': meta.get('source', meta.get('url', 'unknown')),
                            'filename': meta.get('filename', ''),
                            'collection': coll_name,
                            'distance': dist,
                            'type': meta.get('type', ''),
                        })
            except Exception:
                continue

        # Sort by distance (lower = more relevant)
        all_results.sort(key=lambda x: x['distance'])
        return all_results[:n_results]

    # ── EXPERIENCE LEARNING ─────────────────────────────────────────────────

    def learn(self, content: str, category: str = 'general', context: dict = None):
        """Record an experience for future retrieval."""
        meta = {
            "type": "experience",
            "category": category,
            "learned_at": datetime.now().isoformat(),
        }
        if context:
            meta.update(context)

        doc_id = self._doc_id(f"experience:{datetime.now().isoformat()}", 0)
        self.collections['experience'].add(
            ids=[doc_id],
            documents=[content],
            metadatas=[meta],
        )
        return doc_id

    def get_experience(self, query: str, n_results: int = 5) -> list:
        """Search only the experience collection."""
        return self.search(query, n_results=n_results, collections=['experience'])

    # ── STATS ───────────────────────────────────────────────────────────────

    def stats(self) -> dict:
        """Return collection sizes."""
        return {name: coll.count() for name, coll in self.collections.items()}

    # ── HELPERS ──────────────────────────────────────────────────────────────

    def _read_pdf(self, filepath: str) -> str:
        """Extract text from PDF."""
        try:
            import subprocess
            # Try pdftotext first (most reliable)
            result = subprocess.run(['pdftotext', filepath, '-'], capture_output=True, text=True, timeout=60)
            if result.returncode == 0 and result.stdout.strip():
                return result.stdout
        except FileNotFoundError:
            pass
        # Fallback: basic read
        with open(filepath, 'rb') as f:
            raw = f.read()
        # Extract text-like content from PDF binary
        text_parts = re.findall(rb'\((.*?)\)', raw)
        return '\n'.join(p.decode('utf-8', errors='ignore') for p in text_parts)

    def _read_html(self, filepath: str) -> str:
        """Extract text from HTML."""
        with open(filepath, errors='ignore') as f:
            html = f.read()
        return self._html_to_text(html)

    def _html_to_text(self, html: str) -> str:
        """Strip HTML tags and extract text."""
        # Remove script/style
        html = re.sub(r'<script[^>]*>.*?</script>', '', html, flags=re.DOTALL | re.IGNORECASE)
        html = re.sub(r'<style[^>]*>.*?</style>', '', html, flags=re.DOTALL | re.IGNORECASE)
        # Remove tags
        text = re.sub(r'<[^>]+>', ' ', html)
        # Clean whitespace
        text = re.sub(r'\s+', ' ', text)
        return text.strip()


# ═══════════════════════════════════════════════════════════════════════════════
# CLI
# ═══════════════════════════════════════════════════════════════════════════════

DEFAULT_URLS = [
    # Synopsys Fusion Compiler
    "https://www.synopsys.com/implementation-and-signoff/physical-implementation/fusion-compiler.html",
    # Synopsys PrimeTime
    "https://www.synopsys.com/implementation-and-signoff/signoff/primetime.html",
    # Synopsys IC Validator
    "https://www.synopsys.com/implementation-and-signoff/signoff/ic-validator.html",
    # Cadence Innovus
    "https://www.cadence.com/en_US/home/tools/digital-design-and-signoff/soc-implementation-and-floorplanning/innovus-implementation-system.html",
]


def main():
    if len(sys.argv) < 2:
        print("CBflow Knowledge Engine")
        print("")
        print("Commands:")
        print("  ingest                 Ingest all CBflow docs + code")
        print("  ingest --all           Ingest docs + code + EDA guides + web")
        print("  add --file <path>      Add a specific file")
        print("  add --url <url>        Add a web page")
        print("  search <query>         Search knowledge base")
        print("  learn --category <c> --content <text>  Record experience")
        print("  stats                  Show collection sizes")
        print("")
        print("Setup:")
        print("  pip install chromadb")
        print("  mkdir -p PD/ai/eda_guides  # Add PDF/HTML tool guides here")
        return

    engine = KnowledgeEngine()
    cmd = sys.argv[1]

    if cmd == 'ingest':
        total = 0
        total += engine.ingest_cbflow_docs()
        total += engine.ingest_cbflow_code()
        if '--all' in sys.argv:
            total += engine.ingest_eda_guides()
            total += engine.ingest_urls(DEFAULT_URLS)
        print(f"\n  Total ingested: {total} chunks")
        print(f"  DB location: {DB_DIR}")
        print(f"\n  Stats: {json.dumps(engine.stats(), indent=2)}")

    elif cmd == 'add':
        if '--file' in sys.argv:
            idx = sys.argv.index('--file') + 1
            filepath = sys.argv[idx]
            coll = 'eda_guides' if any(x in filepath.lower() for x in ['guide', 'manual', 'eda']) else 'cbflow_docs'
            n = engine.ingest_file(filepath, coll)
            print(f"  Added {n} chunks from {filepath}")
        elif '--url' in sys.argv:
            idx = sys.argv.index('--url') + 1
            url = sys.argv[idx]
            n = engine.ingest_url(url)
            print(f"  Added {n} chunks from {url}")

    elif cmd == 'search':
        query = ' '.join(sys.argv[2:])
        results = engine.search(query)
        print(f"\n  Search: \"{query}\"")
        print(f"  Results: {len(results)}\n")
        for i, r in enumerate(results):
            print(f"  [{i+1}] ({r['collection']}) {r['filename'] or r['source'][:50]}")
            print(f"      {r['text'][:200]}...")
            print()

    elif cmd == 'learn':
        category = 'general'
        content = ''
        if '--category' in sys.argv:
            category = sys.argv[sys.argv.index('--category') + 1]
        if '--content' in sys.argv:
            content = ' '.join(sys.argv[sys.argv.index('--content') + 1:])
        if content:
            doc_id = engine.learn(content, category)
            print(f"  Learned: {doc_id} (category: {category})")
        else:
            print("  ERROR: --content required")

    elif cmd == 'stats':
        stats = engine.stats()
        print("\n  Knowledge Base Stats:")
        for name, count in stats.items():
            print(f"    {name:<20} {count:>6} chunks")
        print(f"    {'TOTAL':<20} {sum(stats.values()):>6} chunks")
        print(f"\n  DB: {DB_DIR}")


if __name__ == '__main__':
    main()
