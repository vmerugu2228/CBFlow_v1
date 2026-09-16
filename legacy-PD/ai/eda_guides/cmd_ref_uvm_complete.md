# UVM Complete Reference

Comprehensive reference for the Universal Verification Methodology (UVM) library,
covering every major class, phase, mechanism, and pattern used in production
SystemVerilog testbenches.

---

## 1. UVM Base Classes

### 1.1 uvm_void

The root of the UVM class hierarchy. Provides no data members or methods of its
own; exists solely so that every UVM class shares a common ancestor.

```systemverilog
virtual class uvm_void;
endclass
```

### 1.2 uvm_object

Base class for all UVM data and structural objects. Provides core utility
methods.

```systemverilog
class uvm_object extends uvm_void;

  // Construction
  function new(string name = "");

  // Identification
  function string        get_name();
  function string        get_full_name();
  function int           get_inst_id();
  static function int    get_inst_count();
  function uvm_object_wrapper get_type();
  function string        get_type_name();

  // Creation / Copy / Compare / Print / Pack
  virtual function uvm_object  create    (string name = "");
  virtual function uvm_object  clone     ();
  virtual function void        copy      (uvm_object rhs);
  virtual function bit         compare   (uvm_object rhs, uvm_comparer comparer = null);
  virtual function string      convert2string();
  virtual function void        print     (uvm_printer printer = null);
  virtual function void        sprint    (uvm_printer printer = null);
  virtual function void        record    (uvm_recorder recorder = null);
  virtual function void        do_copy   (uvm_object rhs);
  virtual function bit         do_compare(uvm_object rhs, uvm_comparer comparer);
  virtual function void        do_print  (uvm_printer printer);
  virtual function void        do_record (uvm_recorder recorder);
  virtual function void        do_pack   (uvm_packer packer);
  virtual function void        do_unpack (uvm_packer packer);
  virtual function int unsigned pack_bytes   (ref byte unsigned m_bytes[], input uvm_packer packer = null);
  virtual function int unsigned pack_ints    (ref int unsigned  m_ints[],  input uvm_packer packer = null);
  virtual function int unsigned unpack_bytes (ref byte unsigned m_bytes[], input uvm_packer packer = null);
  virtual function int unsigned unpack_ints  (ref int unsigned  m_ints[],  input uvm_packer packer = null);

  // Field automation macros (deprecated in favor of do_* methods)
  `uvm_field_int(ARG, FLAG)
  `uvm_field_string(ARG, FLAG)
  `uvm_field_object(ARG, FLAG)
  `uvm_field_enum(T, ARG, FLAG)
  `uvm_field_array_int(ARG, FLAG)
  `uvm_field_queue_int(ARG, FLAG)
  `uvm_field_aa_int_string(ARG, FLAG)

endclass
```

**Field Automation Flags:**
| Flag | Value | Description |
|------|-------|-------------|
| UVM_ALL_ON | 'b000000_111111 | All operations enabled |
| UVM_COPY | 'b000000_000001 | Enable copy |
| UVM_NOCOPY | 'b000001_000000 | Disable copy |
| UVM_COMPARE | 'b000000_000010 | Enable compare |
| UVM_NOCOMPARE | 'b000010_000000 | Disable compare |
| UVM_PRINT | 'b000000_000100 | Enable print |
| UVM_NOPRINT | 'b000100_000000 | Disable print |
| UVM_RECORD | 'b000000_001000 | Enable record |
| UVM_NORECORD | 'b001000_000000 | Disable record |
| UVM_PACK | 'b000000_010000 | Enable pack |
| UVM_NOPACK | 'b010000_000000 | Disable pack |
| UVM_REFERENCE | 'b100000_000000 | For objects, compare by reference |
| UVM_READONLY | UVM_NOCOPY | Prevent setting from config_db |

### 1.3 uvm_transaction

Extends uvm_object with timing and recording information.

```systemverilog
class uvm_transaction extends uvm_object;

  function new(string name = "", uvm_component initiator = null);

  // Timing
  function void          accept_tr    (time accept_time = 0);
  function void          begin_tr     (time begin_time = 0, int parent_handle = 0);
  function void          end_tr       (time end_time = 0, bit free_handle = 1);
  function time          get_accept_time();
  function time          get_begin_time();
  function time          get_end_time();

  // Recording
  function integer       begin_child_tr(time begin_time = 0, int parent_handle = 0);
  function void          end_child_tr  (time end_time = 0);
  function int           get_tr_handle();
  function void          set_initiator (uvm_component initiator);
  function uvm_component get_initiator ();

  // Events
  function uvm_event     get_event(string name);
  function void          set_id_info(uvm_transaction other);

endclass
```

### 1.4 uvm_component

Base class for all hierarchical testbench components (drivers, monitors,
scoreboards, agents, environments, tests).

```systemverilog
class uvm_component extends uvm_object;

  function new(string name, uvm_component parent);

  //----------------------------------------------------------------------
  // Hierarchy
  //----------------------------------------------------------------------
  function string          get_full_name();
  function uvm_component   get_parent();
  function int             get_num_children();
  function void            get_children(ref uvm_component children[$]);
  function uvm_component   get_child(string name);
  function int             has_child(string name);
  function void            get_first_child(ref string name);
  function void            get_next_child(ref string name);
  function string          get_full_name();
  function int             get_depth();

  //----------------------------------------------------------------------
  // Lookup
  //----------------------------------------------------------------------
  function uvm_component   lookup(string name);
  static function void     find_all(string name, ref uvm_component comps[$],
                                    uvm_component comp = null);

  //----------------------------------------------------------------------
  // Factory
  //----------------------------------------------------------------------
  virtual function uvm_object        create_object (string requested_type_name,
                                                    string name = "");
  virtual function uvm_component     create_component(string requested_type_name,
                                                       string name,
                                                       uvm_component parent);
  static function void               set_type_override_by_type(
                                         uvm_object_wrapper original_type,
                                         uvm_object_wrapper override_type,
                                         bit replace = 1);
  static function void               set_inst_override_by_type(
                                         string relative_inst_path,
                                         uvm_object_wrapper original_type,
                                         uvm_object_wrapper override_type);

  //----------------------------------------------------------------------
  // Phasing (virtual task/function placeholders)
  //----------------------------------------------------------------------
  virtual function void build_phase       (uvm_phase phase);
  virtual function void connect_phase     (uvm_phase phase);
  virtual function void end_of_elaboration_phase(uvm_phase phase);
  virtual function void start_of_simulation_phase(uvm_phase phase);
  virtual task          run_phase         (uvm_phase phase);
  virtual function void extract_phase     (uvm_phase phase);
  virtual function void check_phase       (uvm_phase phase);
  virtual function void report_phase      (uvm_phase phase);
  virtual function void final_phase       (uvm_phase phase);
  virtual task          pre_reset_phase   (uvm_phase phase);
  virtual task          reset_phase       (uvm_phase phase);
  virtual task          post_reset_phase  (uvm_phase phase);
  virtual task          pre_configure_phase(uvm_phase phase);
  virtual task          configure_phase   (uvm_phase phase);
  virtual task          post_configure_phase(uvm_phase phase);
  virtual task          pre_main_phase    (uvm_phase phase);
  virtual task          main_phase        (uvm_phase phase);
  virtual task          post_main_phase   (uvm_phase phase);
  virtual task          pre_shutdown_phase(uvm_phase phase);
  virtual task          shutdown_phase    (uvm_phase phase);
  virtual task          post_shutdown_phase(uvm_phase phase);

  //----------------------------------------------------------------------
  // Configuration
  //----------------------------------------------------------------------
  function void set_config_int   (string inst_name, string field_name, uvm_bitstream_t value);
  function void set_config_string(string inst_name, string field_name, string value);
  function void set_config_object(string inst_name, string field_name, uvm_object value, bit clone = 1);

  //----------------------------------------------------------------------
  // Reporting
  //----------------------------------------------------------------------
  function void uvm_report_info   (string id, string message, int verbosity = UVM_MEDIUM, string filename = "", int line = 0);
  function void uvm_report_warning(string id, string message, string filename = "", int line = 0);
  function void uvm_report_error  (string id, string message, string filename = "", int line = 0);
  function void uvm_report_fatal  (string id, string message, string filename = "", int line = 0);
  function int  uvm_report_enabled(int verbosity, uvm_severity severity = UVM_INFO, string id = "");
  function void set_report_verbosity_level(int verbosity);
  function void set_report_severity_action(uvm_severity severity, uvm_action action);
  function void set_report_id_action(string id, uvm_action action);

  //----------------------------------------------------------------------
  // Objection
  //----------------------------------------------------------------------
  // (through phase.raise_objection / phase.drop_objection)

  //----------------------------------------------------------------------
  // Recording
  //----------------------------------------------------------------------
  function void accept_tr(uvm_transaction tr, time accept_time = 0);
  function int  begin_tr (uvm_transaction tr, string stream_name = "main",
                          string label = "", string desc = "", time begin_time = 0,
                          int parent_handle = 0);
  function void end_tr   (uvm_transaction tr, time end_time = 0, bit free_handle = 1);

endclass
```

---

## 2. UVM Factory

The factory is the central mechanism for creating objects and components in UVM.
It enables type and instance overrides, which is the foundation for test reuse
and configuration.

### 2.1 Registration Macros

```systemverilog
// For uvm_object-derived classes
class my_transaction extends uvm_sequence_item;
  `uvm_object_utils(my_transaction)
  // or with field automation:
  `uvm_object_utils_begin(my_transaction)
    `uvm_field_int(addr, UVM_ALL_ON)
    `uvm_field_int(data, UVM_ALL_ON)
    `uvm_field_enum(cmd_t, cmd, UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name = "my_transaction");
    super.new(name);
  endfunction
endclass

// For uvm_component-derived classes
class my_driver extends uvm_driver #(my_transaction);
  `uvm_component_utils(my_driver)
  // or with field automation:
  `uvm_component_utils_begin(my_driver)
    `uvm_field_int(bus_width, UVM_ALL_ON)
  `uvm_component_utils_end

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
endclass

// Parameterized classes
class my_param_driver #(int WIDTH = 8) extends uvm_driver #(my_transaction);
  typedef my_param_driver #(WIDTH) this_type;
  `uvm_component_param_utils(this_type)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
endclass
```

### 2.2 Factory Creation

```systemverilog
// Object creation (preferred)
my_transaction tr;
tr = my_transaction::type_id::create("tr");

// Component creation (preferred)
my_driver drv;
drv = my_driver::type_id::create("drv", this);

// Direct factory call (less common)
uvm_factory factory = uvm_factory::get();
uvm_object obj = factory.create_object_by_type(my_transaction::get_type(), "", "tr");
uvm_component comp = factory.create_component_by_type(my_driver::get_type(), "", "drv", this);

// By name (for dynamic creation)
uvm_object obj = factory.create_object_by_name("my_transaction", "", "tr");
uvm_component comp = factory.create_component_by_name("my_driver", "", "drv", this);
```

### 2.3 Type Overrides

Type overrides replace ALL instances of a type globally.

```systemverilog
// Override base type with derived type (preferred)
my_transaction::type_id::set_type_override(my_error_transaction::get_type());

// Using factory directly
factory.set_type_override_by_type(
  my_transaction::get_type(),
  my_error_transaction::get_type()
);

// By name
factory.set_type_override_by_name("my_transaction", "my_error_transaction");
```

### 2.4 Instance Overrides

Instance overrides replace a specific instance identified by hierarchical path.

```systemverilog
// Override specific instance
my_transaction::type_id::set_inst_override(
  my_error_transaction::get_type(),
  "env.agent.sequencer.*"
);

// Using factory directly
factory.set_inst_override_by_type(
  my_transaction::get_type(),
  my_error_transaction::get_type(),
  "env.agent.sequencer.*"
);

