/**
  ******************************************************************************
  * @file           : signal_reconstruction.c
  * @brief          : 信号重建函数
  * @date           : 2025-08-01 02:35:45
  * @author         : WWW8966
  ******************************************************************************
  */

#include "signal_reconstruction.h"
#include <math.h>
#include <stdio.h>

/* 信号重建模块专用采样完成标志位 */
volatile uint8_t sr_adc_complete_flag = 0;

typedef struct {
    float duty_cycle;  // 占空比
    float dc_offset;   // 直流分量(V)
} DutyToDC_t;

/* 外部变量引用 */
extern uint16_t adc_buffer1[];
extern uint16_t adc_buffer2[];
extern float fft_input_buf[];
extern float fft_output_buf[];
extern arm_rfft_fast_instance_f32 rfft_instance_4096;
extern const float kaiser_window[];
extern ADC_HandleTypeDef hadc2;        // 使用ADC2进行信号采样
extern TIM_HandleTypeDef htim3;        // 使用TIM3触发ADC
extern DMA_HandleTypeDef hdma_adc2;    // 使用DMA2_Stream2
extern SPI_HandleTypeDef hspi1;
extern uint32_t freq_array[];
extern float magnitude_array[];
extern float phase_array[];
extern uint32_t response_count;
extern uint16_t waveform_lut[];
extern int circuit_type; // 从main.c引入电路类型
float  k = 4.3898285;

/* 方波直流分量查询表(峰峰值2V) */
static const DutyToDC_t square_dc_table[] = {
    {0.10f, -0.80f},
    {0.15f, -0.70f},
    {0.20f, -0.60f},
    {0.25f, -0.50f},
    {0.30f, -0.40f},
    {0.35f, -0.30f},
    {0.40f, -0.20f},
    {0.45f, -0.10f},
    {0.50f,  0.00f}
};
#define DC_TABLE_SIZE (sizeof(square_dc_table) / sizeof(DutyToDC_t))

/* 私有函数声明 */
static void SR_ApplyKaiserWindow(float* data, uint32_t size);
static float SR_RefineFrequency(float* spectrum, uint32_t peakIndex, uint32_t fftSize, uint32_t sampleRate);

/**
  * @brief 初始化信号重建模块
  * @param None
  * @retval None
  */
void SR_Init(void)
{
    // 初始化FFT实例 - 只需要4096点的实例
    arm_rfft_fast_init_f32(&rfft_instance_4096, 4096);

    // 重置标志位
    sr_adc_complete_flag = 0;
}

/**
  * @brief ADC2转换完成回调，专用于信号重建模块
  * @param hadc: ADC句柄
  * @retval None
  * @note 此函数在HAL_ADC_ConvCpltCallback中被调用
  */
void SR_ADC_ConvCpltCallback(ADC_HandleTypeDef* hadc)
{
	if(hadc->Instance == ADC2)
	    {
	        // 设置信号重建模块专用完成标志
	        sr_adc_complete_flag = 1;

	    }
}

/**
  * @brief 采集输入信号
  * @param buffer: 采样数据缓冲区
  * @param size: 缓冲区大小
  * @param use_low_freq: 是否使用低频采样
  * @retval 1: 成功, 0: 失败
  */
uint8_t SR_AcquireSignal(uint16_t* buffer, uint32_t size, uint8_t use_low_freq)
{
    uint32_t timerPeriod = use_low_freq ? 255 : 49;

    // 设置定时器周期
    __HAL_TIM_SET_AUTORELOAD(&htim3, timerPeriod);

    // 清除完成标志
    sr_adc_complete_flag = 0;

    // 启动ADC采样，使用DMA
    HAL_ADC_Start_DMA(&hadc2, (uint32_t*)buffer, size);

    // 启动定时器触发ADC采样
    HAL_TIM_Base_Start(&htim3);

    // 使用带超时的等待
    while(!sr_adc_complete_flag) ;
    // 停止定时器
    HAL_TIM_Base_Stop(&htim3);

    return 1;
}

