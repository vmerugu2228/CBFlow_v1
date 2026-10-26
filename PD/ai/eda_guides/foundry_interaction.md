# Foundry Interaction

## Overview

The foundry (fabrication facility) is the ultimate arbiter of what can and cannot be manufactured. Every physical design decision is constrained by the foundry's process design rules, and every tapeout must pass the foundry's acceptance checks. Effective foundry interaction requires understanding PDK contents, managing design rule updates, navigating the waiver process, and planning for test chips and multi-project wafers. This guide covers the practical aspects of working with foundries from a PD engineer's perspective.

## PDK Contents

The Process Design Kit (PDK) is the foundry's deliverable to the design house. It contains everything needed to design and verify a chip in the target technology.

### Technology Files

- **Tech LEF**: Defines metal layers, via definitions, routing rules, minimum widths, spacing rules, and antenna limits for PnR tools
- **ITF/QRC tech file**: Interconnect technology file for parasitic extraction (layer thicknesses, dielectric constants, resistivity)
- **nxtgrd/QRC models**: Detailed RC extraction models used by tools like StarRC, QRC, or Quantus
- **Process corner definitions**: Typical, fast, slow, and skewed corners for interconnect extraction

### Design Rule Files

- **DRC deck**: Runset for physical verification tools (Calibre, ICV, Pegasus) encoding all manufacturing design rules
- **LVS deck**: Runset for layout vs. schematic verification, including device recognition rules
- **ERC deck**: Electrical rule checks (antenna, latch-up, ESD)
- **DFM deck**: Optional recommended rules beyond minimum requirements (for yield enhancement)
- **Density rules**: Metal density requirements per layer (minimum and maximum fill density)

### Standard Cell Libraries

- **Liberty files (.lib)**: Timing, power, and noise characterization for every cell, across all PVT corners
- **LEF files**: Physical abstractions for PnR tools
- **GDS files**: Full layout for physical verification and tapeout merge
- **CDL files**: Circuit netlists for LVS
- **Verilog models**: Functional and timing simulation models
- **Library variants**: Multi-Vt libraries (HVT, SVT, LVT, ULVT) for power-performance optimization

### I/O and Special Cells

- **I/O pad library**: Pad cells for chip-level I/O (with ESD protection)
- **ESD structures**: Clamp cells, diodes, and other ESD protection devices
- **Filler cells**: Non-functional cells to fill gaps and satisfy density rules
- **Well tap cells**: Substrate and N-well connection cells for latch-up prevention
- **Decoupling capacitor cells**: Standard-cell-sized decap for local power supply filtering
- **End cap cells**: Boundary cells placed at row ends for manufacturing continuity

## DRM and DRC Deck Updates

### Design Rule Manual (DRM)

The DRM is the foundry's comprehensive document specifying all manufacturing rules. PD engineers should be familiar with key sections:

- **Metal rules**: Minimum width, spacing, enclosure for each metal layer
- **Via rules**: Via size, enclosure, spacing, and stacking rules
- **Density rules**: Minimum and maximum metal density per layer
- **Antenna rules**: Ratio limits for gate-to-metal area
- **Special rules**: Restricted routing directions, coloring rules (for multi-patterning), and latch-up rules

### Deck Updates

Foundries periodically release updated DRC/LVS decks. These updates can:

- Fix bugs in existing rules
- Add new rules discovered during manufacturing ramp
- Tighten existing rules for yield improvement
- Add recommended rules for advanced yield optimization

### Managing Deck Updates

1. **Track deck versions**: Maintain a log of which deck version is used for each design milestone
2. **Qualification runs**: When a new deck arrives, run it on existing designs to identify new violations
3. **Impact assessment**: Quantify how many new violations the update introduces and estimate the fix effort
4. **Schedule coordination**: Coordinate deck updates with the project schedule; avoid mid-stream deck changes unless critical bugs are being fixed
5. **Communication**: Ensure all PD engineers are using the same deck version; version mismatches cause confusion

### Tech File Updates

Tech LEF and extraction model updates follow the same discipline:

- New extraction models can change parasitic values, shifting timing by 1-5%
- Always rerun STA after extraction model updates to detect timing shifts
- Log the tech file version alongside every run in the QoR database

## Waiver Process

### What is a Waiver?

A waiver is formal foundry approval to ship a design with a known DRC violation that the foundry has determined will not cause a manufacturing failure. Waivers are a last resort, not a design methodology.

### When to Request Waivers

- The violation is caused by an IP block that cannot be modified (e.g., third-party hard macro)
- The violation is at a block boundary where the fix would require fundamental redesign
- The violation is in a non-critical area and the risk of manufacturing failure is assessed as low
- The rule is overly conservative for the specific geometry context

### Waiver Request Process

