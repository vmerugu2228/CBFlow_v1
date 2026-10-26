#!/usr/bin/env tclsh
###############################################################################
# cts_debug.tcl — FC Clock Tree Quality Analyzer
#
# Analyzes clock tree QoR: per-domain skew, insertion delay, latency,
# buffer/ICG counts, outlier sinks, non-clock cells, reconvergence issues.
# Works in two modes:
#   1. Report mode: parses report_clock_qor.rpt (plain tclsh)
#   2. Live mode: queries FC directly via get_clocks, report_clock_qor, etc.
#
# Usage (report mode — plain tclsh):
#   tclsh cts_debug.tcl -report report_clock_qor.rpt -outliers 10
#   tclsh cts_debug.tcl -report report_clock_qor.rpt -outliers 20 -out results.txt
#
# Usage (inside FC):
#   source cts_debug.tcl
#   cts_debug -live -outliers 10
#   cts_debug -live -outliers 5 -clock_cells {CLKBUF CLKINV CLKGT} -out cts.txt
#
# Features:
#   -report FILE       Parse report_clock_qor.rpt file
#   -live              Query FC session directly
#   -outliers N        Show top N worst skew/latency sinks (default 10)
#   -clock_cells LIST  Allowed clock cell ref names (for non-clock detection)
#   -out FILE          Write output to file instead of stdout
#
# No fallbacks. Errors if report not found or data missing.
###############################################################################

namespace eval ::cts_debug {
    variable version "1.0.0"
}

# Detect whether running inside FC
proc ::cts_debug::in_fc {} {
    return [expr {[info commands "get_clocks"] ne ""}]
}

# Output helper — write to file or stdout
proc ::cts_debug::output {lines args} {
    set out_file ""
    foreach {key val} $args {
        if {$key eq "-out"} { set out_file $val }
    }
    set text [join $lines "\n"]
    if {$out_file ne ""} {
        set fh [open $out_file w]
        puts $fh $text
        close $fh
        puts "INFO: Output written to $out_file"
    } else {
        puts $text
    }
}