/**
  * @brief 应用Kaiser窗
  * @param data: 数据缓冲区
  * @param size: 数据大小
  * @retval None
  */
static void SR_ApplyKaiserWindow(float* data, uint32_t size)
{
    for (uint32_t i = 0; i < size; i++) {
        data[i] *= kaiser_window[i];
    }
}

/**
  * @brief 计算数组均值
  * @param samples: 数据缓冲区
  * @param size: 数据大小
  * @retval 均值
  */
static float SR_CalculateMean(uint16_t* samples, uint32_t size)
{
    uint32_t sum = 0;
    for (uint32_t i = 0; i < size; i++) {
        sum += samples[i];
    }
    return (float)sum / size;
}

/**
  * @brief 分析输入信号
  * @param samples: 采样数据
  * @param size: 数据大小
  * @param sampleRate: 采样率
  * @param baseFreq: 输出检测到的频率
  * @retval 信号类型
  */
int SR_AnalyzeSignalType(uint16_t* samples, uint32_t size, uint32_t sampleRate, float* baseFreq)
{
	 // 计算数组均值作为DC偏置
	float dc_offset = SR_CalculateMean(samples, size);
	float freqResolution = (float)sampleRate/(float)size ;
	// ADC值到电压的转换系数
	const float ADC_TO_VOLTAGE = 3.3f / 4095.0f;

	// 将ADC采样转换为浮点数据，去除DC偏置并归一化到电压值
	for (uint32_t i = 0; i < size; i++) {
		fft_input_buf[i] = ((float)samples[i] - dc_offset) * ADC_TO_VOLTAGE;
	}

    // 应用Kaiser窗
    SR_ApplyKaiserWindow(fft_input_buf, size);

    // 执行实FFT - 始终使用4096点
    arm_rfft_fast_f32(&rfft_instance_4096, fft_input_buf, fft_output_buf, 0);

    // 计算幅度谱
    float spectrum[SR_SAMPLE_SIZE/2];

    // 计算直流分量
    spectrum[0] = fabsf(fft_output_buf[0]) / size;

    // 计算交流分量
    for (uint32_t i = 1; i < size/2; i++) {
        float real = fft_output_buf[2*i];
        float imag = fft_output_buf[2*i+1];

        // 计算幅度 (应用2倍系数，因为能量分布在正负频率)
        spectrum[i] = sqrtf(real*real + imag*imag) / size * 2.0f * k;
    }

    // 查找基频（最大峰值，忽略直流和极低频）
    uint32_t startBin = (uint32_t)(1000.0f * size / sampleRate); // 1kHz对应的bin
    uint32_t maxIndex = startBin;
    float maxVal = spectrum[startBin];

    for (uint32_t i = startBin; i < size/2; i++) {
        if (spectrum[i] > maxVal) {
            maxVal = spectrum[i];
            maxIndex = i;
        }
    }

    // 使用抛物线插值优化频率估计
    float refinedFreq = SR_RefineFrequency(spectrum, maxIndex, size, sampleRate);


    // 四舍五入到最接近的200Hz
    float roundedFreq = roundf(refinedFreq / 200.0f) * 200.0f;
    *baseFreq = roundedFreq;

    // 计算各次谐波位置
    uint32_t fundBin = (uint32_t)(roundedFreq / freqResolution + 0.5f);  // 基频bin
    uint32_t secondBin = (uint32_t)((2.0f * roundedFreq) / freqResolution + 0.5f);  // 2次谐波bin
    uint32_t thirdBin = (uint32_t)((3.0f * roundedFreq) / freqResolution + 0.5f);   // 3次谐波bin

    // 计算各次谐波比例
    float secondHarmRatio = 0, thirdHarmRatio = 0;
    secondHarmRatio = SR_FindPeakAroundBin(spectrum, secondBin, 2, size/2) / maxVal;
    thirdHarmRatio = SR_FindPeakAroundBin(spectrum, thirdBin, 2, size/2) / maxVal;

    // 统计显著谐波数量
    uint32_t significantHarmonics = 0;
    for (uint32_t i = 2; i <= 10; i++) {
        uint32_t harmIndex = (uint32_t)(roundedFreq*i / freqResolution + 0.5f);
        if (harmIndex < size/2) {
            float ratio = SR_FindPeakAroundBin(spectrum, harmIndex, 2, size/2) / maxVal;
            if (ratio > 0.05f) {
                significantHarmonics++;
            }
        }
    }
    // 信号类型判断
    if (secondHarmRatio < 0.05f && thirdHarmRatio < 0.05f) {
        return SIGNAL_SINE;
    } else if (secondHarmRatio > 0.5f && significantHarmonics <= 2) {
        return SIGNAL_HARMONIC_SINE;
    } else if (fabs(thirdHarmRatio - 0.11f) < 0.05f&&significantHarmonics>=3) {
        return SIGNAL_TRIANGLE;
    } else if (thirdHarmRatio > 0.25f&&significantHarmonics>=4) {

        return SIGNAL_SQUARE;

    } else {
        printf("SR: 检测到一般周期信号\r\n");
        return SIGNAL_GENERAL;
    }
}
/**
  * @brief 在指定范围内搜索峰值
  * @param spectrum: 幅度谱
  * @param centerBin: 中心bin位置
  * @param searchRange: 搜索范围(±)
  * @param size: 谱线总数
  * @retval 找到的峰值幅度
  */
