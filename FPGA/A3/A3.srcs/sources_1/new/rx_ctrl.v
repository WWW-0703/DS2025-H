`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date: 2025/07/31 09:08:34
// Design Name:
// Module Name: rx_ctrl
// Project Name:
// Target Devices:
// Tool Versions:
// Description: SPI数据选择器，根据last_active_mode状态选择工作模式
//              模式1：DDS1模式，SPI数据给频率ROM地址，同时打一拍给DDS1模块
//              模式2：RAM写入模式，SPI数据写入RAM
//              模式3：DDS2频率控制模式，SPI数据查找频率控制字
//              valid信号只在SPI通信时触发一次，保证模式稳定性
//
// Dependencies:
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////


module rx_ctrl(
        input  wire         sys_clk,          // 系统时钟
        input  wire         sys_rst_n,        // 系统复位，低有效
        input  wire [1:0]   last_active_mode, // 当前激活的模式：01-模式1，10-模式2，11-模式3

        // SPI接口
        input  wire [15:0]  spi_rx_data,      // SPI接收数据
        input  wire         spi_rx_valid,     // SPI数据有效

        // 模式1：DDS1接口（类似模式3但给ram_16x256）
        output wire [11:0]  mode1_dds1_rom_addr,    // DDS1 ROM地址
        output reg          mode1_dds1_valid,       // DDS1有效信号（spi_rx_valid打一拍）

        // 模式2：RAM写入接口
        output reg          wea,              // RAM写使能
        output reg [7:0]    addra,            // RAM写地址
        output wire [15:0]  dina,             // RAM写数据

        // 模式3：频率控制接口
        output wire [7:0]   mode3_rom_addr,         // freq_rom地址
        output reg          mode3_dds_valid         // DDS有效信号（spi_rx_valid打一拍）
    );

    // 数据选择器逻辑
    assign dina = spi_rx_data;                     // 模式2：SPI数据给RAM
    assign mode1_dds1_rom_addr = spi_rx_data[11:0];       // 模式1：SPI数据给DDS1 ROM地址
    assign mode3_rom_addr = spi_rx_data[7:0];            // 模式3：SPI数据给freq_rom

    // 模式1：DDS1模式 - spi_rx_valid打一拍给mode1_dds1_valid
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            mode1_dds1_valid <= 1'b0;
        end
        else if (last_active_mode == 2'b01) begin  // 模式1激活
            mode1_dds1_valid <= spi_rx_valid;  // 打一拍
        end
        else begin
            mode1_dds1_valid <= 1'b0;
        end
    end

    // 模式2：写地址计数器和写使能
    reg [7:0] write_addr_cnt;
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            write_addr_cnt <= 8'b0;
            wea <= 1'b0;
            addra <= 8'b0;
        end
        else if (last_active_mode == 2'b10 && spi_rx_valid) begin  // 模式2激活且SPI数据有效
            wea <= 1'b1;
            addra <= write_addr_cnt;
            write_addr_cnt <= write_addr_cnt + 1;
        end
        else begin
            wea <= 1'b0;
        end
    end

    // 模式3：spi_rx_valid打一拍给mode3_dds_valid
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            mode3_dds_valid <= 1'b0;
        end
        else if (last_active_mode == 2'b11) begin  // 模式3激活
            mode3_dds_valid <= spi_rx_valid;  // 打一拍
        end
        else begin
            mode3_dds_valid <= 1'b0;
        end
    end

endmodule
