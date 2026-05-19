#!/usr/bin/env python3
"""
CBflow SmartGenie — Usage Tracker & Maturity Engine.

Tracks per-user: tokens used, commands run, success/fail rate,
knowledge contributions, and computes maturity level.

Maturity Levels:
    Beginner    — Asks basic questions, runs simple commands
    Intermediate — Runs flows, creates branches, debugs issues
    Advanced    — Optimizes configs, runs regressions, contributes fixes
    Expert      — Teaches others, contributes patterns, drives releases
    Master      — Top contributor, highest success rate, mentors team

Storage: SQLite database on the server (usage_stats.db)
"""

import json
import os
import sqlite3
import time
from datetime import datetime, timedelta

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DB_PATH = os.path.join(SCRIPT_DIR, 'usage_stats.db')

# ═══════════════════════════════════════════════════════════════════════════════
# MATURITY LEVELS
# ═══════════════════════════════════════════════════════════════════════════════

MATURITY_LEVELS = [
    {"name": "Beginner",     "min_score": 0,    "badge": "🌱", "color": "white"},
    {"name": "Intermediate", "min_score": 50,   "badge": "🔵", "color": "cyan"},
    {"name": "Advanced",     "min_score": 200,  "badge": "🟢", "color": "green"},
    {"name": "Expert",       "min_score": 500,  "badge": "🟡", "color": "yellow"},
    {"name": "Master",       "min_score": 1000, "badge": "⭐", "color": "magenta"},
]

# Points per action
POINTS = {
    "chat": 1,
    "tool_call": 2,
    "flow_run": 10,
    "flow_pass": 15,
    "flow_fail": 5,
    "branch_create": 8,
    "node_add": 5,
    "release": 20,
    "search_kb": 1,
    "learn_shared": 25,
    "learn_private": 5,
    "debug_fix": 30,
    "regression": 40,
}

# Command complexity classification
COMMAND_COMPLEXITY = {
    "status": "basic",
    "list-runs": "basic",
    "list-nodes": "basic",
    "list-branches": "basic",
    "show-graph": "basic",
    "logs": "basic",
    "all": "intermediate",
    "stage": "intermediate",
    "retrace": "intermediate",
    "add-node": "advanced",
    "create-branch": "advanced",
    "bypass": "advanced",
    "forcevalidate": "advanced",
    "release": "expert",
    "release-check": "expert",
}


# ═══════════════════════════════════════════════════════════════════════════════
# USAGE TRACKER
# ═══════════════════════════════════════════════════════════════════════════════

