`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date: 2025/07/20 16:53:42
// Design Name:
// Module Name: DDS（DDS2）
// Project Name:
// Target Devices:
// Tool Versions:
// Description:
//
// Dependencies:
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////


module DDS
    #(
         parameter FWORD_WIDTH     = 32       ,
         parameter ADDR_WIDTH      = 8        ,
         parameter DAC_WIDTH       = 16
     )
     (
         input     wire                          sys_rst_n    ,

         input     wire   [FWORD_WIDTH-1:0]      fword        ,

         input     wire                          dds_valid    ,

         output    reg    [ADDR_WIDTH-1:0]       rom_addr     ,

         input     wire                          dac_clk_50M  

     );


    //频率控制字寄存器
    reg   [FWORD_WIDTH-1:0]   fword_r     ;

    always @(posedge dac_clk_50M or negedge sys_rst_n) begin
        if(~sys_rst_n) begin
            fword_r <= 0;
        end
        else if (dds_valid)  begin //直接使用dds_valid作为有效信号
            fword_r <= fword;
        end
        else begin
            fword_r <= fword_r;
        end
    end

    //相位累加器
    reg   [FWORD_WIDTH-1:0]   f_acc    ;
    always @(posedge dac_clk_50M or negedge sys_rst_n) begin
        if(~sys_rst_n) begin
            f_acc <= 0;
        end
        else if (dds_valid) begin  // 新频率更新时清零，实现同相位
            f_acc <= 0;  // 清零重新开始累加
        end
        else begin
            f_acc <= f_acc + fword_r;
        end
    end

    //相位调制器（相位控制字默认为0）
    always @(posedge dac_clk_50M or negedge sys_rst_n) begin
        if(~sys_rst_n) begin
            rom_addr <= 0;
        end
        else begin
            rom_addr <= f_acc[FWORD_WIDTH-1:FWORD_WIDTH-ADDR_WIDTH];
        end
    end
endmodule