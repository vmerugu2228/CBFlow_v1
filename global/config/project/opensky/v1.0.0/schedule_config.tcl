#!/usr/bin/env tclsh
# ═════════════════════════════════════════════════════════════════════════════
# CBflow schedule — opensky
# Source of the SmartGrid schedule page. Data only (no procs).
# Dates only: phases and the exits each phase has come from the project
# config (project(phases), project(phase_exits)). Block dates are
# auto-populated: each hierarchy level releases block_lead_days before its
# parent (block date = phase exit − block_lead_days × levels below the top).
# Edit here or in SmartGrid (Schedule → Edit); the previous version is kept
# in backup/ on every SmartGrid save.
# Last written 2026-11-22 09:50:44 by vmerugu
# ═════════════════════════════════════════════════════════════════════════════

set schedule(start_date)             "2026-11-21"
set schedule(tapeout_date)           "2027-03-31"
set schedule(block_lead_days)        7

# ── Phase exits: schedule(<phase>,<exit>) ──────────────────────────────
set schedule(P0,FP_EXIT)             "2026-11-26"
set schedule(P0,PRO_EXIT)            "2026-12-12"

set schedule(P1,FP_EXIT)             "2026-12-29"
set schedule(P1,PRO_EXIT)            "2027-01-14"

set schedule(P2,FP_EXIT)             "2027-01-31"
set schedule(P2,PLACE_EXIT)          "2027-02-05"
set schedule(P2,CTS_EXIT)            "2027-02-10"
set schedule(P2,PRO_EXIT)            "2027-02-16"
set schedule(P2,BTO)                 "2027-02-22"
set schedule(P2,MTO)                 "2027-02-27"

set schedule(P3,FP_EXIT)             "2027-03-04"
set schedule(P3,PLACE_EXIT)          "2027-03-10"
set schedule(P3,CTS_EXIT)            "2027-03-15"
set schedule(P3,PRO_EXIT)            "2027-03-20"
set schedule(P3,BTO)                 "2027-03-26"
set schedule(P3,MTO)                 "2027-03-31"
