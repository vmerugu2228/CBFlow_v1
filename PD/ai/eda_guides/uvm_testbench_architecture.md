# UVM Testbench Architecture

## Overview

A UVM testbench is a structured, hierarchical collection of reusable components that work together to generate stimulus, observe responses, check correctness, and collect coverage for a design under test (DUT). The architecture follows well-defined patterns that promote modularity, reuse, and scalability from block-level verification through SoC-level integration. Understanding the role and interaction of each component is fundamental to building production-quality verification environments.

## Top-Level Structure

### Module-Based Top

The simulation top module instantiates the DUT, connects interfaces, generates clocks and resets, and starts the UVM testbench:

```systemverilog
module tb_top;
  logic clk, reset;

  // Clock generation
  always #5 clk = ~clk;

  // Interface instantiation
  my_interface intf(clk, reset);

  // DUT instantiation
  my_dut u_dut (
    .clk    (intf.clk),
    .reset  (intf.reset),
    .data_in(intf.data_in),
    .data_out(intf.data_out)
  );

  initial begin
    clk = 0;
    reset = 1;
    #100 reset = 0;

    // Pass interface to UVM via config_db
    uvm_config_db#(virtual my_interface)::set(null, "*", "vif", intf);

    // Start UVM
    run_test();
  end
endmodule
```

### Virtual Interfaces

Virtual interfaces bridge the static (module-based) and dynamic (class-based) worlds. The interface is instantiated in the top module and passed to UVM components through the configuration database. This is the only mechanism for UVM class-based components to access DUT signals.

## UVM Environment (uvm_env)

The environment is the top-level container within the UVM class hierarchy. It instantiates and connects all agents, scoreboards, coverage collectors, and sub-environments.

