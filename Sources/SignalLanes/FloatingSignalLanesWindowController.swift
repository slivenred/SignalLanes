import AppKit
import ApplicationServices
import SignalLanesCore

enum FloatingSignalLanesTheme: String, CaseIterable {
    case midnightGlass
    case calendarLight
    case weatherBlue

    var displayName: String {
        switch self {
        case .midnightGlass:
            return "Midnight Glass"
        case .calendarLight:
            return "Calendar Light"
        case .weatherBlue:
            return "Weather Blue"
        }
    }
}

enum FloatingSignalLanesDisplaySize: String, CaseIterable {
    case small
    case medium
    case large

    var displayName: String {
        switch self {
        case .small:
            return "Small"
        case .medium:
            return "Medium"
        case .large:
            return "Large"
        }
    }
}

@MainActor
final class FloatingSignalLanesWindowController: NSObject, NSWindowDelegate {
    private enum DefaultsKey {
        static let isEnabled = "floatingLight.isEnabled"
        static let originX = "floatingLight.originX"
        static let originY = "floatingLight.originY"
        static let theme = "floatingLight.theme"
        static let displaySize = "floatingLight.displaySize"
    }

    private let defaults: UserDefaults
    private let indicatorView = FloatingSignalLanesView()
    private lazy var panel: NSPanel = makePanel()
    private var language = AppLanguage.defaultLanguage

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init()
        indicatorView.theme = theme
        indicatorView.displaySize = displaySize
        indicatorView.language = language
    }

    var isEnabled: Bool {
        if defaults.object(forKey: DefaultsKey.isEnabled) == nil {
            return true
        }

        return defaults.bool(forKey: DefaultsKey.isEnabled)
    }

    var theme: FloatingSignalLanesTheme {
        get {
            guard let rawValue = defaults.string(forKey: DefaultsKey.theme),
                  let theme = FloatingSignalLanesTheme(rawValue: rawValue)
            else {
                return .midnightGlass
            }

            return theme
        }
        set {
            defaults.set(newValue.rawValue, forKey: DefaultsKey.theme)
            indicatorView.theme = newValue
            resizePanel()
            showIfEnabled()
        }
    }

    var displaySize: FloatingSignalLanesDisplaySize {
        get {
            guard let rawValue = defaults.string(forKey: DefaultsKey.displaySize),
                  let displaySize = FloatingSignalLanesDisplaySize(rawValue: rawValue)
            else {
                return .medium
            }

            return displaySize
        }
        set {
            defaults.set(newValue.rawValue, forKey: DefaultsKey.displaySize)
            indicatorView.displaySize = newValue
            resizePanel()
            showIfEnabled()
        }
    }

    func showIfEnabled() {
        guard isEnabled else {
            panel.orderOut(nil)
            return
        }

        panel.orderFrontRegardless()
    }

    func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: DefaultsKey.isEnabled)
        if enabled {
            showIfEnabled()
        } else {
            panel.orderOut(nil)
        }
    }

    func setTheme(_ theme: FloatingSignalLanesTheme) {
        self.theme = theme
    }

    func setDisplaySize(_ displaySize: FloatingSignalLanesDisplaySize) {
        self.displaySize = displaySize
    }

    func setLanguage(_ language: AppLanguage) {
        self.language = language
        indicatorView.language = language
        updateToolTip()
    }

    func update(result: DetectionResult) {
        indicatorView.result = result
        indicatorView.fallbackState = result.overallState
        indicatorView.message = nil
        updateToolTip()
        resizePanel()
        showIfEnabled()
    }

    func update(state: LightState, message: String? = nil) {
        indicatorView.result = nil
        indicatorView.fallbackState = state
        indicatorView.message = message
        updateToolTip()
        resizePanel()
        showIfEnabled()
    }

    func resetPosition() {
        defaults.removeObject(forKey: DefaultsKey.originX)
        defaults.removeObject(forKey: DefaultsKey.originY)
        panel.setFrame(defaultFrame(), display: true)
        saveOrigin()
    }

    func windowDidMove(_ notification: Notification) {
        saveOrigin()
    }

    private func makePanel() -> NSPanel {
        let panel = NonActivatingPanel(
            contentRect: defaultFrame(),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.contentView = indicatorView
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.isOpaque = false
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.delegate = self
        return panel
    }

    private func updateToolTip() {
        let state = indicatorView.result?.overallState ?? indicatorView.fallbackState
        indicatorView.toolTip = SignalLanesLocalization(language: language).floatingToolTip(for: state)
    }

    private func defaultFrame() -> NSRect {
        let size = indicatorView.preferredSize

        if defaults.object(forKey: DefaultsKey.originX) != nil,
           defaults.object(forKey: DefaultsKey.originY) != nil {
            return constrainedFrame(NSRect(
                x: defaults.double(forKey: DefaultsKey.originX),
                y: defaults.double(forKey: DefaultsKey.originY),
                width: size.width,
                height: size.height
            ))
        }

        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return constrainedFrame(NSRect(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.maxY - size.height - 12,
            width: size.width,
            height: size.height
        ))
    }

    private func resizePanel() {
        let newSize = indicatorView.preferredSize
        var frame = panel.frame
        let topY = frame.maxY
        frame.size = newSize
        frame.origin.y = topY - newSize.height
        panel.setFrame(constrainedFrame(frame), display: true)
        saveOrigin()
    }

    private func saveOrigin() {
        let frame = constrainedFrame(panel.frame)
        defaults.set(frame.origin.x, forKey: DefaultsKey.originX)
        defaults.set(frame.origin.y, forKey: DefaultsKey.originY)
    }

    private func constrainedFrame(_ frame: NSRect) -> NSRect {
        let visibleFrame = visibleFrame(for: frame)
        let padding: CGFloat = 12
        let maxX = max(visibleFrame.minX + padding, visibleFrame.maxX - frame.width - padding)
        let maxY = max(visibleFrame.minY + padding, visibleFrame.maxY - frame.height - padding)

        return NSRect(
            x: min(max(frame.origin.x, visibleFrame.minX + padding), maxX),
            y: min(max(frame.origin.y, visibleFrame.minY + padding), maxY),
            width: frame.width,
            height: frame.height
        )
    }

    private func visibleFrame(for frame: NSRect) -> NSRect {
        NSScreen.screens
            .max { lhs, rhs in
                lhs.visibleFrame.intersection(frame).area < rhs.visibleFrame.intersection(frame).area
            }?
            .visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    }
}

