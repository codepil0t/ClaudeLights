import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private enum Defaults {
        static let detectQuestions = "detectQuestionsInReplies"
        static let playSounds = "playSounds"
        static let declinedHookInstall = "declinedHookInstall"
    }

    private let store = SessionStore()
    private var statusItem: NSStatusItem!
    private var sessions: [Session] = []
    private var previousLights: [String: Light] = [:]
    private var timer: Timer?
    private var directoryWatcher: DispatchSourceFileSystemObject?
    private var menuIsOpen = false

    private var defaults: UserDefaults { .standard }

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        defaults.register(defaults: [Defaults.detectQuestions: true, Defaults.playSounds: false])
        store.detectQuestionsInReplies = defaults.bool(forKey: Defaults.detectQuestions)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.imagePosition = .imageOnly
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu

        try? FileManager.default.createDirectory(at: SessionStore.sessionsDirectory, withIntermediateDirectories: true)
        HookInstaller.refreshScriptIfInstalled()
        watchDirectory()

        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()

        if !HookInstaller.isInstalled && !defaults.bool(forKey: Defaults.declinedHookInstall) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.offerHookInstall()
            }
        }
    }

    // MARK: Refresh

    private func watchDirectory() {
        let fd = open(SessionStore.sessionsDirectory.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.refresh() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        directoryWatcher = source
    }

    private func refresh() {
        sessions = store.load()
        playSoundsForTransitions()

        let lights = sessions.map(\.light)
        guard let button = statusItem.button else { return }
        button.image = LightIcon.statusImage(for: lights)
        let summary = summaryText()
        button.toolTip = summary
        button.setAccessibilityLabel("Claude Lights: \(summary)")

        if menuIsOpen, let menu = statusItem.menu { rebuild(menu) }
    }

    private func playSoundsForTransitions() {
        defer { previousLights = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0.light) }) }
        guard defaults.bool(forKey: Defaults.playSounds) else { return }
        var sound: String?
        for s in sessions {
            guard let before = previousLights[s.id], before != s.light else { continue }
            if s.light == .attention { sound = "Ping"; break }
            if s.light == .done, before == .working { sound = "Glass" }
        }
        if let sound { NSSound(named: sound)?.play() }
    }

    private func summaryText() -> String {
        if sessions.isEmpty { return "No Claude Code sessions" }
        let counts = Dictionary(grouping: sessions, by: \.light).mapValues(\.count)
        var parts: [String] = []
        if let n = counts[.attention] { parts.append("\(n) need you") }
        if let n = counts[.working] { parts.append("\(n) working") }
        if let n = counts[.done] { parts.append("\(n) done") }
        return parts.joined(separator: ", ")
    }

    // MARK: Menu

    func menuWillOpen(_ menu: NSMenu) {
        menuIsOpen = true
        refresh()
        rebuild(menu)
    }

    func menuDidClose(_ menu: NSMenu) {
        menuIsOpen = false
    }

    private func rebuild(_ menu: NSMenu) {
        menu.removeAllItems()

        let header = NSMenuItem(title: sessions.isEmpty ? "No Claude Code sessions" : "Claude Code sessions", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        for session in sessions {
            let item = NSMenuItem(title: "", action: #selector(focusSession(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = session.id
            item.image = LightIcon.dot(for: session.light)
            item.attributedTitle = title(for: session)
            item.toolTip = "\(session.cwd)\nSession \(session.id)\nClick to bring its terminal to the front. ⌥-click to open the folder."
            menu.addItem(item)

            let alt = NSMenuItem(title: "", action: #selector(openFolder(_:)), keyEquivalent: "")
            alt.target = self
            alt.representedObject = session.id
            alt.image = item.image
            alt.attributedTitle = title(for: session, suffix: "Open folder")
            alt.isAlternate = true
            alt.keyEquivalentModifierMask = .option
            menu.addItem(alt)
        }

        menu.addItem(.separator())

        let clear = NSMenuItem(title: "Clear Finished Sessions", action: #selector(clearFinished), keyEquivalent: "")
        clear.target = self
        clear.isEnabled = sessions.contains { $0.light == .done }
        menu.addItem(clear)

        menu.addItem(.separator())

        menu.addItem(toggle("Red Light for Questions in Replies", key: Defaults.detectQuestions,
                            tip: "Turn the light red when the agent's final reply ends with a question."))
        menu.addItem(toggle("Play Sounds", key: Defaults.playSounds,
                            tip: "Play a sound when an agent finishes or needs you."))

        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        let installed = HookInstaller.isInstalled
        let hooks = NSMenuItem(
            title: installed ? "Remove Claude Code Hooks…" : "Install Claude Code Hooks…",
            action: installed ? #selector(uninstallHooks) : #selector(installHooks),
            keyEquivalent: ""
        )
        hooks.target = self
        menu.addItem(hooks)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Claude Lights", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    private func title(for session: Session, suffix: String? = nil) -> NSAttributedString {
        let s = NSMutableAttributedString(
            string: session.name,
            attributes: [.font: NSFont.menuFont(ofSize: 0)]
        )
        let secondary = suffix ?? "\(session.detail) · \(Self.age(of: session.updated))"
        s.append(NSAttributedString(
            string: "   " + secondary,
            attributes: [
                .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        ))
        return s
    }

    private func toggle(_ title: String, key: String, tip: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(toggleDefault(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = key
        item.state = defaults.bool(forKey: key) ? .on : .off
        item.toolTip = tip
        return item
    }

    private static func age(of date: Date) -> String {
        let s = Int(Date().timeIntervalSince(date))
        switch s {
        case ..<5: return "now"
        case ..<60: return "\(s)s"
        case ..<3600: return "\(s / 60)m"
        case ..<86400: return "\(s / 3600)h"
        default: return "\(s / 86400)d"
        }
    }

    // MARK: Actions

    private func session(for sender: NSMenuItem) -> Session? {
        guard let id = sender.representedObject as? String else { return nil }
        return sessions.first { $0.id == id }
    }

    @objc private func focusSession(_ sender: NSMenuItem) {
        guard let session = session(for: sender) else { return }
        if session.pid > 0, let app = ProcessTree.hostingApp(of: session.pid) {
            if #available(macOS 14.0, *) {
                app.activate()
            } else {
                app.activate(options: [.activateIgnoringOtherApps])
            }
        } else if !session.cwd.isEmpty {
            NSWorkspace.shared.open(URL(fileURLWithPath: session.cwd))
        }
    }

    @objc private func openFolder(_ sender: NSMenuItem) {
        guard let session = session(for: sender), !session.cwd.isEmpty else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: session.cwd))
    }

    @objc private func clearFinished() {
        for s in sessions where s.light == .done { store.remove(sessionID: s.id) }
        refresh()
    }

    @objc private func toggleDefault(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        defaults.set(!defaults.bool(forKey: key), forKey: key)
        store.detectQuestionsInReplies = defaults.bool(forKey: Defaults.detectQuestions)
        refresh()
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            showError("Couldn't change Launch at Login", error)
        }
    }

    @objc private func installHooks() {
        do {
            try HookInstaller.install()
            defaults.set(false, forKey: Defaults.declinedHookInstall)
            showInfo(
                "Hooks installed",
                "Claude Lights hooks were added to ~/.claude/settings.json (a backup was saved next to it).\n\n" +
                "Sessions that are already running pick them up after a restart; new sessions show a light right away."
            )
        } catch {
            showError("Couldn't install hooks", error)
        }
        refresh()
    }

    @objc private func uninstallHooks() {
        do {
            try HookInstaller.uninstall()
            showInfo("Hooks removed", "Claude Lights hooks were removed from ~/.claude/settings.json.")
        } catch {
            showError("Couldn't remove hooks", error)
        }
        refresh()
    }

    // MARK: Alerts

    private func offerHookInstall() {
        let alert = NSAlert()
        alert.messageText = "Connect Claude Lights to Claude Code?"
        alert.informativeText =
            "Claude Lights needs a small hook in ~/.claude/settings.json so every Claude Code session " +
            "reports its state. Your existing settings are kept and a backup is saved.\n\n" +
            "You can remove it any time from the menu."
        alert.addButton(withTitle: "Install Hooks")
        alert.addButton(withTitle: "Not Now")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            installHooks()
        } else {
            defaults.set(true, forKey: Defaults.declinedHookInstall)
        }
    }

    private func showInfo(_ title: String, _ text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func showError(_ title: String, _ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
