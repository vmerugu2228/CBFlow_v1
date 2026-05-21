#!/usr/bin/env tclsh
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                          DIRECTORY CONFIGURATION                            ║
# ║                    Flow-Specific Directory Structures                       ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# This file contains directory structure definitions for each flow type.
# Each flow type defines its complete directory structure independently.
# All flow types are in UPPERCASE (SYNTH, PNR, FP, etc.)
#
# Usage: source config/flow/v1.0.0/dir_config.tcl

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                       FLOW-SPECIFIC DIRECTORIES                             ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# ┌─ Synthesis Flow Directories ───────────────────────────────────────────────┐
set directory(SYNTH) {
    "logs"
    "setup"
    "work"
    ".make"
    "work/SYNTH"
}

# ┌─ Floorplan Flow Directories ───────────────────────────────────────────────┐
set directory(FP) {
    "logs"
    "setup"
    "work"
    ".make"
    "work/FP"
}

# ┌─ Place and Route Flow Directories ─────────────────────────────────────────┐
set directory(PNR) {
    "logs"
    "setup"
    "work"
    ".make"
    "work/PNR"
}

# ┌─ ECO Flow Directories ─────────────────────────────────────────────────────┐
set directory(ECO) {
    "logs"
    "setup"
    "work"
    ".make"
    "work/ECO"
}

# ┌─ Final Timing Analysis Flow Directories ───────────────────────────────────┐
set directory(STA) {
    "logs"
    "setup"
    "work"
    ".make"
    "work/STA"
}

# ┌─ Logic Equivalence Check Flow Directories ─────────────────────────────────┐
set directory(LEC) {
    "logs"
    "setup"
    "work"
    ".make"
    "work/LEC"
}

# ┌─ Power Analysis Flow Directories ──────────────────────────────────────────┐
set directory(EMIR) {
    "logs"
    "setup"
    "work"
    ".make"
    "work/EMIR"
}

# ┌─ Physical Verification Flow Directories ───────────────────────────────────┐
set directory(PV) {
    "logs"
    "setup"
    "work"
    ".make"
    "work/PV"
}

# ┌─ Clock LP Flow Directories ────────────────────────────────────────────────┐
set directory(CLP) {
    "logs"
    "setup"
    "work"
    ".make"
    "work/CLP"
}

# ┌─ Power Optimization Flow Directories ──────────────────────────────────────┐
set directory(POPT) {
    "logs"
    "setup"
    "work"
    ".make"
    "work/POPT"
}

# ┌─ Final Clock & Floorplan Flow Directories ─────────────────────────────────┐
set directory(FCFP) {
    "logs"
    "setup"
    "work"
    ".make"
    "work/FCFP"
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                       SYNTH_PNR Flow Directories                            ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

set directory(SYNTH_PNR) {
    "logs"
    "setup"
    "work"
    ".make"
    "work/SYNTH_PNR"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Runtime path setup proc: setup_dirs — defined in utils/utilities/utils.tcl
# Called by command files: setup_dirs $run_dir $FLOW_TYPE $NODE_NAME
# ═══════════════════════════════════════════════════════════════════════════════