private extension NSRect {
    var area: CGFloat {
        guard !isNull, !isEmpty else {
            return 0
        }

        return width * height
    }
}

private final class NonActivatingPanel: NSPanel {
    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }
}

private final class FloatingSignalLanesView: NSView {
    private typealias DisplayTaskGroup = TaskGroupReport

    private struct ActivationIdentity {
        var appNames: Set<String>
        var bundleIdentifiers: Set<String>
    }

    private struct MouseDownContext {
        var clickedGroup: DisplayTaskGroup?
        var clickedFilterState: LightState?
        var startMouseLocation: NSPoint
        var startWindowOrigin: NSPoint
        var didDrag: Bool
    }

    var fallbackState: LightState = .idle {
        didSet {
            needsDisplay = true
        }
    }
    var result: DetectionResult? {
        didSet {
            rebuildDisplayGroups()
        }
    }
    var message: String? {
        didSet {
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
        }
    }
    var theme: FloatingSignalLanesTheme = .midnightGlass {
        didSet {
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
        }
    }
    var displaySize: FloatingSignalLanesDisplaySize = .medium {
        didSet {
            clampScrollOffset()
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
        }
    }
    var language: AppLanguage = .defaultLanguage {
        didSet {
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
        }
    }

    private let dragThreshold: CGFloat = 4
    private var cachedDisplayGroups: [DisplayTaskGroup] = []
    private var mouseDownContext: MouseDownContext?
    private var selectedFilterState: LightState?
    private var scrollOffset = 0

    private var localized: SignalLanesLocalization {
        SignalLanesLocalization(language: language)
    }

    var preferredSize: NSSize {
        NSSize(
            width: panelWidth,
            height: headerHeight + CGFloat(maxVisibleTasks) * rowHeight + bottomPadding
        )
    }

