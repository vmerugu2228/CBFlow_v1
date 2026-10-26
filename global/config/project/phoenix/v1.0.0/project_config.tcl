#!/usr/bin/env tclsh
# =============================================================================
# CBflow Project Configuration — phoenix
# GLOBAL layer (cross-discipline: PD + DFT + DV all read this)
# Auto-split from legacy PD/config/project/phoenix/v1.0.0/phoenix_config.tcl
# =============================================================================

#!/usr/bin/env tclsh
# ============================================================================
# CBflow - Denali Project Configuration
# Description: Denali project-specific parameters
# ============================================================================

# Project identification
set project(name) "phoenix"

# Phase timeline for this project (project-specific — flow(phases) is deprecated).
set project(phases)          {P0 P1 P2 P3}
set project(current_phase)   "P0"
set project(version) "1.0"
set project(cbflow_release) "v1.0.0"   ;# CBflow release version for this project
set project(description) "Phoenix chip design project"
set project(owner) "Phoenix Design Team"
set project(contact) "phoenix@company.com"

# Project root directory for relative path resolution
set project(technology) "tsmc_5nm"
set project(vt_flavors) "svt lvt hvt"
set project(top_module) "phoenix_top"

# SDC Mode Definitions (used for file naming: <design_name>.<mode>.sdc)
set project(sdc_modes) {func scan test dft}
set project(default_sdc_mode) "func"

# Power & Ground Nets (consumed by init_design/PNR — top-level SoC-wide)
set project(power,vdd_net) "VDD"
set project(power,vss_net) "VSS"
set project(power,vdd_pin) "VDD"
set project(power,vss_pin) "VSS"

# Block-level specs (clock uncertainty, target frequency/power/area, reset
# ports, I/O voltage, power domains, design-size estimates) used to live
# here as `project(target,*)`, `project(estimated_*)`, `project(io,*)`,
# `project(reset,*)`, `project(power,domains|states|switches|isolation|
# retention)`. They were unread by any cmd handler and removed in the
# cleanup commit. Block-shaped specs belong in user_config or a per-block
# `<block_name>_floorplan.tcl`, not in this project-wide config.

# Test and verification
set project(dft,scan_chains) "8"
set project(dft,coverage_target) "98"
set project(dft,compression) "true"
set project(verification,formal) "true"
set project(verification,simulation) "true"

# Feature toggles
set project(tapeout_date) "2027-01-31"          ;# ISO date — drives "Weeks to tapeout" on dashboard

# ---------------------------------------------------------------------------
# LSF RESOURCE MANAGEMENT
# ---------------------------------------------------------------------------

set project(analog_blocks) "pll_block adc_block"
set project(design_hierarchy) {
    chip_top {
        description "Full chip top level (DL1)"
        level "DL1"
        parent ""
        children {cpu_complex memory_subsys io_subsys power_mgmt}
    }

    cpu_complex {
        description "CPU and cache subsystem (DL2)"
        level "DL2"
        parent "chip_top"
        children {cpu_core l1_cache l2_cache}
    }

    memory_subsys {
        description "Memory controller and interfaces (DL2)"
        level "DL2"
        parent "chip_top"
        children {ddr_ctrl mem_arbiter}
    }

    io_subsys {
        description "I/O controllers and peripherals (DL2)"
        level "DL2"
        parent "chip_top"
        children {pcie_ctrl gpio_ctrl uart_ctrl spi_ctrl}
    }

    power_mgmt {
        description "Power management unit (DL2)"
        level "DL2"
        parent "chip_top"
        children {power_ctrl clock_mgr reset_ctrl}
    }

    cpu_core {
        description "Main CPU processing core (DL3)"
        level "DL3"
        parent "cpu_complex"
        children {alu fetch_unit decode_unit}
    }

    l1_cache {
        description "Level 1 cache controller (DL3)"
        level "DL3"
        parent "cpu_complex"
        children {}
    }

    l2_cache {
        description "Level 2 cache controller (DL3)"
        level "DL3"
        parent "cpu_complex"
        children {}
    }

    ddr_ctrl {
        description "DDR memory controller (DL3)"
        level "DL3"
        parent "memory_subsys"
        children {}
    }

    mem_arbiter {
        description "Memory arbiter (DL3)"
        level "DL3"
        parent "memory_subsys"
        children {}
    }

    pcie_ctrl {
        description "PCIe controller (DL3)"
        level "DL3"
        parent "io_subsys"
        children {}
    }

    gpio_ctrl {
        description "GPIO controller (DL3)"
        level "DL3"
        parent "io_subsys"
        children {}
    }

    uart_ctrl {
        description "UART controller (DL3)"
        level "DL3"
        parent "io_subsys"
        children {}
    }

    spi_ctrl {
        description "SPI controller (DL3)"
        level "DL3"
        parent "io_subsys"
        children {}
    }

    power_ctrl {
        description "Power control unit (DL3)"
        level "DL3"
        parent "power_mgmt"
        children {}
    }

    clock_mgr {
        description "Clock manager (DL3)"
        level "DL3"
        parent "power_mgmt"
        children {}
    }

    reset_ctrl {
        description "Reset controller (DL3)"
        level "DL3"
        parent "power_mgmt"
        children {}
    }

    alu {
        description "Arithmetic Logic Unit (DL4)"
        level "DL4"
        parent "cpu_core"
        children {}
    }

    fetch_unit {
        description "Instruction fetch unit (DL4)"
        level "DL4"
        parent "cpu_core"
        children {}
    }

    decode_unit {
        description "Instruction decode unit (DL4)"
        level "DL4"
        parent "cpu_core"
        children {}
    }
}

# Default Cadence tools
set project(valid_design_names) [dict keys $project(design_hierarchy)]

# ─────────────────────────────────────────────────────────────────────────────
# Derived: project(block_list) — the DL2 subsystems of design_hierarchy.
# Consumed by FCFP/FP init_design_fc.tcl for hierarchical NDM loading.
# ─────────────────────────────────────────────────────────────────────────────
set _blk_list {}
dict for {_blk _spec} $project(design_hierarchy) {
    if {[dict exists $_spec level] && [dict get $_spec level] eq "DL2"} {
        lappend _blk_list $_blk
    }
}
set project(block_list) $_blk_list
unset _blk_list _blk _spec
