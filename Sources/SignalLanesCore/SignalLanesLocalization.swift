import Foundation

public enum AppLanguage: String, CaseIterable, Sendable {
    case english = "en"
    case traditionalChinese = "zh-Hant"
    case simplifiedChinese = "zh-Hans"

    public static let defaultLanguage: AppLanguage = .english

    public var displayName: String {
        switch self {
        case .english:
            return "English"
        case .traditionalChinese:
            return "繁體中文"
        case .simplifiedChinese:
            return "简体中文"
        }
    }

    public static func parse(_ value: String?) -> AppLanguage? {
        guard let value else {
            return nil
        }

        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()

        switch normalized {
        case "en", "en-us", "english":
            return .english
        case "zh-hant", "zh-tw", "zh-hk", "traditional", "traditional-chinese", "繁體中文":
            return .traditionalChinese
        case "zh-hans", "zh-cn", "zh-sg", "simplified", "simplified-chinese", "简体中文":
            return .simplifiedChinese
        default:
            return nil
        }
    }
}

public struct SignalLanesLocalization: Sendable {
    public let language: AppLanguage

    public init(language: AppLanguage = .defaultLanguage) {
        self.language = language
    }

    public var detectionFailed: String {
        switch language {
        case .english:
            return "Detection failed"
        case .traditionalChinese:
            return "偵測失敗"
        case .simplifiedChinese:
            return "检测失败"
        }
    }

    public var lastScan: String {
        switch language {
        case .english:
            return "Last scan"
        case .traditionalChinese:
            return "上次掃描"
        case .simplifiedChinese:
            return "上次扫描"
        }
    }

    public var waitingForPermission: String {
        switch language {
        case .english:
            return "Waiting for Permission"
        case .traditionalChinese:
            return "等待授權"
        case .simplifiedChinese:
            return "等待授权"
        }
    }

    public var running: String {
        switch language {
        case .english:
            return "Running"
        case .traditionalChinese:
            return "執行中"
        case .simplifiedChinese:
            return "运行中"
        }
    }

    public var stopped: String {
        switch language {
        case .english:
            return "Stopped"
        case .traditionalChinese:
            return "已停止"
        case .simplifiedChinese:
            return "已停止"
        }
    }

    public var none: String {
        switch language {
        case .english:
            return "None"
        case .traditionalChinese:
            return "無"
        case .simplifiedChinese:
            return "无"
        }
    }

    public var openSession: String {
        switch language {
        case .english:
            return "Open session"
        case .traditionalChinese:
            return "開啟工作階段"
        case .simplifiedChinese:
            return "打开会话"
        }
    }

    public var project: String {
        switch language {
        case .english:
            return "Project"
        case .traditionalChinese:
            return "專案"
        case .simplifiedChinese:
            return "项目"
        }
    }

    public var session: String {
        switch language {
        case .english:
            return "Session"
        case .traditionalChinese:
            return "工作階段"
        case .simplifiedChinese:
            return "会话"
        }
    }

    public var source: String {
        switch language {
        case .english:
            return "Source"
        case .traditionalChinese:
            return "來源"
        case .simplifiedChinese:
            return "来源"
        }
    }

    public var mixed: String {
        switch language {
        case .english:
            return "mixed"
        case .traditionalChinese:
            return "混合"
        case .simplifiedChinese:
            return "混合"
        }
    }

    public var refreshNow: String {
        switch language {
        case .english:
            return "Refresh Now"
        case .traditionalChinese:
            return "立即重新整理"
        case .simplifiedChinese:
            return "立即刷新"
        }
    }

    public var hideFloatingLight: String {
        switch language {
        case .english:
            return "Hide Floating Light"
        case .traditionalChinese:
            return "隱藏浮動燈號"
        case .simplifiedChinese:
            return "隐藏浮动灯号"
        }
    }

    public var showFloatingLight: String {
        switch language {
        case .english:
            return "Show Floating Light"
        case .traditionalChinese:
            return "顯示浮動燈號"
        case .simplifiedChinese:
            return "显示浮动灯号"
        }
    }

