% 生成频率控制字的.coe文件
% 公式: B = (1k + 200×x) × 2^28 / 125M

% 参数定义
base_freq = 1000;
step_freq = 200;
fs = 125e6;
N = 28;
max_freq = 500000;

% 计算
max_x = (max_freq - base_freq) / step_freq;
x = 0:max_x;
frequencies = base_freq + step_freq * x;
B_values = round(frequencies * 2^N / fs);

% 生成.coe文件
fid = fopen('frequency_control_20250730_101318.coe', 'w');
fprintf(fid, 'memory_initialization_radix=10;\n');
fprintf(fid, 'memory_initialization_vector=\n');
for i = 1:length(B_values)
    if i == length(B_values)
        fprintf(fid, '%d;\n', B_values(i));
    else
        fprintf(fid, '%d,\n', B_values(i));
    end
end
fclose(fid);

% 生成Verilog ROM初始化文本格式
fprintf('\n=== Verilog ROM初始化文本格式 ===\n');
for i = 1:length(B_values)
    addr = i - 1; % 地址从0开始
    if addr <= 9
        % 对于地址0-9，使用单个空格对齐
        fprintf('        rom[%d]   = 32''d%d;\n', addr, B_values(i));
    elseif addr <= 99
        % 对于地址10-99，使用两个空格对齐
        fprintf('        rom[%d]  = 32''d%d;\n', addr, B_values(i));
    else
        % 对于地址100以上，使用一个空格对齐
        fprintf('        rom[%d] = 32''d%d;\n', addr, B_values(i));
    end
end
fprintf('=== 复制上述内容到Verilog文件中 ===\n');