#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow CLI — Subcommand → Discipline Map
#
# Source of truth for which discipline owns each `cbflow flow <subcommand>`
# entry. Read by:
#   · global/bin/cbflow-flow   — auto-dispatch unknown subcommands to
#                                <disc>/bin/cbflow-<disc>
#   · <disc>/bin/cbflow-<disc> — advertise what it owns via --list
#   · PD/utils/core/paths.py   — get_discipline_command_owner(subcmd)
#
# Cross-domain flow subcommands (types, info, stages, project, release,
# metrics, dashboard, plugin, config, dev, version, qor-report, trending,
# lsf-manager) are NOT listed here — the global cbflow-flow handles them
# in-tree. This file only lists the subcommands that need to route out to
# a discipline-specific launcher.
#
# Adding a new discipline command:
#   1. Add `set cli(discipline,<subcmd>) "<DISC>"` below.
#   2. Add the case to `<DISC>/bin/cbflow-<disc>`'s dispatcher.
#   3. Place the Python handler at `<DISC>/utils/commands/<subcmd>_cmd.py`.
# ═══════════════════════════════════════════════════════════════════════════════

# ── PD-owned subcommands ─────────────────────────────────────────────────────
# library-manager  — tech_config → lib_config binding (physical-design)
# mmmc-manager     — MMMC scenario generation for PD STA/PNR flows
# checklist        — PD exit milestones (FP_EXIT, PLACE_EXIT, CTS_EXIT,
#                    PRO_EXIT, BTO, MTO). DFT/DV will get their own milestone
#                    families with their own checklist commands over time.
set cli(discipline,library-manager) "PD"
set cli(discipline,mmmc-manager)    "PD"
set cli(discipline,checklist)       "PD"

# ── DFT-owned subcommands ────────────────────────────────────────────────────
# (Extension point — populated when DFT-specific tooling ships.)

# ── DV-owned subcommands ─────────────────────────────────────────────────────
# (Extension point — populated when DV-specific tooling ships.)