    public var resetFloatingPosition: String {
        switch language {
        case .english:
            return "Reset Floating Position"
        case .traditionalChinese:
            return "重設浮動位置"
        case .simplifiedChinese:
            return "重置浮动位置"
        }
    }

    public var theme: String {
        switch language {
        case .english:
            return "Theme"
        case .traditionalChinese:
            return "主題"
        case .simplifiedChinese:
            return "主题"
        }
    }

    public var displaySize: String {
        switch language {
        case .english:
            return "Display Size"
        case .traditionalChinese:
            return "顯示大小"
        case .simplifiedChinese:
            return "显示大小"
        }
    }

    public var languageMenu: String {
        switch language {
        case .english:
            return "Language"
        case .traditionalChinese:
            return "語言"
        case .simplifiedChinese:
            return "语言"
        }
    }

    public var preciseWindowSwitchingEnabled: String {
        switch language {
        case .english:
            return "Precise Window Switching Enabled"
        case .traditionalChinese:
            return "已啟用精準視窗切換"
        case .simplifiedChinese:
            return "已启用精准窗口切换"
        }
    }

    public var enablePreciseWindowSwitching: String {
        switch language {
        case .english:
            return "Enable Precise Window Switching..."
        case .traditionalChinese:
            return "啟用精準視窗切換..."
        case .simplifiedChinese:
            return "启用精准窗口切换..."
        }
    }

    public var accessibilityPermissionTitle: String {
        switch language {
        case .english:
            return "Allow precise window switching?"
        case .traditionalChinese:
            return "要啟用精準視窗切換嗎？"
        case .simplifiedChinese:
            return "要启用精准窗口切换吗？"
        }
    }

    public var accessibilityPermissionMessage: String {
        switch language {
        case .english:
            return "SignalLanes needs macOS Accessibility permission to bring the exact IDE window to the front when you click a row. Enable SignalLanes in System Settings > Privacy & Security > Accessibility, then click the row again."
        case .traditionalChinese:
            return "SignalLanes 需要 macOS「輔助使用」權限，才能在你點擊某一列時，把對應的 IDE 視窗精準帶到最前方。請在「系統設定 > 隱私權與安全性 > 輔助使用」啟用 SignalLanes，然後再點同一列一次。"
        case .simplifiedChinese:
            return "SignalLanes 需要 macOS“辅助功能”权限，才能在你点击某一行时，把对应的 IDE 窗口精准带到最前方。请在“系统设置 > 隐私与安全性 > 辅助功能”启用 SignalLanes，然后再点同一行一次。"
        }
    }

    public var openAccessibilitySettings: String {
        switch language {
        case .english:
            return "Open Accessibility Settings"
        case .traditionalChinese:
            return "開啟輔助使用設定"
        case .simplifiedChinese:
            return "打开辅助功能设置"
        }
    }

    public var notNow: String {
        switch language {
        case .english:
            return "Not Now"
        case .traditionalChinese:
            return "稍後"
        case .simplifiedChinese:
            return "稍后"
        }
    }

    public var openStatusFolder: String {
        switch language {
        case .english:
            return "Open Status Folder"
        case .traditionalChinese:
            return "開啟狀態資料夾"
        case .simplifiedChinese:
            return "打开状态文件夹"
        }
    }

    public var quitSignalLanes: String {
        switch language {
        case .english:
            return "Quit SignalLanes"
        case .traditionalChinese:
            return "結束 SignalLanes"
        case .simplifiedChinese:
            return "退出 SignalLanes"
        }
    }

    public var noTrackedSessions: String {
        switch language {
        case .english:
            return "No tracked sessions right now"
        case .traditionalChinese:
            return "目前沒有追蹤中的工作階段"
        case .simplifiedChinese:
            return "目前没有追踪中的会话"
        }
    }

    public var noActiveOverrides: String {
        switch language {
        case .english:
            return "No active overrides."
        case .traditionalChinese:
            return "目前沒有有效的手動覆寫。"
        case .simplifiedChinese:
            return "目前没有有效的手动覆盖。"
        }
    }

