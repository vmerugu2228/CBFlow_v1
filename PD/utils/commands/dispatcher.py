#!/usr/bin/env python3
"""
CBflow Dispatcher Abstraction — Decouples run_cmd.py from execution backend.
Supports Make (existing) and cbflow-engine (new DAG executor).
"""

import os
import re
import subprocess
import logging
from abc import ABC, abstractmethod

logger = logging.getLogger('cbflow.dispatcher')


class DispatcherBase(ABC):
    """Abstract base for flow dispatchers."""

    @abstractmethod
    def setup(self, run_dir: str, flow_type: str, env_vars: dict) -> bool:
        """Initialize dispatcher for a run. Returns True on success."""

    @abstractmethod
    def run_target(self, target: str, env_vars: dict = None,
                   use_lsf: bool = False, lsf_queue: str = None) -> int:
        """Execute a target (stage name or 'all'). Returns exit code."""

    @abstractmethod
    def retrace(self, from_stage: str = None, stages: list = None) -> bool:
        """Invalidate stages to force re-execution. Returns True on success."""

    @abstractmethod
    def is_available(self) -> bool:
        """Check if this dispatcher's backend is available."""

    @abstractmethod
    def get_name(self) -> str:
        """Return dispatcher name."""


class MakeDispatcher(DispatcherBase):
    """GNU Make dispatcher — wraps existing Makefile-based execution."""

    def __init__(self):
        self.run_dir = None
        self.flow_type = None

    def setup(self, run_dir: str, flow_type: str, env_vars: dict) -> bool:
        self.run_dir = run_dir
        self.flow_type = flow_type
        # Check Makefile exists
        if not os.path.exists(os.path.join(run_dir, 'Makefile')):
            logger.warning("No Makefile found — run 'cbflow run gen-makefile' first")
            return False
        return True

    def run_target(self, target: str, env_vars: dict = None,
                   use_lsf: bool = False, lsf_queue: str = None) -> int:
        run_env = os.environ.copy()
        if env_vars:
            run_env.update(env_vars)

        if use_lsf:
            run_env['CBFLOW_USE_LSF'] = '1'
            if lsf_queue:
                run_env['CBFLOW_LSF_QUEUE'] = lsf_queue

        cmd = ['make', target]
        try:
            result = subprocess.run(cmd, env=run_env, cwd=self.run_dir)
            return result.returncode
        except FileNotFoundError:
            logger.error("make command not found")
            return 1

    def retrace(self, from_stage: str = None, stages: list = None) -> bool:
        stamps_dir = os.path.join(self.run_dir, '.stamps')
        if not os.path.isdir(stamps_dir):
            return True

        if from_stage:
            # Read flow order from node config to find downstream stages
            all_stamps = sorted(os.listdir(stamps_dir))
            found = False
            for stamp in all_stamps:
                if stamp.startswith(from_stage):
                    found = True
                if found and stamp.endswith('.stamp'):
                    os.remove(os.path.join(stamps_dir, stamp))
        elif stages:
            for stage in stages:
                for stamp in os.listdir(stamps_dir):
                    if stamp.startswith(stage) and stamp.endswith('.stamp'):
                        os.remove(os.path.join(stamps_dir, stamp))
        else:
            # Full retrace
            for stamp in os.listdir(stamps_dir):
                if stamp.endswith('.stamp'):
                    os.remove(os.path.join(stamps_dir, stamp))
        return True

    def is_available(self) -> bool:
        try:
            result = subprocess.run(['make', '--version'], capture_output=True, timeout=5)
            return result.returncode == 0
        except Exception:
            return False

    def get_name(self) -> str:
        return 'make'


class EngineDispatcher(DispatcherBase):
    """cbflow-engine dispatcher — Python-native DAG executor with SQLite tracking."""

    def __init__(self):
        self.engine = None
        self.run_dir = None
        self.flow_type = None

    def setup(self, run_dir: str, flow_type: str, env_vars: dict) -> bool:
        self.run_dir = run_dir
        self.flow_type = flow_type
        try:
            from cbflow_engine import CbflowEngine
            self.engine = CbflowEngine(run_dir, flow_type, env_vars)
            return self.engine.initialize()
        except ImportError:
            logger.error("cbflow_engine module not found")
            return False

    def run_target(self, target: str, env_vars: dict = None,
                   use_lsf: bool = False, lsf_queue: str = None) -> int:
        if not self.engine:
            logger.error("Engine not initialized")
            return 1
        return self.engine.execute(target, env_vars=env_vars,
                                   use_lsf=use_lsf, lsf_queue=lsf_queue)

    def retrace(self, from_stage: str = None, stages: list = None) -> bool:
        if not self.engine:
            return False
        return self.engine.retrace(from_stage=from_stage, stages=stages)

    def is_available(self) -> bool:
        try:
            from cbflow_engine import CbflowEngine
            return True
        except ImportError:
            return False

    def get_name(self) -> str:
        return 'engine'


def get_dispatcher(run_dir: str = None) -> DispatcherBase:
    """Factory: return dispatcher based on flow(dispatcher) config.

    Priority:
      1. CBFLOW_DISPATCHER env var
      2. flow(dispatcher) in flow_config.tcl (via .run.cbflow.tcl)
      3. Default: 'make'
    """
    if run_dir is None:
        run_dir = os.getcwd()

    dispatcher_type = os.environ.get('CBFLOW_DISPATCHER', '')

    if not dispatcher_type:
        # Read from .run.cbflow.tcl
        env_file = os.path.join(run_dir, '.run.cbflow.tcl')
        if os.path.exists(env_file):
            try:
                with open(env_file) as f:
                    for line in f:
                        m = re.match(r'set\s+flow\(dispatcher\)\s+"(\w+)"', line.strip())
                        if m:
                            dispatcher_type = m.group(1)
                            break
            except Exception:
                pass

    if not dispatcher_type:
        dispatcher_type = 'make'

    if dispatcher_type == 'engine':
        d = EngineDispatcher()
        if d.is_available():
            return d
        else:
            logger.warning("cbflow-engine not available, falling back to Make")
            return MakeDispatcher()
    else:
        return MakeDispatcher()
