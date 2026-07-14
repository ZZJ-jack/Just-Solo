cmake_minimum_required(VERSION 3.16)
project(JustSolo VERSION 0.1.0 LANGUAGES CXX)

# 指定 Qt 安装目录
set(Qt6_DIR "C:/Qt/6.8.3/msvc2022_64/lib/cmake/Qt6")
set(CMAKE_PREFIX_PATH "C:/Qt/6.8.3/msvc2022_64")

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

# 查找 Qt 6.8.3
find_package(Qt6 6.8.3 REQUIRED COMPONENTS
    Core
    Quick
    QuickControls2
    QuickLayouts
    Multimedia
    Network
)

qt_standard_project_setup()

# 启用 Qt 6.8+ 的 QML 新策略（消除 AUTHOR_WARNING，IDE 也会消标）
qt_policy(SET QTP0001 NEW)
qt_policy(SET QTP0004 NEW)

# 可执行文件
qt_add_executable(JustSolo WIN32
    src/main.cpp
    src/core/MusicManager.cpp
)

# QML 模块
qt_add_qml_module(JustSolo
    URI "JustSolo"
    VERSION 1.0
    QML_FILES
        src/qml/main.qml
    RESOURCES
        data/image/logo.png
        data/image/logo2.png
        data/image/home.png
        data/image/mylike.png
        data/image/history.png
        data/image/play.png
        data/image/playing.png
        data/font/HarmonyOS_Sans_SC_Regular.ttf
)

# 链接 Qt 库
target_link_libraries(JustSolo PRIVATE
    Qt6::Core
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::QuickLayouts
    Qt6::Multimedia
    Qt6::Network
)

# 输出目录
set_target_properties(JustSolo PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
)

# 每次编译自动生成版本号 (yymmddhhmmss)
add_custom_target(GenerateVersion ALL
    COMMAND powershell -ExecutionPolicy Bypass -File "${CMAKE_SOURCE_DIR}/cmake/GenerateVersion.ps1"
    COMMENT "Generating version header..."
    BYPRODUCTS "${CMAKE_SOURCE_DIR}/src/version.h"
)
add_dependencies(JustSolo GenerateVersion)
target_include_directories(JustSolo PRIVATE "${CMAKE_SOURCE_DIR}/src" "${CMAKE_SOURCE_DIR}/src/core")
