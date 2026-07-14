# Just Solo

**轻量级桌面音乐播放器** —— 基于 Qt 6.8.3 + QML 构建。

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
├── CMakeLists.txt
├── src/
│   ├── main.cpp              # 程序入口
│   └── qml/
│       └── main.qml           # 主窗口 (所有 UI)
├── data/
│   ├── image/                 # 图标资源
│   │   ├── logo.png          # 程序图标
│   │   ├── logo2.png         # 侧边栏 Logo
│   │   ├── home.png          # 首页图标
│   │   ├── mylike.png        # 收藏图标
│   │   └── history.png       # 历史图标
│   └── font/
│       └── HarmonyOS_Sans_SC_Regular.ttf
└── run.ps1                    # 编译+部署+运行脚本
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

---

## 当前功能

- 无边框自定义窗口（最小化/最大化/关闭）
- 侧边栏导航（首页 / 收藏 / 播放历史）
- 搜索框
- 底部播放栏（UI 占位）
- 灰色/青色暗色主题
- HarmonyOS Sans 内置字体

---

## 更新日志

### v0.0.1-beta.1

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

- 新增软件版本号系统（`0.0.1-beta.2`）与构建时间戳双版本
- 新增设置页面（外观 / 软件更新 / 关于 子菜单）
- 软件更新页显示软件版本 + 构建版本 + 检查更新按钮
- 侧边栏优化：整体左移、布局对齐调整
- 窗口顶部全宽区域支持拖动
- 修复 QML `mouse` 参数声明警告
- README 精简为项目实际内容

---

## 许可证

MIT
