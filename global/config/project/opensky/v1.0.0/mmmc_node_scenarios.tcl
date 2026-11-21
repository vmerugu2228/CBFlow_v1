# ── MMMC Node Scenario Assignments ──
# Template from: cbflow flow mmmc-manager generate --tech skywater_130nm
# Fill each node with analysis-view names (see: mmmc-manager list-views),
# by hand or with: cbflow flow mmmc-manager set-node --node <n> --setup "..." --hold "..."
array set mmmc {
    cts {
        setup {
            func_ss_1p60v_rc_max_100c
            func_ss_1p60v_rc_max_m40c
        }
        hold  {
            func_ff_1p95v_rc_min_m40c
            func_ff_1p95v_rc_min_100c
        }
    }

    cts_opt {
        setup {
            func_ss_1p60v_rc_max_100c
            func_ss_1p60v_rc_max_m40c
        }
        hold  {
            func_ff_1p95v_rc_min_m40c
            func_ff_1p95v_rc_min_100c
        }
    }

    extraction {
        setup {
            func_ss_1p60v_rc_max_100c
            func_ss_1p60v_rc_max_m40c
        }
        hold  {
            func_ff_1p95v_rc_min_m40c
            func_ff_1p95v_rc_min_100c
        }
    }

    init_design {
        setup {
            func_ss_1p60v_rc_max_100c
            func_ss_1p60v_rc_max_m40c
        }
        hold  {
            func_ff_1p95v_rc_min_m40c
            func_ff_1p95v_rc_min_100c
        }
    }

    place {
        setup {
            func_ss_1p60v_rc_max_100c
            func_ss_1p60v_rc_max_m40c
        }
        hold  {
            func_ff_1p95v_rc_min_m40c
            func_ff_1p95v_rc_min_100c
        }
    }

    pro {
        setup {
            func_ss_1p60v_rc_max_100c
            func_ss_1p60v_rc_max_m40c
        }
        hold  {
            func_ff_1p95v_rc_min_m40c
            func_ff_1p95v_rc_min_100c
        }
    }

    route {
        setup {
            func_ss_1p60v_rc_max_100c
            func_ss_1p60v_rc_max_m40c
        }
        hold  {
            func_ff_1p95v_rc_min_m40c
            func_ff_1p95v_rc_min_100c
        }
    }

    signoff {
        setup {
            func_ss_1p60v_rc_max_100c
            func_ss_1p60v_rc_max_m40c
        }
        hold  {
            func_ff_1p95v_rc_min_m40c
            func_ff_1p95v_rc_min_100c
        }
    }

    synthesis {
        setup {func_tt_1p80v_rc_typ_25c}
        hold  {func_tt_1p80v_rc_typ_25c}
    }

    timing {
        setup {
            func_ss_1p60v_rc_max_100c
            func_ss_1p60v_rc_max_m40c
        }
        hold  {
            func_ff_1p95v_rc_min_m40c
            func_ff_1p95v_rc_min_100c
        }
    }

}
