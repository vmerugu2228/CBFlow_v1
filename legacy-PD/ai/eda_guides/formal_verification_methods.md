# Formal Verification Methods

## Overview

Formal verification uses mathematical techniques to exhaustively prove or disprove properties of a digital design without requiring simulation stimulus. Unlike simulation, which can only check a finite number of scenarios, formal methods explore all reachable states of the design. This makes formal verification uniquely powerful for finding corner-case bugs that would require astronomical simulation time to discover. Formal methods have become an essential complement to simulation in modern verification flows.

## Model Checking

### Concept

Model checking systematically explores the state space of a design to determine whether a property (expressed as an assertion) holds for all reachable states. The tool builds an internal representation of the design's state machine and searches for any state sequence that violates the property.

### Bounded Model Checking (BMC)

BMC unrolls the design for a fixed number of clock cycles (the "bound") and uses a SAT (Boolean Satisfiability) or SMT (Satisfiability Modulo Theories) solver to check whether any property violation exists within that depth.

- **Advantages**: Efficient for finding shallow bugs; scales well for large designs.
- **Limitations**: A "no violation found" result only proves safety up to the bound depth, not for all time.
- **Typical bounds**: 20-200 cycles depending on design complexity and property depth.

### Unbounded Model Checking

Unbounded (full) proofs demonstrate that a property holds for all reachable states regardless of how many cycles elapse. Techniques include:

- **BDD-based model checking**: Uses Binary Decision Diagrams to represent state sets. Effective for small-to-medium designs.
- **K-induction**: Proves that if a property holds for K cycles, it holds for K+1 (inductive step). If the base case and inductive step both pass, the property is universally proven.
- **Interpolation**: Uses Craig interpolation to compute over-approximations of reachable states, enabling proofs without full state exploration.
- **IC3/PDR (Property Directed Reachability)**: An incremental algorithm that builds clause-based abstractions of the reachable state set. Currently the most effective technique for many industrial designs.

### Proof Results

- **Proven**: The property holds for all reachable states and all time. This is the strongest result.
- **Falsified (CEX)**: A counterexample (CEX) trace has been found. The tool provides a waveform showing the violation.
- **Bounded**: No violation found up to the specified depth, but the proof is not complete.
- **Inconclusive**: The tool could not prove or disprove the property within resource limits.

## Property Checking

### Writing Properties for Formal

Properties for formal verification require careful attention to:

1. **Completeness**: Properties must cover all relevant behaviors. Missing properties mean unchecked design space.
2. **Assumptions**: Input constraints (via `assume`) bound the legal input space. Over-constraining hides bugs; under-constraining creates false counterexamples.
3. **Reachability**: Properties should be reachable — vacuous proofs (where the antecedent never fires) provide no verification value.
4. **Reset specification**: The formal tool must know the initial state. Explicit reset assumptions are critical.

### Assumption Management

```systemverilog
// Input protocol assumptions
assume property (@(posedge clk) $rose(valid) |-> ##[1:$] $rose(ready));
assume property (@(posedge clk) !valid |-> $stable(data));

// Properties to prove
assert property (@(posedge clk) valid && ready |-> ##1 ack);
```

The correctness of formal proofs depends entirely on the accuracy of assumptions. Invalid assumptions can make the proof meaningless. Regular assumption review and validation (via coverage of assumption antecedents in simulation) is essential.

## Equivalence Checking

### Logic Equivalence Checking (LEC)

LEC proves that two representations of a design are functionally identical at every input combination. It is used at multiple points in the design flow:

- **RTL-to-gate (RTL vs. synthesized netlist)**: Verifies synthesis correctness.
- **Gate-to-gate (pre-ECO vs. post-ECO)**: Verifies that engineering change orders preserve functionality.
- **Gate-to-gate (pre-scan vs. post-scan)**: Verifies DFT insertion correctness.

### LEC Flow

1. **Read reference and implementation**: Load the golden (reference) and revised (implementation) designs.
2. **Map key points**: The tool identifies corresponding flip-flops, primary inputs/outputs, and internal key points between the two designs.
3. **Compare**: For each mapped key point pair, the tool proves (or disproves) that they produce identical outputs for all input combinations.
4. **Debug non-equivalent points**: Non-equivalent (NEQ) points indicate a functional difference. The tool provides a distinguishing pattern — a set of input values that produces different outputs.

### Handling Unmapped Points

Unmapped points occur when the two designs have different structures (e.g., retiming added or removed flip-flops). These require manual guidance:
- Adding mapping directives.
- Using sequential equivalence checking (SEC) for retimed designs.
- Applying black-box constraints for intentionally different blocks.

