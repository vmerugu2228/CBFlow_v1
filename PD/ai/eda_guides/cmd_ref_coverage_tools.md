# Coverage Tools Complete Reference

Comprehensive reference for coverage collection, merging, analysis, and
closure using VCS (Synopsys), Xcelium (Cadence), Questa (Siemens), and Verdi.

---

## 1. Coverage Types Overview

### 1.1 Code Coverage Types

| Type | Description | What it Measures |
|------|-------------|-----------------|
| Statement (Line) | Each executable line of code | Was this statement executed? |
| Branch | Each branch of if/else, case | Were both if and else taken? |
| Condition | Each sub-expression in boolean | Was each sub-expression T and F? |
| Toggle | Each bit transition | Did each bit go 0->1 and 1->0? |
| FSM State | Each state in FSM | Was each state visited? |
| FSM Transition | Each state-to-state arc | Was each transition taken? |
| Expression | All truth table combinations | All boolean combinations? |
| Path | Execution paths through code | Was this sequence of branches taken? |

### 1.2 Functional Coverage Types

| Type | Description | Example |
|------|-------------|---------|
| Coverpoint | Individual variable coverage | Transaction type coverage |
| Cross | Cartesian product of coverpoints | cmd x size x channel |
| Transition | Sequence of values | state transitions |
| Assertion | Property coverage | Protocol compliance |

---

## 2. VCS Coverage (Synopsys)

### 2.1 VCS Coverage Collection

**Compile-Time Options:**

```bash
# Enable all code coverage
vcs -cm line+cond+fsm+tgl+branch+assert \
    -cm_dir coverage/simv.vdb \
    -cm_name test_name \
    -cm_hier coverage_hier.cfg \
    -cm_log coverage.log \
    <design_files>

# Individual coverage types
vcs -cm line                    # Statement/line coverage
vcs -cm cond                    # Condition coverage
vcs -cm fsm                     # FSM coverage
vcs -cm tgl                     # Toggle coverage
vcs -cm branch                  # Branch coverage
vcs -cm assert                  # Assertion coverage
vcs -cm line+cond+fsm+tgl+branch # All except assertion

# Coverage options
vcs -cm_cond basic              # Basic condition (each sub-expression)
vcs -cm_cond allops             # All operator combinations
vcs -cm_cond full               # Full truth table
vcs -cm_cond obs                # Observability-based condition

# Toggle options
vcs -cm_tgl mda                 # Multi-dimensional array toggle
vcs -cm_tgl portsonly           # Toggle on ports only
vcs -cm_tgl structarr           # Include struct arrays

# FSM options
vcs -cm_fsmcfg fsm_config.cfg   # FSM configuration file
vcs -cm_fsmresetonly            # Only count transitions from reset state

# Hierarchy control
vcs -cm_hier coverage_hier.cfg  # Specify coverage hierarchy
# coverage_hier.cfg format:
# +tree tb.dut                  # Include DUT hierarchy
# -tree tb.dut.pad_ring         # Exclude pad ring
# +module fifo                  # Include all fifo instances
# -module clock_gen             # Exclude clock generator
# +moduletree cpu               # Include cpu and all children
```

**Runtime Options:**

```bash
# Run simulation with coverage
./simv -cm line+cond+fsm+tgl+branch+assert \
       -cm_dir coverage/simv.vdb \
       -cm_name test_name_seed12345 \
       -cm_log cm.log \
       +UVM_TESTNAME=my_test

# Coverage output name
./simv -cm_name test1_seed$(SEED)

# Coverage test name for tracking
./simv -cm_test test_write_read

# Toggle options at runtime
./simv -cm_tgl_portsonly_on      # Toggle on ports only
```

### 2.2 URG (Unified Report Generator)

URG is the VCS tool for merging and reporting coverage.

**Basic Usage:**

```bash
# Generate HTML report from single run
urg -dir coverage/simv.vdb -report report_dir

# Merge multiple coverage databases
urg -dir run1/simv.vdb run2/simv.vdb run3/simv.vdb \
    -dbname merged.vdb \
    -report merged_report

# Merge using wildcard
urg -dir coverage/*/simv.vdb \
    -dbname merged.vdb \
    -report merged_report

# Merge with test grouping
urg -dir coverage/*/simv.vdb \
    -group group_config.cfg \
    -dbname merged.vdb \
    -report merged_report
```

