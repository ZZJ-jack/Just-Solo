/*
 * alac_wrapper.h —— Apple ALACDecoder (C++) 的 C 接口包装
 *
 * ALAC（Apple Lossless）参考解码器为 C++ 类，miniaudio 自定义后端为 C，
 * 通过本包装层以 extern "C" 方式调用。源码位于 third_party/alac（Apache 2.0）。
 */
#ifndef ALAC_WRAPPER_H
#define ALAC_WRAPPER_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* 创建解码器并初始化（cookie = ALACSpecificConfig 24 字节），失败返回 NULL */
void* alac_decoder_create(const unsigned char* cookie, unsigned int cookieSize);

/* 解码一帧：in=压缩数据, inBytes=输入字节数, out=输出缓冲,
 * inOutFrames 传入期望帧数、返回实际解码帧数；
 * 输出格式由位深决定（16 位→int16，20/24 位→3 字节打包，32 位→int32，均交错）。 */
int alac_decoder_decode(void* dec, const unsigned char* in, unsigned int inBytes,
                        unsigned char* out, unsigned int* inOutFrames,
                        unsigned int* outBytes);

/* 查询配置 */
unsigned int alac_decoder_sample_rate(void* dec);
unsigned int alac_decoder_channels(void* dec);
unsigned int alac_decoder_bit_depth(void* dec);
unsigned int alac_decoder_frame_length(void* dec);

/* 每样本字节数（16 位→2，20/24 位→3，32 位→4） */
unsigned int alac_decoder_bytes_per_sample(void* dec);

/* 将 3 字节打包（20/24 位）样本转为 int32，写入 out（out 为 int32*，交错） */
void alac_decoder_convert_3byte_to_s32(void* dec, const unsigned char* in,
                                       int32_t* out, unsigned int numFrames,
                                       unsigned int channels);

void alac_decoder_destroy(void* dec);

#ifdef __cplusplus
}
#endif

#endif /* ALAC_WRAPPER_H */
