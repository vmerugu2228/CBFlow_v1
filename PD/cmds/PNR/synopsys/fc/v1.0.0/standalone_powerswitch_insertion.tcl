# FC-RM Y-2026.03 power switch insertion — interactive standalone
# Source from fc_shell after the block is current and UPF is loaded.

if {[catch {current_block} _cb] || $_cb eq ""} {
    return -code error "No current_block — open lib + load_upf first."
}

file mkdir ./reports/psw

set_app_options -name design.upf.enable_implementation -value true

set_lib_cell_purpose -include power_switch     [get_lib_cells "PSW_*"]
set_lib_cell_purpose -include always_on_buffer [get_lib_cells "BUFFD*_AON"]

set_app_options -name design.power_switch_name_prefix              -value "psw_"
set_app_options -name design.power_switch_enable_buf_name_prefix   -value "psw_en_buf_"
set_app_options -name design.power_switch_ack_buf_name_prefix      -value "psw_ack_buf_"

set_app_options -name place.coarse.power_switch_set_to_set_distance  -value 100
set_app_options -name place.coarse.power_switch_chain_distance       -value 50
set_app_options -name place.coarse.power_switch_array_x_distance     -value 50
set_app_options -name place.coarse.power_switch_array_y_distance     -value 50
set_app_options -name design.power_switch_max_voltage_drop           -value 0.05

set_app_options -name place.coarse.power_switch_enable_buf_lib_cells -value "BUFFD*_AON"
set_app_options -name place.coarse.power_switch_ack_buf_lib_cells    -value "BUFFD*_AON"

set_app_options -name place.coarse.enable_power_switch     -value true
set_app_options -name opt.power_switch.enable_insertion    -value true
set_app_options -name place.coarse.power_switch_lib_cells  -value "PSW_*"

commit_upf

redirect -file ./reports/psw/check_mv_design.pre_psw.rpt { check_mv_design -verbose }

foreach_in_collection _pd [get_power_domains -filter "primary == false"] {
    set _pd_name [get_attribute $_pd full_name]
    if {[sizeof_collection [get_power_switches -of $_pd -quiet]] == 0} { continue }
    create_power_switches -power_domain $_pd_name
}

connect_supply_net

redirect -file ./reports/psw/check_mv_design.post_psw.rpt { check_mv_design -verbose }
redirect -file ./reports/psw/report_power_switches.rpt    { catch { report_power_switches } }
redirect -file ./reports/psw/report_power_domain.rpt      { catch { report_power_domain } }
redirect -file ./reports/psw/report_mv_design.rpt         { catch { report_mv_design } }

report_power_switches
report_power_domain
