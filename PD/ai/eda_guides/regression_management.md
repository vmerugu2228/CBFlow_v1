# Regression Management

## Overview

Regression management is the discipline of organizing, executing, analyzing, and optimizing the full suite of verification tests that run continuously throughout the design project. A well-managed regression system ensures that every RTL change is validated against the complete test suite, that coverage progresses monotonically toward sign-off goals, and that failures are quickly triaged and resolved. As projects grow to thousands of tests running across hundreds of compute nodes, the regression infrastructure becomes a critical verification asset.

## Regression Architecture

### Test Organization

Tests are organized hierarchically to support targeted and full regression runs:

```
regression_suite/
├── smoke/              # Quick sanity (5-10 tests, < 1 hour)
│   ├── basic_read_write
│   ├── reset_test
│   └── register_reset
├── feature/            # Feature-level tests (100+ tests)
│   ├── dma/
│   │   ├── dma_single_transfer
│   │   ├── dma_burst_transfer
│   │   └── dma_error_handling
│   ├── interrupt/
│   └── memory/
├── stress/             # Stress and performance (20-50 tests)
│   ├── max_throughput
│   ├── deep_queue
│   └── concurrent_access
├── corner/             # Corner-case and error tests (50+ tests)
│   ├── boundary_values
│   ├── error_injection
│   └── reset_recovery
└── gls/                # Gate-level simulation tests
    ├── gls_smoke
    ├── gls_xprop
    └── gls_timing
```

### Regression Levels

| Level | Tests | Frequency | Duration | Purpose |
|-------|-------|-----------|----------|---------|
| Smoke | 5-10 | Per commit | < 30 min | Basic sanity |
| Nightly | 200-500 | Daily | 4-8 hours | Feature coverage |
| Weekly | 1000-5000 | Weekly | 24-48 hours | Full coverage |
| Release | All | Milestone | 48-72 hours | Sign-off |

## Test Selection

### Change-Based Selection

Intelligent test selection based on RTL changes reduces regression time:

1. **Impact analysis**: Determine which modules were modified.
2. **Test mapping**: Map modified modules to the tests that exercise them.
3. **Priority ordering**: Run highest-impact tests first.

```python
# Example: change-based test selection
changed_modules = get_changed_files(commit_id)
affected_tests = []
for module in changed_modules:
    affected_tests.extend(test_module_map[module])
# Run affected tests first, then remaining tests by priority
```

### Coverage-Based Selection

Select tests that contribute the most unique coverage:

1. Track each test's coverage contribution (unique bins covered).
2. Rank tests by unique coverage value.
3. Deprioritize tests that contribute no unique coverage.
4. Periodically re-evaluate as the design evolves.

### Risk-Based Selection

Allocate regression resources based on risk:
- New or modified RTL: Run all related tests.
- Stable RTL: Run a representative subset.
- Critical features: Always run full test suite.
- Low-risk features: Run periodically (weekly rather than nightly).

## Seed Management

### Random Seed Strategy

Constrained random tests produce different results with different seeds. Seed management ensures reproducibility and maximizes coverage:

```bash
# Run with a specific seed
simv +ntb_random_seed=12345

# Run with a random seed (record it for reproducibility)
simv +ntb_random_seed_automatic
```

### Seed Database

Maintain a database of seeds and their characteristics:

```
Seed     | Test Name       | Coverage Contribution | Bug Found | Status
---------|----------------|----------------------|-----------|-------
12345    | random_traffic  | 15 unique bins       | BUG-201   | Keep
67890    | stress_test     | 3 unique bins        |           | Keep
11111    | random_traffic  | 0 unique bins        |           | Prune
22222    | error_inject    | 8 unique bins        | BUG-215   | Keep
```

### Seed Optimization

- **Keep high-value seeds**: Seeds that found bugs or contributed unique coverage.
- **Prune redundant seeds**: Seeds that contribute no unique coverage.
- **Generate new seeds**: Periodically add fresh seeds to explore new state space.
- **Seed sweeping**: Run the same test with many seeds to maximize coverage from a single test.

```bash
# Seed sweep: run test with 100 different seeds
for seed in $(seq 1 100); do
  simv +ntb_random_seed=$seed +test_name=random_traffic &
done
```

## Coverage Merging

### Merge Strategy

Coverage from individual test runs must be merged to produce the aggregate view:

```bash
# VCS: merge coverage databases
urg -dir test_*.vdb -dbname merged.vdb

# Xcelium: merge using imc
imc -exec merge.tcl
# merge.tcl:
# merge test_1.ucd test_2.ucd -output merged.ucd

# Questa: merge UCDBs
vcover merge merged.ucdb test_*.ucdb
```

### Incremental Merging

For large regression suites, merge incrementally:
1. Merge each night's results into a nightly database.
2. Merge nightly databases into a weekly database.
3. Use the weekly database for coverage analysis and closure tracking.

### Coverage Trending

Track coverage progression over time:

```
Week 1:  Functional: 45%  Code: 72%  Tests: 150
Week 2:  Functional: 62%  Code: 81%  Tests: 280
Week 3:  Functional: 75%  Code: 88%  Tests: 420
Week 4:  Functional: 84%  Code: 91%  Tests: 550
Week 5:  Functional: 90%  Code: 93%  Tests: 650
Week 6:  Functional: 94%  Code: 95%  Tests: 720
Week 7:  Functional: 97%  Code: 96%  Tests: 780
Week 8:  Functional: 99%  Code: 97%  Tests: 800
```

