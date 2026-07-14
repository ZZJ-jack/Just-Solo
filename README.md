# Just Solo

**轻量级桌面音乐播放器** —— 基于 Qt 6.8.3 + QML 构建。

**作者**: ZZJ-JACK ([zzjjack.us.kg](https://zzjjack.us.kg))

**仓库**: [GitCode](https://gitcode.com/ZZJ-JACK/Just-Solo) | [GitHub](https://github.com/ZZJ-jack/Just-Solo)

## 项目简介

Just Solo 是一款追求简洁、高性能的本地音乐播放器。采用 C++ 高性能核心 + QML 现代界面，无 Electron 依赖，内存占用低，启动迅速。

与常见的 Web 技术栈播放器相比：
- 内存占用 < 100MB（vs Electron 的 400MB+）
- 冷启动 < 0.5s
- 原生 GPU 渲染，60fps 流畅动画
- 完全自主的无边框窗口与自定义控件
- 基于 Qt 6.8.3 + QML，原生 C++ 高性能
- 无边框自定义窗口（最小化 / 最大化 / 关闭）
- 侧边栏导航（首页 / 收藏 / 历史）
- 设置页面（外观 / 软件更新 / 关于）
- 导入本地音乐，不移动文件、留在原目录
- 音乐列表展示（封面 / 标题 / 歌手 / 专辑 / 时长 五列对齐）
- 播放控制（播放 / 暂停 / 上一首 / 下一首）+ 进度条
- 底部播放栏：封面 / 进度条 / 当前时间 / 总时长 / 播放控制
- 支持一次添加多个文件，异步逐首解析，实时渲染
- 暗色滚动条，窗口缩放时列宽按比例自适应
- 音频直通输出，零衰减
- 软件版本号 + 构建时间戳双版本
- `--develop` 开发者模式（控制台 + 关闭窗口退出进程）
- HarmonyOS Sans 内置字体
- 灰色 / 青色暗色主题
- CMake 构建系统 + windeployqt 部署

---

## 技术栈

- **UI**: Qt Quick (QML), Qt QuickControls2, Qt QuickLayouts
- **后端**: C++17, Qt 6.8.3
- **构建**: CMake 3.16+, Visual Studio 2026 (MSVC)
- **字体**: HarmonyOS Sans SC

---

## 项目结构

```
Just-Solo/
├── CMakeLists.txt              # CMake 构建配置
├── .gitignore
├── README.md
├── run.ps1                     # 编译 + 部署 + 运行脚本
├── cmake/
│   └── GenerateVersion.ps1    # 自动生成版本号 (yymmddhhmmss)
├── src/
│   ├── main.cpp                # 程序入口
│   ├── core/
│   │   ├── MusicManager.h      # C++ 音乐管理器（播放/暂停/切歌/列表）
│   │   └── MusicManager.cpp
│   └── qml/
│       └── main.qml            # 主窗口 (所有 UI)
├── data/
│   ├── image/
│   │   ├── logo.png            # 程序图标
│   │   ├── logo2.png           # 侧边栏 Logo
│   │   ├── home.png            # 首页图标
│   │   ├── mylike.png          # 收藏图标
│   │   ├── history.png         # 历史图标
│   │   ├── play.png            # 播放按钮图标
│   │   └── playing.png         # 播放中指示图标
│   └── font/
│       └── HarmonyOS_Sans_SC_Regular.ttf
├── resources/
│   ├── fonts/                  # 备用字体目录
│   └── icons/                  # 备用图标目录
├── deploy/
│   ├── windows/                # Windows 部署配置
│   ├── macos/                  # macOS 部署配置
│   └── linux/                  # Linux 部署配置
└── tests/
    ├── unit/                   # 单元测试
    └── qml/                    # QML 测试
```

---

## 构建与运行

### 环境要求

| 依赖 | 说明 |
|------|------|
| Qt 6.8.3 | msvc2022_64 |
| CMake | 3.16+ |
| Visual Studio | 2022+ (含 MSVC 工具链) |

### 配置

```powershell
cmake -B build -G "Visual Studio 18 2026" -A x64 -DCMAKE_PREFIX_PATH="C:\Qt\6.8.3\msvc2022_64"
```

### 编译

```powershell
cmake --build build --config Release
```

### 运行

```powershell
.\run.ps1
```

或直接：

```powershell
& "build\bin\Release\JustSolo.exe"
```

开发者模式（附加控制台，关闭窗口自动退出）：

```powershell
& "build\bin\Release\JustSolo.exe" --develop
```

### 打包发布

```powershell
# 1. 构建 Release
cmake --build build --config Release

# 2. windeployqt 自动收集依赖
windeployqt build\bin\Release\JustSolo.exe --qmldir src\qml

# 3. 打包为 zip
Compress-Archive -Path build\bin\Release\* -DestinationPath JustSolo_v0.0.2-beta.1.zip -Force
```

---

## 当前功能

- 无边框自定义窗口（最小化 / 最大化 / 关闭）
- 侧边栏导航（首页 / 收藏 / 播放历史）
- 设置页面（外观 / 软件更新 / 关于）
  - 关于页：作者信息 / 项目地址 / 图标来源
  - 软件更新页：GitCode / GitHub 仓库链接
- 导入本地音乐（单选 / 多选），异步解析
- 音乐列表五列对齐：封面 / 标题 / 歌手 / 专辑 / 时长
- 播放控制（播放 / 暂停 / 上一首 / 下一首）
- 播放进度条 + 当前时间 / 总时长
- 底部播放栏：当前封面 / 进度条 / 时长 / 播放按钮
- 音频直通输出
- 开发者模式 `--develop`
- 灰色 / 青色暗色主题
- HarmonyOS Sans 内置字体
- CMake 构建系统 + windeployqt 部署

---

## 更新日志

### v0.0.1-beta.1

> 项目初始化，搭建 Qt 6 + QML 无边框窗口框架与侧边栏导航。

- 无边框自定义窗口（最小化/最大化/关闭）
- 侧边栏导航（首页 / 收藏 / 历史）
- 自定义 NavItem 组件（图标 + 文字）
- 内容区标题随页面切换 + 对应图标
- 搜索框（UI 占位）
- 底部播放栏（UI 占位）
- 灰色/青色暗色主题
- HarmonyOS Sans 内置字体
- CMake 构建系统 + windeployqt 部署

### v0.0.1-beta.2

> 新增版本号系统与设置页面，优化侧边栏与窗口体验。

- 新增软件版本号系统（`0.0.1-beta.2`）与构建时间戳双版本
- 新增设置页面（外观 / 软件更新 / 关于 子菜单）
- 软件更新页显示软件版本 + 构建版本 + 检查更新按钮
- 侧边栏优化：整体左移、布局对齐调整
- 窗口顶部全宽区域支持拖动
- 修复 QML `mouse` 参数声明警告
- README 精简为项目实际内容

### v0.0.2-beta.1（已发行）

> 首个已发行预览版：C++ 音乐管理器、QMediaPlayer 元数据解析、播放控制、进度条、多文件导入与完整 UI 交互。

**新增**
- C++ MusicManager 模块：播放 / 暂停 / 上一首 / 下一首 / 播放列表管理
- 基于 `QMediaPlayer::metaData` 的元数据提取（标题 / 歌手 / 专辑 / 封面），兼容 MP3 / FLAC / M4A
- 封面提取流程：嵌入封面 → 缓存 JPEG → `QUrl::fromLocalFile()`，底部栏实时显示
- 播放进度条 + 当前时间 / 总时长，`durationChanged` 信号确保就绪后更新
- 支持一次添加多个音乐文件（`FileDialog.OpenFiles`），异步队列逐首解析，实时渲染不卡 UI
- 音乐列表五列对齐，共享属性（`colCover/Title/Artist/Album/Duration/Play` + `colSpacing` + `colPlayIconSize`），改一处全局生效
- 播放进度条取代音量控制，布局：上/下首 | 播放 | 封面 | 进度条 + 时长
- 暗色滚动条（`Basic` 风格，屏蔽系统悬浮/拖拽变色）
- 音频直通输出（`setVolume(1.0)`，无 DSP / 均衡器）
- 开发者模式 `--develop`：附加控制台，关闭窗口自动退出进程
- play.png / playing.png 替换文字图标；列表行点击播放/暂停切换
- 软件更新页：检查更新按钮暂禁用，GitCode / GitHub 仓库链接（可点击跳转）
- 关于页：项目地址（GitCode + GitHub）、图标来源声明（鸿蒙开发者 `developer.huawei.com`）
- 关于页新增作者信息：ZZJ-JACK（`https://zzjjack.us.kg`）

**变更**
- 窗口标题简化为 "Just Solo"（任务管理器同步）
- 底部栏添加防穿透层，点击空白区域不触发后方歌曲列表
- 行高亮改为 `musicManager.currentIndex`（播放中）和鼠标悬浮，无播放时首行不高亮
- 列间距独立全局变量，滚动条紧贴右边缘
- 所有链接显示文本统一加 `https://` 前缀
- README 全面更新：项目结构、功能列表、打包命令、作者信息、仓库链接
- 版本号升至 v0.0.2-beta.1

**修复**
- 封面加载时序：`metaDataChanged` debounce + 兜底超时，确保异步元数据就绪后提取
- 滚动条锁死问题：经多轮调试，最终选型系统 ScrollBar + Basic 风格
- 多文件添加时滚动条卡顿：异步队列 + `processEvents` 让出事件循环
- 进度条 duration 显示：`durationChanged` 信号替代直接读取

---

## 许可证

MIT License

Copyright (c) 2026 - NOW ZZJ-JACK

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
