# ═══════════════════════════════════════════════════════════════════════════════
# PNR run overrides for opensky P1 — appended to each PNR run's
# setup/override_config.tcl by the P1 build scripts (run_p1_dl*.sh).
# ═══════════════════════════════════════════════════════════════════════════════

# Design max-fanout constraint (repair_design buffers to it; the stage
# metrics count against it)
set pnr(oss,drv,max_fanout) 10

# MMMC corners per stage (oss_node_views): 4 at place, 6 at cts / cts_opt,
# 8 at route / pro. signoff keeps the project's 4 (timing models per lib set).
set mmmc(place) {
    setup {func_ss_1p60v_rc_max_100c func_ss_1p60v_rc_max_m40c}
    hold  {func_ff_1p95v_rc_min_m40c func_ff_1p95v_rc_min_100c}
}
set mmmc(cts) {
    setup {func_ss_1p60v_rc_max_100c func_ss_1p60v_rc_max_m40c func_ss_1p60v_rc_typ_100c}
    hold  {func_ff_1p95v_rc_min_m40c func_ff_1p95v_rc_min_100c func_ff_1p95v_rc_typ_m40c}
}
set mmmc(cts_opt) $mmmc(cts)
set mmmc(route) {
    setup {func_ss_1p60v_rc_max_100c func_ss_1p60v_rc_max_m40c func_ss_1p60v_rc_typ_100c func_tt_1p80v_rc_max_100c}
    hold  {func_ff_1p95v_rc_min_m40c func_ff_1p95v_rc_min_100c func_ff_1p95v_rc_typ_m40c func_tt_1p80v_rc_min_25c}
}
set mmmc(pro) $mmmc(route)