**Report Options:**

```bash
# Report format
urg -format text          # Text report
urg -format html          # HTML report (default)
urg -format both          # Both text and HTML

# Summary only
urg -show summary

# Detailed report
urg -show detail

# Metric-specific reports
urg -show ratios          # Coverage ratios
urg -show tests           # Test contribution
urg -show holes           # Coverage holes only

# Per-module report
urg -show modreport

# Cross coverage report
urg -show cross

# Grade tests by coverage contribution
urg -grade run
urg -grade seed           # Grade by seed value

# Exclusion handling
urg -elfile exclusions.el # Apply exclusion file
urg -elfile excl1.el -elfile excl2.el  # Multiple exclusion files

# Filter
urg -metric line+branch+cond+toggle+fsm  # Specific metrics
urg -hier_filter +tree tb.dut             # Filter hierarchy
```

**Coverage Grading:**

```bash
# Grade tests to find minimal set achieving same coverage
urg -dir coverage/*/simv.vdb \
    -grade run \
    -report grading_report

# Output shows:
# Test    | Incremental Coverage | Cumulative Coverage
# test_1  | 45.2%               | 45.2%
# test_7  | 12.3%               | 57.5%
# test_3  |  8.1%               | 65.6%
# ...
```

### 2.3 VCS Exclusion Files

```
# Exclusion file format (.el)

# Exclude specific line
begin line
  module fifo
  file fifo.sv
  line 42
  comment "Debug-only code, not synthesizable"
end

# Exclude branch
begin branch
  module decoder
  file decoder.sv
  line 100
  expr "case (cmd)"
  branch_num 5
  comment "Reserved command encoding, not implemented"
end

# Exclude toggle
begin tgl
  module regs
  file regs.sv
  signal unused_bits[31:16]
  comment "Reserved register bits, tied to 0"
end

# Exclude FSM transition
begin fsm
  module ctrl_fsm
  file ctrl.sv
  fsm state
  transition IDLE->ERROR
  comment "Error state not reachable in normal operation"
end

# Exclude condition
begin cond
  module arbiter
  file arbiter.sv
  line 55
  expr_num 2
  row_num 3
  comment "Dead condition due to priority logic"
end

# Exclude entire module
begin module
  module test_wrapper
  comment "Test wrapper, not part of design"
end

# Exclude block instance
begin instance
  instance tb.dut.debug_port
  comment "Debug port, tested separately"
end
```

### 2.4 VCS Coverage Merging Scripts

```bash
#!/bin/bash
# merge_coverage.sh

COVERAGE_DIR=./coverage
MERGED_DIR=./merged_coverage
REPORT_DIR=./coverage_report

# Find all coverage databases
VDB_LIST=""
for dir in ${COVERAGE_DIR}/*/simv.vdb; do
  if [ -d "$dir" ]; then
    VDB_LIST="${VDB_LIST} -dir ${dir}"
  fi
done

# Merge
urg ${VDB_LIST} \
    -dbname ${MERGED_DIR}/merged.vdb \
    -elfile exclusions.el \
    -report ${REPORT_DIR} \
    -format both \
    -show summary+detail+holes \
    -metric line+branch+cond+toggle+fsm+assert

# Print summary
echo "=== Coverage Summary ==="
grep -A 20 "COVERAGE SUMMARY" ${REPORT_DIR}/dashboard.txt
```

---

## 3. Xcelium Coverage (Cadence)

### 3.1 Xcelium Coverage Collection

**Compile-Time Options:**

```bash
# Enable coverage with xrun
xrun -coverage all \
     -covdut tb.dut \
     -covfile coverage_config.ccf \
     -covoverwrite \
     <design_files>

# Individual coverage types
xrun -coverage b           # Block (statement) coverage
xrun -coverage e           # Expression coverage
xrun -coverage f           # FSM coverage
xrun -coverage t           # Toggle coverage
xrun -coverage u           # Functional coverage
xrun -coverage s           # Statement coverage
xrun -coverage a           # Assertion coverage
xrun -coverage all         # All types

# Combined
xrun -coverage b:e:f:t:u:s:a

# Coverage configuration file
xrun -covfile my_coverage.ccf
```

