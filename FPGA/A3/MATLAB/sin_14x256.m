clc;                    %清除命令行命令
clear all;              %清除工作区变量,释放内存空间
F1=1;                   %信号频率
Fs=2^8;                %采样频率*******改变存储的数目
P1=0;                   %信号初始相位
N=2^8;                 %采样点数*******改变存储的数目
t=[0:1/Fs:(N-1)/Fs];    %采样时刻
ADC=2^13;                %直流分量*******改变数据位宽（14位DAC的中点值）
A=2^13 - 1;              %信号幅度*******改变数据位宽（14位DAC的最大幅度）
%生成正弦信号
s=A*sin(2*pi*F1*t + pi*P1/180) + ADC;
plot(s);                %绘制图形
%创建coe文件
fild = fopen('sin_wave_256x14.coe','wt');%*******改一下名字
%写入coe文件头
fprintf(fild, '%s\n','MEMORY_INITIALIZATION_RADIX=10;');
fprintf(fild, '%s\n','MEMORY_INITIALIZATION_VECTOR=');
for i = 1:N
    s0(i) = round(s(i));    %对小数四舍五入以取整
    if s0(i) < 0             %负值强制置零
        s0(i) = 0;
    end
    if s0(i) > (2^14-1)      %超出14位最大值限制
        s0(i) = 2^14-1;
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