```systemverilog
class my_env extends uvm_env;
  `uvm_component_utils(my_env)

  my_agent      agent;
  my_scoreboard scoreboard;
  my_coverage   coverage;

  function void build_phase(uvm_phase phase);
    agent      = my_agent::type_id::create("agent", this);
    scoreboard = my_scoreboard::type_id::create("scoreboard", this);
    coverage   = my_coverage::type_id::create("coverage", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    agent.monitor.analysis_port.connect(scoreboard.analysis_imp);
    agent.monitor.analysis_port.connect(coverage.analysis_export);
  endfunction
endclass
```

### Nested Environments

For subsystem and SoC-level verification, environments nest hierarchically:

```
soc_env
  ├── cpu_subsystem_env
  │     ├── cpu_agent
  │     └── cache_agent
  ├── memory_env
  │     ├── ddr_agent
  │     └── memory_scoreboard
  ├── bus_fabric_env
  │     ├── axi_master_agent
  │     └── axi_slave_agent
  └── soc_scoreboard
```

Block-level environments are reused verbatim in subsystem environments, and subsystem environments in SoC environments. This compositional reuse is a core UVM value proposition.

## UVM Agent (uvm_agent)

An agent encapsulates all protocol-specific functionality for one DUT interface. It contains three primary components:

### Agent Modes

- **UVM_ACTIVE**: Agent contains driver, sequencer, and monitor. Generates stimulus and observes responses.
- **UVM_PASSIVE**: Agent contains only a monitor. Observes responses without generating stimulus.

```systemverilog
class my_agent extends uvm_agent;
  `uvm_component_utils(my_agent)

  my_sequencer sequencer;
  my_driver    driver;
  my_monitor   monitor;

  function void build_phase(uvm_phase phase);
    monitor = my_monitor::type_id::create("monitor", this);
    if (get_is_active() == UVM_ACTIVE) begin
      sequencer = my_sequencer::type_id::create("sequencer", this);
      driver    = my_driver::type_id::create("driver", this);
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    if (get_is_active() == UVM_ACTIVE)
      driver.seq_item_port.connect(sequencer.seq_item_export);
  endfunction
endclass
```

### Agent as Reuse Boundary

The agent is the primary unit of verification IP reuse. A well-designed agent:
- Encapsulates a complete protocol implementation.
- Is configurable (active/passive mode, data width, protocol options).
- Is independent of the DUT — it can be reused in any testbench that has the same interface.

## UVM Sequencer (uvm_sequencer)

The sequencer arbitrates between multiple sequences competing to send transactions to the driver. It implements a request-response protocol:

1. Sequence calls `start_item(req)` to request access.
2. Sequencer grants access based on priority and arbitration mode.
3. Sequence randomizes the item and calls `finish_item(req)`.
4. Driver fetches the item via `get_next_item()`.
5. Driver signals completion via `item_done()`.

### Arbitration Modes

- **SEQ_ARB_FIFO**: First-come, first-served (default).
- **SEQ_ARB_RANDOM**: Random selection among waiting sequences.
- **SEQ_ARB_STRICT_FIFO**: Priority-based with FIFO within same priority.
- **SEQ_ARB_STRICT_RANDOM**: Priority-based with random within same priority.
- **SEQ_ARB_USER**: User-defined arbitration algorithm.

## UVM Driver (uvm_driver)

The driver converts transaction-level stimulus into pin-level signal activity. It is the protocol engine that implements the DUT interface timing.

### Driver-Sequencer Handshake

```systemverilog
task run_phase(uvm_phase phase);
  forever begin
    seq_item_port.get_next_item(req);  // Blocking fetch
    drive_pins(req);                    // Protocol-specific driving
    seq_item_port.item_done();          // Signal completion
  end
endtask
```

### Response Handling

For protocols with responses (e.g., read data), the driver can send responses back to the sequence:

```systemverilog
seq_item_port.item_done(rsp);  // Return response with completion
// OR
seq_item_port.put_response(rsp);  // Separate response call
```

## UVM Monitor (uvm_monitor)

The monitor passively observes the DUT interface and reconstructs transactions. It is always present (in both active and passive agents) and serves as the canonical source of observed behavior.

### Monitor Architecture

```systemverilog
class my_monitor extends uvm_monitor;
  virtual my_interface vif;
  uvm_analysis_port #(my_transaction) analysis_port;

  task run_phase(uvm_phase phase);
    forever begin
      my_transaction txn;
      collect_transaction(txn);  // Sample interface signals
      analysis_port.write(txn);  // Broadcast to all subscribers
    end
  endtask

  task collect_transaction(output my_transaction txn);
    txn = my_transaction::type_id::create("txn");
    // Protocol-specific signal sampling logic
    @(posedge vif.valid);
    txn.addr = vif.addr;
    txn.data = vif.data;
    @(posedge vif.ready);
    // Transaction complete
  endtask
endclass
```

### Analysis Port Broadcasting

The monitor's analysis port broadcasts transactions to all connected subscribers simultaneously. This one-to-many pattern enables independent consumers (scoreboards, coverage collectors, protocol checkers) to receive the same data without coupling to each other.

## UVM Scoreboard (uvm_scoreboard)

The scoreboard is the primary correctness checker. It receives actual DUT output from monitors and compares it against expected results.

### Scoreboard Patterns

**Predictor + Comparator Pattern**

```systemverilog
class my_scoreboard extends uvm_scoreboard;
  uvm_analysis_imp #(my_transaction, my_scoreboard) input_imp;
  uvm_analysis_imp #(my_transaction, my_scoreboard) output_imp;
  my_transaction expected_queue[$];

  function void write_input(my_transaction txn);
    my_transaction expected = predict(txn);
    expected_queue.push_back(expected);
  endfunction

  function void write_output(my_transaction txn);
    my_transaction expected = expected_queue.pop_front();
    if (!txn.compare(expected))
      `uvm_error("MISMATCH", $sformatf("Expected: %s Got: %s",
                 expected.convert2string(), txn.convert2string()))
  endfunction
endclass
```

**Out-of-Order Scoreboard**

For designs with multiple outstanding transactions that may complete out of order, use an associative array keyed by transaction ID:

```systemverilog
my_transaction expected_map[int];  // Keyed by transaction ID

function void write_output(my_transaction txn);
  if (expected_map.exists(txn.id)) begin
    if (!txn.compare(expected_map[txn.id]))
      `uvm_error("MISMATCH", "...")
    expected_map.delete(txn.id);
  end
endfunction
```

## UVM Subscriber (uvm_subscriber)

The subscriber extends `uvm_component` and implements `uvm_analysis_imp`. It provides a simple framework for receiving transactions from analysis ports. The most common use is coverage collection:

```systemverilog
class my_coverage extends uvm_subscriber #(my_transaction);
  covergroup cg with function sample(my_transaction txn);
    // Coverpoints and crosses
  endgroup

  function void write(my_transaction t);
    cg.sample(t);
  endfunction
endclass
```

## UVM Factory

The factory enables late binding of types — components and transactions are created via factory methods rather than direct construction. This enables tests to override default types without modifying the testbench code.

### Registration and Creation

```systemverilog
// Registration (in class definition)
class my_driver extends uvm_driver #(my_transaction);
  `uvm_component_utils(my_driver)
endclass

// Creation (in build_phase)
driver = my_driver::type_id::create("driver", this);
```

### Type Overrides

```systemverilog
// In the test: replace my_driver with my_error_driver
class error_test extends base_test;
  function void build_phase(uvm_phase phase);
    my_driver::type_id::set_type_override(my_error_driver::get_type());
    super.build_phase(phase);
  endfunction
endclass
```

This mechanism is the backbone of test customization. The base testbench remains untouched; tests inject variations through factory overrides.

## Testbench Integration Checklist

1. All components registered with factory via `uvm_component_utils` or `uvm_object_utils`.
2. Virtual interfaces passed through `uvm_config_db` (never through constructor arguments).
3. All inter-component communication via TLM ports (no direct cross-references).
4. Agents configurable for active/passive mode.
5. Scoreboards and coverage connected to monitor analysis ports.
6. Sequences use `start_item`/`finish_item` protocol for driver interaction.
7. All transaction classes implement `do_compare()`, `do_copy()`, `convert2string()`.

## Summary

The UVM testbench architecture provides a proven, scalable framework for building verification environments. The environment contains agents (one per interface), each with a sequencer, driver, and monitor. Scoreboards check correctness while subscribers collect coverage. The factory enables test-specific customization. TLM ports decouple components for maximum reuse. This architecture scales from unit-block verification through SoC-level integration, with block-level environments reused compositionally at higher levels of the hierarchy.
