# RISC-V Architecture: ISA, Privilege Levels, Custom Instructions, and Ecosystem

## Overview

RISC-V is an open-standard instruction set architecture (ISA) that has rapidly gained adoption across embedded, edge, datacenter, and accelerator applications. Unlike proprietary ISAs (ARM, x86), RISC-V is royalty-free and extensible, enabling organizations to customize the processor without licensing fees. Understanding RISC-V's modular ISA, privilege model, extension mechanism, and growing ecosystem is essential for SoC designers evaluating or integrating RISC-V cores.

## ISA Foundation

### Base Integer ISAs

RISC-V defines multiple base ISAs differentiated by register width:

- **RV32I**: 32-bit integer base; 32 registers (x0-x31), x0 hardwired to zero; 47 instructions
- **RV64I**: 64-bit integer base; extends RV32I with 64-bit operations; adds word-size variants (addw, subw, etc.)
- **RV128I**: 128-bit base (draft specification; not widely implemented)
- **RV32E**: embedded variant of RV32I; 16 registers only; reduced area for microcontrollers

All base ISAs share the same instruction encoding format: 32-bit fixed-width instructions with a few standard formats (R-type, I-type, S-type, B-type, U-type, J-type).

### Standard Extensions

RISC-V uses a letter-based naming convention for extensions:

| Extension | Name | Description |
|---|---|---|
| M | Multiplication | Integer multiply/divide (mul, mulh, div, rem) |
| A | Atomic | Atomic memory operations (lr/sc, AMO instructions) |
| F | Single-precision FP | IEEE 754 single-precision floating-point |
| D | Double-precision FP | IEEE 754 double-precision floating-point |
| C | Compressed | 16-bit compressed instructions (reduced code size by ~25%) |
| V | Vector | Scalable vector extension (variable-length vectors) |
| B | Bit manipulation | Bit counting, rotation, permutation, extract/deposit |
| H | Hypervisor | Hardware virtualization support |
| Zicsr | CSR instructions | Control/status register access |
| Zifencei | Fence.I | Instruction fetch fence for self-modifying code |

**G = IMAFD**: the "general-purpose" combination. A typical application processor implements RV64GC (RV64I + M + A + F + D + C).

### Vector Extension (V)

The RISC-V Vector extension is particularly noteworthy:

- **Scalable vector length**: software does not assume a specific vector width; VLEN is implementation-defined (128-65536 bits)
- **Vector registers**: 32 vector registers (v0-v31)
- **VL/VTYPE**: dynamic vector length and element type configuration
- **Masked operations**: v0 used as mask register
- **Advantage**: same binary runs on implementations with different VLEN; future-proof
- **Use case**: DSP, ML inference, cryptography, multimedia

## Privilege Levels

### Privilege Hierarchy

RISC-V defines up to four privilege levels:

| Level | Name | Abbreviation | Purpose |
|---|---|---|---|
| 3 | Machine | M-mode | Firmware, hardware abstraction, most privileged |
| 2 | Hypervisor | HS-mode | Virtual machine monitor (with H extension) |
| 1 | Supervisor | S-mode | OS kernel |
| 0 | User | U-mode | Applications, least privileged |

**Minimal implementation**: M-mode only (bare-metal embedded)
**Standard embedded**: M + U modes (basic protection)
**Full OS**: M + S + U modes (Linux-capable)
**Virtualization**: M + HS + VS + VU modes (hypervisor + guest OS + guest user)

### Machine Mode (M-mode)

M-mode is the highest privilege level and always present:

- Full access to all hardware resources and CSRs
- Handles interrupts and exceptions before delegating to lower levels
- Implements platform-specific initialization (SBI - Supervisor Binary Interface)
- Firmware (OpenSBI, BBL) runs in M-mode
- Trap delegation: medeleg/mideleg CSRs delegate specific exceptions/interrupts to S-mode

### Supervisor Mode (S-mode)

S-mode provides OS-level privilege:

- Virtual memory management via page tables (Sv32, Sv39, Sv48, Sv57)
- Interrupt handling for delegated interrupts
- Timer management via SBI calls to M-mode
- Linux and other OSes run in S-mode

### Page Table Formats

- **Sv32**: 2-level page table, 32-bit virtual address, 34-bit physical address (RV32)
- **Sv39**: 3-level page table, 39-bit VA (512 GB), 56-bit PA (RV64, most common)
- **Sv48**: 4-level page table, 48-bit VA (256 TB)
- **Sv57**: 5-level page table, 57-bit VA (128 PB)

## Custom Instructions

### Extension Mechanism

RISC-V reserves opcode space specifically for custom extensions:

- **custom-0**: opcode 0001011 (available for custom use)
- **custom-1**: opcode 0101011
- **custom-2**: opcode 1011011
- **custom-3**: opcode 1111011

These opcodes will never be used by standard extensions, guaranteeing no conflicts.

### Designing Custom Extensions

Steps for adding a custom instruction:

1. **Define the instruction**: specify encoding, operands, and semantics
2. **Modify the decoder**: add decoding logic in the processor pipeline
3. **Implement execution unit**: add the functional unit for the custom operation
4. **Toolchain support**: modify GCC/LLVM to emit the instruction (or use inline assembly)
5. **Verification**: extend the ISA test suite with custom instruction tests

