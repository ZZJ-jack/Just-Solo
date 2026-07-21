# Just Solo
<div align="center">

<img src="./data/image/logo.png" alt="Just Solo" width="200" />

**Just Solo** —— 纯粹轻量的本地音乐播放器

[![Qt](https://img.shields.io/badge/Qt-6.8.3-brightgreen?logo=qt)](https://www.qt.io)
[![C++](https://img.shields.io/badge/C++-17-blue?logo=cplusplus)](https://isocpp.org)
[![QML](https://img.shields.io/badge/QML-6.8-orange?logo=qt)](https://doc.qt.io/qt-6/qmlapplications.html)
[![CMake](https://img.shields.io/badge/CMake-3.20+-064F8C?logo=cmake)](https://cmake.org)
[![License](https://img.shields.io/badge/License-MIT-yellow?logo=opensourceinitiative)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Windows-0078D6?logo=windows)](https://www.microsoft.com/windows)

</div>

<img src="./data/image/photo-1.png" alt="Photo 1"/>

<font size="1">PS：本示范图片仅用于展示功能，歌曲版权属于原作者</font>

## **轻量级本地音乐播放器** —— 基于 Qt 6.8.3 + QML 构建。

### **作者**: ZZJ-JACK ([zzjjack.us.kg](https://zzjjack.us.kg))

### **仓库**: [GitCode](https://gitcode.com/ZZJ-JACK/Just-Solo) | [Gitee](https://gitee.com/zzj-jack/just-solo) | [GitHub](https://github.com/ZZJ-jack/Just-Solo)

### 暂时仅支持 Windows 平台，如需下载，前往 Releases 下载最新 .exe 安装包。

## 项目简介

Just Solo 是一款追求简洁、高性能的本地音乐播放器。采用 C++ 高性能核心 + QML 现代界面，无 Electron 依赖，内存占用低，冷启动迅速。

同时，Just Solo 已原生支持 Windows SMTC 系统媒体控件，可配合 [NSD 灵动岛工具](https://github.com/GEORGEWWWU/NetSpeed-Dynamic)（由 [Ryenryen大佬](https://github.com/GEORGEWWWU) 开发）显示音乐信息与控制播放（暂请将目标音乐平台设置成通用音频）。

**性能**
- 平均内存占用 < 150MB（vs Electron 的 500MB+）
- 冷启动 < 0.5s
- 原生 GPU 渲染，60fps 流畅动画
- `MetadataReader` 二进制解析（~1ms/文件），批处理 10 文件/轮
- 歌词预编译缓存：QVariantMap 深拷贝 → 纯整数数组，播放时零分配

**外观**
- 完全自主的无边框窗口与自定义控件
- 最小化 / 最大化 / 关闭，悬停 ToolTip
- 灰色 / 青色暗色主题
- HarmonyOS Sans 内置字体，统一 UI 元素
- 全 UI 自适应布局，所有尺寸随窗口大小弹性变化
- 暗色滚动条，音乐列表列宽按比例分配
- exe 图标内嵌（`app.rc` + `logo.ico`）

**核心功能**
- 侧边栏导航（首页 / 播放列表 / 收藏 / 历史）
- 播放控制（播放 / 暂停 / 上一首 / 下一首）+ 进度条
- 5 种播放模式（顺序 / 列表循环 / 单曲循环 / 随机 / 关闭循环）
- Windows 系统媒体控件 SMTC（任务栏音量弹窗 / 锁屏 / 蓝牙设备）
- 导入本地音乐，不移动文件、留在原目录
- 音乐搜索：标题/歌手/专辑模糊匹配，关键词高亮显示，结果点击播放+列表自动滚动定位
- 音乐列表展示（封面 / 标题 / 歌手 / 专辑 / 时长 五列对齐）
- 底部播放栏：封面 + 歌名/歌手 + 控制按钮 + 进度条
- 添加文件自动去重（路径跳过 / 同歌保留高音质）
- 音频直通输出，10% 余量防削波
- 音乐收藏：收藏/取消收藏，持久化到 `favorites_cache.json`
- 播放历史：自动记录，去重上限 500 条，持久化恢复
- 最大化窗口拖拽还原：任意位置点击均能准确定位到鼠标

**播放详情页**
- 点击封面全屏打开，毛玻璃背景（`ShaderEffectSource` + `MultiEffect`）
- 三色逐字高亮歌词：已播=黄、当前=青大号、未播=蓝
- 两段式滚动：下一句先放大预显示，再滚动到位
- 双语字幕：`.lrc` 外部文件 + FLAC 嵌入双路支持，同时间戳自动合并
- 歌名超长横向 marquee 滚动，歌词 WordWrap 自动换行
- 底部进度条可拖动 seek，透明度可调持久化

**工程**
- 基于 Qt 6.8.3 + QML，原生 C++ 高性能
- CMake 构建系统 + windeployqt 部署
- 软件版本号 + 构建时间戳双版本号系统
- 内置 `--develop` 开发者模式（提供控制台输出，方便调试）

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
├── LICENSE                     # MIT 许可证
├── README.md
├── 安装说明.txt                 # 安装与部署说明
├── run.ps1                     # 编译 + 部署 + 运行脚本
├── package.ps1                 # 一键打包脚本
├── cmake/
│   └── GenerateVersion.ps1    # 自动生成版本号
├── src/
│   ├── main.cpp                # 程序入口（DWM 标题栏、SMTC、HotkeyManager 初始化）
│   ├── version.h               # 构建时间戳版本号（由 GenerateVersion.ps1 生成）
│   ├── core/
│   │   ├── MusicManager.h/cpp     # 音乐管理器（播放/列表/收藏/历史/设置/播放模式）
│   │   ├── MetadataReader.h/cpp   # 元数据快速解析（MP3/FLAC/M4A）
│   │   ├── SMTCManager.h/cpp      # Windows 系统媒体控件（SMTC）
│   │   └── HotkeyManager.h/cpp    # 全局快捷键管理器
│   ├── common/.gitkeep
│   ├── services/.gitkeep
│   └── qml/
│       ├── main.qml            # 主窗口 —— 侧边栏、播放栏、路由控制
│       ├── components/
│       │   ├── NavItem.qml     #   侧边栏主菜单项
│       │   ├── SubNavItem.qml  #   设置页子菜单项
│       │   └── SongRow.qml     #   歌曲列表行共享组件
│       └── views/              # 页面（预创建，切换时仅切换 visible）
│           ├── HomePage.qml        # 首页 —— 音乐列表
│           ├── PlaylistPage.qml    # 播放列表页
│           ├── FavoritePage.qml    # 收藏页
│           ├── HistoryPage.qml     # 历史页
│           ├── SettingsPage.qml    # 设置页
│           └── PlayerDetailPage.qml# 播放详情页
├── data/
│   ├── image/
│   │   ├── logo.ico / logo.png / logo2.png  # 程序图标
│   │   ├── home.png / mylike.png / history.png / PlayList.png / AddToPlayList.png # 导航图标
│   │   ├── play.png / playing.png           # 播放控制图标
│   │   ├── mode_sequential.png / mode_loop.png / mode_single.png / mode_shuffle.png / mode_stop.png # 播放模式图标
│   │   └── backgroud.png       # 背景图
│   └── font/
│       └── HarmonyOS_Sans_SC_Regular.ttf    # 字体文件（HarmonyOS Sans SC 正常字型）
├── resources/
│   ├── app.rc                  # Windows 资源文件（嵌入 ico）
│   ├── fonts/.gitkeep
│   └── icons/.gitkeep
└── release/                    # 打包输出目录
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

或直接：（使用已编译好的）

```powershell
& "build\bin\Release\JustSolo.exe"
```

开发者模式（附加控制台）：

```powershell
& "build\bin\Release\JustSolo.exe" --develop
```

### 打包发布

```powershell
# 一键编译 + windeployqt → release/
.\package.ps1
```

---

## 当前功能

- 无边框自定义窗口（最小化 / 最大化 / 关闭，悬停 ToolTip）
- 侧边栏导航（首页 / 播放列表 / 收藏 / 播放历史）
- 设置页面（外观设置 / 播放设置 / 快捷键设置 / 软件更新 / 关于 JustSolo）
  - 外观设置：播放详情页透明度滑块、模式菜单透明度滑块
  - 播放设置：歌词预读偏移滑块（±5ms 步长，持久化）、跨来源跟踪开关
  - 快捷键设置：全局快捷键自定义捕获界面，支持播放/暂停、上一首、下一首
  - 关于页：作者信息 / 项目地址 / 运行环境 / 图标来源
  - 软件更新页：GitCode / GitHub 仓库链接
- Windows 系统媒体控件 (SMTC)：任务栏音量弹窗 / 锁屏 / 蓝牙显示歌名歌手封面
- 导入本地音乐（单选 / 多选），`MetadataReader` 加速解析，**自动去重**
  - 同一文件路径跳过
  - 不同文件同一首歌保留音质更高版本
  - 多歌手分隔符统一（`/ ; |` → `、`）
- **音乐搜索**：输入实时过滤标题/歌手/专辑，关键词青色加粗高亮，下拉结果行超长 marquee 滚动
  - 全部页面可搜，结果点击切到首页播放并自动滚动列表定位
- 音乐列表五列对齐，**列宽随窗口自适应**：封面 / 标题 / 歌手 / 专辑 / 时长
- 标题行显示音质标签（极低 / 标准 / 高品质 / 无损 / 高解析 / 母带 / 空间音频）
- 播放控制（播放 / 暂停 / 上一首 / 下一首）
- 全局快捷键：`Ctrl+Alt+Space` 播放/暂停，`Ctrl+Alt+←→` 上下首（快捷键设置页可自定义）
- 5 种播放模式（顺序 / 列表循环 / 单曲循环 / 随机 / 关闭循环）
- 播放进度条（支持点击拖动 seek）+ 当前时间 / 总时长
- 底部播放栏：封面 + 歌名/歌手自适应填充 + 控制按钮 + 进度条（固定窗口 1/3）
- **播放详情页**：点击封面打开，毛玻璃背景 + 封面/歌名/歌手/专辑 + 逐字高亮歌词
  - 三色方案：已播=黄 / 当前=青（58px）/ 未播=蓝
  - 两段式滚动：下一句先放大预显示，再滚动到位
  - 歌词 WordWrap 自动换行，行间平滑滚动
  - 透明度可调持久化
- **双语字幕**：`.lrc` 外部文件 + FLAC 嵌入 `LYRICS` 双路支持，同时间戳自动合并
- 音频直通输出
- 开发者模式 `--develop`
- 灰色 / 青色暗色主题
- HarmonyOS Sans 内置字体
- exe 图标内嵌（`app.rc` + `logo.ico`）
- 进程完全退出（`shutdown()` + `QCoreApplication::exit(0)`）
- 最大化拖拽还原精准跟随鼠标

---

## 最新版本更新日志（其他详见 `CHANGELOG.md`）

### v0.5.1：新增关闭最小化到系统托盘功能，设置页可自由开关。
#### 关闭窗口自动最小化到系统托盘，音乐继续后台播放
#### 右键托盘图标菜单：显示主窗口 / 退出
#### 左键/双击托盘图标恢复窗口
#### 设置 → 外观 新增开关，默认关闭，持久化重启保持
#### 引入 Qt::Widgets 模块（QSystemTrayIcon 依赖）

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
