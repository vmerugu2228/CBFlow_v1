# Siemens Questa Verification — Complete Command Reference

## Table of Contents

1. [Overview and Architecture](#overview-and-architecture)
2. [Compilation: vlog, vcom, vopt](#compilation)
3. [Simulation: vsim](#simulation)
4. [Runtime Commands](#runtime-commands)
5. [Waveform and Debug](#waveform-and-debug)
6. [Code Coverage](#code-coverage)
7. [Functional Coverage](#functional-coverage)
8. [Assertions (SVA/PSL)](#assertions)
9. [UVM Support](#uvm-support)
10. [Performance Optimization](#performance-optimization)
11. [Mixed-Signal Simulation](#mixed-signal-simulation)
12. [Advanced Features](#advanced-features)
13. [Common Flows and Recipes](#common-flows-and-recipes)

---

## 1. Overview and Architecture

### Questa Tool Components

| Tool | Purpose |
|------|---------|
| vlog | Verilog/SystemVerilog compiler |
| vcom | VHDL compiler |
| vopt | Design optimizer |
| vsim | Simulator/elaborator |
| vlib | Library management |
| vmap | Library mapping |
| vdir | Library directory listing |
| vdel | Library deletion |
| vmake | Makefile generation |
| vcover | Coverage analysis |
| qverilog | Single-command compile+simulate |
| qvhdl | Single-command VHDL compile+simulate |

### Basic Invocation Flow

```bash
# 1. Create work library
vlib work

# 2. Map library
vmap work ./work

# 3. Compile
vlog -sv design.sv
vlog -sv testbench.sv

# 4. Optimize (optional but recommended)
vopt top_tb -o top_tb_opt

# 5. Simulate
vsim -c top_tb_opt -do "run -all; quit"
```

### Environment Setup

```bash
# Questa environment
export QUESTA_HOME=/opt/siemens/questa/2024.1
export PATH=$QUESTA_HOME/bin:$PATH
export MGLS_LICENSE_FILE=27000@license_server

# Library path for UVM
export UVM_HOME=$QUESTA_HOME/verilog_src/uvm-1.2

# ModelSim compatibility
export MODEL_TECH=$QUESTA_HOME
export MODELSIM=./modelsim.ini
```

---

## 2. Compilation

### 2.1 vlog — Verilog/SystemVerilog Compiler

```bash
# Basic Verilog compilation
vlog design.v

# SystemVerilog compilation
vlog -sv design.sv

# SystemVerilog 2012
vlog -sv12 design.sv

# Multiple files
vlog -sv design.sv testbench.sv package.sv

# Compile into specific library
vlog -sv -work mylib design.sv

# Include directories
vlog -sv +incdir+./includes +incdir+./src design.sv

# Define macros
vlog -sv +define+SIMULATION +define+DEBUG=1 design.sv

# Suppress specific warnings
vlog -sv -suppress 2583,2244 design.sv

# Error on warnings
vlog -sv -error 2583 design.sv

# Lint checks
vlog -sv -lint design.sv

# Pedantic mode (strict standard compliance)
vlog -sv -pedanticerrors design.sv

# File list
vlog -sv -f filelist.f

# Timing annotations
vlog -sv +notimingchecks design.sv
vlog -sv +nospecify design.sv

# Verilog 2001
vlog -vlog01compat design.v

# Mixed language support
vlog -sv -mixedsvvh design.sv

# Optimize for coverage
vlog -sv -cover bcesfx design.sv

# Debug options
vlog -sv +acc design.sv              # full access (slow)
vlog -sv +acc=rnbp design.sv         # specific access

# 64-bit compilation
vlog -sv -64 design.sv

# Parallel compilation
vlog -sv -j 8 design.sv              # 8 parallel jobs

# Output compilation stats
vlog -sv -timescale "1ns/1ps" design.sv

# Library cell compilation
vlog -sv -work cellslib -y /path/to/cells +libext+.v
```

### 2.2 vlog Options Reference

```bash
# Compilation switches
-sv                      # SystemVerilog mode
-sv05                    # SystemVerilog 2005
-sv09                    # SystemVerilog 2009
-sv12                    # SystemVerilog 2012
-sv17                    # SystemVerilog 2017
-vlog01compat            # Verilog 2001 compatibility
-vlog95compat            # Verilog 1995 compatibility
-work <library>          # target library
-f <filelist>            # file list
-F <filelist>            # file list (relative paths)
-y <dir>                 # library directory
+libext+.v+.sv           # library extensions
+incdir+<dir>            # include directory
+define+<macro>=<value>  # define macro
-timescale <ts>          # default timescale
-suppress <nums>         # suppress warnings
-error <nums>            # promote warnings to errors
-lint                    # enable lint checks
-pedanticerrors          # strict compliance
-cover <types>           # enable coverage
-64                      # 64-bit mode
-j <n>                   # parallel jobs
-O0                      # no optimization
-O4                      # aggressive optimization
-O5                      # maximum optimization
-quiet                   # suppress banner
-nocoverfec              # no FEC in coverage
-nocoveraliases          # no aliases in coverage
-dpiheader <file>        # generate DPI header
+acc                     # full signal access
+acc=rnbp                # selective access (read, net, bit, port)
-nologo                  # suppress logo
-mfcu                    # multi-file compilation unit
-cuname <name>           # compilation unit name
-svinputport=compat      # SV input port compatibility
-svinputport=net         # SV input ports as nets
-svinputport=var         # SV input ports as variables
```

### 2.3 vcom — VHDL Compiler

```bash
# Basic VHDL compilation
vcom design.vhd

# VHDL 2008
vcom -2008 design.vhd

# VHDL 1993
vcom -93 design.vhd

# VHDL 2002
vcom -2002 design.vhd

# VHDL 2019
vcom -2019 design.vhd

# Compile into library
vcom -work mylib design.vhd

# Multiple files
vcom entity.vhd architecture.vhd testbench.vhd

# Check syntax only
vcom -check_synthesis design.vhd

# With coverage
vcom -cover bcesfx design.vhd

# Suppress warnings
vcom -suppress 1236 design.vhd

# Debug
vcom +acc design.vhd

# Explicit binding
vcom -explicit design.vhd

# Performance flags
vcom -O4 design.vhd
```

### 2.4 vopt — Design Optimizer

```bash
# Basic optimization
vopt top_tb -o top_tb_opt

# With full debug access
vopt +acc top_tb -o top_tb_opt

# Selective access (faster)
vopt +acc=rnbp top_tb -o top_tb_opt

# Named access for specific hierarchy
vopt +acc=rnbp+/top_tb/dut top_tb -o top_tb_opt

# With coverage
vopt +cover=bcesfx top_tb -o top_tb_opt

# With assertions
vopt +acc top_tb -o top_tb_opt -assertdebug

# 64-bit
vopt -64 top_tb -o top_tb_opt

# Optimization level
vopt -O0 top_tb -o top_tb_opt     # debug mode (no optimization)
vopt -O4 top_tb -o top_tb_opt     # aggressive optimization
vopt -O5 top_tb -o top_tb_opt     # maximum optimization

# Include timing
vopt top_tb -o top_tb_opt +notimingchecks
vopt top_tb -o top_tb_opt -sdfmin /dut=design.sdf

# Glitch filtering
vopt top_tb -o top_tb_opt -gf    # glitch filtering

# Multi-threaded optimization
vopt -j 4 top_tb -o top_tb_opt

# VHDL generics override
vopt -g WIDTH=16 -g DEPTH=256 top_tb -o top_tb_opt

# Verilog parameter override
vopt -G /top_tb/dut/WIDTH=16 top_tb -o top_tb_opt
```

### 2.5 Library Management

```bash
# Create library
vlib work
vlib mylib
vlib ./libs/design_lib

# Map library
vmap work ./work
vmap mylib ./libs/mylib

# List library contents
vdir work
vdir -lib work

# Delete from library
vdel -lib work -all    # delete all units
vdel -lib work top_tb  # delete specific unit

# Copy between libraries
vcopy work.top_tb mylib.top_tb

# Check library integrity
vlib -check work

# Refresh library
vlib -refresh work
```

---

## 3. Simulation: vsim

### 3.1 Basic Simulation Launch

```bash
# Interactive simulation (GUI)
vsim top_tb

# Batch simulation (no GUI)
vsim -c top_tb -do "run -all; quit"

# With optimized design
vsim -c top_tb_opt -do "run -all; quit"

# With do file
vsim -c top_tb -do simulation.do

# Specify library
vsim -lib work top_tb

# With generics/parameters
vsim -c top_tb -g WIDTH=16 -g DEPTH=256
vsim -c top_tb -G /top_tb/dut/WIDTH=16

# With SDF timing
vsim -c top_tb -sdfmin /top_tb/dut=design.sdf
vsim -c top_tb -sdftyp /top_tb/dut=design.sdf
vsim -c top_tb -sdfmax /top_tb/dut=design.sdf

# Multiple SDF files
vsim -c top_tb \
    -sdfmin /top_tb/dut/core=core.sdf \
    -sdfmax /top_tb/dut/io=io.sdf

# With VCD dump
vsim -c top_tb -vcdfile dump.vcd

# Suppress specific messages
vsim -c top_tb -suppress 3839,8233

# With license queueing
vsim -c top_tb -lic_noqueue
vsim -c top_tb -lic_wait

# 64-bit simulation
vsim -64 -c top_tb

# Seed for random
vsim -c top_tb -sv_seed 12345
vsim -c top_tb -sv_seed random

# With transcript
vsim -c top_tb -l simulation.log
```

### 3.2 vsim Options Reference

```bash
# Simulation control
-c                           # command-line (batch) mode
-gui                         # GUI mode (default)
-i                           # interactive command-line
-do <file_or_cmd>            # execute do file or command
-l <logfile>                 # transcript file
-quiet                       # suppress banner
-64                          # 64-bit mode

# Timing
-sdfmin <inst>=<file>        # min SDF annotation
-sdftyp <inst>=<file>        # typical SDF annotation
-sdfmax <inst>=<file>        # max SDF annotation
+notimingchecks              # disable timing checks
+nospecify                   # disable specify blocks
-sdfnoerror                  # no error on SDF mismatch
-sdfnowarn                   # suppress SDF warnings

# Parameters/Generics
-g <name>=<value>            # VHDL generic
-G <path/name>=<value>       # Verilog parameter

# Coverage
-coverage                    # enable all coverage
-coveropt 1                  # coverage optimization
-coverfec                    # finite expression coverage
-coveraliases                # coverage aliases
-togglewidthlimit <n>        # toggle width limit

# Debug
-debugDB                     # debug database for Visualizer
-classdebug                  # class debug
-assertdebug                 # assertion debug
+acc                         # full access
-onfinish stop               # stop on $finish

# Random seed
-sv_seed <value>             # SystemVerilog random seed
-sv_seed random              # random seed

# Performance
-novopt                      # disable automatic optimization
-wlf <file>                  # WLF output file
-wlfslim                     # slim WLF file
-wlfcollapse                 # collapse WLF signals
+noacc                       # no signal access (fastest)

# VPI/DPI
-pli <library>               # load PLI library
-sv_lib <library>            # load DPI library
-dpioutoftheblue 1           # DPI out-of-the-blue calls

# UVM
+UVM_TESTNAME=<test>         # UVM test name
+UVM_VERBOSITY=<level>       # UVM verbosity
+UVM_NO_RELNOTES             # suppress UVM release notes

# Messaging
-suppress <msgids>           # suppress messages
-error <msgids>              # promote to errors
-fatal <msgids>              # promote to fatal
-warning <msgids>            # demote to warnings
-note <msgids>               # demote to notes
-msgmode both                # both tran and wlf
```

---

## 4. Runtime Commands

### 4.1 Simulation Control

```tcl
# Run simulation
run -all                     ;# run until $finish or assertion
run 100ns                    ;# run for 100ns
run 1000                     ;# run for 1000 timesteps
run -continue                ;# continue after break

# Step
step                         ;# step one event
step 10                      ;# step 10 events

# Stop / Break
stop                         ;# stop simulation
break                        ;# break at current point
pause                        ;# pause simulation

# Restart
restart -f                   ;# restart simulation (fast)
restart                      ;# restart with confirmation

# End simulation
quit -f                      ;# quit without confirmation
quit -sim                    ;# end simulation, keep GUI
quit -code 0                 ;# quit with exit code

# Abort
abort                        ;# abort simulation
```

### 4.2 Signal Examination and Forcing

```tcl
# Examine signal values
examine /top_tb/dut/clk
examine -radix hex /top_tb/dut/data_bus
examine -radix bin /top_tb/dut/control
examine -radix unsigned /top_tb/dut/counter
examine -time 100ns /top_tb/dut/state         ;# value at specific time

# Examine arrays/memories
examine /top_tb/dut/mem_array(0)
examine /top_tb/dut/mem_array(0 to 15)

# Examine with wildcards
examine /top_tb/dut/u_core/*

# Force signal values
force /top_tb/dut/clk 0 0, 1 5ns -repeat 10ns    ;# clock
force /top_tb/dut/reset 1 0, 0 100ns               ;# reset pulse
force /top_tb/dut/data 8'hFF                        ;# constant
force /top_tb/dut/enable 1                           ;# constant 1

# Force with deposit (no driver)
force -deposit /top_tb/dut/signal 1

# Force with freeze (override drivers)
force -freeze /top_tb/dut/signal 0

# Force with drive (acts as driver)
force -drive /top_tb/dut/signal 1

# Release force
noforce /top_tb/dut/signal
noforce /top_tb/dut/*                               ;# release all forces

# Change signal value (deposit)
change /top_tb/dut/counter 8'h00

# Describe signals
describe /top_tb/dut/state
describe -full /top_tb/dut/data_bus
```

### 4.3 Breakpoints and Watchpoints

```tcl
# When breakpoint (conditional)
when {/top_tb/dut/error == 1} {
    echo "Error detected at time $now"
    stop
}

# When with signal change
when -label watch_state {/top_tb/dut/state} {
    echo "State changed to [examine /top_tb/dut/state] at $now"
}

# Breakpoint at time
bp 1000ns

# Breakpoint on signal
bp /top_tb/dut/done -value 1

# List breakpoints
bp

# Delete breakpoint
bd *                         ;# delete all breakpoints
bd 1                         ;# delete breakpoint #1

# Enable/disable breakpoints
be *                         ;# enable all
be 1                         ;# enable #1
bi 1                         ;# disable (inhibit) #1

# When with expression
when -label check_overflow {
    /top_tb/dut/counter > 8'hF0
} {
    echo "Counter near overflow at $now"
}

# On signal transition
onbreak resume               ;# resume after break
onbreak stop                 ;# stop after break
```

### 4.4 Process and Thread Control

```tcl
# List active processes
status

# Show simulation time
echo $now

# Show resolution
echo $resolution

# Environment info
environment
find instances /top_tb/*
find signals /top_tb/dut/*
find processes /top_tb/*
find memories /top_tb/dut/*

# Hierarchy navigation
cd /top_tb/dut
ls
ls -r                        ;# recursive listing
pwd
```

---

## 5. Waveform and Debug

### 5.1 Wave Window Commands

```tcl
# Add signals to wave window
add wave /top_tb/dut/clk
add wave /top_tb/dut/reset
add wave /top_tb/dut/data_bus
add wave -radix hex /top_tb/dut/address

# Add all signals in hierarchy
add wave /top_tb/dut/*
add wave -r /top_tb/dut/*              ;# recursive

# Add with grouping
add wave -group "Clocks" /top_tb/dut/clk /top_tb/dut/clk2
add wave -group "Control" /top_tb/dut/reset /top_tb/dut/enable

# Add with divider
add wave -divider "=== DUT Signals ==="
add wave /top_tb/dut/data_in
add wave -divider "=== TB Signals ==="
add wave /top_tb/stimulus/*

# Wave format options
add wave -radix hex /top_tb/dut/data
add wave -radix bin /top_tb/dut/control
add wave -radix unsigned /top_tb/dut/counter
add wave -radix decimal /top_tb/dut/signed_val
add wave -radix ascii /top_tb/dut/char
add wave -radix symbolic /top_tb/dut/state    ;# enum display

# Wave display options
add wave -color yellow /top_tb/dut/clk
add wave -height 40 /top_tb/dut/data
add wave -format analog-step /top_tb/dut/dac_out
add wave -format analog-interpolated /top_tb/dut/adc_in
add wave -format literal /top_tb/dut/state

# Remove signals from wave
delete wave /top_tb/dut/clk
```

### 5.2 Logging

```tcl
# Log signals to WLF
log /top_tb/dut/*
log -r /top_tb/dut/*                     ;# recursive
log -r /*                                 ;# all signals

# Log with options
log -ports /top_tb/dut/*                  ;# ports only
log -internal /top_tb/dut/*               ;# internal signals only
log -events /top_tb/dut/*                 ;# event-based

# WLF file management
dataset open simulation.wlf
dataset close

# VCD dump
vcd file dump.vcd
vcd add /top_tb/dut/*
vcd on
run -all
vcd off
vcd flush

# FSDB dump (for Verdi)
fsdbDumpfile "dump.fsdb"
fsdbDumpvars 0 /top_tb
```

### 5.3 Bookmarks and Navigation

```tcl
# Add bookmark
bookmark add -name "error_point" -time 5432ns

# List bookmarks
bookmark list

# Go to bookmark
bookmark goto "error_point"

# Zoom controls
wave zoom full
wave zoom in
wave zoom out
wave zoom range 100ns 200ns

# Cursor
wave cursor add -time 150ns
wave cursor delete

# Save wave configuration
write format wave wave_config.do

# Load wave configuration
do wave_config.do
```

### 5.4 Visualizer (Advanced Debug)

```tcl
# Launch Visualizer
vsim -debugDB top_tb                    ;# generate debug database

# Visualizer features (GUI-based):
# - Transaction-level debug
# - Protocol analysis
# - Class/object browser
# - Memory window
# - Assertion window
# - Coverage window

# Visualizer batch mode
vis -do visualizer_commands.tcl
```

---

## 6. Code Coverage

### 6.1 Enabling Coverage

```bash
# Enable during compilation
vlog -sv -cover bcesfx design.sv
vcom -cover bcesfx design.vhd
vopt +cover=bcesfx top_tb -o top_tb_opt

# Coverage types:
# b - branch coverage
# c - condition coverage
# e - expression coverage
# s - statement coverage
# f - FSM coverage (state + transition)
# x - toggle coverage

# Enable during simulation
vsim -coverage top_tb_opt

# Or specific types
vsim -coverage -coveropt 1 top_tb_opt
```

### 6.2 Coverage Collection

```tcl
# Coverage enable/disable during simulation
coverage save -onexit coverage.ucdb       ;# save on exit

# Coverage exclusions
coverage exclude -src design.sv -line 45
coverage exclude -du /top_tb/dut -toggle clk
coverage exclude -instance /top_tb/dut/u_debug

# Toggle coverage width limit
coverage configure -toggle_widthlimit 32

# FSM coverage
coverage configure -fsmimplicittrans

# Expression coverage
coverage configure -exprmerge on

# Save coverage database
coverage save coverage_test1.ucdb

# Coverage reporting during simulation
coverage report -summary
coverage report -detail
```

### 6.3 vcover — Coverage Analysis Tool

```bash
# Merge multiple coverage databases
vcover merge merged.ucdb test1.ucdb test2.ucdb test3.ucdb
vcover merge -out merged.ucdb -inputs ucdb_list.txt

# Generate HTML report
vcover report -html -output cov_html merged.ucdb
vcover report -html -details -output cov_html merged.ucdb

# Text report
vcover report merged.ucdb > coverage_report.txt
vcover report -detail merged.ucdb > coverage_detail.txt

# Specific coverage type reports
vcover report -toggle merged.ucdb
vcover report -branch merged.ucdb
vcover report -condition merged.ucdb
vcover report -statement merged.ucdb
vcover report -fsm merged.ucdb
vcover report -expression merged.ucdb

# Per-instance report
vcover report -instance /top_tb/dut/* merged.ucdb

# Per-file report
vcover report -srcfile design.sv merged.ucdb

# Exclusion file
vcover report -excl exclusions.do merged.ucdb

# Coverage statistics
vcover stats merged.ucdb

# Compare coverage databases
vcover diff old.ucdb new.ucdb -output diff.ucdb

# Ranking (minimum test set)
vcover ranktest merged.ucdb -output ranking.txt

# Filter coverage
vcover report -threshold 80 merged.ucdb    ;# items below 80%
vcover report -below 100 merged.ucdb       ;# items below 100%

# XML report for CI/CD
vcover report -xml -output coverage.xml merged.ucdb

# Coverage trending
vcover trend -output trend.html ucdb1 ucdb2 ucdb3
```

### 6.4 Coverage Exclusions

```tcl
# In do file or inline

# Exclude by source line
coverage exclude -src design.sv -line 45
coverage exclude -src design.sv -linerange 100 150

# Exclude instance
coverage exclude -instance /top_tb/dut/u_debug -toggleall
coverage exclude -instance /top_tb/dut/u_jtag -stmtall

# Exclude by signal name
coverage exclude -du /top_tb/dut -toggle scan_*

# Exclude pragmas in RTL
// synthesis translate_off
// coverage off
// ... code not covered ...
// coverage on
// synthesis translate_on

# Or using Questa-specific pragmas:
// pragma coverage off
// ... code ...
// pragma coverage on

// pragma coverage block = off
always @(posedge clk) begin
    // pragma coverage block = on
end
```

---

## 7. Functional Coverage

### 7.1 SystemVerilog Covergroups

```systemverilog
// Define covergroup in SV (not a Questa command, but key context)
covergroup cg_transaction @(posedge clk);
    option.per_instance = 1;
    option.goal = 100;

    cp_opcode: coverpoint tr.opcode {
        bins read  = {OP_READ};
        bins write = {OP_WRITE};
        bins idle  = {OP_IDLE};
        illegal_bins reserved = {[3:7]};
    }

    cp_addr: coverpoint tr.addr {
        bins low    = {[0:255]};
        bins mid    = {[256:511]};
        bins high   = {[512:1023]};
    }

    cross_op_addr: cross cp_opcode, cp_addr;
endgroup
```

### 7.2 Functional Coverage Commands in Questa

```tcl
# Report functional coverage
coverage report -detail -cvg

# List covergroups
coverage report -cvg -summary

# Per-coverpoint report
coverage report -cvg -detail -coverpoint

# Specific covergroup
coverage report -cvg -inst /top_tb/env/cov_collector/cg_transaction

# Uncovered bins
coverage report -cvg -detail -zeros

# Save functional coverage
coverage save -onexit func_cov.ucdb

# Merge functional coverage
vcover merge merged_fcov.ucdb test1.ucdb test2.ucdb

# HTML report
vcover report -html -cvg -output fcov_html merged_fcov.ucdb

# Coverage goal tracking
coverage report -cvg -totals
```

---

## 8. Assertions (SVA/PSL)

### 8.1 Assertion Debug

```tcl
# Enable assertion debug
vsim -assertdebug top_tb_opt

# Or during vopt
vopt +acc top_tb -o top_tb_opt -assertdebug

# Assertion control
assertion fail -action break     ;# break on assertion failure
assertion fail -action continue  ;# continue on failure
assertion fail -action error     ;# report error

# Enable/disable assertions
assertion enable /top_tb/dut/*
assertion disable /top_tb/dut/u_debug/*

# Assertion count control
assertion fail -limit 100        ;# max 100 failures per assertion

# Report assertions
assertion report
assertion report -detail
assertion report -failures

# Assertion coverage
assertion report -coverage

# List all assertions
assertion list
assertion list -active
assertion list -inactive

# Watch assertion
assertion watch /top_tb/dut/a_handshake
```

### 8.2 Assertion Waveform Debug

```tcl
# Add assertions to wave
add wave -assertion /top_tb/dut/a_handshake
add wave -assertion /top_tb/dut/*            ;# all assertions

# Assertion debug in wave:
# - Green = pass
# - Red = fail
# - Yellow = active/pending
# - Gray = disabled

# Log assertion activity
log -assertion /top_tb/dut/*
```

---

## 9. UVM Support

### 9.1 UVM Compilation and Simulation

```bash
# Compile with UVM
vlog -sv +incdir+$UVM_HOME/src $UVM_HOME/src/uvm_pkg.sv
vlog -sv +incdir+./src -f filelist.f

# Or use built-in UVM (Questa ships with UVM)
vlog -sv +incdir+$QUESTA_HOME/verilog_src/uvm-1.2/src \
    $QUESTA_HOME/verilog_src/uvm-1.2/src/uvm_pkg.sv

# Simulate with UVM test
vsim -c top_tb \
    +UVM_TESTNAME=basic_test \
    +UVM_VERBOSITY=UVM_MEDIUM \
    -do "run -all; quit"

# With UVM seed
vsim -c top_tb \
    +UVM_TESTNAME=random_test \
    -sv_seed random \
    -do "run -all; quit"
```

### 9.2 UVM Plus-Args

```bash
# Test selection
+UVM_TESTNAME=my_test

# Verbosity levels
+UVM_VERBOSITY=UVM_NONE        # 0
+UVM_VERBOSITY=UVM_LOW         # 100
+UVM_VERBOSITY=UVM_MEDIUM      # 200
+UVM_VERBOSITY=UVM_HIGH        # 300
+UVM_VERBOSITY=UVM_FULL        # 400
+UVM_VERBOSITY=UVM_DEBUG       # 500

# Component verbosity override
+uvm_set_verbosity=uvm_test_top.env.agent,_ALL_,UVM_HIGH

# Factory override (type)
+uvm_set_type_override=base_driver,extended_driver

# Factory override (instance)
+uvm_set_inst_override=env.agent.driver,base_driver,extended_driver

# Timeout
+UVM_TIMEOUT=1000000,YES       # timeout in ns, overridable

# Max quit count
+UVM_MAX_QUIT_COUNT=10,YES

# Config DB settings
+uvm_set_config_int=*,num_transactions,100
+uvm_set_config_string=*,filename,test_data.txt

# Objection debug
+UVM_OBJECTION_TRACE

# Phase debug
+UVM_PHASE_TRACE

# Config DB tracing
+UVM_CONFIG_DB_TRACE

# Resource DB tracing
+UVM_RESOURCE_DB_TRACE

# Suppress UVM release notes
+UVM_NO_RELNOTES

# Dump test hierarchy
+UVM_DUMP_CMDLINE_ARGS
```

### 9.3 UVM Debug in Questa

```tcl
# UVM-aware debug (Visualizer)
vsim -classdebug -uvmcontrol=all top_tb

# UVM control options
-uvmcontrol=all              ;# all UVM debug
-uvmcontrol=trlog            ;# transaction logging
-uvmcontrol=cmplog           ;# component logging
-uvmcontrol=msglog           ;# message logging
-uvmcontrol=phslog           ;# phase logging
-uvmcontrol=struct           ;# structural views
-uvmcontrol=disable          ;# disable UVM debug

# Transaction recording
-transaction on               ;# enable transaction recording

# Class debug
-classdebug                  ;# enable class object debug

# UVM-specific examination
uvm_examine /uvm_test_top.env.agent.driver
uvm_examine -all /uvm_test_top

# Factory display
uvm_factory_display

# Topology
uvm_topology
```

---

## 10. Performance Optimization

### 10.1 Compilation Optimization

```bash
# Optimization levels
vopt -O0 top_tb -o opt_debug   ;# no optimization (debug)
vopt -O1 top_tb -o opt_low     ;# low optimization
vopt -O4 top_tb -o opt_high    ;# high optimization (default)
vopt -O5 top_tb -o opt_max     ;# maximum optimization

# Disable access for speed
vopt +noacc top_tb -o opt_fast

# Selective access (recommended for balanced speed+debug)
vopt +acc=rnbp+/top_tb/dut top_tb -o opt_balanced

# Inline optimization
vopt -inline top_tb -o opt_inline

# Constant propagation
vopt -constprop top_tb -o opt_constprop
```

### 10.2 Simulation Performance

```bash
# Parallel simulation (Questa Multi-Core)
vsim -c -multisource top_tb_opt

# Thread count
vsim -c -threads 4 top_tb_opt

# Memory optimization
vsim -c -wlfslim top_tb_opt              ;# slim WLF
vsim -c -wlfcollapse top_tb_opt          ;# collapse identical signals
vsim -c -wlftlimit 1000000 top_tb_opt    ;# limit WLF size

# Suppress unnecessary logging
vsim -c -suppress 3839 top_tb_opt         ;# suppress toggle messages

# Disable timing checks for faster simulation
vsim -c +notimingchecks +nospecify top_tb_opt

# Large design optimizations
vsim -c -64 top_tb_opt                    ;# 64-bit for large designs
vsim -c -memory 8192 top_tb_opt           ;# memory limit (MB)

# Fast startup
vsim -c -fast top_tb_opt
```

### 10.3 Questa Multi-Core Simulation

```bash
# Enable multi-core simulation
vlog -sv -j 8 design.sv                  ;# parallel compilation
vopt -j 4 top_tb -o opt_mc               ;# parallel optimization

# Multi-core simulation
vsim -c -threads 8 opt_mc -do "run -all; quit"

# Partition for parallelism
vopt +partition=auto top_tb -o opt_partitioned
vsim -c -threads 8 opt_partitioned
```

---

## 11. Mixed-Signal Simulation

### 11.1 Questa ADMS (Analog/Digital Mixed-Signal)

```bash
# Compile analog (SPICE/Spectre)
vlog -ams analog_block.vams
vlog -ams -f analog_filelist.f

# Connect rules
vlog -sv -connectrules connect_rules.sv

# Simulate mixed-signal
vsim -c top_tb \
    -ams \
    -amsconnectrules connect_rules \
    -do "run -all; quit"

# With SPICE solver
vsim -c top_tb \
    -ams \
    -eldo                              ;# use Eldo analog solver
    -do "run -all; quit"
```

### 11.2 Connect Rules

```systemverilog
// SystemVerilog connect rules for AMS
connectrules connect_rules;
    connect_rule logic_to_analog;
        from logic;
        to electrical;
        connect_module d2a_converter;
    end_connect_rule

    connect_rule analog_to_logic;
        from electrical;
        to logic;
        connect_module a2d_converter;
    end_connect_rule
end_connectrules
```

### 11.3 AMS Commands

```tcl
# During simulation
ams_info                     ;# display AMS info
ams_control accuracy high    ;# set analog accuracy
ams_control step max 1ns     ;# max analog step
ams_control reltol 1e-4      ;# relative tolerance
ams_control abstol 1e-12     ;# absolute tolerance

# Analog probing
probe analog /top_tb/dut/vdd
probe analog /top_tb/dut/vss
```

---

## 12. Advanced Features

### 12.1 SystemVerilog DPI (Direct Programming Interface)

```bash
# Generate DPI header
vlog -sv -dpiheader dpi_header.h design.sv

# Compile C code
gcc -shared -fPIC -o dpi_lib.so dpi_impl.c \
    -I$QUESTA_HOME/include

# Simulate with DPI library
vsim -c top_tb -sv_lib dpi_lib -do "run -all; quit"

# Multiple DPI libraries
vsim -c top_tb \
    -sv_lib dpi_lib1 \
    -sv_lib dpi_lib2 \
    -do "run -all; quit"
```

### 12.2 VPI/PLI

```bash
# Compile VPI code
gcc -shared -fPIC -o vpi_lib.so vpi_impl.c \
    -I$QUESTA_HOME/include

# Load VPI library
vsim -c top_tb -pli vpi_lib.so -do "run -all; quit"
```

### 12.3 Power-Aware Simulation (UPF)

```bash
# Read UPF during simulation
vsim -c top_tb \
    -pa \
    -pa_upf design.upf \
    -do "run -all; quit"

# Power-aware options
vsim -c top_tb \
    -pa \
    -pa_upf design.upf \
    -pa_genrpt on \
    -pa_checks on \
    -pa_highlight on
```

### 12.4 Memory and Array Debug

```tcl
# Memory window (GUI)
mem display /top_tb/dut/u_sram/mem_array

# Memory commands
mem load -i mem_init.hex /top_tb/dut/u_sram/mem_array
mem save -o mem_dump.hex /top_tb/dut/u_sram/mem_array

# Load memory from file
mem load -i data.mem -format hex /top_tb/dut/ram/mem

# Examine memory range
mem display -startaddress 0 -endaddress 255 /top_tb/dut/ram/mem
```

### 12.5 Virtual Interfaces and Register Model Debug

```tcl
# Examine UVM register model
uvm_reg_display /uvm_test_top/env/reg_model

# Read register value
uvm_reg_read /uvm_test_top/env/reg_model/status_reg

# Compare register values
uvm_reg_check /uvm_test_top/env/reg_model
```

### 12.6 Do File Scripting

```tcl
# ========================================
# Example comprehensive do file
# ========================================

# Set up environment
set TOP /top_tb
set DUT $TOP/dut

# Add waves
add wave -divider "=== Clocks & Reset ==="
add wave -color cyan $DUT/clk
add wave -color yellow $DUT/reset_n

add wave -divider "=== AXI Interface ==="
add wave -group "AXI Write" -radix hex \
    $DUT/awaddr $DUT/awvalid $DUT/awready \
    $DUT/wdata $DUT/wvalid $DUT/wready \
    $DUT/bresp $DUT/bvalid $DUT/bready

add wave -group "AXI Read" -radix hex \
    $DUT/araddr $DUT/arvalid $DUT/arready \
    $DUT/rdata $DUT/rvalid $DUT/rready $DUT/rresp

add wave -divider "=== Internal ==="
add wave -radix symbolic $DUT/state
add wave -radix hex $DUT/data_reg
add wave $DUT/error $DUT/done

# Set up breakpoints
when {$DUT/error == 1} {
    echo "*** ERROR detected at time $now ***"
    stop
}

# Configure coverage
coverage save -onexit coverage.ucdb

# Log everything
log -r $DUT/*

# Run
run -all

# Generate reports
coverage report -detail > coverage_report.txt
echo "Simulation complete"
quit -f
```

---

## 13. Common Flows and Recipes

### 13.1 Complete RTL Simulation Flow

```bash
#!/bin/bash
# Complete Questa simulation flow

DESIGN="my_design"
TOP="top_tb"
SEED=${1:-random}

# 1. Create library
vlib work 2>/dev/null

# 2. Compile
vlog -sv -64 +incdir+./src +incdir+./tb \
    +define+SIMULATION \
    -cover bcesfx \
    -f rtl_filelist.f \
    -f tb_filelist.f \
    2>&1 | tee compile.log

# Check compilation
if grep -q "Errors: [^0]" compile.log; then
    echo "COMPILATION FAILED"
    exit 1
fi

# 3. Optimize
vopt -64 +cover=bcesfx +acc=rnbp+/$TOP/dut \
    $TOP -o ${TOP}_opt \
    2>&1 | tee optimize.log

# 4. Simulate
vsim -64 -c ${TOP}_opt \
    -coverage \
    -sv_seed $SEED \
    +UVM_TESTNAME=basic_test \
    +UVM_VERBOSITY=UVM_MEDIUM \
    -l sim_${SEED}.log \
    -do "coverage save -onexit cov_${SEED}.ucdb; run -all; quit -f" \
    2>&1 | tee sim.log

# 5. Check results
if grep -q "UVM_FATAL" sim.log; then
    echo "SIMULATION FAILED"
    exit 1
elif grep -q "UVM_ERROR" sim.log; then
    echo "SIMULATION PASSED WITH ERRORS"
else
    echo "SIMULATION PASSED"
fi
```

### 13.2 Regression Flow

```bash
#!/bin/bash
# Regression flow with coverage merge

TESTS="basic_test stress_test corner_test random_test"
SEEDS="12345 67890 11111 random"

# Run all tests
for test in $TESTS; do
    for seed in $SEEDS; do
        echo "Running $test with seed $seed"
        vsim -64 -c top_tb_opt \
            -coverage \
            -sv_seed $seed \
            +UVM_TESTNAME=$test \
            -l logs/${test}_${seed}.log \
            -do "coverage save -onexit ucdb/${test}_${seed}.ucdb; run -all; quit -f" &
    done
done
wait

# Merge coverage
vcover merge merged_coverage.ucdb ucdb/*.ucdb

# Generate reports
vcover report -html -details -output cov_report merged_coverage.ucdb
vcover report -totals merged_coverage.ucdb > coverage_summary.txt

# Check coverage targets
vcover report -threshold 90 merged_coverage.ucdb > below_90.txt

echo "Regression complete"
echo "Coverage report: cov_report/index.html"
```

### 13.3 Gate-Level Simulation Flow

```bash
#!/bin/bash
# Gate-level simulation with SDF

# Compile gate-level netlist
vlog -sv +define+GATE_SIM \
    -y /path/to/std_cells +libext+.v \
    gate_netlist.v \
    testbench.sv

# Optimize with SDF
vopt +acc top_tb -o gate_opt \
    -sdfmax /top_tb/dut=design_max.sdf \
    +notimingchecks    # optional: suppress timing violations initially

# Simulate
vsim -64 -c gate_opt \
    -sdfmax /top_tb/dut=design_max.sdf \
    +UVM_TESTNAME=gate_test \
    -l gate_sim.log \
    -do "run -all; quit -f"

# Check for timing violations
grep "Timing violation" gate_sim.log | sort | uniq -c | sort -rn > timing_violations.txt
```

### 13.4 Makefile Template

```makefile
# Questa Makefile template
QUESTA_HOME ?= /opt/siemens/questa/2024.1
VLOG = vlog
VOPT = vopt
VSIM = vsim
VLIB = vlib
VCOVER = vcover

TOP = top_tb
SEED ?= random
TEST ?= basic_test

RTL_FILES = -f rtl_filelist.f
TB_FILES = -f tb_filelist.f

VLOG_OPTS = -sv -64 +incdir+./src +incdir+./tb +define+SIMULATION
VOPT_OPTS = -64 +cover=bcesfx +acc=rnbp+/$(TOP)/dut
VSIM_OPTS = -64 -c -coverage -sv_seed $(SEED)
UVM_OPTS = +UVM_TESTNAME=$(TEST) +UVM_VERBOSITY=UVM_MEDIUM

.PHONY: all compile optimize sim clean

all: compile optimize sim

lib:
	$(VLIB) work

compile: lib
	$(VLOG) $(VLOG_OPTS) -cover bcesfx $(RTL_FILES) $(TB_FILES)

optimize: compile
	$(VOPT) $(VOPT_OPTS) $(TOP) -o $(TOP)_opt

sim: optimize
	$(VSIM) $(VSIM_OPTS) $(TOP)_opt $(UVM_OPTS) \
		-l sim.log \
		-do "coverage save -onexit coverage.ucdb; run -all; quit -f"

gui: optimize
	$(VSIM) $(TOP)_opt $(UVM_OPTS) \
		-do "add wave -r /$(TOP)/dut/*; run -all"

coverage:
	$(VCOVER) report -html -details -output cov_report coverage.ucdb

clean:
	rm -rf work transcript *.log *.ucdb *.wlf cov_report
```

---

*This document covers the Siemens Questa verification platform including compilation, simulation, coverage, assertions, UVM support, performance optimization, and mixed-signal simulation. For specific library compilation and foundry cell model setup, consult your technology vendor documentation.*
