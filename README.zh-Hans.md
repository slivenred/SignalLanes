<p align="center">
  <img src="Assets/Brand/signallanes-logo.png" alt="SignalLanes logo" width="120">
</p>

# SignalLanes

[English](README.md) | [繁體中文](README.zh-Hant.md) | [简体中文](README.zh-Hans.md)

SignalLanes 是一个小型 macOS 菜单栏 App 与 CLI，用来监控本机 AI coding agent 与 AI IDE 的工作状态。默认界面语言是英文，App 与 CLI 都可以切换为繁体中文或简体中文。

## 预览

以下截图使用示例项目名称，不包含私人本机路径或真实项目数据。

| 工作中 | 等待授权 | 空闲 |
| --- | --- | --- |
| <img src="Assets/Screenshots/status-red-working.png" alt="SignalLanes red working example" width="260"> | <img src="Assets/Screenshots/status-yellow-waiting.png" alt="SignalLanes yellow waiting example" width="260"> | <img src="Assets/Screenshots/status-green-idle.png" alt="SignalLanes green idle example" width="260"> |

SignalLanes 会用红绿灯状态显示你本机正在使用的工具：

- 绿灯代表目前没有追踪到正在工作的 agent。
- 红灯代表有追踪到 agent 正在工作。
- 黄灯代表有 agent 正在等待授权、批准或用户输入。

优先级是黄灯、红灯、绿灯。如果一个工具在等待批准、另一个工具还在运行，SignalLanes 会显示黄灯，让需要你处理的事情优先浮出来。

## 普通用户安装

最简单的方式是从 GitHub Releases 下载 macOS 安装程序。

1. 从最新 release 下载 `SignalLanes-<version>-macos-installer.pkg`。
2. 打开安装包并按照提示安装。
3. 从 Applications 打开 `SignalLanes.app`。
4. 在 macOS 菜单栏寻找红绿灯图标。SignalLanes 不会显示 Dock 图标。

App 不需要服务器账号、云同步或浏览器扩展。照常打开你的 AI coding tools，SignalLanes 会从本机信号更新菜单栏灯号与浮动面板。

安装程序也会把 `signallanesctl` 安装到 `/usr/local/bin/signallanesctl`，方便需要用 CLI 手动覆盖状态的用户。

替代方式：下载 `SignalLanes-<version>-macos.zip`，解压后手动把 `SignalLanes.app` 拖到 Applications。

如果 macOS 显示 App 无法验证，代表这个下载版本可能尚未签名与 notarize。测试版本可以 Control-click `SignalLanes.app`，选择 Open 并确认。正式公开分享前，建议使用 Apple Developer 账号签名并 notarize。

可选：如果你希望从浮动面板更精准切换到对应窗口，可以在菜单中选择启用精准窗口切换，并在系统设置授予 Accessibility 权限。

## 监控内容

SignalLanes 使用保守的本机信号，不需要服务器账号、云服务或浏览器扩展。

目前自动检测包含：

- `ps` 的 process snapshot。
- CPU 使用率、可运行 process state、命令行关键词。
- 常见命令行 flag 中提供的项目路径与 session ID。
- Codex 与 Claude Desktop 的近期本机 session metadata。
- Antigravity、VS Code、Cursor、Windsurf 内 Claude Code extension 的近期 log。
- `signallanesctl` 写入的手动状态覆盖。

内置 agent 定义目前包含：

- Codex
- Claude Code
- Antigravity
- Cursor
- Windsurf
- Visual Studio Code
- Zed
- Xcode
- Aider
- Gemini CLI
- OpenCode
- Goose

## 系统要求

- macOS 14 或更新版本。
- Swift 6 toolchain，通常可由近期 Xcode 安装取得。
- 可选：如果要从浮动面板更精准切换窗口，需要 Accessibility 权限。

## 从源码运行

在 repository root 运行：

```sh
swift run SignalLanes
```