### Common Custom Extension Use Cases

- **AI/ML accelerators**: matrix multiply, activation function, quantization instructions
- **Cryptography**: AES round, SHA compression, Galois field operations (some now in standard Zkn/Zks extensions)
- **Signal processing**: complex multiply, saturating arithmetic, bit-reverse
- **Networking**: checksum computation, packet parsing, hash functions
- **Domain-specific accelerators**: FPGA-style reconfigurable units accessible via custom instructions

### RISC-V Crypto Extensions

Standardized crypto extensions reduce the need for fully custom implementations:

- **Zbkb/Zbkc/Zbkx**: bit manipulation for crypto (byte reverse, carry-less multiply, crossbar permute)
- **Zknd/Zkne**: AES encrypt/decrypt round instructions (32-bit and 64-bit variants)
- **Zknh**: SHA-256 and SHA-512 compression instructions
- **Zks**: ShangMi (SM3, SM4) crypto algorithms
- **Scalar crypto**: single-instruction AES round achieves competitive throughput without dedicated accelerator

## RISC-V Core Implementations

### Open-Source Cores

- **Rocket**: 5-stage in-order, RV64GC, parameterizable; from UC Berkeley/SiFive
- **BOOM (Berkeley Out-of-Order Machine)**: superscalar OOO, RV64GC; research-focused
- **CVA6 (Ariane)**: 6-stage in-order, RV64GC, Linux-capable; from OpenHW Group
- **Ibex (formerly Zero-riscy)**: 2-stage in-order, RV32IMC; microcontroller-class; from lowRISC
- **VexRiscv**: FPGA-optimized, parameterizable, RV32IM; written in SpinalHDL
- **SERV**: world's smallest RISC-V core; bit-serial implementation; minimal area

### Commercial Cores

- **SiFive**: U-series (application), S-series (automotive/embedded), E-series (microcontroller), X-series (vector/AI); industry's largest RISC-V IP portfolio
- **Andes**: A-series (application), N-series (embedded), D-series (DSP); strong in Asia
- **Codasip**: configurable cores with Codasip Studio; custom extension design flow
- **Ventana/Rivos**: high-performance datacenter RISC-V cores
- **Tenstorrent**: acquired by Jim Keller; RISC-V based AI/HPC processors

## Verification

### ISA Compliance Testing

- **riscv-tests**: official ISA test suite covering base instructions and extensions
- **RISCOF (RISC-V Compatibility Framework)**: reference model comparison testing
- **Spike**: RISC-V functional ISA simulator (golden reference)
- **SAIL model**: formal specification of RISC-V ISA in SAIL language

### Verification Approaches

- **Constrained random**: generate random instruction streams with coverage targets
- **Formal verification**: prove pipeline correctness against ISA specification
- **Co-simulation**: run RTL alongside Spike/SAIL; compare architectural state after each instruction
- **Compliance suite**: official tests for standard extension compliance
- **Performance verification**: benchmarks (CoreMark, SPEC, MLPerf) for microarchitecture validation

### Common Verification Challenges

- **Privilege transitions**: trap handling, delegation, and return across M/S/U modes
- **Virtual memory**: TLB miss handling, page fault, access permission violations
- **Atomic operations**: LR/SC reservation logic, AMO ordering in multi-core
- **Interrupt timing**: interrupt delivery during multi-cycle instructions, pipeline interactions
- **CSR side effects**: read/write ordering of CSRs that affect pipeline state

## Ecosystem and Software

### Software Stack

- **Toolchain**: GCC and LLVM fully support RISC-V (RV32/RV64, all standard extensions)
- **Linux**: mainline Linux kernel supports RISC-V since 5.0; full distribution support (Fedora, Ubuntu, Debian)
- **RTOS**: FreeRTOS, Zephyr, NuttX, RT-Thread all support RISC-V
- **Firmware**: OpenSBI (M-mode runtime), U-Boot (bootloader), EDK2/UEFI (server boot)
- **Debug**: OpenOCD + GDB with RISC-V Debug Specification (0.13.2, 1.0)

### Debug Specification

The RISC-V Debug Specification defines:

- **Debug Module (DM)**: hardware block accessed via JTAG; controls halt, step, breakpoints
- **Trigger Module**: hardware breakpoints and watchpoints (instruction address, data address, data value)
- **Program Buffer**: small code buffer for executing arbitrary instructions during debug halt
- **Abstract Commands**: register access and memory access during halt
- **Trace**: Efficient Trace (E-Trace) specification for instruction trace with compression

### RISC-V International

- **Ratification process**: extensions go through task group development, public review, and ratification
- **Profiles**: RVA (Application), RVM (Microcontroller) define mandatory extensions for software compatibility
- **RVA22/RVA23**: application processor profiles mandating specific extensions for Linux ecosystem compatibility

RISC-V's open nature, modular architecture, and growing ecosystem make it increasingly viable across the full spectrum of computing, from tiny IoT sensors to warehouse-scale computing. Its extensibility through custom instructions gives SoC designers the ability to differentiate without forking the base ISA.
