# Verification IP (VIP) Integration Guide

Comprehensive guide for selecting, integrating, configuring, and using
Verification IPs for protocol verification in UVM testbenches.

---

## 1. VIP Architecture Overview

### 1.1 Standard VIP Components

A production Verification IP typically includes:

```
VIP Package
  +-- Agent
  |     +-- Sequencer
  |     +-- Driver (Master / Slave / Monitor)
  |     +-- Monitor
  |     +-- Coverage Collector
  |     +-- Protocol Checker (Assertions)
  +-- Sequences
  |     +-- Base Sequence
  |     +-- Configuration Sequences
  |     +-- Traffic Sequences
  |     +-- Error Sequences
  |     +-- Built-in Test Sequences
  +-- Configuration Object
  +-- Transaction Classes
  +-- Interface Definition
  +-- Documentation
```

### 1.2 VIP Operating Modes

| Mode | Description | Use Case |
|------|-------------|----------|
| Master/Active | Drives transactions to DUT | DUT is slave |
| Slave/Reactive | Responds to DUT requests | DUT is master |
| Monitor/Passive | Observes traffic only | Passive checking |
| Protocol Checker | Assertion-based checking | Always-on checking |

### 1.3 VIP Data Flow

```
Master Mode:                    Slave Mode:
===========                    ===========

  Sequence                       DUT
     |                            |
  Sequencer                    Interface
     |                            |
  Driver -----> Interface     Monitor ----> Sequencer
     |              |             |              |
  Monitor <---- Interface     Driver <---- Sequence
     |                            |
  Analysis Port              Analysis Port
     |                            |
  Scoreboard/Coverage       Scoreboard/Coverage
```

---

## 2. Protocol VIPs

### 2.1 AXI4 VIP

**Protocol Overview:**

AXI4 (Advanced eXtensible Interface) is an AMBA bus protocol supporting
high-performance, high-frequency system designs.

**AXI4 Channels:**

| Channel | Direction (Master view) | Purpose |
|---------|----------------------|---------|
| AW (Write Address) | Master -> Slave | Write address and control |
| W (Write Data) | Master -> Slave | Write data |
| B (Write Response) | Slave -> Master | Write response |
| AR (Read Address) | Master -> Slave | Read address and control |
| R (Read Data) | Slave -> Master | Read data and response |

**AXI4 Transaction Fields:**

```systemverilog
class axi4_transaction extends uvm_sequence_item;
  // Address channel
  rand bit [AXI_ADDR_W-1:0]  addr;
  rand axi_burst_type_e       burst;     // FIXED, INCR, WRAP
  rand bit [7:0]               len;       // Burst length (0-255 = 1-256 beats)
  rand bit [2:0]               size;      // Beat size (0-7 = 1-128 bytes)
  rand bit [AXI_ID_W-1:0]     id;
  rand axi_lock_e              lock;      // NORMAL, EXCLUSIVE
  rand bit [3:0]               cache;     // Cache attributes
  rand bit [2:0]               prot;      // Protection
  rand bit [3:0]               qos;       // Quality of service
  rand bit [3:0]               region;    // Region identifier

  // Data
  rand bit [AXI_DATA_W-1:0]   data[];    // Data array (len+1 entries)
  rand bit [AXI_STRB_W-1:0]   strb[];    // Write strobes

  // Response
  axi_resp_e                    resp[];    // Response per beat
  axi_resp_e                    bresp;     // Write response

  // Direction
  rand axi_rw_e                rw;        // READ or WRITE
endclass
```

**AXI4 VIP Configuration:**

```systemverilog
class axi4_vip_config extends uvm_object;
  // Interface parameters
  int unsigned addr_width  = 32;
  int unsigned data_width  = 64;
  int unsigned id_width    = 4;
  int unsigned user_width  = 0;

  // Mode
  axi_agent_mode_e  agent_mode = AXI_MASTER;  // MASTER, SLAVE, MONITOR

  // Protocol features
  bit enable_exclusive    = 1;
  bit enable_qos          = 1;
  bit enable_region       = 0;
  bit enable_wstrb_check  = 1;

  // Performance
  int unsigned max_outstanding_reads  = 16;
  int unsigned max_outstanding_writes = 16;
  int unsigned max_read_burst_len     = 256;
  int unsigned max_write_burst_len    = 256;

  // Slave configuration
  int unsigned slave_response_delay_min = 0;
  int unsigned slave_response_delay_max = 10;
  axi_resp_e   default_slave_response   = AXI_RESP_OKAY;

  // Coverage
  bit enable_coverage = 1;
  bit enable_protocol_check = 1;

  // Timing
  int unsigned ready_delay_min = 0;
  int unsigned ready_delay_max = 5;
  bit          random_ready    = 1;  // Randomize ready signal timing
endclass
```

**AXI4 VIP Integration:**