    override var acceptsFirstResponder: Bool {
        false
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        let contentRect = bounds.insetBy(dx: 1, dy: 1)
        for rect in statusSegmentRects(in: contentRect) {
            addCursorRect(rect, cursor: .pointingHand)
        }
        for index in visibleTaskGroups().indices {
            addCursorRect(rowRect(at: index, contentRect: contentRect), cursor: .pointingHand)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let contentRect = bounds.insetBy(dx: 1, dy: 1)
        drawPanelBackground(in: contentRect)

        drawHeader(in: contentRect)
        drawTaskList(in: contentRect)
    }

    override func mouseDown(with event: NSEvent) {
        guard event.buttonNumber == 0, let window else {
            return
        }

        mouseDownContext = MouseDownContext(
            clickedGroup: group(at: convert(event.locationInWindow, from: nil)),
            clickedFilterState: filterState(at: convert(event.locationInWindow, from: nil)),
            startMouseLocation: NSEvent.mouseLocation,
            startWindowOrigin: window.frame.origin,
            didDrag: false
        )
    }

    override func mouseDragged(with event: NSEvent) {
        guard event.buttonNumber == 0,
              let window,
              var context = mouseDownContext
        else {
            return
        }

        let mouseLocation = NSEvent.mouseLocation
        let deltaX = mouseLocation.x - context.startMouseLocation.x
        let deltaY = mouseLocation.y - context.startMouseLocation.y

        if !context.didDrag, abs(deltaX) + abs(deltaY) >= dragThreshold {
            context.didDrag = true
        }

        if context.didDrag {
            window.setFrameOrigin(NSPoint(
                x: context.startWindowOrigin.x + deltaX,
                y: context.startWindowOrigin.y + deltaY
            ))
        }

        mouseDownContext = context
    }

    override func mouseUp(with event: NSEvent) {
        guard event.buttonNumber == 0,
              let context = mouseDownContext
        else {
            mouseDownContext = nil
            return
        }

        mouseDownContext = nil

        if !context.didDrag, let clickedFilterState = context.clickedFilterState {
            selectedFilterState = clickedFilterState
            scrollOffset = 0
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
            return
        }

        if !context.didDrag, let clickedGroup = context.clickedGroup {
            activateApplication(for: clickedGroup)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        guard maxVisibleTasks > 0 else {
            return
        }

        let groups = filteredGroups()
        let maxOffset = max(0, groups.count - maxVisibleTasks)
        guard maxOffset > 0 else {
            scrollOffset = 0
            return
        }

        let delta = event.scrollingDeltaY
        guard delta != 0 else {
            return
        }

        if delta < 0 {
            scrollOffset = min(maxOffset, scrollOffset + 1)
        } else {
            scrollOffset = max(0, scrollOffset - 1)
        }

        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    private func drawHeader(in rect: NSRect) {
        let counts = queueCounts(for: cachedDisplayGroups)
        let titleRect = NSRect(
            x: rect.minX + horizontalInset + 4,
            y: rect.maxY - (displaySize == .large ? 35 : 31),
            width: rect.width - horizontalInset * 2 - statusPillWidth - 14,
            height: 20
        )
        drawText(
            "SignalLanes",
            in: titleRect,
            font: .systemFont(ofSize: displaySize == .large ? 15.5 : 14, weight: .bold),
            color: primaryTextColor
        )

        drawText(
            summaryText(for: counts),
            in: NSRect(
                x: rect.minX + horizontalInset + 4,
                y: rect.maxY - (displaySize == .large ? 54 : 48),
                width: rect.width - horizontalInset * 2 - 8,
                height: 14
            ),
            font: .systemFont(ofSize: displaySize == .large ? 11.5 : 11, weight: .medium),
            color: secondaryTextColor
        )

        drawStatusPill(in: rect)

        for segment in statusSegments(in: rect, counts: counts) {
            drawStatusSegment(
                state: segment.state,
                count: segment.count,
                label: segment.label,
                in: segment.rect
            )
        }

        let separatorY = rect.maxY - headerHeight + (displaySize == .large ? 5 : 3)
        separatorColor.setStroke()
        let separator = NSBezierPath()
        separator.move(to: NSPoint(x: rect.minX + horizontalInset + 1, y: separatorY))
        separator.line(to: NSPoint(x: rect.maxX - horizontalInset - 1, y: separatorY))
        separator.lineWidth = 1
        separator.stroke()
    }

    private func drawPanelBackground(in rect: NSRect) {
        let radius = panelCornerRadius
        let backgroundPath = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

        NSGraphicsContext.saveGraphicsState()
        backgroundPath.addClip()
        drawThemeBackgroundFill(in: rect)
        NSGraphicsContext.restoreGraphicsState()

        outerBorderColor.setStroke()
        backgroundPath.lineWidth = 1
        backgroundPath.stroke()

        let innerPath = NSBezierPath(
            roundedRect: rect.insetBy(dx: 1.25, dy: 1.25),
            xRadius: radius - 1.25,
            yRadius: radius - 1.25
        )
        innerBorderColor.setStroke()
        innerPath.lineWidth = 1
        innerPath.stroke()
    }

    private func drawThemeBackgroundFill(in rect: NSRect) {
        switch theme {
        case .midnightGlass:
            NSGradient(colors: [
                NSColor(calibratedRed: 0.078, green: 0.087, blue: 0.108, alpha: 0.98),
                NSColor(calibratedRed: 0.024, green: 0.028, blue: 0.037, alpha: 0.98)
            ])?.draw(in: rect, angle: -90)

            drawTopTint(in: rect, alpha: 0.20)
            drawTopShine(in: rect, alpha: 0.14)

        case .calendarLight:
            NSGradient(colors: [
                NSColor(calibratedWhite: 1.0, alpha: 0.98),
                NSColor(calibratedRed: 0.943, green: 0.948, blue: 0.958, alpha: 0.98)
            ])?.draw(in: rect, angle: -90)

            drawTopTint(in: rect, alpha: 0.075)
            drawTopShine(in: rect, alpha: 0.32)

        case .weatherBlue:
            NSGradient(colors: [
                NSColor(calibratedRed: 0.188, green: 0.342, blue: 0.602, alpha: 0.96),
                NSColor(calibratedRed: 0.322, green: 0.556, blue: 0.796, alpha: 0.96)
            ])?.draw(in: rect, angle: -90)

            drawTopTint(in: rect, alpha: 0.12)
            drawTopShine(in: rect, alpha: 0.20)
        }
    }

    private func drawTopTint(in rect: NSRect, alpha: CGFloat) {
        let topBand = NSRect(x: rect.minX, y: rect.maxY - 108, width: rect.width, height: 108)
        NSGradient(colors: [
            lightColor(for: currentState).withAlphaComponent(alpha),
            NSColor.white.withAlphaComponent(theme == .calendarLight ? 0.08 : 0.045),
            NSColor.clear
        ])?.draw(in: topBand, angle: -90)
    }

    private func drawTopShine(in rect: NSRect, alpha: CGFloat) {
        let shineRect = NSRect(x: rect.minX + 2, y: rect.maxY - 58, width: rect.width - 4, height: 55)
        NSGradient(colors: [
            NSColor.white.withAlphaComponent(alpha),
            NSColor.white.withAlphaComponent(max(alpha * 0.14, 0.015)),
            NSColor.clear
        ])?.draw(in: shineRect, angle: -90)
    }

    private func drawStatusPill(in rect: NSRect) {
        let color = lightColor(for: currentState)
        let pillRect = NSRect(
            x: rect.maxX - horizontalInset - statusPillWidth,
            y: rect.maxY - (displaySize == .large ? 36 : 33),
            width: statusPillWidth,
            height: statusPillHeight
        )
        let path = NSBezierPath(
            roundedRect: pillRect,
            xRadius: statusPillHeight / 2,
            yRadius: statusPillHeight / 2
        )
        statusPillFillColor(for: color).setFill()
        path.fill()
        statusPillStrokeColor(for: color).setStroke()
        path.lineWidth = 1
        path.stroke()

        drawText(
            statusPillLabel(for: currentState),
            in: pillRect.insetBy(dx: 8, dy: 3),
            font: .systemFont(ofSize: displaySize == .large ? 11 : 10.5, weight: .semibold),
            color: statusPillTextColor(for: color),
            alignment: .center
        )
    }

    private func drawStatusSegment(state: LightState, count: Int, label: String, in rect: NSRect) {
        let color = lightColor(for: state)
        let selected = state == activeFilterState
        let active = state == currentState
        let segmentRadius = min(rect.height / 2, displaySize == .large ? 14 : 11)
        let path = NSBezierPath(roundedRect: rect, xRadius: segmentRadius, yRadius: segmentRadius)

        segmentFillColor(for: color, active: active, selected: selected).setFill()
        path.fill()

        segmentStrokeColor(for: color, selected: selected).setStroke()
        path.lineWidth = selected ? 1.1 : 1
        path.stroke()

        let dotSize: CGFloat = displaySize == .large ? 10 : 8
        drawStatusDot(
            state: state,
            active: active,
            selected: selected,
            in: NSRect(x: rect.minX + 10, y: rect.midY - dotSize / 2, width: dotSize, height: dotSize)
        )

        let labelX = rect.minX + (displaySize == .large ? 30 : 25)
        let countWidth: CGFloat = displaySize == .small ? 16 : 22
        drawText(
            displaySize == .small ? shortSegmentLabel(for: state) : label,
            in: NSRect(
                x: labelX,
                y: rect.midY - 7,
                width: max(18, rect.maxX - labelX - countWidth - 9),
                height: 15
            ),
            font: .systemFont(ofSize: displaySize == .large ? 12.5 : 11.5, weight: selected ? .semibold : .medium),
            color: segmentLabelColor(selected: selected)
        )

        drawText(
            "\(count)",
            in: NSRect(x: rect.maxX - countWidth - 9, y: rect.midY - 7, width: countWidth, height: 15),
            font: .monospacedDigitSystemFont(ofSize: displaySize == .large ? 11.5 : 11, weight: .semibold),
            color: segmentCountColor(for: color, selected: selected),
            alignment: .right
        )
    }

    private func drawStatusDot(state: LightState, active: Bool, selected: Bool, in rect: NSRect) {
        let color = lightColor(for: state)
        if active || selected {
            color.withAlphaComponent(active ? 0.30 : 0.18).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: -5, dy: -5)).fill()
        }

        let dotPath = NSBezierPath(ovalIn: rect)
        if active {
            color.setFill()
        } else if selected {
            color.withAlphaComponent(0.72).setFill()
        } else {
            inactiveDotColor.setFill()
        }
        dotPath.fill()

        color.withAlphaComponent(active || selected ? 0.90 : 0.42).setStroke()
        dotPath.lineWidth = active || selected ? 1.3 : 1
        dotPath.stroke()

        if active {
            NSColor.white.withAlphaComponent(0.56).setFill()
            NSBezierPath(ovalIn: NSRect(
                x: rect.minX + 2.4,
                y: rect.maxY - 3.8,
                width: 3.2,
                height: 2.0
            )).fill()
        }
    }

    private var currentState: LightState {
        result?.overallState ?? fallbackState
    }

    private var activeFilterState: LightState {
        selectedFilterState ?? currentState
    }

    private func rebuildDisplayGroups() {
        cachedDisplayGroups = makeDisplayGroups()
        clampScrollOffset()
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    private func makeDisplayGroups() -> [DisplayTaskGroup] {
        guard let result else {
            return []
        }

        return result.taskGroups.filter { group in
            group.tasks.contains(where: shouldDisplay)
        }
    }

    private func drawTaskList(in rect: NSRect) {
        let groups = filteredGroups()
        let visibleGroups = visibleTaskGroups(from: groups)
        var rowY = rect.maxY - headerHeight - rowHeight + 6

        if let message {
            let messageRect = NSRect(
                x: rect.minX + horizontalInset,
                y: rowY - (displaySize == .small ? 5 : 8),
                width: rect.width - horizontalInset * 2,
                height: displaySize == .small ? 28 : 32
            )
            drawMessageWell(in: messageRect, color: .systemYellow)
            drawText(
                message,
                in: messageRect.insetBy(dx: 12, dy: displaySize == .small ? 6 : 8),
                font: .systemFont(ofSize: displaySize == .large ? 12.5 : 12, weight: .medium),
                color: messageTextColor(for: .systemYellow)
            )
            return
        }

        guard !groups.isEmpty else {
            let emptyRect = NSRect(
                x: rect.minX + horizontalInset,
                y: rowY - (displaySize == .small ? 5 : 8),
                width: rect.width - horizontalInset * 2,
                height: displaySize == .small ? 28 : 32
            )
            drawMessageWell(in: emptyRect, color: lightColor(for: activeFilterState))
            drawText(
                emptyMessage(for: activeFilterState),
                in: emptyRect.insetBy(dx: 12, dy: displaySize == .small ? 6 : 8),
                font: .systemFont(ofSize: displaySize == .large ? 12.5 : 12, weight: .medium),
                color: mutedTextColor
            )
            return
        }

        for (index, group) in visibleGroups.enumerated() {
            drawTaskRow(group, in: rowRect(at: index, contentRect: rect))
            rowY -= rowHeight
        }

        if groups.count > maxVisibleTasks, displaySize != .small {
            drawText(
                "\(scrollOffset + 1)-\(scrollOffset + visibleGroups.count) / \(groups.count)",
                in: NSRect(
                    x: rect.minX + horizontalInset,
                    y: rowY + 7,
                    width: rect.width - horizontalInset * 2,
                    height: 14
                ),
                font: .systemFont(ofSize: 10.5, weight: .medium),
                color: secondaryTextColor,
                alignment: .right
            )
        }
    }

    private func drawTaskRow(_ group: DisplayTaskGroup, in rowRect: NSRect) {
        let rowPath = NSBezierPath(roundedRect: rowRect, xRadius: 7, yRadius: 7)
        rowFillColor(active: group.state == currentState).setFill()
        rowPath.fill()
        rowStrokeColor(active: group.state == currentState).setStroke()
        rowPath.lineWidth = 1
        rowPath.stroke()

        let color = lightColor(for: group.state)
        let accentRect = NSRect(x: rowRect.minX + 8, y: rowRect.minY + 7, width: 3, height: rowRect.height - 14)
        let accentPath = NSBezierPath(roundedRect: accentRect, xRadius: 1.5, yRadius: 1.5)
        color.withAlphaComponent(group.state == currentState ? 0.88 : 0.54).setFill()
        accentPath.fill()

        let dotRect = NSRect(x: rowRect.minX + 17, y: rowRect.midY - 3.5, width: 7, height: 7)
        color.withAlphaComponent(0.20).setFill()
        NSBezierPath(ovalIn: dotRect.insetBy(dx: -3, dy: -3)).fill()
        color.setFill()
        NSBezierPath(ovalIn: dotRect).fill()

        let badge = groupBadge(for: group)
        let badgeWidth = badge.map { widthForBadge($0) } ?? 0
        let titleX = rowRect.minX + 31

        drawText(
            groupTitle(group),
            in: NSRect(
                x: titleX,
                y: rowRect.midY - 7.5,
                width: max(24, rowRect.maxX - titleX - 12 - badgeWidth),
                height: 16
            ),
            font: .systemFont(ofSize: displaySize == .large ? 12.5 : 12, weight: .semibold),
            color: primaryTextColor
        )

        if let badge {
            let badgeRect = NSRect(x: rowRect.maxX - badgeWidth - 8, y: rowRect.midY - 8, width: badgeWidth, height: 16)
            let badgePath = NSBezierPath(roundedRect: badgeRect, xRadius: 8, yRadius: 8)
            badgeFillColor.setFill()
            badgePath.fill()
            badgeStrokeColor.setStroke()
            badgePath.lineWidth = 1
            badgePath.stroke()

            drawText(
                badge,
                in: badgeRect.insetBy(dx: 7, dy: 2),
                font: .monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold),
                color: badgeTextColor,
                alignment: .right
            )
        }
    }

    private func group(at point: NSPoint) -> DisplayTaskGroup? {
        let contentRect = bounds.insetBy(dx: 1, dy: 1)
        for (index, group) in visibleTaskGroups().enumerated() {
            if rowRect(at: index, contentRect: contentRect).contains(point) {
                return group
            }
        }

        return nil
    }

    private func filterState(at point: NSPoint) -> LightState? {
        let contentRect = bounds.insetBy(dx: 1, dy: 1)
        let states: [LightState] = [.working, .waitingForPermission, .idle]

        for (index, rect) in statusSegmentRects(in: contentRect).enumerated() {
            if rect.contains(point) {
                return states[index]
            }
        }

        return nil
    }

    private func rowRect(at index: Int, contentRect rect: NSRect) -> NSRect {
        let rowY = rect.maxY - headerHeight - rowHeight + 6 - CGFloat(index) * rowHeight
        return NSRect(
            x: rect.minX + horizontalInset,
            y: rowY,
            width: rect.width - horizontalInset * 2,
            height: rowHeight - 4
        )
    }

    private func shouldDisplay(_ task: TaskReport) -> Bool {
        !task.processes.isEmpty
            || task.source == .manualOverride
            || task.sessionID != nil
            || task.projectPath != nil
            || task.title != nil
    }

    private func groupTitle(_ group: DisplayTaskGroup) -> String {
        let projectLabel = group.projectPath.map { projectName(for: $0) }
            ?? group.tasks.first?.title
            ?? fallbackName()
        return "\(group.displayName) / \(projectLabel)"
    }

    private func groupBadge(for group: DisplayTaskGroup) -> String? {
        let parts = stateBreakdownParts(for: group)
        if parts.count > 1 {
            return parts.joined(separator: " ")
        }

        return group.count > 1 ? "x\(group.count)" : nil
    }

    private func fallbackName() -> String {
        localized.openSession
    }

    private func filteredGroups() -> [DisplayTaskGroup] {
        cachedDisplayGroups.filter { $0.state == activeFilterState }
    }

    private func visibleTaskGroups() -> [DisplayTaskGroup] {
        visibleTaskGroups(from: filteredGroups())
    }

    private func visibleTaskGroups(from groups: [DisplayTaskGroup]) -> [DisplayTaskGroup] {
        guard !groups.isEmpty else {
            return []
        }

        let safeOffset = min(scrollOffset, max(0, groups.count - 1))
        return Array(groups.dropFirst(safeOffset).prefix(maxVisibleTasks))
    }

    private func clampScrollOffset() {
        let maxOffset = max(0, filteredGroups().count - maxVisibleTasks)
        scrollOffset = min(max(0, scrollOffset), maxOffset)
    }

    private func emptyMessage(for state: LightState) -> String {
        localized.emptyMessage(for: state)
    }

    private func queueCounts(for groups: [DisplayTaskGroup]) -> (waiting: Int, running: Int, stopped: Int) {
        (
            groups.filter { $0.state == .waitingForPermission }.count,
            groups.filter { $0.state == .working }.count,
            groups.filter { $0.state == .idle }.count
        )
    }

    private func summaryText(for counts: (waiting: Int, running: Int, stopped: Int)) -> String {
        let total = counts.running + counts.waiting + counts.stopped
        guard total > 0 else {
            return localized.noTrackedSessions
        }

        return localized.floatingSummary(
            running: counts.running,
            waiting: counts.waiting,
            stopped: counts.stopped
        )
    }

    private func statusSegments(
        in rect: NSRect,
        counts: (waiting: Int, running: Int, stopped: Int)
    ) -> [(state: LightState, count: Int, label: String, rect: NSRect)] {
        let specs: [(state: LightState, count: Int, label: String)] = [
            (.working, counts.running, localized.segmentLabel(for: .working)),
            (.waitingForPermission, counts.waiting, localized.segmentLabel(for: .waitingForPermission)),
            (.idle, counts.stopped, localized.segmentLabel(for: .idle))
        ]
        let rects = statusSegmentRects(in: rect)

        return specs.enumerated().map { index, spec in
            (state: spec.state, count: spec.count, label: spec.label, rect: rects[index])
        }
    }

    private func statusSegmentRects(in rect: NSRect) -> [NSRect] {
        let controlHeight: CGFloat = displaySize == .large ? 38 : 30
        let controlTopOffset: CGFloat = displaySize == .large ? 92 : 80
        let spacing: CGFloat = displaySize == .large ? 8 : 6
        let controlRect = NSRect(
            x: rect.minX + horizontalInset,
            y: rect.maxY - controlTopOffset,
            width: rect.width - horizontalInset * 2,
            height: controlHeight
        )
        let baseWidth = floor((controlRect.width - spacing * 2) / 3)

        return (0..<3).map { index in
            let x = controlRect.minX + CGFloat(index) * (baseWidth + spacing)
            let width = index == 2 ? controlRect.maxX - x : baseWidth
            return NSRect(x: x, y: controlRect.minY, width: width, height: controlRect.height)
        }
    }

    private func statusPillLabel(for state: LightState) -> String {
        localized.statusPillLabel(for: state)
    }

    private func shortSegmentLabel(for state: LightState) -> String {
        localized.shortSegmentLabel(for: state)
    }

    private func drawMessageWell(in rect: NSRect, color: NSColor) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 9, yRadius: 9)
        messageWellFillColor.setFill()
        path.fill()
        messageWellStrokeColor(for: color).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    private func widthForBadge(_ badge: String) -> CGFloat {
        min(max(CGFloat(badge.count) * 7 + 16, 36), 86)
    }

