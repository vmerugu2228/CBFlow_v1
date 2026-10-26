# Synopsys VCS Simulator — Comprehensive Command Reference

## Table of Contents
1. [Overview](#overview)
2. [Compilation Commands](#compilation-commands)
3. [Simulation Execution](#simulation-execution)
4. [Debug Capabilities](#debug-capabilities)
5. [Coverage](#coverage)
6. [SystemVerilog Support](#systemverilog-support)
7. [UVM Support](#uvm-support)
8. [Performance Optimization](#performance-optimization)
9. [Waveform Dumping and Debug](#waveform-dumping-and-debug)
10. [Mixed-Signal Co-Simulation](#mixed-signal-co-simulation)
11. [Licensing and Environment](#licensing-and-environment)
12. [Common Flows and Recipes](#common-flows-and-recipes)

---

## Overview

Synopsys VCS (Verilog Compiler Simulator) is an industry-leading functional verification solution that supports Verilog, SystemVerilog, VHDL, SystemC, and mixed-language simulation. VCS uses a two-step compile-then-simulate flow that generates an optimized binary (simv) for fast simulation.

### Architecture

VCS operates in two phases:
1. **Analysis/Compilation** -- source files are parsed, elaborated, and compiled into a simulation binary (`simv`)
2. **Simulation** -- the compiled binary is executed to run the simulation

### Key Capabilities
- Native SystemVerilog and UVM support
- Partition compile for incremental compilation
- Multi-core simulation
- Integrated coverage (line, toggle, condition, FSM, branch, assertion)
- Unified debug with Verdi
- Mixed-signal co-simulation via VCS-AMS or CustomSim integration
- DPI (Direct Programming Interface) for C/C++/SystemC integration

---

## Compilation Commands

### vcs -- Primary Compilation Command

`vcs` is the main command that compiles Verilog/SystemVerilog source into the `simv` executable.

```
vcs [options] <source_files>
```

#### Source File Specification

| Option | Description |
|--------|-------------|
| `file.v` | Directly specify Verilog source files |
| `file.sv` | Directly specify SystemVerilog source files |
| `-f <filelist>` | Read source file names from a filelist |
| `-F <filelist>` | Read source file names from a filelist (relative paths resolved from filelist location) |
| `-v <library_file>` | Specify a Verilog library file (modules resolved on demand) |
| `-y <library_dir>` | Specify a library directory for module resolution |
| `+libext+<ext>` | Specify file extensions to search in library directories (e.g., `+libext+.v+.sv`) |
| `+incdir+<dir>` | Add directory to `include search path |
| `-top <module>` | Specify top-level module name |
| `+define+<macro>=<value>` | Define a preprocessor macro |
| `+define+<macro>` | Define a macro without value (equivalent to `define macro) |

#### Language Options

| Option | Description |
|--------|-------------|
| `-sverilog` | Enable SystemVerilog language features |
| `+sv` | Shorthand for `-sverilog` |
| `+v2k` | Enable Verilog-2001 features |
| `-vhdl` | Compile VHDL files (triggers VHDL compiler) |
| `+verilog2001ext+<ext>` | Treat files with extension as Verilog-2001 |
| `+systemverilogext+<ext>` | Treat files with extension as SystemVerilog |
| `-ams` | Enable AMS (Analog Mixed-Signal) extensions |
| `+acc+<level>` | Set accuracy/access level for PLI |
| `-lca` | Enable Limited Customer Availability features |

#### Compilation Control

| Option | Description |
|--------|-------------|
| `-o <name>` | Specify output binary name (default: `simv`) |
| `-Mdir=<dir>` | Specify intermediate directory (default: `csrc`) |
| `-full64` | Compile for 64-bit execution |
| `-kdb` | Generate KDB (Knowledge Database) for Verdi debug |
| `-j<N>` | Use N parallel compilation jobs |
| `-timescale=<ts>/<tp>` | Set default timescale (e.g., `-timescale=1ns/1ps`) |
| `-override_timescale=<ts>/<tp>` | Override all timescale directives |
| `-q` | Quiet mode (suppress banner/informational messages) |
| `-V` | Verbose mode |
| `-R` | Run simulation immediately after compilation |
| `-e <function>` | Specify alternate entry point function |
| `-l <logfile>` | Log compilation output to file |
| `-Marchive=<options>` | Archive csrc directory for distribution |

#### Optimization Options

| Option | Description |
|--------|-------------|
| `-O0` | No optimization (fastest compile, slowest simulation) |
| `-O1` | Basic optimization |
| `-O2` | Moderate optimization (default) |
| `-O3` | Maximum optimization (slowest compile, fastest simulation) |
| `-Onoopt+<module>` | Disable optimization for specific module |
| `-fastcomp` | Enable fast compilation mode |
| `-noIncrComp` | Disable incremental compilation |
| `+rad` | Enable Radiant technology for performance |
| `+optconfigfile+<file>` | Read optimization configuration from file |
| `-Xkeyopt=<option>` | Advanced optimization key options |

#### Warning/Error Control

| Option | Description |
|--------|-------------|
| `+warn=all` | Enable all warnings |
| `+warn=none` | Suppress all warnings |
| `+warn=noTFIPC` | Suppress specific warning category |
| `-error=<ID>` | Promote specific warning to error |
| `+lint=all` | Enable all lint checks |
| `+lint=PCWM` | Enable specific lint category |
| `-assert svaext` | Enable SVA extension assertions |
| `-notice` | Display notice-level messages |

#### Gate-Level Simulation Options

| Option | Description |
|--------|-------------|
| `+neg_tchk` | Enable negative timing check support |
| `+notimingcheck` | Disable all timing checks |
| `+nospecify` | Ignore specify blocks |
| `+delay_mode_zero` | Set all delays to zero |
| `+delay_mode_unit` | Set all delays to 1 time unit |
| `+delay_mode_path` | Use only path delays |
| `+delay_mode_distributed` | Use only distributed delays |
| `+transport_int_delays` | Use transport model for interconnect delays |
| `+transport_path_delays` | Use transport model for path delays |
| `+pulse_e/<percent>` | Pulse error limit |
| `+pulse_r/<percent>` | Pulse reject limit |
| `+sdfverbose` | Verbose SDF annotation messages |
| `-sdf <options>` | SDF annotation control |
| `+maxdelays` | Use max delays from SDF |
| `+mindelays` | Use min delays from SDF |
| `+typdelays` | Use typical delays from SDF |

#### SDF Annotation

```
-sdf min|typ|max:<instance>:<sdf_file>
```

Examples:
```bash
vcs -sdf max:top.u_cpu:cpu_max.sdf design.v
vcs -sdf typ::chip.sdf design.v  # annotate from root
```

### vlogan -- Verilog/SystemVerilog Analyzer

`vlogan` performs analysis (parsing) of Verilog and SystemVerilog files in multi-step compilation. It is used in the analyze-elaborate-simulate three-step flow.

```
vlogan [options] <source_files>
```

| Option | Description |
|--------|-------------|
| `-sverilog` | Analyze as SystemVerilog |
| `-full64` | 64-bit mode |
| `-work <library>` | Specify work library name |
| `-f <filelist>` | Read filelist |
| `-F <filelist>` | Read filelist (relative path resolution) |
| `+define+<macro>=<value>` | Define preprocessor macro |
| `+incdir+<dir>` | Add include directory |
| `-timescale=<ts>/<tp>` | Set default timescale |
| `-kdb` | Generate KDB for Verdi |
| `-ntb_opts uvm` | Analyze with UVM library |
| `-assert svaext` | Enable SVA extensions |
| `-v <file>` | Specify library file |
| `-y <dir>` | Specify library directory |
| `+libext+<ext>` | Library file extensions |
| `-q` | Quiet mode |
| `-l <logfile>` | Log to file |
| `+v2k` | Enable Verilog-2001 |

#### Three-Step Flow Example

```bash
# Step 1: Analyze Verilog/SV sources
vlogan -sverilog -full64 -f rtl.flist
vlogan -sverilog -full64 -f tb.flist -ntb_opts uvm

# Step 2: Elaborate
vcs -full64 -top tb_top -debug_pp -kdb

# Step 3: Simulate
./simv +UVM_TESTNAME=my_test
```

### vhdlan -- VHDL Analyzer

`vhdlan` performs analysis of VHDL source files.

```
vhdlan [options] <source_files>
```

| Option | Description |
|--------|-------------|
| `-full64` | 64-bit mode |
| `-work <library>` | Specify work library name |
| `-f <filelist>` | Read filelist |
| `-vhdl87` | Analyze as VHDL-87 |
| `-vhdl93` | Analyze as VHDL-93 |
| `-vhdl08` | Analyze as VHDL-2008 |
| `-q` | Quiet mode |
| `-l <logfile>` | Log to file |
| `-kdb` | Generate KDB for Verdi |
| `-xlrm` | Enable relaxed VHDL rules |

#### Mixed-Language Example

```bash
# Analyze VHDL sources
vhdlan -full64 -work my_lib ip_block.vhd

# Analyze Verilog/SV sources
vlogan -sverilog -full64 top.sv

# Elaborate (mixed-language)
vcs -full64 -top tb_top -debug_pp
```

### syscan -- SystemC Compiler

`syscan` compiles SystemC source files for co-simulation with VCS.

```
syscan [options] <source_files>
```

| Option | Description |
|--------|-------------|
| `-full64` | 64-bit mode |
| `-cflags "<flags>"` | Pass flags to C++ compiler |
| `-sysc=<version>` | Specify SystemC version (e.g., `-sysc=2.3.1`) |
| `-tlm2` | Enable TLM-2.0 support |
| `-cpp <compiler>` | Specify C++ compiler path |
| `-f <filelist>` | Read filelist |
| `-q` | Quiet mode |

#### SystemC Co-Simulation Example

```bash
# Compile SystemC model
syscan -full64 -sysc=2.3.1 -tlm2 sc_model.cpp

# Analyze SV wrapper
vlogan -sverilog -full64 sc_wrapper.sv

# Elaborate and link
vcs -full64 -top tb_top -sysc sc_main -debug_pp
```

---

## Simulation Execution

### simv -- Simulation Binary

After compilation, VCS produces the `simv` binary (or custom-named via `-o`). This binary is run to execute the simulation.

```
./simv [runtime_options]
```

#### Basic Runtime Options

| Option | Description |
|--------|-------------|
| `-l <logfile>` | Log simulation output to file |
| `+vcs+finish+<time>` | Terminate simulation at specified time |
| `+vcs+stop+<time>` | Stop simulation (enter interactive) at specified time |
| `+vcs+flush+all` | Flush all output buffers on `$finish` |
| `+vcs+flush+log` | Flush log file buffer on `$finish` |
| `+vcs+flush+dump` | Flush waveform dump buffer on `$finish` |
| `+vcs+lic+wait` | Wait for license if unavailable |
| `+vcs+nostdout` | Suppress stdout output |
| `+vcs+initreg+0` | Initialize all registers to 0 |
| `+vcs+initreg+1` | Initialize all registers to 1 |
| `+vcs+initreg+random` | Initialize all registers to random values |
| `+vcs+initreg+x` | Initialize all registers to X (default) |
| `-q` | Quiet mode |
| `-V` | Verbose mode |

#### Randomization and Seed Control

| Option | Description |
|--------|-------------|
| `+ntb_random_seed=<value>` | Set random seed for constrained random |
| `+ntb_random_seed_automatic` | Use automatic (time-based) random seed |
| `+vcs+random+seed=<value>` | Set seed for $random |
| `+ntb_solver_mode=<mode>` | Set constraint solver mode (1=default, 2=alternative) |
| `+ntb_random_seed_delta=<value>` | Set seed delta between threads |
| `+ntb_solver_array_size_warn=<N>` | Warn if randomized array exceeds size N |

#### Plusargs (User-Defined Runtime Arguments)

VCS supports `$value$plusargs` and `$test$plusargs` for passing runtime arguments:

```bash
./simv +MY_PLUSARG +MY_VALUE=42 +TESTNAME=basic_test
```

In SystemVerilog:
```systemverilog
string test_name;
int my_value;
if ($value$plusargs("TESTNAME=%s", test_name))
  $display("Running test: %s", test_name);
if ($value$plusargs("MY_VALUE=%d", my_value))
  $display("Value: %d", my_value);
if ($test$plusargs("MY_PLUSARG"))
  $display("MY_PLUSARG is set");
```

#### Runtime Control Options

| Option | Description |
|--------|-------------|
| `+vcs+learn+pli` | Learn PLI usage for optimization |
| `+vcs+dumpoff` | Disable VPD dumping at start |
| `+vcs+dumpon` | Enable VPD dumping at start |
| `+memcbk` | Enable memory callback for debug |
| `+vcs+dumpvars+<filename>` | Dump variables to file |
| `+vcs+dumpfile+<filename>` | Specify dump file name |
| `-ucli` | Launch UCLI interactive debug |
| `-gui` | Launch Verdi GUI |
| `-i <ucli_script>` | Source UCLI script at startup |
| `+vcs+TIMEOUT=<N>` | Set simulation timeout in seconds |
| `+vcs+loopreport` | Report zero-delay loop detection |

#### Memory and Performance Runtime Options

| Option | Description |
|--------|-------------|
| `+vcs+mda_enable` | Enable multi-dimensional array access |
| `+vcs+vcdpluson` | Enable VCD+ (VPD) dumping |
| `+vcs+vcdplusmemon` | Enable memory dumping in VPD |
| `+vcs+vcdplusglitchon` | Enable glitch dumping in VPD |
| `+vcs+vcdplusautoflushon` | Enable auto-flush for VPD |
| `+vcs+dumparrays` | Dump arrays to waveform |
| `+vcs+parallel+threads=<N>` | Use N threads for simulation |

---

## Debug Capabilities

### Compile-Time Debug Options

| Option | Description |
|--------|-------------|
| `-debug_all` | Full debug access: line stepping, breakpoints, force, waveform, assertions (slowest) |
| `-debug_access` | Equivalent to `-debug_all` |
| `-debug_pp` | Post-process debug: waveform viewing, no interactive debug (faster) |
| `-debug_access+all` | Fine-grained: enable all debug access |
| `-debug_access+r` | Read access to all signals |
| `-debug_access+w` | Write/force access to all signals |
| `-debug_access+f` | Force access |
| `-debug_access+r+w` | Read and write access |
| `-debug_access+cbk` | Callback (breakpoint) access |
| `-debug_access+pp` | Post-process access |
| `-debug_access+line` | Line-stepping access |
| `-debug_access+class` | Class debug access |
| `-debug_region=<instance>` | Limit debug to specific instance |
| `-kdb` | Generate knowledge database for Verdi |
| `-kdb=+all` | Generate comprehensive KDB |

#### Recommended Debug Levels

```bash
# Development/debug builds -- full interactivity
vcs -sverilog -debug_all -kdb design.sv tb.sv

# Regression builds -- post-process debug only (faster)
vcs -sverilog -debug_pp -kdb design.sv tb.sv

# Performance builds -- no debug overhead
vcs -sverilog design.sv tb.sv
```

### UCLI (Unified Command-Line Interface)

UCLI provides interactive debug during simulation. Enter UCLI by compiling with `-debug_all` and running with `-ucli` or by hitting Ctrl-C during simulation.

#### Starting UCLI

```bash
# Method 1: Launch with UCLI
./simv -ucli

# Method 2: Launch with UCLI script
./simv -ucli -i debug.tcl

# Method 3: Launch Verdi GUI (UCLI embedded)
./simv -gui
```

#### UCLI Navigation Commands

| Command | Description |
|---------|-------------|
| `run` | Run simulation to completion |
| `run <time>` | Run for specified time (e.g., `run 100ns`) |
| `run -next` | Run to next event |
| `step` | Step one statement |
| `step <N>` | Step N statements |
| `next` | Step over (skip function/task calls) |
| `finish` | Run to end of current scope |
| `stop` | Stop simulation |
| `cont` | Continue after stop |
| `quit` | Quit simulation |

#### UCLI Breakpoint Commands

| Command | Description |
|---------|-------------|
| `stop -posedge <signal>` | Break on positive edge |
| `stop -negedge <signal>` | Break on negative edge |
| `stop -change <signal>` | Break on any value change |
| `stop -condition {<expr>}` | Break on condition |
| `stop -line <file> <line>` | Break at source line |
| `stop -time <time>` | Break at simulation time |
| `stop -object <signal> -value <val>` | Break when signal reaches value |
| `stop -delete <id>` | Delete breakpoint |
| `stop -disable <id>` | Disable breakpoint |
| `stop -enable <id>` | Enable breakpoint |
| `stop -show` | Show all breakpoints |

#### UCLI Signal Access Commands

| Command | Description |
|---------|-------------|
| `get <signal>` | Get current value of signal |
| `show <signal>` | Show signal info (type, width, value) |
| `force <signal> <value>` | Force signal to value |
| `force <signal> <value> -after <time>` | Force after delay |
| `force -deposit <signal> <value>` | Deposit value (no hold) |
| `force -drive <signal> <value>` | Drive value (held until released) |
| `release <signal>` | Release forced signal |
| `drivers <signal>` | Show signal drivers |
| `loads <signal>` | Show signal loads |
| `scope` | Show current scope |
| `scope <path>` | Change to scope |
| `scope -up` | Move up one level |
| `scope -list` | List sub-scopes |
| `describe <signal>` | Detailed signal description |

#### UCLI Waveform Commands

| Command | Description |
|---------|-------------|
| `dump -add <signal>` | Add signal to waveform dump |
| `dump -add <scope> -depth <N>` | Add scope signals to depth N |
| `dump -add * -depth 0` | Dump all signals in all scopes |
| `dump -file <filename>` | Specify dump filename |
| `dump -type VPD` | Set dump format to VPD |
| `dump -type FSDB` | Set dump format to FSDB |
| `dump -type VCD` | Set dump format to VCD |
| `dump -enable` | Enable dumping |
| `dump -disable` | Disable dumping |
| `dump -flush` | Flush dump buffer |
| `dump -close` | Close dump file |
| `dump -status` | Show dump status |

#### UCLI Memory Commands

| Command | Description |
|---------|-------------|
| `memory read <addr> <mem_name>` | Read memory at address |
| `memory write <addr> <value> <mem_name>` | Write memory at address |
| `memory display <mem_name>` | Display memory contents |
| `memory dump -file <file> <mem_name>` | Dump memory to file |
| `memory load -file <file> <mem_name>` | Load memory from file |

#### UCLI Assertion Commands

| Command | Description |
|---------|-------------|
| `assertion -summary` | Show assertion summary |
| `assertion -list` | List all assertions |
| `assertion -enable <name>` | Enable assertion |
| `assertion -disable <name>` | Disable assertion |
| `assertion -details <name>` | Show assertion details |
| `assertion -breakOnFail` | Break on assertion failure |
| `assertion -clear` | Clear assertion status |

#### UCLI TCL Scripting

UCLI supports full TCL scripting:

```tcl
# debug.tcl -- example UCLI script
# Set up waveform dumping
dump -file waves.fsdb -type FSDB
dump -add tb_top -depth 0

# Add breakpoint
stop -time 1000ns

# Run to breakpoint
run

# Print register values
set regs [list pc sp ra]
foreach r $regs {
    puts "$r = [get tb_top.u_cpu.$r]"
}

# Continue to finish
run
```

### Save/Restore

VCS supports save/restore to checkpoint simulation state:

```bash
# Save checkpoint
./simv +vcs+save+checkpoint1.save

# Restore and continue
./simv +vcs+restore+checkpoint1.save
```

UCLI save/restore:
```
save checkpoint1.save
restore checkpoint1.save
```

---

## Coverage

### Compile-Time Coverage Options

| Option | Description |
|--------|-------------|
| `-cm line` | Enable line coverage |
| `-cm cond` | Enable condition coverage |
| `-cm fsm` | Enable FSM coverage |
| `-cm tgl` | Enable toggle coverage |
| `-cm branch` | Enable branch coverage |
| `-cm assert` | Enable assertion coverage |
| `-cm line+cond+fsm+tgl+branch` | Enable multiple coverage types |
| `-cm_hier <file>` | Specify coverage hierarchy file |
| `-cm_name <name>` | Name for this coverage database |
| `-cm_dir <dir>` | Directory for coverage database |
| `-cm_log <file>` | Log coverage messages to file |
| `-cm_noconst` | Exclude constant signals from toggle |
| `-cm_seqnoconst` | Exclude sequential constants from toggle |
| `-cm_constfile <file>` | File listing constant signals to exclude |
| `-cm_count` | Count coverage hits (not just hit/miss) |
| `-cm_glitch` | Enable glitch detection for toggle |
| `-cm_autocond` | Auto-generate condition expressions |
| `-cm_fsmcfg <file>` | FSM configuration file |
| `-cm_fsmresetfilter` | Filter FSM transitions during reset |
| `-cm_assert_hier <file>` | Assertion coverage hierarchy |
| `-cm_libs <cells>` | Include library cells in coverage |

#### Coverage Hierarchy File Format

```
# cm_hier.cfg
# Tree-based inclusion/exclusion
+tree tb_top.dut                  # Include DUT tree
-tree tb_top.dut.u_mem_model      # Exclude memory model
+module cpu_core                   # Include module
-module clock_gen                  # Exclude module
+moduletree soc_top               # Include module tree
-instance tb_top.u_tb              # Exclude testbench instance

# Toggle-specific controls
begin tgl
  -tree tb_top.dut.u_clk_gen
  +node tb_top.dut.data_bus[31:0]
end
```

### Runtime Coverage Options

| Option | Description |
|--------|-------------|
| `-cm_test <name>` | Name for this test's coverage |
| `-cm_dir <dir>` | Runtime coverage directory |
| `+vcs+cm+off` | Disable coverage collection at runtime |
| `+vcs+cm+on` | Enable coverage collection at runtime |
| `-cm_from <time>` | Start coverage collection at time |
| `-cm_to <time>` | Stop coverage collection at time |
| `+fsdb+force` | Force FSDB generation with coverage |

### URG (Unified Report Generator)

URG merges and reports coverage data.

```
urg [options]
```

| Option | Description |
|--------|-------------|
| `-dir <simv.vdb>` | Specify coverage database directory |
| `-dir <db1> -dir <db2>` | Merge multiple databases |
| `-dbname <name>` | Name for merged database |
| `-report <dir>` | Output report directory |
| `-format <fmt>` | Report format: text, html, both |
| `-metric <metrics>` | Report specific metrics (line, cond, fsm, tgl, branch, assert) |
| `-group <file>` | Group configuration file |
| `-elfile <file>` | Exclusion file |
| `-show ratios` | Show coverage ratios |
| `-show tests` | Show contributing tests |
| `-hier <file>` | Hierarchy filter for reporting |
| `-map <module>` | Map modules for merged reporting |
| `-parallel` | Use parallel processing for merge |
| `-lca` | Enable LCA features |

#### URG Usage Examples

```bash
# Merge all tests and generate HTML report
urg -dir test1/simv.vdb -dir test2/simv.vdb -dir test3/simv.vdb \
    -dbname merged -report urgReport -format both

# Merge using wildcard
urg -dir "*/simv.vdb" -dbname merged -report urgReport

# Report specific metrics
urg -dir merged.vdb -metric line+cond+tgl -report urgReport -format html

# Apply exclusion file
urg -dir merged.vdb -elfile coverage.el -report urgReport
```

#### Exclusion File Format

```
# coverage.el
MODULE: clock_divider
  LINE: 42  // unreachable by design
  COND: 55  // tied-off input
  TOGGLE: reset_n  // async reset, not toggled in test

INSTANCE: tb_top.dut.u_pll
  ANNOTATION: "PLL model, not real RTL"
  ALL:
```

### Coverage System Tasks

In SystemVerilog, you can control coverage from within the testbench:

```systemverilog
// Start/stop coverage
$coverage_control(1, "line", "tb_top.dut");  // start
$coverage_control(0, "line", "tb_top.dut");  // stop

// Save coverage to database
$coverage_save("test1.vdb", "test1");

// Merge coverage
$coverage_merge("merged.vdb", "test1.vdb", "test2.vdb");

// Get coverage value
real cov;
cov = $coverage_get("line", "tb_top.dut");
$display("Line coverage: %0.2f%%", cov);
```

### Functional Coverage

VCS natively supports SystemVerilog functional coverage:

```systemverilog
covergroup cg_opcode @(posedge clk);
    cp_opcode: coverpoint opcode {
        bins add = {4'h0};
        bins sub = {4'h1};
        bins load = {4'h2};
        bins store = {4'h3};
        bins alu_ops = {[4'h4:4'hA]};
        illegal_bins reserved = {[4'hB:4'hF]};
    }
    cp_mode: coverpoint mode {
        bins user = {2'b00};
        bins supervisor = {2'b01};
        bins kernel = {2'b11};
    }
    cross_op_mode: cross cp_opcode, cp_mode;
endgroup
```

---

## SystemVerilog Support

### Enabling SystemVerilog

| Option | Description |
|--------|-------------|
| `-sverilog` | Enable full SystemVerilog support |
| `+sv` | Shorthand for `-sverilog` |
| `+systemverilogext+<ext>` | Treat files with extension as SystemVerilog |
| `-assert svaext` | Enable SVA extensions |
| `-assert enable_diag` | Enable assertion diagnostics |
| `-assert disable_cover` | Disable cover directives |
| `-assert filter` | Filter trivially passing assertions |

### DPI (Direct Programming Interface)

DPI allows calling C/C++ functions from SystemVerilog and vice versa.

#### SystemVerilog Side

```systemverilog
// Import C function into SV
import "DPI-C" function int c_compute(input int a, input int b);
import "DPI-C" context function void c_callback();
import "DPI-C" pure function real c_sqrt(input real x);

// Export SV function to C
export "DPI-C" function sv_get_data;

function int sv_get_data(input int addr);
    return memory[addr];
endfunction
```

#### C Side

```c
// dpi_functions.c
#include "svdpi.h"

int c_compute(int a, int b) {
    return a * a + b * b;
}

void c_callback() {
    svScope scope = svGetScope();
    // Call back into SV
    int data;
    sv_get_data(0x100, &data);
}

double c_sqrt(double x) {
    return sqrt(x);
}
```

#### Compilation with DPI

```bash
# Compile DPI C files with VCS
vcs -sverilog -full64 design.sv tb.sv dpi_functions.c \
    -CFLAGS "-I/path/to/includes" \
    -LDFLAGS "-L/path/to/libs -lm"

# Or use separate compilation
gcc -c -fPIC -I${VCS_HOME}/include dpi_functions.c -o dpi_functions.o
vcs -sverilog -full64 design.sv tb.sv dpi_functions.o
```

#### DPI Compilation Options

| Option | Description |
|--------|-------------|
| `-CFLAGS "<flags>"` | Pass flags to C compiler |
| `-LDFLAGS "<flags>"` | Pass flags to linker |
| `-cc <compiler>` | Specify C compiler |
| `-cpp <compiler>` | Specify C++ compiler |
| `-ld <linker>` | Specify linker |
| `+vpi` | Enable VPI in addition to DPI |
| `-P <tab_file>` | PLI table file |

### Constrained Random Verification

VCS supports full SystemVerilog constrained random:

```bash
# Set random seed
./simv +ntb_random_seed=12345

# Use automatic seed
./simv +ntb_random_seed_automatic

# Solver options
./simv +ntb_solver_mode=2  # alternative solver
./simv +ntb_random_constraint_solver_verbose  # solver debug
```

#### Solver Debug Options

| Option | Description |
|--------|-------------|
| `+ntb_random_constraint_solver_verbose` | Print solver statistics |
| `+ntb_solver_array_size_warn=<N>` | Warn if array size exceeds N |
| `+ntb_solver_mode=1` | Default solver mode |
| `+ntb_solver_mode=2` | Alternative solver mode |
| `+ntb_enable_solver_trace` | Enable solver trace for debug |
| `+ntb_solver_timeout=<N>` | Set solver timeout in seconds |

### Assertion Control

| Option | Description |
|--------|-------------|
| `-assert svaext` | Enable SVA extensions |
| `-assert enable_diag` | Enable assertion diagnostics |
| `-assert disable_cover` | Disable cover directives |
| `-assert filter` | Filter trivially passing assertions |
| `+assert_count_traces` | Count assertion trace depth |
| `+assert_report_incompletes` | Report incomplete assertions |
| `-assert_hier <file>` | Assertion hierarchy file |
| `+assert_off` | Disable all assertions at runtime |
| `+assert_off+<path>` | Disable assertions at specific path |
| `+assert_on+<path>` | Enable assertions at specific path |
| `-assert maxfail=<N>` | Fail after N assertion failures |

---

## UVM Support

### Compile-Time UVM Options

| Option | Description |
|--------|-------------|
| `-ntb_opts uvm` | Include UVM library (compile with vlogan) |
| `-ntb_opts uvm-1.1` | Use UVM 1.1 |
| `-ntb_opts uvm-1.2` | Use UVM 1.2 |
| `+incdir+${UVM_HOME}/src` | Add UVM include path (manual method) |
| `${UVM_HOME}/src/uvm_pkg.sv` | Include UVM package file (manual method) |
| `-timescale=1ns/1ps` | Required timescale for UVM |

### Runtime UVM Options

| Option | Description |
|--------|-------------|
| `+UVM_TESTNAME=<test>` | Specify UVM test class name |
| `+UVM_VERBOSITY=<level>` | Set UVM verbosity: UVM_NONE, UVM_LOW, UVM_MEDIUM, UVM_HIGH, UVM_FULL, UVM_DEBUG |
| `+UVM_TIMEOUT=<time>,<overridable>` | Set UVM timeout (e.g., `+UVM_TIMEOUT=1000000,YES`) |
| `+UVM_MAX_QUIT_COUNT=<count>` | Maximum errors before quit |
| `+UVM_PHASE_TRACE` | Trace phase execution |
| `+UVM_OBJECTION_TRACE` | Trace objection raise/drop |
| `+UVM_CONFIG_DB_TRACE` | Trace config_db set/get |
| `+UVM_RESOURCE_DB_TRACE` | Trace resource_db operations |
| `+UVM_DUMP_CMDLINE_ARGS` | Dump command-line arguments |
| `+uvm_set_verbosity=<comp>,<id>,<verb>,<phase>` | Set verbosity per component |
| `+uvm_set_config_int=<inst>,<field>,<value>` | Set config_db int |
| `+uvm_set_config_string=<inst>,<field>,<value>` | Set config_db string |
| `+uvm_set_type_override=<orig>,<override>` | Override component/object type |
| `+uvm_set_inst_override=<orig>,<override>,<inst>` | Override type at specific instance |
| `+uvm_set_action=<comp>,<id>,<severity>,<action>` | Set message action |
| `+uvm_set_severity=<comp>,<id>,<cur_sev>,<new_sev>` | Remap severity |
| `+UVM_NO_RELNOTES` | Suppress UVM release notes |
| `+UVM_TR_RECORD` | Enable transaction recording |
| `+UVM_LOG_RECORD` | Enable log recording |

#### UVM Compilation Flow

```bash
# Analyze UVM package and testbench
vlogan -sverilog -full64 -ntb_opts uvm -timescale=1ns/1ps
vlogan -sverilog -full64 -ntb_opts uvm \
    +incdir+./tb \
    -f tb.flist

# Analyze RTL
vlogan -sverilog -full64 -f rtl.flist

# Elaborate
vcs -full64 -top tb_top -debug_pp -kdb -cm line+cond+fsm+tgl+branch+assert \
    -timescale=1ns/1ps -ntb_opts uvm

# Simulate
./simv +UVM_TESTNAME=smoke_test \
       +UVM_VERBOSITY=UVM_MEDIUM \
       +UVM_TIMEOUT=10000000,YES \
       +ntb_random_seed=42 \
       -l sim.log \
       -cm_name smoke_test \
       -cm_dir coverage/simv.vdb
```

#### UVM Debug with VCS

```bash
# Enable UVM tracing for debug
./simv +UVM_TESTNAME=my_test \
       +UVM_VERBOSITY=UVM_DEBUG \
       +UVM_PHASE_TRACE \
       +UVM_OBJECTION_TRACE \
       +UVM_CONFIG_DB_TRACE \
       -ucli -i uvm_debug.tcl

# uvm_debug.tcl
# Break on specific UVM phase
stop -condition {uvm_test_top.m_current_phase.get_name() == "main"}
run
# Print UVM topology
call uvm_top.print_topology()
```

#### UVM Config from Command Line

```bash
# Set integer config
./simv +uvm_set_config_int=*,num_transactions,1000

# Set string config
./simv +uvm_set_config_string=*env*,test_mode,directed

# Override factory type
./simv +uvm_set_type_override=base_driver,enhanced_driver

# Instance override
./simv +uvm_set_inst_override=base_seq,special_seq,uvm_test_top.env.agent.sequencer.*
```

---

## Performance Optimization

### Fast Compilation

| Option | Description |
|--------|-------------|
| `-fastcomp` | Enable fast compilation mode |
| `-j<N>` | Use N parallel compilation jobs |
| `-Mupdate` | Incremental compilation (recompile only changed files) |
| `-noIncrComp` | Disable incremental compilation |
| `-partcomp` | Enable partition compile |
| `-partcomp=autopart` | Automatic partitioning |
| `-pcmakeprof` | Profile partition compile |

### Partition Compile

Partition compile divides the design into independent partitions that can be compiled and re-compiled independently.

```bash
# Automatic partition compile
vcs -sverilog -full64 -partcomp=autopart -f rtl.flist -f tb.flist

# Manual partition configuration
vcs -sverilog -full64 -partcomp -pcconfig partition.cfg -f rtl.flist
```

#### Partition Configuration File

```
# partition.cfg
partition -name cpu_part {
    +instance tb_top.dut.u_cpu
}
partition -name mem_part {
    +instance tb_top.dut.u_mem_ctrl
}
partition -name io_part {
    +instance tb_top.dut.u_io_subsys
}
```

### Parallel Simulation

| Option | Description |
|--------|-------------|
| `+vcs+parallel+threads=<N>` | Use N threads for simulation |
| `+vcs+parallel+mode=<mode>` | Parallel mode: default, event, clock |
| `-partcomp` | Partition compile (prerequisites) |

```bash
# Compile with partition compile
vcs -sverilog -full64 -partcomp=autopart -f all.flist

# Run with parallel threads
./simv +vcs+parallel+threads=4
```

### Native Low-Power Simulation

```bash
# Compile with UPF support
vcs -sverilog -full64 -upf power_intent.upf design.sv tb.sv

# Runtime power-aware options
./simv +vcs+power+supply_on +vcs+power+iso_on
```

### Performance Analysis

```bash
# Profile simulation
vcs -sverilog -full64 -simprofile design.sv tb.sv
./simv -simprofile time
./simv -simprofile mem

# Generate profiling report
simprofile_report -dir simprofile.dir -report profile_report

# Performance statistics
./simv +vcs+perf+stats
```

### Optimization Configuration File

```
# opt_config.cfg
# Optimize specific modules
+optmod cpu_core
+optmod alu_unit

# Skip optimization for debug modules
-optmod tb_scoreboard
-optmod tb_monitor

# Radiant technology
+radmod cpu_core
```

```bash
vcs -sverilog +optconfigfile+opt_config.cfg -f all.flist
```

---

## Waveform Dumping and Debug

### VPD (VCD+) Dumping

VPD is VCS's proprietary waveform format, optimized for large designs.

#### System Tasks in Testbench

```systemverilog
initial begin
    // Start VPD dump
    $vcdpluson;           // Dump all signals
    $vcdpluson(1, top);   // Dump top and 1 level below
    $vcdpluson(0, top);   // Dump top and all levels below

    // Stop/restart dumping
    $vcdplusoff;          // Stop dumping
    $vcdpluson;           // Restart dumping

    // Memory dumping
    $vcdplusmemon;        // Enable memory dumping
    $vcdplusmemoff;       // Disable memory dumping

    // Glitch detection
    $vcdplusglitchon;     // Enable glitch dumping
    $vcdplusglitchoff;    // Disable glitch dumping

    // File control
    $vcdplusfile("waves.vpd");  // Set filename
    $vcdplusflush;              // Flush buffer
    $vcdplusclose;              // Close file
end
```

#### Runtime VPD Options

```bash
./simv +vcs+vcdpluson           # Enable VPD from command line
./simv +vcs+vcdplusmemon        # Include memories
./simv +vcs+vcdplusglitchon     # Include glitches
./simv +vcs+vcdplusautoflushon  # Auto-flush buffer
```

### FSDB Dumping (for Verdi)

FSDB (Fast Signal Database) is the preferred format for Verdi debug.

#### Compilation for FSDB

```bash
# Ensure VERDI_HOME is set
export VERDI_HOME=/path/to/verdi

# Compile with FSDB support
vcs -sverilog -full64 -kdb \
    -P ${VERDI_HOME}/share/PLI/VCS/LINUX64/novas.tab \
       ${VERDI_HOME}/share/PLI/VCS/LINUX64/pli.a \
    design.sv tb.sv
```

#### FSDB System Tasks

```systemverilog
initial begin
    // Basic FSDB dumping
    $fsdbDumpfile("waves.fsdb");
    $fsdbDumpvars(0, tb_top);          // Dump all hierarchy
    $fsdbDumpvars(1, tb_top.dut);      // Dump 1 level
    $fsdbDumpvars("+all");             // Dump all including memories, MDA

    // Selective dumping
    $fsdbDumpvars(0, tb_top.dut, "+mda");     // Include multi-dimensional arrays
    $fsdbDumpvars(0, tb_top.dut, "+struct");  // Include structs
    $fsdbDumpvars(0, tb_top.dut, "+packedmda"); // Packed MDA

    // Control dumping window
    $fsdbDumpon;              // Start dumping
    $fsdbDumpoff;             // Stop dumping
    $fsdbDumpon(0, tb_top);   // Start dumping specific scope

    // Memory dumping
    $fsdbDumpMem(mem_inst, "mem.fsdb");  // Dump specific memory
    $fsdbDumpvars(0, "+Memories");       // Dump all memories

    // SVA (assertion) dumping
    $fsdbDumpSVA;                    // Dump all SVA
    $fsdbDumpSVA(0, tb_top.dut);     // Dump SVA in scope

    // Flush and close
    $fsdbDumpFlush;           // Flush buffer
    $fsdbDumpFinish;          // Close file
end
```

#### FSDB Runtime Options

```bash
./simv +fsdbfile+waves.fsdb       # Set FSDB filename
./simv +fsdb+delta                # Dump delta cycles
./simv +fsdb+glitch              # Dump glitches
./simv +fsdb+force               # Dump forced signals
./simv +fsdb+struct              # Dump struct signals
./simv +fsdb+mda                 # Dump multi-dimensional arrays
./simv +fsdb+autoflush           # Auto-flush
./simv +fsdb+sva                 # Dump SVA
./simv +fsdb+all                 # All FSDB options
./simv +fsdb+parallel=on         # Parallel FSDB dumping
```

### VCD Dumping (IEEE Standard)

```systemverilog
initial begin
    $dumpfile("waves.vcd");
    $dumpvars(0, tb_top);    // Dump all levels
    $dumpon;                   // Enable dumping
    $dumpoff;                  // Disable dumping
    $dumpflush;                // Flush
    $dumpall;                  // Dump all variables
    $dumplimit(1000000000);    // Limit file size (bytes)
end
```

### Verdi Integration

```bash
# Launch Verdi with VCS-generated databases
verdi -sv -f rtl.flist -ssf waves.fsdb -dbdir simv.daidir

# Launch Verdi from simulation
./simv -gui=verdi

# Launch with KDB
verdi -sv -f rtl.flist -ssf waves.fsdb -dbdir simv.daidir -kdb simv.daidir/kdb.elab++
```

### Transaction-Level Waveform

```systemverilog
// Enable transaction recording for UVM
initial begin
    $fsdbDumpvars(0, tb_top, "+Struct", "+Transaction");
    // Or with VPD:
    $vcdpluson;
    void'(uvm_config_db#(int)::set(null, "*", "recording_detail", UVM_FULL));
end
```

---

## Mixed-Signal Co-Simulation

### VCS-AMS Overview

VCS-AMS enables mixed-signal simulation by combining VCS (digital) with CustomSim or HSPICE (analog).

#### Compilation

```bash
# Compile mixed-signal design
vcs -sverilog -full64 -ams \
    -ad analog_config.scs \
    design.sv analog_block.scs \
    -amscml connect_lib.vams
```

#### Analog Configuration

```
// analog_config.scs
simulator lang=spectre
ahdl_include "analog_block.scs"
```

#### Connect Modules

Connect modules bridge digital and analog domains:

```verilog
// connect_module_d2a.vams
connectmodule d2a (input wire d, output electrical a);
    parameter real vh = 1.8;
    parameter real vl = 0.0;
    parameter real tr = 100p;
    parameter real tf = 100p;
    analog begin
        V(a) <+ transition(d ? vh : vl, 0, tr, tf);
    end
endmodule

// connect_module_a2d.vams
connectmodule a2d (input electrical a, output wire d);
    parameter real vth = 0.9;
    real vval;
    analog begin
        @(cross(V(a) - vth, 0)) ;
        vval = V(a);
    end
    assign d = (vval > vth) ? 1'b1 : 1'b0;
endmodule
```

#### AMS Runtime Options

```bash
./simv -ams \
    +ams+analogcontrol+analog.scs \
    +ams+abstol=1e-12 \
    +ams+reltol=1e-3 \
    +ams+vntol=1e-6 \
    +ams+iabstol=1e-12
```

### Real Number Modeling (RNM)

For faster mixed-signal simulation using real-valued signals:

```systemverilog
// real_model.sv -- real-number model of ADC
module adc_rnm #(
    parameter int BITS = 12,
    parameter real VREF = 1.8
) (
    input  real    vin,
    input  logic   clk,
    output logic [BITS-1:0] dout
);
    always @(posedge clk) begin
        dout <= int'((vin / VREF) * (2**BITS - 1));
    end
endmodule
```

```bash
# Compile with wreal support
vcs -sverilog -full64 +vcs+rnm design.sv tb.sv
```

---

## Licensing and Environment

### Environment Variables

| Variable | Description |
|----------|-------------|
| `VCS_HOME` | VCS installation directory |
| `VERDI_HOME` | Verdi installation directory |
| `VCS_LIC_EXPIRE_WARNING` | Days before license expiry warning |
| `SNPSLMD_LICENSE_FILE` | License file/server |
| `VCS_ARCH_OVERRIDE` | Override architecture detection |
| `SYNOPSYS_SIM_SETUP` | Path to synopsys_sim.setup file |
| `VCS_CC` | Default C compiler |
| `VCS_CXX` | Default C++ compiler |
| `VCS_LIC_WAIT` | Wait for license (0 or 1) |

### synopsys_sim.setup

```
-- synopsys_sim.setup
WORK > DEFAULT
DEFAULT : ./work

-- Library mappings
my_lib : ./my_lib
ieee : $VCS_HOME/lib/ieee
std : $VCS_HOME/lib/std

-- UVM library
uvm : $VCS_HOME/etc/uvm-1.2
```

### License Usage

```bash
# Check license usage
vcs -ID              # Show VCS version and license info
lmstat -a -c $SNPSLMD_LICENSE_FILE  # Show all license usage

# Queue for license
./simv +vcs+lic+wait  # Wait for license at runtime
```

---

## Common Flows and Recipes

### Basic RTL Simulation Flow

```bash
#!/bin/bash
# basic_sim.sh -- Basic VCS simulation flow

# Setup
export VCS_HOME=/tools/synopsys/vcs/T-2022.06-SP2
export PATH=$VCS_HOME/bin:$PATH

# Compile
vcs -sverilog -full64 \
    -timescale=1ns/1ps \
    -debug_pp -kdb \
    +define+SIMULATION \
    +incdir+./rtl +incdir+./tb \
    -f rtl.flist \
    -f tb.flist \
    -o simv \
    -l compile.log

# Check compilation
if [ $? -ne 0 ]; then
    echo "ERROR: Compilation failed"
    exit 1
fi

# Simulate
./simv \
    +ntb_random_seed=42 \
    +vcs+flush+all \
    -l sim.log

echo "Simulation complete: $?"
```

### UVM Regression Flow

```bash
#!/bin/bash
# uvm_regression.sh -- UVM regression with coverage

TESTS=(
    "smoke_test"
    "directed_read_test"
    "directed_write_test"
    "random_traffic_test"
    "error_injection_test"
    "stress_test"
)

SEEDS=(42 123 456 789 1024 2048)

# Compile once
vlogan -sverilog -full64 -ntb_opts uvm -timescale=1ns/1ps -kdb
vlogan -sverilog -full64 -ntb_opts uvm \
    +incdir+./tb +incdir+./rtl \
    -f rtl.flist -f tb.flist -kdb

vcs -full64 -top tb_top \
    -debug_pp -kdb \
    -cm line+cond+fsm+tgl+branch+assert \
    -cm_hier cm_hier.cfg \
    -ntb_opts uvm \
    -timescale=1ns/1ps \
    -o simv_regr \
    -l compile.log

# Run tests
for test in "${TESTS[@]}"; do
    for seed in "${SEEDS[@]}"; do
        DIR="results/${test}_seed${seed}"
        mkdir -p $DIR

        ./simv_regr \
            +UVM_TESTNAME=$test \
            +UVM_VERBOSITY=UVM_MEDIUM \
            +ntb_random_seed=$seed \
            +UVM_TIMEOUT=10000000,YES \
            -cm_name ${test}_seed${seed} \
            -cm_dir coverage/simv.vdb \
            -l ${DIR}/sim.log \
            +vcs+flush+all &
    done
done
wait

# Merge coverage
urg -dir coverage/simv.vdb -dbname merged -report urgReport -format both
echo "Coverage report: urgReport/dashboard.html"
```

### Gate-Level Simulation Flow

```bash
#!/bin/bash
# gate_sim.sh -- Gate-level simulation with SDF

# Compile
vcs -sverilog -full64 \
    -debug_pp -kdb \
    +define+GATE_SIM \
    +neg_tchk \
    +sdfverbose \
    -sdf max:tb_top.dut:netlist_max.sdf \
    +libext+.v+.sv \
    -v /path/to/std_cell.v \
    -v /path/to/io_cell.v \
    -v /path/to/mem_model.v \
    netlist.v tb_top.sv \
    -o simv_gate \
    -l gate_compile.log

# Simulate
./simv_gate \
    +vcs+flush+all \
    +vcs+initreg+0 \
    -l gate_sim.log
```

### Power-Aware Simulation Flow

```bash
#!/bin/bash
# pa_sim.sh -- Power-aware simulation with UPF

# Compile with UPF
vcs -sverilog -full64 \
    -debug_all -kdb \
    -upf power_intent.upf \
    +define+UPF_SIM \
    -f rtl.flist -f tb.flist \
    -o simv_pa \
    -l pa_compile.log

# Simulate with power-aware options
./simv_pa \
    +UVM_TESTNAME=power_test \
    +vcs+power+supply_on \
    +vcs+power+iso_on \
    +vcs+power+ret_on \
    -l pa_sim.log
```

### Multi-Language Simulation

```bash
#!/bin/bash
# mixed_lang.sh -- VHDL + Verilog/SV + SystemC

# Analyze VHDL
vhdlan -full64 -work ip_lib vhdl_block.vhd

# Analyze SystemVerilog
vlogan -sverilog -full64 -work work sv_top.sv sv_tb.sv

# Compile SystemC
syscan -full64 -sysc=2.3.1 sc_model.cpp

# Elaborate and link
vcs -full64 -top tb_top \
    -debug_pp -kdb \
    -sysc sc_main \
    -o simv_mixed \
    -l mixed_compile.log

# Simulate
./simv_mixed -l mixed_sim.log
```

### Quick Reference: Most Common Options

```bash
# Compile (development)
vcs -sverilog -full64 -debug_all -kdb -timescale=1ns/1ps -f all.flist -o simv

# Compile (regression)
vcs -sverilog -full64 -debug_pp -kdb -cm line+cond+tgl+fsm+branch -timescale=1ns/1ps -f all.flist -o simv

# Simulate (development)
./simv -gui +UVM_TESTNAME=test +UVM_VERBOSITY=UVM_HIGH +ntb_random_seed=42 -l sim.log

# Simulate (regression)
./simv +UVM_TESTNAME=test +UVM_VERBOSITY=UVM_LOW +ntb_random_seed_automatic -cm_name test -l sim.log +vcs+flush+all

# Coverage report
urg -dir "*/simv.vdb" -report urgReport -format both
```

---

*Document Version: 2026.05 -- Comprehensive VCS command reference for simulation, debug, coverage, and performance optimization.*