```systemverilog
class my_env extends uvm_env;
  axi4_agent  axi_master_agent;
  axi4_agent  axi_slave_agent;

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    // Configure master agent
    axi4_vip_config master_cfg = axi4_vip_config::type_id::create("master_cfg");
    master_cfg.agent_mode = AXI_MASTER;
    master_cfg.addr_width = 32;
    master_cfg.data_width = 64;
    uvm_config_db #(axi4_vip_config)::set(this, "axi_master_agent", "cfg", master_cfg);

    // Configure slave agent
    axi4_vip_config slave_cfg = axi4_vip_config::type_id::create("slave_cfg");
    slave_cfg.agent_mode = AXI_SLAVE;
    slave_cfg.default_slave_response = AXI_RESP_OKAY;
    slave_cfg.slave_response_delay_max = 20;
    uvm_config_db #(axi4_vip_config)::set(this, "axi_slave_agent", "cfg", slave_cfg);

    // Create agents
    axi_master_agent = axi4_agent::type_id::create("axi_master_agent", this);
    axi_slave_agent  = axi4_agent::type_id::create("axi_slave_agent",  this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    // Connect analysis ports to scoreboard
    axi_master_agent.monitor.analysis_port.connect(scoreboard.master_export);
    axi_slave_agent.monitor.analysis_port.connect(scoreboard.slave_export);
  endfunction
endclass

// Top-level connections
module tb_top;
  axi4_if #(.ADDR_W(32), .DATA_W(64), .ID_W(4)) axi_if(clk, rst_n);

  // DUT connection
  my_dut dut(
    .ACLK    (axi_if.ACLK),
    .ARESETn (axi_if.ARESETn),
    .AWVALID (axi_if.AWVALID),
    .AWREADY (axi_if.AWREADY),
    // ... all AXI signals
  );

  initial begin
    uvm_config_db #(virtual axi4_if)::set(null, "*.axi_master_agent", "vif", axi_if);
    uvm_config_db #(virtual axi4_if)::set(null, "*.axi_slave_agent",  "vif", axi_if);
  end
endmodule
```

**AXI4 Common Sequences:**

```systemverilog
// Single write
class axi_single_write_seq extends axi_base_sequence;
  task body();
    axi4_transaction tr;
    tr = axi4_transaction::type_id::create("tr");
    start_item(tr);
    assert(tr.randomize() with {
      rw    == AXI_WRITE;
      burst == AXI_BURST_INCR;
      len   == 0;  // Single beat
      size  == 3;  // 8 bytes (64-bit)
      addr  == 32'h0000_1000;
    });
    finish_item(tr);
  endtask
endclass

// Burst write
class axi_burst_write_seq extends axi_base_sequence;
  rand int unsigned burst_length;
  constraint c_len { burst_length inside {[1:256]}; }

  task body();
    axi4_transaction tr;
    tr = axi4_transaction::type_id::create("tr");
    start_item(tr);
    assert(tr.randomize() with {
      rw    == AXI_WRITE;
      burst == AXI_BURST_INCR;
      len   == burst_length - 1;
      size  == 3;
    });
    finish_item(tr);
  endtask
endclass

// Read-after-write consistency check
class axi_raw_seq extends axi_base_sequence;
  task body();
    axi4_transaction wr_tr, rd_tr;

    // Write
    wr_tr = axi4_transaction::type_id::create("wr_tr");
    start_item(wr_tr);
    assert(wr_tr.randomize() with {
      rw   == AXI_WRITE;
      len  == 0;
      addr == 32'h0000_2000;
    });
    finish_item(wr_tr);

    // Read back
    rd_tr = axi4_transaction::type_id::create("rd_tr");
    start_item(rd_tr);
    rd_tr.rw   = AXI_READ;
    rd_tr.addr = wr_tr.addr;
    rd_tr.len  = 0;
    rd_tr.size = wr_tr.size;
    finish_item(rd_tr);

    // Check response
    get_response(rd_tr);
    if (rd_tr.data[0] !== wr_tr.data[0])
      `uvm_error("RAW", $sformatf("Read-after-write mismatch at 0x%h", wr_tr.addr))
  endtask
endclass

// Exclusive access sequence
class axi_exclusive_seq extends axi_base_sequence;
  task body();
    axi4_transaction rd_tr, wr_tr;

    // Exclusive read
    rd_tr = axi4_transaction::type_id::create("rd_tr");
    start_item(rd_tr);
    rd_tr.rw   = AXI_READ;
    rd_tr.lock = AXI_LOCK_EXCLUSIVE;
    rd_tr.addr = 32'h0000_3000;
    rd_tr.len  = 0;
    finish_item(rd_tr);

    // Modify data
    // ...

    // Exclusive write
    wr_tr = axi4_transaction::type_id::create("wr_tr");
    start_item(wr_tr);
    wr_tr.rw   = AXI_WRITE;
    wr_tr.lock = AXI_LOCK_EXCLUSIVE;
    wr_tr.addr = rd_tr.addr;
    wr_tr.id   = rd_tr.id;
    wr_tr.len  = 0;
    finish_item(wr_tr);

    // Check exclusive response
    if (wr_tr.bresp != AXI_RESP_EXOKAY)
      `uvm_info("EXCL", "Exclusive write failed (expected if contention)", UVM_MEDIUM)
  endtask
endclass
```