// By name
factory.set_inst_override_by_name(
  "my_transaction",
  "my_error_transaction",
  "env.agent.sequencer.*"
);
```

### 2.5 Factory Debug

```systemverilog
// Print all registered types
factory.print();

// Print overrides
factory.print(1);  // 1 = show all, 0 = show only user-registered

// Debug creation for a specific type
factory.debug_create_by_type(my_transaction::get_type());
factory.debug_create_by_name("my_transaction", "env.agent.sequencer.tr");
```

---

## 3. UVM Phases

### 3.1 Phase Overview

UVM simulation proceeds through a defined sequence of phases. Phases are either
**functions** (execute in zero time) or **tasks** (can consume simulation time).

```
Time Flow:
==========

build_phase              (function, top-down)
connect_phase            (function, bottom-up)
end_of_elaboration_phase (function, bottom-up)
start_of_simulation_phase(function, bottom-up)

  run_phase              (task, parallel with runtime schedule below)
  |
  +-- pre_reset_phase    (task, bottom-up start)
  +-- reset_phase        (task, bottom-up start)
  +-- post_reset_phase   (task, bottom-up start)
  +-- pre_configure_phase(task, bottom-up start)
  +-- configure_phase    (task, bottom-up start)
  +-- post_configure_phase(task, bottom-up start)
  +-- pre_main_phase     (task, bottom-up start)
  +-- main_phase         (task, bottom-up start)
  +-- post_main_phase    (task, bottom-up start)
  +-- pre_shutdown_phase (task, bottom-up start)
  +-- shutdown_phase     (task, bottom-up start)
  +-- post_shutdown_phase(task, bottom-up start)

extract_phase            (function, bottom-up)
check_phase              (function, bottom-up)
report_phase             (function, bottom-up)
final_phase              (function, top-down)
```

### 3.2 Phase Details

#### build_phase (function, top-down)

- First phase called on each component.
- Execute top-down so parents can configure children before children build.
- Create sub-components, configure using uvm_config_db.
- Do NOT connect ports here.

```systemverilog
function void build_phase(uvm_phase phase);
  super.build_phase(phase);

  // Get configuration
  if (!uvm_config_db #(virtual my_if)::get(this, "", "vif", vif))
    `uvm_fatal("NOVIF", "Virtual interface not found")

  // Create sub-components
  agent = my_agent::type_id::create("agent", this);
  scoreboard = my_scoreboard::type_id::create("scoreboard", this);
endfunction
```

#### connect_phase (function, bottom-up)

- Connect TLM ports, exports, and implementations.
- Execute bottom-up so children are fully built before parent connects them.

```systemverilog
function void connect_phase(uvm_phase phase);
  super.connect_phase(phase);
  agent.monitor.analysis_port.connect(scoreboard.analysis_export);
  agent.monitor.analysis_port.connect(coverage_collector.analysis_export);
endfunction
```

#### end_of_elaboration_phase (function, bottom-up)

- Called after all components are built and connected.
- Useful for topology adjustments, printing topology, final checks.

```systemverilog
function void end_of_elaboration_phase(uvm_phase phase);
  super.end_of_elaboration_phase(phase);
  uvm_top.print_topology();
endfunction
```

#### start_of_simulation_phase (function, bottom-up)

- Called just before simulation starts consuming time.
- Print banners, display configuration summaries.

```systemverilog
function void start_of_simulation_phase(uvm_phase phase);
  super.start_of_simulation_phase(phase);
  `uvm_info("START", $sformatf("Starting test with config: %s",
            cfg.convert2string()), UVM_LOW)
endfunction
```

#### run_phase (task, parallel)

- Main simulation phase, consumes simulation time.
- Runs in parallel with the runtime sub-phases.
- Must use objections to control phase completion.

```systemverilog
task run_phase(uvm_phase phase);
  phase.raise_objection(this);
  // ... stimulus / checking ...
  phase.drop_objection(this);
endtask
```

#### Runtime Sub-Phases

These phases run inside run_phase and execute sequentially. Each phase runs
across all components before moving to the next.

| Phase | Purpose |
|-------|---------|
| pre_reset_phase | Pre-reset setup, power-on |
| reset_phase | Assert and deassert reset |
| post_reset_phase | Post-reset stabilization |
| pre_configure_phase | Setup for configuration |
| configure_phase | Program DUT registers, configure interfaces |
| post_configure_phase | Verify configuration |
| pre_main_phase | Setup for main test |
| main_phase | Main test stimulus and checking |
| post_main_phase | Post-main cleanup |
| pre_shutdown_phase | Setup for shutdown |
| shutdown_phase | Graceful shutdown, drain outstanding transactions |
| post_shutdown_phase | Final cleanup |

```systemverilog
task reset_phase(uvm_phase phase);
  phase.raise_objection(this);
  vif.rst_n <= 1'b0;
  repeat(10) @(posedge vif.clk);
  vif.rst_n <= 1'b1;
  repeat(5) @(posedge vif.clk);
  phase.drop_objection(this);
endtask

task main_phase(uvm_phase phase);
  phase.raise_objection(this);
  // Main test stimulus
  my_sequence seq = my_sequence::type_id::create("seq");
  seq.start(agent.sequencer);
  phase.drop_objection(this);
endtask
```

#### extract_phase (function, bottom-up)

- Extract results from scoreboards, coverage collectors.
- Compute statistics, aggregate data.

```systemverilog
function void extract_phase(uvm_phase phase);
  super.extract_phase(phase);
  total_errors = scoreboard.get_error_count();
  total_transactions = scoreboard.get_total_count();
endfunction
```

#### check_phase (function, bottom-up)

- Verify that DUT operated correctly.
- Check scoreboard results, coverage levels.

```systemverilog
function void check_phase(uvm_phase phase);
  super.check_phase(phase);
  if (total_errors > 0)
    `uvm_error("CHECK", $sformatf("Found %0d errors", total_errors))
  if (scoreboard.has_pending())
    `uvm_error("CHECK", "Scoreboard has pending transactions")
endfunction
```

#### report_phase (function, bottom-up)

- Generate reports, print summaries.

```systemverilog
function void report_phase(uvm_phase phase);
  super.report_phase(phase);
  `uvm_info("REPORT", $sformatf(
    "Test complete: %0d transactions, %0d errors",
    total_transactions, total_errors), UVM_LOW)
endfunction
```

#### final_phase (function, top-down)

- Last phase executed.
- Close files, release resources.

```systemverilog
function void final_phase(uvm_phase phase);
  super.final_phase(phase);
  if (log_file) $fclose(log_file);
endfunction
```

### 3.3 Phase Jumping and Interruption

```systemverilog
// Jump to a specific phase (restart from reset, etc.)
task main_phase(uvm_phase phase);
  phase.raise_objection(this);
  // ...
  if (need_reset) begin
    phase.jump(uvm_reset_phase::get());
  end
  phase.drop_objection(this);
endtask

// Phase timeout
initial begin
  uvm_top.set_timeout(1ms, 0);  // 1ms timeout, no overridable
end
```

### 3.4 Custom Phases

```systemverilog
class my_custom_phase extends uvm_task_phase;
  static local my_custom_phase m_inst;
  static const string type_name = "my_custom_phase";

  static function my_custom_phase get();
    if (m_inst == null) m_inst = new;
    return m_inst;
  endfunction

  function new(string name = "my_custom_phase");
    super.new(name);
  endfunction

  virtual task exec_task(uvm_component comp, uvm_phase phase);
    comp.my_custom_phase(phase);
  endtask
endclass
```

---

## 4. UVM Sequencer and Sequences

### 4.1 uvm_sequence_item

Base class for all transaction items that flow through the sequencer-driver
mechanism.

```systemverilog
class my_transaction extends uvm_sequence_item;
  `uvm_object_utils(my_transaction)

  rand bit [31:0] addr;
  rand bit [31:0] data;
  rand bit        write;
  rand int unsigned delay;

  // Response fields
  bit [31:0] rdata;
  bit        error;

  constraint c_addr { addr inside {[32'h0000_0000 : 32'h0000_FFFF]}; }
  constraint c_delay { delay inside {[0:10]}; }

  function new(string name = "my_transaction");
    super.new(name);
  endfunction

  virtual function void do_copy(uvm_object rhs);
    my_transaction rhs_;
    super.do_copy(rhs);
    $cast(rhs_, rhs);
    addr  = rhs_.addr;
    data  = rhs_.data;
    write = rhs_.write;
    delay = rhs_.delay;
    rdata = rhs_.rdata;
    error = rhs_.error;
  endfunction

  virtual function bit do_compare(uvm_object rhs, uvm_comparer comparer);
    my_transaction rhs_;
    if (!$cast(rhs_, rhs)) return 0;
    return (super.do_compare(rhs, comparer) &&
            addr  == rhs_.addr &&
            data  == rhs_.data &&
            write == rhs_.write);
  endfunction

  virtual function string convert2string();
    return $sformatf("addr=0x%08h data=0x%08h %s delay=%0d",
                     addr, data, write ? "WR" : "RD", delay);
  endfunction

  virtual function void do_print(uvm_printer printer);
    super.do_print(printer);
    printer.print_field_int("addr",  addr,  32, UVM_HEX);
    printer.print_field_int("data",  data,  32, UVM_HEX);
    printer.print_field_int("write", write, 1,  UVM_BIN);
    printer.print_field_int("delay", delay, 32, UVM_DEC);
  endfunction
endclass
```

### 4.2 uvm_sequencer

Parameterized sequencer that arbitrates among sequences requesting to send
items to a driver.

```systemverilog
class uvm_sequencer #(type REQ = uvm_sequence_item, type RSP = REQ)
  extends uvm_sequencer_param_base #(REQ, RSP);

  // Arbitration modes
  typedef enum {
    UVM_SEQ_ARB_FIFO,         // First-in, first-out (default)
    UVM_SEQ_ARB_WEIGHTED,     // Weighted random based on priority
    UVM_SEQ_ARB_RANDOM,       // Random, ignoring priority
    UVM_SEQ_ARB_STRICT_FIFO,  // Priority-ordered FIFO
    UVM_SEQ_ARB_STRICT_RANDOM,// Priority-ordered random
    UVM_SEQ_ARB_USER          // User-defined
  } uvm_sequencer_arb_mode;

  function void set_arbitration(uvm_sequencer_arb_mode val);
  function uvm_sequencer_arb_mode get_arbitration();

  // Lock / Grab
  task lock(uvm_sequence_base sequence_ptr);
  task grab(uvm_sequence_base sequence_ptr);
  function void unlock(uvm_sequence_base sequence_ptr);
  function void ungrab(uvm_sequence_base sequence_ptr);

  function bit is_locked();
  function bit is_grabbed();

  // Sequence control
  function void stop_sequences();
  function bit  has_do_available();
endclass

// Typical sequencer declaration
class my_sequencer extends uvm_sequencer #(my_transaction);
  `uvm_component_utils(my_sequencer)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
endclass
```

### 4.3 uvm_sequence

Base class for all sequences. Sequences generate stimulus items and send them
to a sequencer.

```systemverilog
class uvm_sequence #(type REQ = uvm_sequence_item, type RSP = REQ)
  extends uvm_sequence_base;

  // Key methods
  virtual task body();
  virtual task pre_body();
  virtual task post_body();
  virtual task pre_start();
  virtual task post_start();
  virtual function void pre_do(bit is_item);
  virtual function void mid_do(uvm_sequence_item this_item);
  virtual function void post_do(uvm_sequence_item this_item);

  // Start sequence on sequencer
  virtual task start(uvm_sequencer_base sequencer,
                     uvm_sequence_base parent_sequence = null,
                     int this_priority = -1,
                     bit call_pre_post = 1);

  // Item flow
  task start_item(uvm_sequence_item item,
                  int set_priority = -1,
                  uvm_sequencer_base sequencer = null);
  task finish_item(uvm_sequence_item item,
                   int set_priority = -1);

  // Get response from driver
  task get_response(output RSP response, input int transaction_id = -1);

  // Convenience: create, randomize, send
  task `uvm_do(SEQ_OR_ITEM)
  task `uvm_do_with(SEQ_OR_ITEM, CONSTRAINTS)
  task `uvm_do_on(SEQ_OR_ITEM, SEQUENCER)
  task `uvm_do_on_with(SEQ_OR_ITEM, SEQUENCER, CONSTRAINTS)
  task `uvm_do_on_pri(SEQ_OR_ITEM, SEQUENCER, PRIORITY)
  task `uvm_do_on_pri_with(SEQ_OR_ITEM, SEQUENCER, PRIORITY, CONSTRAINTS)
  task `uvm_create(SEQ_OR_ITEM)
  task `uvm_create_on(SEQ_OR_ITEM, SEQUENCER)
  task `uvm_send(SEQ_OR_ITEM)
  task `uvm_send_pri(SEQ_OR_ITEM, PRIORITY)
  task `uvm_rand_send(SEQ_OR_ITEM)
  task `uvm_rand_send_with(SEQ_OR_ITEM, CONSTRAINTS)
  task `uvm_rand_send_pri(SEQ_OR_ITEM, PRIORITY)
  task `uvm_rand_send_pri_with(SEQ_OR_ITEM, PRIORITY, CONSTRAINTS)

  // Priority
  function int get_priority();
  function void set_priority(int value);

  // Sequence ID
  function int get_sequence_id();

  // Parent sequence
  function uvm_sequence_base get_parent_sequence();

  // Sequencer handle
  function uvm_sequencer_base get_sequencer();

  // Response queue
  function void set_response_queue_error_report_disabled(bit value);
  function bit  get_response_queue_error_report_disabled();
  function void set_response_queue_depth(int value);
  function int  get_response_queue_depth();
endclass
```

### 4.4 Sequence Examples

#### Simple Sequence

```systemverilog
class write_sequence extends uvm_sequence #(my_transaction);
  `uvm_object_utils(write_sequence)

  rand int unsigned num_transactions;
  constraint c_num { num_transactions inside {[5:20]}; }

  function new(string name = "write_sequence");
    super.new(name);
  endfunction

  virtual task body();
    my_transaction tr;
    repeat(num_transactions) begin
      tr = my_transaction::type_id::create("tr");
      start_item(tr);
      if (!tr.randomize() with { write == 1; })
        `uvm_fatal("RNDFAIL", "Randomization failed")
      finish_item(tr);
    end
  endtask
endclass
```

#### Sequence with Response

```systemverilog
class read_check_sequence extends uvm_sequence #(my_transaction);
  `uvm_object_utils(read_check_sequence)

  bit [31:0] expected_data;
  bit [31:0] addr;

  function new(string name = "read_check_sequence");
    super.new(name);
  endfunction

  virtual task body();
    my_transaction tr;
    my_transaction rsp;

    tr = my_transaction::type_id::create("tr");
    start_item(tr);
    tr.addr  = addr;
    tr.write = 0;
    finish_item(tr);

    get_response(rsp);
    if (rsp.rdata !== expected_data)
      `uvm_error("MISMATCH", $sformatf(
        "addr=0x%08h: exp=0x%08h got=0x%08h",
        addr, expected_data, rsp.rdata))
  endtask
endclass
```

#### Hierarchical Sequence (Sequence of Sequences)

```systemverilog
class traffic_sequence extends uvm_sequence #(my_transaction);
  `uvm_object_utils(traffic_sequence)

  function new(string name = "traffic_sequence");
    super.new(name);
  endfunction

  virtual task body();
    write_sequence wr_seq;
    read_check_sequence rd_seq;

    // Write phase
    wr_seq = write_sequence::type_id::create("wr_seq");
    wr_seq.num_transactions = 10;
    wr_seq.start(m_sequencer);

    // Read-back phase
    rd_seq = read_check_sequence::type_id::create("rd_seq");
    rd_seq.addr = 32'h0000_0100;
    rd_seq.expected_data = 32'hDEAD_BEEF;
    rd_seq.start(m_sequencer);
  endtask
endclass
```

#### Virtual Sequence

```systemverilog
class virtual_sequence extends uvm_sequence #(uvm_sequence_item);
  `uvm_object_utils(virtual_sequence)

  // Sequencer handles (set by virtual sequencer or test)
  uvm_sequencer #(axi_transaction) axi_sqr;
  uvm_sequencer #(apb_transaction) apb_sqr;

  function new(string name = "virtual_sequence");
    super.new(name);
  endfunction

  virtual task body();
    axi_write_sequence axi_seq;
    apb_config_sequence apb_seq;

    // Configure via APB, then transfer via AXI
    apb_seq = apb_config_sequence::type_id::create("apb_seq");
    apb_seq.start(apb_sqr);

    axi_seq = axi_write_sequence::type_id::create("axi_seq");
    axi_seq.start(axi_sqr);
  endtask
endclass
```

#### Sequence with Lock/Grab

```systemverilog
class exclusive_sequence extends uvm_sequence #(my_transaction);
  `uvm_object_utils(exclusive_sequence)

  function new(string name = "exclusive_sequence");
    super.new(name);
  endfunction

  virtual task body();
    my_transaction tr;

    // Lock sequencer - no other sequence can send until unlock
    lock(m_sequencer);

    repeat(5) begin
      tr = my_transaction::type_id::create("tr");
      start_item(tr);
      if (!tr.randomize()) `uvm_fatal("RNDFAIL", "Randomization failed")
      finish_item(tr);
    end

    // Unlock
    unlock(m_sequencer);
  endtask
endclass
```

---

## 5. UVM Driver

### 5.1 uvm_driver

The driver converts abstract sequence items into pin-level activity on the DUT
interface.

```systemverilog
class uvm_driver #(type REQ = uvm_sequence_item, type RSP = REQ)
  extends uvm_component;

  uvm_seq_item_pull_port #(REQ, RSP) seq_item_port;
  uvm_analysis_port #(RSP)           rsp_port;

  // Get next item from sequencer (blocking)
  task get_next_item(output REQ t);
  // Signal item processing is complete
  function void item_done(input RSP t = null);
  // Non-blocking alternative
  task try_next_item(output REQ t);
  // Get without removing
  task peek(output REQ t);
  // Get and remove (legacy)
  task get(output REQ t);
  // Put response
  function void put(input RSP t);
endclass
```

### 5.2 Driver Implementation Patterns

#### Basic Driver

```systemverilog
class my_driver extends uvm_driver #(my_transaction);
  `uvm_component_utils(my_driver)

  virtual my_if vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual my_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "Virtual interface not found")
  endfunction

  task run_phase(uvm_phase phase);
    my_transaction tr;
    forever begin
      seq_item_port.get_next_item(tr);
      drive_transaction(tr);
      seq_item_port.item_done();
    end
  endtask

  task drive_transaction(my_transaction tr);
    @(posedge vif.clk);
    vif.addr  <= tr.addr;
    vif.data  <= tr.data;
    vif.write <= tr.write;
    vif.valid <= 1'b1;
    @(posedge vif.clk);
    while (!vif.ready) @(posedge vif.clk);
    vif.valid <= 1'b0;
  endtask
