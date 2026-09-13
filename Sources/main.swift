import AppKit

// MARK: - Tunables

let refreshInterval: TimeInterval = 300   // auto-refresh cadence (seconds)
let panelWidth: CGFloat = 320             // glass panel width

// MARK: - Brand

enum Brand {
    /// Synthetic purple — fixed so it reads on both light & dark glass.
    static let accent = NSColor(srgbRed: 0.545, green: 0.486, blue: 0.969, alpha: 1)
}

// MARK: - Usage model

struct Usage {
    var weeklyPercentRemaining = 100.0
    var weeklyRemaining = "$0"
    var weeklyMax = "$0"
    var weeklyRegen = "$0"
    var weeklyRegenAt: Date?

    var rollUsed = 0
    var rollMax = 0
    var rollLimited = false
    var rollNextTick: Date?

    var searchUsed = 0
    var searchLimit = 0
    var searchRenewsAt: Date?

    var fetchedAt = Date()

    static func parse(_ data: Data) -> Usage? {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        var u = Usage()
        let w = obj["weeklyTokenLimit"] as? [String: Any] ?? [:]
        let r = obj["rollingFiveHourLimit"] as? [String: Any] ?? [:]
        let s = (obj["search"] as? [String: Any])?["hourly"] as? [String: Any] ?? [:]

        u.weeklyPercentRemaining = jnum(w["percentRemaining"]) ?? 100
        u.weeklyRemaining = jstr(w["remainingCredits"]) ?? "$0"
        u.weeklyMax = jstr(w["maxCredits"]) ?? "$0"
        u.weeklyRegen = jstr(w["nextRegenCredits"]) ?? "$0"
        u.weeklyRegenAt = jdate(jstr(w["nextRegenAt"]))

        u.rollMax = Int(jnum(r["max"]) ?? 0)
        u.rollUsed = u.rollMax - Int(jnum(r["remaining"]) ?? 0)
        u.rollLimited = (r["limited"] as? Bool) ?? false
        u.rollNextTick = jdate(jstr(r["nextTickAt"]))

        u.searchUsed = Int(jnum(s["requests"]) ?? 0)
        u.searchLimit = Int(jnum(s["limit"]) ?? 0)
        u.searchRenewsAt = jdate(jstr(s["renewsAt"]))
        return u
    }
}

// MARK: - JSON / formatting helpers

private func jnum(_ v: Any?) -> Double? { (v as? NSNumber)?.doubleValue }

private func jstr(_ v: Any?) -> String? {
    if let s = v as? String { return s }
    if let n = v as? NSNumber { return n.stringValue }
    return nil
}

private func jdate(_ s: String?) -> Date? {
    guard let s else { return nil }
    if s.contains(".") {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
    }
    return ISO8601DateFormatter().date(from: s)
}

private func money(_ s: String) -> Double? {
    Double(s.replacingOccurrences(of: "$", with: ""))
}

/// "in 1h 8m" style relative time, matching the Synthetic dashboard.
private func relativeIn(_ d: Date?) -> String {
    guard let d else { return "—" }
    let iv = d.timeIntervalSinceNow
    if iv <= 0 { return "now" }
    let totalMin = max(1, Int(iv / 60))
    if totalMin < 60 { return "in \(totalMin)m" }
    let h = totalMin / 60, m = totalMin % 60
    if h < 48 { return h > 0 ? "in \(h)h \(m)m" : "in \(m)m" }
    let days = h / 24, hh = h % 24
    return "in \(days)d \(hh)h"
}

private func shortTime(_ d: Date) -> String {
    let f = DateFormatter()
    f.timeStyle = .short
    return f.string(from: d)
}

// MARK: - Simple painted views

final class SolidView: NSView {
    let color: NSColor
    init(color: NSColor) {
        self.color = color
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        NSBezierPath(rect: bounds).fill()
    }
}

final class BarView: NSView {
    var fraction: CGFloat = 0 { didSet { needsDisplay = true } }
    var fillColor: NSColor { didSet { needsDisplay = true } }
    private let trackColor: NSColor

    init(track: NSColor, fill: NSColor) {
        trackColor = track
        fillColor = fill
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        trackColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 3, yRadius: 3).fill()
        guard fraction > 0 else { return }
        var f = bounds
        f.size.width = max(6, bounds.width * min(1, max(0, fraction)))
        fillColor.setFill()
        NSBezierPath(roundedRect: f, xRadius: 3, yRadius: 3).fill()
    }
}

// MARK: - Panel content