float SR_FindPeakAroundBin(float* spectrum, uint32_t centerBin, uint32_t searchRange, uint32_t size)
{
    float maxVal = 0;

    // 确定搜索范围，防止越界
    uint32_t startBin = (centerBin > searchRange) ? (centerBin - searchRange) : 0;
    uint32_t endBin = (centerBin + searchRange < size) ? (centerBin + searchRange) : size - 1;

    // 在范围内搜索最大值
    for (uint32_t i = startBin; i <= endBin; i++) {
        if (spectrum[i] > maxVal) {
            maxVal = spectrum[i];
        }
    }

    return maxVal;
}
/**
  * @brief 使用抛物线插值优化频率估计
  * @param spectrum: 幅度谱
  * @param peakIndex: 峰值索引
  * @param fftSize: FFT大小
  * @param sampleRate: 采样率
  * @retval 优化后的频率估计(Hz)
  */
static float SR_RefineFrequency(float* spectrum, uint32_t peakIndex, uint32_t fftSize, uint32_t sampleRate)
{
    // 确保索引在有效范围内
    if (peakIndex <= 0 || peakIndex >= fftSize/2-1) {
        return (float)peakIndex * sampleRate / fftSize;
    }

    // 获取峰值及其左右点的幅度
    float y1 = spectrum[peakIndex-1];
    float y2 = spectrum[peakIndex];
    float y3 = spectrum[peakIndex+1];

    // 抛物线插值计算频率偏移
    float d = 0.5f * (y1 - y3) / (y1 - 2*y2 + y3);

    // 计算优化后的频率
    float refinedFreq = (peakIndex + d) * sampleRate / fftSize;

    return refinedFreq;
}

/**
  * @brief 检测方波占空比
  * @param samples: 原始采样数据
  * @param size: 数据大小
  * @param threshold: 检测阈值(0.0-1.0)
  * @retval 占空比(0.0-1.0)
  */
float SR_DetectDutyCycle(uint16_t* samples, uint32_t size, float threshold)
{
    // 计算数组均值作为基准
    float mean = SR_CalculateMean(samples, size);

    // 计算数组标准差，用于阈值计算
    float stddev = 0.0f;
    for (uint32_t i = 0; i < size; i++) {
        float diff = (float)samples[i] - mean;
        stddev += diff * diff;
    }
    stddev = sqrtf(stddev / size);

    // 计算比较阈值
    float highThreshold = mean + stddev * threshold;

    // 统计高电平点数
    uint32_t highCount = 0;
    for (uint32_t i = 0; i < size; i++) {
        if ((float)samples[i] > highThreshold) {
            highCount++;
        }
    }

    // 计算占空比
    float dutyCycle = (float)highCount / size;

    return dutyCycle;
}