### 2.2 AHB VIP

**AHB-Lite Transaction:**

```systemverilog
class ahb_transaction extends uvm_sequence_item;
  rand bit [31:0]  haddr;
  rand bit [2:0]   hburst;    // SINGLE, INCR, WRAP4, INCR4, WRAP8, INCR8, WRAP16, INCR16
  rand bit [2:0]   hsize;     // Byte, Halfword, Word
  rand bit [1:0]   htrans;    // IDLE, BUSY, NONSEQ, SEQ
  rand bit         hwrite;
  rand bit [31:0]  hwdata;
  bit [31:0]       hrdata;
  bit              hready;
  bit [1:0]        hresp;     // OKAY, ERROR
endclass
```

**AHB VIP Configuration:**

```systemverilog
class ahb_config extends uvm_object;
  int unsigned addr_width = 32;
  int unsigned data_width = 32;
  ahb_agent_mode_e mode = AHB_MASTER;
  int unsigned max_wait_states = 16;
  bit enable_busy_transfers = 0;
  bit enable_error_responses = 0;
endclass
```

### 2.3 APB VIP

**APB Transaction:**

```systemverilog
class apb_transaction extends uvm_sequence_item;
  rand bit [31:0]  paddr;
  rand bit [31:0]  pwdata;
  rand bit         pwrite;
  rand bit [3:0]   pstrb;
  rand bit [2:0]   pprot;
  bit [31:0]       prdata;
  bit              pslverr;
  bit              pready;
endclass
```

**APB VIP Configuration:**

```systemverilog
class apb_config extends uvm_object;
  int unsigned addr_width = 32;
  int unsigned data_width = 32;
  apb_agent_mode_e mode = APB_MASTER;
  int unsigned max_pready_delay = 10;
  bit enable_pslverr = 0;
  bit enable_strobe = 1;  // APB4
endclass
```

### 2.4 PCIe VIP

**PCIe Transaction Layer:**

```systemverilog
class pcie_transaction extends uvm_sequence_item;
  // TLP Header
  rand pcie_tlp_type_e   tlp_type;    // MRd, MWr, CplD, Msg, etc.
  rand bit [2:0]          tc;          // Traffic class
  rand bit                td;          // TLP digest
  rand bit                ep;          // Error poisoned
  rand bit [1:0]          attr;        // Attributes
  rand bit [9:0]          length;      // Payload length (DW)
  rand bit [15:0]         requester_id;
  rand bit [7:0]          tag;
  rand bit [63:0]         address;

  // Payload
  rand bit [31:0]         data[];

  // Completion
  rand bit [15:0]         completer_id;
  rand pcie_cpl_status_e  cpl_status;  // SC, UR, CRS, CA
  rand bit [11:0]         byte_count;
endclass
```

**PCIe VIP Configuration:**

```systemverilog
class pcie_config extends uvm_object;
  // Link parameters
  int unsigned num_lanes = 4;         // x1, x2, x4, x8, x16
  pcie_gen_e   gen = PCIE_GEN3;       // Gen1/2/3/4/5
  pcie_speed_e speed = PCIE_8GT;      // 2.5/5/8/16/32 GT/s

  // Device type
  pcie_device_type_e device_type = PCIE_ENDPOINT;

  // Configuration space
  bit [15:0] vendor_id  = 16'hABCD;
  bit [15:0] device_id  = 16'h1234;
  bit [7:0]  class_code = 8'h00;

  // BARs
  bit [63:0] bar0_base = 64'h0000_0000_1000_0000;
  bit [63:0] bar0_size = 64'h0000_0000_0001_0000;  // 64KB

  // Capabilities
  bit enable_msi      = 1;
  bit enable_msix     = 0;
  bit enable_pm       = 1;
  int max_payload     = 256;     // bytes
  int max_read_req    = 512;     // bytes

  // Error injection
  bit enable_ecrc_error    = 0;
  bit enable_lcrc_error    = 0;
  bit enable_poisoned_tlp  = 0;
  bit enable_malformed_tlp = 0;
endclass
```

### 2.5 USB VIP

**USB Transaction:**

```systemverilog
class usb_transaction extends uvm_sequence_item;
  rand usb_pid_e         pid;        // Token, Data, Handshake, Special
  rand bit [6:0]         addr;       // Device address
  rand bit [3:0]         endp;       // Endpoint number
  rand usb_transfer_e    xfer_type;  // CONTROL, BULK, INTERRUPT, ISOCHRONOUS
  rand usb_direction_e   direction;  // IN, OUT, SETUP
  rand byte unsigned     data[];
  rand bit [4:0]         crc5;
  rand bit [15:0]        crc16;
endclass
```

**USB VIP Configuration:**