A healthy project shows monotonically increasing coverage with diminishing returns toward the end.

## Failure Triage

### Automated Triage

When hundreds of tests fail, manual triage is impractical. Automated classification accelerates debug:

1. **Signature extraction**: Extract unique failure signatures from logs (error messages, assertion names, signal values).
2. **Clustering**: Group failures with the same signature — they likely share the same root cause.
3. **Regression comparison**: Compare against the previous regression to identify new failures vs. known issues.
4. **Priority assignment**: Rank failure clusters by impact (number of tests affected, coverage impact, feature criticality).

### Failure Categories

| Category | Description | Action |
|----------|-------------|--------|
| RTL bug | Design defect | File bug, assign to designer |
| Testbench bug | Checker/stimulus error | Fix testbench |
| Environment | Infrastructure issue (license, memory, timeout) | Rerun |
| Known issue | Already filed bug | Link to existing bug |
| Flaky | Intermittent (race condition, timing) | Investigate root cause |

### Triage Workflow

```
1. Run regression → collect results
2. Extract failure signatures from logs
3. Cluster failures by signature
4. For each cluster:
   a. Is this a known issue? → Link to existing bug
   b. Is this an environment issue? → Rerun
   c. Is this new? → Debug, file bug, assign
5. Update triage database
6. Report summary to team
```

### Bug Tracking Integration

Link regression failures directly to bug tracking systems:
- Each unique failure signature maps to a bug ID.
- New failures without a matching signature trigger bug filing.
- Bug resolution triggers regression verification (rerun the failing seed).

## Regression Prioritization

### Test Prioritization Algorithms

**Coverage-Weighted Priority**
```
priority(test) = unique_coverage_contribution(test) * feature_criticality * recency
```

**Failure History Priority**
```
priority(test) = bug_find_rate(test) * coverage_contribution(test)
```

**Time-Budget Optimization**
Given a fixed compute budget, select the test subset that maximizes expected coverage:
```
maximize: sum(coverage_contribution[i]) for i in selected_tests
subject to: sum(runtime[i]) for i in selected_tests <= budget
```

## Compute Infrastructure

### Farm Management

Regression tests run on compute farms managed by job schedulers:
- **LSF (Load Sharing Facility)**: IBM Spectrum LSF, widely used in EDA.
- **SGE (Sun Grid Engine) / UGE**: Open-source and commercial variants.
- **Slurm**: Open-source, commonly used in HPC environments.

### Resource Allocation

```bash
# LSF: submit regression job
bsub -q regression -R "rusage[mem=8000]" -n 4 \
  run_test.sh test_name seed

# Parallel regression: submit all tests
for test in $(cat test_list.txt); do
  bsub -q regression run_test.sh $test $RANDOM
done
```

### Resource Optimization

- **Right-size memory requests**: Over-requesting memory wastes farm resources; under-requesting causes OOM failures.
- **Parallelize aggressively**: Each test is independent; submit all tests simultaneously.
- **Use checkpointing**: For long-running tests, checkpoint periodically to enable restart on preemption.
- **Monitor utilization**: Track farm utilization to identify bottlenecks and plan capacity.

## Regression Reporting

### Daily Report

```
Regression Report: 2024-01-15 Nightly
=====================================
Tests run:     450
Tests passed:  442 (98.2%)
Tests failed:  8 (1.8%)
New failures:  3
Known issues:  5

Coverage:
  Functional: 92.4% (+0.8% from yesterday)
  Code:       95.1% (+0.2% from yesterday)

New Failures:
  [BUG-NEW-1] dma_burst_test (seed 55555): Scoreboard mismatch
  [BUG-NEW-2] interrupt_test (seed 77777): Timeout
  [BUG-NEW-3] memory_stress (seed 99999): Assertion AST_FIFO_OVF
```

### Dashboards

Modern verification management tools provide web-based dashboards:
- Real-time regression status (running, passed, failed).
- Coverage trending graphs.
- Bug rate trending.
- Resource utilization.
- Test efficiency metrics (unique coverage per compute-hour).

## Best Practices

1. **Run smoke regression on every commit** to catch obvious breakage immediately.
2. **Maintain seed databases** and track which seeds contribute unique coverage or found bugs.
3. **Automate failure triage** with signature extraction and clustering to scale debug.
4. **Track coverage continuously** with daily merging and weekly analysis.
5. **Optimize test selection** based on change impact, coverage contribution, and risk.
6. **Report regression health daily** to keep the team informed and aligned.
7. **Invest in regression infrastructure** — it is the backbone of verification productivity.

## Summary

Regression management orchestrates the continuous execution and analysis of the verification test suite. Test selection balances thoroughness against compute budget. Seed management maximizes coverage from constrained random tests. Coverage merging provides the aggregate view needed for closure. Automated failure triage scales debug to handle hundreds of failures. Prioritization algorithms optimize resource allocation. A well-managed regression infrastructure enables teams to maintain verification momentum throughout the project, achieving coverage goals and sign-off criteria on schedule.