final class PanelView: NSStackView {
    weak var app: AppDelegate?

    init() {
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = 7
        translatesAutoresizingMaskIntoConstraints = false
        edgeInsets = NSEdgeInsets(top: 16, left: 18, bottom: 14, right: 18)
    }
    required init?(coder: NSCoder) { fatalError() }

    private var inset: CGFloat { edgeInsets.left + edgeInsets.right }

    private func addFull(_ v: NSView, height: CGFloat? = nil) {
        addArrangedSubview(v)
        v.translatesAutoresizingMaskIntoConstraints = false
        v.widthAnchor.constraint(equalTo: widthAnchor, constant: -inset).isActive = true
        if let h = height { v.heightAnchor.constraint(equalToConstant: h).isActive = true }
    }

    private func label(_ text: String, _ font: NSFont, _ color: NSColor, tracking: CGFloat = 0) -> NSTextField {
        let tf = NSTextField(labelWithString: "")
        let s = NSMutableAttributedString(string: text)
        s.addAttributes([.font: font, .foregroundColor: color, .kern: tracking],
                        range: NSRange(location: 0, length: s.length))
        tf.attributedStringValue = s
        return tf
    }

    private func spacer(_ height: CGFloat) -> NSView {
        let v = NSView()
        v.heightAnchor.constraint(equalToConstant: height).isActive = true
        return v
    }

    // MARK: build

