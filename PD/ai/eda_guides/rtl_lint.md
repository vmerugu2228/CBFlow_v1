# RTL Linting

## Overview

RTL linting is the static analysis of hardware description language code to detect coding errors, style violations, and potential synthesis/simulation mismatches before the code enters the design flow. Lint tools analyze the RTL structure without simulating it, providing fast feedback on thousands of potential issues. Lint is the first quality gate in any RTL design flow and should be run continuously during development. Fixing lint issues early is orders of magnitude cheaper than finding the same bugs in simulation, synthesis, or silicon.

## Major Lint Tools

### Synopsys SpyGlass

SpyGlass is the most widely used lint tool in the industry. It provides rule-based analysis across multiple domains:

- **SpyGlass Lint**: General RTL coding rules (synthesizability, simulation/synthesis mismatch, naming conventions).
- **SpyGlass CDC**: Clock domain crossing analysis (covered separately in the CDC guide).
- **SpyGlass DFT**: Design-for-test rule checking.
- **SpyGlass Power**: Power intent verification.
- **SpyGlass Constraints**: SDC constraint consistency checking.

SpyGlass uses a goal-based methodology where rule sets are organized into goals (e.g., `lint_rtl`, `lint_functional_rtl`, `cdc_verify`).

### Cadence HAL (Hardware Analysis and Linting)

HAL integrates with the Cadence design flow (Genus, Innovus) and provides lint, CDC, and RDC (Reset Domain Crossing) analysis. It shares the same design database as Genus synthesis, enabling consistent analysis.

### Real Intent Ascent Lint

Ascent provides deep structural analysis with strong formal-based checks. It excels at finding complex issues like X-propagation problems and reconvergence bugs that simpler pattern-matching tools miss.

### Mentor Questa AutoCheck

Part of the Questa verification platform, AutoCheck combines lint with formal analysis to detect issues like dead code, unreachable states, and arithmetic overflow.

## Common Lint Warning Categories

### Synthesizability Warnings

These identify code that will not synthesize or will synthesize differently than simulation behavior:

- **Inferred latches**: A signal not assigned on all paths in a combinational block.
- **Combinational loops**: A signal depends on itself through purely combinational paths.
- **Unsynthesizable constructs**: `initial` blocks, `$display`, real types, `force`/`release` in RTL.
- **Multiply-driven signals**: Same signal assigned from multiple always blocks or continuous assignments.
- **Full case / parallel case pragmas**: Pragmas that affect synthesis but not simulation.

### Simulation-Synthesis Mismatch

- **Incomplete sensitivity list**: `always @(a, b)` missing signal `c` that is also read in the block.
- **Blocking in sequential / non-blocking in combinational**: Wrong assignment type for the block intent.
- **Simulation-only constructs in RTL**: Delay statements (`#10`), `$random`, `$time` in synthesizable code.
- **Integer used in datapath**: `integer` type defaults to 32-bit signed, which may not match intended hardware width.

### Clock and Reset

- **Gated clock on sensitivity list**: Using a gated version of the clock in `always @(posedge gated_clk)` without proper handling.
- **Clock used as data**: Clock signal used as a data input to combinational logic.
- **Reset used as data**: Reset signal used outside of the reset conditional.
- **Multiple clocks in one always block**: Sensitivity list with edges of multiple clocks.
- **Asynchronous reset polarity mismatch**: Sensitivity list edge does not match the `if` condition.

### Naming and Style

- **Signal naming violations**: Signals not matching project naming conventions (e.g., `_n` suffix for active-low, `_r` for registered, `clk_` prefix for clocks).
- **Module naming violations**: Modules not matching hierarchy naming rules.
- **Magic numbers**: Numeric literals without named constants or parameters.
- **Unused signals**: Declared signals that are never read (dead code).
- **Undriven signals**: Signals that are read but never assigned.

### Width Mismatch

- **Truncation**: Assigning a wider signal to a narrower one without explicit bit select.
- **Extension**: Assigning a narrower signal to a wider one (sign extension vs zero extension ambiguity).
- **Port width mismatch**: Module port width does not match the connected signal width.
- **Operator width mismatch**: Operands of different widths in arithmetic or comparison.

