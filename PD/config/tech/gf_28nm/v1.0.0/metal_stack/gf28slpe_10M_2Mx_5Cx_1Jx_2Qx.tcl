#!/usr/bin/env tclsh
# GF 28SLP-E — 10M Metal Stack (2Mx + 5Cx + 1Jx + 2Qx)
# 2 thick (M9-M10), 5 intermediate (M4-M8), 1 junction (M3), 2 thin (M1-M2)

set tech(metal_stack_label) "10M"
set tech(metal_count) 10
set tech(metal_layers) {M1 M2 M3 M4 M5 M6 M7 M8 M9 M10}

set tech(metal,M1,direction)  "H"
set tech(metal,M1,pitch)      "0.140"
set tech(metal,M1,min_width)  "0.060"
set tech(metal,M1,type)       "Qx"

set tech(metal,M2,direction)  "V"
set tech(metal,M2,pitch)      "0.140"
set tech(metal,M2,min_width)  "0.060"
set tech(metal,M2,type)       "Qx"

set tech(metal,M3,direction)  "H"
set tech(metal,M3,pitch)      "0.140"
set tech(metal,M3,min_width)  "0.060"
set tech(metal,M3,type)       "Jx"

set tech(metal,M4,direction)  "V"
set tech(metal,M4,pitch)      "0.280"
set tech(metal,M4,min_width)  "0.100"
set tech(metal,M4,type)       "Cx"

set tech(metal,M5,direction)  "H"
set tech(metal,M5,pitch)      "0.280"
set tech(metal,M5,min_width)  "0.100"
set tech(metal,M5,type)       "Cx"

set tech(metal,M6,direction)  "V"
set tech(metal,M6,pitch)      "0.280"
set tech(metal,M6,min_width)  "0.100"
set tech(metal,M6,type)       "Cx"

set tech(metal,M7,direction)  "H"
set tech(metal,M7,pitch)      "0.280"
set tech(metal,M7,min_width)  "0.100"
set tech(metal,M7,type)       "Cx"

set tech(metal,M8,direction)  "V"
set tech(metal,M8,pitch)      "0.280"
set tech(metal,M8,min_width)  "0.100"
set tech(metal,M8,type)       "Cx"

set tech(metal,M9,direction)  "H"
set tech(metal,M9,pitch)      "0.800"
set tech(metal,M9,min_width)  "0.400"
set tech(metal,M9,type)       "Mx"

set tech(metal,M10,direction) "V"
set tech(metal,M10,pitch)     "0.800"
set tech(metal,M10,min_width) "0.400"
set tech(metal,M10,type)      "Mx"

# Power strap layers
set tech(pg_strap_layers) "M9 M10"
set tech(pg_strap_width,M9)  "1.600"
set tech(pg_strap_width,M10) "1.600"

# Via stack
set tech(via_stack) {VIA1 VIA2 VIA3 VIA4 VIA5 VIA6 VIA7 VIA8 VIA9}
