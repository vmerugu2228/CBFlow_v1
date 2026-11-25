#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow — scandef writer (OpenROAD)
#
# oss_write_scandef <file> <max_bits>
#   Standard DEF 5.8 scandef of the scan chains in the loaded design
#   (OpenROAD DFT execute_dft_plan, or a scandef read with read_def
#   -incremental): the SCANCHAINS section of write_def, with each chain's
#   element list oriented scan-in -> scan-out by the netlist connectivity.
#
#   execute_dft_plan stores its chains tail-first, and write_def then lists the
#   flop next to the scan-out right after `+ START PIN <scan_in>` — the reverse
#   of the netlist (a tool honouring ORDERED would shift the chain backwards).
#   Each chain is checked: the START pin's net must reach the first element's
#   scan-in pin; when it reaches the last element's instead, the list is
#   reversed; when it reaches neither, the scandef is refused.
#
# Sourced inside OpenROAD (no CBflow config needed) by the SYNTH dft_insert
# script; the PNR flow reads the result with read_def -incremental.
# ═══════════════════════════════════════════════════════════════════════════════

proc oss_write_scandef {file max_bits} {
    set _blk [ord::get_db_block]
    if {$_blk eq "NULL"} { error "oss_write_scandef: no design loaded" }
    if {![llength [[$_blk getDft] getScanChains]]} {
        error "oss_write_scandef: the design has no scan chains (execute_dft_plan / read_def of a scandef)"
    }
    set _tmp "$file.full.def"
    write_def $_tmp
    set _fh [open $_tmp]; set _t [read $_fh]; close $_fh
    file delete $_tmp
    if {![regexp {(?:^|\n)SCANCHAINS\s+\d+\s*;\s*\n(.*?)\nEND SCANCHAINS} $_t -> _sec]} {
        error "oss_write_scandef: write_def produced no SCANCHAINS section"
    }
    set _chains {}
    foreach _c [lrange [split [regsub -all -line {^-\s+} $_sec "\x01"] \x01] 1 end] {
        set _name [lindex [split [string trim $_c] \n] 0]
        set _start ""; set _stop ""; set _part ""; set _mode ORDERED; set _els {}
        foreach _l [split $_c \n] {
            set _l [string trim $_l]
            if {[regexp {^\+\s*START\s+PIN\s+(\S+)} $_l -> _start]} continue
            if {[regexp {^\+\s*STOP\s+PIN\s+(\S+)} $_l -> _stop]} continue
            if {[regexp {^\+\s*PARTITION\s+(\S+)} $_l -> _part]} continue
            if {[regexp {^\+\s*(ORDERED|FLOATING)} $_l -> _mode]} continue
            if {[regexp {^(\S+)\s+\(\s*IN\s+(\S+)\s*\)\s+\(\s*OUT\s+(\S+)\s*\)} $_l -> _i _in _out]} {
                lappend _els [list $_i $_in $_out]
            }
        }
        if {$_start eq "" || $_stop eq "" || ![llength $_els]} {
            error "oss_write_scandef: chain '$_name' — START PIN / STOP PIN / elements not found (only pin-terminated chains are supported)"
        }
        set _sn [[$_blk findBTerm $_start] getNet]
        set _first [lindex $_els 0]; set _last [lindex $_els end]
        set _fn [[[$_blk findInst [lindex $_first 0]] findITerm [lindex $_first 1]] getNet]
        set _ln [[[$_blk findInst [lindex $_last 0]] findITerm [lindex $_last 1]] getNet]
        if {$_fn ne "NULL" && $_fn eq $_sn} {
            # already scan-in first
        } elseif {$_ln ne "NULL" && $_ln eq $_sn} {
            set _els [lreverse $_els]
            puts "oss_write_scandef: chain $_name listed scan-out first by write_def — reversed to netlist order"
        } else {
            error "oss_write_scandef: chain '$_name' — START PIN $_start drives neither end of the element list"
        }
        lappend _chains [list $_name $_start $_stop [expr {$_part eq "" ? "default" : $_part}] $_mode $_els]
    }
    set _fh [open $file w]
    puts $_fh "# CBflow scandef — [$_blk getName] (scan-in -> scan-out order, netlist-checked)"
    puts $_fh "VERSION 5.8 ;\nNAMESCASESENSITIVE ON ;\nDIVIDERCHAR \"/\" ;\nBUSBITCHARS \"\[\]\" ;\nDESIGN [$_blk getName] ;\n"
    puts $_fh "SCANCHAINS [llength $_chains] ;"
    foreach _c $_chains {
        lassign $_c _name _start _stop _part _mode _els
        puts $_fh "- $_name\n  + PARTITION $_part MAXBITS $max_bits\n  + START PIN $_start\n  + $_mode"
        foreach _e $_els { puts $_fh "      [lindex $_e 0] ( IN [lindex $_e 1] ) ( OUT [lindex $_e 2] )" }
        puts $_fh "  + STOP PIN $_stop ;"
    }
    puts $_fh "END SCANCHAINS\n\nEND DESIGN"
    close $_fh
    return [llength $_chains]
}
