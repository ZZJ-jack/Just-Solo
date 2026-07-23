# Just Solo — API 接口文档

> 基于 Qt 6.8.3 的 QML 桌面音乐播放器。本文档覆盖所有暴露给 QML 的对象接口及本地 WebSocket 歌词推送协议。

---

## 目录

- [1. QML 上下文属性](#1-qml-上下文属性)
- [2. MusicManager](#2-musicmanager)
  - [2.1 属性 (Q_PROPERTY)](#21-属性-q_property)
  - [2.2 枚举](#22-枚举)
  - [2.3 方法 (Q_INVOKABLE)](#23-方法-q_invokable)
  - [2.4 信号](#24-信号)
- [3. HotkeyManager](#3-hotkeymanager)
- [4. SMTCManager](#4-smtcmanager)
- [5. MetadataReader](#5-metadatareader)
- [6. WebSocket 歌词推送接口](#6-websocket-歌词推送接口)

---

## 1. QML 上下文属性

`main.cpp` 通过 `QQmlContext` 向 QML 注入以下全局属性：

| 属性名 | 类型 | 说明 |
|--------|------|------|
| `musicManager` | `MusicManager*` | 核心播放管理器，QML 唯一交互入口 |
| `hotkeyManager` | `HotkeyManager*` | 全局快捷键管理器 |
| `APP_VERSION` | `QString` | 应用版本号（CMake `APP_VERSION_DISPLAY`） |
| `BUILD_VERSION` | `QString` | 构建版本号（`GenerateVersion.ps1` 生成） |
| `DEVELOPER_MODE` | `bool` | 是否以 `--develop` 参数启动 |
| `OS_VERSION` | `QString` | 系统版本描述（仅 Windows，`"Windows 11"` / `"Windows 10"`） |

---

## 2. MusicManager

音乐播放核心类，注册名 `musicManager`。负责播放控制、播放列表管理、收藏、历史、歌词、自定义列表、元数据及缓存持久化。

### 2.1 属性 (Q_PROPERTY)

所有属性可在 QML 中直接绑定，变更时触发对应 `NOTIFY` 信号。

#### 数据列表

| 属性 | 类型 | 说明 |
|------|------|------|
| `playlist` | `QVariantList` | 当前播放队列 |
| `library` | `QVariantList` | 音乐库（首页展示，持久化存储） |
| `favorites` | `QVariantList` | 收藏列表 |
| `history` | `QVariantList` | 播放历史 |
| `customPlaylists` | `QVariantList` | 自定义播放列表集合 |
| `currentLyrics` | `QVariantList` | 当前歌词，元素为 `{ time: int(ms), text: string }` |

#### 播放状态

| 属性 | 类型 | 说明 |
|------|------|------|
| `currentIndex` | `int` | 播放队列中当前曲目索引，`-1` = 无 |
| `isPlaying` | `bool` | 是否正在播放 |
| `position` | `qint64` | 当前播放位置（毫秒） |
| `duration` | `qint64` | 当前曲目总时长（毫秒） |
| `isLoading` | `bool` | 是否正在批量加载音频文件 |
| `importProgress` | `qreal` | 导入进度 `0.0–1.0` |
| `importProcessed` | `int` | 已处理文件数 |
| `importTotal` | `int` | 待处理文件总数 |

#### 当前曲目元数据

| 属性 | 类型 | 说明 |
|------|------|------|
| `currentTitle` | `QString` | 当前曲目标题 |
| `currentArtist` | `QString` | 当前曲目艺术家 |
| `currentAlbum` | `QString` | 当前曲目专辑 |
| `currentCover` | `QString` | 当前曲目封面 `file://` 路径 |
| `lyricIndex` | `int` | 当前高亮歌词行索引 |

#### 播放配置

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `playMode` | `int` | `0` (Sequential) | 播放模式，见 [枚举](#22-枚举) |
| `playlistSource` | `int` | `0` (SourcePlaylist) | 活跃播放列表来源 |
| `trackCrossSource` | `bool` | `false` | 跨来源播放跟踪 |
| `minimizeToTray` | `bool` | `false` | 关闭窗口时最小化到托盘 |
| `lyricOffset` | `int` | `130` | 歌词基础偏移（毫秒） |
| `detailOpacity` | `qreal` | `0.90` | 播放详情页背景透明度（`0.3–1.0`） |
| `menuOpacity` | `qreal` | `0.80` | 模式菜单透明度（`0.3–1.0`） |
| `playingListIndex` | `int` | `-1` | 正在播放的列表标识：`-1`=无, `0`=库, `1`=收藏, `2`=历史, `3+n`=自定义 |

### 2.2 枚举

#### PlayMode（播放模式）

```cpp
enum PlayMode {
    Sequential = 0,  // 顺序播放
    ListLoop   = 1,  // 列表循环
    SingleLoop = 2,  // 单曲循环
    Shuffle    = 3,  // 随机播放
    StopAfter  = 4   // 播完当前停止（关闭循环）
};
```

#### PlaylistSource（播放列表来源）

```cpp
enum PlaylistSource {
    SourcePlaylist  = 0,  // 首页（全局播放列表）
    SourceFavorites = 1,  // 收藏页
    SourceHistory   = 2   // 历史页
};
```

### 2.3 方法 (Q_INVOKABLE)

#### 文件导入

| 方法签名 | 说明 |
|----------|------|
| `void addFiles(QStringList paths)` | 添加音频文件到音乐库 |
| `void addFolder(QString path)` | 递归扫描文件夹并导入音频 |
| `bool isDirectory(QString path) const` | 判断路径是否为目录（拖放支持） |
| `bool isAudioFile(QString path) const` | 判断路径是否为支持的音频格式（拖放支持） |

#### 播放队列操作

| 方法签名 | 说明 |
|----------|------|
| `void playIndex(int index)` | 播放队列中指定索引曲目 |
| `void playFromLibrary(int libraryIndex)` | 从音乐库播放，同步播放列表为库内容 |
| `void play()` | 播放 / 恢复 |
| `void pause()` | 暂停 |
| `void stop()` | 停止播放 |
| `void next()` | 下一首（遵循播放模式） |
| `void previous()` | 上一首 |
| `void shutdown()` | 关闭播放器（释放资源） |
| `void seek(qint64 ms)` | 跳转到指定位置（毫秒） |
| `void removeTrack(int index)` | 从队列移除指定索引曲目 |
| `void deleteSongByPath(QString path)` | 按路径从**所有列表**删除（库/播放列表/收藏/历史/自建） |
| `void clearPlaylist()` | 清空播放队列 |

#### 播放队列与来源

| 方法签名 | 说明 |
|----------|------|
| `void addToPlaylist(QVariantMap track)` | 追加单曲到播放队列 |
| `void removeFromPlaylist(QVariantMap track)` | 按路径从播放队列删除 |
| `void copyToPlaylist(int source)` | 将指定来源列表全部复制到播放队列（`source` 为 PlaylistSource 枚举值） |

#### 自定义播放列表

| 方法签名 | 说明 |
|----------|------|
| `void createCustomPlaylist(QString name)` | 创建新的自定义列表 |
| `void renameCustomPlaylist(int index, QString newName)` | 重命名列表 |
| `void deleteCustomPlaylist(int index)` | 删除列表 |
| `void playCustomPlaylist(int playlistIndex, int songIndex)` | 播放指定列表的指定曲目 |
| `void addSongsToCustomPlaylist(QStringList paths, int playlistIndex)` | 从文件路径追加歌曲到列表 |
| `void addLibrarySongsToCustomPlaylist(QVariantList libraryIndices, int playlistIndex)` | 从音乐库索引追加歌曲到列表（按 path 去重） |
| `bool isValidPlaylistName(QString name) const` | 校验列表名是否合法（非空、不重复） |

#### 收藏

| 方法签名 | 说明 |
|----------|------|
| `void toggleFavorite(QVariantMap track)` | 切换收藏状态（有则删，无则加） |
| `void removeFavorite(int index)` | 按收藏列表索引删除 |
| `bool isFavorite(QVariantMap track)` | 检查是否已收藏 |

#### 历史

| 方法签名 | 说明 |
|----------|------|
| `void addToHistory(QVariantMap track)` | 添加到播放历史（播放时自动调用） |
| `void clearHistory()` | 清空历史 |
| `void removeHistoryItem(int index)` | 删除指定历史条目 |

#### 歌词与封面

| 方法签名 | 返回值 | 说明 |
|----------|--------|------|
| `QVariantList loadLyricsForFile(QString filePath)` | `[{time, text}]` | 解析 LRC 文件，返回时间轴 |
| `QString loadOriginalCover()` | `file://` 路径 | 从音频文件提取原始封面保存为 PNG |
| `void releaseOriginalCover()` | — | 释放原画质封面临时文件 |

#### 播放模式

| 方法签名 | 说明 |
|----------|------|
| `void setPlayMode(int mode)` | 设置播放模式（`mode` 为 PlayMode 枚举值） |

#### 缓存与用户数据

| 方法签名 | 说明 |
|----------|------|
| `void setUseCache(bool use)` | 启用/禁用本地缓存持久化 |
| `void clearUserData()` | 清空用户配置和缓存数据 |

### 2.4 信号

QML 中通过 `Connections { target: musicManager }` 监听。

| 信号 | 触发时机 |
|------|----------|
| `playlistChanged()` | 播放队列变更 |
| `libraryChanged()` | 音乐库变更 |
| `favoritesChanged()` | 收藏列表变更 |
| `historyChanged()` | 历史列表变更 |
| `customPlaylistsChanged()` | 自定义列表变更 |
| `currentIndexChanged()` | 当前曲目索引变更 |
| `playbackStateChanged()` | 播放/暂停状态变更 |
| `currentTrackChanged()` | 当前曲目元数据变更（标题/歌手/封面/专辑） |
| `currentLyricsChanged()` | 当前歌词变更（切歌时触发） |
| `lyricIndexChanged()` | 高亮歌词行变更 |
| `positionChanged(qint64 ms)` | 播放位置变更（携带当前毫秒值） |
| `durationChanged()` | 曲目总时长变更 |
| `isLoadingChanged()` | 加载状态变更 |
| `importProgressChanged()` | 导入进度变更 |
| `playModeChanged()` | 播放模式变更 |
| `playlistSourceChanged()` | 播放列表来源变更 |
| `trackCrossSourceChanged()` | 跨来源跟踪开关变更 |
| `minimizeToTrayChanged()` | 最小化到托盘开关变更 |
| `detailOpacityChanged()` | 详情页透明度变更 |
| `menuOpacityChanged()` | 菜单透明度变更 |
| `lyricOffsetChanged()` | 歌词偏移变更 |
| `playingListIndexChanged()` | 正在播放的列表标识变更 |

---

## 3. HotkeyManager

全局快捷键管理器，注册名 `hotkeyManager`。基于 Windows `RegisterHotKey` 实现，通过 `QAbstractNativeEventFilter` 捕获系统热键消息。

### 3.1 枚举

```cpp
enum HotkeyId {
    PlayPause = 0,  // 播放/暂停
    Next      = 1,  // 下一首
    Previous  = 2,  // 上一首
    Count     = 3   // 热键总数（非有效 id）
};
```

### 3.2 方法

| 方法签名 | 说明 |
|----------|------|
| `void setHotkey(int id, int qtKey, int qtMods)` | 设置指定 id 的快捷键（`qtKey` = `Qt::Key`，`qtMods` = `Qt::KeyboardModifiers`） |
| `int hotkeyKey(int id) const` | 获取指定 id 的 Qt key code |
| `int hotkeyMods(int id) const` | 获取指定 id 的修饰键 |

### 3.3 信号

| 信号 | 触发时机 |
|------|----------|
| `playPauseTriggered()` | 播放/暂停热键按下 |
| `nextTriggered()` | 下一首热键按下 |
| `previousTriggered()` | 上一首热键按下 |
| `hotkeyChanged()` | 任意热键配置变更 |

> **绑定说明**：`main.cpp` 已将三个信号连接到 `MusicManager` 的对应操作（play/pause/next/previous），QML 无需额外处理。

---

## 4. SMTCManager

Windows 系统媒体传输控件管理器。**未暴露到 QML**，由 `main.cpp` 内部创建并绑定到 `MusicManager` 信号。

### 职责

- 在任务栏音量弹窗、锁屏界面、蓝牙耳机等位置显示歌名/歌手/封面
- 提供系统级播放/暂停/上一首/下一首控制
- 定时更新播放进度时间轴（约 500ms 间隔）

### 接口（仅 C++ 内部）

| 方法 | 说明 |
|------|------|
| `SMTCManager(MusicManager *manager, HWND hwnd, QObject *parent)` | 构造并初始化 SMTC |
| `void onPlaybackStateChanged()` | slot，播放状态变化时更新系统控件 |
| `void onCurrentTrackChanged()` | slot，切歌时更新元数据 |
| `void updateTimelineTick()` | 定时器回调，更新播放位置 |

> 仅在 Windows 平台编译（`#ifdef Q_OS_WIN`）。

---

## 5. MetadataReader

音频元数据读取工具类（纯静态），**未暴露到 QML**，由 `MusicManager` 内部调用。

### 结构体

```cpp
struct AudioMetadata {
    QString title;        // 标题
    QString artist;       // 艺术家
    QString album;        // 专辑
    QString coverPath;    // 封面 file:/// 路径（空 = 无封面）
    int     durationSecs; // 时长秒数（0 = 未知）
};
```

### 方法

| 方法签名 | 说明 |
|----------|------|
| `static AudioMetadata read(QString filePath, QString cacheDir)` | 一站式提取元数据，封面自动缓存 |

### 支持格式

| 格式 | 元数据来源 | 封面来源 |
|------|------------|----------|
| MP3 | ID3v2 text frames | ID3v2 APIC |
| FLAC | Vorbis comment | FLAC 图片块 |
| MP4/M4A | — | MP4 封面 |

> 无内嵌封面时尝试同目录外部封面文件。

---

## 6. WebSocket 歌词推送接口

实时歌词推送服务，供外部歌词显示应用（如桌面歌词、移动端联动）订阅。

### 连接

```
ws://127.0.0.1:47290
```

- 仅监听本地环回地址，不暴露到网卡
- 仅支持 `ws://`（非加密），不提供 `wss://`
- 多客户端可同时连接

### 消息格式

所有消息为 JSON 文本帧，通过 `type` 字段区分。

#### 6.1 `init` — 歌词时间轴初始化

切歌或歌词异步加载完成时推送。新客户端连接时也会立即收到。

```json
{
  "type": "init",
  "lyrics": [
    { "time": 0,     "text": "Just Solo" },
    { "time": 12450, "text": "第一行歌词" },
    { "time": 18200, "text": "第二行歌词" }
  ]
}
```

| 字段 | 类型 | 说明 |
|------|------|------|
| `type` | `string` | 固定 `"init"` |
| `lyrics` | `array` | 歌词行数组 |
| `lyrics[].time` | `int` | 该行时间戳（毫秒） |
| `lyrics[].text` | `string` | 歌词文本 |

#### 6.2 `progress` — 播放进度

播放中每 200ms 推送一次。暂停或停止时停止推送。

```json
{
  "type": "progress",
  "position": 15680
}
```

| 字段 | 类型 | 说明 |
|------|------|------|
| `type` | `string` | 固定 `"progress"` |
| `position` | `int` | 当前播放位置（毫秒） |

#### 6.3 `playback` — 播放状态变更

播放/暂停状态切换时推送。

```json
{
  "type": "playback",
  "status": "playing"
}
```

| 字段 | 类型 | 说明 |
|------|------|------|
| `type` | `string` | 固定 `"playback"` |
| `status` | `string` | `"playing"` 或 `"paused"` |

### 客户端连接时序

```
客户端连接
  │
  ├─ 立即收到 init（当前歌词时间轴）
  ├─ 立即收到 playback（当前播放状态）
  └─ 若正在播放 → 立即收到 progress（当前进度）
        │
        └─ 之后每 200ms 收到 progress（持续到暂停/断开）
```

### 示例：HTML 客户端

参见项目根目录 `lyric_client_test.html`，包含完整连接、渲染、高亮逻辑。

---

## 附录：命令行参数

| 参数 | 说明 |
|------|------|
| `--develop` | 开启控制台调试日志（UTF-8 输出） |
| `--clearUserData` | 启动时清空用户配置和缓存数据 |
