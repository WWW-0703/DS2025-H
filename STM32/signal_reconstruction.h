/**
  ******************************************************************************
  * @file           : signal_reconstruction.h
  * @brief          : 信号重建函数
  * @date           : 2025-08-01 02:35:45
  * @author         : WWW8966
  ******************************************************************************
  */

#ifndef __SIGNAL_RECONSTRUCTION_H
#define __SIGNAL_RECONSTRUCTION_H

#ifdef __cplusplus
extern "C" {
#endif

#include "stm32f4xx_hal.h"
#include "arm_math.h"
#include <stdint.h>

/* 信号类型定义 */
#define SIGNAL_SINE           0   // 纯正弦波
#define SIGNAL_HARMONIC_SINE  1   // 谐波正弦波
#define SIGNAL_TRIANGLE       2   // 三角波
#define SIGNAL_SQUARE         3   // 方波
#define SIGNAL_GENERAL        4   // 一般周期信号

/* 采样参数 */
#define SR_HIGH_FREQ_SAMPLE_RATE  1280000 // 1.28MHz
#define SR_LOW_FREQ_SAMPLE_RATE   250000  // 250kHz
#define SR_SAMPLE_SIZE            4096    // 采样点数 - 始终为4096
#define SR_MAX_HARMONICS          20      // 最大谐波数

/* 全局变量声明 */
extern volatile uint8_t sr_adc_complete_flag; // 信号重建模块专用采样完成标志位

/**
  * @brief 检测方波占空比
  * @param samples: 原始采样数据
  * @param size: 数据大小
  * @param threshold: 检测阈值(0.0-1.0)
  * @retval 占空比(0.0-1.0)
  */
float SR_DetectDutyCycle(uint16_t* samples, uint32_t size, float threshold);

/**
  * @brief 通过查表获取方波的直流分量
  * @param measured_duty: 测量的占空比
  * @param peak_to_peak: 峰峰值(V)
  * @retval 直流分量(V)
  */
float SR_GetSquareDCFromTable(float measured_duty, float peak_to_peak);

/**
  * @brief ADC2转换完成回调，专用于信号重建模块
  * @param hadc: ADC句柄
  * @retval None
  * @note 此函数在HAL_ADC_ConvCpltCallback中被调用
  */
void SR_ADC_ConvCpltCallback(ADC_HandleTypeDef* hadc);

/**
  * @brief 初始化信号重建模块
  * @param None
  * @retval None
  */
void SR_Init(void);

/**
  * @brief 采集输入信号
  * @param buffer: 采样数据缓冲区
  * @param size: 缓冲区大小
  * @param use_low_freq: 是否使用低频采样
  * @retval 1: 成功, 0: 失败
  */
uint8_t SR_AcquireSignal(uint16_t* buffer, uint32_t size, uint8_t use_low_freq);

/**
  * @brief 分析输入信号
  * @param samples: 采样数据
  * @param size: 数据大小
  * @param sampleRate: 采样率
  * @param baseFreq: 输出检测到的频率
  * @retval 信号类型
  */
int SR_AnalyzeSignalType(uint16_t* samples, uint32_t size, uint32_t sampleRate, float* baseFreq);

/**
  * @brief 在指定范围内搜索峰值
  * @param spectrum: 幅度谱
  * @param centerBin: 中心bin位置
  * @param searchRange: 搜索范围(±)
  * @param size: 谱线总数
  * @retval 找到的峰值幅度
  */
float SR_FindPeakAroundBin(float* spectrum, uint32_t centerBin, uint32_t searchRange, uint32_t size);

/**
  * @brief 使用抛物线插值优化频率估计
  * @param spectrum: 幅度谱
  * @param peakIndex: 峰值索引
  * @param fftSize: FFT大小
  * @param sampleRate: 采样率
  * @retval 优化后的频率估计(Hz)
  */
static float SR_RefineFrequency(float* spectrum, uint32_t peakIndex, uint32_t fftSize, uint32_t sampleRate);

/**
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
                         int signalType, float baseFreq, float* harmonics, uint32_t* harmOrders);

/**
  * @brief 应用RLC网络特性到信号谐波
  * @param harmonics: 谐波幅度数组
  * @param harmOrders: 谐波次数数组
  * @param numHarmonics: 谐波数量
  * @param baseFreq: 基频
  * @retval None
  */
void SR_ApplyRLCResponse(float* harmonics, uint32_t* harmOrders, uint32_t numHarmonics, float baseFreq);

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
                  int signalType, uint16_t* lutBuffer, float dcOffset, float baseFreq);;

/**
  * @brief 发送波形表和频率控制字到FPGA
  * @param lutBuffer: 波形表
  * @param frequency: 频率
  * @retval None
  */
void SR_SendToFPGA(uint16_t* lutBuffer, uint32_t frequency);

/**
  * @brief 信号重建主函数
  * @param None
  * @retval 信号类型
  */
int SR_ReconstructSignal(void);

#ifdef __cplusplus
}
#endif

#endif /* __SIGNAL_RECONSTRUCTION_H */