### Potential Functional Issues

- **Case statement overlap**: Multiple case items can match the same input value (relevant for `casez`/`casex`).
- **Dead code**: Code that can never execute (e.g., unreachable else branches).
- **Constant conditions**: `if` conditions that are always true or always false.
- **Shift by width or more**: Shifting a signal by its full width or more, resulting in zero (likely a bug).
- **Array index out of bounds**: Static or potentially dynamic array access beyond declared bounds.

## Coding Rules

### Rule Set Organization

Lint rules are organized into severity levels:

- **Error**: Must fix. Indicates code that will not synthesize or will malfunction.
- **Warning**: Should fix. Indicates likely bugs or poor practices.
- **Info**: Optional. Style guidance and best practices.

Projects define a target rule set based on their quality requirements. Safety-critical designs (automotive, aerospace) enforce stricter rule sets.

### Custom Rules

Most lint tools allow custom rules defined in TCL or a proprietary scripting language:

```tcl
# SpyGlass custom rule example
# Enforce that all flip-flops have asynchronous reset
new_rule CUSTOM_001 -severity error \
  -message "Flip-flop without asynchronous reset" \
  -condition {always_ff without negedge rst_n in sensitivity list}
```

### Industry Standards

- **RTL Design Rule Guidelines from foundries**: TSMC, Samsung, and Intel provide technology-specific lint rule sets.
- **STARC RTL Design Style Guide**: Japanese semiconductor consortium guidelines widely adopted in Asia.
- **Company-specific guidelines**: Most large semiconductor companies maintain internal lint rule sets.

## Waiver Management

Not every lint violation is a real bug. Waivers document intentional deviations from lint rules.

### Waiver File

```tcl
# SpyGlass waiver example
waive -rule W_REDEFINE -module top_wrapper \
  -comment "Parameter redefinition is intentional for configuration"

waive -rule W_TRUNCATION -file "alu.sv" -line 145 \
  -comment "Truncation is intentional: only lower 16 bits needed"
```

### Waiver Best Practices

1. **Never bulk-waive**: Waive individually with specific justification.
2. **Require review**: Waivers should be peer-reviewed, not self-approved.
3. **Track in version control**: Waiver files must be committed alongside RTL.
4. **Re-validate periodically**: Waivers may become stale as code changes.
5. **Distinguish permanent from temporary**: Temporary waivers for known issues should have expiration or tracking.

## Lint Flow Integration

### Continuous Integration

Run lint on every RTL commit. Fail the CI check if new errors are introduced. This prevents lint debt from accumulating.

```bash
# Example CI lint script
spyglass -project design.prj -goal lint_rtl -batch
if [ $? -ne 0 ]; then
  echo "LINT FAILED: new violations detected"
  exit 1
fi
```

### Pre-Synthesis Gate

Run lint before synthesis. All errors must be resolved and warnings must be waived or fixed before synthesis begins.

### Incremental Analysis

Modern lint tools support incremental analysis that checks only changed files, reducing turnaround time from minutes to seconds for large designs.

## Measuring Lint Quality

Track the following metrics:

- **Total violations by severity**: Trending downward over the project lifecycle.
- **Waiver count and waiver-to-violation ratio**: High waiver ratios indicate over-waiving.
- **Violations per KLOC (thousand lines of code)**: Benchmark against project history.
- **Time to lint-clean**: Number of iterations from first lint run to zero errors.

## Common Mistakes in Lint Adoption

1. **Running lint too late**: Run from day one, not after RTL freeze.
2. **Ignoring warnings**: Warnings often indicate real bugs masked by other mechanisms.
3. **Over-waiving**: Waiving to meet a deadline without understanding the issue.
4. **Wrong rule set**: Using a generic rule set instead of one tuned for the target technology and design methodology.
5. **No CDC analysis**: Lint alone does not catch CDC bugs; SpyGlass CDC or equivalent is needed.

## Summary

RTL lint is a non-negotiable quality gate. Run it continuously, fix violations promptly, waive judiciously, and track metrics. The combination of lint (structural), CDC analysis (clock domains), simulation (functional), and formal (exhaustive properties) provides comprehensive RTL verification coverage.