class UsageTracker:
    """Track per-user token usage, commands, and maturity."""

    def __init__(self, db_path: str = DB_PATH):
        self.db_path = db_path
        self._init_db()

    def _init_db(self):
        conn = sqlite3.connect(self.db_path)
        conn.executescript("""
            CREATE TABLE IF NOT EXISTS usage_events (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user TEXT NOT NULL,
                event_type TEXT NOT NULL,
                detail TEXT DEFAULT '',
                tokens_in INTEGER DEFAULT 0,
                tokens_out INTEGER DEFAULT 0,
                points INTEGER DEFAULT 0,
                timestamp TEXT DEFAULT (datetime('now')),
                session_id TEXT DEFAULT ''
            );

            CREATE TABLE IF NOT EXISTS user_stats (
                user TEXT PRIMARY KEY,
                total_tokens_in INTEGER DEFAULT 0,
                total_tokens_out INTEGER DEFAULT 0,
                total_points INTEGER DEFAULT 0,
                total_chats INTEGER DEFAULT 0,
                total_tool_calls INTEGER DEFAULT 0,
                total_flows_run INTEGER DEFAULT 0,
                total_flows_pass INTEGER DEFAULT 0,
                total_flows_fail INTEGER DEFAULT 0,
                total_learns INTEGER DEFAULT 0,
                total_searches INTEGER DEFAULT 0,
                first_seen TEXT,
                last_seen TEXT,
                maturity_level TEXT DEFAULT 'Beginner'
            );

            CREATE TABLE IF NOT EXISTS daily_stats (
                date TEXT NOT NULL,
                user TEXT NOT NULL,
                tokens_in INTEGER DEFAULT 0,
                tokens_out INTEGER DEFAULT 0,
                chats INTEGER DEFAULT 0,
                tool_calls INTEGER DEFAULT 0,
                points INTEGER DEFAULT 0,
                PRIMARY KEY (date, user)
            );

            CREATE INDEX IF NOT EXISTS idx_events_user ON usage_events(user);
            CREATE INDEX IF NOT EXISTS idx_events_timestamp ON usage_events(timestamp);
            CREATE INDEX IF NOT EXISTS idx_daily_date ON daily_stats(date);
        """)
        conn.close()

    def record(self, user: str, event_type: str, detail: str = "",
               tokens_in: int = 0, tokens_out: int = 0, session_id: str = ""):
        """Record a usage event."""
        points = POINTS.get(event_type, 1)
        now = datetime.now().isoformat()
        today = datetime.now().strftime('%Y-%m-%d')

        conn = sqlite3.connect(self.db_path)

        # Insert event
        conn.execute(
            "INSERT INTO usage_events (user, event_type, detail, tokens_in, tokens_out, points, timestamp, session_id) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            (user, event_type, detail[:500], tokens_in, tokens_out, points, now, session_id)
        )

        # Upsert user stats
        conn.execute("""
            INSERT INTO user_stats (user, total_tokens_in, total_tokens_out, total_points,
                total_chats, total_tool_calls, total_flows_run, total_flows_pass, total_flows_fail,
                total_learns, total_searches, first_seen, last_seen, maturity_level)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'Beginner')
            ON CONFLICT(user) DO UPDATE SET
                total_tokens_in = total_tokens_in + ?,
                total_tokens_out = total_tokens_out + ?,
                total_points = total_points + ?,
                total_chats = total_chats + CASE WHEN ? = 'chat' THEN 1 ELSE 0 END,
                total_tool_calls = total_tool_calls + CASE WHEN ? = 'tool_call' THEN 1 ELSE 0 END,
                total_flows_run = total_flows_run + CASE WHEN ? IN ('flow_run','flow_pass','flow_fail') THEN 1 ELSE 0 END,
                total_flows_pass = total_flows_pass + CASE WHEN ? = 'flow_pass' THEN 1 ELSE 0 END,
                total_flows_fail = total_flows_fail + CASE WHEN ? = 'flow_fail' THEN 1 ELSE 0 END,
                total_learns = total_learns + CASE WHEN ? LIKE 'learn%' THEN 1 ELSE 0 END,
                total_searches = total_searches + CASE WHEN ? = 'search_kb' THEN 1 ELSE 0 END,
                last_seen = ?
        """, (user, tokens_in, tokens_out, points, 0, 0, 0, 0, 0, 0, 0, now, now,
              tokens_in, tokens_out, points,
              event_type, event_type, event_type, event_type, event_type, event_type, event_type, now))

        # Update maturity level
        cur = conn.execute("SELECT total_points FROM user_stats WHERE user = ?", (user,))
        row = cur.fetchone()
        if row:
            total = row[0]
            level = "Beginner"
            for ml in MATURITY_LEVELS:
                if total >= ml["min_score"]:
                    level = ml["name"]
            conn.execute("UPDATE user_stats SET maturity_level = ? WHERE user = ?", (level, user))

        # Upsert daily stats
        conn.execute("""
            INSERT INTO daily_stats (date, user, tokens_in, tokens_out, chats, tool_calls, points)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(date, user) DO UPDATE SET
                tokens_in = tokens_in + ?,
                tokens_out = tokens_out + ?,
                chats = chats + CASE WHEN ? = 'chat' THEN 1 ELSE 0 END,
                tool_calls = tool_calls + CASE WHEN ? = 'tool_call' THEN 1 ELSE 0 END,
                points = points + ?
        """, (today, user, tokens_in, tokens_out,
              1 if event_type == 'chat' else 0, 1 if event_type == 'tool_call' else 0, points,
              tokens_in, tokens_out, event_type, event_type, points))

        conn.commit()
        conn.close()

    # ── QUERIES ─────────────────────────────────────────────────────────────

    def get_user_stats(self, user: str = None) -> list:
        """Get stats for one user or all users."""
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        if user:
            rows = conn.execute("SELECT * FROM user_stats WHERE user = ?", (user,)).fetchall()
        else:
            rows = conn.execute("SELECT * FROM user_stats ORDER BY total_points DESC").fetchall()
        conn.close()
        return [dict(r) for r in rows]

    def get_leaderboard(self, top_n: int = 10) -> list:
        """Get top users by maturity points."""
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        rows = conn.execute("""
            SELECT user, total_points, maturity_level,
                   total_chats, total_tool_calls, total_flows_pass,
                   total_learns, total_tokens_in + total_tokens_out as total_tokens
            FROM user_stats ORDER BY total_points DESC LIMIT ?
        """, (top_n,)).fetchall()
        conn.close()
        return [dict(r) for r in rows]

    def get_daily_stats(self, days: int = 7, user: str = None) -> list:
        """Get daily usage stats."""
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        since = (datetime.now() - timedelta(days=days)).strftime('%Y-%m-%d')
        if user:
            rows = conn.execute(
                "SELECT * FROM daily_stats WHERE date >= ? AND user = ? ORDER BY date", (since, user)
            ).fetchall()
        else:
            rows = conn.execute(
                "SELECT date, SUM(tokens_in) as tokens_in, SUM(tokens_out) as tokens_out, "
                "SUM(chats) as chats, SUM(tool_calls) as tool_calls, SUM(points) as points "
                "FROM daily_stats WHERE date >= ? GROUP BY date ORDER BY date", (since,)
            ).fetchall()
        conn.close()
        return [dict(r) for r in rows]

    def get_token_summary(self) -> dict:
        """Get aggregate token usage."""
        conn = sqlite3.connect(self.db_path)
        row = conn.execute("""
            SELECT SUM(total_tokens_in) as total_in, SUM(total_tokens_out) as total_out,
                   COUNT(*) as total_users, SUM(total_chats) as total_chats,
                   SUM(total_tool_calls) as total_tools, SUM(total_flows_run) as total_flows,
                   SUM(total_learns) as total_learns
            FROM user_stats
        """).fetchone()
        conn.close()
        return {
            "total_tokens_in": row[0] or 0,
            "total_tokens_out": row[1] or 0,
            "total_tokens": (row[0] or 0) + (row[1] or 0),
            "total_users": row[2] or 0,
            "total_chats": row[3] or 0,
            "total_tool_calls": row[4] or 0,
            "total_flows": row[5] or 0,
            "total_learns": row[6] or 0,
        }

    def get_maturity_badge(self, user: str) -> dict:
        """Get user's maturity level with badge."""
        stats = self.get_user_stats(user)
        if not stats:
            return {"level": "Beginner", "badge": "🌱", "points": 0}
        s = stats[0]
        for ml in reversed(MATURITY_LEVELS):
            if s["total_points"] >= ml["min_score"]:
                return {"level": ml["name"], "badge": ml["badge"],
                        "points": s["total_points"], "color": ml["color"]}
        return {"level": "Beginner", "badge": "🌱", "points": 0}

    def format_stats_report(self) -> str:
        """Generate a formatted stats report."""
        summary = self.get_token_summary()
        users = self.get_user_stats()
        daily = self.get_daily_stats(7)

        lines = []
        lines.append("")
        lines.append("  SmartGenie Usage Report")
        lines.append("  " + "=" * 58)
        lines.append("")
        lines.append(f"  Total Tokens:     {summary['total_tokens']:,}")
        lines.append(f"    Input:          {summary['total_tokens_in']:,}")
        lines.append(f"    Output:         {summary['total_tokens_out']:,}")
        lines.append(f"  Total Users:      {summary['total_users']}")
        lines.append(f"  Total Chats:      {summary['total_chats']}")
        lines.append(f"  Total Tool Calls: {summary['total_tool_calls']}")
        lines.append(f"  Total Flows Run:  {summary['total_flows']}")
        lines.append(f"  Total Learns:     {summary['total_learns']}")
        lines.append("")
        lines.append("  " + "-" * 58)
        lines.append("  User Leaderboard")
        lines.append("  " + "-" * 58)
        lines.append(f"  {'Rank':<5}{'User':<15}{'Level':<15}{'Points':<8}{'Tokens':<10}{'Flows':<7}{'Learns'}")
        lines.append(f"  {'─'*5}{'─'*15}{'─'*15}{'─'*8}{'─'*10}{'─'*7}{'─'*7}")
        for i, u in enumerate(users[:10], 1):
            badge = ""
            for ml in reversed(MATURITY_LEVELS):
                if u["total_points"] >= ml["min_score"]:
                    badge = ml["badge"]; break
            tokens = u.get("total_tokens_in", 0) + u.get("total_tokens_out", 0)
            lines.append(f"  {i:<5}{u['user']:<15}{badge} {u['maturity_level']:<12}{u['total_points']:<8}{tokens:<10}{u.get('total_flows_pass',0):<7}{u.get('total_learns',0)}")
        lines.append("")

        if daily:
            lines.append("  " + "-" * 58)
            lines.append("  Daily Usage (Last 7 Days)")
            lines.append("  " + "-" * 58)
            lines.append(f"  {'Date':<12}{'Tokens':<10}{'Chats':<8}{'Tools':<8}{'Points'}")
            for d in daily:
                tokens = (d.get("tokens_in", 0) or 0) + (d.get("tokens_out", 0) or 0)
                lines.append(f"  {d['date']:<12}{tokens:<10}{d.get('chats',0):<8}{d.get('tool_calls',0):<8}{d.get('points',0)}")
            lines.append("")

        return '\n'.join(lines)
