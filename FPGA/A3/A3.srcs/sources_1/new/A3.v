`timescale 1ns / 1ps
/////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date: 2025/07/30 22:25:41
// Design Name:
// Module Name: PART2
// Project Name:
// Target Devices:
// Tool Versions:
// Description: 顶层模块，集成SPI接收、频率ROM查找、DDS生成
//
// Dependencies:
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////


module A3(
        // 系统时钟和复位
        input  wire         sys_clk_in,        // 系统时钟
        input  wire         sys_rst_n,         // 系统复位，低有效

        //请求
        input  wire         dds1_req,          // 模式1请求：DDS1模式，低有效
        input  wire         ram_req,           // 模式2请求：RAM写入模式，低有效
        input  wire         dds2_freq_req,     // 模式3请求：DDS2频率控制模式，低有效
        input  wire         a2_en,             // A2模块使能信号，高有效

        // SPI接口信号
        input  wire         sck,               // SPI时钟
        input  wire         cs_n,              // SPI片选，低有效
        input  wire         mosi,              // SPI主设备输出，从设备输入
        output wire         miso,              // SPI主设备输入，从设备输出

        // DAC
        output reg          dac_clk,
        output reg          dac_wrt,
        output reg [13:0]   dac_data           // DAC数据输出

    );

    // 参数定义
    parameter FWORD_WIDTH_28 = 28;     // DDS1频率控制字位宽
    parameter FWORD_WIDTH_32 = 32;     // DDS2频率控制字位宽
    parameter ADDR_WIDTH_8 = 8;        // DDS1地址位宽
    parameter DATA_WIDTH = 32;

    // 内部信号定义
    wire [15:0]     spi_rx_data;         // SPI接收到的数据(16位)
    wire            spi_rx_valid;        // SPI接收数据有效信号
    wire            sys_clk_50M;         // 内部系统时钟50M
    wire            locked;              // PLL锁定信号
    wire            dac_clk_50M;         // 内部DAC时钟50M
    wire            dac_clk_125M;        // 内部DAC时钟125M

    // rx_ctrl相关信号
    // 模式1：DDS1模式 - 高频正弦波生成
    wire [11:0]     mode1_spi_to_freq_addr;        // 模式1 SPI数据到频率ROM地址
    wire            mode1_dds1_freq_valid;         // 模式1 DDS1频率更新有效信号
    wire [27:0]     mode1_freq_rom_data;           // 模式1 频率ROM输出的频率控制字
    wire [7:0]      mode1_dds1_sin_addr;           // 模式1 DDS1输出的正弦波地址
    wire [13:0]     mode1_sin_wave_data;           // 模式1 正弦波ROM输出数据

    // 模式2：RAM写入模式 - 波形数据存储
    wire            mode2_ram_write_en;            // 模式2 RAM写使能信号
    wire [7:0]      mode2_ram_write_addr;          // 模式2 RAM写地址
    wire [15:0]     mode2_ram_write_data;          // 模式2 RAM写入数据

    // 模式3：DDS2频率控制模式 - 可变频率波形生成
    wire [7:0]      mode3_spi_to_freq_addr;        // 模式3 SPI数据到频率ROM地址
    wire            mode3_dds2_freq_valid;         // 模式3 DDS2频率更新有效信号
    wire [31:0]     mode3_freq_control_word;       // 模式3 频率ROM输出的频率控制字
    wire [7:0]      mode3_dds2_wave_addr;          // 模式3 DDS2输出的波形地址
    wire [15:0]     mode3_ram_wave_data;           // 模式3 从RAM读取的波形数据

    // 模式状态记录寄存器
    reg [1:0]       last_active_mode;              // 记录最后激活的模式：00-无效，01-模式1，10-模式2，11-模式3

    // 模式状态记录逻辑
    always @(posedge sys_clk_50M or negedge sys_rst_n) begin
        if (sys_rst_n == 1'b0) begin
            last_active_mode <= 2'b00;  // 复位时无激活模式
        end
        else begin
            if (~dds1_req) begin
                last_active_mode <= 2'b01;  // 记录模式1激活
            end
            else if (~ram_req) begin
                last_active_mode <= 2'b10;  // 记录模式2激活
            end
            else if (~dds2_freq_req) begin
                last_active_mode <= 2'b11;  // 记录模式3激活
            end else
                last_active_mode <= last_active_mode;  
        end
    end

    assign dac_clk_50M = sys_clk_50M;

    // SPI模块例化
    SPI2 #(
        .BIT_NUM        (16),
        .BIT_CNT_WIDTH  (5),
        .BYTE_NUM       (256),
        .BYTE_NUM_WIDTH (8)
    ) spi2_inst (
        .sys_rst_n      (locked),
        .sys_clk        (sys_clk_50M),
        .sck            (sck),
        .cs_n           (cs_n),
        .mosi           (mosi),
        .miso           (miso),
        .rx_data_valid  (spi_rx_valid),
        .rx_data        (spi_rx_data)
    );

    // rx_ctrl模块例化 - 数据选择器
    rx_ctrl rx_ctrl_inst (
        .sys_clk           (sys_clk_50M),
        .sys_rst_n         (locked),
        .last_active_mode  (last_active_mode),
        .spi_rx_data       (spi_rx_data),
        .spi_rx_valid      (spi_rx_valid),
        // 模式1：DDS1接口
        .mode1_dds1_rom_addr     (mode1_spi_to_freq_addr),
        .mode1_dds1_valid        (mode1_dds1_freq_valid),
        // 模式2：RAM写入接口
        .wea               (mode2_ram_write_en),
        .addra             (mode2_ram_write_addr),
        .dina              (mode2_ram_write_data),
        // 模式3：频率控制接口
        .mode3_rom_addr          (mode3_spi_to_freq_addr),
        .mode3_dds_valid         (mode3_dds2_freq_valid)
    );

    // 模式1：高频率控制ROM模块例化（2500个频率点）   多的
    rom_28x2500 mode1_freq_rom_inst (
        .clka(sys_clk_50M),                           // input wire clka
        .addra(mode1_spi_to_freq_addr),    // input wire [11:0] addra 
        .douta(mode1_freq_rom_data)                   // output wire [27 : 0] douta
    );

    // 模式1：DDS1模块例化 (28位频率控制字，8位地址，125M时钟)
    DDS #(
        .FWORD_WIDTH (FWORD_WIDTH_28),    // 28位
        .ADDR_WIDTH  (ADDR_WIDTH_8),      // 8位
        .DAC_WIDTH   (14)
    ) mode1_dds1_inst (
        .sys_rst_n   (locked),
        .fword       (mode1_freq_rom_data),     // 从频率ROM读取的28位频率控制字
        .dds_valid   (mode1_dds1_freq_valid),         // 来自rx_ctrl的频率更新有效信号
        .rom_addr    (mode1_dds1_sin_addr),           // DDS1输出的正弦波地址
        .dac_clk_50M (dac_clk_125M)                   // 使用125M时钟
    );

    // 模式1：正弦波ROM模块例化（使用125M时钟生成高精度正弦波）
    rom_sin #(
                .DATA_WIDTH (14),     // 14位数据
                .ADDR_WIDTH (8),      // 8位地址
                .ROM_DEPTH  (256)     // 256深度
            ) mode1_sin_rom_inst (
                .sys_clk    (dac_clk_125M),               // 使用125M时钟
                .sys_rst_n  (locked),
                .rom_addr   (mode1_dds1_sin_addr),        // 使用DDS1输出的正弦波地址
                .rom_dout   (mode1_sin_wave_data)         // 输出正弦波数据
            );

    // 模式2：波形数据存储RAM模块例化（50M时钟，用于SPI写入和读取）
    ram_16x256 mode2_wave_ram_inst (
                   .clka(sys_clk_50M),                       // input wire clka - 使用50M时钟
                   .wea(mode2_ram_write_en),                 // input wire [0:0] wea - 来自rx_ctrl的写使能
                   .addra(mode2_ram_write_addr),             // input wire [7:0] addra - 来自rx_ctrl的写地址
                   .dina(mode2_ram_write_data),              // input wire [15:0] dina - 来自rx_ctrl的写数据
                   .clkb(sys_clk_50M),                       // input wire clkb - 使用50M时钟
                   .addrb(mode3_dds2_wave_addr),              // input wire [7:0] addrb - 来自DDS1的地址（用于读取）
                   .doutb(mode3_ram_wave_data)               // output wire [15:0] doutb - 输出波形数据
               );

    // 模式3：低频率控制ROM模块例化（246个频率点）
    freq_rom #(
                 .DATA_WIDTH (DATA_WIDTH),
                 .ADDR_WIDTH (8),
                 .ROM_DEPTH  (246)
             ) mode3_freq_rom_inst (
                 .sys_clk     (sys_clk_50M),
                 .sys_rst_n   (locked),
                 .rom_addr    (mode3_spi_to_freq_addr),        // 来自rx_ctrl的频率地址
                 .rom_dout    (mode3_freq_control_word)        // 输出频率控制字
             );

    // 模式3：DDS2模块例化 (32位频率控制字，8位地址，50M时钟)
    DDS #(
            .FWORD_WIDTH (FWORD_WIDTH_32),    // 32位
            .ADDR_WIDTH  (ADDR_WIDTH_8),     // 8位
            .DAC_WIDTH   (14)
        ) mode3_dds2_inst (
            .sys_rst_n   (locked),
            .fword       (mode3_freq_control_word),       // 从频率ROM读取的频率控制字
            .dds_valid   (mode3_dds2_freq_valid),         // 来自rx_ctrl的频率更新有效信号
            .rom_addr    (mode3_dds2_wave_addr),          // DDS2输出的波形地址
            .dac_clk_50M (sys_clk_50M)                    // 使用50M时钟
        );

    // DAC输出选择逻辑
    always @(negedge dac_clk_125M or negedge sys_rst_n) begin
        if (sys_rst_n == 1'b0) begin
            dac_data <= 14'd8192;
        end
        else if (~a2_en) begin
            dac_data <= 14'd8192;  // 使能信号为低时，DAC输出为8,192
        end
        else begin
            // 根据最后激活的模式输出相应数据
            case (last_active_mode)
                2'b01: begin
                    dac_data <= mode1_sin_wave_data;         // 输出模式1数据
                    end
                2'b10:begin
                    dac_data <= mode3_ram_wave_data[13:0];   // 输出模式2数据
                    end
                2'b11:begin
                    dac_data <= mode3_ram_wave_data[13:0];   // 输出模式3数据
                    end
                default:
                    dac_data <= 14'd8192;                     // 无有效模式时输出0
            endcase
        end
    end

    // DAC时钟输出选择逻辑 - 使用组合逻辑
    always @(*) begin
        case (last_active_mode)
            2'b01: dac_clk = dac_clk_125M;    // 模式1使用125M时钟
            default: dac_clk = sys_clk_50M;   // 模式2和3使用50M时钟
        endcase
    end

    // DAC写信号输出选择逻辑 - 使用组合逻辑
    always @(*) begin
        case (last_active_mode)
            2'b01: dac_wrt = dac_clk_125M;    // 模式1使用125M时钟
            default: dac_wrt = sys_clk_50M;   // 模式2和3使用50M时钟
        endcase
    end
    // 时钟生成模块实例化
    clk_wiz_0 u_clk_wiz_0 (
        // Clock out ports
        .sys_clk_50M(sys_clk_50M),     // output sys_clk_50M
        .dac_clk_125M(dac_clk_125M),   // output dac_clk_125M
        // Status and control signals
        .resetn(sys_rst_n),            // input resetn
        .locked(locked),               // output locked
        // Clock in ports
        .sys_clk_in(sys_clk_in)        // input sys_clk_in
    );

//    // ILA调试模块实例化
//     ila_0 u_ila_0 (
//	.clk(sys_clk_50M), // input wire clk - 使用50M系统时钟，与大部分信号同步

//	.probe0(spi_rx_data),                // input wire [15:0]  probe0 - SPI接收数据  
//	.probe1(spi_rx_valid),               // input wire [0:0]   probe1 - SPI接收有效信号
//	.probe2(mode1_spi_to_freq_addr),     // input wire [11:0]  probe2 - 模式1频率地址
//	.probe3(mode1_dds1_freq_valid),      // input wire [0:0]   probe3 - 模式1频率有效信号
//	.probe4(mode1_freq_rom_data),        // input wire [27:0]  probe4 - 模式1频率控制字
//	.probe5(mode1_dds1_sin_addr),        // input wire [7:0]   probe5 - 模式1正弦波地址
//	.probe6(mode1_sin_wave_data),        // input wire [13:0]  probe6 - 模式1正弦波数据
//	.probe7(mode2_ram_write_en),         // input wire [0:0]   probe7 - 模式2RAM写使能
//	.probe8(mode2_ram_write_addr),       // input wire [7:0]   probe8 - 模式2RAM写地址
//	.probe9(mode2_ram_write_data),       // input wire [15:0]  probe9 - 模式2RAM写数据
//	.probe10(mode3_spi_to_freq_addr),    // input wire [7:0]   probe10 - 模式3频率地址
//	.probe11(mode3_dds2_freq_valid),     // input wire [0:0]   probe11 - 模式3频率有效信号
//	.probe12(mode3_freq_control_word),   // input wire [31:0]  probe12 - 模式3频率控制字
//	.probe13(mode3_dds2_wave_addr),      // input wire [7:0]   probe13 - 模式3DDS2波形地址
//	.probe14(mode3_ram_wave_data),       // input wire [15:0]  probe14 - 模式3RAM波形数据
//	.probe15(last_active_mode),           // input wire [1:0]   probe15 - 当前激活模式
//  .probe16(dds1_req),      // input wire [0:0]  probe16 - 模式1请求信号
//	.probe17(ram_req),       // input wire [0:0]  probe17 - 模式2请求信号
//	.probe18(dds2_freq_req), // input wire [0:0]  probe18 - 模式3请求信号
//	.probe19(sck),           // input wire [0:0]  probe19 - SPI时钟
//	.probe20(cs_n),          // input wire [0:0]  probe20 - SPI片选
//	.probe21(mosi),          // input wire [0:0]  probe21 - SPI主设备输出
//	.probe22(miso),           // input wire [0:0]  probe22 - SPI主设备输入
//  .probe23(dac_data),       // input wire [13:0]  probe23 - DAC输出数据
//  .probe24(miso)           // input wire [0:0]   probe24 - A2使能信号
//);   

endmodule
