import Foundation

/// What a session's light shows.
enum Light: Int, Comparable {
    case done = 0       // green: finished and replied
    case working = 1    // orange: running
    case attention = 2  // red: asked a question / needs permission

    static func < (a: Light, b: Light) -> Bool { a.rawValue < b.rawValue }
}

/// The raw record written by `claude-lights-hook.sh`.
struct SessionRecord: Decodable {
    let session_id: String
    let state: String
    let event: String?
    let cwd: String?
    let transcript_path: String?
    let pid: Int32?
    let started: Double?
    let updated: Double?
}

/// A session as shown in the menu bar.
struct Session {
    let id: String
    let cwd: String
    let transcriptPath: String?
    let pid: Int32
    let started: Date
    let updated: Date
    let light: Light
    let detail: String

    var name: String {
        let base = (cwd as NSString).lastPathComponent
        return base.isEmpty ? String(id.prefix(8)) : base
    }
}