/**
  * @brief 通过查表获取方波的直流分量
  * @param measured_duty: 测量的占空比
  * @param peak_to_peak: 峰峰值(V)
  * @retval 直流分量(V)
  */
float SR_GetSquareDCFromTable(float measured_duty, float peak_to_peak)
{
    // 如果占空比大于0.5，转换为等效值(方波是对称的)
    if (measured_duty > 0.5f) {
        measured_duty = 1.0f - measured_duty;
    }

    // 限制在表格范围内
    if (measured_duty < 0.1f) measured_duty = 0.1f;
    if (measured_duty > 0.5f) measured_duty = 0.5f;

    // 将占空比四舍五入到最近的0.05步进值
    float rounded_duty = roundf(measured_duty * 20.0f) / 20.0f;

    // 查表获取直流分量
    float dc_offset = 0.0f;
    for (uint8_t i = 0; i < DC_TABLE_SIZE; i++) {
        if (fabs(rounded_duty - square_dc_table[i].duty_cycle) < 0.001f) {
            dc_offset = square_dc_table[i].dc_offset;
            break;
        }
    }

    // 按峰峰值比例缩放(默认表格是按2V峰峰值计算的)
    dc_offset = dc_offset * (peak_to_peak / 2.0f);


    return dc_offset;
}


/*
  * @brief 提取信号谐波
  * @param samples: 采样数据
  * @param size: 数据大小
  * @param sampleRate: 采样率
  * @param signalType: 信号类型
  * @param baseFreq: 基频
  * @param harmonics: 输出谐波幅度数组
  * @param harmOrders: 输出谐波次数数组
  * @retval 谐波数量
  */
uint32_t SR_ExtractHarmonics(uint16_t* samples, uint32_t size, uint32_t sampleRate,
                         int signalType, float baseFreq, float* harmonics, uint32_t* harmOrders)
{
    // 计算数组均值作为DC偏置
    float dc_offset = SR_CalculateMean(samples, size);

    // ADC值到电压的转换系数
    const float ADC_TO_VOLTAGE = 3.3f / 4095.0f;

    // 将ADC采样转换为浮点数据，去除DC偏置并转换为实际电压值
    for (uint32_t i = 0; i < size; i++) {
        fft_input_buf[i] = ((float)samples[i] - dc_offset) * ADC_TO_VOLTAGE;
    }

    // 应用Kaiser窗
    SR_ApplyKaiserWindow(fft_input_buf, size);

    // 执行实FFT - 始终使用4096点
    arm_rfft_fast_f32(&rfft_instance_4096, fft_input_buf, fft_output_buf, 0);

    // 计算幅度谱
    float spectrum[SR_SAMPLE_SIZE/2];

    // 计算直流分量
    spectrum[0] = fabsf(fft_output_buf[0]) / size * k;

    // 计算交流分量
    for (uint32_t i = 1; i < size/2; i++) {
        float real = fft_output_buf[2*i];
        float imag = fft_output_buf[2*i+1];

        // 计算幅度 (应用补偿系数)
        spectrum[i] = sqrtf(real*real + imag*imag) / size * 2.0f * k;
    }

    // 计算基频对应的FFT bin索引
    float binPerHz = (float)size / sampleRate;
    float baseFreqBin = baseFreq * binPerHz;
    int fundBin = (int)(baseFreqBin + 0.5f);

    // 初始化谐波数组和谐波次数数组
    memset(harmonics, 0, sizeof(float) * SR_MAX_HARMONICS);
    memset(harmOrders, 0, sizeof(uint32_t) * SR_MAX_HARMONICS);

    // 确定提取的谐波次数
    uint32_t maxOrder;
    float minRatio;

    switch (signalType) {
        case SIGNAL_SINE:
            maxOrder = 1;
            minRatio = 0.0f;
            break;
        case SIGNAL_HARMONIC_SINE:
            maxOrder = 5;
            minRatio = 0.1f;
            break;
        default:
            maxOrder = 20; // 增大最大谐波数量以捕获更多高次谐波
            minRatio = 0.005f;
    }

    uint32_t numHarmonics = 0;

    // 提取基频
    if (fundBin > 0 && fundBin < size/2) {
        harmonics[numHarmonics] = spectrum[fundBin];
        harmOrders[numHarmonics] = 1; // 基频的谐波次数为1
        numHarmonics++;

        // 基频幅度作为参考
        float fundAmp = spectrum[fundBin];

        // 提取谐波
        for (uint32_t i = 2; i <= maxOrder && numHarmonics < SR_MAX_HARMONICS; i++) {
            int harmBin = (int)(i * baseFreq * binPerHz + 0.5f);

            if (harmBin < size/2) {
                // 在谐波频率附近搜索最大值
                int searchRange = 2;
                int searchStart = harmBin - searchRange;
                int searchEnd = harmBin + searchRange;

                if (searchStart < 0) searchStart = 0;
                if (searchEnd >= size/2) searchEnd = size/2 - 1;

                float maxHarmAmp = 0;
                int maxHarmBin = 0;

                for (int j = searchStart; j <= searchEnd; j++) {
                    if (spectrum[j] > maxHarmAmp) {
                        maxHarmAmp = spectrum[j];
                        maxHarmBin = j;
                    }
                }

                // 如果谐波幅度超过阈值，保存谐波信息
                float ratio = maxHarmAmp / fundAmp;
                if (ratio > minRatio) {
                    harmonics[numHarmonics] = maxHarmAmp;
                    harmOrders[numHarmonics] = i; // 保存具体的谐波次数
                    numHarmonics++;
                }
            }
        }
    }

    return numHarmonics;
}

