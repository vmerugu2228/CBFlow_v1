#!/usr/bin/env python3
"""
CBflow Dispatcher — RACE is the only execution backend.
No Make, no fallback. Engine builds DAG from node_configs, executes via handlers.
"""

import os

# Post cbflow_global utils-refactor: shared Python packages (core.*,
# logging_config, cbflow_config, …) live under global/utils/, not PD/utils/.
# Add both to sys.path so inner `from core.* import …` calls resolve even
# when the invoker didn't preset env.
import sys as _bootstrap_sys
_this = os.path.dirname(os.path.abspath(__file__))
_pd_utils = os.path.dirname(_this)
_umbrella = os.path.dirname(os.path.dirname(_pd_utils))
_global_utils = os.path.join(_umbrella, 'global', 'utils')
_global_cmds = os.path.join(_global_utils, 'commands')
if os.path.isdir(_global_cmds) and _global_cmds not in _bootstrap_sys.path:
    _bootstrap_sys.path.insert(0, _global_cmds)
if os.path.isdir(_global_utils) and _global_utils not in _bootstrap_sys.path:
    _bootstrap_sys.path.insert(0, _global_utils)
if _pd_utils not in _bootstrap_sys.path:
    _bootstrap_sys.path.insert(0, _pd_utils)

import logging

logger = logging.getLogger('cbflow.dispatcher')


class EngineDispatcher:
    """RACE dispatcher — Python-native DAG executor with SQLite tracking."""

    def __init__(self):
        self.engine = None
        self.run_dir = None
        self.flow_type = None

    def setup(self, run_dir: str, flow_type: str, env_vars: dict) -> bool:
        self.run_dir = run_dir
        self.flow_type = flow_type
        from race_engine import RaceEngine
        self.engine = RaceEngine(run_dir, flow_type, env_vars)
        return self.engine.initialize()

    def run_target(self, target: str, env_vars: dict = None) -> int:
        if not self.engine:
            logger.error("Engine not initialized")
            return 1
        return self.engine.execute(target, env_vars=env_vars)

    def retrace(self, from_stage: str = None, stages: list = None) -> bool:
        if not self.engine:
            return False
        return self.engine.retrace(from_stage=from_stage, stages=stages)

    def get_name(self) -> str:
        return 'engine'


def get_dispatcher(run_dir: str = None) -> EngineDispatcher:
    """Return the engine dispatcher."""
    return EngineDispatcher()
