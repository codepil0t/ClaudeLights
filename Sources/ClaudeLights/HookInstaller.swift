import Foundation

/// Installs / removes the Claude Lights hook in ~/.claude/settings.json.
///
/// Only entries whose command points at our hook script are touched; everything
/// else in settings.json is preserved. A backup is written before every change.
enum HookInstaller {
    enum InstallError: LocalizedError {
        case missingBundledScript
        case unreadableSettings(String)

        var errorDescription: String? {
            switch self {
            case .missingBundledScript:
                return "The hook script is missing from the app bundle. Rebuild the app with scripts/build-app.sh."
            case .unreadableSettings(let why):
                return "Couldn't parse ~/.claude/settings.json, so it was left untouched.\n\n\(why)"
            }
        }
    }

    static let scriptName = "claude-lights-hook.sh"
    static let marker = "claude-lights/\(scriptName)"
    static let command = "\"$HOME/.claude/claude-lights/\(scriptName)\""

    /// Hook events we listen to. Tool events get a match-all matcher.
    static let events: [(name: String, matcher: String?)] = [
        ("SessionStart", nil),
        ("SessionEnd", nil),
        ("UserPromptSubmit", nil),
        ("PreToolUse", "*"),
        ("PostToolUse", "*"),
        ("PermissionRequest", "*"),
        ("Notification", nil),
        ("Stop", nil),
    ]

    static var claudeDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude", isDirectory: true)
    }
    static var settingsURL: URL { claudeDirectory.appendingPathComponent("settings.json") }
    static var installedScriptURL: URL { SessionStore.baseDirectory.appendingPathComponent(scriptName) }
    static var bundledScriptURL: URL? {
        Bundle.main.url(forResource: "claude-lights-hook", withExtension: "sh")
    }

    // MARK: Status

    static var isInstalled: Bool {
        guard FileManager.default.isExecutableFile(atPath: installedScriptURL.path),
              let settings = try? readSettings(),
              let hooks = settings["hooks"] as? [String: Any]
        else { return false }
        return events.allSatisfy { event in
            groups(in: hooks[event.name]).contains { group in
                commands(in: group).contains { $0.contains(marker) }
            }
        }
    }

    // MARK: Install / uninstall

    static func install() throws {
        try installScript()

        var settings = try readSettings()
        var hooks = removingOurHooks(from: settings["hooks"] as? [String: Any] ?? [:])

        for event in events {
            var group: [String: Any] = [
                "hooks": [["type": "command", "command": command, "timeout": 10]]
            ]
            if let matcher = event.matcher { group["matcher"] = matcher }
            hooks[event.name] = groups(in: hooks[event.name]) + [group]
        }
        settings["hooks"] = hooks
        try writeSettings(settings)
    }

    static func uninstall() throws {
        var settings = try readSettings()
        if let hooks = settings["hooks"] as? [String: Any] {
            let cleaned = removingOurHooks(from: hooks)
            if cleaned.isEmpty {
                settings.removeValue(forKey: "hooks")
            } else {
                settings["hooks"] = cleaned
            }
            try writeSettings(settings)
        }
        try? FileManager.default.removeItem(at: installedScriptURL)
    }

    /// Keeps the installed hook script in sync with the one bundled in this app version.
    static func refreshScriptIfInstalled() {
        guard FileManager.default.fileExists(atPath: installedScriptURL.path),
              let bundled = bundledScriptURL,
              let new = try? Data(contentsOf: bundled),
              (try? Data(contentsOf: installedScriptURL)) != new
        else { return }
        try? installScript()
    }

    // MARK: Helpers

    private static func installScript() throws {
        guard let bundled = bundledScriptURL else { throw InstallError.missingBundledScript }
        let fm = FileManager.default
        try fm.createDirectory(at: SessionStore.sessionsDirectory, withIntermediateDirectories: true)
        let data = try Data(contentsOf: bundled)
        try data.write(to: installedScriptURL, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: installedScriptURL.path)
    }

    private static func readSettings() throws -> [String: Any] {
        guard let data = try? Data(contentsOf: settingsURL), !data.isEmpty else { return [:] }
        do {
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw InstallError.unreadableSettings("The top level is not a JSON object.")
            }
            return obj
        } catch let error as InstallError {
            throw error
        } catch {
            throw InstallError.unreadableSettings(error.localizedDescription)
        }
    }

    private static func writeSettings(_ settings: [String: Any]) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: claudeDirectory, withIntermediateDirectories: true)
        if fm.fileExists(atPath: settingsURL.path) {
            let backup = claudeDirectory.appendingPathComponent("settings.json.claude-lights-backup")
            try? fm.removeItem(at: backup)
            try fm.copyItem(at: settingsURL, to: backup)
        }
        try Data(JSONWriter.string(from: settings).utf8).write(to: settingsURL, options: .atomic)
    }

    private static func groups(in value: Any?) -> [[String: Any]] {
        value as? [[String: Any]] ?? []
    }

    private static func commands(in group: [String: Any]) -> [String] {
        (group["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String }
    }

    private static func removingOurHooks(from hooks: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (event, value) in hooks {
            guard let list = value as? [[String: Any]] else {
                result[event] = value // unknown shape: leave it alone
                continue
            }
            let cleaned: [[String: Any]] = list.compactMap { group in
                guard let entries = group["hooks"] as? [[String: Any]] else { return group }
                let kept = entries.filter { !(($0["command"] as? String)?.contains(marker) ?? false) }
                if kept.isEmpty { return nil }
                var g = group
                g["hooks"] = kept
                return g
            }
            if !cleaned.isEmpty { result[event] = cleaned }
        }
        return result
    }
}