/**
  * @brief 应用RLC网络特性到信号谐波
  * @param harmonics: 谐波幅度数组
  * @param harmOrders: 谐波次数数组
  * @param numHarmonics: 谐波数量
  * @param baseFreq: 基频
  * @retval None
  */
void SR_ApplyRLCResponse(float* harmonics, uint32_t* harmOrders, uint32_t numHarmonics, float baseFreq)
{
    // 临时数组保存修改后的值
    float modifiedHarmonics[SR_MAX_HARMONICS];

    for (uint32_t i = 0; i < numHarmonics; i++) {
        // 计算当前谐波的频率，使用保存的谐波次数
        float harmFreq = baseFreq * harmOrders[i];

        // 查找最接近的测量频率点
        uint32_t freqIndex = (uint32_t)((harmFreq - 1000.0f) / 200.0f+0.5f);

        // 确保索引在有效范围内
        if (freqIndex >= response_count) {
            freqIndex = response_count - 1;
        }

        // 应用幅度响应
        modifiedHarmonics[i] = harmonics[i] * magnitude_array[freqIndex];
    }

    // 复制回原始数组
    for (uint32_t i = 0; i < numHarmonics; i++) {
        harmonics[i] = modifiedHarmonics[i];
    }
}

/**
  * @brief 生成波形查找表，直接映射电压值
  * @param harmonics: 谐波幅度数组(真实电压值)
  * @param harmOrders: 谐波次数数组
  * @param numHarmonics: 谐波数量
  * @param signalType: 信号类型
  * @param lutBuffer: 输出波形表
  * @param dcOffset: 直流偏移值(V)
  * @param baseFreq: 信号基频
  * @retval None
  */