endclass
```

#### Driver with Response

```systemverilog
class my_driver extends uvm_driver #(my_transaction);
  `uvm_component_utils(my_driver)

  virtual my_if vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    my_transaction req, rsp;
    forever begin
      seq_item_port.get_next_item(req);

      // Drive and get response
      drive_and_collect(req, rsp);

      // Send response back to sequence
      rsp.set_id_info(req);
      seq_item_port.item_done(rsp);
    end
  endtask

  task drive_and_collect(input my_transaction req, output my_transaction rsp);
    rsp = my_transaction::type_id::create("rsp");
    rsp.copy(req);

    @(posedge vif.clk);
    vif.addr  <= req.addr;
    vif.write <= req.write;
    if (req.write) vif.wdata <= req.data;
    vif.valid <= 1'b1;

    @(posedge vif.clk);
    while (!vif.ready) @(posedge vif.clk);

    if (!req.write) rsp.rdata = vif.rdata;
    rsp.error = vif.error;
    vif.valid <= 1'b0;
  endtask
endclass
```

#### Pipelined Driver using try_next_item

```systemverilog
class pipelined_driver extends uvm_driver #(my_transaction);
  `uvm_component_utils(pipelined_driver)

  virtual my_if vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    my_transaction tr;
    forever begin
      @(posedge vif.clk);
      seq_item_port.try_next_item(tr);
      if (tr != null) begin
        drive_transaction(tr);
        seq_item_port.item_done();
      end else begin
        drive_idle();
      end
    end
  endtask

  task drive_idle();
    vif.valid <= 1'b0;
  endtask
endclass
```

---

## 6. UVM Monitor

### 6.1 uvm_monitor

Monitors observe DUT interface activity and convert pin-level signals into
transactions. Monitors are always passive (never drive signals).

```systemverilog
class uvm_monitor extends uvm_component;
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
endclass
```

### 6.2 Monitor Implementation

```systemverilog
class my_monitor extends uvm_monitor;
  `uvm_component_utils(my_monitor)

  virtual my_if vif;
  uvm_analysis_port #(my_transaction) analysis_port;

  // Optional: coverage
  my_transaction trans_collected;
  covergroup cg_transaction;
    cp_addr:  coverpoint trans_collected.addr  { bins low  = {[0:32'hFFFF]};
                                                  bins mid  = {[32'h10000:32'hFFFFF]};
                                                  bins high = {[32'h100000:$]}; }
    cp_write: coverpoint trans_collected.write { bins read = {0}; bins write = {1}; }
    cross cp_addr, cp_write;
  endgroup

  function new(string name, uvm_component parent);
    super.new(name, parent);
    analysis_port = new("analysis_port", this);
    cg_transaction = new();
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual my_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "Virtual interface not found")
  endfunction

  task run_phase(uvm_phase phase);
    forever begin
      collect_transaction();
    end
  endtask

  task collect_transaction();
    my_transaction tr;
    tr = my_transaction::type_id::create("tr");

    // Wait for valid transaction
    @(posedge vif.clk);
    while (!vif.valid) @(posedge vif.clk);

    // Capture transaction fields
    tr.addr  = vif.addr;
    tr.write = vif.write;
    if (vif.write) tr.data = vif.wdata;

    // Wait for ready
    while (!vif.ready) @(posedge vif.clk);

    if (!vif.write) tr.rdata = vif.rdata;
    tr.error = vif.error;

    // Sample coverage
    trans_collected = tr;
    cg_transaction.sample();

    `uvm_info("MON", $sformatf("Collected: %s", tr.convert2string()), UVM_HIGH)

    // Broadcast to all subscribers
    analysis_port.write(tr);
  endtask
endclass
```

### 6.3 Analysis Ports and Subscribers

```systemverilog
// Analysis port (1-to-many, non-blocking)
uvm_analysis_port #(my_transaction) analysis_port;

// Analysis export (in subscriber)
class my_subscriber extends uvm_subscriber #(my_transaction);
  `uvm_component_utils(my_subscriber)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void write(my_transaction t);
    // Process received transaction
    `uvm_info("SUB", $sformatf("Received: %s", t.convert2string()), UVM_HIGH)
  endfunction
endclass

// Connecting in parent (env)
function void connect_phase(uvm_phase phase);
  monitor.analysis_port.connect(subscriber.analysis_export);
