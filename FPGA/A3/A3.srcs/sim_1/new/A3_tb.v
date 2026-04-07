`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/07/30 22:30:00
// Design Name: 
// Module Name: PART2_tb
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: PART2模块测试程序
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module A3_tb();

    // SPI时钟周期参数
    parameter SPI_CLK_PERIOD = 100; // 100ns周期 = 10MHz

    // 测试信号定义
    reg                 sys_clk_in;      
    reg                 sys_rst_n;
    reg                 dds1_req;        // 模式1请求：DDS1模式，低有效
    reg                 ram_req;         // 模式2请求：RAM写入模式，低有效
    reg                 dds2_freq_req;   // 模式3请求：DDS2频率控制模式，低有效
    reg                 sck;
    reg                 cs_n;
    reg                 mosi;
    wire                miso;
    wire                dac_clk_50M;
    wire                dac_wrt;
    wire    [13:0]      dac_data;        
    // reg                 a2_en;  // 已注释掉
    

    // SPI测试数据 - 16位
    integer i;

    // 实例化被测模块
    A3 u_a3 (
           .sys_clk_in      (sys_clk_in),   
           .sys_rst_n       (sys_rst_n),
           .dds1_req        (dds1_req),      // 模式1请求
           .ram_req         (ram_req),       // 模式2请求  
           .dds2_freq_req   (dds2_freq_req), // 模式3请求
           .sck             (sck),
           .cs_n            (cs_n),
           .mosi            (mosi),
           .miso            (miso),
           .dac_clk         (dac_clk_50M),
           .dac_wrt         (dac_wrt),
           .dac_data        (dac_data)
           // .a2_en           (a2_en)  // 已注释掉
       );

    // 生成系统时钟 50MHz
    initial begin
        sys_clk_in = 0;                    // 修正信号名
        forever
            #10 sys_clk_in = ~sys_clk_in;  // 20ns周期 = 50MHz
    end

    // SPI时钟初始化（在任务中手动控制）
    initial begin
        sck = 0; // 初始状态为低电平
    end

    // 主测试流程
    initial begin
        // 初始化信号
        sys_rst_n = 0;
        // a2_en = 1;        // 已注释掉
        dds1_req = 1;        // 高电平为非激活状态
        ram_req = 1;         // 高电平为非激活状态  
        dds2_freq_req = 1;   // 高电平为非激活状态
        cs_n = 1;
        mosi = 0;

        // 等待复位释放
        #100;
        sys_rst_n = 1;
        
        // 等待PLL锁定
        wait(u_a3.locked);
        #1000;

        $display("========================================");
        $display("开始A2模块三模式测试流程");
        $display("========================================");

        // ========== 模式1测试：DDS1高频正弦波生成 ==========
        $display("\n=== 模式1测试：DDS1高频正弦波生成 ===");
        
        // 激活模式1
        $display("激活模式1 - 拉低dds1_req信号");
        dds1_req = 0;  // 拉低激活模式1
        #20;         // 等待模式切换稳定
        dds1_req = 1;
        
        // 模式1 - 频率地址0
        $display("模式1 - 发送频率地址: 0");
        spi_send_16bit(16'h0000);  // 频率地址0

        #1000000;  // 观察输出波形

        // 模式1 - 频率地址20  
        $display("模式1 - 发送频率地址: 20");
        spi_send_16bit(16'h0014);  // 频率地址20
        #1000000;  // 观察输出波形
        
        // 模式1 - 频率地址2496
        $display("模式1 - 发送频率地址: 2496");
        spi_send_16bit(16'h09BF);  // 频率地址2495
        #1000000;  // 观察输出波形
        
        // 退出模式1
        $display("退出模式1 - 拉高dds1_req信号");
        dds1_req = 1;  // 拉高退出模式1
        #5000;

        // ========== 模式2测试：RAM波形数据存储 ==========
        $display("\n=== 模式2测试：RAM波形数据存储 ===");
        
        // 激活模式2
        $display("激活模式2 - 拉低ram_req信号");
        ram_req = 0;   // 拉低激活模式2
        #5000;         // 等待模式切换稳定
        
        // 写入256个14位递减数据
        $display("模式2 - 写入256个14位递减数据");
        spi_send_waveform_256(1);
        #10000;  // 等待数据写入完成
        
        // 退出模式2
        $display("退出模式2 - 拉高ram_req信号");
        ram_req = 1;   // 拉高退出模式2
        #1000000;  // 观察输出波形

        // ========== 模式3测试：DDS2频率控制 ==========
        $display("\n=== 模式3测试：DDS2频率控制 ===");
        
        // 激活模式3
        $display("激活模式3 - 拉低dds2_freq_req信号");
        dds2_freq_req = 0;  // 拉低激活模式3
        #5000;              // 等待模式切换稳定
        
        // 模式3 - 频率地址0
        $display("模式3 - 发送频率地址: 0");
        spi_send_16bit(16'h0000);  // 频率地址0
        #1000000;  // 观察输出波形
        
        // 模式3 - 频率地址10
        $display("模式3 - 发送频率地址: 10");
        spi_send_16bit(16'h000A);  // 频率地址10
        #1000000;  // 观察输出波形
        
        // 模式3 - 频率地址245
        $display("模式3 - 发送频率地址: 245");
        spi_send_16bit(16'h00F5);  // 频率地址245
        #1000000;  // 观察输出波形
        
        // 退出模式3
        $display("退出模式3 - 拉高dds2_freq_req信号");
        dds2_freq_req = 1;  // 拉高退出模式3
        #5000;

        // a2_en = 0; // 关闭A2模块 - 已注释掉
        #5000;
        $display("\n========================================");
        $display("所有模式测试完成");
        $display("========================================");

        $finish;
    end

    // SPI发送16位数据的任务
    task spi_send_16bit;
        input [15:0] data;
        integer i;
        begin
            $display("    SPI发送16位数据: 0x%04X", data);
            cs_n = 0;      // 片选拉低
            #100;          // 片选建立时间
            
            // 发送16位数据，MSB优先
            for (i = 15; i >= 0; i = i - 1) begin
                mosi = data[i];
                #(SPI_CLK_PERIOD/2);       // 半个时钟周期
                sck = 1;
                #(SPI_CLK_PERIOD/2);       // 半个时钟周期
                sck = 0;
            end
            
            #100;          // 数据保持时间
            cs_n = 1;      // 片选拉高
            #1000;         // 片选间隔时间
            $display("    SPI传输完成");
        end
    endtask

    // SPI连续发送256个16位波形数据任务（用于波形写入模式）
    task spi_send_waveform_256(input mode); // mode: 0=递增(0-255), 1=递减(256-1)
        integer word_idx, bit_idx;
        reg [15:0] current_data;
        begin
            $display("开始连续发送256个16位波形数据 - 模式: %s", mode ? "递减(256-1)" : "递增(0-255)");
            
            // 拉低CS开始连续传输（整个256个数据期间CS_N保持低电平）
            cs_n = 0;
            #200; // 等待一段时间
            
            sck = 0;
            #(SPI_CLK_PERIOD/2);

            // 连续发送256个16位数据
            for (word_idx = 0; word_idx < 256; word_idx = word_idx + 1) begin
                // 计算当前数据
                if (mode == 0) begin
                    current_data = word_idx; // 递增模式：0到255
                end else begin
                    current_data = 256 - word_idx; // 递减模式：256到1
                end
                
                
                // 发送当前16位数据，MSB先发
                for (bit_idx = 15; bit_idx >= 0; bit_idx = bit_idx - 1) begin
                    mosi = current_data[bit_idx]; // 在SCK下降沿设置数据
                    #(SPI_CLK_PERIOD/2);
                    sck = 1;                      // SCK上升沿（SPI在上升沿采样）
                    #(SPI_CLK_PERIOD/2);
                    sck = 0;                      // SCK下降沿
                end

            end

            // 所有256个数据发送完成，等待后拉高CS
            #200;
            cs_n = 1;
            #500;
            
        end
    endtask

endmodule
