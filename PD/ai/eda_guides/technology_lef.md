# Technology LEF: Layer Definitions, Cell Abstractions, and Physical Rules

## What Is LEF?

Library Exchange Format (LEF) is an ASCII format that describes the physical aspects of a technology and its cell library. LEF serves as the interface between the foundry/library provider and the place-and-route tools, giving the tools everything they need to place cells, route wires, and check design rules without requiring access to the full GDS layout.

LEF has two distinct components:
- **Technology LEF:** Describes the metal layer stack, via definitions, routing rules, and design rules
- **Cell LEF (Macro LEF):** Describes the physical abstraction of each cell -- pin shapes, obstructions, and cell dimensions

## Technology LEF

The technology LEF file defines the manufacturing technology's physical characteristics.

### Layer Definitions

Each metal and via layer is defined with its properties:

```lef
LAYER M1
  TYPE ROUTING ;
  DIRECTION HORIZONTAL ;
  PITCH 0.048 ;
  WIDTH 0.024 ;
  SPACING 0.024 ;
  RESISTANCE RPERSQ 12.5 ;       # Sheet resistance (ohms/sq)
  CAPACITANCE CPERSQDIST 0.00015 ; # Capacitance per unit area
  THICKNESS 0.036 ;
  HEIGHT 0.100 ;                  # Distance from substrate
  MINWIDTH 0.024 ;
  MAXWIDTH 2.0 ;
  AREA 0.0014 ;                   # Minimum enclosed area
END M1

LAYER VIA12
  TYPE CUT ;
  SPACING 0.040 ;
  WIDTH 0.032 ;
END VIA12

LAYER M2
  TYPE ROUTING ;
  DIRECTION VERTICAL ;
  PITCH 0.048 ;
  WIDTH 0.024 ;
  SPACING 0.024 ;
  ...
END M2
```

### Layer Types

- **ROUTING:** Metal layers used for signal and power routing (M1, M2, ..., M12+)
- **CUT:** Via layers connecting adjacent metal layers (VIA12, VIA23, ...)
- **MASTERSLICE:** Non-routing layers (poly, active) used in cell internals
- **OVERLAP:** Used for cell overlap checking
- **IMPLANT:** Implant layers for well/substrate contacts

### Routing Direction

Each metal layer has a preferred routing direction:
- **HORIZONTAL:** Wires primarily run left-right (typically odd metal layers: M1, M3, M5)
- **VERTICAL:** Wires primarily run up-down (typically even metal layers: M2, M4, M6)

This alternating pattern ensures that adjacent layers are orthogonal, minimizing coupling between layers and simplifying the routing algorithm.

### Spacing Rules

Design rules for minimum spacing between wires:

```lef
LAYER M3
  SPACING 0.040 ;                          # Minimum spacing
  SPACINGTABLE
    PARALLELRUNLENGTH 0.0 0.5 1.0 2.0
    WIDTH 0.040 0.040 0.050 0.060 0.070    # Wider wires need more space
    WIDTH 0.080 0.050 0.060 0.070 0.080
    WIDTH 0.120 0.060 0.070 0.080 0.100 ;
END M3
```

Spacing tables capture the rule that wider wires and longer parallel runs require greater spacing. This is critical for preventing shorts and managing electromigration.

### Via Definitions

Vias are defined with their geometry (metal overlap, cut dimensions, spacing):

```lef
VIA VIA12_1x1 DEFAULT
  LAYER M1 ;
    RECT -0.020 -0.020 0.020 0.020 ;    # M1 enclosure
  LAYER VIA12 ;
    RECT -0.016 -0.016 0.016 0.016 ;    # Via cut
  LAYER M2 ;
    RECT -0.020 -0.020 0.020 0.020 ;    # M2 enclosure
END VIA12_1x1

# Multi-cut via for lower resistance
VIA VIA12_2x2 DEFAULT
  LAYER M1 ;
    RECT -0.060 -0.060 0.060 0.060 ;
  LAYER VIA12 ;
    RECT -0.016 -0.046 0.016 -0.014 ;   # Via cut 1
    RECT -0.016  0.014 0.016  0.046 ;   # Via cut 2
    RECT -0.046 -0.016 -0.014 0.016 ;   # Via cut 3
    RECT  0.014 -0.016  0.046 0.016 ;   # Via cut 4
  LAYER M2 ;
    RECT -0.060 -0.060 0.060 0.060 ;
END VIA12_2x2
```

### Via Rules (VIARULE GENERATE)

Via rules define how to automatically generate via arrays of arbitrary size:

```lef
VIARULE VIA12_ARRAY GENERATE
  LAYER M1 ;
    ENCLOSURE 0.005 0.005 ;
    DIRECTION HORIZONTAL ;
  LAYER VIA12 ;
    RECT -0.016 -0.016 0.016 0.016 ;
    SPACING 0.060 BY 0.060 ;
  LAYER M2 ;
    ENCLOSURE 0.005 0.005 ;
    DIRECTION VERTICAL ;
END VIA12_ARRAY
```

### Site Definitions

Sites define the basic unit of placement. Standard cells are placed on site rows:

```lef
SITE CoreSite
  SYMMETRY Y ;
  CLASS CORE ;
  SIZE 0.048 BY 0.270 ;   # Width x Height (CPP x Cell Height)
END CoreSite
```

The site width (typically one CPP) defines the horizontal placement grid. The site height defines the cell row height.

### Track Definitions

Tracks define the routing grid for each metal layer:

