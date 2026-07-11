# LSF Coverage Checks — Reference

The test suite verifies that every DAG job resolves to a real LSF envelope.
Three checks work together to catch broken resource mapping from static
declaration through runtime materialization.

## Static: `cat15_lsf_per_node_assignment`

**Where:** `PD/utils/commands/test_suite/static_checks.py` (category 15)

**What it verifies:**

For every stage of every flow, one of the following MUST be true:
1. An explicit `lsf(flow_mapping,<FLOW>,<stage_base>)` entry exists in
   `PD/config/flow/v1.0.0/lsf_config.tcl`, or
2. `lsf(default_queue_type)` is set — the safety-net fallback.

**Statuses:**
- **PASS** — the stage has an explicit LSF mapping.
- **SKIP** — the stage has no explicit mapping but the default fallback
  will catch it. The reviewer can promote to an explicit entry.
- **FAIL** — the stage has no explicit mapping AND no default. Any
  submission for this stage would run without a resource envelope.

**Baseline coverage:** 107 flow×stage combinations across the 12 CBflow
flows.

## Static: `cat16_lsf_tier_completeness`

**Where:** `PD/utils/commands/test_suite/static_checks.py` (category 16)

**What it verifies:**

Every tier referenced by a `lsf(flow_mapping,*,*)` entry (plus the
default tier) MUST have `memory`, `cpu`, and `runtime_limit` populated
in `lsf(queue_types,<tier>,*)`. Missing any of those means bsub can't
build a submission envelope.

**Baseline coverage:** 5 tiers verified (XS, S, M, L, XL). `ultra` is
defined but not referenced by any flow_mapping, so the check skips it
naturally.

## E2E: `e2e19_lsf_tier_resolved`

**Where:** `PD/utils/commands/test_suite/e2e_checks.py`

**What it verifies:**

For an already-executed run, every subnode job in the DAG must have a
non-empty `resource_tier` column in the `jobs` table, and that tier must
be one of the known valid names (`XS`, `S`, `M`, `L`, `XL`, `ultra`).

This closes the loop: the two static checks verify declarations, this
one verifies that the engine actually resolved a tier at DAG build time
for every job.

**Statuses:**
- **PASS** — all subnode jobs have a valid resolved tier.
- **SKIP** — DB missing, `resource_tier` column absent, or no subnode
  jobs found.
- **FAIL** — one or more jobs have empty or unknown `resource_tier`
  (reports the count + example job names).

## Running the checks

```bash
# Static only:
cbflow test --static --category 15
cbflow test --static --category 16

# E2E (as part of the standard suite):
cbflow test --e2e
```

## Common failure modes and fixes

| Failure | Root cause | Fix |
|---|---|---|
| `cat15` FAIL: `stage x has no LSF mapping AND no default` | Someone commented out `lsf(default_queue_type)` | Restore the default in `lsf_config.tcl` |
| `cat15` SKIP: `stage x falls back to default "M"` | New stage added without `lsf(flow_mapping,...)` entry | Add an explicit entry — pick the tier appropriate for the stage's compute cost |
| `cat16` FAIL: `tier "XX" missing memory` | Typo in flow_mapping like `"XLG"` | Correct the typo OR define the new tier in `lsf(queue_types,...)` |
| `e2e19` FAIL: `N jobs have no resource_tier` | Race engine's `_parse_resource_map` failed silently (framework bug) | File a bug — the engine should never produce a jobless job |

## See also

- [`lsf-reference.md`](lsf-reference.md) — LSF configuration surface
- `PD/config/flow/v1.0.0/lsf_config.tcl` — the config
- `PD/utils/commands/race_engine.py` — the resolver (`_parse_resource_map`)