### Sequential Equivalence Checking (SEC)

SEC handles designs where structural correspondence is broken (e.g., retiming, pipeline stage changes). It proves that the two designs produce the same output sequences for the same input sequences, even if internal state representations differ.

## Formal Apps

Modern formal tools provide pre-packaged "formal apps" that automate common verification tasks:

### Connectivity Checking

Verifies that signals are correctly connected between blocks, typically using a connectivity specification (CSV or spreadsheet) as the golden reference.

### Deadlock/Livelock Detection

Automatically checks that the design cannot enter a state from which it cannot make progress (deadlock) or a cycle of states that never produces useful output (livelock).

### X-Propagation Analysis

Formal X-propagation checks identify cases where unknown (X) values on inputs propagate to outputs or control signals, potentially masking bugs in simulation.

### Reset Domain Verification

Verifies that all flip-flops reach a known state after reset, and that no X values persist after the reset sequence completes.

### Security Verification

Information flow analysis uses formal techniques to prove that secret data (keys, passwords) cannot leak to untrusted outputs.

## Formal Verification Flow

### Setup

1. **File list**: RTL files, library cells, constraints.
2. **Clock and reset definition**: Explicit specification of clock frequencies, phases, and reset polarity/duration.
3. **Assumptions**: Constraints on primary inputs and environmental conditions.
4. **Properties**: Assertions to be proven.

### Execution

1. **Compile and elaborate**: Parse RTL, elaborate the design, resolve parameters.
2. **Initialize**: Apply reset assumptions, compute initial state.
3. **Prove**: Run the proof engine on all properties. Monitor proof progress — some properties may prove quickly while others require more resources.
4. **Analyze results**: Review proven, falsified, bounded, and inconclusive properties.

### Convergence Strategies

When properties remain inconclusive:
- **Add helper assertions**: Proven properties can serve as lemmas that help prove more complex properties (assumption chaining).
- **Abstract complex logic**: Replace irrelevant sub-blocks with black boxes or simplified models.
- **Cut-point insertion**: Sever feedback loops by introducing free variables at strategic points.
- **Decompose**: Break a complex property into simpler sub-properties.

## Complexity Management

### State Space Explosion

The primary challenge of formal verification is state space explosion — the number of reachable states grows exponentially with the number of state elements. For a design with N flip-flops, the theoretical state space is 2^N.

### Abstraction Techniques

- **Black-boxing**: Replace irrelevant sub-blocks with unconstrained logic.
- **Cut points**: Introduce free variables to break internal feedback.
- **Data abstraction**: Reduce data-path width while preserving control logic.
- **Counter abstraction**: Replace wide counters with small abstract counters.
- **Symmetry reduction**: Exploit structural symmetries in the design.

### Design Size Guidelines

| Design Complexity | Flip-flop Count | Formal Tractability |
|-------------------|----------------|---------------------|
| Small block       | < 5K FF        | Full proofs typical |
| Medium block      | 5K-50K FF      | Proofs with abstractions |
| Large subsystem   | 50K-500K FF    | Bounded proofs, formal apps |
| Full SoC          | > 500K FF      | Formal apps only, targeted checks |

## Integration with Simulation

Formal verification and simulation are complementary:

- **Formal finds corner cases** that simulation's random generator would never reach.
- **Simulation validates real-world scenarios** including software interaction, performance, and system-level behavior.
- **Shared assertions**: The same SVA assertions used in simulation are proven in formal, providing dual value.
- **Formal-guided simulation**: Counterexamples from formal can be converted to simulation test vectors to debug in a simulation environment.

## Best Practices

1. **Start formal early** — even partial RTL can benefit from property checking.
2. **Keep the formal environment minimal** — include only the logic relevant to the properties being proven.
3. **Review assumptions rigorously** — invalid assumptions produce meaningless proofs.
4. **Use coverage to detect vacuity** — ensure property antecedents are reachable.
5. **Document proof results** — track proven, bounded, and excluded properties for sign-off.
6. **Use formal for what it excels at**: protocol compliance, deadlock detection, connectivity, and equivalence checking.

## Summary

Formal verification provides mathematical certainty that cannot be achieved through simulation alone. Model checking proves temporal properties for all reachable states. Equivalence checking verifies design transformations. Formal apps automate common checks like connectivity, deadlock, and reset verification. While formal methods face complexity challenges for large designs, targeted application combined with abstraction techniques makes formal verification an indispensable component of modern verification methodology.
