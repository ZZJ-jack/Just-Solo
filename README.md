# Just Solo

<div align="center">

<img src="./data/image/logo.png" alt="Just Solo" width="200" />

**Just Solo** —— 纯粹轻量的播放器

[![Qt](https://img.shields.io/badge/Qt-6.8.3-brightgreen?logo=qt)](https://www.qt.io)
[![C++](https://img.shields.io/badge/C++-17-blue?logo=cplusplus)](https://isocpp.org)
[![QML](https://img.shields.io/badge/QML-6.8-orange?logo=qt)](https://doc.qt.io/qt-6/qmlapplications.html)
[![CMake](https://img.shields.io/badge/CMake-3.20+-064F8C?logo=cmake)](https://cmake.org)
[![License](https://img.shields.io/badge/License-MIT-yellow?logo=opensourceinitiative)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Windows-0078D6?logo=windows)](https://www.microsoft.com/windows)

</div>

<img src="./data/image/photo-1.png" alt="Photo 1" width="200" />

**轻量级桌面音乐播放器** —— 基于 Qt 6.8.3 + QML 构建。

**作者**: ZZJ-JACK ([zzjjack.us.kg](https://zzjjack.us.kg))

**仓库**: [GitCode](https://gitcode.com/ZZJ-JACK/Just-Solo) | [Gitee](https://gitee.com/zzj-jack/just-solo) | [GitHub](https://github.com/ZZJ-jack/Just-Solo)

### 下载即用：前往 Releases 下载最新 .exe 安装包，双击即可使用。

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

## 更新日志

### v0.0.1-beta.1 - 2026.7.12

> v0.0.1-beta.1，项目初始化，搭建 Qt 6 + QML 无边框窗口框架与侧边栏导航。

**新增**
- 无边框自定义窗口（最小化 / 最大化 / 关闭），保留 Alt+Tab 系统行为
- 侧边栏导航（首页 / 收藏 / 历史），支持页面切换
- 自定义 NavItem 组件（图标 + 文字），支持悬浮高亮与激活态
- 内容区标题随页面切换 + 对应图标
- 搜索框 UI 占位
- 底部播放栏 UI 占位
- 灰色 / 青色暗色主题配色方案

**基础建设**
- HarmonyOS Sans 内置字体
- CMake 构建系统 + windeployqt 部署
- Git 工作流与 .gitignore

### v0.0.1-beta.2 - 2026.7.13

> v0.0.1-beta.2，新增版本号系统与设置页面，优化侧边栏与窗口体验。

**新增**
- 软件版本号系统（`0.0.1-beta.2`）与构建时间戳双版本显示
- 设置页面（外观 / 软件更新 / 关于 三个子菜单）
- SubNavItem 可复用组件（设置子导航项）
- 软件更新页：显示软件版本 + 构建版本 + 检查更新按钮
- 关于页：项目信息与链接

**优化**
- 侧边栏布局整体左移、间距与对齐调整
- 窗口顶部 70px 全宽区域支持鼠标拖拽移动窗口
- README 精简为项目实际内容

**修复**
- QML `mouse` 参数声明警告

### v0.0.2-beta.1（已发行） - 2026.7.14

> v0.0.2-beta.1，首个已发行预览版：C++ 音乐管理器、QMediaPlayer 元数据解析、播放控制、进度条、多文件导入与完整 UI 交互。

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
- 关于页：项目地址（GitCode + GitHub）、图标来源声明（鸿蒙开发者）
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

### v0.0.2-beta.2 - 2026.7.15

> v0.0.2-beta.2，自适应布局重构、歌曲去重并补充全量注释。

**新增**
- 添加歌曲自动去重：
  - 同一文件路径重复选择自动跳过
  - 不同文件但同一首歌（同名+同歌手）自动比较音质等级，保留更高版本
  - 若当前正在播放的歌曲被替换为高音质版本，自动切换音源继续播放
- 全部 UI 自适应窗口大小，所有尺寸随窗口弹性变化
- main.qml 补充全量中英文注释，覆盖每个模块的设计意图与布局策略

**优化**
- 音乐列表列宽根据窗口可用宽度动态按百分比分配（标题35% / 歌手25% / 专辑25% / 时长15%），带最小宽度保护
- 搜索框宽度自适应：基于窗口宽度 35%，最小 200px，最大 420px
- 版本信息卡片改为自适应宽度（`Layout.fillWidth` + 最大 520px）
- 播放栏进度条宽度自适应：最小 180px，最大取播放栏可用宽度的 25%
- 底部栏歌名和歌手区域移除 160px 最大宽度限制，自动填充剩余空间

**修复**
- 音乐列表标题在上、音质标签在下左对齐（原为右下角）
- 播放栏左侧固定 240px 导致宽窗口出现大量留白，改为自适应填充
- 列表底部内容被 72px 播放栏遮挡，`bottomMargin` 从 30px 调整为 `playerBarHeight + 14`

### v0.3.0-beta.1（已作为首个正式版本发行） - 2026.7.15

> 代码架构重构为多文件模块化，新增收藏、播放历史及全量数据本地存储。
> 本版本作为首个正式版本发行，包含所有主要功能（暂缺播放详情页）。

**新增**

**代码重构**
- 所有页面视图从 `main.qml` 内联组件拆分为独立 QML 文件：`src/qml/views/{HomePage,FavoritePage,HistoryPage,SettingsPage}.qml`
- `NavItem` / `SubNavItem` 组件拆分为独立文件：`src/qml/components/{NavItem,SubNavItem}.qml`
- 清理 `.gitkeep` 占位文件

**音乐收藏系统**
- `MusicManager` 新增 `favorites` 属性 + `favoritesChanged` 信号
- `toggleFavorite(track)`: 有则删除、无则新增，写入 `favorites_cache.json`
- `removeFavorite(index)`: 按索引删除
- `isFavorite(track)`: 检查是否已收藏，供 UI 判断图标状态

**播放历史系统**
- `MusicManager` 新增 `history` 属性 + `historyChanged` 信号
- `addToHistory(track)`: 播放时自动调用，同文件去重置顶，上限 500 条
- `clearHistory()` / `removeHistoryItem(index)`: 清空/单项删除
- 历史页右上角「清空全部历史」按钮（列表外部独立定位）
- 持久化到 `history_cache.json`，启动自动恢复

**数据持久化**
- 新增通用 JSON 读写工具函数 `writeVariantListToFile` / `readVariantListFromFile`
- 播放列表缓存 `playlist_cache.json`，添加/删除/清空歌曲时自动保存
- 启动时自动加载缓存，自动跳过已删除/移动的文件
- 路径：`%APPDATA%/Just Solo/`（Windows），`~/.local/share/Just Solo/`（Linux/macOS）
- `--develop` 模式每次启动先删除缓存目录，从零开始

**导入体验**
- `MusicManager` 新增 `importProgress` / `importProcessed` / `importTotal` 属性
- 导入时显示 Loader 覆盖层：文件名 + 处理进度（N/M）+ 带渐变动画的进度条
- 百分比实时更新，导入完成后 Loader 自动失活销毁释放内存
- 支持增量添加（追加文件时 total 自动累加）

**封面存储策略**
- 原画质 JPEG 从 `QStandardPaths::CacheLocation`（可被系统清理）迁移到 `AppDataLocation`（持久保留）
- `cacheDir()` 重命名为 `coverDir()`，体现持久化语义

**变更**
- 版本号：v0.0.2-beta.2 → v0.3.0-beta.1
- `CMakeLists.txt`: 移除内联编译依赖，所有 QML 文件加入 `.qrc`
- `main.qml`: 从 ~1000+ 行精简至 ~840 行，NavItem/SubNavItem 组件定义移除
- 播放按钮改用 opacity 淡入淡出动画替代 visible 切换
- 播放按钮中心 Rectangle 添加 hover 颜色动画
- 进度条圆角宽度变化添加 300ms EaseOutCubic 动画
- `toggleMaximize()` 还原窗口时保留 X 坐标（之前强制设 lastGeo.x）
- `play.png` 图标重新导出（1422→2381 字节）

**优化**
- 封面内存大幅降低：列表 delegate 中 `sourceSize: 30×30`（~0.9KB/张），播放栏 `40×40`（~1.6KB/张），不再按原始分辨率解码 GPU 纹理
- 行高从 60px 降至 50px，内边距同步缩小，同屏可展示更多歌曲
- 全部文字颜色微调提亮：标题 `#ccc→#d4d4d4`，歌手/时长 `#888→#969696`，专辑 `#777→#888`，空状态文字 `#666→#757575`
- 列表行内容上下居中，封面与左边缘保留 8px 间距
- 导入完成后 `Loader` 自动失活销毁覆盖层，释放相关内存

**修复**
- 封面图片未按 `Rectangle` 容器尺寸裁剪 → 添加 `anchors.fill: parent`
- delegate 销毁时 `memReleaseTimer.restart()` 空指针崩溃 → 添加 null 检查
- 最大化窗口从右侧拖拽还原时窗口不跟随鼠标 → 改为按比例计算定位
- 滚动条滑块尺寸为 0 不可见 → `contentItem` 从嵌套结构改为直接 `Rectangle`
- RowLayout 未 `anchors.fill: parent` 导致内容贴边、垂直不居中

**变更**
- 版本号升至 v0.3.0-beta.1，作为首个正式版本发行
- 当前功能列表新增封面缓存策略、历史持久化、窗口拖拽说明

### v0.3.5（已发行）— 2026.7.16

> v0.3.5，首个真正意义上的正式版！本版本全新引入播放详情页！现代化ui、设置页扩展、导入加速及全面优化。

**新增**

**播放详情页**
- 点击底部封面打开全屏详情页，毛玻璃背景（`ShaderEffectSource` + `MultiEffect` 实时模糊）
- 左侧：封面 + 歌名（超长横向 marquee 滚动）+ 歌手 + 专辑
- 右侧：歌词列表，WordWrap 自动换行，只展示约 5 句带上下留白居中
- 底部：三按钮左上角等 Y 轴对齐 + 进度条（缩短让位控制区）
- 开关动画：左下角原点缩放 + 透明度过渡，`Easing.Linear` 匀速
- 全窗口背景防穿透层，鼠标事件不泄漏到后层
- 透明度可调（30%-100%，外观设置），持久化重启保持
- 窗口标题栏：最小化 / 最大化 / 关闭按钮，最大化时封面占比扩至 1/3

**逐字高亮歌词**
- 双层 `Text` 叠放：底层灰色 + 上层 `clip` 按 `rawProgress` 裁剪
- 逐字进度直接绑定 `musicManager.position` 每帧更新，由 `lyricOffset` 控制提前完成节奏
- 进度公式 `(pos - curT) / (highlightEnd - curT)`，终点提前 `lyricOffset` ms，高光滚完暂停后自然换行
- 主歌词蓝色 (`#00d4ff`)，翻译金色 (`#FFD700`)
- `isPast` 属性：已播行保持全高光不消失，高光最后一个字也完整显示
- 字号自适应：当前行 38px / 30px，按 `lyricDelegate` id 精确引用消除 parent 链深度错误
- 行间内容滚动动画 `NumberAnimation { duration: 250; Linear }`，`positionViewAtIndex` 自动居中

**双语字幕解析**
- 同毫秒时间戳双行合并：`text + translation` 一条记录
- 外部 `.lrc` 文件与 FLAC 嵌入 `LYRICS` 标签两路均支持
- 毫秒精度完整保留（1-3 位均容错），主歌词与翻译同时逐字高光
- 多行长歌词 WordWrap 正常显示，已播行字号缩小无重叠

**设置页扩展**
- 侧边栏新增 **播放设置**子页面（外观设置 → 播放设置 → 软件更新 → 关于 JustSolo）
- 歌词预读偏移滑块：±5ms 步长，自由调节歌词预读时长
- 外观设置：播放详情页透明度滑块（30%-100%），两者均实时生效持久化
- `MusicManager` 新增 `lyricOffset` 属性（Q_PROPERTY int，默认 170ms）
- 设置界面所有文字提亮：标题 `#f4f4f4`，标签 `#e8e8e8`，辅助 `#aaa`
- 窗口控制按钮 ToolTip：“最小化”“最大化 / 还原”“关闭”

**导入加速**
- `buildTrack` 快路径：MP3/FLAC/M4A 用 `MetadataReader` 二进制解析（~1ms/文件）
- FLAC 时长：解析 `STREAMINFO` block（`total_samples / sample_rate`）
- MP3 时长：`TLEN` 帧优先 → 首个 MPEG 帧头 bitrate 估算（MPEG1/MPEG2 分表）
- 歌手名分隔符统一：`/ ; |` 自动替换为 `、`
- 批处理每轮 8 文件，时长 + 封面三重回退（MetadataReader → QMediaPlayer → 播放修正）

**欢迎页**
- 未选择菜单时显示“欢迎使用 Just Solo”（标题栏）+“点击左侧列表开始使用”（正下方独立行）
- 仅 `currentMenu === ""` 可见，切换菜单自动隐藏

**优化**
- 主页底部进度条固定 280px，脱离窗口弹性变化
- 列表封面 `cache: false` 移除，复用 delegate 不再串图
- 时长值合理性检查（单曲 ≤ 1 小时，超出 3600s 置零）
- 播放时 `mediaStatusChanged` 反写真实时长回列表
- 歌词时间戳正则全面容错：分、秒、毫秒全部 `\d{1,3}`
- 右键菜单 `rightClickedTrack` null 保护
- exe 图标：`app.rc` + `logo.ico`
- 列表时长列表头与 delegate 统一对齐
- 滚动条紧贴右边缘

**修复**
- 关闭进程残留：`shutdown()` 停定时器 + `QCoreApplication::exit(0)`
- ShaderEffectSource `live` 生命周期：不可见时 `blurFx.source = null` + `live = false` 断开渲染管线
- 全尺寸窗口拖拽虚空：`onPositionChanged` 自然接管，`startSystemMove` 不覆盖位置
- 时长异常值：MetadataReader MPEG 帧头假阳性（加同步位校验） + MPEG2 bitrate 表缺失
- `[00:06.0]` 单位数字丢失：正则 `\d{2,3}` → `\d{1,3}` + 1 位 CS 处理
- 时长文字未左对齐
- 翻译重复显示：去掉行内 `/` 误匹配，仅保留同时间戳合并
- 主页 `mouse` 参数弃用警告：`onClicked` → `onClicked: function(mouse)`
- CMake 编译：漏加 `MetadataReader.cpp` + `app.rc`

### v0.3.6 — 2026.7.17

> v0.3.6，UI 重构：原生标题栏、共享组件、歌词三色、列宽优化。

**窗口**
- 系统原生标题栏替代自定义无边框（删除 ~350 行手动实现代码）
- Windows DWM API 深度自定义：暗黑模式、边框颜色与背景同色（Win11 视觉无边框）

**歌词**
- 三色方案：已播=黄 `#FFD700`、当前=青 `#00d4ff`（58px 大字）、未播=蓝 `#6a9ac0`
- 300ms 过渡动画，平移字号/颜色/透明度
- FLAC 嵌入歌词同时间戳行智能堆叠（`looksLikeTranslation` 启发式判断双语）
- 元数据行（作词/作曲/编曲/OP/SP）保留为歌词同时滚动

**歌曲列表**
- 提取 `SongRow.qml` 共享组件，首页/收藏/历史三页统一，改一处全局生效
- 列宽比例 2:2:2:2:1（封面:标题:歌手:专辑:时长），专辑列不再被挤压
- 封面固定 40x40 正方形，`sourceSize` 40px，列间 spacing=0 无缝
- 底部进度条自适应屏幕 1/2 宽度（最大 600px）
- 收藏/历史页播放按钮修复：play/pause 切换逻辑对齐首页

**工程**
- 构建版本号：`ts-machineId-vX.Y.Z`
- 版本号统一由 CMakeLists.txt 管理
- 移除设置页无效语言选择器
- 修复关闭时异步 Loader 引擎销毁警告

### v0.3.7（已发行） — 2026.7.17

> v0.3.7，UI 打磨：可拖动进度条、歌词两段式滚动动画、底部栏优化。

**进度条**
- 播放详情页和全局底部栏进度条支持**点击拖动 seek**，随鼠标实时响应
- 拖动期间锁定进度条宽度（`_trackW`），避免时间文字布局变化导致抖动
- 修复 hover 误触发 seek 的问题（`onPositionChanged` 加 `pressed` 守卫）

**歌词动画**
- 两段式滚动：下一句先放大到 40px 预显示，250ms 后再滚动到位并切换到 58px
- 滚动缓动改为 `OutCubic` 300ms（原 `Linear` 250ms），过渡更丝滑

**底部栏**
- 进度条区域固定**窗口宽度的 1/3**，不再因歌名长度变化而伸缩

**快捷键**
- 禁用 F11 最大化

### v0.4.0（已发行） — 2026.7.18

> v0.4.0，架构调整、升级：多列表播放、播放模式、播放列表页、首页跨来源跟踪、DWM 深色标题栏。

**多列表播放架构**
- 音乐库（`library`）与播放队列（`playlist`）分离，首页展示库不变，播放列表页展示可变队列
- `playlistSource` 属性：首页=0 / 收藏=1 / 历史=2，`currentPlaylist()` 动态路由
- `playIndex`/`next`/`previous`/`play`/`currentTitle` 全部按来源自动选列表
- 收藏/历史左键切换来源播放，右键「添加到音乐列表」追加单曲

**播放列表页（全新）**
- 新增「播放列表」侧边栏入口（首页下、收藏上）
- 模型动态跟随 `playlistSource`，播放收藏/历史时自动切换内容
- 「清除播放列表」按钮：清空队列、复位底部栏、下次自动从库恢复
- 左键支持暂停/播放 toggle，右键支持从播放列表删除曲目

**播放模式（5 种）**
- 新增 `PlayMode` 枚举：顺序播放 / 列表循环 / 单曲循环 / 随机播放 / 关闭循环
- `EndOfMedia` 自动处理：单曲→重播，关闭→停止，其他→下一首
- `next()` 随机模式用 `QRandomGenerator`，顺序模式播完停止
- 播放详情页底部进度条左侧模式切换按钮：点击弹出横向图标菜单、悬浮自动展开
- 外观设置新增菜单透明度滑块（30%-100%，默认 80%）

**首页跨来源播放跟踪**
- 播放设置新增开关「其他列表播放时首页是否显示对应歌曲」
- ON：首页高亮当前播放曲目（路径匹配）；OFF：全变未播放，点击弹窗确认后从头播
- 弹窗深色圆角背景、确定/取消按钮
- 默认关闭

**DWM 深色标题栏**
- Win11 检测（Build ≥ 22000）→ 三色定制（背景 `#1e1e2e`、文字 `#cccccc`、边框 `#1e1e2e`）
- Win10 强制暗黑模式（属性 19 + 20 双保险）
- 关于页显示运行环境（Windows 11 / Windows 10）

**UI/交互优化**
- 播放详情页底部进度条右移缩短；模式按钮悬浮展开
- 全部页面播放/暂停 toggle 统一
- 历史页「清除所有历史」按钮与标题同 Y 对齐
- 设置页去掉重复子标题，只保留顶部标题栏
- 页面切换 Loader 改为同步加载消除闪屏
- 进度条拖动时锁定宽度防抖动
- 首页/播放列表/收藏/历史 `isCurrent` 改用路径匹配（跨来源精准）

**修复**
- 清除播放列表后底部栏封面不清空、播放按钮失效
- 收藏页播放后切换播放列表页闪退
- 历史 `addToHistory`/收藏 `prepend` 导致 `currentIndex` 错位
- 首页歌曲列表高度不一致

### v0.4.1（已发行） — 2026.7.20

> v0.4.1，原生支持Windows 系统媒体控件 (SMTC)、播放列表右键删除、UI 优化、操作逻辑优化、修复了v0.4.0发行以后的已知bug。

**系统集成**
- 新增 Windows 系统媒体传输控件 (SMTC) 支持
- 任务栏音量弹窗、锁屏界面、蓝牙设备显示歌名/歌手/封面
- 播放/暂停/上一首/下一首系统按键支持
- 设置 AppUserModelID (JustSolo.JustSolo)
- 控制台 UTF-8 编码（--develop 模式）

**播放列表**
- 右键菜单新增「从播放列表删除」
- 首页播放时自动从音乐库恢复空播放列表
- 简化 playIndex / addToHistory 逻辑

**UI 优化**
- 首页布局重构：Item → ColumnLayout，彻底解决溢出
- 跨来源弹窗改用 Overlay 层，不再挤占布局
- 跨来源跟踪开关自定义样式（青色滑块）
- 全局文本颜色层次调整（#555 → #999 等）
- 收藏/历史页移除冗余"添加到音乐列表"菜单项

**清理**
- 删除废弃的性能分析报告文件

### v0.4.2（已发行） — 2026.7.20

> v0.4.2，SMTC 完善：新增 Timeline 属性支持，修复 NSD 灵动岛歌词同步问题。

**SMTC 增强**
- 新增 SMTC Timeline 属性推送（Position / EndTime），每 500ms 更新播放进度
- 切歌时自动初始化 duration，播放/暂停时精确更新 position
- 修复 `SetCurrentProcessExplicitAppUserModelID` 调用时机，移至 `QGuiApplication` 之前
- 移除冗余注册表写入（由 InnoSetup 管理）

**兼容性**
- NSD灵动岛工具歌词同步恢复正常（Timeline 提供播放位置信息）
- NSD灵动岛工具在通用媒体模式下歌词展示体验对齐 Electron 播放器

### v0.5.0（已发行） — 2026.7.21

> v0.5.0，优化软件整体体验，添加搜索功能、全局快捷键，并做了一下播放优化。

**新增**

**搜索功能**
- 搜索框支持标题/歌手/专辑模糊匹配，输入实时过滤下拉结果
- 搜索结果关键词青色加粗高亮，歌名超长 marquee 滚动
- 点击结果自动切换到首页、播放歌曲并滚动列表定位
- 全部页面均可搜索，不在首页时自动跳转

**全局快捷键**
- 基于 Windows `RegisterHotKey` + `QAbstractNativeEventFilter` 原生实现
- 全局播放/暂停 `Ctrl+Alt+Space`、上一首 `Ctrl+Alt+←`、下一首 `Ctrl+Alt+→`
- 快捷键设置页：点击卡片进入捕获模式，按下组合键实时生效
- 每项独立重置按钮，配置持久化到 `hotkeys.json`

**设置页**
- 侧边栏新增 **快捷键设置**子页面（播放设置 → 快捷键设置 → 软件更新）
- 顶层 Key 捕获绕过 Repeater 焦点域，解决按键无效问题
- Column 布局替代 Repeater 嵌套，修复 UI 重叠

**优化**

**播放体验**
- 音量 `1.0 → 0.90`，预留 10% 余量防数字削波爆音
- 歌词索引 30ms debounce 防抖 + 预编译 `LyricEntry` 纯整数缓存，消除运行时 toMap 深拷贝
- `next()` 顺序模式播完不再停止，改为循环到第一首

**导入**
- BATCH_SIZE 8 → 10，每次批量处理更多文件

**UI/交互优化**
- 首页/播放列表页切换时自动滚动列表到当前播放歌曲
- 播放详情页入场动画加 80ms 延时等毛玻璃就绪，消除开启动画闪屏
- 页面从 Loader 销毁重建改为预创建 + visible 切换，消除页面切换闪屏

**修复**
- 全局快捷键 `valid` 默认 `false` 导致首次运行不注册
- 全局快捷键构造时注册过早（消息循环未就绪），改为 `QTimer::singleShot` 延迟注册
- 快捷键卡片 `Repeater` 在 `ColumnLayout` 中布局重叠
- 顺序模式最后一首点下一首直接停止

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