    private var panelWidth: CGFloat {
        switch displaySize {
        case .small:
            return 278
        case .medium:
            return 342
        case .large:
            return 430
        }
    }

    private var maxVisibleTasks: Int {
        switch displaySize {
        case .small:
            return 1
        case .medium:
            return 8
        case .large:
            return 11
        }
    }

    private var headerHeight: CGFloat {
        switch displaySize {
        case .small, .medium:
            return 84
        case .large:
            return 104
        }
    }

    private var rowHeight: CGFloat {
        switch displaySize {
        case .small:
            return 32
        case .medium:
            return 29
        case .large:
            return 31
        }
    }

    private var bottomPadding: CGFloat {
        switch displaySize {
        case .small:
            return 14
        case .medium:
            return 22
        case .large:
            return 26
        }
    }

    private var horizontalInset: CGFloat {
        switch displaySize {
        case .small, .medium:
            return 14
        case .large:
            return 16
        }
    }

    private var statusPillWidth: CGFloat {
        switch displaySize {
        case .small:
            return 68
        case .medium:
            return 74
        case .large:
            return 86
        }
    }

    private var statusPillHeight: CGFloat {
        switch displaySize {
        case .small, .medium:
            return 21
        case .large:
            return 24
        }
    }

    private var panelCornerRadius: CGFloat {
        switch (theme, displaySize) {
        case (.calendarLight, .small):
            return 28
        case (.calendarLight, _):
            return 34
        case (.weatherBlue, .small):
            return 26
        case (.weatherBlue, _):
            return 30
        case (.midnightGlass, .small):
            return 22
        case (.midnightGlass, _):
            return 24
        }
    }