```systemverilog
class usb_config extends uvm_object;
  usb_speed_e      speed = USB_HIGH_SPEED;   // LS, FS, HS, SS
  usb_role_e       role  = USB_HOST;         // HOST, DEVICE
  bit [6:0]        device_addr = 7'h01;
  int unsigned     max_packet_size = 512;    // HS bulk
  bit              enable_otg = 0;
  int unsigned     num_endpoints = 4;
endclass
```

### 2.6 DDR VIP

**DDR Transaction:**

```systemverilog
class ddr_transaction extends uvm_sequence_item;
  rand ddr_cmd_e          cmd;        // ACT, READ, WRITE, PRE, REF, MRS
  rand bit [2:0]          bank_group;
  rand bit [1:0]          bank;
  rand bit [17:0]         row;
  rand bit [9:0]          col;
  rand bit [63:0]         data[];     // Burst data
  rand bit [7:0]          dm[];       // Data mask
  rand int unsigned       cas_latency;
endclass
```

**DDR VIP Configuration:**

```systemverilog
class ddr_config extends uvm_object;
  ddr_type_e        ddr_type = DDR4;         // DDR3, DDR4, DDR5, LPDDR4, LPDDR5
  int unsigned      data_width = 64;          // x8, x16, x32, x64
  int unsigned      ranks = 1;
  int unsigned      bank_groups = 4;
  int unsigned      banks_per_group = 4;
  int unsigned      rows = 65536;             // 64K rows
  int unsigned      cols = 1024;
  int unsigned      burst_length = 8;

  // Timing parameters (in clock cycles)
  int unsigned      tRCD = 14;
  int unsigned      tRP  = 14;
  int unsigned      tRAS = 33;
  int unsigned      tRC  = 47;
  int unsigned      tRFC = 350;
  int unsigned      CL   = 14;
  int unsigned      CWL  = 11;
  int unsigned      tWR  = 15;

  // Controller
  ddr_role_e        role = DDR_CONTROLLER;    // CONTROLLER, MEMORY
endclass
```

### 2.7 Ethernet VIP

**Ethernet Transaction:**

```systemverilog
class ethernet_transaction extends uvm_sequence_item;
  rand bit [47:0]        dst_mac;
  rand bit [47:0]        src_mac;
  rand bit [15:0]        etype;       // EtherType / Length
  rand bit [2:0]         pcp;         // 802.1Q priority
  rand bit               dei;         // Drop eligible
  rand bit [11:0]        vid;         // VLAN ID
  rand byte unsigned     payload[];
  rand int unsigned      ipg;         // Inter-packet gap
  bit [31:0]             fcs;         // Frame check sequence

  constraint c_payload_size {
    payload.size() inside {[46:1500]};  // Standard frame
    // payload.size() inside {[46:9000]};  // Jumbo frame
  }

  constraint c_ipg {
    ipg >= 12;  // Minimum IPG
  }
endclass
```

---

## 3. VIP Configuration Best Practices

### 3.1 Configuration Hierarchy

```systemverilog
// Test configures VIP through config_db
class my_test extends base_test;
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    // AXI master configuration
    axi4_vip_config axi_cfg;
    axi_cfg = axi4_vip_config::type_id::create("axi_cfg");
    axi_cfg.agent_mode = AXI_MASTER;
    axi_cfg.random_ready = 1;
    axi_cfg.ready_delay_max = 10;  // Exercise back-pressure
    uvm_config_db #(axi4_vip_config)::set(this, "env.axi_agent", "cfg", axi_cfg);

    // Different config for stress test
    // axi_cfg.ready_delay_max = 0;  // No back-pressure for max throughput
  endfunction
endclass
```

### 3.2 Randomization Control

```systemverilog
// Control VIP randomization for specific scenarios

// Always-ready slave (no back-pressure)
class fast_slave_config extends axi4_slave_config;
  constraint c_no_delay {
    ready_delay == 0;
    response_delay == 0;
  }
endclass

// Slow slave (maximum back-pressure)
class slow_slave_config extends axi4_slave_config;
  constraint c_slow {
    ready_delay inside {[5:20]};
    response_delay inside {[10:50]};
  }
endclass

// Error-prone slave
class error_slave_config extends axi4_slave_config;
  constraint c_errors {
    error_rate inside {[5:20]};  // 5-20% error responses
    response_type dist {
      AXI_RESP_OKAY   := 80,
      AXI_RESP_SLVERR := 15,
      AXI_RESP_DECERR := 5
    };
  }
endclass
```

### 3.3 Coverage Control

```systemverilog
// Enable/disable VIP coverage per test
class performance_test extends base_test;
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    // Disable coverage for performance measurement
    axi_cfg.enable_coverage = 0;
    axi_cfg.enable_protocol_check = 1;  // Keep checking on
  endfunction
endclass

class coverage_test extends base_test;
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    // Enable all coverage
    axi_cfg.enable_coverage = 1;
    axi_cfg.enable_protocol_check = 1;
  endfunction
endclass
```