```lef
TRACKS X 0.024 DO 10000 STEP 0.048 LAYER M1 ;
TRACKS Y 0.024 DO 5000 STEP 0.048 LAYER M2 ;
```

This specifies that M1 tracks start at x=0.024 and repeat every 0.048um (one pitch). Wires are routed on these grid lines.

## Cell LEF (Macro LEF)

Cell LEF provides the physical abstraction of each standard cell.

### Cell Definition

```lef
MACRO BUFX4_SVT
  CLASS CORE ;
  ORIGIN 0.0 0.0 ;
  SIZE 0.192 BY 0.270 ;             # Width x Height
  SYMMETRY X Y ;                     # Can be flipped in X and Y
  SITE CoreSite ;

  PIN A
    DIRECTION INPUT ;
    USE SIGNAL ;
    PORT
      LAYER M1 ;
        RECT 0.020 0.100 0.060 0.170 ;   # Pin shape on M1
    END
  END A

  PIN Y
    DIRECTION OUTPUT ;
    USE SIGNAL ;
    PORT
      LAYER M1 ;
        RECT 0.132 0.100 0.172 0.170 ;
    END
  END Y

  PIN VDD
    DIRECTION INOUT ;
    USE POWER ;
    PORT
      LAYER M1 ;
        RECT 0.0 0.255 0.192 0.270 ;     # Power rail at top
    END
  END VDD

  PIN VSS
    DIRECTION INOUT ;
    USE GROUND ;
    PORT
      LAYER M1 ;
        RECT 0.0 0.0 0.192 0.015 ;       # Ground rail at bottom
    END
  END VSS

  OBS                                      # Obstructions
    LAYER M1 ;
      RECT 0.060 0.015 0.132 0.255 ;     # Internal M1 routing blocked
  END
END BUFX4_SVT
```

### Pin Shapes

Pins define where the router can connect to the cell. Pin shapes must be on routing layers (typically M1 and M2) and must be accessible by the router (not blocked by obstructions).

**Pin accessibility** is a critical concern at advanced nodes where M1 pin shapes are small and may be accessible from only one direction.

### Obstructions (OBS)

Obstructions mark regions within the cell that the router cannot use. These are areas occupied by internal cell routing:

```lef
OBS
  LAYER M1 ;
    RECT 0.040 0.020 0.150 0.250 ;   # M1 used internally
  LAYER M2 ;
    RECT 0.080 0.050 0.110 0.220 ;   # M2 used internally
END
```

The router must avoid placing wires in obstruction regions.

### Cell Symmetry

```lef
SYMMETRY X Y ;    # Cell can be mirrored in X (left-right) and Y (top-bottom)
SYMMETRY X Y R90; # Also supports 90-degree rotation (for non-standard orientations)
```

Y-symmetry is essential for row-based placement where alternating rows are flipped vertically to share power rails.

### Cell Classes

- **CORE:** Standard logic cells placed in rows
- **CORE WELLTAP:** Well tap cells
- **CORE SPACER:** Filler cells
- **CORE ANTENNACELL:** Antenna fix cells
- **CORE TIEHIGH / TIELOW:** Tie cells
- **BLOCK:** Hard macros (memories, IP blocks)
- **PAD:** IO pad cells
- **ENDCAP:** Row termination cells

## Advanced LEF Features

### Minimum Cut Rules

Specify minimum number of via cuts for reliability:

```lef
LAYER VIA12
  MINIMUMCUT 2 WIDTH 0.080 ;   # Wires wider than 0.080 need 2+ cuts
  MINIMUMCUT 4 WIDTH 0.200 ;   # Wires wider than 0.200 need 4+ cuts
END VIA12
```

### Antenna Rules

Metal antenna rules prevent charge accumulation during manufacturing that can damage thin gate oxides:

```lef
LAYER M3
  ANTENNAMODEL OXIDE1 ;
  ANTENNAAREARATIO 400 ;          # Max metal area / gate area ratio
  ANTENNADIFFAREARATIO PWL ( (0 400) (0.0125 500) ) ;
END M3
```

### Density Rules

Minimum and maximum metal density requirements for CMP uniformity:

```lef
LAYER M2
  MINIMUMDENSITY 20 ;    # At least 20% metal coverage
  MAXIMUMDENSITY 80 ;    # At most 80% metal coverage
  DENSITYCHECKWINDOW 100 100 ;  # Check in 100x100 um windows
  DENSITYCHECKSTEP 50 50 ;      # Window step size
END M2
```

## Practical Recommendations

1. **Read the technology LEF carefully.** It contains the physical rules that govern routing. Misunderstanding a spacing rule or via enclosure can lead to DRC violations that are expensive to fix.

2. **Verify cell LEF pin accessibility.** At advanced nodes (7nm, 5nm), limited pin shapes can cause routability issues. Run pin access analysis early in the flow.

3. **Check obstruction coverage.** Incomplete obstructions can lead to the router placing wires inside cells, causing shorts in the GDS. Verify that all internal routing is properly blocked.

4. **Match LEF to the PDK version.** Technology LEF and cell LEF must come from the same PDK release. Mismatched versions cause subtle DRC violations.

5. **Use multi-cut vias when possible.** Multi-cut vias have lower resistance and better reliability (redundancy). Configure the router to prefer multi-cut vias.

6. **Understand the metal stack for your design.** Not all metal layers are created equal. Lower metals have finer pitch (signal routing), upper metals have coarser pitch (power, clock, long-distance signals).

LEF is the physical contract between the technology/library and the implementation tools. Thorough understanding of LEF contents enables efficient physical design and helps debug routing and DRC issues.