SignalLanes 会以菜单栏 App 运行，不会显示 Dock 图标。

## 构建 App bundle

构建 release app bundle 与 CLI：

```sh
./Scripts/build-app.sh
```

打开构建出的 App：

```sh
open .build/SignalLanes.app
```

脚本会生成：

- `.build/SignalLanes.app`
- `.build/release/signallanesctl`

本机构建的 app bundle 是开发版本。正式下载通常需要签名与 notarize，macOS 才会把它视为普通发布 App。

## 构建安装程序

构建未签名的 macOS installer package：

```sh
./Scripts/build-installer.sh 0.1.0
```

安装包会输出到：

```text
dist/SignalLanes-0.1.0-macos-installer.pkg
```

它会安装：

- `SignalLanes.app` 到 `/Applications/SignalLanes.app`
- `signallanesctl` 到 `/usr/local/bin/signallanesctl`

如果要生成签名 package，请设置 `SIGNALLANES_PKG_SIGN_ID` 为 Developer ID Installer certificate 名称：

```sh
SIGNALLANES_PKG_SIGN_ID="Developer ID Installer: Example Name (TEAMID)" ./Scripts/build-installer.sh 0.1.0
```

已签名的公开版本也建议在发布前 notarize。

## 创建 release 下载文件

创建可附加到 GitHub Release 的 installer 与 zip：

```sh
./Scripts/package-release.sh 0.1.0
```

脚本会生成：

- `dist/SignalLanes-0.1.0-macos-installer.pkg`
- `dist/SignalLanes-0.1.0-macos.zip`
- `dist/signallanesctl-0.1.0-macos.zip`

普通用户建议下载 `SignalLanes-0.1.0-macos-installer.pkg`。`SignalLanes-0.1.0-macos.zip` 可用于手动拖放安装，`signallanesctl-0.1.0-macos.zip` 则适合只需要 CLI 的用户。

## 菜单栏 App

SignalLanes 启动后，会在 macOS 菜单栏加入红绿灯图标，并每 5 秒重新检测一次。

打开菜单栏项目可以看到：

- 整体状态。
- 上次扫描时间。
- 等待授权的任务。
- 运行中的任务。
- 已停止的任务。
- 可用时显示对应 process、CPU 使用率、session ID、项目路径与状态来源。

菜单也包含：

- 立即刷新
- 隐藏浮动灯号 / 显示浮动灯号
- 重置浮动位置
- 主题
- 显示大小
- 语言
- 启用精准窗口切换
- 打开状态文件夹
- 退出 SignalLanes

## 浮动灯号

SignalLanes 默认会在屏幕上方附近显示浮动面板。

你可以：

- 拖动它来移动位置。
- 点击状态 segment 来筛选显示的任务。
- 当任务数量超过可见行数时滚动列表。
- 点击任务行，尝试切换到对应的 IDE 或 App。
- 从菜单栏菜单切换主题、大小与语言。
- 从菜单栏菜单重置位置。

浮动窗口使用 floating window level，所以会停留在普通 App 窗口上方，但仍低于系统菜单栏与系统面板。

## CLI

当 IDE 或 terminal 没有提供足够状态让 SignalLanes 自动判断时，可以使用 CLI。

从源码运行：

```sh
swift run signallanesctl agents
swift run signallanesctl queue
swift run signallanesctl queue --all-known
swift run signallanesctl --lang zh-Hans queue --all-known
```

或使用构建后的 release binary：

```sh
.build/release/signallanesctl agents
.build/release/signallanesctl queue
```

CLI 默认语言是英文。使用 `--lang en`、`--lang zh-Hant` 或 `--lang zh-Hans` 可切换单次命令输出语言，也可以设置 `SIGNALLANES_LANG`。

### 列出支持的 agent ID

```sh
swift run signallanesctl agents
```

左栏就是手动覆盖时使用的 `<agent-id>`。

### 显示当前 queue

```sh
swift run signallanesctl queue
```

