<p align="center">
  <img src="Assets/Brand/signallanes-logo.png" alt="SignalLanes logo" width="120">
</p>

# SignalLanes

[English](README.md) | [繁體中文](README.zh-Hant.md) | [简体中文](README.zh-Hans.md)

SignalLanes 是一個小型 macOS 選單列 App 與 CLI，用來監控本機 AI coding agent 與 AI IDE 的工作狀態。預設介面語言是英文，App 與 CLI 都可以切換為繁體中文或簡體中文。

## 預覽

以下截圖使用示範專案名稱，不包含私人本機路徑或真實專案資料。

| 工作中 | 等待授權 | 閒置 |
| --- | --- | --- |
| <img src="Assets/Screenshots/status-red-working.png" alt="SignalLanes red working example" width="260"> | <img src="Assets/Screenshots/status-yellow-waiting.png" alt="SignalLanes yellow waiting example" width="260"> | <img src="Assets/Screenshots/status-green-idle.png" alt="SignalLanes green idle example" width="260"> |

SignalLanes 會用紅綠燈狀態顯示你本機正在使用的工具：

- 綠燈代表目前沒有追蹤到正在工作的 agent。
- 紅燈代表有追蹤到 agent 正在工作。
- 黃燈代表有 agent 正在等待授權、核准或使用者輸入。

優先順序是黃燈、紅燈、綠燈。如果一個工具在等待核准、另一個工具還在執行，SignalLanes 會顯示黃燈，讓需要你處理的事情優先浮出來。

## 一般使用者安裝

最簡單的方式是從 GitHub Releases 下載 macOS 安裝程式。

1. 從最新 release 下載 `SignalLanes-<version>-macos-installer.pkg`。
2. 開啟安裝套件並依照提示安裝。
3. 從 Applications 開啟 `SignalLanes.app`。
4. 在 macOS 選單列尋找紅綠燈圖示。SignalLanes 不會顯示 Dock 圖示。

App 不需要伺服器帳號、雲端同步或瀏覽器擴充套件。照常開啟你的 AI coding tools，SignalLanes 會從本機訊號更新選單列燈號與浮動面板。

安裝程式也會把 `signallanesctl` 安裝到 `/usr/local/bin/signallanesctl`，方便需要用 CLI 手動覆寫狀態的使用者。

替代方式：下載 `SignalLanes-<version>-macos.zip`，解壓縮後手動把 `SignalLanes.app` 拖到 Applications。

如果 macOS 顯示 App 無法驗證，代表這個下載版本可能尚未簽署與 notarize。測試版本可以 Control-click `SignalLanes.app`，選擇 Open 並確認。正式公開分享前，建議使用 Apple Developer 帳號簽署並 notarize。

可選：如果你希望從浮動面板更精準切換到對應視窗，可以在選單中選擇啟用精準視窗切換，並在系統設定授予 Accessibility 權限。

## 監控內容

SignalLanes 使用保守的本機訊號，不需要伺服器帳號、雲端服務或瀏覽器擴充套件。

目前自動偵測包含：

- `ps` 的 process snapshot。
- CPU 使用率、可執行 process state、命令列關鍵字。
- 常見命令列 flag 中提供的專案路徑與 session ID。
- Codex 與 Claude Desktop 的近期本機 session metadata。
- Antigravity、VS Code、Cursor、Windsurf 內 Claude Code extension 的近期 log。
- `signallanesctl` 寫入的手動狀態覆寫。

內建 agent 定義目前包含：

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

## 系統需求

- macOS 14 或更新版本。
- Swift 6 toolchain，通常可由近期 Xcode 安裝取得。
- 可選：如果要從浮動面板更精準切換視窗，需要 Accessibility 權限。

## 從原始碼執行

在 repository root 執行：

```sh
swift run SignalLanes
```

SignalLanes 會以選單列 App 執行，不會顯示 Dock 圖示。

## 建置 App bundle

建置 release app bundle 與 CLI：