void SR_GenerateLUT(float* harmonics, uint32_t* harmOrders, uint32_t numHarmonics,
                   int signalType, uint16_t* lutBuffer, float dcOffset, float baseFreq)
{
    const float TWO_PI = 6.28318530718f;
    float waveform[256] = {0};
    float min_val = 0, max_val = 0;


    // 合成一个完整周期的波形(真实电压值)
    for (int i = 0; i < 256; i++) {
        float angle = TWO_PI * i / 256.0f;

        // 添加直流分量
        waveform[i] = dcOffset;

        // 累加各次谐波分量，相位根据RLC网络响应和信号类型设置
        for (uint32_t h = 0; h < numHarmonics; h++) {
            uint32_t harmOrder = harmOrders[h];
            float harmFreq = harmOrder * baseFreq;

            // 相位 = RLC网络相位响应
            float phase = 0.0f;
            uint32_t freqIndex = (uint32_t)((harmFreq - 1000.0f) / 200.0f + 0.5f);
            if (freqIndex < response_count) {
                phase = phase_array[freqIndex];
            }

            // 三角波的偶次谐波相位反转
            if (signalType == SIGNAL_TRIANGLE && harmOrder % 2 == 0) {
                phase += 3.14159265358979323846f;
            }

            // 添加谐波分量(真实电压值)
            waveform[i] += harmonics[h] * sinf(harmOrder * angle + phase);
        }

        // 跟踪最大最小值(用于监控，不用于归一化)
        if (i == 0 || waveform[i] < min_val) min_val = waveform[i];
        if (i == 0 || waveform[i] > max_val) max_val = waveform[i];
    }

    // 直接映射到DAC范围
    // 假设DAC为14位(0-16383)，对应-5V到+5V
    // 如果是其他范围，请调整这些常量
    const float DAC_MIN_VOLTAGE = -5.0f;
    const float DAC_MAX_VOLTAGE = +5.0f;
    const float DAC_VOLTAGE_RANGE = DAC_MAX_VOLTAGE - DAC_MIN_VOLTAGE;
    const uint16_t DAC_MAX_VALUE = 16383; // 14-bit DAC
    float gain = 1.05f;  // 可选增益系数
    for (int i = 0; i < 256; i++) {
        // 应用可选的增益系数,仅对非直流项作用，
        float voltage = (waveform[i] - dcOffset) * gain+dcOffset ;

        // 映射电压到DAC值：(voltage - DAC_MIN_VOLTAGE) / DAC_VOLTAGE_RANGE * DAC_MAX_VALUE
        float dac_value = (voltage - DAC_MIN_VOLTAGE) / DAC_VOLTAGE_RANGE * DAC_MAX_VALUE;

        // 限制在有效范围内
        if (dac_value < 0) dac_value = 0;
        if (dac_value > DAC_MAX_VALUE) dac_value = DAC_MAX_VALUE;

        // 保存到LUT
        lutBuffer[i] = (uint16_t)(dac_value + 0.5f);
    }

}

/**
  * @brief 发送波形表和频率控制字到FPGA
  * @param lutBuffer: 波形表
  * @param frequency: 频率
  * @retval None
  */
void SR_SendToFPGA(uint16_t* lutBuffer, uint32_t frequency)
{
    // 发送模式选择(PF3拉低表示波形表模式)
    HAL_GPIO_WritePin(GPIOF, GPIO_PIN_3, GPIO_PIN_RESET);
    HAL_GPIO_WritePin(GPIOA, GPIO_PIN_4, GPIO_PIN_RESET);


    // 发送256点波形表,16位发送

        HAL_SPI_Transmit(&hspi1, lutBuffer, 256, 100);

    HAL_GPIO_WritePin(GPIOA, GPIO_PIN_4, GPIO_PIN_SET);
    HAL_GPIO_WritePin(GPIOF, GPIO_PIN_3, GPIO_PIN_SET);
    // 发送模式选择(PF1拉低表示频率控制字模式)
    HAL_GPIO_WritePin(GPIOF, GPIO_PIN_1, GPIO_PIN_RESET);
    HAL_GPIO_WritePin(GPIOA, GPIO_PIN_4, GPIO_PIN_RESET);



    // 计算频率控制字(从1K-50K转换为0-245)
    uint16_t freqWord = (uint16_t)((frequency - 1000.0f) / 200.0f);
    if (freqWord > 245) freqWord = 245; // 安全检查

    // 发送频率控制字
    HAL_SPI_Transmit(&hspi1, (uint8_t*)&freqWord, 1, 100);

    HAL_GPIO_WritePin(GPIOA, GPIO_PIN_4, GPIO_PIN_SET);
    HAL_GPIO_WritePin(GPIOF, GPIO_PIN_1, GPIO_PIN_SET);

}