**Coverage Configuration File (.ccf):**

```tcl
# coverage configuration file

# Set DUT scope
set_cover_dut -module dut_top

# Include/exclude hierarchy
select_coverage -block -expr -toggle -fsm -all
deselect_coverage -instance tb.dut.debug_module

# Toggle settings
set_toggle_portsonly
set_toggle_includez

# Expression settings
set_expr_coverable_operators -all
set_expr_scoring_countmax 1

# FSM settings
set_fsm_force_var -module ctrl -name state
set_fsm_reset_trans_only

# Functional coverage
set_covergroup -per_instance_default_one

# Exclusion
set_refinement_file exclusions.vRefine
```

**Runtime Options:**

```bash
# Run with coverage
xrun -R \
     -coverage all \
     -covdut tb.dut \
     -covscope tb.dut \
     -covtest test_name \
     -covworkdir ./cov_work \
     -covoverwrite

# Coverage database output
xrun -R -covworkdir ./cov_work -covscope tb.dut
```

### 3.2 IMC (Integrated Metrics Center)

IMC is the Cadence tool for coverage analysis, merging, and reporting.

**Command-Line Usage:**

```bash
# Launch IMC GUI
imc -gui -init imc_script.tcl

# Batch mode
imc -batch -init imc_script.tcl -exec "exit"

# Merge coverage databases
imc -batch -exec '
  merge cov_work/scope/test1 cov_work/scope/test2 \
        -output merged_cov -overwrite
  exit
'

# Generate reports
imc -batch -exec '
  load -run merged_cov
  report -detail -all -out report.txt
  report -summary -out summary.txt
  exit
'
```

**IMC TCL Commands:**

```tcl
# Load coverage
load -run cov_work/scope/test1

# Merge runs
merge cov_work/scope/test1 cov_work/scope/test2 \
      -output merged -overwrite

# Apply exclusions
load -refinement exclusions.vRefine

# Generate reports
report -summary                    ;# Summary report
report -detail                     ;# Detailed report
report -metrics all               ;# All metrics
report -metrics block              ;# Block coverage only
report -metrics expression         ;# Expression coverage
report -metrics toggle             ;# Toggle coverage
report -metrics fsm                ;# FSM coverage
report -metrics functional         ;# Functional coverage
report -metrics assertion          ;# Assertion coverage

# Report to file
report -detail -all -out report.txt -format text
report -detail -all -out report.html -format html

# Coverage holes
report -uncovered                  ;# Show uncovered items
report -uncovered -metrics block   ;# Uncovered blocks only

# Test grading
grade -metric all                  ;# Grade all tests
grade -testranking                 ;# Rank tests by contribution

# Query specific coverage
report -inst tb.dut.cpu           ;# Coverage for specific instance
report -module fifo                ;# Coverage for module type

# Exclusion management
set_refinement_file excl.vRefine
save_refinement -file new_excl.vRefine

# Export
export_coverage -type lcov -output lcov.info
```

### 3.3 Xcelium Exclusion Files

```tcl
# Exclusion file format (.vRefine)

# Exclude block coverage
begin_exclusion
  -scope tb.dut.ctrl
  -line 45
  -type block
  -comment "Debug-only path"
end_exclusion

# Exclude toggle
begin_exclusion
  -scope tb.dut.regs
  -signal reserved[31:16]
  -type toggle
  -comment "Reserved bits"
end_exclusion

# Exclude expression
begin_exclusion
  -scope tb.dut.decoder
  -line 100
  -type expression
  -comment "Impossible condition"
end_exclusion

# Exclude FSM transition
begin_exclusion
  -scope tb.dut.fsm
  -type fsm
  -state IDLE
  -trans ERROR
  -comment "Not reachable"
end_exclusion

# Exclude entire instance
begin_exclusion
  -scope tb.dut.debug_module
  -type all
  -comment "Debug module excluded"
end_exclusion
```

---

## 4. Questa Coverage (Siemens)

### 4.1 Questa Coverage Collection

