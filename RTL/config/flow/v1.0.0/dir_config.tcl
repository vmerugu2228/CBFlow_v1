#!/usr/bin/env tclsh
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                    RTL DIRECTORY CONFIGURATION                               ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# Run-directory layout per RTL flow, created by `cbflow workspace create`
# (start_run.py reads the dir_config.tcl of the flow's discipline). Every
# RTL flow in flow(types) must have an entry — there is no built-in layout.
# Keep one `set directory(<FLOW>) { "<dir>" ... }` block per flow (data only).

set directory(RTL_SPEC) {
    "logs"
    "setup"
    "work"
    "work/RTL_SPEC"
}

set directory(RTL_LINT) {
    "logs"
    "setup"
    "work"
    "work/RTL_LINT"
}

set directory(RTL_CDC) {
    "logs"
    "setup"
    "work"
    "work/RTL_CDC"
}

set directory(RTL_RDC) {
    "logs"
    "setup"
    "work"
    "work/RTL_RDC"
}

set directory(UPF_CHECK) {
    "logs"
    "setup"
    "work"
    "work/UPF_CHECK"
}