/**
  * @brief 信号重建主函数
  * @param None
  * @retval 信号类型
  */
/**
  * @brief 重建输入信号并发送到FPGA输出
  * @retval 信号类型
  */
int SR_ReconstructSignal(void)
{
    float baseFreq = 0.0f;
    int signalType = -1;
    float harmonics[SR_MAX_HARMONICS] = {0};
    uint32_t harmOrders[SR_MAX_HARMONICS] = {0}; // 谐波次数数组
    uint32_t numHarmonics = 0;
    float dutyCycle = 0.5f;  // 默认占空比50%
    float dcComponent = 0.0f;
    float peakToPeak = 0.0f;


    // 1. 采集信号 - 始终使用4096点
    if (!SR_AcquireSignal(adc_buffer2, SR_SAMPLE_SIZE, 0)) {
        return -1;
    }

    // 2. 分析信号类型和基频
    signalType = SR_AnalyzeSignalType(adc_buffer2, SR_SAMPLE_SIZE, SR_HIGH_FREQ_SAMPLE_RATE, &baseFreq);
    // 3. 对于方波，检测占空比

    if (signalType == SIGNAL_SQUARE) {
        dutyCycle = SR_DetectDutyCycle(adc_buffer2, SR_SAMPLE_SIZE, 0.8f);
    }


    // 4. 对于低频信号(1K-5K)，重新采集以提高精度
    if (baseFreq >= 1000.0f && baseFreq <= 5000.0f) {

        // 重新采集
        if (!SR_AcquireSignal(adc_buffer2, SR_SAMPLE_SIZE, 1)) {
            return -1;
        }

        // 重新分析
        signalType = SR_AnalyzeSignalType(adc_buffer2, SR_SAMPLE_SIZE, SR_LOW_FREQ_SAMPLE_RATE, &baseFreq);

        // 重新检测占空比
        if (signalType == SIGNAL_SQUARE) {
            dutyCycle = SR_DetectDutyCycle(adc_buffer2, SR_SAMPLE_SIZE, 0.8f);

        }
    }

    // 5. 提取谐波信息
    numHarmonics = SR_ExtractHarmonics(
        adc_buffer2, SR_SAMPLE_SIZE,
        (baseFreq <= 5000.0f) ? SR_LOW_FREQ_SAMPLE_RATE : SR_HIGH_FREQ_SAMPLE_RATE,
        signalType, baseFreq, harmonics, harmOrders
    );

    if (numHarmonics == 0) {

        return -1;
    }


    // 7. 计算方波的峰峰值和直流分量
    if (signalType == SIGNAL_SQUARE && numHarmonics > 0) {
        // 方波基波幅度与峰峰值的关系: 峰峰值 ≈ π * 基波幅度
        peakToPeak =  2 ;//3.14159f * harmonics[0];

        // 只有低通电路才需要处理直流分量
        if (circuit_type == 0) {
            // 通过查表获取直流分量
            dcComponent = SR_GetSquareDCFromTable(dutyCycle, peakToPeak);

        }
    }

    // 8. 应用RLC网络响应
    SR_ApplyRLCResponse(harmonics, harmOrders, numHarmonics, baseFreq);

    // 9. 生成波形查找表(增加直流分量和基频参数)
    SR_GenerateLUT(harmonics, harmOrders, numHarmonics, signalType, waveform_lut, dcComponent, baseFreq);

    // 10. 发送到FPGA
    float roundedFreq = roundf(baseFreq / 200.0f) * 200.0f;
    SR_SendToFPGA(waveform_lut, (uint32_t)roundedFreq);


    return signalType;
}

