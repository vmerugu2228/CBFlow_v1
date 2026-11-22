#!/usr/bin/env tclsh
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                    DFT DIRECTORY CONFIGURATION                               ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# Run-directory layout per DFT flow, created by `cbflow workspace create`
# (start_run.py reads the dir_config.tcl of the flow's discipline). Every
# DFT flow in flow(types) must have an entry — there is no built-in layout.
# Keep one `set directory(<FLOW>) { "<dir>" ... }` block per flow (data only).

set directory(DFT_INSERT_PASS1) {
    "logs"
    "setup"
    "work"
    "work/DFT_INSERT_PASS1"
}

set directory(DFT_INSERT_PASS2) {
    "logs"
    "setup"
    "work"
    "work/DFT_INSERT_PASS2"
}

set directory(DFT_INSERT_PASS3) {
    "logs"
    "setup"
    "work"
    "work/DFT_INSERT_PASS3"
}

set directory(SCAN_INSERT) {
    "logs"
    "setup"
    "work"
    "work/SCAN_INSERT"
}

set directory(ATPG) {
    "logs"
    "setup"
    "work"
    "work/ATPG"
}

set directory(GLS_FUNC) {
    "logs"
    "setup"
    "work"
    "work/GLS_FUNC"
}

set directory(GLS_SCAN_MBIST) {
    "logs"
    "setup"
    "work"
    "work/GLS_SCAN_MBIST"
}