endfunction
```

---

## 7. UVM Scoreboard

### 7.1 Basic Scoreboard Architecture

```systemverilog
class my_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(my_scoreboard)

  // Analysis exports to receive transactions from monitors
  uvm_analysis_imp #(my_transaction, my_scoreboard) analysis_imp;

  // Internal storage
  my_transaction expected_queue[$];
  int unsigned match_count;
  int unsigned mismatch_count;
  int unsigned total_count;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    analysis_imp = new("analysis_imp", this);
  endfunction

  virtual function void write(my_transaction tr);
    my_transaction expected;
    total_count++;

    if (expected_queue.size() == 0) begin
      `uvm_error("SCBD", "Received unexpected transaction")
      mismatch_count++;
      return;
    end

    expected = expected_queue.pop_front();
    if (!tr.compare(expected)) begin
      `uvm_error("SCBD", $sformatf("Mismatch:\n  EXP: %s\n  GOT: %s",
                expected.convert2string(), tr.convert2string()))
      mismatch_count++;
    end else begin
      `uvm_info("SCBD", $sformatf("Match: %s", tr.convert2string()), UVM_HIGH)
      match_count++;
    end
  endfunction

  function void add_expected(my_transaction tr);
    expected_queue.push_back(tr);
  endfunction

  function bit has_pending();
    return expected_queue.size() > 0;
  endfunction

  function int get_error_count();
    return mismatch_count;
  endfunction

  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    if (expected_queue.size() > 0)
      `uvm_error("SCBD", $sformatf("%0d expected transactions never received",
                expected_queue.size()))
    `uvm_info("SCBD", $sformatf("Total=%0d Match=%0d Mismatch=%0d",
              total_count, match_count, mismatch_count), UVM_LOW)
  endfunction
endclass
```

### 7.2 Scoreboard with Multiple Input Ports

When a scoreboard needs to receive from multiple monitors, use the
`uvm_analysis_imp_decl` macro.

```systemverilog
`uvm_analysis_imp_decl(_expected)
`uvm_analysis_imp_decl(_actual)

class dual_port_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(dual_port_scoreboard)

  uvm_analysis_imp_expected #(my_transaction, dual_port_scoreboard) expected_export;
  uvm_analysis_imp_actual   #(my_transaction, dual_port_scoreboard) actual_export;

  my_transaction expected_queue[$];
  int unsigned match_count, mismatch_count;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    expected_export = new("expected_export", this);
    actual_export   = new("actual_export",   this);
  endfunction

  function void write_expected(my_transaction tr);
    expected_queue.push_back(tr);
    `uvm_info("SCBD", $sformatf("Expected enqueued: %s", tr.convert2string()), UVM_HIGH)
  endfunction

  function void write_actual(my_transaction tr);
    my_transaction exp;
    int found = -1;

    foreach (expected_queue[i]) begin
      if (expected_queue[i].addr == tr.addr) begin
        found = i;
        break;
      end
    end

    if (found >= 0) begin
      exp = expected_queue[found];
      expected_queue.delete(found);
      if (tr.compare(exp)) begin
        match_count++;
      end else begin
        mismatch_count++;
        `uvm_error("SCBD", $sformatf("Mismatch at addr 0x%08h", tr.addr))
      end
    end else begin
      mismatch_count++;
      `uvm_error("SCBD", $sformatf("Unexpected transaction at addr 0x%08h", tr.addr))
    end
  endfunction
endclass
```

### 7.3 TLM FIFO-Based Scoreboard

Using TLM FIFOs provides buffering and more control over transaction flow.

```systemverilog
class fifo_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(fifo_scoreboard)

  uvm_tlm_analysis_fifo #(my_transaction) expected_fifo;
  uvm_tlm_analysis_fifo #(my_transaction) actual_fifo;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    expected_fifo = new("expected_fifo", this);
    actual_fifo   = new("actual_fifo",   this);
  endfunction

  task run_phase(uvm_phase phase);
    my_transaction exp_tr, act_tr;
    forever begin
      expected_fifo.get(exp_tr);
      actual_fifo.get(act_tr);

      if (!exp_tr.compare(act_tr)) begin
        `uvm_error("SCBD", $sformatf("Mismatch:\n  EXP: %s\n  ACT: %s",
                  exp_tr.convert2string(), act_tr.convert2string()))
      end else begin
        `uvm_info("SCBD", "Match", UVM_HIGH)
      end
    end
  endtask
endclass
```

### 7.4 Built-in Comparators

```systemverilog
// In-order comparator
class my_env extends uvm_env;
  uvm_in_order_class_comparator #(my_transaction) comparator;

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    comparator = uvm_in_order_class_comparator #(my_transaction)::type_id::create("comparator", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    expected_monitor.analysis_port.connect(comparator.before_export);
    actual_monitor.analysis_port.connect(comparator.after_export);
  endfunction
endclass

// Built-in comparator
uvm_in_order_built_in_comparator #(int) int_comp;

// Algorithmic comparator (with transformer)
uvm_algorithmic_comparator #(input_type, output_type, transformer_type) algo_comp;
```

---

## 8. UVM Agent

### 8.1 Agent Architecture

An agent encapsulates a sequencer, driver, and monitor for a specific
interface. It can operate in active mode (with driver and sequencer) or passive
mode (monitor only).

```systemverilog
class my_agent extends uvm_agent;
  `uvm_component_utils(my_agent)

  my_driver    driver;
  my_sequencer sequencer;
  my_monitor   monitor;

  // Configuration object
  my_agent_config cfg;

  // Analysis port forwarded from monitor
  uvm_analysis_port #(my_transaction) analysis_port;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    // Get configuration
    if (!uvm_config_db #(my_agent_config)::get(this, "", "cfg", cfg))
      `uvm_fatal("NOCFG", "Agent configuration not found")

    // Monitor is always created
    monitor = my_monitor::type_id::create("monitor", this);

    // Active mode: create driver and sequencer
    if (cfg.is_active == UVM_ACTIVE) begin
      driver    = my_driver::type_id::create("driver", this);
      sequencer = my_sequencer::type_id::create("sequencer", this);
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);

    // Forward monitor's analysis port
    analysis_port = monitor.analysis_port;

    // Connect driver to sequencer in active mode
    if (cfg.is_active == UVM_ACTIVE) begin
      driver.seq_item_port.connect(sequencer.seq_item_export);
    end
  endfunction
endclass
```

### 8.2 Agent Configuration Object

```systemverilog
class my_agent_config extends uvm_object;
  `uvm_object_utils(my_agent_config)

  uvm_active_passive_enum is_active = UVM_ACTIVE;
  virtual my_if            vif;
  bit                      has_coverage = 1;
  bit                      has_checks   = 1;
  int unsigned             bus_width    = 32;

  function new(string name = "my_agent_config");
    super.new(name);
  endfunction

  virtual function string convert2string();
    return $sformatf("is_active=%s has_cov=%0b has_chk=%0b bus_width=%0d",
                     is_active.name(), has_coverage, has_checks, bus_width);
  endfunction
endclass
```

### 8.3 Multiple Agent Instantiation

```systemverilog
class multi_agent_env extends uvm_env;
  `uvm_component_utils(multi_agent_env)

  my_agent agents[4];

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    foreach (agents[i]) begin
      agents[i] = my_agent::type_id::create($sformatf("agent%0d", i), this);
    end
  endfunction