    public var noExpiry: String {
        switch language {
        case .english:
            return "no expiry"
        case .traditionalChinese:
            return "不過期"
        case .simplifiedChinese:
            return "不过期"
        }
    }

    public var projectNotExposed: String {
        switch language {
        case .english:
            return "project not exposed"
        case .traditionalChinese:
            return "未提供專案"
        case .simplifiedChinese:
            return "未提供项目"
        }
    }

    public var titleLabel: String {
        switch language {
        case .english:
            return "Title"
        case .traditionalChinese:
            return "標題"
        case .simplifiedChinese:
            return "标题"
        }
    }

    public var overall: String {
        switch language {
        case .english:
            return "Overall"
        case .traditionalChinese:
            return "整體"
        case .simplifiedChinese:
            return "整体"
        }
    }

    public var ttlRequiresPositiveSeconds: String {
        switch language {
        case .english:
            return "--ttl requires a positive number of seconds"
        case .traditionalChinese:
            return "--ttl 需要正數秒數"
        case .simplifiedChinese:
            return "--ttl 需要正数秒数"
        }
    }

    public var missingLanguageValue: String {
        switch language {
        case .english:
            return "--lang requires en, zh-Hant, or zh-Hans"
        case .traditionalChinese:
            return "--lang 需要 en、zh-Hant 或 zh-Hans"
        case .simplifiedChinese:
            return "--lang 需要 en、zh-Hant 或 zh-Hans"
        }
    }

    public var cliUsage: String {
        switch language {
        case .english:
            return """
            Usage:
              signallanesctl [--lang en|zh-Hant|zh-Hans] set <agent-id> <green|yellow|red> [--ttl seconds|--no-expire] [reason...]
              signallanesctl [--lang en|zh-Hant|zh-Hans] clear <agent-id>
              signallanesctl [--lang en|zh-Hant|zh-Hans] list
              signallanesctl [--lang en|zh-Hant|zh-Hans] status [--all-known]
              signallanesctl [--lang en|zh-Hant|zh-Hans] queue [--all-known]
              signallanesctl [--lang en|zh-Hant|zh-Hans] agents

            Examples:
              signallanesctl set codex yellow "waiting for approval"
              signallanesctl --lang zh-Hant queue --all-known
              signallanesctl set claude red --ttl 120 "running tests"
              signallanesctl clear codex
            """
        case .traditionalChinese:
            return """
            使用方式:
              signallanesctl [--lang en|zh-Hant|zh-Hans] set <agent-id> <green|yellow|red> [--ttl 秒數|--no-expire] [原因...]
              signallanesctl [--lang en|zh-Hant|zh-Hans] clear <agent-id>
              signallanesctl [--lang en|zh-Hant|zh-Hans] list
              signallanesctl [--lang en|zh-Hant|zh-Hans] status [--all-known]
              signallanesctl [--lang en|zh-Hant|zh-Hans] queue [--all-known]
              signallanesctl [--lang en|zh-Hant|zh-Hans] agents

            範例:
              signallanesctl set codex yellow "waiting for approval"
              signallanesctl --lang zh-Hant queue --all-known
              signallanesctl set claude red --ttl 120 "running tests"
              signallanesctl clear codex
            """
        case .simplifiedChinese:
            return """
            使用方式:
              signallanesctl [--lang en|zh-Hant|zh-Hans] set <agent-id> <green|yellow|red> [--ttl 秒数|--no-expire] [原因...]
              signallanesctl [--lang en|zh-Hant|zh-Hans] clear <agent-id>
              signallanesctl [--lang en|zh-Hant|zh-Hans] list
              signallanesctl [--lang en|zh-Hant|zh-Hans] status [--all-known]
              signallanesctl [--lang en|zh-Hant|zh-Hans] queue [--all-known]
              signallanesctl [--lang en|zh-Hant|zh-Hans] agents

            示例:
              signallanesctl set codex yellow "waiting for approval"
              signallanesctl --lang zh-Hans queue --all-known
              signallanesctl set claude red --ttl 120 "running tests"
              signallanesctl clear codex
            """
        }
    }