**Compile-Time Options:**

```bash
# Compile with coverage
vlog +cover=bcestf design.sv
vlog +cover           # All coverage types

# Coverage types
# b = branch
# c = condition
# e = expression
# s = statement
# t = toggle
# f = FSM

# Compile with specific coverage
vlog +cover=bcs design.sv    # Branch + condition + statement

# Optimization with coverage
vopt +cover=bcestf top -o top_opt

# Toggle options
vlog +cover=t+portonly design.sv      # Ports only
vlog +cover=t+/top/dut design.sv     # Specific hierarchy
```

**Runtime Options:**

```bash
# Run simulation with coverage
vsim -coverage top_opt \
     -do "coverage save -onexit coverage.ucdb; run -all; quit"

# Coverage database
vsim -coverage -cvgperinstance top_opt

# Functional coverage per instance
vsim -cvgperinstance top_opt

# Coverage merge during simulation
vsim -coverage -covermerge coverage.ucdb top_opt
```

### 4.2 Questa Coverage Analysis

**UCDB (Unified Coverage Database) Management:**

```bash
# Merge coverage databases
vcover merge merged.ucdb test1.ucdb test2.ucdb test3.ucdb

# Merge with wildcard
vcover merge merged.ucdb ./results/*/coverage.ucdb

# Generate reports
vcover report merged.ucdb -output report.txt
vcover report merged.ucdb -output report.html -html
vcover report merged.ucdb -details            # Detailed
vcover report merged.ucdb -summary            # Summary only

# Specific metrics
vcover report merged.ucdb -toggle             # Toggle only
vcover report merged.ucdb -fsm                # FSM only
vcover report merged.ucdb -condition           # Condition only
vcover report merged.ucdb -branch              # Branch only
vcover report merged.ucdb -statement           # Statement only
vcover report merged.ucdb -cvg                 # Functional only
vcover report merged.ucdb -assert              # Assertion only

# Coverage holes
vcover report merged.ucdb -zeros              # Show zero-coverage items
vcover report merged.ucdb -belowlimit 90      # Items below 90%

# Per-instance report
vcover report merged.ucdb -instance=/top/dut

# Test ranking
vcover ranktest merged.ucdb -output ranking.txt

# Exclusion
vcover report merged.ucdb -excludefile excl.do

# Export
vcover report merged.ucdb -output cov.xml -xml
```

### 4.3 Questa Coverage Commands (Interactive)

```tcl
# In vsim interactive mode

# Enable coverage
coverage save -onexit -cvg -codeAll coverage.ucdb

# Query coverage during simulation
coverage report -summary
coverage report -detail /top/dut

# Add exclusions interactively
coverage exclude -src design.sv -line 42 -comment "Dead code"
coverage exclude -toggle /top/dut/reserved -comment "Reserved"
coverage exclude -branch /top/dut/ctrl -line 100 -comment "Not reachable"

# Save exclusions
coverage save exclusions.ucdb
coverage exclude -save excl.do

# Coverage-driven simulation control
# Stop when coverage target reached
coverage configure -target 95

# View coverage in GUI
coverage open merged.ucdb
```

### 4.4 Questa Exclusion Files

```tcl
# Exclusion file format (.do)

# Statement exclusion
coverage exclude -src fifo.sv -line 42 \
    -comment "Debug-only code"

# Branch exclusion
coverage exclude -branch -src ctrl.sv -line 100 -item 3 \
    -comment "Reserved case branch"

# Toggle exclusion
coverage exclude -toggle -scope /top/dut/regs -signal reserved \
    -comment "Reserved bits tied to 0"

# Condition exclusion
coverage exclude -condition -src arb.sv -line 55 -row 3 \
    -comment "Impossible condition combination"

# FSM exclusion
coverage exclude -fsm -scope /top/dut/fsm -state ERROR \
    -comment "Error state tested separately"

# Instance exclusion
coverage exclude -scope /top/dut/debug -all \
    -comment "Debug module excluded from coverage"
```

---

## 5. Verdi Coverage Visualization

### 5.1 Verdi Coverage Analysis

Verdi provides graphical coverage visualization integrated with the waveform
viewer.

