#!/usr/bin/env python3
"""
CBflow Dispatcher — cbflow-engine is the only execution backend.
No Make, no fallback. Engine builds DAG from node_configs, executes via handlers.
"""

import os
import logging

logger = logging.getLogger('cbflow.dispatcher')


class EngineDispatcher:
    """cbflow-engine dispatcher — Python-native DAG executor with SQLite tracking."""

    def __init__(self):
        self.engine = None
        self.run_dir = None
        self.flow_type = None

    def setup(self, run_dir: str, flow_type: str, env_vars: dict) -> bool:
        self.run_dir = run_dir
        self.flow_type = flow_type
        from cbflow_engine import CbflowEngine
        self.engine = CbflowEngine(run_dir, flow_type, env_vars)
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
