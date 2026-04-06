## ============================================================================
## constraints.xdc for 4-Core Mesh NoC + UART Bridge
## Target FPGA: Digilent Nexys A7-100T (Artix-7)
## ============================================================================

## 1. Clock Signal (100 MHz)
set_property -dict { PACKAGE_PIN E3    IOSTANDARD LVCMOS33 } [get_ports { clk }];
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports { clk }];
## 2. Reset Button (Active-Low)
# Nexys A7 uses dedicated CPU RESET button (Pin C12) which is natively active-low.
set_property -dict { PACKAGE_PIN C12    IOSTANDARD LVCMOS33 } [get_ports { rst_n }];
## 3. USB-UART Interface
set_property -dict { PACKAGE_PIN C4    IOSTANDARD LVCMOS33 } [get_ports { uart_rxd }]; # uart_txd_in  (PC -> FPGA)
set_property -dict { PACKAGE_PIN D4    IOSTANDARD LVCMOS33 } [get_ports { uart_txd }]; # uart_rxd_out (FPGA -> PC)
