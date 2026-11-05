import Foundation

/// Loads session state files written by the hook and turns them into lights.
final class SessionStore {
    static let baseDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/claude-lights", isDirectory: true)
    static let sessionsDirectory = baseDirectory.appendingPathComponent("sessions", isDirectory: true)

    /// Sessions whose process can't be identified are dropped after this long without activity.
    private let orphanTimeout: TimeInterval = 12 * 60 * 60

    private let transcripts = TranscriptReader()
    var detectQuestionsInReplies = true

    func load() -> [Session] {
        let fm = FileManager.default
        let dir = Self.sessionsDirectory
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return []
        }

        let decoder = JSONDecoder()
        var sessions: [Session] = []
        var livePaths = Set<String>()

        for url in files where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let record = try? decoder.decode(SessionRecord.self, from: data)
            else { continue }

            let updated = Date(timeIntervalSince1970: record.updated ?? 0)
            let pid = record.pid ?? 0

            if pid > 0 {
                if kill(pid, 0) == -1 && errno == ESRCH {
                    try? fm.removeItem(at: url) // the claude process is gone
                    continue
                }
            } else if Date().timeIntervalSince(updated) > orphanTimeout {
                try? fm.removeItem(at: url)
                continue
            }

            if let path = record.transcript_path, !path.isEmpty { livePaths.insert(path) }
            sessions.append(makeSession(record, pid: pid, updated: updated))
        }

        transcripts.forget(except: livePaths)
        return sessions.sorted {
            $0.started == $1.started ? $0.id < $1.id : $0.started < $1.started
        }
    }

    private func makeSession(_ r: SessionRecord, pid: Int32, updated: Date) -> Session {
        var light: Light
        var detail: String

        switch r.state {
        case "working":
            light = .working
            detail = "Working"
        case "waiting":
            light = .attention
            detail = r.event == "PreToolUse" ? "Asking you a question" : "Needs your permission"
        default:
            light = .done
            detail = r.event == "SessionStart" ? "Ready" : "Done"
        }

        if let path = r.transcript_path, !path.isEmpty {
            let (tail, mtime) = transcripts.tail(of: path)
            // Allow a little clock slack: hook timestamps have 1 s resolution.
            let transcriptIsNewer = (mtime ?? .distantPast) >= updated.addingTimeInterval(-1)

            switch (light, tail) {
            case (.working, .interrupted), (.attention, .interrupted):
                // Esc doesn't fire the Stop hook; the transcript tells us.
                if transcriptIsNewer {
                    light = .done
                    detail = "Interrupted"
                }
            case (.done, .reply(let text)) where detectQuestionsInReplies && r.event == "Stop":
                if text.endsWithQuestion {
                    light = .attention
                    detail = "Asked a question"
                }
            default:
                break
            }
        }

        return Session(
            id: r.session_id,
            cwd: r.cwd ?? "",
            transcriptPath: r.transcript_path,
            pid: pid,
            started: Date(timeIntervalSince1970: r.started ?? r.updated ?? 0),
            updated: updated,
            light: light,
            detail: detail
        )
    }

    func remove(sessionID: String) {
        let url = Self.sessionsDirectory.appendingPathComponent("\(sessionID).json")
        try? FileManager.default.removeItem(at: url)
    }
}