    public func stateDisplayName(_ state: LightState) -> String {
        switch (language, state) {
        case (.english, .idle):
            return "Green / idle"
        case (.english, .working):
            return "Red / working"
        case (.english, .waitingForPermission):
            return "Yellow / waiting for permission"
        case (.traditionalChinese, .idle):
            return "綠燈 / 閒置"
        case (.traditionalChinese, .working):
            return "紅燈 / 執行中"
        case (.traditionalChinese, .waitingForPermission):
            return "黃燈 / 等待授權"
        case (.simplifiedChinese, .idle):
            return "绿灯 / 空闲"
        case (.simplifiedChinese, .working):
            return "红灯 / 运行中"
        case (.simplifiedChinese, .waitingForPermission):
            return "黄灯 / 等待授权"
        }
    }

    public func stateColorName(_ state: LightState) -> String {
        switch (language, state) {
        case (.english, .idle):
            return "Green"
        case (.english, .working):
            return "Red"
        case (.english, .waitingForPermission):
            return "Yellow"
        case (.traditionalChinese, .idle):
            return "綠燈"
        case (.traditionalChinese, .working):
            return "紅燈"
        case (.traditionalChinese, .waitingForPermission):
            return "黃燈"
        case (.simplifiedChinese, .idle):
            return "绿灯"
        case (.simplifiedChinese, .working):
            return "红灯"
        case (.simplifiedChinese, .waitingForPermission):
            return "黄灯"
        }
    }

    public func statusPillLabel(for state: LightState) -> String {
        switch (language, state) {
        case (.english, .idle):
            return "Idle"
        case (.english, .working):
            return "Working"
        case (.english, .waitingForPermission):
            return "Waiting"
        case (.traditionalChinese, .idle):
            return "閒置"
        case (.traditionalChinese, .working):
            return "工作中"
        case (.traditionalChinese, .waitingForPermission):
            return "等待中"
        case (.simplifiedChinese, .idle):
            return "空闲"
        case (.simplifiedChinese, .working):
            return "工作中"
        case (.simplifiedChinese, .waitingForPermission):
            return "等待中"
        }
    }

    public func segmentLabel(for state: LightState) -> String {
        switch state {
        case .idle:
            return stopped
        case .working:
            return running
        case .waitingForPermission:
            switch language {
            case .english:
                return "Waiting"
            case .traditionalChinese:
                return "等待中"
            case .simplifiedChinese:
                return "等待中"
            }
        }
    }

    public func shortSegmentLabel(for state: LightState) -> String {
        switch (language, state) {
        case (.english, .idle):
            return "Stop"
        case (.english, .working):
            return "Run"
        case (.english, .waitingForPermission):
            return "Wait"
        case (.traditionalChinese, .idle):
            return "停止"
        case (.traditionalChinese, .working):
            return "執行"
        case (.traditionalChinese, .waitingForPermission):
            return "等待"
        case (.simplifiedChinese, .idle):
            return "停止"
        case (.simplifiedChinese, .working):
            return "运行"
        case (.simplifiedChinese, .waitingForPermission):
            return "等待"
        }
    }

    public func emptyMessage(for state: LightState) -> String {
        switch (language, state) {
        case (.english, .working):
            return "No running IDE tasks detected."
        case (.english, .waitingForPermission):
            return "No permission requests detected."
        case (.english, .idle):
            return "No stopped IDE tasks detected."
        case (.traditionalChinese, .working):
            return "沒有偵測到執行中的 IDE 工作。"
        case (.traditionalChinese, .waitingForPermission):
            return "沒有偵測到等待授權的請求。"
        case (.traditionalChinese, .idle):
            return "沒有偵測到已停止的 IDE 工作。"
        case (.simplifiedChinese, .working):
            return "没有检测到运行中的 IDE 任务。"
        case (.simplifiedChinese, .waitingForPermission):
            return "没有检测到等待授权的请求。"
        case (.simplifiedChinese, .idle):
            return "没有检测到已停止的 IDE 任务。"
        }
    }

