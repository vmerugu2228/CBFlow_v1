#!/usr/bin/env python3
"""
CBFlow Web Dashboard

Lightweight web dashboard for project/run/release visualization.
Uses standard library only (no FastAPI/Flask dependency) for portability.
"""

import http.server
import json
import os
import sys
import threading
from pathlib import Path
from urllib.parse import urlparse, parse_qs

# Add commands dir to path for imports
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'commands'))


def get_cbflow_core_dir() -> str:
    if 'CBFLOW_CORE_DIR' in os.environ:
        return os.environ['CBFLOW_CORE_DIR']
    return os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


class DataProvider:
    """Provides data from CBflow configuration and run files."""

    def __init__(self):
        self.core_dir = Path(get_cbflow_core_dir())

    def get_projects(self) -> dict:
        projects_file = self.core_dir / 'config' / 'master_projects.json'
        if projects_file.exists():
            with open(projects_file, 'r') as f:
                return json.load(f)
        return {'projects': {}}

    def get_releases(self) -> list:
        releases_dir = self.core_dir / 'releases'
        releases = []
        if releases_dir.exists():
            for d in sorted(releases_dir.iterdir(), reverse=True):
                if d.is_dir() and d.name.startswith('v'):
                    manifest_file = d / 'MANIFEST.json'
                    info = {'version': d.name}
                    if manifest_file.exists():
                        with open(manifest_file, 'r') as f:
                            manifest = json.load(f)
                        info['created'] = manifest.get('created', '')
                        info['description'] = manifest.get('description', '')
                        info['components'] = len(manifest.get('components', {}))
                    releases.append(info)
            # Check current symlink
            current = releases_dir / 'current'
            if current.is_symlink():
                for r in releases:
                    if r['version'] == os.readlink(str(current)):
                        r['current'] = True
        return releases

    def get_runs(self, search_dirs: list = None) -> list:
        runs = []
        if not search_dirs:
            # Look in common workarea locations
            search_dirs = [
                self.core_dir.parent / 'workarea',
                self.core_dir.parent / 'workarea_test',
            ]

        for search_dir in search_dirs:
            search_path = Path(search_dir)
            if not search_path.exists():
                continue
            for d in sorted(search_path.iterdir(), reverse=True):
                if d.is_dir() and '_run_' in d.name:
                    run_info = self._parse_run_dir(d)
                    if run_info:
                        runs.append(run_info)
        return runs

    def _parse_run_dir(self, run_dir: Path) -> dict:
        info = {'name': run_dir.name, 'path': str(run_dir)}

        # Parse environment
        env_file = run_dir / '.run.cbflow.env'
        if env_file.exists():
            with open(env_file, 'r') as f:
                for line in f:
                    line = line.strip()
                    if line.startswith('export ') and '=' in line:
                        kv = line[7:]
                        k, v = kv.split('=', 1)
                        v = v.strip('"').strip("'")
                        if k == 'CBFLOW_FLOW_TYPE': info['flow_type'] = v
                        elif k == 'CBFLOW_DESIGN_NAME': info['design_name'] = v
                        elif k == 'CBFLOW_PROJECT_PHASE': info['phase'] = v
                        elif k == 'CBFLOW_RELEASE_VERSION': info['release'] = v

        # Parse stamps
        stamps_dir = run_dir / '.stamps'
        if stamps_dir.exists():
            stamps = sorted([s.stem for s in stamps_dir.glob('*.stamp')])
            info['completed_stages'] = stamps
            info['stage_count'] = len(stamps)

        # Check for Makefile
        info['has_makefile'] = (run_dir / 'Makefile').exists()

        return info

    def get_metrics_summary(self) -> dict:
        try:
            from metrics_cmd import MetricsDB
            db = MetricsDB()
            stats = db.query_stage_stats()
            rates = db.query_success_rate()
            recent = db.query_run_summaries(limit=10)
            db.close()
            return {'stage_stats': stats, 'success_rates': rates, 'recent_runs': recent}
        except Exception:
            return {'stage_stats': [], 'success_rates': {}, 'recent_runs': []}


class DashboardHandler(http.server.SimpleHTTPRequestHandler):
    """HTTP request handler for the dashboard."""

    data_provider = DataProvider()
    static_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'static')

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path

        # API routes
        if path.startswith('/api/'):
            self._handle_api(path, parse_qs(parsed.query))
            return

        # Static files
        if path == '/' or path == '/index.html':
            self._serve_file('index.html', 'text/html')
        elif path == '/dashboard.js':
            self._serve_file('dashboard.js', 'application/javascript')
        elif path == '/dashboard.css':
            self._serve_file('dashboard.css', 'text/css')
        else:
            self.send_error(404)

    def _handle_api(self, path: str, params: dict):
        try:
            if path == '/api/projects':
                data = self.data_provider.get_projects()
            elif path == '/api/releases':
                data = self.data_provider.get_releases()
            elif path == '/api/runs':
                data = self.data_provider.get_runs()
            elif path == '/api/metrics':
                data = self.data_provider.get_metrics_summary()
            elif path == '/api/status':
                data = {
                    'status': 'running',
                    'core_dir': str(self.data_provider.core_dir),
                    'projects': len(self.data_provider.get_projects().get('projects', {})),
                    'releases': len(self.data_provider.get_releases()),
                    'runs': len(self.data_provider.get_runs()),
                }
            else:
                self.send_error(404)
                return

            self._send_json(data)
        except Exception as e:
            self._send_json({'error': str(e)}, status=500)

    def _send_json(self, data: dict, status: int = 200):
        response = json.dumps(data, indent=2, default=str).encode('utf-8')
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', len(response))
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(response)

    def _serve_file(self, filename: str, content_type: str):
        filepath = os.path.join(self.static_dir, filename)
        if os.path.exists(filepath):
            with open(filepath, 'rb') as f:
                content = f.read()
            self.send_response(200)
            self.send_header('Content-Type', content_type)
            self.send_header('Content-Length', len(content))
            self.end_headers()
            self.wfile.write(content)
        else:
            self.send_error(404)

    def log_message(self, format, *args):
        pass  # Suppress default logging


def start_server(port: int = 8080):
    """Start the dashboard server."""
    server = http.server.HTTPServer(('0.0.0.0', port), DashboardHandler)
    print(f"CBFlow Dashboard running at http://localhost:{port}")
    print(f"Press Ctrl+C to stop")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nDashboard stopped")
        server.shutdown()


if __name__ == '__main__':
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
    start_server(port)