endclass
```

---

## 9. UVM Env (Environment)

### 9.1 Block-Level Environment

```systemverilog
class my_env extends uvm_env;
  `uvm_component_utils(my_env)

  // Agents
  my_agent       agent;

  // Scoreboard
  my_scoreboard  scoreboard;

  // Coverage collector
  my_coverage    coverage;

  // Configuration
  my_env_config  cfg;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    // Get env configuration
    if (!uvm_config_db #(my_env_config)::get(this, "", "cfg", cfg))
      `uvm_fatal("NOCFG", "Env configuration not found")

    // Pass agent config down
    uvm_config_db #(my_agent_config)::set(this, "agent", "cfg", cfg.agent_cfg);

    // Create components
    agent      = my_agent::type_id::create("agent", this);
    scoreboard = my_scoreboard::type_id::create("scoreboard", this);
    if (cfg.has_coverage)
      coverage = my_coverage::type_id::create("coverage", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    agent.analysis_port.connect(scoreboard.analysis_imp);
    if (cfg.has_coverage)
      agent.analysis_port.connect(coverage.analysis_export);
  endfunction
endclass
```

### 9.2 Chip-Level Environment with Virtual Sequencer

```systemverilog
class chip_env extends uvm_env;
  `uvm_component_utils(chip_env)

  // Sub-environments
  axi_env  axi;
  apb_env  apb;
  intr_env intr;

  // Virtual sequencer
  virtual_sequencer v_sqr;

  // Top scoreboard
  chip_scoreboard scoreboard;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    axi  = axi_env::type_id::create("axi", this);
    apb  = apb_env::type_id::create("apb", this);
    intr = intr_env::type_id::create("intr", this);
    v_sqr = virtual_sequencer::type_id::create("v_sqr", this);
    scoreboard = chip_scoreboard::type_id::create("scoreboard", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);

    // Virtual sequencer connections
    v_sqr.axi_sqr  = axi.agent.sequencer;
    v_sqr.apb_sqr  = apb.agent.sequencer;
    v_sqr.intr_sqr = intr.agent.sequencer;

    // Scoreboard connections
    axi.agent.analysis_port.connect(scoreboard.axi_export);
    apb.agent.analysis_port.connect(scoreboard.apb_export);
  endfunction
endclass

class virtual_sequencer extends uvm_sequencer;
  `uvm_component_utils(virtual_sequencer)

  uvm_sequencer #(axi_transaction) axi_sqr;
  uvm_sequencer #(apb_transaction) apb_sqr;
  uvm_sequencer #(intr_transaction) intr_sqr;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
endclass
```

---

## 10. UVM Register Model (RAL)

### 10.1 Register Abstraction Layer Overview

The UVM Register Abstraction Layer (RAL) provides a structured way to model
and access DUT registers.

```
Hierarchy:
  uvm_reg_block
    +-- uvm_reg_map        (address map)
    +-- uvm_reg            (register)
    |     +-- uvm_reg_field (field within register)
    +-- uvm_mem            (memory)
    +-- uvm_reg_block      (sub-block, nested)
```

### 10.2 uvm_reg_field

```systemverilog
class uvm_reg_field extends uvm_object;
  // Configuration
  function void configure(uvm_reg        parent,
                          int unsigned   size,
                          int unsigned   lsb_pos,
                          string         access,     // "RW", "RO", "WO", "W1C", etc.
                          bit            volatile,
                          uvm_reg_data_t reset,
                          bit            has_reset,
                          bit            is_rand,
                          bit            individually_accessible);

  // Access types:
  // "RO"   - Read only
  // "RW"   - Read/Write
  // "RC"   - Read clears all bits
  // "RS"   - Read sets all bits
  // "WRC"  - Writeable, read clears
  // "WRS"  - Writeable, read sets
  // "WC"   - Write clears all bits
  // "WS"   - Write sets all bits
  // "WSRC" - Write sets, read clears
  // "WCRS" - Write clears, read sets
  // "W1C"  - Write 1 to clear
  // "W1S"  - Write 1 to set
  // "W1T"  - Write 1 to toggle
  // "W0C"  - Write 0 to clear
  // "W0S"  - Write 0 to set
  // "W0T"  - Write 0 to toggle
  // "W1SRC"- Write 1 set, read clears
  // "W1CRS"- Write 1 clear, read sets
  // "W0SRC"- Write 0 set, read clears
  // "W0CRS"- Write 0 clear, read sets
  // "WO"   - Write only
  // "WOC"  - Write only clears
  // "WOS"  - Write only sets
  // "NOACCESS" - No access

  // Value access
  function uvm_reg_data_t get();
  function uvm_reg_data_t get_mirrored_value();
  function void            set(uvm_reg_data_t value);
  function uvm_reg_data_t get_reset(string kind = "HARD");
  function void            reset(string kind = "HARD");
  function bit             has_reset(string kind = "HARD", bit delete = 0);
  function void            set_reset(uvm_reg_data_t value, string kind = "HARD");

  // Properties
  function string        get_access(uvm_reg_map map = null);
  function int unsigned  get_n_bits();
  function int unsigned  get_lsb_pos();
endclass
```

### 10.3 uvm_reg

```systemverilog
class uvm_reg extends uvm_object;
  function new(string name = "", int unsigned n_bits, int has_coverage);

  function void configure(uvm_reg_block blk_parent,
                          uvm_reg_file  regfile_parent = null,
                          string        hdl_path = "");

  // Build (called after all fields are created and configured)
  virtual function void build();

  // Front-door access (through bus interface)
  virtual task write  (output uvm_status_e  status,
                       input  uvm_reg_data_t value,
                       input  uvm_path_e     path = UVM_DEFAULT_PATH,
                       input  uvm_reg_map    map = null,
                       input  uvm_sequence_base parent = null,
                       input  int            prior = -1,
                       input  uvm_object     extension = null,
                       input  string         fname = "",
                       input  int            lineno = 0);

  virtual task read   (output uvm_status_e  status,
                       output uvm_reg_data_t value,
                       input  uvm_path_e     path = UVM_DEFAULT_PATH,
                       input  uvm_reg_map    map = null,
                       input  uvm_sequence_base parent = null,
                       input  int            prior = -1,
                       input  uvm_object     extension = null,
                       input  string         fname = "",
                       input  int            lineno = 0);

  virtual task mirror (output uvm_status_e  status,
                       input  uvm_check_e   check = UVM_NO_CHECK,
                       input  uvm_path_e    path = UVM_DEFAULT_PATH,
                       input  uvm_reg_map   map = null,
                       input  uvm_sequence_base parent = null,
                       input  int           prior = -1,
                       input  uvm_object    extension = null,
                       input  string        fname = "",
                       input  int           lineno = 0);

  virtual task update (output uvm_status_e  status,
                       input  uvm_path_e    path = UVM_DEFAULT_PATH,
                       input  uvm_reg_map   map = null,
                       input  uvm_sequence_base parent = null,
                       input  int           prior = -1,
                       input  uvm_object    extension = null,
                       input  string        fname = "",
                       input  int           lineno = 0);

  // Predict (update mirror without accessing DUT)
  function bit predict(uvm_reg_data_t value,
                       uvm_reg_byte_en_t be = -1,
                       uvm_predict_e kind = UVM_PREDICT_DIRECT,
                       uvm_path_e path = UVM_FRONTDOOR,
                       uvm_reg_map map = null,
                       string fname = "",
                       int lineno = 0);

  // Value access
  function uvm_reg_data_t get();
  function uvm_reg_data_t get_mirrored_value();
  function void            set(uvm_reg_data_t value);
  function void            reset(string kind = "HARD");

  // Fields
  function void get_fields(ref uvm_reg_field fields[$]);
  function uvm_reg_field get_field_by_name(string name);

  // Address
  function uvm_reg_addr_t get_address(uvm_reg_map map = null);
  function uvm_reg_addr_t get_offset (uvm_reg_map map = null);
  function int unsigned    get_n_bits();

  // HDL path for backdoor
  function void add_hdl_path_slice(string name, int offset, int size,
                                   bit first = 0, string kind = "RTL");
  function void add_hdl_path(uvm_hdl_path_concat slices[], string kind = "RTL");
endclass
```

### 10.4 uvm_reg_block

```systemverilog
class uvm_reg_block extends uvm_object;
  function new(string name = "", int has_coverage = UVM_NO_COVERAGE);

  function void configure(uvm_reg_block parent = null, string hdl_path = "");

  // Build (called after all registers, maps are created)
  virtual function void build();

  // Lock model (no further modifications)
  virtual function void lock_model();

  // Maps
  function uvm_reg_map create_map(string name,
                                   uvm_reg_addr_t base_addr,
                                   int unsigned n_bytes,
                                   uvm_endianness_e endian,
                                   bit byte_addressing = 1);
  function uvm_reg_map get_map_by_name(string name);
  function void        get_maps(ref uvm_reg_map maps[$]);
  function uvm_reg_map get_default_map();
  function void        set_default_map(uvm_reg_map map);

  // Reset
  virtual function void reset(string kind = "HARD");

  // Access
  function uvm_reg get_reg_by_name(string name);
  function void    get_registers(ref uvm_reg regs[$]);
  function uvm_mem get_mem_by_name(string name);
  function void    get_memories(ref uvm_mem mems[$]);
  function void    get_blocks(ref uvm_reg_block blks[$]);

  // HDL path
  function void add_hdl_path(string path, string kind = "RTL");
  function void set_hdl_path_root(string path, string kind = "RTL");
endclass
```

### 10.5 uvm_reg_map

```systemverilog
class uvm_reg_map extends uvm_object;
  function void configure(uvm_reg_block parent,
                          uvm_reg_addr_t base_addr,
                          int unsigned   n_bytes,
                          uvm_endianness_e endian,
                          bit byte_addressing = 1);

  // Add registers to map
  function void add_reg(uvm_reg rg,
                        uvm_reg_addr_t offset,
                        string rights = "RW",
                        bit unmapped = 0,
                        uvm_reg_frontdoor frontdoor = null);

  // Add memories to map
  function void add_mem(uvm_mem mem,
                        uvm_reg_addr_t offset,
                        string rights = "RW",
                        bit unmapped = 0,
                        uvm_reg_frontdoor frontdoor = null);

  // Add sub-map
  function void add_submap(uvm_reg_map child_map, uvm_reg_addr_t offset);

  // Sequencer connection
  function void set_sequencer(uvm_sequencer_base sequencer,
                              uvm_reg_adapter adapter);
  function uvm_sequencer_base get_sequencer();

  // Auto-predict (for simple environments without explicit predictor)
  function void set_auto_predict(bit on = 1);
  function bit  get_auto_predict();
endclass
```

### 10.6 Complete RAL Example

```systemverilog
//----------------------------------------------------------------------
// Register definitions
//----------------------------------------------------------------------
class ctrl_reg extends uvm_reg;
  `uvm_object_utils(ctrl_reg)

  rand uvm_reg_field enable;
  rand uvm_reg_field mode;
  rand uvm_reg_field irq_en;
  rand uvm_reg_field reserved;

  function new(string name = "ctrl_reg");
    super.new(name, 32, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    enable   = uvm_reg_field::type_id::create("enable");
    mode     = uvm_reg_field::type_id::create("mode");
    irq_en   = uvm_reg_field::type_id::create("irq_en");
    reserved = uvm_reg_field::type_id::create("reserved");

    enable.configure  (this, 1,  0,  "RW", 0, 1'h0,  1, 1, 0);
    mode.configure    (this, 2,  1,  "RW", 0, 2'h0,  1, 1, 0);
    irq_en.configure  (this, 1,  3,  "RW", 0, 1'h0,  1, 1, 0);
    reserved.configure(this, 28, 4,  "RO", 0, 28'h0, 1, 0, 0);
  endfunction
endclass

class status_reg extends uvm_reg;
  `uvm_object_utils(status_reg)

  rand uvm_reg_field busy;
  rand uvm_reg_field error;
  rand uvm_reg_field irq_pending;
  rand uvm_reg_field done_count;

  function new(string name = "status_reg");
    super.new(name, 32, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    busy        = uvm_reg_field::type_id::create("busy");
    error       = uvm_reg_field::type_id::create("error");
    irq_pending = uvm_reg_field::type_id::create("irq_pending");
    done_count  = uvm_reg_field::type_id::create("done_count");

    busy.configure       (this, 1,  0,  "RO",  1, 1'h0, 1, 0, 0);
    error.configure      (this, 1,  1,  "W1C", 1, 1'h0, 1, 1, 0);
    irq_pending.configure(this, 1,  2,  "RC",  1, 1'h0, 1, 0, 0);
    done_count.configure (this, 16, 16, "RO",  1, 16'h0, 1, 0, 0);
  endfunction
endclass

//----------------------------------------------------------------------
// Register block
//----------------------------------------------------------------------
class my_reg_block extends uvm_reg_block;
  `uvm_object_utils(my_reg_block)

  rand ctrl_reg   ctrl;
  rand status_reg status;
  uvm_reg_map     default_map;

  function new(string name = "my_reg_block");
    super.new(name, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    // Create registers
    ctrl   = ctrl_reg::type_id::create("ctrl");
    status = status_reg::type_id::create("status");

    // Build registers
    ctrl.configure(this, null, "");
    ctrl.build();
    status.configure(this, null, "");
    status.build();

    // Create address map
    default_map = create_map("default_map", 'h0, 4, UVM_LITTLE_ENDIAN, 1);
    default_map.add_reg(ctrl,   'h00, "RW");
    default_map.add_reg(status, 'h04, "RW");

    // HDL paths for backdoor access
    ctrl.add_hdl_path_slice("ctrl_reg", 0, 32);
    status.add_hdl_path_slice("status_reg", 0, 32);
    add_hdl_path("tb.dut.regs");

    lock_model();
  endfunction
endclass

//----------------------------------------------------------------------
// Register adapter (bus <-> register)
//----------------------------------------------------------------------
class my_reg_adapter extends uvm_reg_adapter;
  `uvm_object_utils(my_reg_adapter)

  function new(string name = "my_reg_adapter");
    super.new(name);
    supports_byte_enable = 0;
    provides_responses   = 1;
  endfunction

  virtual function uvm_sequence_item reg2bus(const ref uvm_reg_bus_op rw);
    my_transaction tr = my_transaction::type_id::create("tr");
    tr.addr  = rw.addr;
    tr.write = (rw.kind == UVM_WRITE);
    tr.data  = rw.data;
    return tr;
  endfunction

  virtual function void bus2reg(uvm_sequence_item bus_item, ref uvm_reg_bus_op rw);
    my_transaction tr;
    if (!$cast(tr, bus_item)) begin
      `uvm_fatal("CAST", "Failed to cast bus_item to my_transaction")
    end
    rw.addr   = tr.addr;
    rw.kind   = tr.write ? UVM_WRITE : UVM_READ;
    rw.data   = tr.write ? tr.data : tr.rdata;
    rw.status = tr.error ? UVM_NOT_OK : UVM_IS_OK;
  endfunction
endclass

//----------------------------------------------------------------------
// Register predictor
//----------------------------------------------------------------------
// Use uvm_reg_predictor to automatically update the register model
// based on observed bus transactions.

class my_env extends uvm_env;
  my_reg_block    reg_model;
  my_reg_adapter  adapter;
  uvm_reg_predictor #(my_transaction) predictor;

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    reg_model = my_reg_block::type_id::create("reg_model");
    reg_model.build();

    adapter   = my_reg_adapter::type_id::create("adapter");
    predictor = uvm_reg_predictor #(my_transaction)::type_id::create("predictor", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);

    reg_model.default_map.set_sequencer(agent.sequencer, adapter);

    // Connect predictor
    predictor.map     = reg_model.default_map;
    predictor.adapter = adapter;
    agent.monitor.analysis_port.connect(predictor.bus_in);
  endfunction
endclass

//----------------------------------------------------------------------
// Using RAL in sequences
//----------------------------------------------------------------------
class reg_test_sequence extends uvm_reg_sequence;
  `uvm_object_utils(reg_test_sequence)

  my_reg_block reg_model;

  function new(string name = "reg_test_sequence");
    super.new(name);
  endfunction

  virtual task body();
    uvm_status_e  status;
    uvm_reg_data_t value;

    // Write register
    reg_model.ctrl.write(status, 32'h0000_0007);
    if (status != UVM_IS_OK)
      `uvm_error("REG", "Write to ctrl register failed")

    // Read register
    reg_model.status.read(status, value);
    `uvm_info("REG", $sformatf("Status register = 0x%08h", value), UVM_LOW)

    // Mirror (read and check against expected)
    reg_model.status.mirror(status, UVM_CHECK);

    // Desired value manipulation
    reg_model.ctrl.set(32'h0000_000F);
    reg_model.ctrl.update(status);  // Write only if different from mirror

    // Field-level access
    reg_model.ctrl.enable.set(1);
    reg_model.ctrl.mode.set(2'b11);
    reg_model.ctrl.update(status);

    // Reset model
    reg_model.reset();

    // Built-in test sequences
    begin
      uvm_reg_hw_reset_seq rst_seq;
      rst_seq = uvm_reg_hw_reset_seq::type_id::create("rst_seq");
      rst_seq.model = reg_model;
      rst_seq.start(null);
    end

    begin
      uvm_reg_bit_bash_seq bash_seq;
      bash_seq = uvm_reg_bit_bash_seq::type_id::create("bash_seq");
      bash_seq.model = reg_model;
      bash_seq.start(null);
    end
  endtask
endclass
```

### 10.7 Built-in Register Test Sequences

| Sequence | Description |
|----------|-------------|
| uvm_reg_hw_reset_seq | Reads all registers, checks reset values |
| uvm_reg_bit_bash_seq | Writes walking 1/0 patterns to all RW fields |
| uvm_reg_access_seq | Tests front-door vs back-door access |
| uvm_reg_shared_access_seq | Tests shared access for multi-map registers |
| uvm_reg_mem_built_in_seq | Runs all built-in sequences |
| uvm_reg_mem_shared_access_seq | Shared memory access tests |
| uvm_mem_walk_seq | Walking 1/0 memory test |
| uvm_mem_access_seq | Memory access test |

---

## 11. UVM Callbacks

### 11.1 Callback Mechanism

Callbacks provide a way to inject custom behavior into existing components
without modifying the component code.

```systemverilog
//----------------------------------------------------------------------
// Define callback class
//----------------------------------------------------------------------
class my_driver_callback extends uvm_callback;
  `uvm_object_utils(my_driver_callback)

  function new(string name = "my_driver_callback");
    super.new(name);
  endfunction

  // Virtual methods to be overridden
  virtual task pre_drive(my_driver drv, my_transaction tr);
  endtask

  virtual task post_drive(my_driver drv, my_transaction tr);
  endtask

  virtual function void modify_transaction(my_driver drv, ref my_transaction tr);
  endfunction
endclass

//----------------------------------------------------------------------
// Register callback type with component
//----------------------------------------------------------------------
typedef uvm_callbacks #(my_driver, my_driver_callback) my_driver_cb;

class my_driver extends uvm_driver #(my_transaction);
  `uvm_component_utils(my_driver)
  `uvm_register_cb(my_driver, my_driver_callback)

  task run_phase(uvm_phase phase);
    my_transaction tr;
    forever begin
      seq_item_port.get_next_item(tr);

      // Invoke pre_drive callbacks
      `uvm_do_callbacks(my_driver, my_driver_callback, pre_drive(this, tr))

      drive_transaction(tr);

      // Invoke post_drive callbacks
      `uvm_do_callbacks(my_driver, my_driver_callback, post_drive(this, tr))

      seq_item_port.item_done();
    end
  endtask
endclass

//----------------------------------------------------------------------
// Implement specific callback
//----------------------------------------------------------------------
class error_inject_callback extends my_driver_callback;
  `uvm_object_utils(error_inject_callback)

  int error_rate = 10;  // 10% error injection

  function new(string name = "error_inject_callback");
    super.new(name);
  endfunction

  virtual function void modify_transaction(my_driver drv, ref my_transaction tr);
    if ($urandom_range(99) < error_rate) begin
      tr.data = $urandom();
      `uvm_info("CB", "Injected error into transaction", UVM_MEDIUM)
    end
  endfunction
endclass

//----------------------------------------------------------------------
// Add callback in test
//----------------------------------------------------------------------
class error_inject_test extends base_test;
  `uvm_component_utils(error_inject_test)

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    begin
      error_inject_callback cb = error_inject_callback::type_id::create("cb");
      cb.error_rate = 20;
      uvm_callbacks #(my_driver, my_driver_callback)::add(env.agent.driver, cb);
    end
  endfunction
endclass
```

### 11.2 Sequence Callbacks

```systemverilog
class my_sequence extends uvm_sequence #(my_transaction);
  `uvm_object_utils(my_sequence)

  virtual task pre_body();
    // Called before body() executes
    `uvm_info("SEQ", "pre_body", UVM_HIGH)
  endtask

  virtual task body();
    // Main sequence logic
  endtask

  virtual task post_body();
    // Called after body() completes
    `uvm_info("SEQ", "post_body", UVM_HIGH)
  endtask

  virtual task pre_start();
    // Called before sequence starts (always called, even if call_pre_post=0)
    `uvm_info("SEQ", "pre_start", UVM_HIGH)
  endtask

  virtual task post_start();
    // Called after sequence completes (always called)
    `uvm_info("SEQ", "post_start", UVM_HIGH)
  endtask

  virtual function void pre_do(bit is_item);
    // Called after item is randomized, before sending to driver
    // is_item = 1 for items, 0 for sub-sequences
  endfunction

  virtual function void mid_do(uvm_sequence_item this_item);
    // Called after start_item returns, before finish_item sends to driver
  endfunction

  virtual function void post_do(uvm_sequence_item this_item);
    // Called after item_done from driver
  endfunction
endclass
```

---

## 12. UVM Reporting

### 12.1 Severity Levels

| Severity | Macro | Default Action |
|----------|-------|----------------|
| UVM_INFO | `uvm_info | Display |
| UVM_WARNING | `uvm_warning | Display |
| UVM_ERROR | `uvm_error | Display, count |
| UVM_FATAL | `uvm_fatal | Display, exit |

### 12.2 Verbosity Levels

| Level | Value | Description |
|-------|-------|-------------|
| UVM_NONE | 0 | Always printed |
| UVM_LOW | 100 | Low verbosity |
| UVM_MEDIUM | 200 | Medium verbosity (default) |
| UVM_HIGH | 300 | High verbosity |
| UVM_FULL | 400 | Full verbosity |
| UVM_DEBUG | 500 | Debug verbosity |

### 12.3 Reporting Macros

```systemverilog
// Basic reporting
`uvm_info("TAG", "message", UVM_MEDIUM)
`uvm_warning("TAG", "warning message")
`uvm_error("TAG", "error message")
`uvm_fatal("TAG", "fatal message")

// Context-aware (includes component hierarchy)
`uvm_info_context("TAG", "message", UVM_MEDIUM, comp)
`uvm_warning_context("TAG", "message", comp)
`uvm_error_context("TAG", "message", comp)
`uvm_fatal_context("TAG", "message", comp)

// Conditional
`uvm_info_begin("TAG", "message", UVM_MEDIUM)
`uvm_message_add_tag("field", "value")
`uvm_message_add_int(value, radix)
`uvm_message_add_string(value)
`uvm_message_add_object(obj)
`uvm_info_end
```

### 12.4 Controlling Reporting

```systemverilog
// Set verbosity for all components
uvm_top.set_report_verbosity_level_hier(UVM_HIGH);

// Set verbosity for specific component hierarchy
env.agent.monitor.set_report_verbosity_level(UVM_FULL);

// Set verbosity for specific message ID
env.set_report_id_verbosity("SCBD", UVM_DEBUG);

// Change severity action
// Actions: UVM_NO_ACTION, UVM_DISPLAY, UVM_LOG, UVM_COUNT, UVM_EXIT, UVM_CALL_HOOK, UVM_STOP
env.set_report_severity_action(UVM_ERROR, UVM_DISPLAY | UVM_COUNT | UVM_STOP);

// Change action for specific ID
env.set_report_id_action("TIMEOUT", UVM_DISPLAY | UVM_EXIT);

// Severity override (downgrade/upgrade)
env.set_report_severity_id_override(UVM_ERROR, "EXPECTED_ERR", UVM_WARNING);

// Max quit count (errors before exit)
uvm_report_server server = uvm_report_server::get_server();
server.set_max_quit_count(10);

// Get error/warning counts
int err_count = server.get_severity_count(UVM_ERROR);
int warn_count = server.get_severity_count(UVM_WARNING);

// File logging
UVM_FILE log_file;
log_file = $fopen("sim.log", "w");
env.set_report_default_file(log_file);
env.set_report_severity_action(UVM_INFO, UVM_DISPLAY | UVM_LOG);

// Demote errors to warnings
env.set_report_severity_override(UVM_ERROR, UVM_WARNING);

// From command line
// +UVM_VERBOSITY=UVM_HIGH
// +uvm_set_verbosity=<comp>,<id>,<verbosity>,<phase>
// +uvm_set_action=<comp>,<id>,<severity>,<action>
// +uvm_set_severity=<comp>,<id>,<current_severity>,<new_severity>
```

### 12.5 Custom Report Server

```systemverilog
class my_report_server extends uvm_report_server;
  virtual function string compose_report_message(
    uvm_report_message report_message,
    string report_object_name = ""
  );
    string severity_str;
    string time_str;

    case (report_message.get_severity())
      UVM_INFO:    severity_str = "INFO";
      UVM_WARNING: severity_str = "WARN";
      UVM_ERROR:   severity_str = "ERROR";
      UVM_FATAL:   severity_str = "FATAL";
    endcase

    $sformat(time_str, "%0t", $time);

    return $sformatf("[%s][%s][%s][%s] %s",
                     time_str,
                     severity_str,
                     report_message.get_id(),
                     report_message.get_context(),
                     report_message.get_message());
  endfunction
endclass

// Install custom server
initial begin
  my_report_server server = new;
  uvm_report_server::set_server(server);
end
```

---

## 13. UVM Configuration Database

### 13.1 uvm_config_db

The configuration database is a type-parameterized interface for setting and
getting configuration values across the testbench hierarchy.

```systemverilog
class uvm_config_db #(type T = int) extends uvm_resource_db #(T);

  // Set a value
  static function void set(uvm_component cntxt,
                           string        inst_name,
                           string        field_name,
                           T             value);

  // Get a value
  static function bit get(uvm_component cntxt,
                           string        inst_name,
                           string        field_name,
                           ref T         value);

  // Check if a value exists
  static function bit exists(uvm_component cntxt,
                              string        inst_name,
                              string        field_name,
                              bit           spell_chk = 0);

  // Wait for a value to be set
  static task wait_modified(uvm_component cntxt,
                            string        inst_name,
                            string        field_name);
endclass
```

### 13.2 Usage Patterns

```systemverilog
//----------------------------------------------------------------------
// Setting values (typically in test or top-level)
//----------------------------------------------------------------------

// Virtual interface
uvm_config_db #(virtual my_if)::set(null, "uvm_test_top.env.agent*", "vif", vif);

// Integer values
uvm_config_db #(int)::set(null, "uvm_test_top.env.agent", "num_transactions", 100);

// Enum values
uvm_config_db #(uvm_active_passive_enum)::set(this, "agent", "is_active", UVM_ACTIVE);

// Configuration objects
uvm_config_db #(my_agent_config)::set(this, "agent", "cfg", agent_cfg);

// Strings
uvm_config_db #(string)::set(null, "*", "test_name", "basic_test");

// Bit vectors
uvm_config_db #(bit [31:0])::set(this, "agent.driver", "base_addr", 32'h1000_0000);

//----------------------------------------------------------------------
// Getting values (typically in build_phase)
//----------------------------------------------------------------------

// Virtual interface
virtual my_if vif;
if (!uvm_config_db #(virtual my_if)::get(this, "", "vif", vif))
  `uvm_fatal("NOVIF", {"Virtual interface not found for: ", get_full_name()})

// Integer values
int num_tr;
if (!uvm_config_db #(int)::get(this, "", "num_transactions", num_tr))
  num_tr = 10;  // default

// Configuration objects
my_agent_config cfg;
if (!uvm_config_db #(my_agent_config)::get(this, "", "cfg", cfg))
  `uvm_fatal("NOCFG", "Configuration not found")
```

### 13.3 Scope Resolution

The context (cntxt) and instance name (inst_name) together form the hierarchical
path. The rules are:

```
set(cntxt, inst_name, field_name, value)
  Effective path = cntxt.get_full_name() + "." + inst_name

get(cntxt, inst_name, field_name, value)
  Effective path = cntxt.get_full_name() + "." + inst_name

// Examples:
// In test (uvm_test_top):
set(this, "env.agent", "cfg", cfg);        // path = "uvm_test_top.env.agent"
set(this, "env.agent*", "vif", vif);       // path = "uvm_test_top.env.agent*" (wildcard)
set(null, "uvm_test_top.env.*", "x", 5);   // path = "uvm_test_top.env.*" (from top)

// In env (uvm_test_top.env):
set(this, "agent", "cfg", cfg);            // path = "uvm_test_top.env.agent"

// In agent (uvm_test_top.env.agent):
get(this, "", "cfg", cfg);                 // path = "uvm_test_top.env.agent"
get(this, "", "vif", vif);                 // path = "uvm_test_top.env.agent"
```

### 13.4 Precedence Rules

1. Last set wins for same scope level.
2. More specific scope wins over less specific (exact path beats wildcard).
3. Component context set beats null context set for same path.

### 13.5 Debug

```systemverilog
// Command line: dump config_db at end of build phase
// +UVM_CONFIG_DB_TRACE

// In code
uvm_config_db #(int)::set(this, "agent", "x", 5);
// Prints: UVM_INFO ... config_db: set(uvm_test_top, agent, x, 5)

// Dump all resources
uvm_resource_db #(int)::dump();
```

---

## 14. UVM Objections

### 14.1 Objection Mechanism

Objections control when phases (especially task phases like run_phase) complete.
A phase does not end until all raised objections are dropped.

```systemverilog
class uvm_objection extends uvm_object;

  // Raise an objection (prevent phase from ending)
  virtual function void raise_objection(uvm_object obj = null,
                                        string description = "",
                                        int count = 1);

  // Drop an objection (allow phase to end when all dropped)
  virtual function void drop_objection(uvm_object obj = null,
                                       string description = "",
                                       int count = 1);

  // Set drain time (delay after last objection drop before phase ends)
  function void set_drain_time(uvm_object obj = null, time drain);

  // Get current count
  function int get_objection_count(uvm_object obj = null);
  function int get_objection_total(uvm_object obj = null);

  // Callbacks
  virtual function void raised  (uvm_object obj, uvm_object source_obj, string description, int count);
  virtual function void dropped (uvm_object obj, uvm_object source_obj, string description, int count);
  virtual task          all_dropped(uvm_object obj, uvm_object source_obj, string description, int count);
endclass
```

### 14.2 Usage Patterns

```systemverilog
// Basic usage in run_phase
task run_phase(uvm_phase phase);
  phase.raise_objection(this, "Starting test");
  // ... test activity ...
  phase.drop_objection(this, "Test complete");
endtask

// In sequences (through starting_phase)
class my_sequence extends uvm_sequence #(my_transaction);
  task body();
    // Raise objection at start
    if (starting_phase != null)
      starting_phase.raise_objection(this);

    // ... sequence activity ...

    // Drop at end
    if (starting_phase != null)
      starting_phase.drop_objection(this);
  endtask
endclass

// In test
task run_phase(uvm_phase phase);
  my_sequence seq = my_sequence::type_id::create("seq");
  seq.starting_phase = phase;
  seq.start(env.agent.sequencer);
endtask

// Set drain time
function void build_phase(uvm_phase phase);
  super.build_phase(phase);
  uvm_phase run_ph = uvm_run_phase::get();
  run_ph.get_objection().set_drain_time(this, 100ns);
endfunction
```

### 14.3 Objection Debug

```systemverilog
// Command line
// +UVM_OBJECTION_TRACE

// In code: set objection trace on specific phase
uvm_phase run_ph = uvm_run_phase::get();
run_ph.get_objection().set_report_verbosity_level(UVM_FULL);
```

---

## 15. TLM (Transaction Level Modeling)

### 15.1 TLM Port Types

| Type | Description | Directionality |
|------|-------------|----------------|
| uvm_*_port | Initiates transactions | Producer -> Consumer |
| uvm_*_export | Intermediate connection | Forwarding |
| uvm_*_imp | Provides implementation | Terminal (has write/get/put) |

### 15.2 TLM1 Interfaces

```systemverilog
// Put interface (producer pushes to consumer)
uvm_put_port       #(T)
uvm_put_export     #(T)
uvm_put_imp        #(T, IMP)

// Get interface (consumer pulls from producer)
uvm_get_port       #(T)
uvm_get_export     #(T)
uvm_get_imp        #(T, IMP)

// Get-Peek interface
uvm_get_peek_port  #(T)
uvm_get_peek_export#(T)
uvm_get_peek_imp   #(T, IMP)

// Blocking/Non-blocking variants
uvm_blocking_put_port       #(T)
uvm_nonblocking_put_port    #(T)
uvm_blocking_get_port       #(T)
uvm_nonblocking_get_port    #(T)
uvm_blocking_get_peek_port  #(T)
uvm_nonblocking_get_peek_port#(T)

// Analysis (1-to-many broadcast)
uvm_analysis_port   #(T)     // Broadcast to all connected
uvm_analysis_export #(T)     // Intermediate
uvm_analysis_imp    #(T, IMP)// Terminal
```

### 15.3 TLM FIFOs

```systemverilog
// Standard TLM FIFO
uvm_tlm_fifo #(T) fifo;
fifo = new("fifo", this, 16);  // depth = 16 (0 = unbounded)

// Analysis FIFO (has analysis_export for connection to analysis_port)
uvm_tlm_analysis_fifo #(T) afifo;
afifo = new("afifo", this);

// FIFO methods
task          put(T t);         // blocking put
function bit  try_put(T t);     // non-blocking put
function bit  can_put();        // check if FIFO has space
task          get(output T t);  // blocking get
function bit  try_get(output T t);// non-blocking get
function bit  can_get();        // check if FIFO has data
task          peek(output T t); // blocking peek (no remove)
function bit  try_peek(output T t);// non-blocking peek
function bit  can_peek();
function int  used();           // items in FIFO
function bit  is_empty();
function bit  is_full();
function int  size();           // max depth
function void flush();          // remove all items
```

### 15.4 TLM Connection Examples

```systemverilog
// Direct connection: port -> imp
class producer extends uvm_component;
  uvm_blocking_put_port #(my_transaction) put_port;

  function void build_phase(uvm_phase phase);
    put_port = new("put_port", this);
  endfunction

  task run_phase(uvm_phase phase);
    my_transaction tr = new("tr");
    put_port.put(tr);
  endtask
endclass

class consumer extends uvm_component;
  uvm_blocking_put_imp #(my_transaction, consumer) put_imp;

  function void build_phase(uvm_phase phase);
    put_imp = new("put_imp", this);
  endfunction

  task put(my_transaction tr);
    // Process transaction
  endtask
endclass

// In env connect_phase:
producer_inst.put_port.connect(consumer_inst.put_imp);

// Through FIFO
producer_inst.put_port.connect(fifo.put_export);
consumer_inst.get_port.connect(fifo.get_export);

// Analysis broadcast
monitor.analysis_port.connect(scoreboard.analysis_export);
monitor.analysis_port.connect(coverage.analysis_export);
monitor.analysis_port.connect(logger.analysis_export);
```

---

## 16. UVM Test and Top Module

### 16.1 Base Test

```systemverilog
class base_test extends uvm_test;
  `uvm_component_utils(base_test)

  my_env env;
  my_env_config env_cfg;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    // Build configuration
    env_cfg = my_env_config::type_id::create("env_cfg");
    configure_env(env_cfg);
    uvm_config_db #(my_env_config)::set(this, "env", "cfg", env_cfg);

    // Create environment
    env = my_env::type_id::create("env", this);
  endfunction

  virtual function void configure_env(my_env_config cfg);
    cfg.agent_cfg.is_active = UVM_ACTIVE;
    cfg.has_coverage = 1;
  endfunction

  virtual function void end_of_elaboration_phase(uvm_phase phase);
    super.end_of_elaboration_phase(phase);
    uvm_top.print_topology();
  endfunction

  virtual task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    phase.drop_objection(this);
  endtask

  function void report_phase(uvm_phase phase);
    uvm_report_server server = uvm_report_server::get_server();
    if (server.get_severity_count(UVM_ERROR) > 0 ||
        server.get_severity_count(UVM_FATAL) > 0)
      `uvm_info("TEST", "*** TEST FAILED ***", UVM_NONE)
    else
      `uvm_info("TEST", "*** TEST PASSED ***", UVM_NONE)
  endfunction
endclass
```

### 16.2 Specific Test

```systemverilog
class write_read_test extends base_test;
  `uvm_component_utils(write_read_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    write_read_sequence seq;
    phase.raise_objection(this);

    seq = write_read_sequence::type_id::create("seq");
    seq.start(env.agent.sequencer);

    phase.drop_objection(this);
  endtask
endclass

class random_test extends base_test;
  `uvm_component_utils(random_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void configure_env(my_env_config cfg);
    super.configure_env(cfg);
    cfg.num_transactions = 1000;
  endfunction

  task run_phase(uvm_phase phase);
    random_sequence seq;
    phase.raise_objection(this);

    seq = random_sequence::type_id::create("seq");
    seq.num_transactions = env_cfg.num_transactions;
    seq.start(env.agent.sequencer);

    phase.drop_objection(this);
  endtask
endclass
```

### 16.3 Top Module

```systemverilog
module tb_top;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  // Import test package
  import my_test_pkg::*;

  // Clock and reset
  logic clk, rst_n;

  initial begin
    clk = 0;
    forever #5ns clk = ~clk;
  end

  initial begin
    rst_n = 0;
    #100ns rst_n = 1;
  end

  // DUT interface
  my_if dut_if(.clk(clk), .rst_n(rst_n));

  // DUT instantiation
  my_dut dut(
    .clk    (dut_if.clk),
    .rst_n  (dut_if.rst_n),
    .addr   (dut_if.addr),
    .wdata  (dut_if.wdata),
    .rdata  (dut_if.rdata),
    .write  (dut_if.write),
    .valid  (dut_if.valid),
    .ready  (dut_if.ready),
    .error  (dut_if.error)
  );

  // Interface binding
  initial begin
    uvm_config_db #(virtual my_if)::set(null, "uvm_test_top.*", "vif", dut_if);
  end

  // Start test
  initial begin
    run_test();  // Test name from +UVM_TESTNAME=write_read_test
  end

  // Waveform dump
  initial begin
    $fsdbDumpfile("waves.fsdb");
    $fsdbDumpvars(0, tb_top);
  end

  // Timeout
  initial begin
    #10ms;
    `uvm_fatal("TIMEOUT", "Simulation timed out")
  end
endmodule
```

### 16.4 Command-Line Arguments

```
# Run specific test
+UVM_TESTNAME=write_read_test

# Set verbosity
+UVM_VERBOSITY=UVM_HIGH

# Set timeout
+UVM_TIMEOUT=1000000,YES

# Max errors before quit
+UVM_MAX_QUIT_COUNT=10,YES

# Config DB trace
+UVM_CONFIG_DB_TRACE

# Objection trace
+UVM_OBJECTION_TRACE

# Phase trace
+UVM_PHASE_TRACE

# Random seed
+ntb_random_seed=12345
+UVM_SEED=12345

# Set config values
+uvm_set_config_int=*,num_transactions,100
+uvm_set_config_string=*,test_mode,stress

# Verbosity per component/ID
+uvm_set_verbosity=uvm_test_top.env.agent.monitor,MON,UVM_DEBUG,time,0
```

---

## 17. Advanced Patterns

### 17.1 Layered Sequences (Protocol Layering)

```systemverilog
// Upper layer sequence item
class ethernet_frame extends uvm_sequence_item;
  rand bit [47:0] dst_mac;
  rand bit [47:0] src_mac;
  rand bit [15:0] etype;
  rand byte       payload[];
  // ...
endclass

// Lower layer sequence item
class phy_word extends uvm_sequence_item;
  rand bit [7:0] data;
  rand bit       valid;
  // ...
endclass

// Translation sequence (runs on lower-layer sequencer)
class eth_to_phy_sequence extends uvm_sequence #(phy_word);
  uvm_sequencer #(ethernet_frame) upper_sqr;

  task body();
    ethernet_frame frame;
    phy_word word;

    forever begin
      upper_sqr.get_next_item(frame);

      // Preamble
      repeat(7) begin
        word = phy_word::type_id::create("word");
        start_item(word);
        word.data  = 8'h55;
        word.valid = 1;
        finish_item(word);
      end

      // SFD
      word = phy_word::type_id::create("word");
      start_item(word);
      word.data = 8'hD5;
      word.valid = 1;
      finish_item(word);

      // Frame data
      // ... translate frame fields to phy words ...

      upper_sqr.item_done();
    end
  endtask
endclass
```

### 17.2 Register Backdoor Access

```systemverilog
class my_reg_backdoor extends uvm_reg_backdoor;
  `uvm_object_utils(my_reg_backdoor)

  function new(string name = "my_reg_backdoor");
    super.new(name);
  endfunction

  virtual task write(uvm_reg_item rw);
    // Direct HDL access
    case (rw.offset)
      0: force tb.dut.regs.ctrl_reg   = rw.value[0];
      4: force tb.dut.regs.status_reg = rw.value[0];
    endcase
    @(posedge tb.dut.clk);
    case (rw.offset)
      0: release tb.dut.regs.ctrl_reg;
      4: release tb.dut.regs.status_reg;
    endcase
    rw.status = UVM_IS_OK;
  endtask

  virtual task read(uvm_reg_item rw);
    case (rw.offset)
      0: rw.value[0] = tb.dut.regs.ctrl_reg;
      4: rw.value[0] = tb.dut.regs.status_reg;
    endcase
    rw.status = UVM_IS_OK;
  endtask
endclass
```

### 17.3 Out-of-Order Scoreboard with Associative Array

```systemverilog
class ooo_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(ooo_scoreboard)

  // Associative array keyed by transaction ID
  my_transaction expected_aa[int];

  `uvm_analysis_imp_decl(_expected)
  `uvm_analysis_imp_decl(_actual)

  uvm_analysis_imp_expected #(my_transaction, ooo_scoreboard) expected_imp;
  uvm_analysis_imp_actual   #(my_transaction, ooo_scoreboard) actual_imp;

  function void write_expected(my_transaction tr);
    expected_aa[tr.id] = tr;
  endfunction

  function void write_actual(my_transaction tr);
    if (expected_aa.exists(tr.id)) begin
      if (!tr.compare(expected_aa[tr.id]))
        `uvm_error("SCBD", $sformatf("Mismatch for ID %0d", tr.id))
      expected_aa.delete(tr.id);
    end else begin
      `uvm_error("SCBD", $sformatf("Unexpected transaction ID %0d", tr.id))
    end
  endfunction

  function void check_phase(uvm_phase phase);
    if (expected_aa.size() > 0) begin
      foreach (expected_aa[i])
        `uvm_error("SCBD", $sformatf("Expected ID %0d never received", i))
    end
  endfunction
endclass
```

### 17.4 Phase-Aware Sequence

```systemverilog
class reset_sequence extends uvm_sequence #(my_transaction);
  `uvm_object_utils(reset_sequence)

  function new(string name = "reset_sequence");
    super.new(name);
  endfunction

  task body();
    // This sequence is designed for the reset_phase
    if (starting_phase != null)
      starting_phase.raise_objection(this, "Reset sequence started");

    `uvm_info("SEQ", "Driving reset", UVM_LOW)
    // ... reset stimulus ...

    if (starting_phase != null)
      starting_phase.drop_objection(this, "Reset sequence complete");
  endtask
endclass

// Default sequence assignment for a phase
class my_test extends base_test;
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    uvm_config_db #(uvm_object_wrapper)::set(this,
      "env.agent.sequencer.reset_phase",
      "default_sequence",
      reset_sequence::type_id::get());

    uvm_config_db #(uvm_object_wrapper)::set(this,
      "env.agent.sequencer.main_phase",
      "default_sequence",
      main_sequence::type_id::get());
  endfunction
endclass
```

---

## 18. Common Patterns and Best Practices

### 18.1 Interface and Modport

```systemverilog
interface my_if(input logic clk, input logic rst_n);
  logic [31:0] addr;
  logic [31:0] wdata;
  logic [31:0] rdata;
  logic        write;
  logic        valid;
  logic        ready;
  logic        error;

  // Driver modport
  modport driver_mp(
    input  clk, rst_n, ready, rdata, error,
    output addr, wdata, write, valid
  );

  // Monitor modport
  modport monitor_mp(
    input clk, rst_n, addr, wdata, rdata, write, valid, ready, error
  );

  // Clocking blocks
  clocking driver_cb @(posedge clk);
    default input #1ns output #1ns;
    output addr, wdata, write, valid;
    input  ready, rdata, error;
  endclocking

  clocking monitor_cb @(posedge clk);
    default input #1ns;
    input addr, wdata, rdata, write, valid, ready, error;
  endclocking

  // Assertions
  property p_valid_stable;
    @(posedge clk) disable iff (!rst_n)
    valid && !ready |=> $stable(addr) && $stable(wdata) && $stable(write) && valid;
  endproperty
  assert property(p_valid_stable) else
    $error("Protocol violation: signals must be stable while valid && !ready");
endinterface
```

### 18.2 Package Organization

```systemverilog
package my_test_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  // Types and enums
  `include "my_types.svh"

  // Transaction
  `include "my_transaction.sv"

  // Agent components
  `include "my_driver.sv"
  `include "my_monitor.sv"
  `include "my_sequencer.sv"
  `include "my_agent_config.sv"
  `include "my_agent.sv"

  // Coverage
  `include "my_coverage.sv"

  // Scoreboard
  `include "my_scoreboard.sv"

  // Environment
  `include "my_env_config.sv"
  `include "my_env.sv"

  // Sequences
  `include "my_base_sequence.sv"
  `include "my_write_sequence.sv"
  `include "my_read_sequence.sv"
  `include "my_random_sequence.sv"
  `include "my_virtual_sequence.sv"

  // Register model
  `include "my_reg_model.sv"
  `include "my_reg_adapter.sv"

  // Tests
  `include "base_test.sv"
  `include "write_read_test.sv"
  `include "random_test.sv"
  `include "register_test.sv"
endpackage
```

### 18.3 Parameterized Components

```systemverilog
class generic_driver #(type T = uvm_sequence_item, int WIDTH = 32)
  extends uvm_driver #(T);

  typedef generic_driver #(T, WIDTH) this_type;
  `uvm_component_param_utils(this_type)

  virtual generic_if #(WIDTH) vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    T tr;
    forever begin
      seq_item_port.get_next_item(tr);
      drive(tr);
      seq_item_port.item_done();
    end
  endtask

  virtual task drive(T tr);
    // Override in derived class
  endtask
endclass
```

### 18.4 Heartbeat Monitor

```systemverilog
class heartbeat_monitor extends uvm_component;
  `uvm_component_utils(heartbeat_monitor)

  uvm_heartbeat hb;
  uvm_event     hb_event;
  time          timeout_val = 1000ns;
  uvm_component comps_to_watch[$];

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    hb_event = new("hb_event");
    hb = new("hb", this, hb_event);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    foreach (comps_to_watch[i])
      hb.add(comps_to_watch[i]);
    hb.set_mode(UVM_ANY_ACTIVE);  // At least one must be active
  endfunction

  task run_phase(uvm_phase phase);
    hb.start(hb_event);
    forever begin
      #timeout_val;
      hb_event.trigger();
    end
  endtask
endclass
```

---

## 19. UVM Macros Quick Reference

| Macro | Description |
|-------|-------------|
| `uvm_component_utils(T) | Register component with factory |
| `uvm_object_utils(T) | Register object with factory |
| `uvm_component_param_utils(T) | Register parameterized component |
| `uvm_object_param_utils(T) | Register parameterized object |
| `uvm_info(ID, MSG, VERB) | Info message |
| `uvm_warning(ID, MSG) | Warning message |
| `uvm_error(ID, MSG) | Error message |
| `uvm_fatal(ID, MSG) | Fatal message |
| `uvm_do(SEQ_OR_ITEM) | Create, randomize, send |
| `uvm_do_with(SEQ_OR_ITEM, CONSTR) | Create, randomize with constraints, send |
| `uvm_do_on(SEQ_OR_ITEM, SQR) | Create, randomize, send on specific sequencer |
| `uvm_do_on_with(SEQ_OR_ITEM, SQR, CONSTR) | As above with constraints |
| `uvm_create(SEQ_OR_ITEM) | Create via factory |
| `uvm_send(SEQ_OR_ITEM) | Send pre-created item |
| `uvm_rand_send(SEQ_OR_ITEM) | Randomize and send |
| `uvm_rand_send_with(SEQ_OR_ITEM, CONSTR) | Randomize with constraints and send |
| `uvm_declare_p_sequencer(SQR_TYPE) | Declare p_sequencer handle |
| `uvm_register_cb(T, CB) | Register callback type |
| `uvm_do_callbacks(T, CB, METHOD) | Invoke callbacks |
| `uvm_analysis_imp_decl(_SUFFIX) | Declare analysis imp with suffix |
| `uvm_field_int(ARG, FLAG) | Field automation for int |
| `uvm_field_string(ARG, FLAG) | Field automation for string |
| `uvm_field_object(ARG, FLAG) | Field automation for object |
| `uvm_field_enum(T, ARG, FLAG) | Field automation for enum |
| `uvm_field_array_int(ARG, FLAG) | Field automation for int array |
| `uvm_field_queue_int(ARG, FLAG) | Field automation for int queue |
| `uvm_field_sarray_int(ARG, FLAG) | Field automation for static int array |
| `uvm_field_aa_int_string(ARG, FLAG) | Field automation for assoc array |
| `uvm_pack_int(VAR) | Pack integer |
| `uvm_pack_string(VAR) | Pack string |
| `uvm_unpack_int(VAR) | Unpack integer |
| `uvm_unpack_string(VAR) | Unpack string |

---

## 20. UVM 1.2 to IEEE 1800.2 Migration Notes

| UVM 1.2 | IEEE 1800.2 | Notes |
|----------|-------------|-------|
| uvm_sequence_base::starting_phase | set_starting_phase() / get_starting_phase() | Deprecation |
| Field automation macros | do_copy, do_compare, do_print, do_pack | Performance |
| uvm_config_db (unchanged) | uvm_config_db (unchanged) | Compatible |
| uvm_report_server (custom) | uvm_default_report_server | Refactored |
| set_config_* methods | uvm_config_db::set | Deprecated |
| uvm_packer (32-bit packing) | uvm_packer (abstract) | Refactored |
| `uvm_do macros | start_item/finish_item | Recommended |
| uvm_reg_bit_bash_seq | uvm_reg_bit_bash_seq (unchanged) | Compatible |

---
