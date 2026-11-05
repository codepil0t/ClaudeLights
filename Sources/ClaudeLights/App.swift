import AppKit

@main
enum ClaudeLightsApp {
    @MainActor
    static func main() {
        // `ClaudeLights --status` prints what the menu bar would show (handy for debugging).
        let args = CommandLine.arguments
        if args.contains("--status") {
            printStatus()
            return
        }
        if args.contains("--install-hooks") || args.contains("--uninstall-hooks") {
            do {
                if args.contains("--install-hooks") {
                    try HookInstaller.install()
                    print("Hooks installed into \(HookInstaller.settingsURL.path)")
                } else {
                    try HookInstaller.uninstall()
                    print("Hooks removed from \(HookInstaller.settingsURL.path)")
                }
            } catch {
                FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
                exit(1)
            }
            return
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory) // menu bar only, no Dock icon
        app.run()
    }

    private static func printStatus() {
        let sessions = SessionStore().load()
        print("hooks installed: \(HookInstaller.isInstalled ? "yes" : "no")")
        if sessions.isEmpty { print("no sessions") }
        for s in sessions {
            let lamp: String
            switch s.light {
            case .working: lamp = "🟠"
            case .done: lamp = "🟢"
            case .attention: lamp = "🔴"
            }
            print("\(lamp) \(s.name)  \(s.detail)  pid=\(s.pid)  \(s.id)")
        }
    }
}
