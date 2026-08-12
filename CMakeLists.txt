cmake_minimum_required(VERSION 3.16)
project(JustSolo VERSION 0.1.0 LANGUAGES CXX)

# ---- 软件版本号 ----
set(APP_VERSION_MAJOR 1)   # X：主版本号
set(APP_VERSION_MINOR 3)   # Y：次版本号
set(APP_VERSION_PATCH 0)   # Z：修订版本号
set(APP_VERSION_PRE   8)   # N：0=正式版, >0=beta.N
# 版本号格式: vX.Y.Z-beta.N

# 格式化显示版本: vX.Y.Z 或 vX.Y.Z-beta.N
if(APP_VERSION_PRE GREATER 0)
    set(APP_VERSION_DISPLAY "v${APP_VERSION_MAJOR}.${APP_VERSION_MINOR}.${APP_VERSION_PATCH}-beta.${APP_VERSION_PRE}")
else()
    set(APP_VERSION_DISPLAY "v${APP_VERSION_MAJOR}.${APP_VERSION_MINOR}.${APP_VERSION_PATCH}")
endif()
message(STATUS "App version: ${APP_VERSION_DISPLAY}")

# ---- Just Solo LyricServer 协议版本号 ----
set(LYRICSERVER_PROTOCOL_VERSION_MAJOR 1)
set(LYRICSERVER_PROTOCOL_VERSION_MINOR 1)
set(LYRICSERVER_PROTOCOL_VERSION_PATCH 0)
set(LYRICSERVER_PROTOCOL_PRE_TIME 400)
set(LYRICSERVER_PROTOCOL_VERSION "v${LYRICSERVER_PROTOCOL_VERSION_MAJOR}.${LYRICSERVER_PROTOCOL_VERSION_MINOR}.${LYRICSERVER_PROTOCOL_VERSION_PATCH}")
message(STATUS "LyricServer protocol: ${LYRICSERVER_PROTOCOL_VERSION}")

# 指定 Qt 安装目录
set(Qt6_DIR "C:/Qt/6.8.3/msvc2022_64/lib/cmake/Qt6")
set(CMAKE_PREFIX_PATH "C:/Qt/6.8.3/msvc2022_64")

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

# 避免因缺少 Vulkan SDK 导致 CMake 配置卡住
set(CMAKE_DISABLE_FIND_PACKAGE_Vulkan TRUE)
# Qt 6.8+ Quick 模块内部对 WrapVulkanHeaders 的检查（不归 CMAKE_DISABLE_FIND_PACKAGE 管）
set(QT_QUICK_NO_VULKAN_CHECK ON CACHE BOOL "" FORCE)

# 查找 Qt 6.8.3
find_package(Qt6 6.8.3 REQUIRED COMPONENTS
    Core
    Quick
    QuickControls2
    QuickLayouts
    Multimedia
    Network
    WebSockets
    Widgets
)

qt_standard_project_setup()

# 启用 Qt 6.8+ 的 QML 新策略（消除 AUTHOR_WARNING，IDE 也会消标）
qt_policy(SET QTP0001 NEW)
qt_policy(SET QTP0004 NEW)

