#!/usr/bin/env tclsh
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                    DV DIRECTORY CONFIGURATION                                ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# Run-directory layout per DV flow, created by `cbflow workspace create`
# (start_run.py reads the dir_config.tcl of the flow's discipline). Every
# DV flow in flow(types) must have an entry — there is no built-in layout.
# Keep one `set directory(<FLOW>) { "<dir>" ... }` block per flow (data only).

set directory(SPEC_RAMP) {
    "logs"
    "setup"
    "work"
    "work/SPEC_RAMP"
}

set directory(PLANNING) {
    "logs"
    "setup"
    "work"
    "work/PLANNING"
}

set directory(TB_SETUP) {
    "logs"
    "setup"
    "work"
    "work/TB_SETUP"
}

set directory(M1_EXEC) {
    "logs"
    "setup"
    "work"
    "work/M1_EXEC"
}

set directory(M2_EXEC) {
    "logs"
    "setup"
    "work"
    "work/M2_EXEC"
}

set directory(M3_EXEC) {
    "logs"
    "setup"
    "work"
    "work/M3_EXEC"
}

set directory(M4_EXEC) {
    "logs"
    "setup"
    "work"
    "work/M4_EXEC"
}

set directory(ECO_EXEC) {
    "logs"
    "setup"
    "work"
    "work/ECO_EXEC"
}

set directory(DV_SIGNOFF) {
    "logs"
    "setup"
    "work"
    "work/DV_SIGNOFF"
}