    public func floatingToolTip(for state: LightState) -> String {
        let actionText: String
        switch language {
        case .english:
            actionText = "Click a status to filter, scroll the list, click a row to activate its IDE, or drag to move."
        case .traditionalChinese:
            actionText = "點擊狀態可篩選，捲動列表，點擊列可切換到對應 IDE，也可以拖曳移動。"
        case .simplifiedChinese:
            actionText = "点击状态可筛选，滚动列表，点击行可切换到对应 IDE，也可以拖动移动。"
        }
        return "SignalLanes: \(stateDisplayName(state)). \(actionText)"
    }

    public func queueSummary(waiting: Int, running: Int, stopped: Int) -> String {
        switch language {
        case .english:
            return "\(waiting) waiting, \(running) running, \(stopped) stopped"
        case .traditionalChinese:
            return "\(waiting) 個等待、\(running) 個執行中、\(stopped) 個已停止"
        case .simplifiedChinese:
            return "\(waiting) 个等待、\(running) 个运行中、\(stopped) 个已停止"
        }
    }

    public func floatingSummary(running: Int, waiting: Int, stopped: Int) -> String {
        let total = running + waiting + stopped
        guard total > 0 else {
            return noTrackedSessions
        }

        switch language {
        case .english:
            return "\(running) running / \(waiting) waiting / \(stopped) stopped"
        case .traditionalChinese:
            return "\(running) 執行中 / \(waiting) 等待 / \(stopped) 停止"
        case .simplifiedChinese:
            return "\(running) 运行中 / \(waiting) 等待 / \(stopped) 停止"
        }
    }

    public func groupedSessions(count: Int) -> String {
        switch language {
        case .english:
            return "Grouped \(count) sessions by IDE and project."
        case .traditionalChinese:
            return "已依 IDE 與專案合併 \(count) 個工作階段。"
        case .simplifiedChinese:
            return "已按 IDE 与项目合并 \(count) 个会话。"
        }
    }

    public func badgeParts(waiting: Int, running: Int, stopped: Int) -> [String] {
        let waitingPrefix: String
        let runningPrefix: String
        let stoppedPrefix: String
        switch language {
        case .english:
            waitingPrefix = "Y"
            runningPrefix = "R"
            stoppedPrefix = "G"
        case .traditionalChinese:
            waitingPrefix = "黃"
            runningPrefix = "紅"
            stoppedPrefix = "綠"
        case .simplifiedChinese:
            waitingPrefix = "黄"
            runningPrefix = "红"
            stoppedPrefix = "绿"
        }

        return [
            waiting > 0 ? "\(waitingPrefix)\(waiting)" : nil,
            running > 0 ? "\(runningPrefix)\(running)" : nil,
            stopped > 0 ? "\(stoppedPrefix)\(stopped)" : nil
        ].compactMap { $0 }
    }

    public func sourceName(_ source: ReportSource) -> String {
        switch (language, source) {
        case (.english, .automatic):
            return "automatic"
        case (.english, .manualOverride):
            return "manual override"
        case (.traditionalChinese, .automatic):
            return "自動偵測"
        case (.traditionalChinese, .manualOverride):
            return "手動覆寫"
        case (.simplifiedChinese, .automatic):
            return "自动检测"
        case (.simplifiedChinese, .manualOverride):
            return "手动覆盖"
        }
    }

    public func unknownState(_ value: String) -> String {
        switch language {
        case .english:
            return "unknown state '\(value)'"
        case .traditionalChinese:
            return "未知狀態 '\(value)'"
        case .simplifiedChinese:
            return "未知状态 '\(value)'"
        }
    }

    public func setMessage(agentID: String, state: LightState) -> String {
        switch language {
        case .english:
            return "Set \(agentID) to \(stateDisplayName(state))."
        case .traditionalChinese:
            return "已將 \(agentID) 設為 \(stateDisplayName(state))。"
        case .simplifiedChinese:
            return "已将 \(agentID) 设为 \(stateDisplayName(state))。"
        }
    }