**Loading Coverage:**

```bash
# Launch Verdi with coverage
verdi -cov -covdir merged.vdb

# Launch with design and coverage
verdi -ssf waves.fsdb -cov -covdir merged.vdb

# Coverage-specific launch
verdi -covdir merged.vdb -covFSMDir fsm_data
```

**Verdi Coverage Features:**

```
1. Source Code Annotation:
   - Green: covered
   - Red: uncovered
   - Yellow: partially covered
   - Gray: excluded

2. Hierarchy Browser:
   - Per-module coverage percentages
   - Drill down from block to signal level
   - Color-coded coverage indicators

3. Coverage Metrics Window:
   - Statement, branch, condition, toggle, FSM
   - Functional coverage (covergroups)
   - Assertion coverage
   - Sort by coverage percentage

4. Unreachable Code Analysis:
   - Automatic detection of unreachable code
   - Formal-based analysis of impossible conditions
   - Reduces false coverage holes

5. Coverage Comparison:
   - Compare coverage between runs
   - Identify incremental coverage from new tests
   - Delta coverage visualization
```

### 5.2 Verdi Coverage Commands

```tcl
# In Verdi TCL console

# Load coverage
covLoadData -dir merged.vdb

# Set coverage metric
covSetMetric -line -branch -cond -toggle -fsm

# Navigate to uncovered items
covGotoUncovered -next
covGotoUncovered -prev

# Filter by coverage percentage
covSetFilter -belowLimit 90

# Generate report
covReport -all -output report.txt
covReport -summary -output summary.txt

# Exclusion
covExclude -line -file ctrl.sv -lineNo 42 -comment "Dead code"
covSaveExclusion -file exclusions.el

# Comparison
covCompare -baseline run1.vdb -current run2.vdb -report delta.txt
```

### 5.3 Unreachable Code Analysis

Verdi can perform formal analysis to identify structurally unreachable code,
reducing false coverage holes.

```bash
# Enable unreachable analysis during simulation
vcs -cm line+cond+branch \
    -cm_seqnoconst \
    -cm_constfile const_analysis.cfg

# In Verdi, use Coverage -> Unreachable Analysis
# This identifies:
# - Dead code branches
# - Impossible condition combinations
# - Unreachable FSM states/transitions
# - Constant propagation effects
```

---

## 6. Functional Coverage Deep Dive

### 6.1 Covergroup Syntax

```systemverilog
// Basic covergroup
covergroup cg_transaction @(posedge clk iff valid);
  option.per_instance = 1;
  option.name = "Transaction Coverage";
  option.comment = "Covers all transaction types and sizes";
  option.goal = 100;
  option.at_least = 1;
  option.auto_bin_max = 64;
  option.weight = 1;

  // Coverpoints
  cp_cmd: coverpoint cmd {
    bins read  = {CMD_READ};
    bins write = {CMD_WRITE};
    bins rmw   = {CMD_RMW};
    illegal_bins illegal = default;
  }

  cp_size: coverpoint size {
    bins byte_xfer = {1};
    bins half_word = {2};
    bins word      = {4};
    bins dword     = {8};
    bins large     = {[16:256]};
  }

  cp_addr: coverpoint addr[31:28] {
    bins region[] = {[0:15]};
  }

  // Cross coverage
  cx_cmd_size: cross cp_cmd, cp_size;
endgroup
```

### 6.2 Advanced Coverpoint Features

