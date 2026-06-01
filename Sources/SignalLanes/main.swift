import AppKit
import ApplicationServices
import SignalLanesCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum RefreshOutcome: Sendable {
        case success(DetectionResult)
        case failure(String)
    }

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let overrideStore: FileStatusOverrideStore
    private let taskHintProvider: CompositeTaskHintProvider
    private let floatingWindowController: FloatingSignalLanesWindowController
    private let refreshQueue = DispatchQueue(label: "signal-lanes.refresh", qos: .utility)
    private var refreshInFlight = false
    private var refreshTimer: Timer?
    private var lastResult: DetectionResult?

    override init() {
        overrideStore = FileStatusOverrideStore()
        taskHintProvider = DefaultTaskHintProvider.make()
        floatingWindowController = FloatingSignalLanesWindowController()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        if let button = statusItem.button {
            button.imagePosition = .imageOnly
            button.toolTip = "SignalLanes"
        }

        floatingWindowController.showIfEnabled()
        refresh()
        refreshTimer = Timer.scheduledTimer(
            timeInterval: 5,
            target: self,
            selector: #selector(refreshFromTimer),
            userInfo: nil,
            repeats: true
        )
    }

    @objc private func refreshFromTimer() {
        refresh()
    }

    @objc private func refreshFromMenu() {
        refresh()
    }

    private func refresh() {
        guard !refreshInFlight else {
            return
        }

        refreshInFlight = true
        let overrideFileURL = overrideStore.fileURL
        let taskHintProvider = taskHintProvider

        refreshQueue.async { [overrideFileURL, taskHintProvider] in
            let detector = AgentDetector(
                overrideProvider: FileStatusOverrideStore(fileURL: overrideFileURL),
                taskHintProvider: taskHintProvider
            )
            let outcome: RefreshOutcome
            do {
                outcome = .success(try detector.detect())
            } catch {
                outcome = .failure(String(describing: error))
            }

            Task { @MainActor [weak self, outcome] in
                self?.finishRefresh(outcome)
            }
        }
    }

    private func finishRefresh(_ outcome: RefreshOutcome) {
        refreshInFlight = false

        switch outcome {
        case .success(let result):
            let previousResult = lastResult
            lastResult = result
            updateStatusItem(result: result, previousResult: previousResult)
        case .failure(let message):
            updateStatusItem(errorMessage: message)
        }
    }

    private func refreshSynchronously() {
        do {
            let detector = AgentDetector(
                overrideProvider: overrideStore,
                taskHintProvider: taskHintProvider
            )
            let result = try detector.detect()
            let previousResult = lastResult
            lastResult = result
            updateStatusItem(result: result, previousResult: previousResult)
        } catch {
            updateStatusItem(errorMessage: String(describing: error))
        }
    }

    private func updateStatusItem(result: DetectionResult, previousResult: DetectionResult? = nil) {
        guard let button = statusItem.button else {
            return
        }

        if previousResult?.overallState != result.overallState || button.image == nil {
            button.image = SignalLanesImage.make(active: result.overallState)
        }
        button.toolTip = "SignalLanes: \(result.overallState.displayName)"

        let visibleResultChanged = previousResult.map {
            $0.overallState != result.overallState || $0.taskGroups != result.taskGroups
        } ?? true
        if visibleResultChanged {
            floatingWindowController.update(result: result)
        }
        statusItem.menu = makeMenu(result: result)
    }

    private func updateStatusItem(errorMessage: String) {
        guard let button = statusItem.button else {
            return
        }

        button.image = SignalLanesImage.make(active: .waitingForPermission)
        button.toolTip = "SignalLanes: \(errorMessage)"
        floatingWindowController.update(state: .waitingForPermission, message: "Detection failed")

        let menu = NSMenu()
        let item = NSMenuItem(title: "Detection failed: \(errorMessage)", action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
        menu.addItem(NSMenuItem.separator())
        addCommonMenuItems(to: menu)
        statusItem.menu = menu
    }

    private func makeMenu(result: DetectionResult) -> NSMenu {
        let menu = NSMenu()
        let taskGroups = result.taskGroups

        let summary = NSMenuItem(
            title: "SignalLanes: \(result.overallState.displayName)  |  \(queueSummary(for: taskGroups))",
            action: nil,
            keyEquivalent: ""
        )
        summary.isEnabled = false
        menu.addItem(summary)

        let scanTime = NSMenuItem(
            title: "Last scan: \(Self.timeFormatter.string(from: result.scannedAt))",
            action: nil,
            keyEquivalent: ""
        )
        scanTime.isEnabled = false
        menu.addItem(scanTime)
        menu.addItem(NSMenuItem.separator())

        addQueueSection(
            title: "Waiting for Permission",
            groups: taskGroups.filter { $0.state == .waitingForPermission },
            to: menu
        )
        menu.addItem(NSMenuItem.separator())
        addQueueSection(
            title: "Running",
            groups: taskGroups.filter { $0.state == .working },
            to: menu
        )
        menu.addItem(NSMenuItem.separator())
        addQueueSection(
            title: "Stopped",
            groups: taskGroups.filter { $0.state == .idle },
            to: menu
        )

        menu.addItem(NSMenuItem.separator())
        addCommonMenuItems(to: menu)
        return menu
    }

    private func addQueueSection(title: String, groups: [TaskGroupReport], to menu: NSMenu) {
        let header = NSMenuItem(title: "\(title) (\(groups.count))", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        if groups.isEmpty {
            let empty = NSMenuItem(title: "  None", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
            return
        }

        for group in groups {
            menu.addItem(menuItem(for: group))
        }
    }

    private func menuItem(for group: TaskGroupReport) -> NSMenuItem {
        let projectName = group.projectPath.map { URL(fileURLWithPath: $0).lastPathComponent }
            ?? group.tasks.first?.title
            ?? "Open session"
        let titleSuffix = group.count == 1 && group.projectPath != nil
            ? group.tasks.first?.title.map { " - \($0)" } ?? ""
            : ""
        let badgeSuffix = groupBadge(for: group).map { " · \($0)" } ?? ""
        let item = NSMenuItem(
            title: "\(stateSymbol(for: group.state)) \(group.displayName) / \(projectName)\(titleSuffix)\(badgeSuffix)",
            action: nil,
            keyEquivalent: ""
        )

        let submenu = NSMenu()
        let reasonText = group.count == 1
            ? group.tasks[0].reason
            : "Grouped \(group.count) sessions by IDE and project."
        let reason = NSMenuItem(title: reasonText, action: nil, keyEquivalent: "")
        reason.isEnabled = false
        submenu.addItem(reason)

        if let projectPath = group.projectPath {
            let project = NSMenuItem(title: "Project: \(projectPath)", action: nil, keyEquivalent: "")
            project.isEnabled = false
            submenu.addItem(project)
        }

        if group.count > 1 {
            submenu.addItem(NSMenuItem.separator())
            for task in group.tasks.prefix(8) {
                let title = task.title ?? task.sessionID ?? "Open session"
                let session = NSMenuItem(
                    title: "\(stateSymbol(for: task.state)) \(title)",
                    action: nil,
                    keyEquivalent: ""
                )
                session.isEnabled = false
                submenu.addItem(session)
            }
        } else if let sessionID = group.tasks.first?.sessionID {
            let session = NSMenuItem(title: "Session: \(sessionID)", action: nil, keyEquivalent: "")
            session.isEnabled = false
            submenu.addItem(session)
        }

        let firstSource = group.tasks[0].source
        let sourceValue = group.tasks.allSatisfy { $0.source == firstSource }
            ? firstSource.rawValue
            : "mixed"
        let source = NSMenuItem(title: "Source: \(sourceValue)", action: nil, keyEquivalent: "")
        source.isEnabled = false
        submenu.addItem(source)

        if !group.processes.isEmpty {
            submenu.addItem(NSMenuItem.separator())
            for process in group.processes.prefix(5) {
                let processItem = NSMenuItem(
                    title: "PID \(process.pid), CPU \(String(format: "%.1f", process.cpuPercent))%, \(process.state)",
                    action: nil,
                    keyEquivalent: ""
                )
                processItem.toolTip = process.commandPreview
                processItem.isEnabled = false
                submenu.addItem(processItem)
            }
        }

        item.submenu = submenu
        return item
    }

    private func addCommonMenuItems(to menu: NSMenu) {
        menu.addItem(NSMenuItem(
            title: "Refresh Now",
            action: #selector(refreshFromMenu),
            keyEquivalent: "r"
        ))
        menu.addItem(NSMenuItem(
            title: floatingWindowController.isEnabled ? "Hide Floating Light" : "Show Floating Light",
            action: #selector(toggleFloatingLight),
            keyEquivalent: "f"
        ))
        menu.addItem(NSMenuItem(
            title: "Reset Floating Position",
            action: #selector(resetFloatingPosition),
            keyEquivalent: ""
        ))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(themeMenuItem())
        menu.addItem(displaySizeMenuItem())
        menu.addItem(NSMenuItem.separator())
        let accessibilityTitle = AXIsProcessTrusted()
            ? "Precise Window Switching Enabled"
            : "Enable Precise Window Switching..."
        let accessibilityItem = NSMenuItem(
            title: accessibilityTitle,
            action: AXIsProcessTrusted() ? nil : #selector(requestAccessibilityPermission),
            keyEquivalent: ""
        )
        accessibilityItem.isEnabled = !AXIsProcessTrusted()
        menu.addItem(accessibilityItem)
        menu.addItem(NSMenuItem(
            title: "Open Status Folder",
            action: #selector(openStatusFolder),
            keyEquivalent: ""
        ))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(
            title: "Quit SignalLanes",
            action: #selector(quit),
            keyEquivalent: "q"
        ))
    }

    private func themeMenuItem() -> NSMenuItem {
        let selectedTheme = floatingWindowController.theme
        let item = NSMenuItem(title: "Theme: \(selectedTheme.displayName)", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        for theme in FloatingSignalLanesTheme.allCases {
            let themeItem = NSMenuItem(
                title: theme.displayName,
                action: #selector(selectFloatingTheme(_:)),
                keyEquivalent: ""
            )
            themeItem.target = self
            themeItem.representedObject = theme.rawValue
            themeItem.state = theme == selectedTheme ? .on : .off
            submenu.addItem(themeItem)
        }

        item.submenu = submenu
        return item
    }

    private func displaySizeMenuItem() -> NSMenuItem {
        let selectedSize = floatingWindowController.displaySize
        let item = NSMenuItem(title: "Display Size: \(selectedSize.displayName)", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        for displaySize in FloatingSignalLanesDisplaySize.allCases {
            let sizeItem = NSMenuItem(
                title: displaySize.displayName,
                action: #selector(selectFloatingDisplaySize(_:)),
                keyEquivalent: ""
            )
            sizeItem.target = self
            sizeItem.representedObject = displaySize.rawValue
            sizeItem.state = displaySize == selectedSize ? .on : .off
            submenu.addItem(sizeItem)
        }

        item.submenu = submenu
        return item
    }

    @objc private func openStatusFolder() {
        NSWorkspace.shared.open(overrideStore.directoryURL)
    }

    @objc private func toggleFloatingLight() {
        floatingWindowController.setEnabled(!floatingWindowController.isEnabled)
        if let lastResult {
            floatingWindowController.update(result: lastResult)
            statusItem.menu = makeMenu(result: lastResult)
        } else {
            refreshSynchronously()
        }
    }

    @objc private func selectFloatingTheme(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let theme = FloatingSignalLanesTheme(rawValue: rawValue)
        else {
            return
        }

        floatingWindowController.setTheme(theme)
        if let lastResult {
            floatingWindowController.update(result: lastResult)
            statusItem.menu = makeMenu(result: lastResult)
        } else {
            refreshSynchronously()
        }
    }

    @objc private func selectFloatingDisplaySize(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let displaySize = FloatingSignalLanesDisplaySize(rawValue: rawValue)
        else {
            return
        }

        floatingWindowController.setDisplaySize(displaySize)
        if let lastResult {
            floatingWindowController.update(result: lastResult)
            statusItem.menu = makeMenu(result: lastResult)
        } else {
            refreshSynchronously()
        }
    }

    @objc private func resetFloatingPosition() {
        floatingWindowController.resetPosition()
        floatingWindowController.setEnabled(true)
        if let lastResult {
            floatingWindowController.update(result: lastResult)
            statusItem.menu = makeMenu(result: lastResult)
        }
    }

    @objc private func requestAccessibilityPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let lastResult {
            statusItem.menu = makeMenu(result: lastResult)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func queueSummary(for groups: [TaskGroupReport]) -> String {
        let waiting = groups.filter { $0.state == .waitingForPermission }.count
        let running = groups.filter { $0.state == .working }.count
        let stopped = groups.filter { $0.state == .idle }.count
        return "\(waiting) waiting, \(running) running, \(stopped) stopped"
    }

    private func groupBadge(for group: TaskGroupReport) -> String? {
        let parts = [
            group.waitingCount > 0 ? "Y\(group.waitingCount)" : nil,
            group.runningCount > 0 ? "R\(group.runningCount)" : nil,
            group.stoppedCount > 0 ? "G\(group.stoppedCount)" : nil
        ].compactMap { $0 }

        if parts.count > 1 {
            return parts.joined(separator: " ")
        }

        return group.count > 1 ? "x\(group.count)" : nil
    }

    private func stateSymbol(for state: LightState) -> String {
        switch state {
        case .idle:
            return "Green"
        case .working:
            return "Red"
        case .waitingForPermission:
            return "Yellow"
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return formatter
    }()
}

@MainActor
private enum SignalLanesImage {
    private static var cache: [LightState: NSImage] = [:]

    static func make(active state: LightState) -> NSImage {
        if let image = cache[state] {
            return image
        }

        let size = NSSize(width: 56, height: 20)
        let image = NSImage(size: size)

        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()

        let housing = NSBezierPath(
            roundedRect: NSRect(x: 1, y: 1, width: 54, height: 18),
            xRadius: 9,
            yRadius: 9
        )
        NSColor(calibratedWhite: 0.08, alpha: 0.92).setFill()
        housing.fill()
        NSColor.white.withAlphaComponent(0.18).setStroke()
        housing.lineWidth = 0.8
        housing.stroke()

        let lights: [(LightState, NSColor, CGFloat)] = [
            (.working, .systemRed, 8),
            (.waitingForPermission, .systemYellow, 22),
            (.idle, .systemGreen, 36)
        ]

        for (lightState, color, x) in lights {
            drawLight(
                state: lightState,
                activeState: state,
                color: color,
                rect: NSRect(x: x, y: 5, width: 10, height: 10)
            )
        }

        image.unlockFocus()
        image.isTemplate = false
        cache[state] = image
        return image
    }

    private static func drawLight(
        state lightState: LightState,
        activeState: LightState,
        color: NSColor,
        rect: NSRect
    ) {
        let isActive = lightState == activeState
        let path = NSBezierPath(ovalIn: rect)

        if isActive {
            color.withAlphaComponent(0.42).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: -3, dy: -3)).fill()
        }

        if isActive {
            color.setFill()
        } else {
            NSColor(calibratedWhite: 0.18, alpha: 1).setFill()
        }
        path.fill()

        color.withAlphaComponent(isActive ? 0.95 : 0.42).setStroke()
        path.lineWidth = isActive ? 1.4 : 0.9
        path.stroke()

        if isActive {
            NSColor.white.withAlphaComponent(0.56).setFill()
            NSBezierPath(ovalIn: NSRect(
                x: rect.minX + 2.1,
                y: rect.maxY - 4.4,
                width: 3.4,
                height: 2.2
            )).fill()
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
