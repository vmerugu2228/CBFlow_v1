"""Sandbox helpers for e2e runs.

Each e2e flow gets:
  - A temp dir for the rewritten uc_*.tcl fixture
  - A unique run_name so the resulting run directory under
    project(workarea_path)/<design>/ does not clobber any existing run
  - Cleanup of both the temp dir and the run directory on success
"""

import os
import shutil
import tempfile


class Sandbox:
    """Holds bookkeeping for a single e2e flow execution."""

    def __init__(self, flow, repo_root):
        self.flow = flow
        self.repo_root = repo_root
        self.tmp_dir = tempfile.mkdtemp(prefix=f'cbflow-test-{flow.lower()}-')
        self.run_dir = None          # set after workspace create succeeds
        self.run_name = None
        self.kept = False

    def set_run(self, run_dir, run_name):
        self.run_dir = run_dir
        self.run_name = run_name

    def cleanup(self, keep=False):
        if keep:
            self.kept = True
            return
        if self.tmp_dir and os.path.isdir(self.tmp_dir):
            shutil.rmtree(self.tmp_dir, ignore_errors=True)
        if self.run_dir and os.path.isdir(self.run_dir):
            shutil.rmtree(self.run_dir, ignore_errors=True)

    def __repr__(self):
        return f'<Sandbox flow={self.flow} tmp={self.tmp_dir} run={self.run_dir}>'
