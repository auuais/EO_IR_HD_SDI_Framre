set project_root [file normalize "E:/Xylinx/EO_IR_HDSDI_LineBuffer_FRAMESIZE"]
set project_file [file join $project_root "EO_IR_HDSDI_LineBuffer_FRAMESIZE.xpr"]

open_project $project_file
source [file join $project_root scripts update_project.tcl]

reset_run synth_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1

set synth_status [get_property STATUS [get_runs synth_1]]
puts "SYNTH_STATUS=$synth_status"

if {$synth_status ne "synth_design Complete!"} {
    puts "SYNTH_FAILED"
    exit 1
}

open_run synth_1 -name synth_1
report_utilization -file [file join $project_root "synth_utilization.rpt"] -hierarchical -hierarchical_depth 4
report_timing_summary -file [file join $project_root "synth_timing_summary.rpt"]
puts "SYNTH_COMPLETE"
exit 0
