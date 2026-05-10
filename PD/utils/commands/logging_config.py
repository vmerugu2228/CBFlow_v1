#!/usr/bin/env python3
"""
CBFlow Unified Logging Configuration

Provides consistent logging across all CBFlow Python modules.
Format: [TIMESTAMP] [LEVEL] [COMPONENT] message
"""

import logging
import logging.handlers
import os
import json
from datetime import datetime
from pathlib import Path

# Unified format
UNIFIED_FORMAT = '[%(asctime)s] [%(levelname)s] [%(name)s] %(message)s'
UNIFIED_DATE_FORMAT = '%Y-%m-%d %H:%M:%S'
SIMPLE_FORMAT = '[%(levelname)s] %(message)s'

# JSON format for structured logging
class JsonFormatter(logging.Formatter):
    def format(self, record):
        log_entry = {
            'timestamp': datetime.fromtimestamp(record.created).strftime(UNIFIED_DATE_FORMAT),
            'level': record.levelname,
            'component': record.name,
            'message': record.getMessage(),
        }
        if record.exc_info:
            log_entry['exception'] = self.formatException(record.exc_info)
        return json.dumps(log_entry)


def configure_logging(component: str, level: str = 'INFO', log_dir: str = None, json_output: bool = False):
    """
    Configure logging for a CBFlow component.

    Args:
        component: Component name (e.g., 'run_cmd', 'workspace_cmd')
        level: Log level ('DEBUG', 'INFO', 'WARNING', 'ERROR')
        log_dir: Optional directory for file logging
        json_output: If True, use JSON format for structured logging
    """
    # Check environment for overrides
    env_level = os.environ.get('CBFLOW_LOG_LEVEL', level).upper()
    env_json = os.environ.get('CBFLOW_LOG_JSON', '').lower() in ('1', 'true', 'yes')
    env_log_dir = os.environ.get('CBFLOW_LOG_DIR', log_dir)
    use_json = json_output or env_json

    # Get the root logger for cbflow namespace
    logger = logging.getLogger(component)
    logger.setLevel(getattr(logging, env_level, logging.INFO))

    # Avoid duplicate handlers
    if logger.handlers:
        return logger

    # Console handler
    console_handler = logging.StreamHandler()
    console_handler.setLevel(getattr(logging, env_level, logging.INFO))

    if use_json:
        console_handler.setFormatter(JsonFormatter())
    else:
        console_handler.setFormatter(logging.Formatter(SIMPLE_FORMAT))

    logger.addHandler(console_handler)

    # File handler (if log directory specified)
    if env_log_dir:
        add_file_handler(logger, env_log_dir, f'{component}.log', use_json)

    return logger


def get_logger(component: str) -> logging.Logger:
    """
    Get a configured logger for a CBFlow component.
    If not already configured, configures with defaults.

    Args:
        component: Component name
    Returns:
        Configured logger instance
    """
    logger = logging.getLogger(component)
    if not logger.handlers:
        configure_logging(component)
    return logger


def add_file_handler(logger: logging.Logger, log_dir: str, filename: str, json_output: bool = False):
    """
    Add a rotating file handler to a logger.

    Args:
        logger: Logger instance
        log_dir: Directory for log files
        filename: Log filename
        json_output: Use JSON format
    """
    log_path = Path(log_dir)
    log_path.mkdir(parents=True, exist_ok=True)

    file_handler = logging.handlers.RotatingFileHandler(
        log_path / filename,
        maxBytes=10 * 1024 * 1024,  # 10MB
        backupCount=5
    )
    file_handler.setLevel(logging.DEBUG)

    if json_output:
        file_handler.setFormatter(JsonFormatter())
    else:
        file_handler.setFormatter(logging.Formatter(UNIFIED_FORMAT, datefmt=UNIFIED_DATE_FORMAT))

    logger.addHandler(file_handler)
