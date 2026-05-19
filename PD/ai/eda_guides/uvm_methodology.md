# UVM Methodology

## Overview

The Universal Verification Methodology (UVM) is the industry-standard framework for building reusable, scalable SystemVerilog testbenches. Developed under Accellera and based on the earlier OVM (Open Verification Methodology), UVM provides a class library, architectural conventions, and automation mechanisms that dramatically reduce testbench development time while improving quality and reuse.

## UVM Architecture

### Testbench Hierarchy

A UVM testbench is organized as a hierarchy of components:

```
uvm_test
  └── uvm_env (top environment)
        ├── uvm_agent (stimulus/monitoring for one interface)
        │     ├── uvm_sequencer (arbitrates sequence items)
        │     ├── uvm_driver (drives signals on the DUT interface)
        │     └── uvm_monitor (observes signals, creates transactions)
        ├── uvm_scoreboard (checks DUT output against expected results)
        ├── uvm_subscriber (coverage collection)
        └── uvm_agent (another interface)
```

This hierarchy maps naturally to the DUT's interfaces: each interface gets its own agent, while the environment coordinates all agents and connects them to checkers and coverage collectors.

### Phasing

UVM components execute through a defined set of phases:

1. **build_phase**: Construct child components, configure settings. Executes top-down.
2. **connect_phase**: Connect TLM ports between components. Executes bottom-up.
3. **end_of_elaboration_phase**: Final configuration adjustments after all connections are made.
4. **run_phase**: The main simulation phase where stimulus is generated and responses are checked. This is a task (time-consuming) phase.
5. **extract_phase / check_phase / report_phase**: Post-simulation data extraction, checking, and reporting.

The phasing mechanism ensures that all components are properly constructed and connected before simulation begins.

## UVM Agents

An agent encapsulates all the components needed to drive and monitor a single DUT interface. Agents operate in two modes:

- **Active mode**: Contains a sequencer and driver (generates stimulus) plus a monitor (observes responses).
- **Passive mode**: Contains only a monitor (observes an interface without driving it). Used for verification IP reuse in higher-level environments.

### Agent Configuration

Agent mode and other settings are controlled through the UVM configuration database:

```systemverilog
uvm_config_db#(int)::set(this, "agent0", "is_active", UVM_ACTIVE);
```

This mechanism allows the same agent code to be reused in active or passive mode depending on the verification context.

## UVM Drivers

The driver receives transaction-level stimulus from the sequencer and converts it into pin-level signal activity on the DUT interface. Key responsibilities:

- Fetch sequence items from the sequencer via `seq_item_port.get_next_item()`.
- Drive the DUT interface according to the protocol timing.
- Signal completion via `seq_item_port.item_done()`.
- Optionally return response data to the sequence via `seq_item_port.put_response()`.

### Driver Implementation Pattern

```systemverilog
class my_driver extends uvm_driver #(my_transaction);
  virtual my_interface vif;

  task run_phase(uvm_phase phase);
    forever begin
      seq_item_port.get_next_item(req);
      drive_transaction(req);
      seq_item_port.item_done();
    end
  endtask

  task drive_transaction(my_transaction txn);
    // Pin-level driving logic
  endtask
endclass
```

## UVM Monitors

Monitors observe the DUT interface without driving any signals. They reconstruct transactions from pin-level activity and broadcast them via analysis ports. Monitors are always present (in both active and passive agents) and serve as the single source of truth for what actually happened on the interface.

### Monitor Responsibilities

- Sample DUT interface signals according to protocol rules.
- Assemble pin-level activity into complete transactions.
- Broadcast transactions via `uvm_analysis_port` to all connected subscribers (scoreboards, coverage collectors).
- Perform basic protocol checking (e.g., handshake violations).

## UVM Scoreboards

The scoreboard is the primary checking mechanism in a UVM testbench. It receives transactions from monitors (via analysis exports) and compares DUT output against expected results.

### Scoreboard Architecture Patterns

- **Reference model**: A behavioral model that processes input transactions and produces expected output. The scoreboard compares actual DUT output against the reference model's predictions.
- **Transform scoreboard**: For data-path designs, the scoreboard applies a known transformation to input data and checks that output data matches.
- **In-order vs. out-of-order checking**: In-order scoreboards use FIFOs; out-of-order scoreboards use associative arrays keyed by transaction ID.

### TLM Connections

Scoreboards connect to monitors through TLM (Transaction-Level Modeling) analysis ports:

```systemverilog
class my_scoreboard extends uvm_scoreboard;
  uvm_analysis_imp #(my_transaction, my_scoreboard) input_imp;

  function void write(my_transaction txn);
    // Compare txn against expected
  endfunction
endclass
```

## UVM Sequences

Sequences are the primary mechanism for generating stimulus. They create and send sequence items (transactions) to the driver through the sequencer.

### Sequence Item

A sequence item (`uvm_sequence_item`) represents a single transaction — the atomic unit of stimulus. It contains the data fields, constraints, and conversion functions needed to represent one protocol transaction.

### Sequence Body

The `body()` task is where a sequence generates its stimulus:

```systemverilog
class my_sequence extends uvm_sequence #(my_transaction);
  task body();
    repeat(100) begin
      req = my_transaction::type_id::create("req");
      start_item(req);
      assert(req.randomize() with { addr inside {[0:'hFF]}; });
      finish_item(req);
    end
  endtask
endclass
```

### Virtual Sequences

Virtual sequences coordinate multiple sequences across different agents/interfaces. They do not connect to a single sequencer but instead start sub-sequences on specific sequencers. This is essential for SoC-level tests that involve coordinated activity across multiple interfaces.

### Sequence Library

UVM provides `uvm_sequence_library`, a container that holds multiple sequences and can randomly select and execute them. This enables automatic test generation by composing sequences from a library.

## TLM (Transaction-Level Modeling)

TLM is the communication backbone of UVM testbenches. Instead of passing pin-level signals between components, TLM passes transaction objects through well-defined ports and exports.

### TLM Port Types

- **uvm_analysis_port**: One-to-many broadcast. Used by monitors to send transactions to multiple subscribers.
- **uvm_blocking_put_port / uvm_blocking_get_port**: Point-to-point communication with blocking semantics.
- **uvm_tlm_fifo**: Buffered communication channel between producer and consumer.

### Benefits of TLM

- Decouples components (a monitor does not need to know how many subscribers exist).
- Enables reuse (components can be reconnected to different consumers).
- Raises the abstraction level (components work with transactions, not signals).

## UVM Factory

The factory is UVM's mechanism for object creation and type overrides. Instead of calling `new()` directly, components and transactions are created through the factory:

```systemverilog
my_transaction txn = my_transaction::type_id::create("txn");
```

### Factory Overrides

The factory enables replacing one type with another without modifying existing code:

```systemverilog
// Replace my_transaction with my_error_transaction everywhere
my_transaction::type_id::set_type_override(my_error_transaction::get_type());

// Replace only for a specific instance
set_inst_override_by_type("env.agent.seqr.*",
                          my_transaction::get_type(),
                          my_error_transaction::get_type());
```

This is critical for test customization: a base test uses default types, while derived tests override specific components or transactions to inject errors, change behavior, or extend functionality.

## UVM Configuration Database

The configuration database (`uvm_config_db`) passes settings between components using a hierarchical path-based mechanism:

```systemverilog
// Set a value (typically in a test or env)
uvm_config_db#(virtual my_interface)::set(this, "env.agent*", "vif", my_vif);

// Get a value (typically in a component's build_phase)
uvm_config_db#(virtual my_interface)::get(this, "", "vif", vif);
```

The configuration database enables flexible parameterization of testbenches without hard-coding values.

## UVM Reporting

UVM provides a unified reporting mechanism with severity levels:

- `uvm_info`: Informational messages with configurable verbosity.
- `uvm_warning`: Non-fatal warnings.
- `uvm_error`: Errors that increment the error count.
- `uvm_fatal`: Immediately terminates simulation.

Verbosity filtering controls which messages appear in logs, reducing noise during regression while preserving detail during debug.

## Best Practices

1. **Register all components with the factory** to enable type overrides and test flexibility.
2. **Use TLM for all inter-component communication** instead of direct cross-references.
3. **Keep agents protocol-specific and reusable** by separating protocol logic from test-specific behavior.
4. **Use virtual sequences for multi-interface coordination** rather than hard-wiring stimulus sequences.
5. **Implement `do_compare()`, `do_copy()`, `do_print()`, and `convert2string()`** for all transaction classes to support debug and scoreboard comparison.
6. **Leverage the configuration database** for all testbench parameterization to maintain flexibility.

## Summary

UVM provides a comprehensive, standardized framework for building verification environments. Its layered architecture (agents, environments, tests), communication infrastructure (TLM), automation mechanisms (factory, configuration database), and phasing model enable teams to build reusable, scalable testbenches that can be composed from block-level to SoC-level verification.