    public func clearedMessage(agentID: String) -> String {
        switch language {
        case .english:
            return "Cleared \(agentID)."
        case .traditionalChinese:
            return "已清除 \(agentID)。"
        case .simplifiedChinese:
            return "已清除 \(agentID)。"
        }
    }

    public func expiresMessage(_ date: Date) -> String {
        switch language {
        case .english:
            return "expires \(date)"
        case .traditionalChinese:
            return "到期 \(date)"
        case .simplifiedChinese:
            return "到期 \(date)"
        }
    }

    public func processSummary(pid: Int, cpuPercent: Double, state: String) -> String {
        switch language {
        case .english:
            return "PID \(pid), CPU \(String(format: "%.1f", cpuPercent))%, \(state)"
        case .traditionalChinese:
            return "PID \(pid)，CPU \(String(format: "%.1f", cpuPercent))%，\(state)"
        case .simplifiedChinese:
            return "PID \(pid)，CPU \(String(format: "%.1f", cpuPercent))%，\(state)"
        }
    }

    public func localizedReason(_ reason: String) -> String {
        guard language != .english else {
            return reason
        }

        if let exactReason = localizedExactReason(reason) {
            return exactReason
        }

        if let dynamicReason = localizedDynamicReason(reason) {
            return dynamicReason
        }

        return reason
    }

    private func localizedExactReason(_ reason: String) -> String? {
        switch (language, reason) {
        case (.traditionalChinese, "Manual override from signallanesctl."):
            return "來自 signallanesctl 的手動覆寫。"
        case (.simplifiedChinese, "Manual override from signallanesctl."):
            return "来自 signallanesctl 的手动覆盖。"
        case (.traditionalChinese, "Status reported by IDE session logs."):
            return "狀態由 IDE 工作階段 log 回報。"
        case (.simplifiedChinese, "Status reported by IDE session logs."):
            return "状态由 IDE 会话 log 报告。"
        case (.traditionalChinese, "No matching process detected."):
            return "沒有偵測到符合的 process。"
        case (.simplifiedChinese, "No matching process detected."):
            return "没有检测到匹配的 process。"
        case (.traditionalChinese, "A tracked IDE session is waiting for permission."):
            return "追蹤中的 IDE 工作階段正在等待授權。"
        case (.simplifiedChinese, "A tracked IDE session is waiting for permission."):
            return "追踪中的 IDE 会话正在等待授权。"
        case (.traditionalChinese, "Matched a permission or approval keyword."):
            return "符合授權或核准關鍵字。"
        case (.simplifiedChinese, "Matched a permission or approval keyword."):
            return "匹配到授权或批准关键词。"
        case (.traditionalChinese, "Matched a work-in-progress keyword."):
            return "符合工作進行中關鍵字。"
        case (.simplifiedChinese, "Matched a work-in-progress keyword."):
            return "匹配到工作进行中关键词。"
        case (.traditionalChinese, "A matching process is runnable."):
            return "符合的 process 目前可執行。"
        case (.simplifiedChinese, "A matching process is runnable."):
            return "匹配的 process 目前可运行。"
        case (.traditionalChinese, "A matching CLI agent process is running."):
            return "符合的 CLI agent process 正在執行。"
        case (.simplifiedChinese, "A matching CLI agent process is running."):
            return "匹配的 CLI agent process 正在运行。"
        case (.traditionalChinese, "Process is present, but no busy signal was detected."):
            return "Process 存在，但未偵測到忙碌訊號。"
        case (.simplifiedChinese, "Process is present, but no busy signal was detected."):
            return "Process 存在，但未检测到忙碌信号。"
        case (.traditionalChinese, "Codex Desktop session is active."):
            return "Codex Desktop 工作階段正在活動。"
        case (.simplifiedChinese, "Codex Desktop session is active."):
            return "Codex Desktop 会话正在活动。"
        case (.traditionalChinese, "Codex Desktop session is idle."):
            return "Codex Desktop 工作階段目前閒置。"
        case (.simplifiedChinese, "Codex Desktop session is idle."):
            return "Codex Desktop 会话目前空闲。"
        case (.traditionalChinese, "Codex Desktop session is waiting for permission."):
            return "Codex Desktop 工作階段正在等待授權。"
        case (.simplifiedChinese, "Codex Desktop session is waiting for permission."):
            return "Codex Desktop 会话正在等待授权。"
        case (.traditionalChinese, "Claude is requesting permission."):
            return "Claude 正在請求授權。"
        case (.simplifiedChinese, "Claude is requesting permission."):
            return "Claude 正在请求授权。"
        default:
            return nil
        }
    }