```systemverilog
covergroup cg_advanced @(sample_event);

  // Bin ranges and arrays
  cp_data: coverpoint data {
    bins zero       = {0};
    bins small      = {[1:255]};
    bins medium     = {[256:65535]};
    bins large      = {[65536:$]};
    bins max        = {{32{1'b1}}};
    bins powers[]   = {1, 2, 4, 8, 16, 32, 64, 128};
    wildcard bins msb_set = {32'b1???_????_????_????_????_????_????_????};
  }

  // Transition coverage
  cp_state: coverpoint state {
    bins normal[]   = (IDLE => ACTIVE => DONE => IDLE);
    bins error_path = (ACTIVE => ERROR => IDLE);
    bins restart    = (ERROR => IDLE => ACTIVE);
    bins toggle[]   = (IDLE => ACTIVE), (ACTIVE => IDLE);
    bins multi_done = (ACTIVE => DONE [*3:5]);  // 3-5 consecutive DONE
    illegal_bins bad_trans = (IDLE => DONE);
  }

  // Conditional coverage
  cp_error_type: coverpoint error_type iff (error_valid) {
    bins timeout  = {ERR_TIMEOUT};
    bins parity   = {ERR_PARITY};
    bins overflow = {ERR_OVERFLOW};
  }

  // Expression coverpoint
  cp_flags: coverpoint {full, empty, overflow, underflow} {
    bins normal    = {4'b0000};
    bins full_only = {4'b1000};
    bins empty_only = {4'b0100};
    wildcard bins any_error = {4'b??1?};
  }

  // Auto bins with maximum
  cp_latency: coverpoint latency_cycles {
    option.auto_bin_max = 16;
  }

  // Ignore bins
  cp_channel: coverpoint channel {
    bins active_ch[] = {[0:7]};
    ignore_bins reserved = {[8:15]};
  }
endgroup
```

### 6.3 Cross Coverage

```systemverilog
covergroup cg_cross @(sample_event);
  cp_cmd: coverpoint cmd { bins read = {0}; bins write = {1}; }
  cp_size: coverpoint size { bins b1 = {1}; bins b4 = {4}; bins b8 = {8}; }
  cp_channel: coverpoint channel { bins ch[] = {[0:3]}; }
  cp_priority: coverpoint priority { bins low = {0}; bins high = {1}; }

  // Simple cross
  cx_cmd_size: cross cp_cmd, cp_size;

  // Cross with ignore
  cx_cmd_size_ch: cross cp_cmd, cp_size, cp_channel {
    ignore_bins no_burst_read = binsof(cp_cmd.read) && binsof(cp_size.b8);
    ignore_bins ch0_only_small = binsof(cp_channel) intersect {0}
                                && binsof(cp_size) intersect {8};
  }

  // Cross with bins selection
  cx_cmd_pri: cross cp_cmd, cp_priority {
    bins high_priority_write = binsof(cp_cmd.write) && binsof(cp_priority.high);
    bins low_priority_read   = binsof(cp_cmd.read) && binsof(cp_priority.low);
  }

  // Three-way cross
  cx_full: cross cp_cmd, cp_size, cp_priority;
endgroup
```

### 6.4 Covergroup Sampling Methods

```systemverilog
// Method 1: Clock-based sampling
covergroup cg1 @(posedge clk);
  // ...
endgroup

// Method 2: Event-based sampling
covergroup cg2 @(sample_event);
  // ...
endgroup

// Method 3: Explicit sampling in procedural code
covergroup cg3;
  // ...
endgroup
cg3 cg_inst = new();
// Later:
cg_inst.sample();

// Method 4: Conditional sampling
covergroup cg4 @(posedge clk iff (valid && !reset));
  // ...
endgroup

// Method 5: Sampling with arguments
covergroup cg5 with function sample(bit [1:0] mode, int count);
  cp_mode: coverpoint mode;
  cp_count: coverpoint count { bins ranges[] = {[0:10], [11:100], [101:$]}; }
endgroup
cg5 cg_inst = new();
cg_inst.sample(current_mode, transaction_count);

// Method 6: Sample in UVM subscriber
class my_coverage extends uvm_subscriber #(my_transaction);
  covergroup cg;
    cp_cmd: coverpoint tr.cmd;
    cp_addr: coverpoint tr.addr;
  endgroup

  my_transaction tr;

  function void write(my_transaction t);
    tr = t;
    cg.sample();
  endfunction
endclass
```

### 6.5 Coverage Options

