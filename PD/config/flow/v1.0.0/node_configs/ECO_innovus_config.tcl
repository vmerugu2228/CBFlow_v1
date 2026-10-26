#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# ECO — Cadence Innovus Tool Configuration
# Sourced from ECO_config.tcl when tool=innovus
# ═══════════════════════════════════════════════════════════════════════════════

# ┌─ Innovus Tool Settings ───────────────────────────────────────────────────┐
array set eco {
    tool,vendor   "cadence"
    tool,name     "innovus"
    tool,version  "v1.0.0"
    tool,args     "-batch -no_gui"
}

# ┌─ ECO App Settings (moved from common ECO_config.tcl) ──────────────────────┐
array set eco {
    eco,type                   "functional"
    eco,metal_eco              true
    eco,cell_replacement       true
    eco,spare_cell_prefix      "SPARE_"
    eco,legalize_placement     true
    eco,reroute_modified       true
    eco,incr_route_post        true
}

# ┌─ Innovus Timing ECO Control ──────────────────────────────────────────────┐
array set eco {
    eco,engine                  "nanoroute"
    eco,opt_effort              "high"
    eco,hold_fix                true
    eco,filler_cell_prefix      "FILL"
}

# ┌─ Innovus Functional ECO Control ──────────────────────────────────────────┐
array set eco {
    eco,mode                    "freeze_silicon"
    eco,spare_cell_mapping      true
}
