"""
CBflow Core — SQLite connection helper.

Single source of truth for `sqlite3.connect` with WAL + busy_timeout.
race_engine.py and race_dashboard.py both import from here to keep
PRAGMA / retry policy identical and avoid "readers block writers"
contention bugs.
"""

import logging
import sqlite3
import threading

_logger = logging.getLogger('cbflow.db')

# Set of db_paths already warned about WAL non-activation. Dashboard
# polls on a 5s interval and the engine executes 30+ connects per run;
# on an NFS/Lustre mount where WAL silently falls back, warning every
# call would flood the log at tens of lines per minute. Warn once per
# distinct DB path, process-lifetime.
_wal_warned_dbs = set()
_wal_warn_lock = threading.Lock()


def _warn_once(db_path: str, msg: str, *args) -> None:
    """Emit a WARNING if we haven't already warned about this db_path."""
    with _wal_warn_lock:
        _first_time = db_path not in _wal_warned_dbs
        if _first_time:
            _wal_warned_dbs.add(db_path)
    if _first_time:
        _logger.warning(msg, *args)


def sqlite_connect(db_path: str) -> sqlite3.Connection:
    """Open a sqlite3 connection with WAL + 30s busy_timeout.

    WAL mode: readers no longer block writers; multiple readers OK;
    exactly one writer at a time but writers don't block readers.
    busy_timeout=30s: wait up to 30s before raising. Covers the
    bursty-write pattern during job completion sweeps.

    `PRAGMA journal_mode=WAL` silently no-ops on some network
    filesystems (NFS/Lustre/SMB) and legacy sqlite builds — it returns
    a row whose value is the UNCHANGED mode instead of raising. We
    capture fetchone() and warn (once per DB) when the returned mode
    is not 'wal' so operators see the signal when the fix is
    inoperative on their mount, without flooding the log.
    """
    conn = sqlite3.connect(db_path, timeout=30.0)
    # busy_timeout PRAGMA — warn (once) on failure instead of silent pass
    # so a sqlite build that rejects the pragma is visible.
    try:
        conn.execute('PRAGMA busy_timeout=30000')
    except sqlite3.OperationalError as e:
        _warn_once(
            db_path,
            "sqlite_connect(%s): PRAGMA busy_timeout failed: %s; "
            "connections may deadlock under contention. "
            "This warning will not repeat for this DB.",
            db_path, e)
    # WAL PRAGMA + fetchone verification — WARN once if WAL doesn't
    # take effect, so operators on NFS/Lustre see the inoperative-fix
    # signal without log flooding.
    try:
        _row = conn.execute('PRAGMA journal_mode=WAL').fetchone()
        _mode = (_row[0] if _row else '').lower()
        if _mode != 'wal':
            _warn_once(
                db_path,
                "sqlite_connect(%s): journal_mode is %r, not 'wal' "
                "— readers may block during writer transactions. "
                "This warning will not repeat for this DB.",
                db_path, _mode)
    except sqlite3.OperationalError as e:
        _warn_once(
            db_path,
            "sqlite_connect(%s): PRAGMA journal_mode=WAL failed: %s; "
            "readers may block during writer transactions. "
            "This warning will not repeat for this DB.",
            db_path, e)
    return conn
