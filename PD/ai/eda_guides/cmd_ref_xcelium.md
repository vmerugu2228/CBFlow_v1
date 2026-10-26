# Cadence Xcelium Simulator — Comprehensive Command Reference

## Table of Contents
1. [Overview](#overview)
2. [Multi-Step Compilation Flow](#multi-step-compilation-flow)
3. [Single-Command Flow (xrun)](#single-command-flow-xrun)
4. [Debug Capabilities](#debug-capabilities)
5. [Coverage](#coverage)
6. [UVM Support](#uvm-support)
7. [Performance Optimization](#performance-optimization)
8. [Mixed-Signal Simulation (AMS)](#mixed-signal-simulation-ams)
9. [Low-Power Simulation (UPF)](#low-power-simulation-upf)
10. [Waveform and Transaction Debug](#waveform-and-transaction-debug)
11. [Licensing and Environment](#licensing-and-environment)
12. [Common Flows and Recipes](#common-flows-and-recipes)

---

## Overview

Cadence Xcelium is a multi-engine simulation platform supporting Verilog, SystemVerilog, VHDL, SystemC, e (Specman), and mixed-language designs. Xcelium provides both a multi-step (analyze-elaborate-simulate) flow and a single-command (xrun) flow.

### Key Capabilities
- Multi-engine architecture: event-driven, dataflow, multi-core
- Xcelium ML (Machine Learning) for automatic performance optimization
- Native UVM/OVM/VMM support
- Integrated coverage (functional, code, assertion)
- Low-power simulation with IEEE 1801 (UPF) support
- Mixed-signal simulation (AMS, connect modules)
- Indago interactive debug platform
- Transaction-level debug and protocol analysis

### Architecture

Xcelium uses three simulation engines:
1. **xmvlog/xmvhdl** -- Analyzers (parsing and semantic checks)
2. **xmelab** -- Elaborator (design hierarchy build, optimization)
3. **xmsim** -- Simulator (execution engine)

The `xrun` command wraps all three steps into a single invocation.

---

## Multi-Step Compilation Flow

### xmvlog -- Verilog/SystemVerilog Analyzer

```
xmvlog [options] <source_files>
```

#### Source File Options

| Option | Description |
|--------|-------------|
| `<file.v>` | Verilog source files |
| `<file.sv>` | SystemVerilog source files |
| `-f <filelist>` | Read source filenames from filelist |
| `-F <filelist>` | Read filelist (relative paths from filelist location) |
| `-v <lib_file>` | Verilog library file |
| `-y <lib_dir>` | Library directory |
| `+libext+<ext>` | Library file extensions |
| `+incdir+<dir>` | Include directory for `include |
| `+define+<macro>=<value>` | Define preprocessor macro |
| `+define+<macro>` | Define macro (no value) |

#### Language Options

| Option | Description |
|--------|-------------|
| `-sv` | Enable SystemVerilog |
| `-v200x` | Verilog-2001/2005 support |
| `-v1995` | Verilog-1995 strict mode |
| `-ams` | Enable AMS extensions |
| `-assert` | Enable SVA |
| `+ncsv+` | Shorthand for SystemVerilog |

#### Compilation Control

| Option | Description |
|--------|-------------|
| `-work <library>` | Specify work library |
| `-cdslib <file>` | CDS library definition file |
| `-hdlvar <file>` | HDL variable file |
| `-update` | Incremental analysis (re-analyze changed files only) |
| `-64bit` | 64-bit compilation |
| `-nowarn <code>` | Suppress specific warning |
| `-errormax <N>` | Maximum errors before abort |
| `-status` | Print analysis status |
| `-messages` | Show all messages |
| `-logfile <file>` | Log to file |
| `-quiet` | Quiet mode |
| `-DEFINE <macro>=<value>` | Define HDL macro (alternative syntax) |

### xmvhdl -- VHDL Analyzer

```
xmvhdl [options] <source_files>
```

| Option | Description |
|--------|-------------|
| `-v93` | VHDL-93 mode (default) |
| `-v200x` | VHDL-2008 mode |
| `-work <library>` | Specify work library |
| `-cdslib <file>` | CDS library definition file |
| `-f <filelist>` | Read filelist |
| `-64bit` | 64-bit mode |
| `-nowarn <code>` | Suppress warning |
| `-messages` | Show all messages |
| `-logfile <file>` | Log to file |
| `-relax` | Relaxed VHDL rules |
| `-psl` | Enable PSL assertions |

### xmelab -- Elaborator

```
xmelab [options] <top_unit>
```

#### Basic Options

| Option | Description |
|--------|-------------|
| `<lib.cell:view>` | Specify top-level unit to elaborate |
| `-work <library>` | Specify work library |
| `-cdslib <file>` | CDS library definition file |
| `-64bit` | 64-bit mode |
| `-timescale <ts>/<tp>` | Default timescale |
| `-override_timescale <ts>/<tp>` | Override all timescales |
| `-top <module>` | Specify top-level module |
| `-snapshot <name>` | Name the elaborated snapshot |
| `-logfile <file>` | Log to file |
| `-quiet` | Quiet mode |
| `-messages` | Show all messages |
| `-errormax <N>` | Max errors |

#### Debug and Access Options

| Option | Description |
|--------|-------------|
| `-access +rwc` | Full debug access (read, write, connectivity) |
| `-access +r` | Read-only access to all signals |
| `-access +w` | Write (force) access |
| `-access +c` | Connectivity (drivers/loads) access |
| `-access +rw` | Read and write access |
| `-createdebugdb` | Create debug database for Indago |
| `-classlinedebug` | Enable class-level line debug |
| `-linedebug` | Enable source line debug |
| `-uvmlinedebug` | UVM source line debug |
| `-genafile <file>` | Access file for fine-grained control |

#### Access File Format

```
# access.cfg
# Fine-grained debug access control

# Full access for DUT
begin scope tb_top.dut
    access +rwc
end

# Read-only for testbench (saves performance)
begin scope tb_top.u_tb
    access +r
end

# No access for clock gen (fastest)
begin scope tb_top.clk_gen
    access +NONE
end
```

#### Optimization Options

| Option | Description |
|--------|-------------|
| `-noopt` | Disable all optimizations |
| `-opt_partition <file>` | Partition optimization configuration |
| `-newperf` | Enable new performance engine |
| `-fast_recompilation` | Enable fast recompilation |

#### Gate-Level Options

| Option | Description |
|--------|-------------|
| `-negdelay` | Enable negative delay handling |
| `-notimingchecks` | Disable timing checks |
| `-nospecify` | Ignore specify blocks |
| `-delay_mode zero` | Zero delay mode |
| `-delay_mode unit` | Unit delay mode |
| `-delay_mode path` | Path delay mode |
| `-delay_mode distributed` | Distributed delay mode |
| `-sdf_cmd_file <file>` | SDF command file |
| `-sdf_verbose` | Verbose SDF annotation |
| `-pulse_e/<pct>` | Pulse error limit |
| `-pulse_r/<pct>` | Pulse reject limit |
| `-maxdelays` | Use max SDF delays |
| `-mindelays` | Use min SDF delays |
| `-typdelays` | Use typical SDF delays |

#### SDF Command File Format

```
// sdf_cmd.cfg
COMPILED_SDF_FILE = "chip.sdf.X",
  SCOPE = tb_top.dut,
  MTM_SPEC = MAXIMUM,
  SCALE_FACTORS = "1.0:1.0:1.0",
  SCALE_TYPE = FROM_MTM;
```

### xmsim -- Simulator

```
xmsim [options] [snapshot_name]
```

#### Basic Options

| Option | Description |
|--------|-------------|
| `<snapshot>` | Snapshot name to simulate |
| `-input <tcl_file>` | Source TCL commands at startup |
| `-run` | Run simulation (non-interactive) |
| `-gui` | Launch GUI (Indago or SimVision) |
| `-indago` | Launch Indago debug |
| `-logfile <file>` | Log to file |
| `-quiet` | Quiet mode |
| `-64bit` | 64-bit mode |
| `-status` | Print simulation status |
| `-seed <value>` | Random seed |
| `-seed random` | Random seed (time-based) |

#### Runtime Options

| Option | Description |
|--------|-------------|
| `-stop` | Stop at time 0 (enter interactive mode) |
| `-run <time>` | Run for specified time |
| `-exit` | Exit after simulation completes |
| `-input <file>` | Source TCL script at startup |
| `-tcl` | Enter TCL mode |
| `-nontcl` | Non-TCL mode (no interactive) |
| `-unbuffered` | Unbuffered output |
| `-messages` | Show all messages |
| `-nowarn <code>` | Suppress warnings |
| `-nokey` | Disable key file |

#### Initialization Options

| Option | Description |
|--------|-------------|
| `-xminitialize 0` | Initialize all registers to 0 |
| `-xminitialize 1` | Initialize all registers to 1 |
| `-xminitialize x` | Initialize to X (default) |
| `-xminitialize rand:seed` | Random initialization with seed |
| `-xmpropalikealiasaliases` | Propagate X through design |

---

## Single-Command Flow (xrun)

### xrun Overview

`xrun` wraps the entire analyze-elaborate-simulate flow into a single command. It automatically determines file types and manages the compilation flow.

```
xrun [options] <source_files>
```

### Source Specification

| Option | Description |
|--------|-------------|
| `<file.v>` | Verilog source |
| `<file.sv>` | SystemVerilog source |
| `<file.vhd>` | VHDL source |
| `<file.c>` | C source (DPI) |
| `<file.cpp>` | C++ source (DPI/SystemC) |
| `-f <filelist>` | Read filelist |
| `-F <filelist>` | Read filelist (relative paths) |
| `-v <lib_file>` | Library file |
| `-y <lib_dir>` | Library directory |
| `+libext+<ext>` | Library extensions |
| `+incdir+<dir>` | Include directory |
| `+define+<macro>=<value>` | Define macro |

### Language Options

| Option | Description |
|--------|-------------|
| `-sv` | Enable SystemVerilog |
| `-v200x` | Verilog-2001/2005 |
| `-vhdltop <entity>` | Specify VHDL top entity |
| `-top <module>` | Specify top module |
| `-ams` | Enable AMS |
| `-assert` | Enable SVA |

### Compilation and Elaboration

| Option | Description |
|--------|-------------|
| `-64bit` | 64-bit mode |
| `-elaborate` | Stop after elaboration (don't simulate) |
| `-compile` | Stop after compilation (don't elaborate) |
| `-timescale <ts>/<tp>` | Default timescale |
| `-override_timescale <ts>/<tp>` | Override timescales |
| `-snapshot <name>` | Snapshot name |
| `-update` | Incremental compilation |
| `-clean` | Clean before compiling |
| `-xmlibdirpath <path>` | Library directory path |
| `-xmlibdirname <name>` | Library directory name |
| `-cdslib <file>` | CDS library file |
| `-hdlvar <file>` | HDL variable file |

### Debug Options

| Option | Description |
|--------|-------------|
| `-access +rwc` | Full debug access |
| `-createdebugdb` | Create Indago debug database |
| `-linedebug` | Line-level debug |
| `-classlinedebug` | Class line debug |
| `-uvmlinedebug` | UVM line debug |
| `-kdb` | Knowledge database (for some debug features) |
| `-gui` | Launch GUI |
| `-indago` | Launch Indago |
| `-tcl` | Interactive TCL mode |
| `-input <file>` | Source TCL file |

### Simulation Runtime

| Option | Description |
|--------|-------------|
| `-R` | Run simulation only (use existing snapshot) |
| `-run` | Auto-run (non-interactive) |
| `-exit` | Exit after completion |
| `-seed <value>` | Random seed |
| `-seed random` | Random seed |
| `-logfile <file>` | Log file |
| `-quiet` | Quiet mode |
| `-stop` | Stop at time 0 |
| `+xmstop+<time>` | Stop at time |
| `+xmfinish+<time>` | Finish at time |

### Coverage Options (xrun)

| Option | Description |
|--------|-------------|
| `-coverage all` | Enable all code coverage |
| `-coverage line` | Line coverage |
| `-coverage block` | Block coverage |
| `-coverage expression` | Expression coverage |
| `-coverage toggle` | Toggle coverage |
| `-coverage fsm` | FSM coverage |
| `-coverage functional` | Functional coverage |
| `-covoverwrite` | Overwrite existing coverage data |
| `-covfile <file>` | Coverage configuration file |
| `-covtest <name>` | Test name for coverage |
| `-covworkdir <dir>` | Coverage work directory |
| `-covdut <instance>` | DUT instance for coverage |

### UPF (Low-Power) Options

| Option | Description |
|--------|-------------|
| `-upf <file>` | Specify UPF file |
| `-upf2` | UPF 2.0/2.1 mode |
| `-upfexpandaliases` | Expand UPF aliases |
| `-lps_1801` | IEEE 1801 compliance |
| `-lps_verbose` | Verbose low-power messages |
| `-lps_iso_verbose` | Verbose isolation info |
| `-lps_lofile <file>` | Low-power log file |
| `-lps_nonfatal` | Make LP errors non-fatal |

### xrun Usage Examples

```bash
# Simple RTL simulation
xrun -sv -64bit -timescale 1ns/1ps \
    -f rtl.flist tb_top.sv \
    -access +rwc -run -exit \
    -logfile sim.log

# UVM simulation
xrun -sv -64bit -timescale 1ns/1ps \
    -uvm \
    -f rtl.flist -f tb.flist \
    -access +rwc \
    -coverage all -covdut tb_top.dut \
    +UVM_TESTNAME=smoke_test \
    +UVM_VERBOSITY=UVM_MEDIUM \
    -seed 42 \
    -run -exit \
    -logfile sim.log

# Gate-level with SDF
xrun -sv -64bit \
    -negdelay \
    -sdf_cmd_file sdf_cmd.cfg \
    +define+GATE_SIM \
    -v std_cell.v -v io_cell.v \
    netlist.v tb_top.sv \
    -run -exit \
    -logfile gate_sim.log

# Elaborate only
xrun -sv -64bit -elaborate \
    -f rtl.flist -f tb.flist \
    -snapshot my_snap

# Simulate existing snapshot
xrun -R -64bit my_snap \
    +UVM_TESTNAME=test1 \
    -seed random \
    -run -exit
```

---

## Debug Capabilities

### Compile-Time Debug Access

The `-access` flag controls debug visibility:

| Flag | Meaning |
|------|---------|
| `+r` | Read signal values |
| `+w` | Write/force signal values |
| `+c` | Connectivity (drivers, loads) |
| `+rwc` | Full access (recommended for debug) |
| `+NONE` | No access (fastest) |
| `+<flag>+<scope>` | Per-scope access |

```bash
# Full access everywhere
xrun ... -access +rwc

# Fine-grained access
xrun ... -access +r -access +rwc+tb_top.dut
```

### Indago Interactive Debug

Indago is Cadence's next-generation debug platform with time-travel debugging.

#### Launch Methods

```bash
# Launch Indago from xrun
xrun ... -gui -indago -createdebugdb

# Launch Indago standalone
indago -db indago_db

# Launch with waveform
indago -db indago_db -waveform waves.shm
```

#### Indago Capabilities
- **Time-travel debug**: step forward and backward through simulation
- **Root-cause analysis**: trace signal drivers through time
- **Class-aware debug**: inspect UVM/OOP object hierarchy
- **Transaction debug**: visualize transaction flow
- **Assertion debug**: SVA waveform correlation

### TCL Debug Commands

When running in interactive/TCL mode, these commands are available:

#### Navigation Commands

| Command | Description |
|---------|-------------|
| `run` | Run to completion |
| `run <time>` | Run for specified time |
| `run -next` | Run to next time step |
| `stop` | Stop simulation |
| `step` | Step one line |
| `step -over` | Step over task/function |
| `step -out` | Step out of task/function |
| `step -statement` | Step one statement |
| `cont` | Continue execution |
| `finish` | Finish simulation |
| `exit` | Exit simulator |

#### Breakpoint Commands

| Command | Description |
|---------|-------------|
| `stop -create -name bp1 -posedge clk` | Break on posedge |
| `stop -create -name bp2 -negedge rst_n` | Break on negedge |
| `stop -create -name bp3 -change sig` | Break on change |
| `stop -create -name bp4 -condition {sig == 8'hFF}` | Break on condition |
| `stop -create -name bp5 -line file.sv 100` | Break at source line |
| `stop -create -name bp6 -time 1us` | Break at time |
| `stop -create -name bp7 -object sig -value 4'b1010` | Break at value |
| `stop -delete <name>` | Delete breakpoint |
| `stop -disable <name>` | Disable breakpoint |
| `stop -enable <name>` | Enable breakpoint |
| `stop -show` | List breakpoints |

#### Signal Access Commands

| Command | Description |
|---------|-------------|
| `value <signal>` | Get signal value |
| `force <signal> <value>` | Force signal |
| `force <signal> <value> -after <time>` | Force after delay |
| `force -deposit <signal> <value>` | Deposit value |
| `force -drive <signal> <value>` | Drive value |
| `release <signal>` | Release forced signal |
| `describe <signal>` | Signal description |
| `drivers <signal>` | Show drivers |
| `loads <signal>` | Show loads |
| `scope` | Current scope |
| `scope <path>` | Change scope |
| `scope -up` | Move up |
| `scope -list` | List children |

#### Waveform TCL Commands

| Command | Description |
|---------|-------------|
| `database -open -name waves -into waves.shm -default` | Open SHM database |
| `probe -create -name p1 -database waves -all -depth all` | Probe all signals |
| `probe -create -name p2 -database waves tb_top.dut.*` | Probe DUT signals |
| `probe -create -database waves -shm -all -memories -depth all` | Full probe with memories |
| `database -flush waves` | Flush waveform |
| `database -close waves` | Close waveform database |

#### TCL Script Example

```tcl
# debug.tcl -- Xcelium TCL debug script

# Open waveform database
database -open -name waves -into waves.shm -default -event

# Probe all DUT signals
probe -create -database waves tb_top.dut -depth all -all

# Set breakpoints
stop -create -name bp_reset -condition {tb_top.rst_n == 1'b0}
stop -create -name bp_error -condition {tb_top.dut.error_flag == 1'b1}
stop -create -name bp_done  -time 100us

# Run simulation
run

# On breakpoint, dump state
if {[stop -info] == "bp_error"} {
    puts "ERROR detected at time [time]"
    puts "PC = [value tb_top.dut.u_cpu.pc]"
    puts "State = [value tb_top.dut.u_cpu.state]"
}

# Continue to completion
run
```

### SimVision (Legacy GUI)

```bash
# Launch SimVision
xrun ... -gui

# Launch SimVision standalone
simvision -input waves.shm

# SimVision with TCL
simvision -input debug.sv.tcl
```

### Save/Restore Checkpoints

```tcl
# Save checkpoint
save -name checkpoint1

# Restore checkpoint
restart -from checkpoint1

# Save to file
task save_state {} {
    set time_now [time]
    save -name "state_${time_now}" -to "checkpoints/"
}
```

---

## Coverage

### Coverage Types

| Type | Option | Description |
|------|--------|-------------|
| Line | `-coverage line` | Statement line execution |
| Block | `-coverage block` | Basic block execution |
| Expression | `-coverage expression` | Expression evaluation |
| Toggle | `-coverage toggle` | Signal toggle activity |
| FSM | `-coverage fsm` | FSM state/transition |
| Functional | `-coverage functional` | SystemVerilog covergroups |
| Assertion | (automatic with SVA) | Assertion pass/fail |
| All | `-coverage all` | All code coverage types |

### Coverage Configuration File

```
# coverage.cfg

# Select coverage metrics
set_expr_coverable_operators -all
set_toggle_portsonly
set_toggle_excludealiases

# Hierarchy control
select_coverage -block -toggle -expression -fsm -instance tb_top.dut...
deselect_coverage -all -instance tb_top.u_tb...
deselect_coverage -all -instance tb_top.clk_gen

# Toggle configuration
set_toggle_strobe -period 10ns
set_toggle_includereg

# FSM configuration
set_fsm_reset_filter on
set_fsm_auto_detect on

# Expression configuration
set_expr_scoring -all
```

```bash
xrun ... -covfile coverage.cfg -coverage all -covdut tb_top.dut
```

### Compile-Time Coverage Options

| Option | Description |
|--------|-------------|
| `-coverage all` | Enable all code coverage |
| `-coverage line` | Line coverage only |
| `-coverage block` | Block coverage |
| `-coverage expression` | Expression coverage |
| `-coverage toggle` | Toggle coverage |
| `-coverage fsm` | FSM coverage |
| `-coverage functional` | Functional coverage |
| `-covoverwrite` | Overwrite existing data |
| `-covfile <file>` | Coverage config file |
| `-covdut <instance>` | DUT for coverage |
| `-covworkdir <dir>` | Coverage output directory |
| `-covdesign <name>` | Design name for coverage |
| `-covtest <name>` | Test name |
| `-covscope <scope>` | Coverage scope |

### Runtime Coverage Control

```tcl
# TCL commands for runtime coverage control
coverage -start                    ;# Start coverage collection
coverage -stop                     ;# Stop coverage collection
coverage -save <filename>          ;# Save coverage data
coverage -reset                    ;# Reset coverage counters
coverage -report -summary          ;# Print coverage summary
```

### IMC (Integrated Metrics Center) -- Coverage Analysis

IMC is the primary tool for coverage analysis, merging, and reporting.

```
imc [options]
```

#### Basic IMC Commands

| Option | Description |
|--------|-------------|
| `-load <dir>` | Load coverage database |
| `-exec <script>` | Execute IMC TCL script |
| `-gui` | Launch GUI |
| `-batch` | Batch mode |
| `-logfile <file>` | Log file |
| `-64bit` | 64-bit mode |

#### IMC TCL Commands

```tcl
# Load coverage databases
load_test test1/cov_work/scope/test1
load_test test2/cov_work/scope/test2
load_test test3/cov_work/scope/test3

# Merge databases
merge -overwrite -out merged_cov -name merged

# Generate reports
report_metrics -out cov_report.txt -detail -summary
report_metrics -out cov_report.html -detail -html

# Query specific metrics
set line_cov [report_metrics -metric line -instance tb_top.dut]
puts "Line coverage: $line_cov"

# Exclusion
load_exclusion exclusions.vRefine
save_exclusion new_exclusions.vRefine

# Refinement
create_exclusion -scope tb_top.dut.u_mem -metric toggle -name "Memory toggle excluded"
```

#### IMC Batch Script

```tcl
# imc_merge.tcl -- IMC batch merge script

# Load all test databases
set test_dirs [glob -directory results */cov_work]
foreach dir $test_dirs {
    load_test $dir/scope/*
}

# Merge
merge -overwrite -out merged_cov -name regression_merge

# Apply exclusions
load_exclusion exclusions.vRefine

# Generate reports
report_metrics -out reports/summary.html -detail -html -metrics all
report_metrics -out reports/line.txt -detail -metrics line -instance tb_top.dut
report_metrics -out reports/toggle.txt -detail -metrics toggle -instance tb_top.dut
report_metrics -out reports/expression.txt -detail -metrics expression -instance tb_top.dut
report_metrics -out reports/fsm.txt -detail -metrics fsm -instance tb_top.dut

# Check coverage thresholds
set total_cov [report_metrics -metric overall -instance tb_top.dut]
if {$total_cov < 95.0} {
    puts "WARNING: Total coverage $total_cov% below 95% target"
}

exit
```

```bash
# Run IMC in batch
imc -64bit -batch -exec imc_merge.tcl -logfile imc.log
```

#### IMC Report Formats

```bash
# Text report
imc -load cov_work -batch -exec "report_metrics -out report.txt -detail"

# HTML report
imc -load cov_work -batch -exec "report_metrics -out report.html -html -detail"

# Specific metric report
imc -load cov_work -batch -exec "report_metrics -metrics line+toggle+expression -out metrics.txt"
```

### Exclusion File Format (.vRefine)

```xml
<!-- exclusions.vRefine -->
<refinement_list>
  <instance name="tb_top.dut.u_pll">
    <metric name="toggle">
      <exclusion>
        <reason>PLL model, not synthesizable RTL</reason>
      </exclusion>
    </metric>
  </instance>
  <instance name="tb_top.dut.u_cpu">
    <metric name="line">
      <line number="142">
        <exclusion>
          <reason>Debug-only code, unreachable in normal operation</reason>
        </exclusion>
      </line>
    </metric>
  </instance>
</refinement_list>
```

---

## UVM Support

### Compile-Time UVM Options

| Option | Description |
|--------|-------------|
| `-uvm` | Include UVM library |
| `-uvmhome <path>` | Specify UVM home directory |
| `-uvmhome CDNS-1.2` | Use Cadence UVM 1.2 |
| `-uvmhome CDNS-1.1d` | Use Cadence UVM 1.1d |
| `-uvmnoautocompile` | Don't auto-compile UVM |
| `-uvmnocdnsextra` | Don't include Cadence extensions |
| `-uvmlinedebug` | UVM source line debug |

### Runtime UVM Options

| Option | Description |
|--------|-------------|
| `+UVM_TESTNAME=<test>` | Specify UVM test class |
| `+UVM_VERBOSITY=<level>` | Set verbosity (UVM_NONE/LOW/MEDIUM/HIGH/FULL/DEBUG) |
| `+UVM_TIMEOUT=<time>,<overridable>` | Set UVM timeout |
| `+UVM_MAX_QUIT_COUNT=<N>` | Max errors |
| `+UVM_PHASE_TRACE` | Trace phase execution |
| `+UVM_OBJECTION_TRACE` | Trace objections |
| `+UVM_CONFIG_DB_TRACE` | Trace config_db |
| `+UVM_RESOURCE_DB_TRACE` | Trace resource_db |
| `+uvm_set_config_int=<inst>,<field>,<value>` | Set config int |
| `+uvm_set_config_string=<inst>,<field>,<value>` | Set config string |
| `+uvm_set_type_override=<orig>,<override>` | Type override |
| `+uvm_set_inst_override=<orig>,<override>,<inst>` | Instance override |
| `+UVM_NO_RELNOTES` | Suppress release notes |
| `+UVM_TR_RECORD` | Transaction recording |

### UVM Compilation Flow

```bash
# Single-command UVM flow
xrun -sv -64bit -uvm -timescale 1ns/1ps \
    -uvmhome CDNS-1.2 \
    -f rtl.flist -f tb.flist \
    -top tb_top \
    -access +rwc -createdebugdb \
    -coverage all -covdut tb_top.dut \
    +UVM_TESTNAME=smoke_test \
    +UVM_VERBOSITY=UVM_MEDIUM \
    -seed 42 \
    -run -exit \
    -logfile sim.log

# Multi-step UVM flow
xmvlog -sv -64bit -uvm -uvmhome CDNS-1.2 -f rtl.flist
xmvlog -sv -64bit -uvm -uvmhome CDNS-1.2 -f tb.flist
xmelab -64bit -uvm -timescale 1ns/1ps -access +rwc -snapshot uvm_snap tb_top
xmsim -64bit uvm_snap +UVM_TESTNAME=smoke_test +UVM_VERBOSITY=UVM_MEDIUM -seed 42
```

### UVM Debug with Xcelium

```bash
# UVM debug with Indago
xrun -sv -64bit -uvm \
    -f rtl.flist -f tb.flist \
    -access +rwc -createdebugdb -uvmlinedebug -classlinedebug \
    +UVM_TESTNAME=failing_test \
    +UVM_VERBOSITY=UVM_DEBUG \
    +UVM_PHASE_TRACE \
    +UVM_OBJECTION_TRACE \
    +UVM_CONFIG_DB_TRACE \
    -gui -indago
```

---

## Performance Optimization

### Xcelium ML (Machine Learning)

Xcelium ML uses machine learning to automatically optimize simulation performance.

```bash
# Enable ML optimization
xrun ... -xmlint

# ML with training
xrun ... -xmlint -xmlint_training

# ML profiling
xrun ... -xmlint -xmlint_profile
```

### Parallel Simulation

| Option | Description |
|--------|-------------|
| `-xmparallel` | Enable parallel simulation |
| `-xmparallel_maxjobs <N>` | Max parallel jobs |
| `+xmparallel+workers=<N>` | Number of worker threads |

```bash
# Parallel simulation
xrun ... -xmparallel +xmparallel+workers=4
```

### Multi-Core Compilation

| Option | Description |
|--------|-------------|
| `-mccomp` | Multi-core compilation |
| `-mccomp_maxjobs <N>` | Max compilation jobs |

```bash
xrun ... -mccomp -mccomp_maxjobs 8
```

### Profiling

```bash
# Time profiling
xrun ... -xmprofile time

# Memory profiling
xrun ... -xmprofile mem

# Event profiling
xrun ... -xmprofile event

# Profile report
xmprof_report -dir xmprofile.dir -out profile_report.html
```

### Optimization Techniques

```bash
# Fast compile (skip optimization)
xrun ... -fast_recompilation

# Incremental compile
xrun ... -update

# Reduce debug overhead
xrun ... -access +NONE  # No debug access (fastest)

# Snapshot reuse
xrun -elaborate ... -snapshot fast_snap
xrun -R fast_snap +UVM_TESTNAME=test1  # Reuse snapshot
xrun -R fast_snap +UVM_TESTNAME=test2
```

---

## Mixed-Signal Simulation (AMS)

### AMS Overview

Xcelium AMS enables mixed-signal simulation combining digital (Verilog/VHDL/SV) with analog (Verilog-AMS/VHDL-AMS/SPICE).

### AMS Compilation

```bash
xrun -sv -ams -64bit \
    -f digital.flist \
    -f analog.flist \
    -discipline logic \
    -amscml connect_lib.vams \
    -amsconnrules user_connect_rules \
    -top tb_top \
    -run -exit
```

### AMS Options

| Option | Description |
|--------|-------------|
| `-ams` | Enable AMS mode |
| `-discipline <name>` | Default discipline |
| `-amscml <file>` | Connect module library |
| `-amsconnrules <name>` | Connect rules |
| `-amscontrol <file>` | Analog control file |
| `-amsie` | AMS-IE (Incisive Extension) mode |
| `-spectre` | Use Spectre engine for analog |
| `-ultrasim` | Use UltraSim engine for analog |

### Connect Modules

```verilog
// d2a_connect.vams -- Digital to Analog connect module
connectmodule d2a (input wire d_in, output electrical a_out);
    parameter real v_high = 1.8;
    parameter real v_low  = 0.0;
    parameter real trise  = 100p;
    parameter real tfall  = 100p;

    analog begin
        V(a_out) <+ transition(d_in ? v_high : v_low, 0, trise, tfall);
    end
endmodule

// a2d_connect.vams -- Analog to Digital connect module
connectmodule a2d (input electrical a_in, output wire d_out);
    parameter real v_thresh = 0.9;

    assign d_out = (V(a_in) > v_thresh) ? 1'b1 : 1'b0;
endmodule
```

### Connect Rules

```
// connect_rules.vams
connectrules user_connect_rules;
    connect d2a (input logic, output electrical) merged;
    connect a2d (input electrical, output logic) merged;
endconnectrules
```

### AMS Control File

```
// ams_control.scs
simulator lang=spectre

tran tran1 stop=100u errpreset=moderate

options options1 reltol=1e-3 abstol=1e-12
```

---

## Low-Power Simulation (UPF)

### UPF Support Overview

Xcelium supports IEEE 1801 (UPF) for power-aware simulation, modeling power domains, isolation, retention, and level shifters.

### Compile-Time UPF Options

| Option | Description |
|--------|-------------|
| `-upf <file>` | Primary UPF file |
| `-upf2` | UPF 2.0/2.1 compliance |
| `-upf3` | UPF 3.0/3.1 compliance |
| `-lps_1801` | Strict IEEE 1801 mode |
| `-lps_verbose` | Verbose low-power messages |
| `-lps_iso_verbose` | Verbose isolation info |
| `-lps_ret_verbose` | Verbose retention info |
| `-lps_lofile <file>` | Low-power log file |
| `-lps_nonfatal` | Non-fatal LP errors |
| `-lps_pst <file>` | Power state table |
| `-lps_suf <file>` | Supply file |

### Runtime UPF Options

| Option | Description |
|--------|-------------|
| `+lps_on` | Enable low-power simulation |
| `+lps_off` | Disable low-power simulation |
| `+lps_iso_on` | Enable isolation |
| `+lps_iso_off` | Disable isolation |
| `+lps_ret_on` | Enable retention |
| `+lps_ret_off` | Disable retention |
| `+lps_cor_on` | Enable corruption |
| `+lps_cor_off` | Disable corruption |

### UPF Example

```tcl
# power_intent.upf

# Create power domains
create_power_domain PD_TOP -include_scope
create_power_domain PD_CPU -elements {u_cpu} \
    -supply {primary VDD_CPU} -supply {backup VDD_RET}
create_power_domain PD_IO -elements {u_io}

# Define supply nets
create_supply_net VDD -domain PD_TOP
create_supply_net VSS -domain PD_TOP
create_supply_net VDD_CPU -domain PD_CPU
create_supply_net VDD_RET -domain PD_CPU

# Create supply sets
create_supply_set SS_CPU -function {power VDD_CPU} -function {ground VSS}
create_supply_set SS_CPU_RET -function {power VDD_RET} -function {ground VSS}

# Define power states
add_power_state PD_CPU \
    -state ON  {-supply_expr {power == FULL_ON}} \
    -state OFF {-supply_expr {power == OFF}} \
    -state RET {-supply_expr {power == OFF && backup == FULL_ON}}

# Isolation
set_isolation iso_cpu -domain PD_CPU \
    -isolation_power_net VDD -isolation_ground_net VSS \
    -clamp_value 0 -applies_to outputs

# Retention
set_retention ret_cpu -domain PD_CPU \
    -retention_power_net VDD_RET -retention_ground_net VSS \
    -save_signal {save_en posedge} -restore_signal {restore_en posedge}

# Level shifters
set_level_shifter ls_cpu_to_io -domain PD_CPU \
    -applies_to outputs -rule low_to_high \
    -location parent
```

### Power-Aware Simulation Flow

```bash
# Compile with UPF
xrun -sv -64bit -uvm \
    -upf power_intent.upf \
    -lps_1801 -lps_verbose \
    -f rtl.flist -f tb.flist \
    -access +rwc \
    +UVM_TESTNAME=power_sequence_test \
    -run -exit \
    -logfile pa_sim.log

# Debug power states
xrun -sv -64bit -uvm \
    -upf power_intent.upf \
    -lps_1801 -lps_verbose -lps_iso_verbose -lps_ret_verbose \
    -lps_lofile lps_debug.log \
    -f rtl.flist -f tb.flist \
    -access +rwc -gui -indago \
    +UVM_TESTNAME=power_debug_test
```

### Power-Aware TCL Commands

```tcl
# Query power domain state
lps -domain PD_CPU -state
lps -domain PD_CPU -supply

# Force power state
lps -domain PD_CPU -force_state ON
lps -domain PD_CPU -force_state OFF

# Query isolation status
lps -isolation iso_cpu -status

# Query retention status
lps -retention ret_cpu -status
```

---

## Waveform and Transaction Debug

### SHM (Simulation History Manager) Waveform

SHM is Xcelium's native waveform format.

#### TCL Probing Commands

```tcl
# Open SHM database
database -open -name waves -into waves.shm -default

# Probe signals
probe -create -database waves tb_top.dut -depth all -all
probe -create -database waves tb_top.dut.u_cpu.* -memories
probe -create -database waves tb_top.dut -depth 1 -ports

# Selective probing
probe -create -database waves tb_top.dut.clk
probe -create -database waves tb_top.dut.data_bus[31:0]

# Probe with conditions
probe -create -database waves tb_top.dut -depth all -all \
    -time_window {100ns 500ns}

# Control probing
probe -disable waves
probe -enable waves

# Flush and close
database -flush waves
database -close waves
```

#### System Tasks for SHM

```systemverilog
initial begin
    // SHM dumping
    $shm_open("waves.shm");
    $shm_probe(tb_top, "ASTM");  // All Signals, Tasks, Memories
    $shm_probe(tb_top.dut, "AS"); // All Signals

    // Control
    $shm_close;
end
```

### FSDB Dumping (for Verdi)

```bash
# Compile with FSDB support
xrun ... -loadpli1 debpli:novas_pli_boot

# Or use environment
export LD_LIBRARY_PATH=$VERDI_HOME/share/PLI/XCELIUM/LINUX64:$LD_LIBRARY_PATH
```

```systemverilog
initial begin
    $fsdbDumpfile("waves.fsdb");
    $fsdbDumpvars(0, tb_top);
    $fsdbDumpvars(0, "+all");
    $fsdbDumpSVA;
end
```

### Transaction Recording

```bash
# Enable transaction recording
xrun ... -uvm +UVM_TR_RECORD \
    -input "database -open -name trdb -into tr.shm -default -event; run"
```

```systemverilog
// In UVM testbench
class my_monitor extends uvm_monitor;
    uvm_analysis_port #(my_transaction) ap;

    task run_phase(uvm_phase phase);
        forever begin
            my_transaction tr = my_transaction::type_id::create("tr");
            // ... collect transaction ...
            tr.enable_recording("my_stream");
            ap.write(tr);
        end
    endtask
endclass
```

### Waveform Comparison

```bash
# Compare two SHM databases
simvision -compare waves1.shm waves2.shm

# Batch comparison
xmsimcomp -ref waves1.shm -new waves2.shm -out compare_report.txt
```

---

## Licensing and Environment

### Environment Variables

| Variable | Description |
|----------|-------------|
| `CDS_LIC_FILE` | License file/server |
| `CDS_INST_DIR` | Cadence installation directory |
| `XCELIUM_HOME` | Xcelium home directory |
| `CDS_LIC_QUEUE_POLL` | License queue poll interval |
| `CDS_LIC_ONLY` | Restrict to specific license features |
| `CDSLIB` | Default CDS library file |
| `HDLVAR` | Default HDL variable file |
| `CDS_AUTO_64BIT` | Auto 64-bit mode |
| `CDS_COVERAGE_OUT` | Coverage output directory |
| `INDAGO_HOME` | Indago installation directory |
| `VERDI_HOME` | Verdi home (for FSDB support) |

### CDS Library File (cds.lib)

```
# cds.lib -- CDS library definition
DEFINE work ./work
DEFINE my_ip_lib ./ip_lib
DEFINE std_cells /libs/std_cells/xcelium

# Include other cds.lib files
INCLUDE /cad/setup/cds.lib
```

### HDL Variable File (hdl.var)

```
# hdl.var -- HDL variable definitions
DEFINE WORK work
DEFINE LIB_MAP (-default_binding_lib work)
DEFINE SV_OPTIONS (-sv -64bit)
```

---

## Common Flows and Recipes

### Basic RTL Simulation

```bash
#!/bin/bash
# basic_sim.sh

xrun -sv -64bit \
    -timescale 1ns/1ps \
    -access +rwc \
    +define+SIMULATION \
    +incdir+./rtl +incdir+./tb \
    -f rtl.flist \
    -f tb.flist \
    -top tb_top \
    -seed 42 \
    -run -exit \
    -logfile sim.log
```

### UVM Regression Flow

```bash
#!/bin/bash
# regression.sh

TESTS=(smoke_test random_test stress_test corner_test error_test)
SEEDS=(42 100 200 300 400)

# Compile once (multi-step for snapshot reuse)
xrun -sv -64bit -uvm -timescale 1ns/1ps \
    -elaborate \
    -f rtl.flist -f tb.flist \
    -top tb_top \
    -access +r \
    -coverage all -covdut tb_top.dut \
    -snapshot regr_snap \
    -logfile compile.log

# Run tests in parallel
for test in "${TESTS[@]}"; do
    for seed in "${SEEDS[@]}"; do
        DIR="results/${test}_s${seed}"
        mkdir -p $DIR
        xrun -R -64bit regr_snap \
            +UVM_TESTNAME=$test \
            +UVM_VERBOSITY=UVM_LOW \
            -seed $seed \
            -covtest ${test}_s${seed} \
            -covworkdir $DIR/cov_work \
            -run -exit \
            -logfile $DIR/sim.log &
    done
done
wait

# Merge coverage
imc -64bit -batch -exec imc_merge.tcl -logfile imc.log

echo "Regression complete"
```

### Gate-Level Simulation

```bash
#!/bin/bash
# gate_sim.sh

xrun -sv -64bit \
    -timescale 1ns/1ps \
    -negdelay \
    +define+GATE_SIM \
    +define+SDF_ANNOTATE \
    -sdf_cmd_file sdf_cmd.cfg \
    -v /libs/std_cell.v \
    -v /libs/io_cell.v \
    -v /libs/sram_model.v \
    netlist.v \
    tb_top.sv \
    -run -exit \
    -logfile gate_sim.log
```

### Power-Aware Simulation

```bash
#!/bin/bash
# pa_sim.sh

xrun -sv -64bit -uvm \
    -timescale 1ns/1ps \
    -upf power_intent.upf \
    -lps_1801 -lps_verbose \
    -f rtl.flist -f tb.flist \
    -access +rwc \
    -coverage all -covdut tb_top.dut \
    +UVM_TESTNAME=power_sequence_test \
    +UVM_VERBOSITY=UVM_MEDIUM \
    -seed 42 \
    -run -exit \
    -logfile pa_sim.log
```

### Mixed-Signal Simulation

```bash
#!/bin/bash
# ams_sim.sh

xrun -sv -ams -64bit \
    -timescale 1ns/1ps \
    -f digital.flist \
    -f analog.flist \
    -discipline logic \
    -amscml connect_lib.vams \
    -amsconnrules user_rules \
    -amscontrol ams_control.scs \
    -top tb_top \
    -access +rwc \
    -run -exit \
    -logfile ams_sim.log
```

### Quick Reference: Most Common Options

```bash
# Quick compile + simulate
xrun -sv -64bit -f all.flist -top tb_top -run -exit -logfile sim.log

# With UVM
xrun -sv -64bit -uvm -f all.flist +UVM_TESTNAME=test -run -exit

# With debug
xrun -sv -64bit -access +rwc -createdebugdb -f all.flist -gui -indago

# With coverage
xrun -sv -64bit -coverage all -covdut tb_top.dut -covtest test1 -f all.flist -run -exit

# With low-power
xrun -sv -64bit -upf design.upf -lps_1801 -f all.flist -run -exit
```

---

*Document Version: 2026.05 -- Comprehensive Xcelium command reference for simulation, debug, coverage, AMS, and low-power verification.*
