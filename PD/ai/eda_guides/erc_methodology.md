# ERC Methodology: Electrical Rule Checking for Design Integrity

## Overview

Electrical Rule Checking (ERC) verifies that a design meets electrical connectivity and safety rules that go beyond geometric DRC. While DRC ensures shapes are correctly drawn, ERC ensures the circuit is electrically sound: no floating gates, proper well connections, valid ESD paths, and correct power connectivity. ERC catches design errors that could cause functional failure, reliability degradation, or silicon damage.

## Floating Gate Detection

A floating gate is a transistor gate that has no driving connection, leaving it at an undefined voltage. Floating gates cause unpredictable circuit behavior, excessive leakage (gate may bias the transistor into a partially-on state), and reliability concerns (charge accumulation on the floating node).

### How Floating Gates Occur

- **Missing connections**: A signal route intended to reach a cell input was never completed (open net in routing).
- **Unconnected tie-off pins**: Standard cells with unused inputs that should be tied to VDD or VSS but are left floating.
- **ECO errors**: During ECO, a net is deleted but the driven gate is not reconnected.
- **Hierarchical boundary errors**: A port at a hierarchical boundary is not connected on one side.

### Detection Methodology

ERC tools trace connectivity from every transistor gate terminal to identify whether it has a driving source. Gates connected only to other gates (with no diffusion connection anywhere on the net) are flagged as floating.

```
# Calibre ERC example rule:
FLOATING GATE CHECK
NET GATE_ONLY {
    GATE_NET NOT CONNECTED TO DIFFUSION OR SUPPLY
}
```

### Fixing Floating Gates

1. **Route the missing connection**: If the gate should be connected to a signal, complete the routing.
2. **Tie to supply**: If the input is intentionally unused, connect it to VDD (for PMOS-off) or VSS (for NMOS-off) using tie-high/tie-low cells.
3. **Insert tie cells**: Place dedicated tie-high or tie-low cells near the floating gate and route the connection.

In modern P&R flows, unused input tie-off is typically handled automatically during placement/legalization, but ECO operations can inadvertently create new floating gates.

## Well Connectivity

Proper well connectivity is essential for preventing latch-up and ensuring correct transistor operation. Every N-well and P-well region must be connected to the appropriate supply voltage.

### Requirements

- **N-well**: Must be connected to VDD through N+ tap (substrate contact). N-well biases PMOS transistors correctly and prevents the parasitic PNP from turning on.
- **P-well (P-substrate)**: Must be connected to VSS through P+ tap. P-substrate biases NMOS transistors and prevents the parasitic NPN from turning on.

### Well Tap Rules

Foundries specify maximum distance between any point in a well and the nearest well tap. Typical rules:

- Maximum tap-to-tap spacing: 15-30um (varies by node and foundry).
- Every row of standard cells must have tap cells at regular intervals.
- Macros must have internal well taps or be surrounded by tap cells.

### ERC Well Connectivity Checks

- **Unconnected well**: A well region with no tap connection to supply.
- **Well resistance**: The resistance from any point in the well to the nearest tap exceeds the limit.
- **Well continuity**: A well region that should be continuous is broken by an obstacle.

```tcl
# In P&R tools:
# Synopsys ICC2/FC:
report_tap_cell_check

# Cadence Innovus:
verifyEndCap -reportOnly
```

### Fixing Well Connectivity Issues

- Insert additional tap cells (well ties) in areas that violate the maximum distance rule.
- Ensure tap cells are placed in every standard cell row, typically every 20-25um.
- For macro boundaries, add a ring of tap cells around the macro.
- Some flows use continuous tap cell rows (end-cap with tap functionality) at the edges of placement rows.

## Antenna Checks (Electrical)

While antenna rules are often categorized under DRC, the electrical aspects of antenna checking fall under ERC. The ERC antenna check verifies that the charge accumulated during manufacturing on metal connected to gates does not exceed the damage threshold.

ERC antenna checks differ from DRC antenna checks in that they consider the electrical characteristics:
- Gate oxide area and thickness.
- Diode protection effectiveness.
- Cumulative charge across all layers.

See the dedicated antenna_effect.md document for detailed antenna discussion.

## ESD Path Verification

Electrostatic Discharge (ESD) protection requires specific discharge paths from every I/O pad to the supply rails. ERC verifies that these paths exist and meet resistance requirements.