    private var primaryTextColor: NSColor {
        switch theme {
        case .calendarLight:
            return NSColor(calibratedWhite: 0.12, alpha: 0.94)
        case .midnightGlass, .weatherBlue:
            return .white.withAlphaComponent(0.94)
        }
    }

    private var secondaryTextColor: NSColor {
        switch theme {
        case .calendarLight:
            return NSColor(calibratedWhite: 0.24, alpha: 0.58)
        case .midnightGlass, .weatherBlue:
            return .white.withAlphaComponent(0.52)
        }
    }

    private var mutedTextColor: NSColor {
        switch theme {
        case .calendarLight:
            return NSColor(calibratedWhite: 0.22, alpha: 0.62)
        case .midnightGlass, .weatherBlue:
            return .white.withAlphaComponent(0.62)
        }
    }

    private var separatorColor: NSColor {
        switch theme {
        case .calendarLight:
            return NSColor.black.withAlphaComponent(0.07)
        case .midnightGlass, .weatherBlue:
            return .white.withAlphaComponent(0.08)
        }
    }

    private var outerBorderColor: NSColor {
        switch theme {
        case .midnightGlass:
            return .white.withAlphaComponent(0.20)
        case .calendarLight:
            return NSColor.black.withAlphaComponent(0.08)
        case .weatherBlue:
            return .white.withAlphaComponent(0.30)
        }
    }

