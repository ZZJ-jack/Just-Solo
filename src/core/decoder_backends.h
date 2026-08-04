/*
 * decoder_backends.h —— miniaudio 自定义解码后端注册接口
 *
 * 通过 miniaudio 的 ma_decoding_backend_vtable 机制为 AudioEngine 增加
 * miniaudio 内置解码器之外的格式支持：
 *   - Opus（.opus）        基于 libopus + libopusfile
 *   - AAC（.aac / .m4a）   基于 fdk-aac（ADTS 裸流 + MP4 容器解封装）
 *
 * 注册方式：将下面的 vtable 指针填入 ma_resource_manager_config 的
 * ppCustomDecodingBackendVTables 数组，再通过 ma_engine_config.pResourceManager
 * 交给引擎。
 */
#ifndef DECODER_BACKENDS_H
#define DECODER_BACKENDS_H

#include "miniaudio.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Opus 解码后端 vtable（libopusfile）。仅实现 onInit，miniaudio 通过 VFS
 * 回调（read/seek/tell）驱动，可正确处理中文/Unicode 文件路径。 */
extern ma_decoding_backend_vtable* ma_decoding_backend_libopus;

/* AAC 解码后端 vtable（fdk-aac）。支持 .aac（ADTS）与 .m4a/.mp4（MP4 容器）。 */
extern ma_decoding_backend_vtable* ma_decoding_backend_fdkaac;

#ifdef __cplusplus
}
#endif

#endif /* DECODER_BACKENDS_H */
