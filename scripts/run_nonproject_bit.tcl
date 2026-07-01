set project_root [file normalize "E:/Xylinx/EO_IR_HDSDI_BRAM-URAM_FRAMESIZE"]
set build_dir [file join $project_root "batch_build"]
file mkdir $build_dir
cd $build_dir

set part_name "xcku15p-ffve1517-2-i"
set top_name "KintexTop_EO_IR_Combined_HD_SDI"

read_verilog [list \
    [file join $project_root src KintexTop_0cam_ch1_0108.v] \
    [file join $project_root src Kintex_top_1cam_ch1_1202.v] \
    [file join $project_root src Kintex_top_2cam_ch1_1202.v] \
    [file join $project_root src Kintex_top_3cam_ch1_1202.v] \
    [file join $project_root src Kintex_top_4cam_ch1_1202.v] \
    [file join $project_root src Kintex_top_5cam_ch1_1202.v] \
    [file join $project_root src EOStackModules.v] \
    [file join $project_root src KintexTop_EO_IR_PanoramaStack_BRAM.v] \
]

read_xdc [file join $project_root constraints KintexTop_EO_IR_PanoramaStack_BRAM.xdc]

synth_design -top $top_name -part $part_name
write_checkpoint -force [file join $build_dir "post_synth.dcp"]
report_utilization -file [file join $build_dir "post_synth_utilization.rpt"] -hierarchical -hierarchical_depth 4

opt_design
write_checkpoint -force [file join $build_dir "post_opt.dcp"]

place_design
phys_opt_design
write_checkpoint -force [file join $build_dir "post_place.dcp"]

route_design
write_checkpoint -force [file join $build_dir "post_route.dcp"]

report_drc -file [file join $build_dir "post_route_drc.rpt"]
report_route_status -file [file join $build_dir "post_route_status.rpt"]
report_utilization -file [file join $build_dir "post_route_utilization.rpt"] -hierarchical -hierarchical_depth 4
report_timing_summary -file [file join $build_dir "post_route_timing_summary.rpt"] -warn_on_violation

write_bitstream -force [file join $build_dir "${top_name}.bit"]
puts "BITSTREAM_COMPLETE=[file join $build_dir ${top_name}.bit]"
exit 0