1. **Document the violation**: Location (coordinates), rule ID, violation details, screenshot of the violation in the layout viewer
2. **Explain why it cannot be fixed**: Technical justification, not just schedule pressure
3. **Provide context**: What is nearby (other metal, vias, devices), switching frequency, voltage
4. **Submit to foundry**: Through the foundry's formal waiver submission portal (usually a ticketing system)
5. **Wait for response**: Foundries typically respond within 1-2 weeks; expedited requests may be possible for critical tapeouts
6. **Document the decision**: Log the waiver approval (or rejection) with the waiver ID for tapeout records

### Waiver Best Practices

- **Minimize waivers**: A design with hundreds of waivers indicates a methodology problem, not edge cases
- **Request early**: Do not wait until tapeout week to discover you need waivers; start the process as soon as violations are identified
- **Group similar violations**: If you have 50 instances of the same violation type (e.g., an IP macro boundary issue), submit them as a single grouped waiver request
- **Keep records**: Waiver approvals must be archived as part of the tapeout package

## Test Chips

### Purpose

Test chips are small designs fabricated to validate the process, characterize IP, or test specific design techniques before committing to a full product tapeout.

### Types of Test Chips

- **Process characterization**: Ring oscillators, transistor arrays, capacitor structures to validate process parameters
- **IP validation**: First silicon for new hard IP (SRAM, SerDes, PLL) before integration into the product
- **Design methodology validation**: Test structures that exercise specific design rules, routing configurations, or power grid strategies
- **Yield enhancement**: Structures designed to measure yield at different density/spacing points

### Test Chip Design Considerations

- **Small die size**: Test chips should be as small as possible to minimize cost and fit on MPW shuttles
- **Probe-friendly**: Pad placement should accommodate wafer probing; use large pads and standard pitch
- **Comprehensive**: Include enough structures to answer all open questions; second chances are expensive
- **Documentation**: Thorough documentation of test structures and expected measurements

## MPW (Multi-Project Wafer)

### Concept

An MPW shuttle shares a single reticle among multiple designs from different teams or companies. Each design occupies a small area of the reticle, dramatically reducing fabrication cost.

- **Cost**: 10-100x cheaper than a dedicated mask set
- **Turnaround**: Typically 8-16 weeks from tapeout to die delivery
- **Die count**: Limited (typically 20-100 dies per design, depending on die size and wafer count)

### MPW Planning

1. **Reserve a slot**: Foundries and shuttle services (e.g., MOSIS, Europractice, CMP) run shuttles on fixed schedules; reserve early
2. **Meet the deadline**: MPW deadlines are strict; missing the deadline means waiting for the next shuttle (often months later)
3. **Die size constraints**: The reticle is divided into a grid; your design must fit within the allocated area
4. **Scribe lane and seal ring**: The MPW service provides scribe lane and seal ring specifications; follow them exactly
5. **Pad frame**: Use the standard I/O pad frame specified by the shuttle service

### MPW Tapeout Checklist

- [ ] Design fits within the allocated die area
- [ ] Seal ring is included and meets the spec
- [ ] All DRC checks pass with the foundry-qualified deck
- [ ] LVS clean
- [ ] GDSII layer mapping matches the foundry's layer map
- [ ] Correct metal stack option selected
- [ ] Tapeout files submitted in the required format (GDSII, OASIS) by the deadline

## Tapeout Interaction

### Pre-Tapeout Checklist

Before submitting GDSII to the foundry:

1. **DRC clean**: Zero violations (or all violations covered by approved waivers)
2. **LVS clean**: Layout matches schematic exactly
3. **ERC clean**: All electrical checks pass (antenna, latch-up, ESD)
4. **Density checks pass**: Metal and poly density within required ranges (after fill insertion)
5. **Chip ID and alignment marks**: Foundry-required identification structures are present
6. **Seal ring**: Complete and correctly placed around the die boundary
7. **GDSII integrity**: File is not corrupted; passes the foundry's format checker

### Foundry Submission

- Submit through the foundry's secure file transfer system
- Include the tapeout cover sheet with design specifications (process, metal stack, die size, special instructions)
- Receive confirmation of file receipt and successful format checks
- Respond promptly to any queries from the foundry about the submitted data

### Post-Tapeout

- **Mask review**: Some foundries provide a mask data review step where they flag potential issues
- **Wafer fabrication**: Typically 8-14 weeks for advanced nodes
- **Wafer acceptance test**: Foundry runs basic parametric tests on completed wafers
- **Die delivery**: Wafers or singulated dies shipped to the design house or assembly facility

## Communication Best Practices

- **Use the foundry's ticketing system**: Avoid informal email for technical questions; formal tickets create a record and ensure proper routing
- **Be specific**: When reporting issues, include rule IDs, coordinates, tool versions, and deck versions
- **Respect NDA**: All foundry information (PDK contents, design rules, process parameters) is confidential
- **Attend foundry seminars**: Most foundries offer annual technology symposiums and design workshops; attend them for early insight into process updates and new features
- **Build relationships**: A good working relationship with foundry application engineers pays dividends when you need expedited waiver approvals or early access to new PDK releases
