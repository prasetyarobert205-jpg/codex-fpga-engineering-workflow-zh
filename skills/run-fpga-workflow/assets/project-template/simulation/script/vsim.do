onerror {quit -force -code 1}
set script_dir [file dirname [file normalize [info script]]]
set setting_file [file join $script_dir setting.txt]
if {![file isfile $setting_file]} {
    puts stderr "SCRIPT_PATH_FAIL: setting.txt is missing"
    quit -force -code 1
}
source $setting_file
puts stderr "TOOL_ENV_FAIL: configure the confirmed vendor export, library mapping, compile, load and run commands in vsim.do"
quit -force -code 1