    private func localizedDynamicReason(_ reason: String) -> String? {
        if let projectText = reason.removingPrefix("Claude Desktop session is recently active: ") {
            switch language {
            case .english:
                return reason
            case .traditionalChinese:
                return "Claude Desktop 工作階段近期有活動：\(projectText)"
            case .simplifiedChinese:
                return "Claude Desktop 会话近期有活动：\(projectText)"
            }
        }

        if let projectText = reason.removingPrefix("Claude Desktop session is idle: ") {
            switch language {
            case .english:
                return reason
            case .traditionalChinese:
                return "Claude Desktop 工作階段目前閒置：\(projectText)"
            case .simplifiedChinese:
                return "Claude Desktop 会话目前空闲：\(projectText)"
            }
        }

        if let sourceName = reason.removingSuffix(" Claude log shows recent activity.") {
            switch language {
            case .english:
                return reason
            case .traditionalChinese:
                return "\(sourceName) Claude log 顯示近期活動。"
            case .simplifiedChinese:
                return "\(sourceName) Claude log 显示近期活动。"
            }
        }

        if let sourceName = reason.removingSuffix(" Claude session launched.") {
            switch language {
            case .english:
                return reason
            case .traditionalChinese:
                return "\(sourceName) Claude 工作階段已啟動。"
            case .simplifiedChinese:
                return "\(sourceName) Claude 会话已启动。"
            }
        }

        if let translated = localizedReason(
            reason,
            marker: " is waiting for permission.",
            traditionalText: "正在等待授權。",
            simplifiedText: "正在等待授权。"
        ) {
            return translated
        }

        if let translated = localizedReason(
            reason,
            marker: " session is running.",
            traditionalText: "工作階段正在執行。",
            simplifiedText: "会话正在运行。"
        ) {
            return translated
        }

        if let translated = localizedReason(
            reason,
            marker: " session is idle.",
            traditionalText: "工作階段目前閒置。",
            simplifiedText: "会话目前空闲。"
        ) {
            return translated
        }

        if reason.hasPrefix("Process "),
           let range = reason.range(of: " is using "),
           reason.hasSuffix("% CPU.") {
            let processText = String(reason[..<range.lowerBound])
            let cpuText = reason[range.upperBound...].dropLast(" CPU.".count)
            switch language {
            case .english:
                return reason
            case .traditionalChinese:
                return "\(processText) 正在使用 \(cpuText) CPU。"
            case .simplifiedChinese:
                return "\(processText) 正在使用 \(cpuText) CPU。"
            }
        }

        return nil
    }

    private func localizedReason(
        _ reason: String,
        marker: String,
        traditionalText: String,
        simplifiedText: String
    ) -> String? {
        guard let markerRange = reason.range(of: marker) else {
            return nil
        }

        let sourceName = String(reason[..<markerRange.lowerBound])
        let suffix = String(reason[markerRange.upperBound...])
        switch language {
        case .english:
            return reason
        case .traditionalChinese:
            return "\(sourceName) \(traditionalText)\(suffix)"
        case .simplifiedChinese:
            return "\(sourceName) \(simplifiedText)\(suffix)"
        }
    }
}

private extension String {
    func removingPrefix(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else {
            return nil
        }

        return String(dropFirst(prefix.count))
    }

    func removingSuffix(_ suffix: String) -> String? {
        guard hasSuffix(suffix) else {
            return nil
        }

        return String(dropLast(suffix.count))
    }
}
