import Foundation

/// What the end of a Claude Code transcript (JSONL) says about the last turn.
enum TranscriptTail: Equatable {
    case reply(String)   // the last assistant message ended with this text
    case toolActivity    // the turn is in the middle of tool use
    case interrupted     // the user pressed Esc
    case prompt          // the last entry is a user prompt
    case unknown
}

/// Reads only the end of transcript files and caches the result per file version.
final class TranscriptReader {
    private struct CacheEntry {
        let size: UInt64
        let mtime: Date
        let tail: TranscriptTail
    }

    private var cache: [String: CacheEntry] = [:]
    private let chunkSize: UInt64 = 512 * 1024

    func tail(of path: String) -> (TranscriptTail, Date?) {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = (attrs[.size] as? NSNumber)?.uint64Value,
              let mtime = attrs[.modificationDate] as? Date
        else { return (.unknown, nil) }

        if let hit = cache[path], hit.size == size, hit.mtime == mtime {
            return (hit.tail, mtime)
        }
        let tail = read(path: path, size: size)
        cache[path] = CacheEntry(size: size, mtime: mtime, tail: tail)
        return (tail, mtime)
    }

    func forget(except paths: Set<String>) {
        cache = cache.filter { paths.contains($0.key) }
    }

    private func read(path: String, size: UInt64) -> TranscriptTail {
        guard let handle = FileHandle(forReadingAtPath: path) else { return .unknown }
        defer { try? handle.close() }

        let offset = size > chunkSize ? size - chunkSize : 0
        do { try handle.seek(toOffset: offset) } catch { return .unknown }
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return .unknown }

        var lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
        if offset > 0, !lines.isEmpty { lines.removeFirst() } // partial line

        for line in lines.reversed() {
            if let result = classify(line: Data(line)) { return result }
        }
        return .unknown
    }

    /// Returns nil when the line doesn't decide anything (skip and look further back).
    private func classify(line: Data) -> TranscriptTail? {
        // Cheap pre-filter: most lines we don't care about are skipped without parsing.
        guard line.range(of: Data("\"type\":\"assistant\"".utf8)) != nil
                || line.range(of: Data("\"type\":\"user\"".utf8)) != nil
        else { return nil }

        guard let obj = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
              let type = obj["type"] as? String,
              type == "assistant" || type == "user"
        else { return nil }
        if (obj["isSidechain"] as? Bool) == true { return nil }
        if (obj["isMeta"] as? Bool) == true { return nil }

        let message = obj["message"] as? [String: Any]
        let content = message?["content"]

        if type == "assistant" {
            guard let blocks = content as? [[String: Any]] else { return nil }
            if let text = blocks.last(where: { ($0["type"] as? String) == "text" })?["text"] as? String,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return .reply(text)
            }
            if blocks.contains(where: { ($0["type"] as? String) == "tool_use" }) {
                return .toolActivity
            }
            return nil // thinking-only chunk; the text is in a neighbouring line
        }

        // user
        if let text = content as? String {
            return text.contains("[Request interrupted by user") ? .interrupted : .prompt
        }
        if let blocks = content as? [[String: Any]] {
            for block in blocks {
                if let text = block["text"] as? String, text.contains("[Request interrupted by user") {
                    return .interrupted
                }
            }
            if blocks.contains(where: { ($0["type"] as? String) == "tool_result" }) {
                return .toolActivity
            }
            return .prompt
        }
        return nil
    }
}

extension String {
    /// True when a reply ends with a question to the user, e.g. "Should I continue?".
    var endsWithQuestion: Bool {
        let trailing = CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: "*_`)]»\"'”’ "))
        var s = Substring(self)
        while let last = s.unicodeScalars.last, trailing.contains(last) {
            s = s.dropLast()
        }
        return s.hasSuffix("?") || s.hasSuffix("？")
    }
}