```systemverilog
covergroup cg_with_options @(posedge clk);

  // Type-level options (apply to all instances)
  type_option.weight = 1;
  type_option.goal = 100;
  type_option.comment = "Main transaction coverage";
  type_option.strobe = 1;           // Sample in Postponed region
  type_option.merge_instances = 1;  // Merge all instance coverage

  // Instance-level options
  option.per_instance = 1;          // Track per-instance coverage
  option.name = "cg_inst";         // Instance name
  option.comment = "Instance coverage";
  option.goal = 100;               // Coverage goal
  option.at_least = 1;            // Minimum hits per bin
  option.auto_bin_max = 64;       // Max auto-generated bins
  option.weight = 1;              // Weight for overall coverage
  option.cross_num_print_missing = 10;  // Print up to 10 missing cross bins
  option.detect_overlap = 1;      // Detect overlapping bins

  cp_example: coverpoint data {
    option.auto_bin_max = 32;     // Per-coverpoint option
    option.at_least = 5;          // Need 5 hits per bin
    option.weight = 2;            // Double weight
    option.goal = 95;             // 95% goal for this coverpoint
  }
endgroup
```

---

## 7. Coverage Closure Methodology

### 7.1 Coverage Analysis Workflow

```
Coverage Closure Workflow:
==========================

1. COLLECT
   - Run regression suite
   - Collect code and functional coverage

2. MERGE
   - Merge all test coverage into single database
   - Apply exclusion files

3. ANALYZE
   - Review coverage dashboard
   - Identify holes (uncovered items)
   - Categorize holes

4. CATEGORIZE HOLES
   For each uncovered item:
   a. UNREACHABLE: Code/condition that cannot be exercised
      -> Action: Add exclusion with justification
   b. UNTESTED: Missing test scenario
      -> Action: Create new test or modify existing
   c. UNDERTESTED: Partially covered, needs more seeds/runs
      -> Action: Add more random seeds or directed stimulus
   d. COVERAGE MODEL ERROR: Incorrect coverage definition
      -> Action: Fix coverage model
   e. DESIGN BUG: Uncovered due to design issue
      -> Action: File bug, fix design

5. IMPLEMENT
   - Write new tests
   - Update constraints
   - Add exclusions
   - Fix coverage model issues

6. VERIFY
   - Re-run regression with new tests
   - Re-merge coverage
   - Verify holes are filled
   - Check no regression in other coverage

7. SIGN-OFF
   - Final coverage review
   - Exclusion review
   - Coverage closure report
```

### 7.2 Creating Directed Tests for Coverage Holes

```systemverilog
// Example: Coverage hole identified for burst length = 256

// Step 1: Identify the missing scenario
// Functional coverage shows: cp_burst_len bin "max" has 0 hits

// Step 2: Create targeted sequence
class max_burst_sequence extends base_sequence;
  `uvm_object_utils(max_burst_sequence)

  task body();
    my_transaction tr;
    tr = my_transaction::type_id::create("tr");
    start_item(tr);
    assert(tr.randomize() with {
      burst_len == 256;  // Target the missing bin
      cmd == CMD_WRITE;  // Try both directions
    });
    finish_item(tr);

    // Also cover read
    tr = my_transaction::type_id::create("tr");
    start_item(tr);
    assert(tr.randomize() with {
      burst_len == 256;
      cmd == CMD_READ;
    });
    finish_item(tr);
  endtask
endclass

// Step 3: Create test using this sequence
class max_burst_test extends base_test;
  task run_phase(uvm_phase phase);
    max_burst_sequence seq;
    phase.raise_objection(this);
    seq = max_burst_sequence::type_id::create("seq");
    seq.start(env.agent.sequencer);
    phase.drop_objection(this);
  endtask
endclass
```

### 7.3 Coverage Waiver Documentation

```
Coverage Waiver Template:
=========================
Waiver ID:       COV-WAIVE-XXXX
Coverage Type:   Code/Functional/Assertion
Item:            Specific coverage item description
Module/Instance: Hierarchy path
Reason:          Why this cannot be covered
Category:        Unreachable/By-Design/Tool-Limitation
Risk:            None/Low/Medium/High
Approved By:     Name, Date
Review Date:     YYYY-MM-DD

Example:
Waiver ID:       COV-WAIVE-0042
Coverage Type:   Branch
Item:            case default in cmd_decoder.sv:142
Module/Instance: tb.dut.u_decoder
Reason:          All 4 valid commands are enumerated in case
                 statement. Default branch is for safety only
                 and cannot be reached with valid inputs.
