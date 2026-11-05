import Foundation

/// Pretty-prints JSONSerialization objects the way Claude Code writes settings.json
/// (2-space indent, `"key": value`), keeping numbers exact (0.1 stays 0.1).
enum JSONWriter {
    static func string(from value: Any) -> String {
        var out = ""
        write(value, indent: 0, into: &out)
        out.append("\n")
        return out
    }

    private static func write(_ value: Any, indent: Int, into out: inout String) {
        let pad = String(repeating: "  ", count: indent)
        let innerPad = String(repeating: "  ", count: indent + 1)

        switch value {
        case let dict as [String: Any]:
            if dict.isEmpty { out.append("{}"); return }
            out.append("{\n")
            for (i, key) in dict.keys.sorted().enumerated() {
                out.append(innerPad)
                out.append(quote(key))
                out.append(": ")
                write(dict[key]!, indent: indent + 1, into: &out)
                out.append(i == dict.count - 1 ? "\n" : ",\n")
            }
            out.append(pad + "}")
        case let array as [Any]:
            if array.isEmpty { out.append("[]"); return }
            out.append("[\n")
            for (i, element) in array.enumerated() {
                out.append(innerPad)
                write(element, indent: indent + 1, into: &out)
                out.append(i == array.count - 1 ? "\n" : ",\n")
            }
            out.append(pad + "]")
        case let string as String:
            out.append(quote(string))
        case let number as NSNumber:
            out.append(format(number))
        case is NSNull:
            out.append("null")
        default:
            out.append("null")
        }
    }

    private static func format(_ number: NSNumber) -> String {
        if CFGetTypeID(number) == CFBooleanGetTypeID() {
            return number.boolValue ? "true" : "false"
        }
        switch CFNumberGetType(number) {
        case .floatType, .float32Type, .float64Type, .doubleType, .cgFloatType:
            let d = number.doubleValue
            if d.isFinite, d == d.rounded(), abs(d) < 1e15 { return String(Int64(d)) }
            return "\(d)"
        default:
            return number.stringValue
        }
    }

    private static func quote(_ s: String) -> String {
        var out = "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out.append("\\\"")
            case "\\": out.append("\\\\")
            case "\n": out.append("\\n")
            case "\r": out.append("\\r")
            case "\t": out.append("\\t")
            case let c where c.value < 0x20:
                out.append(String(format: "\\u%04x", c.value))
            default:
                out.unicodeScalars.append(scalar)
            }
        }
        out.append("\"")
        return out
    }
}