    func render(usage: Usage?, error: String?, loading: Bool, hasKey: Bool) {
        for v in arrangedSubviews { removeArrangedSubview(v); v.removeFromSuperview() }

        // Header — ✦ Synthetic / API QUOTAS
        let header = NSStackView()
        header.orientation = .horizontal
        header.spacing = 9
        header.alignment = .centerY
        header.addArrangedSubview(label("✦", .systemFont(ofSize: 17, weight: .semibold), Brand.accent))
        let titleCol = NSStackView()
        titleCol.orientation = .vertical
        titleCol.spacing = 1
        titleCol.alignment = .leading
        titleCol.addArrangedSubview(label("Synthetic", .systemFont(ofSize: 14.5, weight: .semibold), .labelColor))
        titleCol.addArrangedSubview(label("API QUOTAS", .systemFont(ofSize: 9, weight: .medium), .tertiaryLabelColor, tracking: 1.3))
        header.addArrangedSubview(titleCol)
        header.addArrangedSubview(NSView()) // spacer
        addFull(header)
        addFull(spacer(3))

        if let e = error {
            addFull(label("⚠︎ \(e)", .systemFont(ofSize: 10.5), .systemRed))
        }

        if !hasKey {
            addFull(label("No API key found.", .systemFont(ofSize: 12, weight: .medium), .labelColor))
            addFull(label("Export SYNTHETIC_API_KEY in ~/.zshrc (or launch from a shell that has it), then hit Refresh.",
                          .systemFont(ofSize: 10.5), .secondaryLabelColor))
        } else if loading && usage == nil {
            addFull(label("Loading…", .systemFont(ofSize: 11), .secondaryLabelColor))
        } else if let u = usage {
            addFull(label("LIMITS", .systemFont(ofSize: 10, weight: .semibold), .secondaryLabelColor, tracking: 1.4))

            // Weekly — dashboard style: bar shows remaining %
            let weeklyPct = Int(u.weeklyPercentRemaining.rounded())
            quota(title: "Weekly",
                  value: "\(weeklyPct)%",
                  valueColor: .labelColor,
                  fraction: CGFloat(u.weeklyPercentRemaining / 100),
                  fill: Brand.accent,
                  caption: regenCaption(u))

            // Rolling 5h requests
            let rollValue = u.rollLimited ? "LIMITED" : "\(u.rollUsed) / \(u.rollMax)"
            quota(title: "Requests · 5h",
                  value: rollValue,
                  valueColor: u.rollLimited ? .systemRed : .secondaryLabelColor,
                  fraction: u.rollMax > 0 ? CGFloat(u.rollUsed) / CGFloat(u.rollMax) : 0,
                  fill: u.rollLimited ? NSColor.systemRed : Brand.accent,
                  caption: "Next tick \(relativeIn(u.rollNextTick))")

            // Search hourly
            quota(title: "Search · hourly",
                  value: "\(u.searchUsed) / \(u.searchLimit)",
                  valueColor: .secondaryLabelColor,
                  fraction: u.searchLimit > 0 ? CGFloat(u.searchUsed) / CGFloat(u.searchLimit) : 0,
                  fill: Brand.accent,
                  caption: "Renews \(relativeIn(u.searchRenewsAt))")
        } else {
            addFull(label("Couldn't load usage.", .systemFont(ofSize: 12, weight: .medium), .labelColor))
        }

        // Footer — updated stamp + glass buttons
        addFull(spacer(4))
        addFull(SolidView(color: .separatorColor), height: 1)
        addFull(spacer(8))

        let footer = NSStackView()
        footer.orientation = .horizontal
        footer.spacing = 6
        let stamp = loading
            ? "Updated just now"
            : (usage != nil ? "Updated \(shortTime(usage!.fetchedAt))" : "Not updated yet")
        footer.addArrangedSubview(label(stamp, .systemFont(ofSize: 9.5), .tertiaryLabelColor))
        footer.addArrangedSubview(NSView()) // spacer

        let refreshBtn = NSButton(title: "Refresh", target: app, action: #selector(AppDelegate.refreshTapped))
        refreshBtn.bezelStyle = .glass
        refreshBtn.controlSize = .small
        footer.addArrangedSubview(refreshBtn)

        let quitBtn = NSButton(title: "Quit", target: NSApp, action: #selector(NSApplication.terminate(_:)))
        quitBtn.bezelStyle = .glass
        quitBtn.controlSize = .small
        footer.addArrangedSubview(quitBtn)
        addFull(footer)
    }

    private func quota(title: String, value: String, valueColor: NSColor,
                       fraction: CGFloat, fill: NSColor, caption: String?) {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        row.addArrangedSubview(label(title, .systemFont(ofSize: 12.5, weight: .medium), .labelColor))
        row.addArrangedSubview(NSView()) // spacer
        row.addArrangedSubview(label(value, .monospacedDigitSystemFont(ofSize: 11.5, weight: .medium), valueColor))
        addFull(row)

        let bar = BarView(track: .separatorColor, fill: fill)
        bar.fraction = fraction
        addFull(bar, height: 6)

        if let c = caption {
            addFull(label(c, .monospacedDigitSystemFont(ofSize: 10, weight: .regular), .secondaryLabelColor))
        }
        addFull(spacer(3))
    }

    private func regenCaption(_ u: Usage) -> String {
        if let g = money(u.weeklyRegen), let m = money(u.weeklyMax), m > 0 {
            let pct = Int((g / m * 100).rounded())
            return "Regenerates \(pct)% \(relativeIn(u.weeklyRegenAt))"
        }
        return "Regenerates +\(u.weeklyRegen) \(relativeIn(u.weeklyRegenAt))"
    }
}

// MARK: - Floating glass panel

final class GlassPanel {
    private let panel: NSPanel
    private let content: NSView
    private var lastAnchor: NSRect = .zero
    private var monitorsInstalled = false
    var onOutsideClick: (() -> Void)?
    var statusButtonWindow: NSWindow?

    init(content: NSView) {
        self.content = content

        let glass = NSGlassEffectView()
        glass.cornerRadius = 24
        glass.contentView = content
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: glass.topAnchor),
            content.bottomAnchor.constraint(equalTo: glass.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
        ])

        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: 200),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.contentView = glass
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    var isVisible: Bool { panel.isVisible }

    func resize(width: CGFloat, height: CGFloat, anchor: NSRect) {
        lastAnchor = anchor
        let screen = anchorWindowScreen() ?? NSScreen.main
        let vf = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var x = anchor.midX - width / 2
        x = min(max(x, vf.minX + 8), vf.maxX - width - 8)
        let y = anchor.minY - height - 8
        panel.setFrame(NSRect(x: x, y: y, width: width, height: max(1, height)), display: true)
    }