---

## 4. VIP Integration Patterns

### 4.1 Virtual Interface Connection

```systemverilog
// Interface definition (typically provided by VIP)
interface axi4_if #(
  parameter ADDR_W = 32,
  parameter DATA_W = 64,
  parameter ID_W   = 4
)(
  input logic ACLK,
  input logic ARESETn
);
  // Write address channel
  logic                AWVALID;
  logic                AWREADY;
  logic [ADDR_W-1:0]   AWADDR;
  logic [7:0]           AWLEN;
  logic [2:0]           AWSIZE;
  logic [1:0]           AWBURST;
  logic [ID_W-1:0]      AWID;
  // ... remaining signals

  // Modports
  modport master(
    output AWVALID, AWADDR, AWLEN, AWSIZE, AWBURST, AWID,
    input  AWREADY,
    // ... all master outputs and inputs
  );

  modport slave(
    input  AWVALID, AWADDR, AWLEN, AWSIZE, AWBURST, AWID,
    output AWREADY,
    // ... all slave outputs and inputs
  );

  modport monitor(
    input AWVALID, AWREADY, AWADDR, AWLEN, AWSIZE, AWBURST, AWID,
    // ... all signals as inputs
  );
endinterface

// Connection in top module
module tb_top;
  logic clk, rst_n;

  // Interface instantiation
  axi4_if #(.ADDR_W(32), .DATA_W(64), .ID_W(4))
    master_if(.ACLK(clk), .ARESETn(rst_n));

  axi4_if #(.ADDR_W(32), .DATA_W(64), .ID_W(4))
    slave_if(.ACLK(clk), .ARESETn(rst_n));

  // DUT connection
  my_dut dut(
    .clk(clk),
    .rst_n(rst_n),
    // Master port (DUT drives as master)
    .m_awvalid(master_if.AWVALID),
    .m_awready(master_if.AWREADY),
    // ...
    // Slave port (DUT receives as slave)
    .s_awvalid(slave_if.AWVALID),
    .s_awready(slave_if.AWREADY),
    // ...
  );

  // Virtual interface to testbench
  initial begin
    uvm_config_db #(virtual axi4_if)::set(null, "*.master_agent", "vif", master_if);
    uvm_config_db #(virtual axi4_if)::set(null, "*.slave_agent",  "vif", slave_if);
  end
endmodule
```

### 4.2 Clock and Reset Connection

```systemverilog
// Shared clock/reset with VIP
module tb_top;
  // Single clock domain
  logic clk = 0;
  always #5ns clk = ~clk;

  logic rst_n;
  initial begin
    rst_n = 0;
    #100ns;
    rst_n = 1;
  end

  // Interface inherits clock
  axi4_if axi_if(.ACLK(clk), .ARESETn(rst_n));

  // Multiple clock domains
  logic fast_clk = 0, slow_clk = 0;
  always #2.5ns fast_clk = ~fast_clk;  // 200 MHz
  always #5ns   slow_clk = ~slow_clk;  // 100 MHz

  axi4_if axi_fast_if(.ACLK(fast_clk), .ARESETn(rst_n));
  axi4_if axi_slow_if(.ACLK(slow_clk), .ARESETn(rst_n));
endmodule
```

### 4.3 Multi-VIP Environment

```systemverilog
class soc_env extends uvm_env;
  `uvm_component_utils(soc_env)

  // Multiple VIP agents
  axi4_agent      axi_master;     // AXI master VIP
  axi4_agent      axi_slave;      // AXI slave VIP
  apb_agent       apb_master;     // APB master VIP
  uart_agent      uart_agent0;    // UART VIP
  spi_agent       spi_master;     // SPI VIP
  gpio_agent      gpio_agent0;    // GPIO VIP

  // Virtual sequencer for coordination
  soc_virtual_sequencer v_sqr;

  // Scoreboards
  axi_scoreboard  axi_scbd;
  apb_scoreboard  apb_scbd;
  system_scoreboard sys_scbd;     // Cross-protocol checking

  // Register model
  soc_reg_block   reg_model;

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    // Create all agents with their configs
    axi_master = axi4_agent::type_id::create("axi_master", this);
    axi_slave  = axi4_agent::type_id::create("axi_slave",  this);
    apb_master = apb_agent::type_id::create("apb_master",  this);
    uart_agent0 = uart_agent::type_id::create("uart_agent0", this);
    spi_master = spi_agent::type_id::create("spi_master",  this);
    gpio_agent0 = gpio_agent::type_id::create("gpio_agent0", this);

    v_sqr = soc_virtual_sequencer::type_id::create("v_sqr", this);

    axi_scbd = axi_scoreboard::type_id::create("axi_scbd", this);
    apb_scbd = apb_scoreboard::type_id::create("apb_scbd", this);
    sys_scbd = system_scoreboard::type_id::create("sys_scbd", this);

    reg_model = soc_reg_block::type_id::create("reg_model");
    reg_model.build();
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);

    // Virtual sequencer connections
    v_sqr.axi_sqr  = axi_master.sequencer;
    v_sqr.apb_sqr  = apb_master.sequencer;
    v_sqr.uart_sqr = uart_agent0.sequencer;
    v_sqr.spi_sqr  = spi_master.sequencer;
    v_sqr.gpio_sqr = gpio_agent0.sequencer;

    // Scoreboard connections
    axi_master.monitor.analysis_port.connect(axi_scbd.master_export);
    axi_slave.monitor.analysis_port.connect(axi_scbd.slave_export);
    apb_master.monitor.analysis_port.connect(apb_scbd.analysis_export);

    // System scoreboard
    axi_master.monitor.analysis_port.connect(sys_scbd.axi_export);
    apb_master.monitor.analysis_port.connect(sys_scbd.apb_export);

    // Register model
    reg_model.default_map.set_sequencer(apb_master.sequencer, apb_adapter);
  endfunction
