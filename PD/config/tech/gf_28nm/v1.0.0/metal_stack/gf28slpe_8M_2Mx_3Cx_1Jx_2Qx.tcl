#!/usr/bin/env tclsh
# GF 28SLP-E — 8M Metal Stack (2Mx + 3Cx + 1Jx + 2Qx)

set tech(metal_stack_label) "8M"
set tech(metal_count) 8
set tech(metal_layers) {M1 M2 M3 M4 M5 M6 M7 M8}

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
set tech(metal,M7,pitch)      "0.800"
set tech(metal,M7,min_width)  "0.400"
set tech(metal,M7,type)       "Mx"

set tech(metal,M8,direction)  "V"
set tech(metal,M8,pitch)      "0.800"
set tech(metal,M8,min_width)  "0.400"
set tech(metal,M8,type)       "Mx"

set tech(pg_strap_layers) "M7 M8"
set tech(pg_strap_width,M7)  "1.600"
set tech(pg_strap_width,M8)  "1.600"

set tech(via_stack) {VIA1 VIA2 VIA3 VIA4 VIA5 VIA6 VIA7}