```sh
./Scripts/build-app.sh
```

開啟建置出的 App：

```sh
open .build/SignalLanes.app
```

腳本會產生：

- `.build/SignalLanes.app`
- `.build/release/signallanesctl`

本機建置的 app bundle 是開發版本。正式下載通常需要簽署與 notarize，macOS 才會把它視為一般發佈 App。

## 建置安裝程式

建置未簽署的 macOS installer package：

```sh
./Scripts/build-installer.sh 0.1.0
```

安裝套件會輸出到：

```text
dist/SignalLanes-0.1.0-macos-installer.pkg
```

它會安裝：

- `SignalLanes.app` 到 `/Applications/SignalLanes.app`
- `signallanesctl` 到 `/usr/local/bin/signallanesctl`

如果要產生簽署 package，請設定 `SIGNALLANES_PKG_SIGN_ID` 為 Developer ID Installer certificate 名稱：

```sh
SIGNALLANES_PKG_SIGN_ID="Developer ID Installer: Example Name (TEAMID)" ./Scripts/build-installer.sh 0.1.0
```

已簽署的公開版本也建議在發佈前 notarize。

## 建立 release 下載檔

建立可附加到 GitHub Release 的 installer 與 zip：

```sh
./Scripts/package-release.sh 0.1.0
```

腳本會產生：

- `dist/SignalLanes-0.1.0-macos-installer.pkg`
- `dist/SignalLanes-0.1.0-macos.zip`
- `dist/signallanesctl-0.1.0-macos.zip`

一般使用者建議下載 `SignalLanes-0.1.0-macos-installer.pkg`。`SignalLanes-0.1.0-macos.zip` 可用於手動拖放安裝，`signallanesctl-0.1.0-macos.zip` 則適合只需要 CLI 的使用者。

## 選單列 App

SignalLanes 啟動後，會在 macOS 選單列加入紅綠燈圖示，並每 5 秒重新偵測一次。

打開選單列項目可以看到：

- 整體狀態。
- 上次掃描時間。
- 等待授權的工作。
- 執行中的工作。
- 已停止的工作。
- 可用時顯示對應 process、CPU 使用率、session ID、專案路徑與狀態來源。

選單也包含：

- 立即重新整理
- 隱藏浮動燈號 / 顯示浮動燈號
- 重設浮動位置
- 主題
- 顯示大小
- 語言
- 啟用精準視窗切換
- 開啟狀態資料夾
- 結束 SignalLanes

## 浮動燈號

SignalLanes 預設會在畫面上方附近顯示浮動面板。

你可以：

- 拖曳它來移動位置。
- 點擊狀態 segment 來篩選顯示的工作。
- 當工作數量超過可見列數時捲動列表。
- 點擊工作列，嘗試切換到對應的 IDE 或 App。
- 從選單列選單切換主題、大小與語言。
- 從選單列選單重設位置。

浮動視窗使用 floating window level，所以會停留在一般 App 視窗上方，但仍低於系統選單列與系統面板。

## CLI

當 IDE 或 terminal 沒有提供足夠狀態讓 SignalLanes 自動判斷時，可以使用 CLI。

從原始碼執行：

```sh
swift run signallanesctl agents
swift run signallanesctl queue
swift run signallanesctl queue --all-known
swift run signallanesctl --lang zh-Hant queue --all-known
```

或使用建置後的 release binary：

```sh
.build/release/signallanesctl agents
.build/release/signallanesctl queue
```

CLI 預設語言是英文。使用 `--lang en`、`--lang zh-Hant` 或 `--lang zh-Hans` 可切換單次指令輸出語言，也可以設定 `SIGNALLANES_LANG`。

### 列出支援的 agent ID

```sh
swift run signallanesctl agents
```

左欄就是手動覆寫時使用的 `<agent-id>`。

### 顯示目前 queue

```sh
swift run signallanesctl queue
```

輸出會包含整體狀態與三個工作區段：

- 等待授權
- 執行中
- 已停止

