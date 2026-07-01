set project_root [file normalize "E:/Xylinx/EO_IR_HDSDI_LineBuffer_FRAMESIZE"]
set project_file [file join $project_root "EO_IR_HDSDI_LineBuffer_FRAMESIZE.xpr"]

if {[catch {current_project}]} {
    open_project $project_file
}

set src_files [list \
    [file join $project_root src KintexTop_0cam_ch1_0108.v] \
    [file join $project_root src Kintex_top_1cam_ch1_1202.v] \
    [file join $project_root src Kintex_top_2cam_ch1_1202.v] \
    [file join $project_root src Kintex_top_3cam_ch1_1202.v] \
    [file join $project_root src Kintex_top_4cam_ch1_1202.v] \
    [file join $project_root src Kintex_top_5cam_ch1_1202.v] \
    [file join $project_root src LineBufferStackModules.v] \
    [file join $project_root src KintexTop_EO_IR_PanoramaStack_BRAM.v] \
    [file join $project_root src EOStackModules.v] \
]

foreach f $src_files {
    if {![llength [get_files -quiet $f]]} {
        add_files -norecurse -fileset sources_1 $f
    }
}

set xdc_file [file join $project_root constraints KintexTop_EO_IR_PanoramaStack_BRAM.xdc]
if {![llength [get_files -quiet $xdc_file]]} {
    add_files -norecurse -fileset constrs_1 $xdc_file
}

set_property top KintexTop_EO_IR_Combined_HD_SDI [get_filesets sources_1]
update_compile_order -fileset sources_1
catch {save_project}