endclass
```

---

## 5. Protocol Checking and Error Injection

### 5.1 Protocol Assertion Checking

VIPs include built-in protocol checkers as assertions:

```systemverilog
// AXI protocol checks (typically built into VIP)
// Handshake rules
// Ordering rules
// Burst rules
// Exclusive access rules
// Response rules
// Reset behavior

// Enabling/disabling protocol checks
class my_test extends base_test;
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    // Enable all protocol checks
    axi_cfg.enable_protocol_check = 1;

    // Disable specific checks for error injection tests
    axi_cfg.disable_check("AXI_VALID_HOLD");
  endfunction
endclass
```

### 5.2 Error Injection

```systemverilog
// VIP-based error injection

// AXI error response
class axi_error_response_seq extends axi_slave_sequence;
  int error_rate = 10;  // 10%

  task body();
    axi4_transaction tr;
    forever begin
      // Get request from DUT
      get_next_item(tr);

      // Inject error response randomly
      if ($urandom_range(99) < error_rate) begin
        tr.resp = AXI_RESP_SLVERR;
        `uvm_info("ERR_INJ", "Injecting slave error response", UVM_MEDIUM)
      end else begin
        tr.resp = AXI_RESP_OKAY;
      end

      // Respond
      finish_item(tr);
    end
  endtask
endclass

// Protocol violation injection (for negative testing)
class axi_protocol_violation_seq extends axi_base_sequence;
  task body();
    axi4_transaction tr;

    // Test: Drop valid before ready
    tr = axi4_transaction::type_id::create("tr");
    start_item(tr);
    tr.inject_violation = AXI_VALID_DROP;
    finish_item(tr);

    // Test: Change address during handshake
    tr = axi4_transaction::type_id::create("tr");
    start_item(tr);
    tr.inject_violation = AXI_ADDR_CHANGE;
    finish_item(tr);
  endtask
endclass

// Timeout injection
class axi_timeout_seq extends axi_slave_sequence;
  task body();
    axi4_transaction tr;
    get_next_item(tr);

    // Never respond - causes timeout
    // VIP should detect and report timeout
    // DUT should handle gracefully
  endtask
endclass
```

### 5.3 Compliance Testing

```systemverilog
// Protocol compliance test suite
class axi_compliance_test extends base_test;
  task run_phase(uvm_phase phase);
    phase.raise_objection(this);

    // Run VIP built-in compliance sequences
    run_handshake_compliance();
    run_burst_compliance();
    run_ordering_compliance();
    run_exclusive_compliance();
    run_reset_compliance();

    phase.drop_objection(this);
  endtask

  task run_handshake_compliance();
    axi_handshake_seq seq;
    seq = axi_handshake_seq::type_id::create("seq");
    // Tests: valid before ready, ready before valid, simultaneous
    seq.start(env.axi_master.sequencer);
  endtask

  task run_burst_compliance();
    axi_burst_compliance_seq seq;
    seq = axi_burst_compliance_seq::type_id::create("seq");
    // Tests: all burst types, sizes, lengths, address wrapping
    seq.start(env.axi_master.sequencer);
  endtask
endclass
```

---

## 6. VIP Vendor Comparison

### 6.1 Synopsys VIP (VCS VIP / VC VIP)

```
Synopsys Verification IP:
- Product: VCS VIP / VC VIP (Verification Compiler)
- Protocols: AXI, AHB, APB, PCIe, USB, DDR, Ethernet, MIPI, JTAG, SPI, I2C, CAN
- Features:
  - Full UVM integration
  - Built-in protocol assertions
  - Comprehensive coverage models
  - Performance analysis
  - Multi-language support (SV, e)
  - Automated compliance testing
  - Error injection capabilities
  - Memory model for DDR VIP

Usage:
  vcs -sverilog +incdir+$VCS_VIP_HOME/axi/include \
      +incdir+$VCS_VIP_HOME/axi/src \
      $VCS_VIP_HOME/axi/src/axi_pkg.sv
```

### 6.2 Cadence VIP (VIPCAT)

