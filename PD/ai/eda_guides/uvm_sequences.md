# UVM Sequences

## Overview

Sequences are the primary stimulus generation mechanism in UVM. A sequence creates a series of transactions (sequence items) and sends them to a driver through a sequencer. Sequences are class-based objects that can be composed, layered, and randomized to create complex stimulus patterns. Unlike traditional directed tests that are monolithic scripts, UVM sequences are modular, reusable building blocks that can be combined in different ways to create diverse test scenarios.

## Sequence Items

### Fundamentals

A sequence item (`uvm_sequence_item`) is the atomic unit of stimulus — a single transaction representing one protocol operation. It contains the data fields, constraints, and utility methods needed to represent the transaction.

```systemverilog
class bus_transaction extends uvm_sequence_item;
  `uvm_object_utils(bus_transaction)

  rand bit [31:0]  addr;
  rand bit [63:0]  data;
  rand bit [2:0]   burst_type;
  rand bit [7:0]   burst_length;
  rand bit         write;
  rand int unsigned delay;

  // Response fields (filled by driver)
  bit [63:0] rdata;
  bit        error;

  constraint c_addr_align {
    addr[2:0] == 3'b000;  // 8-byte aligned
  }

  constraint c_burst {
    burst_length inside {1, 2, 4, 8, 16};
    burst_type inside {FIXED, INCR, WRAP};
  }

  constraint c_delay {
    delay inside {[0:20]};
  }
endclass
```

### Essential Methods

Every sequence item should implement:

- **`do_copy()`**: Deep copy for scoreboard storage and comparison.
- **`do_compare()`**: Field-by-field comparison for scoreboard checking.
- **`do_print()`**: Formatted output for log messages.
- **`convert2string()`**: String representation for debug messages.
- **`do_pack()` / `do_unpack()`**: Serialization for TLM communication and protocol modeling.

### Field Automation vs. Manual Implementation

UVM provides field automation macros (`uvm_field_int`, `uvm_field_enum`, etc.) that auto-generate `copy`, `compare`, `print`, and `pack` methods. However, manual implementation is recommended for production environments because:
- Field macros incur significant performance overhead.
- Manual methods provide better control over comparison and printing behavior.
- Debugging auto-generated methods is difficult.

## The body() Task

The `body()` task is the core of every sequence. It defines the sequence of transactions to generate.

### Basic Sequence Pattern

```systemverilog
class write_sequence extends uvm_sequence #(bus_transaction);
  `uvm_object_utils(write_sequence)

  rand int num_transactions;
  constraint c_num { num_transactions inside {[10:100]}; }

  task body();
    bus_transaction txn;
    repeat (num_transactions) begin
      txn = bus_transaction::type_id::create("txn");
      start_item(txn);
      if (!txn.randomize() with { write == 1; })
        `uvm_error("RAND_FAIL", "Transaction randomization failed")
      finish_item(txn);
    end
  endtask
endclass
```

### start_item() and finish_item()

The `start_item()` / `finish_item()` pair implements the handshake between the sequence and the sequencer/driver:

1. **`start_item(txn)`**: Requests access to the driver. Blocks until the sequencer grants access based on its arbitration policy.
2. **Randomize**: Between `start_item()` and `finish_item()`, the sequence randomizes the transaction. This is the correct place for randomization because it ensures the sequencer has granted access before randomization occurs.
3. **`finish_item(txn)`**: Sends the transaction to the driver and blocks until the driver calls `item_done()`.

### Alternative: `uvm_do` Macros

```systemverilog
`uvm_do_with(txn, { write == 1; addr < 32'h1000; })
```

The `uvm_do` family of macros combines creation, randomization, `start_item()`, and `finish_item()` into a single call. While convenient, they provide less control than the explicit pattern and can obscure the flow. Many teams prefer the explicit pattern for clarity.

## Starting Sequences

### From a Test

```systemverilog
class my_test extends uvm_test;
  task run_phase(uvm_phase phase);
    write_sequence seq = write_sequence::type_id::create("seq");
    phase.raise_objection(this);
    seq.start(env.agent.sequencer);
    phase.drop_objection(this);
  endtask
endclass
```

The `start()` method executes the sequence's `body()` task on the specified sequencer. It blocks until `body()` completes.

### Start Method Parameters

```systemverilog
seq.start(
  sequencer,      // Target sequencer
  parent_sequence, // Parent (null for root sequences)
  priority,       // Arbitration priority (default: -1)
  call_pre_post   // Execute pre_body/post_body (default: 1)
);
```

## Response Handling

### Getting Responses from the Driver

```systemverilog
task body();
  bus_transaction txn;
  start_item(txn);
  txn.randomize() with { write == 0; };  // Read transaction
  finish_item(txn);
  // Access response data
  `uvm_info("SEQ", $sformatf("Read data: 0x%0h", txn.rdata), UVM_MEDIUM)
endtask
```

If the driver modifies the request item or calls `item_done(rsp)` with a response, the sequence can access the response after `finish_item()` returns.

### Separate Response Channel

```systemverilog
task body();
  bus_transaction req, rsp;
  start_item(req);
  req.randomize();
  finish_item(req);
  get_response(rsp);  // Block until driver sends response
