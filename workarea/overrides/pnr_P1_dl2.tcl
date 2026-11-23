# ═══════════════════════════════════════════════════════════════════════════════
# PNR run overrides for opensky P1 DL2 blocks — appended to each DL2 PNR run's
# setup/override_config.tcl by run_p1_dl2.sh (instead of pnr_P1.tcl).
# Same as pnr_P1.tcl except route / pro: a DL2 block can only time the lib
# sets its DL3 children released timing models for (mac_array: ss / ff), so
# route / pro keep the 6 ss / ff scenarios of cts.
# ═══════════════════════════════════════════════════════════════════════════════

# Design max-fanout constraint (repair_design buffers to it; the stage
# metrics count against it)
set pnr(oss,drv,max_fanout) 10

# MMMC scenarios per stage (oss_node_views): 4 at place, 6 at cts / cts_opt /
# route / pro. signoff keeps the project's 4 (timing models per lib set).
set mmmc(place) {
    setup {func_ss_1p60v_rc_max_100c func_ss_1p60v_rc_max_m40c}
    hold  {func_ff_1p95v_rc_min_m40c func_ff_1p95v_rc_min_100c}
}
set mmmc(cts) {
    setup {func_ss_1p60v_rc_max_100c func_ss_1p60v_rc_max_m40c func_ss_1p60v_rc_typ_100c}
    hold  {func_ff_1p95v_rc_min_m40c func_ff_1p95v_rc_min_100c func_ff_1p95v_rc_typ_m40c}
}
set mmmc(cts_opt) $mmmc(cts)
set mmmc(route) $mmmc(cts)
set mmmc(pro)   $mmmc(cts)