# Parse report_clock_qor.rpt — extract per-clock-domain data and sink details
proc ::cts_debug::parse_report {rpt_file} {
    if {![file exists $rpt_file]} {
        error "ERROR: Clock QoR report not found: $rpt_file"
    }
    set fh [open $rpt_file r]
    set content [read $fh]
    close $fh

    set domains [dict create]
    set sinks [list]
    set current_clock ""

    foreach line [split $content "\n"] {
        set trimmed [string trim $line]

        # Detect clock domain header: "Clock: clk_core" or "Clock Name: clk_core"
        if {[regexp {^Clock(?:\s+Name)?:\s+(\S+)} $trimmed -> clk]} {
            set current_clock $clk
            if {![dict exists $domains $clk]} {
                dict set domains $clk skew 0.0
                dict set domains $clk insertion_delay 0.0
                dict set domains $clk latency 0.0
                dict set domains $clk buffer_count 0
                dict set domains $clk icg_count 0
                dict set domains $clk sink_count 0
            }
            continue
        }

        if {$current_clock eq ""} continue

        # Extract skew
        if {[regexp -nocase {(?:Global\s+)?Skew\s*[:(]\s*([-\d.]+)} $trimmed -> val]} {
            dict set domains $current_clock skew $val
            continue
        }

        # Extract insertion delay
        if {[regexp -nocase {Insertion\s+Delay\s*[:(]\s*([-\d.]+)} $trimmed -> val]} {
            dict set domains $current_clock insertion_delay $val
            continue
        }

        # Extract latency (source or max)
        if {[regexp -nocase {(?:Max\s+)?Latency\s*[:(]\s*([-\d.]+)} $trimmed -> val]} {
            dict set domains $current_clock latency $val
            continue
        }

        # Extract buffer count
        if {[regexp -nocase {(?:Clock\s+)?Buffer(?:s|_count)?\s*[:(]\s*(\d+)} $trimmed -> val]} {
            dict set domains $current_clock buffer_count $val
            continue
        }

        # Extract ICG count
        if {[regexp -nocase {(?:ICG|Gating\s+Cell|Clock\s+Gate)(?:s|_count)?\s*[:(]\s*(\d+)} $trimmed -> val]} {
            dict set domains $current_clock icg_count $val
            continue
        }

        # Extract sink count
        if {[regexp -nocase {Sink(?:s|_count)?\s*[:(]\s*(\d+)} $trimmed -> val]} {
            dict set domains $current_clock sink_count $val
            continue
        }

        # Extract individual sink lines: sink_name  skew  latency  insertion  ref_name
        if {[regexp {^\s*(\S+/\S+)\s+([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\s+(\S+)} $trimmed -> sink skw lat ins ref]} {
            lappend sinks [list clock $current_clock sink $sink skew $skw latency $lat insertion $ins ref $ref]
            continue
        }

        # Alternate sink format: just sink and latency
        if {[regexp {^\s*(\S+/\S+)\s+([-\d.]+)\s+([-\d.]+)} $trimmed -> sink lat skw]} {
            lappend sinks [list clock $current_clock sink $sink skew $skw latency $lat insertion 0.0 ref ""]
        }
    }

    if {[dict size $domains] == 0} {
        error "ERROR: No clock domains found in $rpt_file. Verify report format."
    }
    return [list domains $domains sinks $sinks]
}

# Get clock tree data from live FC session
proc ::cts_debug::get_fc_data {} {
    if {![::cts_debug::in_fc]} {
        error "ERROR: Not running inside FC. Use -report flag for report mode."
    }

    set domains [dict create]
    set sinks [list]

    set clk_collection [get_clocks -quiet *]
    if {[sizeof_collection $clk_collection] == 0} {
        error "ERROR: No clocks found in current design."
    }

    foreach_in_collection clk $clk_collection {
        set clk_name [get_attribute $clk name]
        dict set domains $clk_name skew 0.0
        dict set domains $clk_name insertion_delay 0.0
        dict set domains $clk_name latency 0.0
        dict set domains $clk_name buffer_count 0
        dict set domains $clk_name icg_count 0
        dict set domains $clk_name sink_count 0

        # Get clock network objects
        set net_cells [get_clock_network_objects -type cell -clock $clk_name]
        set buf_count 0
        set icg_count 0
        foreach_in_collection c $net_cells {
            set ref [get_attribute $c ref_name]
            if {[regexp -nocase {icg|clock_gate|CKLNQ|CKLHQ} $ref]} {
                incr icg_count
            } else {
                incr buf_count
            }
        }
        dict set domains $clk_name buffer_count $buf_count
        dict set domains $clk_name icg_count $icg_count

        # Get sinks and their timing
        set sink_pins [get_clock_network_objects -type sink -clock $clk_name]
        set sink_count [sizeof_collection $sink_pins]
        dict set domains $clk_name sink_count $sink_count

        set max_lat 0.0
        set min_lat 999999.0
        foreach_in_collection sp $sink_pins {
            set pin_name [get_attribute $sp full_name]
            set lat [get_attribute $sp clock_latency]
            set ins [get_attribute $sp clock_insertion_delay]
            set cell_obj [get_cells -quiet [lindex [split $pin_name "/"] 0]]
            set ref ""
            if {[sizeof_collection $cell_obj] > 0} {
                set ref [get_attribute $cell_obj ref_name]
            }
            if {$lat > $max_lat} { set max_lat $lat }
            if {$lat < $min_lat} { set min_lat $lat }
            lappend sinks [list clock $clk_name sink $pin_name \
                skew 0.0 latency $lat insertion $ins ref $ref]
        }

        set skew [expr {$max_lat - $min_lat}]
        dict set domains $clk_name skew [format "%.4f" $skew]
        dict set domains $clk_name latency [format "%.4f" $max_lat]
        dict set domains $clk_name insertion_delay [format "%.4f" [expr {($max_lat + $min_lat) / 2.0}]]

        # Update per-sink skew relative to mean
        set mean_lat [expr {($max_lat + $min_lat) / 2.0}]
        set updated_sinks [list]
        foreach s $sinks {
            array set sa $s
            if {$sa(clock) eq $clk_name} {
                set sa(skew) [format "%.4f" [expr {$sa(latency) - $mean_lat}]]
            }
            lappend updated_sinks [array get sa]
            array unset sa
        }
        set sinks $updated_sinks
    }

    return [list domains $domains sinks $sinks]
}

# Helper to access list-based dict
proc ::cts_debug::sget {sink key} {
    foreach {k v} $sink {
        if {$k eq $key} { return $v }
    }
    return ""
}

# Display per-domain summary table
proc ::cts_debug::domain_summary {data args} {
    set domains [dict get $data domains]
    set lines [list]
    lappend lines "===== Clock Domain Summary ====="
    lappend lines [format "%-30s %10s %14s %10s %10s %10s %10s" \
        "Clock Domain" "Skew (ns)" "Insertion (ns)" "Lat (ns)" "Buffers" "ICGs" "Sinks"]
    lappend lines [string repeat "-" 100]

    dict for {clk info} $domains {
        lappend lines [format "%-30s %10s %14s %10s %10s %10s %10s" \
            $clk \
            [dict get $info skew] \
            [dict get $info insertion_delay] \
            [dict get $info latency] \
            [dict get $info buffer_count] \
            [dict get $info icg_count] \
            [dict get $info sink_count]]
    }
    lappend lines ""
    output $lines {*}$args
}

# Show top N outlier sinks by worst skew and latency
proc ::cts_debug::outlier_sinks {data n args} {
    set sinks [dict get $data sinks]
    if {[llength $sinks] == 0} {
        puts "INFO: No individual sink data available for outlier analysis."
        return
    }

    # Sort by absolute skew descending
    set sorted_skew [lsort -decreasing -real -command {apply {{a b} {
        set sa [expr {abs([::cts_debug::sget $a skew])}]
        set sb [expr {abs([::cts_debug::sget $b skew])}]
        return [expr {$sa > $sb ? 1 : ($sa < $sb ? -1 : 0)}]
    }}} $sinks]

    # Sort by latency descending
    set sorted_lat [lsort -decreasing -real -command {apply {{a b} {
        set la [::cts_debug::sget $a latency]
        set lb [::cts_debug::sget $b latency]
        return [expr {$la > $lb ? 1 : ($la < $lb ? -1 : 0)}]
    }}} $sinks]

    set lines [list]
    lappend lines "===== Top $n Outlier Sinks by Skew ====="
    lappend lines [format "%-6s %-15s %-50s %10s %10s %s" \
        "Rank" "Clock" "Sink" "Skew (ns)" "Lat (ns)" "Ref"]
    lappend lines [string repeat "-" 110]
    set rank 0
    foreach s $sorted_skew {
        incr rank
        if {$rank > $n} break
        lappend lines [format "%-6d %-15s %-50s %10s %10s %s" \
            $rank [sget $s clock] [sget $s sink] [sget $s skew] \
            [sget $s latency] [sget $s ref]]
    }

    lappend lines ""
    lappend lines "===== Top $n Outlier Sinks by Latency ====="
    lappend lines [format "%-6s %-15s %-50s %10s %10s %s" \
        "Rank" "Clock" "Sink" "Lat (ns)" "Skew (ns)" "Ref"]
    lappend lines [string repeat "-" 110]
    set rank 0
    foreach s $sorted_lat {
        incr rank
        if {$rank > $n} break
        lappend lines [format "%-6d %-15s %-50s %10s %10s %s" \
            $rank [sget $s clock] [sget $s sink] [sget $s latency] \
            [sget $s skew] [sget $s ref]]
    }
    lappend lines ""
    output $lines {*}$args
}

# Detect non-clock cells in the clock tree
proc ::cts_debug::detect_non_clock_cells {data allowed_cells args} {
    set sinks [dict get $data sinks]
    if {[llength $allowed_cells] == 0} {
        puts "INFO: No -clock_cells list provided. Skipping non-clock cell detection."
        return
    }

    set violations [list]
    foreach s $sinks {
        set ref [sget $s ref]
        if {$ref eq ""} continue
        set is_allowed 0
        foreach pattern $allowed_cells {
            if {[string match $pattern $ref]} {
                set is_allowed 1
                break
            }
        }
        if {!$is_allowed} {
            lappend violations $s
        }
    }

    set lines [list]
    lappend lines "===== Non-Clock Cells in Clock Tree ====="
    if {[llength $violations] == 0} {
        lappend lines "PASS: All cells in clock tree match allowed clock cell list."
    } else {
        lappend lines "WARNING: [llength $violations] cells found NOT in allowed clock cell list."
        lappend lines [format "%-15s %-50s %-20s %10s" "Clock" "Instance" "Ref Name" "Lat (ns)"]
        lappend lines [string repeat "-" 100]
        foreach v $violations {
            lappend lines [format "%-15s %-50s %-20s %10s" \
                [sget $v clock] [sget $v sink] [sget $v ref] [sget $v latency]]
        }
    }
    lappend lines ""
    output $lines {*}$args
}

# Detect clock reconvergence — sinks driven by multiple clock domains
proc ::cts_debug::detect_reconvergence {data args} {
    set sinks [dict get $data sinks]
    set sink_clocks [dict create]

    foreach s $sinks {
        set sink_name [sget $s sink]
        # Normalize to cell level (strip pin)
        set cell [lindex [split $sink_name "/"] 0]
        if {$cell eq ""} continue
        set clk [sget $s clock]
        if {[dict exists $sink_clocks $cell]} {
            set existing [dict get $sink_clocks $cell]
            if {[lsearch -exact $existing $clk] == -1} {
                lappend existing $clk
                dict set sink_clocks $cell $existing
            }
        } else {
            dict set sink_clocks $cell [list $clk]
        }
    }

    set reconvergent [list]
    dict for {cell clocks} $sink_clocks {
        if {[llength $clocks] > 1} {
            lappend reconvergent [list $cell $clocks]
        }
    }

    set lines [list]
    lappend lines "===== Clock Reconvergence Analysis ====="
    if {[llength $reconvergent] == 0} {
        lappend lines "PASS: No clock reconvergence detected."
    } else {
        lappend lines "WARNING: [llength $reconvergent] cells driven by multiple clock domains."
        lappend lines [format "%-50s  %s" "Cell" "Clock Domains"]
        lappend lines [string repeat "-" 90]
        foreach entry $reconvergent {
            lassign $entry cell clocks
            lappend lines [format "%-50s  %s" $cell [join $clocks ", "]]
        }
    }
    lappend lines ""
    output $lines {*}$args
}

# Main dispatcher
proc ::cts_debug::run {args} {
    set report_file ""
    set live_mode 0
    set outlier_n 10
    set clock_cells [list]
    set out_file ""

    for {set i 0} {$i < [llength $args]} {incr i} {
        set arg [lindex $args $i]
        switch -- $arg {
            -report {
                incr i
                set report_file [lindex $args $i]
            }
            -live {
                set live_mode 1
            }
            -outliers {
                incr i
                set outlier_n [lindex $args $i]
                if {![string is integer -strict $outlier_n] || $outlier_n <= 0} {
                    error "ERROR: -outliers requires a positive integer argument."
                }
            }
            -clock_cells {
                incr i
                set clock_cells [lindex $args $i]
            }
            -out {
                incr i
                set out_file [lindex $args $i]
            }
            default {
                error "ERROR: Unknown argument: $arg\nUsage: cts_debug \[-report file\] \[-live\] \[-outliers N\] \[-clock_cells list\] \[-out file\]"
            }
        }
    }

    if {$report_file eq "" && !$live_mode} {
        error "ERROR: Specify -report <file> or -live mode."
    }
    if {$report_file ne "" && $live_mode} {
        error "ERROR: Cannot use both -report and -live. Choose one."
    }

    set out_args [list]
    if {$out_file ne ""} { lappend out_args -out $out_file }

    # Get data
    if {$report_file ne ""} {
        set data [::cts_debug::parse_report $report_file]
    } else {
        set data [::cts_debug::get_fc_data]
    }

    # Run all analyses
    ::cts_debug::domain_summary $data {*}$out_args
    ::cts_debug::outlier_sinks $data $outlier_n {*}$out_args
    ::cts_debug::detect_non_clock_cells $data $clock_cells {*}$out_args
    ::cts_debug::detect_reconvergence $data {*}$out_args
}

# FC convenience wrapper
proc cts_debug {args} {
    ::cts_debug::run {*}$args
}

# CLI entry point
if {[info exists ::argv] && [llength $::argv] > 0} {
    ::cts_debug::run {*}$::argv
}
