vlib modelsim_lib/work
vlib modelsim_lib/msim

vlib modelsim_lib/msim/xil_defaultlib

vmap xil_defaultlib modelsim_lib/msim/xil_defaultlib

vlog -work xil_defaultlib -64 -incr \
"../../../../A3.srcs/sources_1/ip/rom_28x2500/sim/rom_28x2500.v" \


vlog -work xil_defaultlib \
"glbl.v"