### ESD Protection Requirements

Every I/O pad must have:
1. **Primary ESD clamp**: A large protection device (diode or SCR) between the pad and each supply rail. The clamp must handle the ESD event current (typically 1-4A for 2kV HBM).
2. **Discharge path**: Low-resistance path from the primary clamp to the power/ground bus. The path resistance must be below a threshold (typically <1 ohm for VDD, <0.5 ohm for VSS).
3. **Power clamp**: Between VDD and VSS near each I/O pad group to provide a cross-domain discharge path.
4. **CDM protection**: Internal gates connected to I/O pads need local clamps or adequate resistance to limit CDM-induced voltage.

### ERC ESD Checks

- **Missing clamp**: An I/O pad has no ESD clamp to VDD or VSS.
- **Path resistance**: The resistance from I/O pad to supply rail exceeds the limit.
- **Missing power clamp**: No VDD-to-VSS clamp in the I/O pad group.
- **Cross-domain ESD**: Signals crossing power domains without ESD protection at the domain boundary.

### ESD Path Verification in Practice

ESD verification requires specialized tools (Calibre PERC, Synopsys IC Validator, Cadence Pegasus). These tools trace the layout connectivity from each I/O pad, identify ESD devices, compute path resistance, and flag violations.

```
# Calibre PERC ESD check example:
PERC ESD CHECK
  FROM PAD_NET
  TO SUPPLY VDD VSS
  MAX_RESISTANCE 1.0
  REQUIRE CLAMP_DEVICE
END CHECK
```

## Power Connectivity

ERC verifies that all cells and macros have proper power and ground connections.

### Checks Performed

- **Unconnected VDD/VSS pins**: Standard cells or macros with power/ground pins not connected to the power grid.
- **Multiple supply connection**: A cell connected to the wrong supply domain (e.g., a 0.85V cell connected to 1.2V supply).
- **Supply voltage mismatch**: Cells placed in a voltage area but connected to a different domain's supply.
- **Power grid continuity**: The VDD/VSS grid is continuous from the pad/bump to every cell.
- **Voltage level correctness**: For multi-voltage designs, each domain receives the correct voltage.

### Common Power Connectivity Issues

1. **Cells at block boundaries**: Cells placed at the edge of a voltage area may have pins that extend into another domain. The P&R tool must ensure correct power connection.
2. **Macro power pins**: Large macros may have multiple VDD/VSS pins on different metal layers. All pins must be connected to the power grid.
3. **Switchable domain isolation**: In power-gated domains, the virtual VDD rail must be isolated from the always-on VDD rail except through the power switch.
4. **Decap cells**: Decoupling capacitor cells must be connected to the correct supply pair.

## ERC Flow Integration

### When to Run ERC

- **Post-placement**: Check well connectivity (tap cell adequacy) and basic power connectivity.
- **Post-routing**: Full ERC including floating gate checks, ESD path verification, and power connectivity.
- **Post-ECO**: Any changes to connectivity require ERC re-verification.
- **Signoff**: Final ERC with the foundry rule deck.

### ERC Tool Ecosystem

| Tool | Vendor | Specialty |
|---|---|---|
| Calibre PERC | Siemens | ESD, latch-up, ERC |
| Calibre ERC | Siemens | General ERC |
| IC Validator ERC | Synopsys | Integrated with ICC2/FC |
| Pegasus ERC | Cadence | Integrated with Innovus |

### Report Interpretation

ERC reports typically categorize violations by severity:
- **Error**: Must be fixed before tapeout (floating gate, missing ESD clamp).
- **Warning**: Should be investigated (marginal well tap spacing, high-resistance ESD path).
- **Info**: Informational (matched ESD devices, verified power domains).

## Best Practices

1. Run well connectivity checks after placement and fix tap cell issues before routing.
2. Verify ESD protection paths early in the I/O ring design phase.
3. Include ERC in the automated signoff flow alongside DRC and LVS.
4. Maintain an ERC waiver list for known benign warnings (e.g., intentionally floating gates in test structures).
5. For multi-voltage designs, run power domain connectivity checks after UPF application.
6. Review floating gate reports carefully; even a single floating gate can cause a silicon failure.

ERC is often underappreciated compared to DRC and LVS, but it catches an important class of errors that geometric and connectivity checks alone cannot detect. A disciplined ERC methodology is part of every successful tapeout.