    func show(anchor: NSRect) {
        installMonitors()
        lastAnchor = anchor
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: { self.panel.orderOut(nil) })
    }

    private func anchorWindowScreen() -> NSScreen? {
        statusButtonWindow?.screen ?? NSScreen.screens.first { NSIntersectsRect($0.frame, lastAnchor) }
    }

    private func installMonitors() {
        guard !monitorsInstalled else { return }
        monitorsInstalled = true
        // Clicks in other apps
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            self?.onOutsideClick?()
        }
        // Clicks in our own app (status item window & panel are excluded; toggle handles those)
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] ev in
            guard let self else { return ev }
            if ev.window === self.statusButtonWindow || ev.window === self.panel { return ev }
            if self.panel.isVisible { self.onOutsideClick?() }
            return ev
        }
        // Esc closes
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] ev in
            if ev.keyCode == 53, self?.panel.isVisible == true {
                self?.hide()
                return nil
            }
            return ev
        }
    }
}

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let panelView = PanelView()
    var panel: GlassPanel!

    var usage: Usage?
    var error: String?
    var isLoading = false
    var apiKey: String?
    var lastFetch = Date.distantPast
    var timer: Timer?

    func applicationDidFinishLaunching(_ note: Notification) {
        panelView.app = self
        apiKey = resolveAPIKey()

        panel = GlassPanel(content: panelView)
        panel.onOutsideClick = { [weak self] in self?.hidePanel() }
        panel.statusButtonWindow = statusItem.button?.window

        if let b = statusItem.button {
            b.title = "✦ …"
            b.target = self
            b.action = #selector(togglePanel)
            b.toolTip = "Synthetic API usage"
        }

        renderAndSize()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    // MARK: panel show/hide

    @objc func togglePanel() {
        panel.isVisible ? hidePanel() : showPanel()
    }

    func showPanel() {
        statusItem.button?.highlight(true)
        if Date().timeIntervalSince(lastFetch) > 30 && apiKey != nil {
            refresh()
        } else {
            renderAndSize()
        }
        syncSize()
        panel.show(anchor: statusFrame())
    }

    func hidePanel() {
        statusItem.button?.highlight(false)
        panel.hide()
    }

    private func statusFrame() -> NSRect { statusItem.button?.window?.frame ?? .zero }

    private func syncSize() {
        let h = max(140, panelView.fittingSize.height)
        panel.resize(width: panelWidth, height: h, anchor: statusFrame())
    }

    private func renderAndSize() {
        panelView.render(usage: usage, error: error, loading: isLoading, hasKey: apiKey != nil)
        if panel.isVisible { syncSize() }
    }

    // MARK: data

    @objc func refreshTapped() {
        if apiKey == nil { apiKey = resolveAPIKey() }
        refresh()
    }

    func refresh() {
        guard let key = apiKey else { renderAndSize(); updateTitle(); return }
        isLoading = true
        error = nil
        renderAndSize()
        updateTitle()

        var req = URLRequest(url: URL(string: "https://api.synthetic.new/v2/quotas")!)
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15
        URLSession.shared.dataTask(with: req) { [weak self] data, _, err in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isLoading = false
                self.lastFetch = Date()
                if let data, let u = Usage.parse(data) {
                    self.usage = u
                    self.error = nil
                } else {
                    self.error = err?.localizedDescription ?? "Couldn't reach api.synthetic.new"
                }
                self.renderAndSize()
                self.updateTitle()
            }
        }.resume()
    }

    private func updateTitle() {
        guard let b = statusItem.button else { return }
        if let u = usage {
            let pct = Int(u.weeklyPercentRemaining.rounded())
            b.title = "✦ \(pct)%"
            b.toolTip = "Synthetic — \(u.weeklyRemaining) of \(u.weeklyMax) left this week"
        } else if isLoading {
            b.title = "✦ …"
        } else {
            b.title = "✦ !"
        }
    }

    // MARK: API key resolution
    // 1. inherited environment (launched from a shell)
    // 2. exported in common shell config files (launched from Finder/Login Items)
    // 3. interactive zsh, as a last resort

    private func resolveAPIKey() -> String? {
        if let k = ProcessInfo.processInfo.environment["SYNTHETIC_API_KEY"], !k.isEmpty {
            return k
        }
        for name in [".zshenv", ".zshrc", ".zprofile", ".profile", ".bash_profile"] {
            let path = NSString(string: "~/" + name).expandingTildeInPath
            guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            for rawLine in contents.components(separatedBy: .newlines) {
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                guard !line.hasPrefix("#"),
                      line.hasPrefix("export SYNTHETIC_API_KEY") || line.hasPrefix("SYNTHETIC_API_KEY"),
                      let eq = line.firstIndex(of: "=") else { continue }
                var v = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
                v = v.trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
                if v.contains(where: { $0 == " " }) { v = String(v.split(separator: " ").first ?? "") }
                if v.count > 10 { return v }
            }
        }
        if let out = runCmd("/bin/zsh", ["-ic", "printf %s \"$SYNTHETIC_API_KEY\""]) {
            let v = out.trimmingCharacters(in: .whitespacesAndNewlines)
            if v.count > 10, !v.contains(where: { $0 == " " }) { return v }
        }
        return nil
    }

    private func runCmd(_ path: String, _ args: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - main

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