    private var innerBorderColor: NSColor {
        switch theme {
        case .midnightGlass:
            return NSColor.black.withAlphaComponent(0.28)
        case .calendarLight:
            return .white.withAlphaComponent(0.68)
        case .weatherBlue:
            return .white.withAlphaComponent(0.12)
        }
    }

    private var inactiveDotColor: NSColor {
        switch theme {
        case .calendarLight:
            return NSColor.black.withAlphaComponent(0.18)
        case .midnightGlass:
            return NSColor(calibratedWhite: 0.28, alpha: 1)
        case .weatherBlue:
            return .white.withAlphaComponent(0.34)
        }
    }

    private var messageWellFillColor: NSColor {
        switch theme {
        case .calendarLight:
            return NSColor.black.withAlphaComponent(0.035)
        case .midnightGlass:
            return .white.withAlphaComponent(0.045)
        case .weatherBlue:
            return .white.withAlphaComponent(0.08)
        }
    }

    private var badgeFillColor: NSColor {
        switch theme {
        case .calendarLight:
            return NSColor.black.withAlphaComponent(0.055)
        case .midnightGlass:
            return NSColor.black.withAlphaComponent(0.20)
        case .weatherBlue:
            return NSColor.black.withAlphaComponent(0.15)
        }
    }

    private var badgeStrokeColor: NSColor {
        switch theme {
        case .calendarLight:
            return NSColor.black.withAlphaComponent(0.05)
        case .midnightGlass, .weatherBlue:
            return .white.withAlphaComponent(0.06)
        }
    }

    private var badgeTextColor: NSColor {
        switch theme {
        case .calendarLight:
            return NSColor(calibratedWhite: 0.18, alpha: 0.58)
        case .midnightGlass, .weatherBlue:
            return .white.withAlphaComponent(0.54)
        }
    }

    private func statusPillFillColor(for color: NSColor) -> NSColor {
        switch theme {
        case .calendarLight:
            return color.withAlphaComponent(0.10)
        case .midnightGlass:
            return color.withAlphaComponent(0.18)
        case .weatherBlue:
            return .white.withAlphaComponent(0.13)
        }
    }

    private func statusPillStrokeColor(for color: NSColor) -> NSColor {
        switch theme {
        case .calendarLight:
            return color.withAlphaComponent(0.24)
        case .midnightGlass:
            return color.withAlphaComponent(0.42)
        case .weatherBlue:
            return .white.withAlphaComponent(0.22)
        }
    }

    private func statusPillTextColor(for color: NSColor) -> NSColor {
        switch theme {
        case .calendarLight:
            return color.withAlphaComponent(0.95)
        case .midnightGlass:
            return color.withAlphaComponent(0.95)
        case .weatherBlue:
            return .white.withAlphaComponent(0.94)
        }
    }

