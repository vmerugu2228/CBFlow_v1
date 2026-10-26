#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow Description Arrays — flow types, run types, phases, milestones
# Used by interactive_config_manager, GUI, help commands
# Sourced from flow_config.tcl
# ═══════════════════════════════════════════════════════════════════════════════

# ── Flow Type Descriptions ──
array set flow_descriptions {
    SYNTH     "Logic synthesis and optimization"
    FP        "Floorplanning and power planning"
    PNR       "Place and route implementation"
    STA       "Final sign-off timing analysis"
    LEC       "Logic equivalence checking"
    EMIR      "Power and thermal analysis"
    PV        "Physical verification (DRC/LVS/ERC/PERC)"
    ECO       "Engineering change orders"
    CLP       "Conformal low power verification"
    POPT      "Power optimization and clock gating"
    FCFP      "Fullchip floorplanning"
    SYNTH_PNR "Unified synthesis to signoff (FC-RM aligned)"
}

# ── Run Type Descriptions ──
array set run_type_descriptions {
    hier "Hierarchical node execution — each stage runs as separate node"
    flat "Merged execution — all execution nodes combined into single merged node"
}

# ── Phase Descriptions ──
array set phase_descriptions {
    P0 "Initial implementation and prototyping"
    P1 "Design refinement and optimization"
    P2 "Final implementation and sign-off"
    P3 "Production and manufacturing release"
}

# ── Milestone Descriptions ──
array set MILESTONE_DESCRIPTIONS {
    FP_EXIT    "Floorplan Exit - Design ready for placement"
    PLACE_EXIT "Placement Exit - Design ready for CTS"
    CTS_EXIT   "CTS Exit - Design ready for routing"
    PRO_EXIT   "Post Route Exit - Design ready for finishing"
    BTO        "Backend Tapeout - Design ready for manufacturing"
    MTO        "Manufacturing Tapeout - Final design release"
}
