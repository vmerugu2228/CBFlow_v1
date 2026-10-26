# UVM Register Model (RAL)

## Overview

The UVM Register Abstraction Layer (RAL) provides a standardized methodology for modeling, accessing, and verifying the register interface of a design. Registers are the primary software-hardware interface — firmware reads and writes registers to control hardware and observe status. The UVM register model mirrors the design's register map, enabling automated register testing, front-door/back-door access, prediction of register values, and verification of register access policies.

## Register Model Architecture

### Hierarchy

The register model mirrors the design's address map hierarchy:

```
uvm_reg_block (top-level register block)
  ├── uvm_reg_block (sub-block: e.g., DMA controller)
  │     ├── uvm_reg (register: e.g., DMA_CTRL)
  │     │     ├── uvm_reg_field (field: DMA_CTRL.EN)
  │     │     ├── uvm_reg_field (field: DMA_CTRL.MODE)
  │     │     └── uvm_reg_field (field: DMA_CTRL.IRQ_EN)
  │     └── uvm_mem (memory: DMA descriptor table)
  ├── uvm_reg_map (address map with adapter)
  └── uvm_reg_block (sub-block: e.g., UART)
```

### Register Block (uvm_reg_block)

The register block is the top-level container that groups registers, memories, and sub-blocks. It also contains the address map that defines how registers are accessed.