    private func segmentFillColor(for color: NSColor, active: Bool, selected: Bool) -> NSColor {
        switch theme {
        case .midnightGlass:
            return selected
                ? color.withAlphaComponent(active ? 0.22 : 0.15)
                : .white.withAlphaComponent(active ? 0.075 : 0.048)
        case .calendarLight:
            return selected
                ? color.withAlphaComponent(active ? 0.17 : 0.12)
                : NSColor.black.withAlphaComponent(active ? 0.045 : 0.026)
        case .weatherBlue:
            return selected
                ? .white.withAlphaComponent(active ? 0.20 : 0.16)
                : .white.withAlphaComponent(active ? 0.12 : 0.075)
        }
    }

    private func segmentStrokeColor(for color: NSColor, selected: Bool) -> NSColor {
        switch theme {
        case .midnightGlass:
            return selected ? color.withAlphaComponent(0.52) : .white.withAlphaComponent(0.075)
        case .calendarLight:
            return selected ? color.withAlphaComponent(0.32) : NSColor.black.withAlphaComponent(0.055)
        case .weatherBlue:
            return selected ? .white.withAlphaComponent(0.34) : .white.withAlphaComponent(0.12)
        }
    }

    private func segmentLabelColor(selected: Bool) -> NSColor {
        switch theme {
        case .calendarLight:
            return NSColor(calibratedWhite: 0.12, alpha: selected ? 0.88 : 0.58)
        case .midnightGlass, .weatherBlue:
            return .white.withAlphaComponent(selected ? 0.91 : 0.63)
        }
    }

    private func segmentCountColor(for color: NSColor, selected: Bool) -> NSColor {
        switch theme {
        case .calendarLight:
            return selected ? NSColor(calibratedWhite: 0.10, alpha: 0.88) : color.withAlphaComponent(0.92)
        case .midnightGlass:
            return selected ? .white.withAlphaComponent(0.92) : color.withAlphaComponent(0.78)
        case .weatherBlue:
            return selected ? .white.withAlphaComponent(0.95) : .white.withAlphaComponent(0.72)
        }
    }

    private func rowFillColor(active: Bool) -> NSColor {
        switch theme {
        case .calendarLight:
            return NSColor.black.withAlphaComponent(active ? 0.052 : 0.030)
        case .midnightGlass:
            return .white.withAlphaComponent(active ? 0.075 : 0.052)
        case .weatherBlue:
            return .white.withAlphaComponent(active ? 0.13 : 0.082)
        }
    }

    private func rowStrokeColor(active: Bool) -> NSColor {
        switch theme {
        case .calendarLight:
            return NSColor.black.withAlphaComponent(active ? 0.070 : 0.045)
        case .midnightGlass:
            return .white.withAlphaComponent(active ? 0.095 : 0.055)
        case .weatherBlue:
            return .white.withAlphaComponent(active ? 0.18 : 0.10)
        }
    }

    private func messageTextColor(for color: NSColor) -> NSColor {
        switch theme {
        case .calendarLight:
            return color.blended(withFraction: 0.34, of: .black)?.withAlphaComponent(0.95)
                ?? color.withAlphaComponent(0.95)
        case .midnightGlass:
            return color.withAlphaComponent(0.94)
        case .weatherBlue:
            return .white.withAlphaComponent(0.92)
        }
    }

    private func messageWellStrokeColor(for color: NSColor) -> NSColor {
        switch theme {
        case .calendarLight:
            return color.withAlphaComponent(0.18)
        case .midnightGlass:
            return color.withAlphaComponent(0.14)
        case .weatherBlue:
            return .white.withAlphaComponent(0.14)
        }
    }

    private func stateBreakdownParts(for group: DisplayTaskGroup) -> [String] {
        localized.badgeParts(
            waiting: group.waitingCount,
            running: group.runningCount,
            stopped: group.stoppedCount
        )
    }

    private func lightColor(for state: LightState) -> NSColor {
        switch (theme, state) {
        case (_, .idle):
            return NSColor(calibratedRed: 0.17, green: 0.72, blue: 0.37, alpha: 1)
        case (.calendarLight, .working):
            return NSColor(calibratedRed: 0.94, green: 0.24, blue: 0.22, alpha: 1)
        case (.calendarLight, .waitingForPermission):
            return NSColor(calibratedRed: 0.90, green: 0.58, blue: 0.05, alpha: 1)
        case (.weatherBlue, .working):
            return NSColor(calibratedRed: 1.00, green: 0.37, blue: 0.34, alpha: 1)
        case (.weatherBlue, .waitingForPermission):
            return NSColor(calibratedRed: 1.00, green: 0.84, blue: 0.18, alpha: 1)
        case (.midnightGlass, .working):
            return .systemRed
        case (.midnightGlass, .waitingForPermission):
            return .systemYellow
        }
    }