Category:        Unreachable
Risk:            None
Approved By:     J. Smith, 2024-03-15
```

### 7.4 Coverage Metric Correlation

```
Metric Correlation Analysis:
============================

1. Code coverage gaps often correlate with functional coverage gaps
   - Low branch coverage in a module -> likely missing test scenarios

2. High code coverage with low functional coverage indicates:
   - Tests exercise code but not meaningful scenarios
   - Coverage model may need enrichment

3. High functional coverage with low code coverage indicates:
   - Coverage model may be too coarse
   - Dead code or untested error paths

4. Cross-metric analysis:
   - If statement coverage is high but branch coverage is low,
     tests follow only happy paths
   - If toggle coverage is low on specific bits,
     data patterns may be limited
```

---

## 8. Coverage Tool Comparison

### 8.1 Feature Comparison

| Feature | VCS (URG) | Xcelium (IMC) | Questa (vcover) |
|---------|-----------|---------------|-----------------|
| Code coverage | Yes | Yes | Yes |
| Functional coverage | Yes | Yes | Yes |
| Assertion coverage | Yes | Yes | Yes |
| Coverage merge | urg -dir | imc merge | vcover merge |
| HTML reports | Yes | Yes | Yes |
| Text reports | Yes | Yes | Yes |
| Test grading | urg -grade | imc grade | vcover ranktest |
| Exclusion files | .el | .vRefine | .do |
| Unreachable analysis | With Verdi | With JasperGold | With Questa Formal |
| GUI analysis | Verdi | IMC GUI | Questa GUI |
| Database format | .vdb | cov_work | .ucdb |
| Incremental merge | Yes | Yes | Yes |
| Cross-coverage | Yes | Yes | Yes |

### 8.2 Command-Line Quick Reference

```bash
# Merge coverage
# VCS:
urg -dir run*/simv.vdb -dbname merged.vdb -report report

# Xcelium:
imc -batch -exec 'merge run1 run2 -output merged -overwrite; exit'

# Questa:
vcover merge merged.ucdb run1.ucdb run2.ucdb

# Generate report
# VCS:
urg -dir merged.vdb -report report_dir -format html

# Xcelium:
imc -batch -exec 'load -run merged; report -detail -all -out report.html -format html; exit'

# Questa:
vcover report merged.ucdb -output report.html -html

# Apply exclusions
# VCS:
urg -dir merged.vdb -elfile excl.el -report report

# Xcelium:
imc -batch -exec 'load -run merged; load -refinement excl.vRefine; report -all; exit'

# Questa:
vcover report merged.ucdb -excludefile excl.do -output report.txt
```

---

## 9. Best Practices

### 9.1 Coverage Collection Best Practices

1. **Collect on DUT only** - exclude testbench from code coverage.
2. **Use hierarchy files** to precisely control what is covered.
3. **Name tests/seeds** in coverage databases for traceability.
4. **Use per-instance** functional coverage to catch instance-specific issues.
5. **Sample functional coverage at meaningful events**, not every clock.
6. **Set auto_bin_max** to reasonable values to avoid bin explosion.
7. **Use illegal_bins** to catch design violations.
8. **Define transition coverage** for state machines and protocols.

### 9.2 Coverage Analysis Best Practices

1. **Merge before analyzing** - individual test coverage is misleading.
2. **Track coverage trends** over time (daily/weekly).
3. **Analyze coverage incrementally** - focus on new holes, not all holes.
4. **Grade tests** to find the minimal set achieving target coverage.
5. **Review exclusions** periodically as design evolves.
6. **Correlate code and functional coverage** to find gaps in both.
7. **Document all exclusions** with clear justifications.
8. **Set realistic goals** - 100% may not be achievable or meaningful.

### 9.3 Coverage Closure Best Practices

1. **Start coverage closure early** - do not wait until end of project.
2. **Set intermediate milestones** (e.g., 80% by Week 4, 90% by Week 8).
3. **Prioritize based on risk** - close critical features first.
4. **Use formal tools** for unreachable analysis before manual exclusion.
5. **Automate coverage reporting** in regression infrastructure.
6. **Track coverage per feature** in addition to per module.
7. **Review coverage model** at each design change.
8. **Maintain exclusion hygiene** - remove stale exclusions.

---
