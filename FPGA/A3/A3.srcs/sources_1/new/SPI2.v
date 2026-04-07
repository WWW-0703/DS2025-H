`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/07/17 17:10:46
// Design Name: 
// Module Name: SPI
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


module SPI2
#(
  parameter   BIT_NUM        =  32    , 
  parameter   BIT_CNT_WIDTH  =  6     ,
  parameter   BYTE_NUM       =  4  ,
  parameter   BYTE_NUM_WIDTH =  2
)
(
    input   wire            sys_rst_n,
    input   wire            sys_clk,

    //SPI
    input   wire            sck,
    input   wire            cs_n,
    input   wire            mosi,
    output  reg             miso,

    //rx_ctrl
    output  reg                            rx_data_valid     ,
    output  reg    [BIT_NUM-1:0]           rx_data           

);

    //边沿提取
    reg         sck_reg1   ;
    reg         sck_reg2   ;
    reg         cs_n_reg1  ;
    reg         cs_n_reg2  ;
    
    //输入输出的值寄存  
    reg  [(BIT_NUM-1):0]  mosi_reg   ; 



    //赋值 输入因为不同慢时钟到快时钟打两拍
    always@(posedge sys_clk or negedge sys_rst_n)begin
        if(!sys_rst_n)begin
            sck_reg1   <= 1'b0;
            sck_reg2   <= 1'b0;
            cs_n_reg1  <= 1'b1;
            cs_n_reg2  <= 1'b1;
        end
        else begin
            sck_reg1   <= sck      ;
            sck_reg2   <= sck_reg1 ;
            cs_n_reg1  <= cs_n     ;
            cs_n_reg2  <= cs_n_reg1;
            end
    end
    //边沿
    wire   sck_posedge   ;
    wire   sck_negedge   ;
    wire   cs_posedge    ;
    wire   cs_negedge    ;
    
    assign sck_posedge =  (sck_reg1 == 1'b1) && (sck_reg2 == 1'b0)  ;
    assign sck_negedge =  (sck_reg1 == 1'b0) && (sck_reg2 == 1'b1)  ;
    assign cs_posedge =  (cs_n_reg1 == 1'b1) && (cs_n_reg2 == 1'b0)  ;
    assign cs_negedge =  (cs_n_reg1 == 1'b0) && (cs_n_reg2 == 1'b1)  ;
    
    
    //状态机
    //状态定义
    localparam  IDLE     =  4'b0001 ;
    localparam  PREPARE  =  4'b0010 ;
    localparam  TRANSMIT =  4'b0100 ;
    localparam  FINISH   =  4'b1000 ;

    reg   [3:0]   state   ;

    //位计数器
    reg   [BIT_CNT_WIDTH-1:0]  bit_cnt  ;
    //字节计数器
    reg   [BYTE_NUM_WIDTH-1:0]  byte_cnt  ;

    //两个计数逻辑合起来
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            bit_cnt <= BIT_NUM-1;
            byte_cnt <=   BYTE_NUM-1;
            end
        else if (state == IDLE) begin
            bit_cnt <= BIT_NUM-1;
            byte_cnt <=   BYTE_NUM-1;
            end
        else if (state == TRANSMIT) begin
            if (sck_posedge) begin
                if (bit_cnt == 0) begin
                 bit_cnt <= BIT_NUM-1;
                 byte_cnt <= byte_cnt - 1;
                end
                else bit_cnt <= bit_cnt - 1;
            end
        end
        else begin 
          bit_cnt <= BIT_NUM-1;
          byte_cnt <=   BYTE_NUM-1;
        end
    end

    //状态转换
    always@(posedge sys_clk or negedge sys_rst_n)
    if (!sys_rst_n)
        state <= IDLE;
    else case(state)
        IDLE:
            if (cs_negedge)
                state <= PREPARE;
            else
                state <= IDLE;
        PREPARE:
            if (cs_posedge)
                state <= IDLE;
            // 直接跳转到TRANSMIT状态，不需要等待tx_data_valid
            else
                state <= TRANSMIT;
        TRANSMIT:
            if (cs_posedge)
                state <= IDLE;
            else if (sck_posedge && bit_cnt == 0 && byte_cnt == 0)
                state <= FINISH;
            else
                state <= TRANSMIT;
        FINISH:
            if (cs_posedge)
                state <= IDLE;
            else
                state <= FINISH;
    endcase

    //  rx
    always@(posedge sys_clk or negedge sys_rst_n)
      if (!sys_rst_n) begin
        mosi_reg <= 0;
        rx_data <= 0;
        rx_data_valid <= 1'b0;
      end
      else case (state)
        IDLE: begin
          mosi_reg <= 0;
          rx_data <= 0;
          rx_data_valid <= 0;
        end
        PREPARE: begin
          mosi_reg <= 0;
          rx_data <= 0;
          rx_data_valid <= 0;
          end
        TRANSMIT: begin
          rx_data_valid <= 0;
          if (sck_posedge) begin
            mosi_reg <= {mosi_reg[(BIT_NUM-2):0], mosi};
            if (bit_cnt == 0) begin
                rx_data <= {mosi_reg[(BIT_NUM-2):0], mosi};
                rx_data_valid <= 1'b1;
                end
            end
          end
          FINISH: begin
            rx_data_valid <= 0;  
          end
      endcase


      //和FIFO_ctrl连接  tx - 已注释掉发送功能，miso固定为0
      always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            miso <= 1'b0;  // miso固定为0
        end
        else begin
            miso <= 1'b0;  // miso固定为0
        end
      end



            

endmodule
