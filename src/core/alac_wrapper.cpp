/*
 * alac_wrapper.cpp —— Apple ALACDecoder (C++) 的 C 接口实现
 *
 * 包装 third_party/alac/codec 的参考解码器（Apache 2.0）。
 */
#include "alac_wrapper.h"

#include <stdint.h>

#include "ALACDecoder.h"
#include "ALACBitUtilities.h"

extern "C" void* alac_decoder_create(const unsigned char* cookie, unsigned int cookieSize)
{
    ALACDecoder* p = new ALACDecoder();
    if (p->Init(const_cast<void*>((const void*)cookie), cookieSize) != 0) {
        delete p;
        return nullptr;
    }
    return p;
}

extern "C" int alac_decoder_decode(void* dec, const unsigned char* in, unsigned int inBytes,
                                   unsigned char* out, unsigned int* inOutFrames,
                                   unsigned int* outBytes)
{
    ALACDecoder* p = static_cast<ALACDecoder*>(dec);
    BitBuffer bits;
    BitBufferInit(&bits, const_cast<unsigned char*>(in), inBytes);
    uint32_t outNumSamples = *inOutFrames;
    int32_t status = p->Decode(&bits, out, *inOutFrames, p->mConfig.numChannels, &outNumSamples);
    *inOutFrames = outNumSamples;
    *outBytes = outNumSamples * p->mConfig.numChannels * alac_decoder_bytes_per_sample(dec);
    return status;
}

extern "C" unsigned int alac_decoder_sample_rate(void* dec)
{
    return static_cast<ALACDecoder*>(dec)->mConfig.sampleRate;
}

extern "C" unsigned int alac_decoder_channels(void* dec)
{
    return static_cast<ALACDecoder*>(dec)->mConfig.numChannels;
}

extern "C" unsigned int alac_decoder_bit_depth(void* dec)
{
    return static_cast<ALACDecoder*>(dec)->mConfig.bitDepth;
}

extern "C" unsigned int alac_decoder_frame_length(void* dec)
{
    return static_cast<ALACDecoder*>(dec)->mConfig.frameLength;
}

extern "C" unsigned int alac_decoder_bytes_per_sample(void* dec)
{
    const ALACDecoder* p = static_cast<const ALACDecoder*>(dec);
    if (p->mConfig.bitDepth <= 16) return 2;
    if (p->mConfig.bitDepth <= 24) return 3;
    return 4;
}

extern "C" void alac_decoder_convert_3byte_to_s32(void* dec, const unsigned char* in,
                                                  int32_t* out, unsigned int numFrames,
                                                  unsigned int channels)
{
    ALACDecoder* p = static_cast<ALACDecoder*>(dec);
    const unsigned int bitDepth = p->mConfig.bitDepth;   /* 20 或 24 */
    /* 20/24 位样本左移到 32 位满刻度（否则音量被压缩到几乎无声） */
    const unsigned int shift = 32 - bitDepth;
    const unsigned int byteStride = 3 * channels;
    for (unsigned int i = 0; i < numFrames; i++) {
        for (unsigned int c = 0; c < channels; c++) {
            const unsigned char* s = in + (size_t)i * byteStride + c * 3;
            uint32_t v = (uint32_t)s[0] | ((uint32_t)s[1] << 8) | ((uint32_t)s[2] << 16);
            if (bitDepth == 20) {
                v &= 0xFFFFF;
                if (v & 0x80000) v |= 0xFFF00000;
            } else {
                if (v & 0x800000) v |= 0xFF000000;
            }
            out[(size_t)i * channels + c] = (int32_t)(v << shift);
        }
    }
}

extern "C" void alac_decoder_destroy(void* dec)
{
    delete static_cast<ALACDecoder*>(dec);
}
