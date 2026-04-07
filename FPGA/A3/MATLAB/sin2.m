clc;                    %清除命令行命令
clear all;              %清除工作区变量,释放内存空间
F1=1;                   %信号频率
Fs=2^8;                %采样频率*******改变存储的数目
P1=0;                   %信号初始相位
N=2^8;                 %采样点数*******改变存储的数目
t=[0:1/Fs:(N-1)/Fs];    %采样时刻

% 14位DAC参数设置 (偏移二进制，-5V~+5V，期望输出-1.5V~+1.5V)
DAC_BITS = 14;                    % DAC位数
DAC_LEVELS = 2^DAC_BITS;          % DAC量化级别 (16384)
VOLTAGE_RANGE = 10;               % DAC电压范围 (-5V~+5V = 10V)
LSB_VOLTAGE = VOLTAGE_RANGE / DAC_LEVELS;  % 每个LSB对应电压 (0.61mV)

% 偏移二进制：0V对应中点值，-5V对应0，+5V对应满量程
ZERO_VOLT_CODE = 2^(DAC_BITS-1);     % 0V对应的数字值 = 8192
MAX_OUTPUT_VOLT = 3.0;               % 期望最大输出电压
MIN_OUTPUT_VOLT = 0.0;               % 期望最小输出电压
AMPLITUDE_VOLT = (MAX_OUTPUT_VOLT - MIN_OUTPUT_VOLT) / 2; % 幅度 = 1.5V
DC_OFFSET_VOLT = (MAX_OUTPUT_VOLT + MIN_OUTPUT_VOLT) / 2; % 直流偏移 = 1.5V (0-3V的中点)

% 计算对应的数字值
ADC = ZERO_VOLT_CODE + round(DC_OFFSET_VOLT / LSB_VOLTAGE);  % 直流分量 (对应1.5V)
A = round(AMPLITUDE_VOLT / LSB_VOLTAGE);                     % 信号幅度 (对应1.5V峰值)

%生成正弦信号
s = A * sin(2*pi*F1*t + pi*P1/180) + ADC;
plot(s);                %绘制图形
%创建coe文件
fild = fopen('sin_wave_256x14_0V_to_3V.coe','wt');  % 0V~3V正弦波文件
%写入coe文件头
fprintf(fild, '%s\n','MEMORY_INITIALIZATION_RADIX=10;');
fprintf(fild, '%s\n','MEMORY_INITIALIZATION_VECTOR=');
for i = 1:N
    s0(i) = round(s(i));    %对小数四舍五入以取整
    if s0(i) < 0             %负值强制置零
        s0(i) = 0;
    end
    if s0(i) > (DAC_LEVELS-1)  % 超出最大值限制
        s0(i) = DAC_LEVELS-1;
    end
    if i == N
        fprintf(fild, '%d',s0(i));
        fprintf(fild, '%s\n',';');
    else
        fprintf(fild, '%d',s0(i));
        fprintf(fild, '%s\n',',');
    end
end
fclose(fild);

% 生成Verilog ROM初始化文本格式
fprintf('\n=== Verilog ROM初始化文本格式 ===\n');
for i = 1:N
    if i <= 9
        % 对于地址0-9，使用单个空格对齐
        fprintf('        rom[%d]   = 14''d%d;\n', i-1, s0(i));
    elseif i <= 99
        % 对于地址10-99，使用两个空格对齐
        fprintf('        rom[%d]  = 14''d%d;\n', i-1, s0(i));
    else
        % 对于地址100以上，使用一个空格对齐
        fprintf('        rom[%d] = 14''d%d;\n', i-1, s0(i));
    end
end
fprintf('=== 复制上述内容到Verilog文件中 ===\n');