```
Cadence Verification IP:
- Product: VIPCAT (VIP Catalog)
- Protocols: AXI, AHB, APB, PCIe, USB, DDR, Ethernet, MIPI, JTAG, SPI, I2C
- Features:
  - Full UVM integration
  - Protocol monitor and checker
  - Functional coverage
  - Error injection
  - Performance monitoring
  - Multi-protocol support
  - Xcelium optimization
  - Memory model integration

Usage:
  xrun +incdir+$CDNS_VIP_HOME/axi/sv \
       $CDNS_VIP_HOME/axi/sv/axi_pkg.sv \
       -uvm
```

### 6.3 Siemens VIP (Questa VIP)

```
Siemens Verification IP:
- Product: Questa VIP
- Protocols: AXI, AHB, APB, PCIe, USB, DDR, Ethernet, MIPI, JTAG, SPI, I2C
- Features:
  - Full UVM integration
  - Protocol-aware debug in Questa
  - Comprehensive assertions
  - Functional coverage
  - Error injection
  - Performance analysis
  - QVIP Configurator GUI

Usage:
  vlog +incdir+$QUESTA_VIP_HOME/axi/sv \
       $QUESTA_VIP_HOME/axi/sv/axi_pkg.sv
  vsim -sv_lib $QUESTA_VIP_HOME/axi/lib/axi_vip_lib
```

### 6.4 Vendor Selection Criteria

| Criterion | Weight | Consideration |
|-----------|--------|---------------|
| Protocol support | High | Does it support all needed protocols? |
| Tool integration | High | Native integration with your simulator? |
| Coverage quality | High | Comprehensive built-in coverage? |
| Ease of integration | Medium | Clear API, good documentation? |
| Performance | Medium | Simulation speed impact? |
| Error injection | Medium | Flexible error injection? |
| Support quality | Medium | Responsive support team? |
| License cost | Medium | Budget alignment? |
| Compliance testing | Low-Med | Pre-built compliance suites? |
| Reuse across projects | Low-Med | Portable across environments? |

---

## 7. Custom VIP Development

### 7.1 When to Build Custom VIP

Build custom VIP when:
- Proprietary protocol with no commercial VIP.
- Simple protocol where commercial VIP is overkill.
- Need deep integration with project-specific infrastructure.
- Budget constraints prevent commercial VIP purchase.

### 7.2 Custom VIP Architecture Template

```systemverilog
//----------------------------------------------------------------------
// Transaction
//----------------------------------------------------------------------
class my_proto_transaction extends uvm_sequence_item;
  `uvm_object_utils(my_proto_transaction)

  // Protocol fields
  rand bit [ADDR_W-1:0] addr;
  rand bit [DATA_W-1:0] data;
  rand my_proto_cmd_e   cmd;
  rand int unsigned      delay;

  // Response
  bit [DATA_W-1:0]       rdata;
  my_proto_resp_e         resp;

  // Constraints
  constraint c_default {
    soft delay inside {[0:10]};
  }

  function new(string name = "my_proto_transaction");
    super.new(name);
  endfunction

  // Implement do_copy, do_compare, convert2string, do_print
endclass

//----------------------------------------------------------------------
// Interface
//----------------------------------------------------------------------
interface my_proto_if(input logic clk, input logic rst_n);
  logic [ADDR_W-1:0] addr;
  logic [DATA_W-1:0] wdata;
  logic [DATA_W-1:0] rdata;
  logic               cmd_valid;
  logic               cmd_ready;
  logic               rsp_valid;
  logic [1:0]         rsp_status;

  modport master_mp(output addr, wdata, cmd_valid, input cmd_ready, rdata, rsp_valid, rsp_status);
  modport slave_mp(input addr, wdata, cmd_valid, output cmd_ready, rdata, rsp_valid, rsp_status);
  modport monitor_mp(input addr, wdata, rdata, cmd_valid, cmd_ready, rsp_valid, rsp_status);

  // Protocol assertions
  property p_valid_until_ready;
    @(posedge clk) disable iff (!rst_n)
    cmd_valid && !cmd_ready |=> cmd_valid;
  endproperty
  assert property (p_valid_until_ready);

  property p_data_stable;
    @(posedge clk) disable iff (!rst_n)
    cmd_valid && !cmd_ready |=> $stable(addr) && $stable(wdata);
  endproperty
  assert property (p_data_stable);
endinterface

