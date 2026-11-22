#!/usr/bin/env tclsh
# ═════════════════════════════════════════════════════════════════════════════
# CBflow schedule — opensky
# Source of the SmartGrid schedule page. Data only (no procs).
# Only the project + phase schedule lives here; block dates are
# auto-populated: each hierarchy level releases block_lead_days before its
# parent (block date = phase exit − block_lead_days × levels below the top).
# Edit here or in SmartGrid (Schedule → Edit); the previous version is kept
# in backup/ on every SmartGrid save.
# Last written 2026-11-22 09:35:52 by vmerugu
# ═════════════════════════════════════════════════════════════════════════════

set schedule(start_date)             "2026-11-21"
set schedule(tapeout_date)           "2027-03-31"
set schedule(phases)                 {P0 P1 P2 P3}
set schedule(exits)                  {FP_EXIT PLACE_EXIT CTS_EXIT PRO_EXIT BTO MTO}
set schedule(block_lead_days)        7

# ── Phase exits: schedule(<phase>,<exit>) ──────────────────────────────
set schedule(P0,FP_EXIT)             "2026-11-26"
set schedule(P0,PLACE_EXIT)          "2026-12-02"
set schedule(P0,CTS_EXIT)            "2026-12-07"
set schedule(P0,PRO_EXIT)            "2026-12-12"
set schedule(P0,BTO)                 "2026-12-18"
set schedule(P0,MTO)                 "2026-12-23"

set schedule(P1,FP_EXIT)             "2026-12-29"
set schedule(P1,PLACE_EXIT)          "2027-01-03"
set schedule(P1,CTS_EXIT)            "2027-01-08"
set schedule(P1,PRO_EXIT)            "2027-01-14"
set schedule(P1,BTO)                 "2027-01-20"
set schedule(P1,MTO)                 "2027-01-25"

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
