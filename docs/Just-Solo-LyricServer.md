# Just Solo LyricServer 协议 v1.0.0

> **Just Solo** 实时歌词推送服务端（LyricServer）对外接口规范。
> 供外部歌词显示应用（桌面歌词、移动端联动、OBS 直播歌词等）订阅。

---

## 1. 连接

```
ws://127.0.0.1:47290
```

| 项 | 值 |
|----|----|
| 协议 | WebSocket（非加密 `ws://`，不提供 `wss://`） |
| 地址 | `127.0.0.1`（仅本地环回，不暴露到网卡） |
| 端口 | `47290` |
| 数据格式 | UTF-8 JSON 文本帧 |
| 连接数 | 支持多客户端同时连接 |

连接建立后无需客户端发送任何请求，服务端单向推送。

---

## 2. 消息总览

| `type` | 触发时机 | 推送频率 | 用途 |
|--------|----------|----------|------|
| `init` | 切歌 / 歌词加载完成 / 新客户端连接 | 事件驱动 | 下发完整歌词时间轴 |
| `progress` | 播放中 | 每 200ms | 下发当前播放进度 |
| `playback` | 播放 / 暂停状态切换 | 事件驱动 | 通知播放状态 |

---

## 3. 消息详情

### 3.1 `init` — 歌词时间轴

切歌或歌词异步加载完成时推送。新客户端连接时也会**立即**收到当前歌词。

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
| `lyrics` | `array<object>` | 歌词行数组，按时间升序 |
| `lyrics[].time` | `int` | 该行时间戳，单位毫秒 |
| `lyrics[].text` | `string` | 歌词文本 |

> 无歌词时 `lyrics` 为空数组 `[]`。

### 3.2 `progress` — 播放进度

播放中每 200ms 推送一次。暂停或停止时**停止推送**。

```json
{
  "type": "progress",
  "position": 15680
}
```

| 字段 | 类型 | 说明 |
|------|------|------|
| `type` | `string` | 固定 `"progress"` |
| `position` | `int` | 当前播放位置，单位毫秒 |

> 客户端可据此 + `init` 时间轴二分查找当前应高亮的歌词行。

### 3.3 `playback` — 播放状态变更

播放 / 暂停状态切换时推送。

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

---

## 4. 客户端连接时序

```
客户端连接 ws://127.0.0.1:47290
  │
  ├─ 立即 ← init      （当前歌词时间轴，可能为空）
  ├─ 立即 ← playback  （当前播放状态）
  └─ 若正在播放
        ├─ 立即 ← progress  （当前进度）
        └─ 之后每 200ms ← progress  （持续到暂停 / 停止 / 断开）

播放中切歌:
  ← init        （新歌词时间轴）
  ← progress    （新曲目进度，从头开始）

暂停:
  ← playback    （status: "paused"）
  （progress 推送停止）

恢复播放:
  ← playback    （status: "playing"）
  ← progress    （立即一帧）
  └─ 每 200ms ← progress  （恢复推送）
```

---

## 5. 最小客户端示例（JavaScript）

```javascript
const ws = new WebSocket('ws://127.0.0.1:47290');

let lyrics = [];       // 来自 init
let position = 0;      // 来自 progress
let isPlaying = false; // 来自 playback

ws.onmessage = (event) => {
  const msg = JSON.parse(event.data);

  switch (msg.type) {
    case 'init':
      lyrics = msg.lyrics;
      renderLyrics();
      break;

    case 'progress':
      position = msg.position;
      highlightCurrentLine();
      break;

    case 'playback':
      isPlaying = (msg.status === 'playing');
      updatePlayState();
      break;
  }
};

// 二分查找当前歌词行
function currentLineIndex() {
  let lo = 0, hi = lyrics.length - 1, ans = -1;
  while (lo <= hi) {
    const mid = (lo + hi) >> 1;
    if (lyrics[mid].time <= position) { ans = mid; lo = mid + 1; }
    else { hi = mid - 1; }
  }
  return ans;
}
```

> 完整 HTML 测试客户端见项目根目录 `lyric_client_test.html`。

---

## 6. 设计原则

| 原则 | 说明 |
|------|------|
| **单向推送** | 服务端不接受客户端消息，所有控制通过 Just Solo 应用本身完成 |
| **本地环回** | 仅监听 `127.0.0.1:47290`，不暴露到局域网或公网 |
| **最小开销** | 每帧仅 40~100 字节 JSON，200ms 间隔避免无效刷新 |
| **即连即用** | 客户端连接后立即补推当前状态，无需额外握手 |
| **优雅降级** | 无客户端连接时自动停推 progress，节省 CPU |

---

## 7. 版本历史

| 版本 | 日期 | 变更 |
|------|------|------|
| v1.0.0 | 2026-07-24 | 初始发布，定义 init / progress / playback 三个消息类型 |