//----------------------------------------------------------------------
// Configuration
//----------------------------------------------------------------------
class my_proto_config extends uvm_object;
  `uvm_object_utils(my_proto_config)

  uvm_active_passive_enum is_active = UVM_ACTIVE;
  virtual my_proto_if vif;
  bit has_coverage = 1;
  bit has_checks = 1;
  my_proto_mode_e mode = MY_PROTO_MASTER;

  function new(string name = "my_proto_config");
    super.new(name);
  endfunction
endclass

//----------------------------------------------------------------------
// Driver
//----------------------------------------------------------------------
class my_proto_driver extends uvm_driver #(my_proto_transaction);
  `uvm_component_utils(my_proto_driver)

  virtual my_proto_if vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual my_proto_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "Virtual interface not found")
  endfunction

  task run_phase(uvm_phase phase);
    // Initialize
    vif.cmd_valid <= 0;
    @(posedge vif.rst_n);
    repeat(2) @(posedge vif.clk);

    forever begin
      my_proto_transaction tr;
      seq_item_port.get_next_item(tr);
      drive_transaction(tr);
      seq_item_port.item_done();
    end
  endtask

  task drive_transaction(my_proto_transaction tr);
    // Pre-delay
    repeat(tr.delay) @(posedge vif.clk);

    // Drive
    @(posedge vif.clk);
    vif.addr      <= tr.addr;
    vif.wdata     <= tr.data;
    vif.cmd_valid <= 1;

    // Wait for ready
    @(posedge vif.clk);
    while (!vif.cmd_ready) @(posedge vif.clk);
    vif.cmd_valid <= 0;

    // Collect response
    while (!vif.rsp_valid) @(posedge vif.clk);
    tr.rdata = vif.rdata;
    tr.resp  = my_proto_resp_e'(vif.rsp_status);
  endtask
endclass

//----------------------------------------------------------------------
// Monitor
//----------------------------------------------------------------------
class my_proto_monitor extends uvm_monitor;
  `uvm_component_utils(my_proto_monitor)

  virtual my_proto_if vif;
  uvm_analysis_port #(my_proto_transaction) analysis_port;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    analysis_port = new("analysis_port", this);
  endfunction

  task run_phase(uvm_phase phase);
    @(posedge vif.rst_n);
    forever begin
      my_proto_transaction tr;
      collect_transaction(tr);
      analysis_port.write(tr);
    end
  endtask

  task collect_transaction(output my_proto_transaction tr);
    tr = my_proto_transaction::type_id::create("tr");

    // Wait for valid handshake
    @(posedge vif.clk);
    while (!(vif.cmd_valid && vif.cmd_ready)) @(posedge vif.clk);

    tr.addr = vif.addr;
    tr.data = vif.wdata;

    // Wait for response
    while (!vif.rsp_valid) @(posedge vif.clk);
    tr.rdata = vif.rdata;
    tr.resp  = my_proto_resp_e'(vif.rsp_status);
  endtask
endclass

//----------------------------------------------------------------------
// Agent
//----------------------------------------------------------------------
class my_proto_agent extends uvm_agent;
  `uvm_component_utils(my_proto_agent)

  my_proto_driver    driver;
  my_proto_sequencer sequencer;
  my_proto_monitor   monitor;
  my_proto_coverage  coverage;
  my_proto_config    cfg;

  uvm_analysis_port #(my_proto_transaction) analysis_port;

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db #(my_proto_config)::get(this, "", "cfg", cfg))
      `uvm_fatal("NOCFG", "Agent config not found")

    monitor = my_proto_monitor::type_id::create("monitor", this);

    if (cfg.is_active == UVM_ACTIVE) begin
      driver    = my_proto_driver::type_id::create("driver", this);
      sequencer = my_proto_sequencer::type_id::create("sequencer", this);
    end

    if (cfg.has_coverage)
      coverage = my_proto_coverage::type_id::create("coverage", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    analysis_port = monitor.analysis_port;

    if (cfg.is_active == UVM_ACTIVE)
      driver.seq_item_port.connect(sequencer.seq_item_export);

    if (cfg.has_coverage)
      monitor.analysis_port.connect(coverage.analysis_export);
  endfunction
endclass
```

### 7.3 Custom VIP Testing

```systemverilog
// Self-test for custom VIP (loopback test)
class vip_loopback_test extends uvm_test;
  my_proto_agent master_agent;
  my_proto_agent slave_agent;

  task run_phase(uvm_phase phase);
    // Master sends, slave responds
    // Verify round-trip through VIP
    fork
      run_master_sequences();
      run_slave_responder();
    join
  endtask
endclass
```

---

## 8. VIP Performance Optimization

### 8.1 Simulation Speed

| Technique | Impact | Description |
|-----------|--------|-------------|
| Disable coverage | High | Turn off coverage during performance runs |
| Reduce protocol checks | Medium | Disable non-critical assertions |
| Transaction batching | Medium | Send multiple transactions per delta |
| Memory model | Medium | Use DPI-C memory for large memories |
| Clocking blocks | Low | Use clocking blocks for timing |

### 8.2 Memory Management

```systemverilog
// For large memory VIPs (DDR), use sparse memory model
class sparse_memory;
  bit [7:0] mem[bit [63:0]];  // Associative array

  function void write(bit [63:0] addr, bit [7:0] data);
    mem[addr] = data;
  endfunction

  function bit [7:0] read(bit [63:0] addr);
    if (mem.exists(addr))
      return mem[addr];
    else
      return 8'hXX;  // Uninitialized
  endfunction
endclass
```

---
