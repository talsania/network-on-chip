#*****************************************************************************************
# Vivado (TM) v2025.2 (64-bit)
#
# create_project.tcl: Network-on-Chip Vivado Project Generation Script
#
# This file contains the Vivado Tcl commands for re-creating the project to the state
# when this script was generated. In order to re-create the project, please source this
# file in the Vivado Tcl Shell.
#*****************************************************************************************

# Resolve the repository root based on where this script is located
set script_path [file normalize [info script]]
set repo_root   [file dirname $script_path]
set proj_name   "network_on_chip"

# Create the Vivado Project (Using the Nexys A7 FPGA)
# The -force flag will overwrite the project folder if it already exists
create_project $proj_name $repo_root/$proj_name -part xc7a100tcsg324-1 -force

# Add Design Sources (RTL & FPGA Wrappers)
add_files -fileset sources_1 [list \
    $repo_root/rtl/input_buffer_fifo.v \
    $repo_root/rtl/network_interface.v \
    $repo_root/rtl/uart/uart_rx.v \
    $repo_root/rtl/uart/uart_tx.v \
    $repo_root/rtl/xy_router.v \
    $repo_root/rtl/crossbar_switch.sv \
    $repo_root/rtl/router_5port.sv \
    $repo_root/rtl/switch_allocator.sv \
    $repo_root/rtl/top_noc_fabric.sv \
    $repo_root/rtl/uart/uart_cmd_parser.sv \
    $repo_root/rtl/uart/uart_resp_formatter.sv \
    $repo_root/fpga/top/top_fpga_uart_stream_noc.sv \
    $repo_root/fpga/image_64x64_rgb.mem \
]

set_property file_type SystemVerilog [get_files -filter {NAME =~ "*.sv"}]

# Set the top module for synthesis/implementation
set_property top top_fpga_uart_stream_noc [get_filesets sources_1]

# Add Constraints
add_files -fileset constrs_1 $repo_root/fpga/constraints/constraints.xdc

# Add Simulation Sources (Testbenches)
add_files -fileset sim_1 [list \
    $repo_root/rtl/sim/tb_input_buffer_fifo.v \
    $repo_root/rtl/sim/tb_uart_bridge.sv \
    $repo_root/rtl/sim/tb_router_5port.sv \
    $repo_root/rtl/sim/tb_xy_router.v \
    $repo_root/rtl/sim/tb_uart_standalone.v \
    $repo_root/rtl/sim/tb_top_noc.sv \
    $repo_root/rtl/sim/tb_crossbar_switch.sv \
    $repo_root/rtl/sim/tb_switch_allocator.sv \
    $repo_root/rtl/sim/tb_network_interface.v \
]

# Set the top module for simulation
set_property top tb_mesh_fabric_noc [get_filesets sim_1]

# Update the compile order to recognize the new hierarchy
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts "\n========================================================="
puts "     SUCCESS: Project '$proj_name' created successfully!"
puts "     All files are linked directly from: $repo_root"
puts "=========================================================\n"