預設只會顯示已偵測到或近期有 hint 的工具。若要包含目前閒置或未開啟的已知工具：

```sh
swift run signallanesctl queue --all-known
```

`status` 也可作為 queue view 的別名：

```sh
swift run signallanesctl status --all-known
```

### 設定手動覆寫

當你知道某個 agent 正在等待、執行或已閒置，但 SignalLanes 無法自動推斷時，可以使用手動覆寫。

```sh
swift run signallanesctl set codex yellow "waiting for approval"
swift run signallanesctl set claude red --ttl 120 "running tests"
swift run signallanesctl set cursor green --no-expire "done"
```

可接受的 state 值包含：

- `green`, `idle`, `done`, `complete`, `completed`
- `red`, `work`, `working`, `running`, `busy`
- `yellow`, `wait`, `waiting`, `permission`, `approval`

覆寫預設 15 分鐘後過期。

使用 `--ttl seconds` 設定自訂過期時間：

```sh
swift run signallanesctl set codex yellow --ttl 300 "waiting for shell approval"
```

使用 `--no-expire` 可讓覆寫保持到手動清除：

```sh
swift run signallanesctl set aider red --no-expire "long-running refactor"
```

### 清除手動覆寫

```sh
swift run signallanesctl clear codex
```

### 列出有效手動覆寫

```sh
swift run signallanesctl list
```

手動覆寫儲存在：

```text
~/.signal-lanes/status.json
```

選單列 App 與 CLI 都會讀取同一份檔案。

## 手動整合範例

你可以從 scripts 呼叫 `signallanesctl`，整合尚未被 SignalLanes 自動偵測的工具。

Shell wrapper 範例：

```sh
#!/usr/bin/env bash
set -euo pipefail

swift run signallanesctl set my-agent red --ttl 3600 "working"
trap 'swift run signallanesctl clear my-agent' EXIT

my-agent "$@"
```

Approval hook 範例：

```sh
swift run signallanesctl set codex yellow --ttl 600 "waiting for command approval"
```

當 approval 處理完成：

```sh
swift run signallanesctl clear codex
```

未知 agent ID 也允許用於手動覆寫，顯示名稱會直接使用該 ID。

## 隱私與本機資料

SignalLanes 是 local-first。

它會讀取本機 process 資訊、部分命令列參數、支援工具的本機 session/log metadata，以及本機覆寫檔 `~/.signal-lanes/status.json`。

它不會把 telemetry 或專案資料送到伺服器。

請注意，UI 與 CLI 可能顯示本機專案路徑、session title、session ID、PID 與短命令預覽。這對除錯與分配注意力很有用，但若截圖或 log 含有私人專案名稱或路徑，請避免公開分享。

## 目前限制

macOS 沒有單一公開 API 可以直接回答「這個 AI IDE 是否正在等待授權」。不同工具會把狀態暴露在不同地方，有些甚至只存在於 terminal buffer、本機 app state 或私有 UI 中。

因此 SignalLanes 結合：

- 自動本機 heuristics。
- 特定工具的本機 session/log reader。
- 手動覆寫。

這讓 App 維持簡單且可檢查，但也代表偵測可能不完美。未來可以加入更多工具專用 adapter，而不需要改變選單列 UI 或 CLI workflow。

## 開發

建置所有產品：

```sh
swift build
```

執行 smoke test：

```sh
swift run SignalLanesCoreSmokeTests
```

建置 App bundle：

```sh
./Scripts/build-app.sh
```

## 貢獻

歡迎貢獻，特別是：

- 新增更多 AI IDE 與 coding agent 的 detector adapter。
- 改善現有工具的狀態解析準確度。
- 更安全地偵測等待授權狀態。
- 改善打包、簽署、release 與文件。

請保持改動小、局部且容易 review。偵測程式碼應優先使用本機、可檢查的訊號，避免上傳專案或 process 資料。

## License

SignalLanes 使用 MIT License 發佈。
