# CBflow Timing Corners List

Generated from: `PD/config/flow/v1.0.0/mmmc_config.tcl`

## Func Mode Corners (12)

| # | Scenario | Process | Voltage | Temp | RC | Analysis | LibSet |
|---|----------|---------|---------|------|----|----------|--------|
| 1 | func_ff_0p80v_rcmin_m40c | ff | 0p80v | -40c | rcmin | hold | ff_0p80v_m40c |
| 2 | func_ff_0p84v_rcmin_150c | ff | 0p84v | 150c | rcmin | hold | ff_0p84v_150c |
| 3 | func_ff_0p84v_rcmin_25c | ff | 0p84v | 25c | rcmin | hold | ff_0p84v_25c |
| 4 | func_ff_0p84v_rcmin_m40c | ff | 0p84v | -40c | rcmin | hold | ff_0p84v_m40c |
| 5 | func_ss_0p76v_rcmax_150c | ss | 0p76v | 150c | rcmax | setup | ss_0p76v_150c |
| 6 | func_ss_0p76v_rcmax_25c | ss | 0p76v | 25c | rcmax | setup | ss_0p76v_25c |
| 7 | func_ss_0p76v_rcmax_m40c | ss | 0p76v | -40c | rcmax | setup | ss_0p76v_m40c |
| 8 | func_ss_0p80v_rcmax_150c | ss | 0p80v | 150c | rcmax | setup | ss_0p80v_150c |
| 9 | func_ss_0p80v_rcmax_25c | ss | 0p80v | 25c | rcmax | setup | ss_0p80v_25c |
| 10 | func_tt_0p80v_rctyp_150c | tt | 0p80v | 150c | rctyp | setup_hold | tt_0p80v_150c |
| 11 | func_tt_0p80v_rctyp_25c | tt | 0p80v | 25c | rctyp | setup_hold | tt_0p80v_25c |
| 12 | func_tt_0p80v_rctyp_m40c | tt | 0p80v | -40c | rctyp | setup_hold | tt_0p80v_m40c |

## Test Mode Corners (12)

| # | Scenario | Process | Voltage | Temp | RC | Analysis | LibSet |
|---|----------|---------|---------|------|----|----------|--------|
| 1 | test_ff_0p80v_rcmin_m40c | ff | 0p80v | -40c | rcmin | hold | ff_0p80v_m40c |
| 2 | test_ff_0p84v_rcmin_150c | ff | 0p84v | 150c | rcmin | hold | ff_0p84v_150c |
| 3 | test_ff_0p84v_rcmin_25c | ff | 0p84v | 25c | rcmin | hold | ff_0p84v_25c |
| 4 | test_ff_0p84v_rcmin_m40c | ff | 0p84v | -40c | rcmin | hold | ff_0p84v_m40c |
| 5 | test_ss_0p76v_rcmax_150c | ss | 0p76v | 150c | rcmax | setup | ss_0p76v_150c |
| 6 | test_ss_0p76v_rcmax_25c | ss | 0p76v | 25c | rcmax | setup | ss_0p76v_25c |
| 7 | test_ss_0p76v_rcmax_m40c | ss | 0p76v | -40c | rcmax | setup | ss_0p76v_m40c |
| 8 | test_ss_0p80v_rcmax_150c | ss | 0p80v | 150c | rcmax | setup | ss_0p80v_150c |
| 9 | test_ss_0p80v_rcmax_25c | ss | 0p80v | 25c | rcmax | setup | ss_0p80v_25c |
| 10 | test_tt_0p80v_rctyp_150c | tt | 0p80v | 150c | rctyp | setup_hold | tt_0p80v_150c |
| 11 | test_tt_0p80v_rctyp_25c | tt | 0p80v | 25c | rctyp | setup_hold | tt_0p80v_25c |
| 12 | test_tt_0p80v_rctyp_m40c | tt | 0p80v | -40c | rctyp | setup_hold | tt_0p80v_m40c |

## Summary

| Category | Count | Process | RC |
|----------|-------|---------|-----|
| Setup | 10 (5 func + 5 test) | ss | rcmax |
| Hold | 8 (4 func + 4 test) | ff | rcmin |
| Typical | 6 (3 func + 3 test) | tt | rctyp |
| **Total** | **24** | | |

## Scenario Sets

| Set | Count | Description |
|-----|-------|-------------|
| setup | 10 | All ss corners (func + test) |
| hold | 8 | All ff corners (func + test) |
| signoff | 19 | All ss + ff + select tt |
| all | 24 | Every corner |

## Building Blocks

- **Process corners**: ss, tt, ff
- **Voltages**: 0p76v (low), 0p80v (nom), 0p84v (high)
- **Temperatures**: m40c (-40C), 25c (room), 150c (hot)
- **RC corners**: rcmax (ss), rctyp (tt), rcmin (ff)
- **Modes**: func, test
- **SDC**: `${design_name}_func.sdc`, `${design_name}_test.sdc`
