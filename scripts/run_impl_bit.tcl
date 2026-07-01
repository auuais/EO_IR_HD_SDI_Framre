set project_root [file normalize "E:/Xylinx/EO_IR_HDSDI_LineBuffer_FRAMESIZE"]
set project_file [file join $project_root "EO_IR_HDSDI_LineBuffer_FRAMESIZE.xpr"]

open_project $project_file
source [file join $project_root scripts update_project.tcl]

reset_run synth_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1
set synth_status [get_property STATUS [get_runs synth_1]]
if {$synth_status ne "synth_design Complete!"} {
    puts "SYNTH_FAILED: $synth_status"
    exit 1
}

reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1

set impl_status [get_property STATUS [get_runs impl_1]]
puts "IMPL_STATUS=$impl_status"

if {$impl_status ne "write_bitstream Complete!"} {
    puts "IMPL_OR_BITSTREAM_FAILED"
    exit 1
}

open_run impl_1
report_utilization -file [file join $project_root "impl_utilization.rpt"] -hierarchical -hierarchical_depth 4
report_timing_summary -file [file join $project_root "impl_timing_summary.rpt"]
puts "BITSTREAM_COMPLETE"
exit 0