# ---- cmark-gfm（Markdown → HTML 渲染）----
# cmark-gfm 的 cmake_minimum_required 版本较旧，新版 CMake 需设置此策略避免报错
set(CMAKE_POLICY_VERSION_MINIMUM 3.5)
include(FetchContent)
# 使用本地已下载的源码，避免每次从 GitHub 克隆（国内网络慢）
set(FETCHCONTENT_SOURCE_DIR_CMARK-GFM "${CMAKE_SOURCE_DIR}/third_party/cmark-gfm-0.29.0.gfm.13" CACHE PATH "Local cmark-gfm source")
FetchContent_Declare(cmark-gfm
    GIT_REPOSITORY https://github.com/github/cmark-gfm.git
    GIT_TAG 0.29.0.gfm.13
)
set(CMARK_THREADING OFF CACHE BOOL "" FORCE)
set(CMARK_SHARED OFF CACHE BOOL "" FORCE)
set(CMARK_TESTS OFF CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(cmark-gfm)

# 抑制 cmark-gfm 源码的 C4819 警告（UTF-8 字符在 GBK 代码页下触发）
if(MSVC)
    target_compile_options(libcmark-gfm_static PRIVATE /wd4819)
    target_compile_options(libcmark-gfm-extensions_static PRIVATE /wd4819)
endif()

# ---- 音频解码扩展：Opus（libogg/libopus/libopusfile）与 AAC（fdk-aac） ----
# 全部编译为静态库，作为 miniaudio 自定义解码后端（见 src/core/decoder_backends.h，
# 由 AudioEngine 注册到引擎的 resource manager）。库源码位于 third_party/。
set(BUILD_SHARED_LIBS OFF CACHE BOOL "Build shared libraries" FORCE)
set(OPUS_BUILD_TESTING OFF CACHE BOOL "" FORCE)
set(OPUS_BUILD_PROGRAMS OFF CACHE BOOL "" FORCE)
set(OPUS_INSTALL_PKG_CONFIG_MODULE OFF CACHE BOOL "" FORCE)
set(FDK_AAC_INSTALL_CMAKE_CONFIG_MODULE OFF CACHE BOOL "" FORCE)
set(FDK_AAC_INSTALL_PKGCONFIG_MODULE OFF CACHE BOOL "" FORCE)

# libopus：官方 CMake 构建（目标名 opus），内部自行生成配置头
add_subdirectory(third_party/opus)

# libogg：仅两个源文件，直接编译，避免外部包查找
add_library(ogg STATIC
    third_party/ogg/src/bitwise.c
    third_party/ogg/src/framing.c
)
target_include_directories(ogg PUBLIC third_party/ogg/include)

# libopusfile：直接编译源码（OP_DISABLE_HTTP 关闭网络功能，仅需本地文件解码）
add_library(opusfile STATIC
    third_party/opusfile/src/info.c
    third_party/opusfile/src/internal.c
    third_party/opusfile/src/opusfile.c
    third_party/opusfile/src/stream.c
)
target_include_directories(opusfile PUBLIC third_party/opusfile/include)
target_compile_definitions(opusfile PRIVATE OP_DISABLE_HTTP)
target_compile_options(opusfile PRIVATE $<$<C_COMPILER_ID:MSVC>:/wd4267> $<$<C_COMPILER_ID:MSVC>:/wd4244> $<$<C_COMPILER_ID:MSVC>:/wd4090>)
target_link_libraries(opusfile PUBLIC ogg opus)

# fdk-aac：官方 CMake 构建（目标名 fdk-aac），含 AAC 解码库
add_subdirectory(third_party/fdk-aac)

# ALAC（Apple Lossless）：苹果参考解码器（Apache 2.0），.m4a 无损格式
add_library(alac STATIC
    third_party/alac/codec/ALACDecoder.cpp
    third_party/alac/codec/ALACBitUtilities.c
    third_party/alac/codec/ag_dec.c
    third_party/alac/codec/dp_dec.c
    third_party/alac/codec/matrix_dec.c
    third_party/alac/codec/EndianPortable.c
)
target_include_directories(alac PUBLIC third_party/alac/codec)

# SoundTouch：时间拉伸/变速不变调（音调补偿）。浮点采样 + x64 SSE 优化；
# 仅编译核心库（不含 BPMDetect/SoundStretch），MMX 优化在 float/x64 下不生效故省略。
add_library(soundtouch STATIC
    third_party/soundtouch/SoundTouch.cpp
    third_party/soundtouch/TDStretch.cpp
    third_party/soundtouch/RateTransposer.cpp
    third_party/soundtouch/FIRFilter.cpp
    third_party/soundtouch/AAFilter.cpp
    third_party/soundtouch/FIFOSampleBuffer.cpp
    third_party/soundtouch/InterpolateLinear.cpp
    third_party/soundtouch/InterpolateCubic.cpp
    third_party/soundtouch/InterpolateShannon.cpp
    third_party/soundtouch/cpu_detect_x86.cpp
    third_party/soundtouch/sse_optimized.cpp
)
target_include_directories(soundtouch PUBLIC third_party/soundtouch)

# 抑制第三方音频库的 C4819 警告（UTF-8 注释）
if(MSVC)
    target_compile_options(ogg PRIVATE /wd4819)
    target_compile_options(opusfile PRIVATE /wd4819)
    target_compile_options(opus PRIVATE /wd4819)
    target_compile_options(fdk-aac PRIVATE /wd4819)
    target_compile_options(alac PRIVATE /wd4819)
    target_compile_options(soundtouch PRIVATE /wd4819)
endif()

# 可执行文件
qt_add_executable(JustSolo WIN32
    src/main.cpp
    src/core/AudioEngine.cpp
    src/core/TimeStretchSource.cpp
    src/core/ma_opus_decoder.c
    src/core/ma_fdkaac_decoder.c
    src/core/alac_wrapper.cpp
    src/core/MusicManager.cpp
    src/core/MetadataReader.cpp
    src/core/SMTCManager.cpp
    src/core/HotkeyManager.cpp
    src/core/UpdateChecker.cpp
    src/core/MarkdownHelper.h
    src/core/MarkdownHelper.cpp
    src/core/CurlRequest.h
    src/core/CurlRequest.cpp
    src/core/BugReporter.h
    src/core/BugReporter.cpp
    src/services/LyricServer.cpp
    src/services/LyricServer.h
    resources/app.rc
)

# QML 模块
qt_add_qml_module(JustSolo
    URI "JustSolo"
    VERSION 1.0
    QML_FILES
        src/qml/main.qml
        src/qml/components/NavItem.qml
        src/qml/components/SubNavItem.qml
        src/qml/components/SongRow.qml
        src/qml/components/MusicListView.qml
        src/qml/components/ToggleSwitch.qml
        src/qml/views/HomePage.qml
        src/qml/views/PlaylistPage.qml
        src/qml/views/FavoritePage.qml
        src/qml/views/HistoryPage.qml
        src/qml/views/SettingsPage.qml
        src/qml/views/PlayerDetailPage.qml
        src/qml/views/MiniPlayer.qml
    RESOURCES
        data/image/logo.png
        data/image/logo2.png
        data/image/logo.ico
        data/image/home.png
        data/image/AllMusic.png
        data/image/menu.png
        data/image/mylike.png
        data/image/mylike-on.png
        data/image/mylike-off.png
        data/image/history.png
        data/image/play.png
        data/image/playing.png
        data/image/mode_sequential.png
        data/image/mode_loop.png
        data/image/mode_single.png
        data/image/mode_shuffle.png
        data/image/mode_stop.png
        data/image/PlayList.png
        data/image/singer_list.png
        data/image/AddToPlayList.png
        data/image/creatList.png
        data/image/drag.png
        data/image/volume-logo.png
        data/image/setting.png
        data/image/back.png
        data/image/prve.png
        data/image/next.png
        data/image/mini-enter.png
        data/image/mini-exit.png
        data/image/Biggest-enter.png
        data/image/Biggest-exit.png
        data/image/speed_change.png
)

# ---- 内置字体（大文件）：编译为二进制资源 .rcc，运行时注册 ----
# 字体总量约 51MB，若嵌入 qrc 会让生成的 C++ 数组超出 MSVC 堆上限（C1060），
# 因此用 rcc --binary 生成 .rcc 文件，启动时通过 QResource::registerResource 注册。
qt_add_binary_resources(JustSolo_fonts
    data/font/fonts.qrc
    DESTINATION "${CMAKE_CURRENT_BINARY_DIR}/fonts.rcc"
)
# 保证 rcc 先于 exe 编译完成（POST_BUILD 复制需要该文件）
add_dependencies(JustSolo JustSolo_fonts)
# 复制 .rcc 到 exe 输出目录，程序运行时从同目录加载
add_custom_command(TARGET JustSolo POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
        "${CMAKE_CURRENT_BINARY_DIR}/fonts.rcc"
        "$<TARGET_FILE_DIR:JustSolo>"
    COMMENT "Copying fonts.rcc to output directory"
)

# 链接 Qt 库
target_link_libraries(JustSolo PRIVATE
    Qt6::Core
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::QuickLayouts
    Qt6::Multimedia
    Qt6::Network
    Qt6::WebSockets
    Qt6::Widgets
    libcmark-gfm_static
    libcmark-gfm-extensions_static
    opusfile        # libopusfile（Opus 解码，PUBLIC 传递 ogg + opus）
    fdk-aac         # fdk-aac（AAC 解码）
    alac            # 苹果 ALAC 参考解码器（.m4a 无损）
    soundtouch      # 时间拉伸（变速不变调/音调补偿）
)
target_include_directories(JustSolo PRIVATE
    "${cmark-gfm_SOURCE_DIR}/src"
    "${cmark-gfm_BINARY_DIR}/src"
    "${cmark-gfm_SOURCE_DIR}/extensions"
    "${cmark-gfm_BINARY_DIR}/extensions"
)

# Windows: DWM API + runtimeobject (SMTC) + shell32 (AUMID) + ole32 (WASAPI 会话枚举) + dxgi (GPU 探测)
if(WIN32)
    target_link_libraries(JustSolo PRIVATE dwmapi runtimeobject shlwapi shcore shell32 ole32 dxgi)
endif()

# ---- libcurl（用于软件更新检查，替代 Qt 网络栈）----
# 使用项目内 third_party 依赖，不依赖外部路径
set(CURL_DIR "${CMAKE_SOURCE_DIR}/third_party/curl")
target_include_directories(JustSolo PRIVATE "${CURL_DIR}/include")
target_link_libraries(JustSolo PRIVATE "${CURL_DIR}/lib/libcurl-x64.lib")
# 运行时复制 DLL 到输出目录
add_custom_command(TARGET JustSolo POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
        "${CURL_DIR}/bin/libcurl-x64.dll"
        "$<TARGET_FILE_DIR:JustSolo>"
    COMMENT "Copying libcurl-x64.dll to output directory"
)

# 输出目录
set_target_properties(JustSolo PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
)

# 每次编译自动生成版本号: $ts-$machineId-vX.Y.Z
add_custom_target(GenerateVersion ALL
    COMMAND powershell -ExecutionPolicy Bypass -File "${CMAKE_SOURCE_DIR}/cmake/GenerateVersion.ps1"
        -Version "${APP_VERSION_DISPLAY}"
    COMMENT "Generating version header..."
    BYPRODUCTS "${CMAKE_SOURCE_DIR}/src/version.h"
)
add_dependencies(JustSolo GenerateVersion)
target_include_directories(JustSolo PRIVATE "${CMAKE_SOURCE_DIR}/src" "${CMAKE_SOURCE_DIR}/src/core")

# 版本号从 CMake 传入源码（单一定义源）
target_compile_definitions(JustSolo PRIVATE
    APP_VERSION_DISPLAY="${APP_VERSION_DISPLAY}"
    LYRICSERVER_PROTOCOL_VERSION="${LYRICSERVER_PROTOCOL_VERSION}"
    LYRICSERVER_PROTOCOL_PRE_TIME=${LYRICSERVER_PROTOCOL_PRE_TIME}
)