    private func projectName(for path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    private func activateApplication(for group: DisplayTaskGroup) {
        if activateCodexTarget(for: group) {
            return
        }

        if activateProjectWindow(for: group) {
            return
        }

        if activateRunningApplication(for: group) {
            return
        }

        if activateApplicationByProcess(group.processes) {
            return
        }

        openApplication(for: group.agentID)
    }

    private func activateCodexTarget(for group: DisplayTaskGroup) -> Bool {
        guard group.agentID == "codex" else {
            return false
        }

        if let sessionID = group.sessionIDs.first,
           let url = codexThreadURL(for: sessionID),
           NSWorkspace.shared.open(url) {
            return true
        }

        return false
    }

    private func activateProjectWindow(for group: DisplayTaskGroup) -> Bool {
        guard let projectPath = group.projectPath else {
            return false
        }

        guard canUseAccessibilityWindowActivation() else {
            return false
        }

        let candidates = windowTitleCandidates(for: projectPath)
        guard !candidates.isEmpty else {
            return false
        }

        for application in matchingRunningApplications(for: group) {
            if raiseWindow(matchingAnyOf: candidates, in: application) {
                return true
            }
        }

        return false
    }

    private func canUseAccessibilityWindowActivation() -> Bool {
        AXIsProcessTrusted()
    }

    private func codexThreadURL(for sessionID: String) -> URL? {
        let allowedCharacters = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#"))
        guard let encodedSessionID = sessionID.addingPercentEncoding(withAllowedCharacters: allowedCharacters) else {
            return nil
        }

        return URL(string: "codex://threads/\(encodedSessionID)")
    }

    private func activateApplicationByProcess(_ processes: [MatchedProcess]) -> Bool {
        var seenPIDs = Set<Int>()
        for process in processes where seenPIDs.insert(process.pid).inserted {
            guard let application = NSRunningApplication(processIdentifier: pid_t(process.pid)) else {
                continue
            }

            application.unhide()
            if application.activate() {
                return true
            }
        }

        return false
    }

    private func activateRunningApplication(for group: DisplayTaskGroup) -> Bool {
        for application in matchingRunningApplications(for: group) {
            application.unhide()
            if application.activate() {
                return true
            }
        }

        return false
    }

    private func matchingRunningApplications(for group: DisplayTaskGroup) -> [NSRunningApplication] {
        let identity = activationIdentity(for: group.agentID, displayName: group.displayName)
        guard !identity.appNames.isEmpty || !identity.bundleIdentifiers.isEmpty else {
            return []
        }

        return NSWorkspace.shared.runningApplications.filter { application in
            guard !application.isTerminated else {
                return false
            }

            if let bundleIdentifier = application.bundleIdentifier?.lowercased(),
               identity.bundleIdentifiers.contains(bundleIdentifier) {
                return true
            }

            let appNames = [
                application.localizedName,
                application.bundleURL?.deletingPathExtension().lastPathComponent
            ].compactMap { $0.map(normalizedApplicationName) }

            return appNames.contains { identity.appNames.contains($0) }
        }
    }

    private func raiseWindow(matchingAnyOf candidates: [String], in application: NSRunningApplication) -> Bool {
        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement]
        else {
            return false
        }

        for window in windows {
            guard let title = accessibilityTitle(for: window),
                  windowTitle(title, matchesAnyOf: candidates)
            else {
                continue
            }

            application.unhide()
            restoreWindowIfMinimized(window)
            AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            return application.activate()
        }

        return false
    }

    private func accessibilityTitle(for element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &value) == .success else {
            return nil
        }

        return value as? String
    }

    private func restoreWindowIfMinimized(_ window: AXUIElement) {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &value) == .success,
              value as? Bool == true
        else {
            return
        }

        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
    }

    private func windowTitle(_ title: String, matchesAnyOf candidates: [String]) -> Bool {
        let normalizedTitle = normalizedWindowMatchString(title)
        return candidates.contains { candidate in
            let normalizedCandidate = normalizedWindowMatchString(candidate)
            return !normalizedCandidate.isEmpty && normalizedTitle.contains(normalizedCandidate)
        }
    }

    private func windowTitleCandidates(for projectPath: String) -> [String] {
        let projectName = projectName(for: projectPath)
        return [
            projectName,
            projectName.replacingOccurrences(of: "-", with: " "),
            projectName.replacingOccurrences(of: "_", with: " "),
            projectPath
        ].filter { !$0.isEmpty }
    }

    private func normalizedWindowMatchString(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "—", with: " ")
            .replacingOccurrences(of: "–", with: " ")
            .replacingOccurrences(of: "/", with: " ")
            .split(separator: " ")
            .joined(separator: " ")
    }

    private func openApplication(for agentID: String) {
        guard let appURL = applicationURL(for: agentID) else {
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(
            at: appURL,
            configuration: configuration
        )
    }

    private func applicationURL(for agentID: String) -> URL? {
        applicationPaths[agentID]?
            .first(where: FileManager.default.fileExists)
            .map { URL(fileURLWithPath: $0) }
    }

    private func activationIdentity(for agentID: String, displayName: String) -> ActivationIdentity {
        var names = activationNameHints[agentID] ?? []
        names.append(displayName)
        let bundleIdentifiers = Set((activationBundleIdentifierHints[agentID] ?? []).map { $0.lowercased() })
        return ActivationIdentity(
            appNames: Set(names.map(normalizedApplicationName)),
            bundleIdentifiers: bundleIdentifiers
        )
    }

    private func normalizedApplicationName(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private var activationNameHints: [String: [String]] {
        [
            "antigravity": ["Antigravity IDE", "Antigravity"],
            "claude": ["Claude", "Claude Code"],
            "codex": ["Codex"],
            "cursor": ["Cursor"],
            "vscode": ["Visual Studio Code", "Code", "Code - Insiders", "VSCodium"],
            "windsurf": ["Windsurf"],
            "zed": ["Zed"],
            "xcode": ["Xcode"]
        ]
    }

    private var activationBundleIdentifierHints: [String: [String]] {
        [
            "antigravity": [
                "com.googlelabs.antigravity",
                "com.googlelabs.antigravityide"
            ],
            "claude": [
                "com.anthropic.claudefordesktop",
                "com.anthropic.claude"
            ],
            "codex": ["com.openai.codex"],
            "cursor": ["com.todesktop.230313mzl4w4u92"],
            "vscode": [
                "com.microsoft.vscode",
                "com.microsoft.vscodeinsiders",
                "com.vscodium"
            ],
            "windsurf": ["com.exafunction.windsurf"],
            "zed": ["dev.zed.zed"],
            "xcode": ["com.apple.dt.xcode"]
        ]
    }

    private var applicationPaths: [String: [String]] {
        [
            "antigravity": ["/Applications/Antigravity IDE.app", "/Applications/Antigravity.app"],
            "claude": ["/Applications/Claude.app", "/Applications/Claude Code.app"],
            "codex": ["/Applications/Codex.app"],
            "cursor": ["/Applications/Cursor.app"],
            "vscode": ["/Applications/Visual Studio Code.app"],
            "windsurf": ["/Applications/Windsurf.app"],
            "zed": ["/Applications/Zed.app"],
            "xcode": ["/Applications/Xcode.app"]
        ]
    }

    private func drawText(
        _ text: String,
        in rect: NSRect,
        font: NSFont,
        color: NSColor,
        alignment: NSTextAlignment = .left
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        paragraph.alignment = alignment

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        text.draw(in: rect, withAttributes: attributes)
    }
}