```systemverilog
class my_reg_block extends uvm_reg_block;
  `uvm_object_utils(my_reg_block)

  rand ctrl_reg    CTRL;
  rand status_reg  STATUS;
  rand data_reg    DATA;

  uvm_reg_map      default_map;

  function void build();
    CTRL   = ctrl_reg::type_id::create("CTRL");
    CTRL.configure(this, null, "");
    CTRL.build();

    STATUS = status_reg::type_id::create("STATUS");
    STATUS.configure(this, null, "");
    STATUS.build();

    DATA   = data_reg::type_id::create("DATA");
    DATA.configure(this, null, "");
    DATA.build();

    // Create address map
    default_map = create_map("default_map", 'h0, 4, UVM_LITTLE_ENDIAN);
    default_map.add_reg(CTRL,   'h00, "RW");
    default_map.add_reg(STATUS, 'h04, "RO");
    default_map.add_reg(DATA,   'h08, "RW");
  endfunction
endclass
```

### Register (uvm_reg)

A register represents a single addressable location in the design's register space. It contains one or more fields.

```systemverilog
class ctrl_reg extends uvm_reg;
  `uvm_object_utils(ctrl_reg)

  rand uvm_reg_field EN;
  rand uvm_reg_field MODE;
  rand uvm_reg_field IRQ_EN;
  rand uvm_reg_field RSVD;

  function new(string name = "ctrl_reg");
    super.new(name, 32, UVM_NO_COVERAGE);  // 32-bit register
  endfunction

  function void build();
    EN     = uvm_reg_field::type_id::create("EN");
    EN.configure(this, 1, 0, "RW", 0, 1'h0, 1, 1, 0);
    //          (parent, size, lsb, access, volatile, reset, has_reset, rand, indiv_access)

    MODE   = uvm_reg_field::type_id::create("MODE");
    MODE.configure(this, 2, 1, "RW", 0, 2'h0, 1, 1, 0);

    IRQ_EN = uvm_reg_field::type_id::create("IRQ_EN");
    IRQ_EN.configure(this, 1, 3, "RW", 0, 1'h0, 1, 1, 0);

    RSVD   = uvm_reg_field::type_id::create("RSVD");
    RSVD.configure(this, 28, 4, "RO", 0, 28'h0, 1, 0, 0);
  endfunction
endclass
```

### Register Fields (uvm_reg_field)

Fields are the individual bit groups within a register. Each field has:

- **Size**: Number of bits.
- **Position**: LSB offset within the register.
- **Access policy**: Defines read/write behavior (RW, RO, WO, W1C, RC, etc.).
- **Reset value**: Value after hardware reset.
- **Volatility**: Whether the hardware can change the value asynchronously.

## Access Policies

UVM supports numerous standard access policies:

| Policy | Read Behavior | Write Behavior |
|--------|--------------|----------------|
| RW | Returns stored value | Stores written value |
| RO | Returns stored value | Write has no effect |
| WO | Returns 0 (or X) | Stores written value |
| W1C | Returns stored value | Writing 1 clears bits |
| RC | Returns and clears value | Write has no effect |
| RS | Returns and sets value | Write has no effect |
| W1S | Returns stored value | Writing 1 sets bits |
| W0C | Returns stored value | Writing 0 clears bits |
| WC | Returns stored value | Any write clears all bits |
| WS | Returns stored value | Any write sets all bits |

Custom access policies can be implemented by extending `uvm_reg_field` and overriding the `predict()` method.

## Front-Door and Back-Door Access

### Front-Door Access

Front-door access performs register operations through the DUT's bus interface — the transaction travels through the complete protocol path (sequencer, driver, interface, DUT logic):

```systemverilog
// Write via front door
reg_model.CTRL.write(status, 32'h0000_000F);

// Read via front door
reg_model.STATUS.read(status, rdata);
```

Front-door access verifies the full register access path including address decoding, bus protocol, and register logic.

### Back-Door Access

Back-door access bypasses the bus interface and directly reads/writes the register's RTL signals using the DPI (Direct Programming Interface) or hierarchical references:

```systemverilog
// Write via back door
reg_model.CTRL.write(status, 32'h0000_000F, .path(UVM_BACKDOOR));

// Read via back door
reg_model.STATUS.read(status, rdata, .path(UVM_BACKDOOR));

// Peek (read without side effects)
reg_model.STATUS.peek(status, rdata);

// Poke (write without side effects)
reg_model.CTRL.poke(status, 32'hDEAD_BEEF);
```

Back-door access is used for:
- Fast initialization (loading register values without bus transactions).
- Checking register values without generating bus traffic.
- Accessing registers that are difficult to reach via front door.

### HDL Path Configuration

Back-door access requires specifying the HDL path to the register's storage element:

```systemverilog
CTRL.configure(this, null, "tb.dut.reg_file.ctrl_reg");
// OR
CTRL.add_hdl_path_slice("ctrl_reg_q", 0, 32);
```

## Register Map and Adapter

### Register Map (uvm_reg_map)

The register map defines the address space and maps registers to addresses. It also holds a reference to the adapter that converts register operations to bus transactions.

### Register Adapter

The adapter converts between UVM register operations and protocol-specific bus transactions:

```systemverilog
class my_reg_adapter extends uvm_reg_adapter;
  `uvm_object_utils(my_reg_adapter)

  function uvm_sequence_item reg2bus(const ref uvm_reg_bus_op rw);
    bus_transaction txn = bus_transaction::type_id::create("txn");
    txn.addr  = rw.addr;
    txn.data  = rw.data;
    txn.write = (rw.kind == UVM_WRITE);
    return txn;
  endfunction

  function void bus2reg(uvm_sequence_item bus_item, ref uvm_reg_bus_op rw);
    bus_transaction txn;
    $cast(txn, bus_item);
    rw.addr   = txn.addr;
    rw.data   = txn.rdata;
    rw.kind   = txn.write ? UVM_WRITE : UVM_READ;
    rw.status = txn.error ? UVM_NOT_OK : UVM_IS_OK;
  endfunction
endclass
```

### Connecting the Adapter

```systemverilog
// In the environment's connect_phase
reg_model.default_map.set_sequencer(agent.sequencer, adapter);
reg_model.default_map.set_auto_predict(1);
```

## Prediction

### Auto-Prediction

With auto-prediction enabled, the register model updates its mirror and desired values automatically based on write/read operations performed through the map:

```systemverilog
reg_model.default_map.set_auto_predict(1);
```

This is simpler but does not verify that the bus transaction actually reached the DUT.

### Explicit Prediction

Explicit prediction uses a predictor component that monitors the actual bus interface and updates the register model based on observed transactions:

```systemverilog
uvm_reg_predictor #(bus_transaction) predictor;

// In build_phase
predictor = uvm_reg_predictor#(bus_transaction)::type_id::create("predictor", this);

// In connect_phase
predictor.map = reg_model.default_map;
predictor.adapter = adapter;
agent.monitor.analysis_port.connect(predictor.bus_in);
```

Explicit prediction is more robust because it updates the model only when transactions are observed on the actual bus, catching address decode errors and access issues.

## Built-In Sequences

UVM provides pre-built register test sequences:

### uvm_reg_hw_reset_seq

Reads all registers after reset and verifies they match their documented reset values:

```systemverilog
uvm_reg_hw_reset_seq reset_seq = uvm_reg_hw_reset_seq::type_id::create("reset_seq");
reset_seq.model = reg_model;
reset_seq.start(env.agent.sequencer);
```

### uvm_reg_bit_bash_seq

Writes walking-1 and walking-0 patterns to each register to verify every bit is writable (for RW fields) and not writable (for RO fields).

### uvm_reg_access_seq

Writes known patterns, reads back, and compares. Tests both front-door and back-door access paths.

### uvm_reg_mem_access_seq

Tests memory access: writes patterns to all memory locations and reads them back.

### uvm_reg_mem_walk_seq

Walks through memory addresses verifying read/write capability.

## Register Coverage

The register model supports built-in coverage:

- **Address map coverage**: Tracks which registers have been accessed.
- **Field value coverage**: Tracks which values have been written to each field.
- **Access type coverage**: Tracks read vs. write access to each register.

```systemverilog
// Enable coverage during register creation
function new(string name = "ctrl_reg");
  super.new(name, 32, build_coverage(UVM_CVR_FIELD_VALS | UVM_CVR_ADDR_MAP));
endfunction
```

## Register Model Generation

For designs with hundreds or thousands of registers, the register model is typically auto-generated from:

- **IP-XACT/IEEE 1685**: XML-based IP description format. Tools like Cadence Register Assistant or Synopsys RALF generate UVM register models from IP-XACT descriptions.
- **RALF (Register Abstraction Layer File)**: Synopsys-specific register description format.
- **SystemRDL**: A register description language that can generate UVM models.
- **Custom scripts**: Many teams use Python/Perl scripts to generate register models from spreadsheets or proprietary formats.

## Best Practices

1. **Auto-generate the register model** from the register specification to avoid manual errors and maintain consistency.
2. **Use explicit prediction** for production verification to catch real bus access issues.
3. **Run built-in sequences early** (reset, bit-bash, access) to catch basic register implementation bugs.
4. **Use back-door access for initialization** and front-door access for verification.
5. **Keep the register model synchronized** with the specification throughout the project.
6. **Enable register coverage** and track it as part of the verification plan.

## Summary

The UVM Register Abstraction Layer provides a comprehensive framework for register verification. Register blocks, registers, and fields mirror the design's register map. Front-door access verifies the complete bus path; back-door access enables fast initialization and checking. Adapters bridge between register operations and protocol-specific transactions. Prediction mechanisms keep the model synchronized with the DUT. Built-in sequences automate common register tests. Auto-generation from register specifications ensures consistency and reduces manual effort.