输出会包含整体状态与三个任务区段：

- 等待授权
- 运行中
- 已停止

默认只会显示已检测到或近期有 hint 的工具。若要包含目前空闲或未打开的已知工具：

```sh
swift run signallanesctl queue --all-known
```

`status` 也可作为 queue view 的别名：

```sh
swift run signallanesctl status --all-known
```

### 设置手动覆盖

当你知道某个 agent 正在等待、运行或已空闲，但 SignalLanes 无法自动推断时，可以使用手动覆盖。

```sh
swift run signallanesctl set codex yellow "waiting for approval"
swift run signallanesctl set claude red --ttl 120 "running tests"
swift run signallanesctl set cursor green --no-expire "done"
```

可接受的 state 值包含：

- `green`, `idle`, `done`, `complete`, `completed`
- `red`, `work`, `working`, `running`, `busy`
- `yellow`, `wait`, `waiting`, `permission`, `approval`

覆盖默认 15 分钟后过期。

使用 `--ttl seconds` 设置自定义过期时间：

```sh
swift run signallanesctl set codex yellow --ttl 300 "waiting for shell approval"
```

使用 `--no-expire` 可让覆盖保持到手动清除：

```sh
swift run signallanesctl set aider red --no-expire "long-running refactor"
```

### 清除手动覆盖

```sh
swift run signallanesctl clear codex
```

### 列出有效手动覆盖

```sh
swift run signallanesctl list
```

手动覆盖存储在：

```text
~/.signal-lanes/status.json
```

菜单栏 App 与 CLI 都会读取同一份文件。

## 手动集成示例

你可以从 scripts 调用 `signallanesctl`，集成尚未被 SignalLanes 自动检测的工具。

Shell wrapper 示例：

```sh
#!/usr/bin/env bash
set -euo pipefail

swift run signallanesctl set my-agent red --ttl 3600 "working"
trap 'swift run signallanesctl clear my-agent' EXIT

my-agent "$@"
```

Approval hook 示例：

```sh
swift run signallanesctl set codex yellow --ttl 600 "waiting for command approval"
```

当 approval 处理完成：

```sh
swift run signallanesctl clear codex
```

未知 agent ID 也允许用于手动覆盖，显示名称会直接使用该 ID。

## 隐私与本机数据

SignalLanes 是 local-first。

它会读取本机 process 信息、部分命令行参数、支持工具的本机 session/log metadata，以及本机覆盖文件 `~/.signal-lanes/status.json`。

它不会把 telemetry 或项目数据发送到服务器。

请注意，UI 与 CLI 可能显示本机项目路径、session title、session ID、PID 与短命令预览。这对调试与分配注意力很有用，但若截图或 log 含有私人项目名称或路径，请避免公开分享。

## 当前限制

macOS 没有单一公开 API 可以直接回答“这个 AI IDE 是否正在等待授权”。不同工具会把状态暴露在不同地方，有些甚至只存在于 terminal buffer、本机 app state 或私有 UI 中。

因此 SignalLanes 结合：

- 自动本机 heuristics。
- 特定工具的本机 session/log reader。
- 手动覆盖。

这让 App 保持简单且可检查，但也代表检测可能不完美。未来可以加入更多工具专用 adapter，而不需要改变菜单栏 UI 或 CLI workflow。

## 开发

构建所有产品：

```sh
swift build
```

运行 smoke test：

```sh
swift run SignalLanesCoreSmokeTests
```

构建 App bundle：

```sh
./Scripts/build-app.sh
```

## 贡献

欢迎贡献，特别是：

- 新增更多 AI IDE 与 coding agent 的 detector adapter。
- 改善现有工具的状态解析准确度。
- 更安全地检测等待授权状态。
- 改善打包、签名、release 与文档。

请保持改动小、局部且容易 review。检测代码应优先使用本机、可检查的信号，避免上传项目或 process 数据。

## License

SignalLanes 使用 MIT License 发布。