endtask
```

The driver sends the response via `seq_item_port.put_response(rsp)` and the sequence retrieves it with `get_response()`.

## Virtual Sequences

### Purpose

Virtual sequences coordinate stimulus across multiple interfaces. They do not connect to a single sequencer but instead start sub-sequences on different sequencers. This is essential for SoC-level tests where coordinated activity across multiple interfaces is required.

### Implementation

```systemverilog
class soc_virtual_sequence extends uvm_sequence;
  `uvm_object_utils(soc_virtual_sequence)

  // Sequencer handles (set by the test or virtual sequencer)
  uvm_sequencer #(axi_transaction) axi_seqr;
  uvm_sequencer #(apb_transaction) apb_seqr;
  uvm_sequencer #(irq_transaction) irq_seqr;

  task body();
    axi_write_seq  axi_seq  = axi_write_seq::type_id::create("axi_seq");
    apb_config_seq apb_seq  = apb_config_seq::type_id::create("apb_seq");
    irq_wait_seq   irq_seq  = irq_wait_seq::type_id::create("irq_seq");

    // Configure registers first (sequential)
    apb_seq.start(apb_seqr);

    // Then start data transfer and interrupt monitoring in parallel
    fork
      axi_seq.start(axi_seqr);
      irq_seq.start(irq_seqr);
    join
  endtask
endclass
```

### Virtual Sequencer

A virtual sequencer provides a central point for routing sequences to the correct protocol sequencers:

```systemverilog
class soc_virtual_sequencer extends uvm_sequencer;
  `uvm_component_utils(soc_virtual_sequencer)

  uvm_sequencer #(axi_transaction) axi_seqr;
  uvm_sequencer #(apb_transaction) apb_seqr;
endclass
```

The environment connects the virtual sequencer's handles to the actual protocol sequencers during `connect_phase`.

## Sequence Library

### UVM Sequence Library

`uvm_sequence_library` is a container that holds multiple sequences and can randomly select and execute them. This enables automatic test generation:

```systemverilog
class my_seq_lib extends uvm_sequence_library #(bus_transaction);
  `uvm_object_utils(my_seq_lib)
  `uvm_sequence_library_utils(my_seq_lib)

  function new(string name = "my_seq_lib");
    super.new(name);
    init_sequence_library();
  endfunction
endclass
```

Register sequences with the library:

```systemverilog
class write_sequence extends uvm_sequence #(bus_transaction);
  `uvm_object_utils(write_sequence)
  `uvm_add_to_seq_lib(write_sequence, my_seq_lib)
  // ...
endclass
```

### Library Selection Modes

- **UVM_SEQ_LIB_RAND**: Random selection from registered sequences.
- **UVM_SEQ_LIB_RANDC**: Cyclic random — all sequences run before any repeats.
- **UVM_SEQ_LIB_ITEM**: Generate random items directly (no sequence structure).
- **UVM_SEQ_LIB_USER**: User-defined selection algorithm.

## p_sequencer

### Typed Sequencer Access

By default, sequences have access to `m_sequencer` (type `uvm_sequencer_base`). To access sequencer-specific fields or sub-sequencer handles, use the `p_sequencer` mechanism:

```systemverilog
class my_sequence extends uvm_sequence #(my_transaction);
  `uvm_object_utils(my_sequence)
  `uvm_declare_p_sequencer(my_virtual_sequencer)

  task body();
    // Access virtual sequencer's sub-sequencer handles
    my_sub_seq seq = my_sub_seq::type_id::create("seq");
    seq.start(p_sequencer.axi_seqr);
  endtask
endclass
```

The `uvm_declare_p_sequencer` macro creates a typed handle to the sequencer, enabling access to sequencer-specific fields.

## Sequence Composition Patterns

### Sequential Composition

```systemverilog
task body();
  init_seq.start(m_sequencer);    // First: initialization
  config_seq.start(m_sequencer);  // Then: configuration
  traffic_seq.start(m_sequencer); // Finally: traffic
endtask
```

### Parallel Composition

```systemverilog
task body();
  fork
    write_seq.start(m_sequencer);
    read_seq.start(m_sequencer);
  join
endtask
```

### Layered Sequences

Protocol-layer sequences generate low-level transactions. Application-layer sequences generate high-level operations that decompose into multiple protocol-layer transactions:

```systemverilog
class dma_transfer_seq extends uvm_sequence #(bus_transaction);
  task body();
    // One DMA transfer = config registers + data burst + status poll
    write_reg_seq.start(m_sequencer);   // Program DMA registers
    wait_irq_seq.start(m_sequencer);    // Wait for completion interrupt
    read_status_seq.start(m_sequencer); // Check status register
  endtask
endclass
```

## Pre/Post Body Hooks

```systemverilog
task pre_body();
  // Setup before body() — e.g., raise objection
  if (starting_phase != null)
    starting_phase.raise_objection(this);
endtask

task post_body();
  // Cleanup after body() — e.g., drop objection
  if (starting_phase != null)
    starting_phase.drop_objection(this);
endtask
```

Note: `pre_body()` and `post_body()` are only called when `call_pre_post` is set in the `start()` method.

## Best Practices

1. **Randomize between `start_item` and `finish_item`** for correct timing with sequencer arbitration.
2. **Use the factory for all sequence and item creation** to enable test-level overrides.
3. **Keep sequences protocol-agnostic** — sequences should not know about DUT internals.
4. **Use virtual sequences for multi-interface coordination** rather than coupling sequences to specific testbench structures.
5. **Implement proper response handling** for protocols with responses — do not ignore driver responses.
6. **Compose complex scenarios from simple sequences** rather than writing monolithic sequences.

## Summary

UVM sequences provide a flexible, composable mechanism for stimulus generation. Sequence items define the transaction structure. The `body()` task defines the stimulus pattern. Virtual sequences coordinate across interfaces. Sequence libraries enable automated test generation. Together, these mechanisms enable verification teams to build rich, diverse stimulus scenarios from modular, reusable building blocks.
