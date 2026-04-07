onbreak {quit -f}
onerror {quit -f}

vsim -t 1ps -lib xil_defaultlib ram_16x256_opt

do {wave.do}

view wave
view structure
view signals

do {ram_16x256.udo}

run -all

quit -force
