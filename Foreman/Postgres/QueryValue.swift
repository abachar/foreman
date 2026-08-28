import Foundation
import PostgresNIO

/// A result cell as the grid and the clipboard need it (postgres R16, technical options).
///
/// Results come back in the binary format (PostgresNIO asks for it on every column), so the
/// value is decoded per type: PostgresNIO's decoders for what it knows, ~60 lines here for
/// `time`, `interval`, `money`, `inet`, `macaddr`, `oid` and arrays of any known element, whose
/// wire formats are documented and tiny. A type nobody knows is shown as its name and its hex.
nonisolated enum QueryValue: Equatable, Sendable {
    case null
    case text(String)
    case int(Int64)
    case double(Double)
    case bool(Bool)
    case date(Date, hasTime: Bool)
    case json(String)
    case bytes([UInt8])
    /// Already formatted: arrays, time, interval, network types, unknown types.
    case raw(String)

    static let nullText = "NULL"
    /// Edge cases: a very wide column is cut in the grid, whole on a double click.
    static let displayLimit = 1000
    static let bytesDisplayLimit = 32

    // MARK: - Decoding

    static func decode(_ cell: PostgresCell) -> QueryValue {
        guard var buffer = cell.bytes else { return .null }
        return decode(type: cell.dataType, buffer: &buffer)
    }

    static func decode(type: PostgresDataType, buffer: inout ByteBuffer) -> QueryValue {
        do {
            return try decodeKnown(type: type, buffer: &buffer)
        } catch {
            return .raw("<\(type)> \\x" + hex(buffer.readableBytesView.prefix(bytesDisplayLimit)))
        }
    }

    private static func decodeKnown(type: PostgresDataType, buffer: inout ByteBuffer) throws -> QueryValue {
        let context = PostgresDecodingContext.default
        switch type {
        case .bool:
            return .bool(try Bool(from: &buffer, type: type, format: .binary, context: context))
        case .int2:
            return .int(Int64(try Int16(from: &buffer, type: type, format: .binary, context: context)))
        case .int4:
            return .int(Int64(try Int32(from: &buffer, type: type, format: .binary, context: context)))
        case .int8:
            return .int(try Int64(from: &buffer, type: type, format: .binary, context: context))
        case .oid, .xid, .regclass, .regproc:
            return .int(Int64(try readInteger(&buffer, as: UInt32.self)))
        case .float4:
            return .double(Double(try Float(from: &buffer, type: type, format: .binary, context: context)))
        case .float8:
            return .double(try Double(from: &buffer, type: type, format: .binary, context: context))
        case .numeric:
            return .raw(try Decimal(from: &buffer, type: type, format: .binary, context: context).description)
        case .money:
            let cents = try readInteger(&buffer, as: Int64.self)
            return .raw(String(format: "%lld.%02lld", cents / 100, abs(cents % 100)))
        case .text, .varchar, .name, .bpchar, .char:
            return .text(try String(from: &buffer, type: type, format: .binary, context: context))
        case .uuid:
            return .text(try UUID(from: &buffer, type: type, format: .binary, context: context).uuidString.lowercased())
        case .date:
            return .date(try Date(from: &buffer, type: type, format: .binary, context: context), hasTime: false)
        case .timestamp, .timestamptz:
            return .date(try Date(from: &buffer, type: type, format: .binary, context: context), hasTime: true)
        case .time:
            return .raw(timeOfDay(microseconds: try readInteger(&buffer, as: Int64.self)))
        case .timetz:
            let microseconds = try readInteger(&buffer, as: Int64.self)
            let zone = try readInteger(&buffer, as: Int32.self)
            return .raw(timeOfDay(microseconds: microseconds) + zoneSuffix(secondsWestOfUTC: zone))
        case .interval:
            let microseconds = try readInteger(&buffer, as: Int64.self)
            let days = try readInteger(&buffer, as: Int32.self)
            let months = try readInteger(&buffer, as: Int32.self)
            return .raw(interval(microseconds: microseconds, days: days, months: months))
        case .json, .jsonb:
            return .json(try String(from: &buffer, type: type, format: .binary, context: context))
        case .bytea:
            return .bytes(try [UInt8](from: &buffer, type: type, format: .binary, context: context))
        case .inet, .cidr:
            return .raw(try networkAddress(&buffer))
        case .macaddr:
            return .raw(
                try (0..<6).map { _ in String(format: "%02x", try readInteger(&buffer, as: UInt8.self)) }.joined(
                    separator: ":"))
        default:
            if let array = try decodeArray(type: type, buffer: &buffer) {
                return .raw(array)
            }
            throw PostgresDecodingError.Code.typeMismatch
        }
    }

    /// The binary array format: dimensions, element type, then `length + bytes` per element.
    private static func decodeArray(type: PostgresDataType, buffer: inout ByteBuffer) throws -> String? {
        let dimensions = try readInteger(&buffer, as: Int32.self)
        guard (0...6).contains(dimensions) else { return nil }
        _ = try readInteger(&buffer, as: Int32.self)
        let elementType = PostgresDataType(try readInteger(&buffer, as: UInt32.self))
        guard elementType != .null || dimensions == 0 else { return nil }
        var counts: [Int] = []
        for _ in 0..<dimensions {
            counts.append(Int(try readInteger(&buffer, as: Int32.self)))
            _ = try readInteger(&buffer, as: Int32.self)
        }
        func level(_ depth: Int) throws -> String {
            guard depth < counts.count else { return "{}" }
            var items: [String] = []
            for _ in 0..<counts[depth] {
                if depth == counts.count - 1 {
                    let length = try readInteger(&buffer, as: Int32.self)
                    if length < 0 {
                        items.append(nullText)
                    } else {
                        guard var slice = buffer.readSlice(length: Int(length)) else {
                            throw PostgresDecodingError.Code.missingData
                        }
                        items.append(arrayElement(decode(type: elementType, buffer: &slice)))
                    }
                } else {
                    items.append(try level(depth + 1))
                }
            }
            return "{" + items.joined(separator: ",") + "}"
        }
        return try level(0)
    }

    private static func arrayElement(_ value: QueryValue) -> String {
        let text = value.fullText
        let needsQuotes =
            text.isEmpty || text.lowercased() == "null"
            || text.contains { $0 == "," || $0 == "{" || $0 == "}" || $0 == "\"" || $0 == "\\" || $0.isWhitespace }
        guard case .text = value, needsQuotes else { return text }
        return "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            + "\""
    }

    private static func readInteger<T: FixedWidthInteger>(_ buffer: inout ByteBuffer, as type: T.Type) throws -> T {
        guard let value = buffer.readInteger(as: type) else { throw PostgresDecodingError.Code.missingData }
        return value
    }

    static func timeOfDay(microseconds: Int64) -> String {
        let seconds = microseconds / 1_000_000
        let fraction = microseconds % 1_000_000
        let base = String(format: "%02lld:%02lld:%02lld", seconds / 3600, seconds / 60 % 60, seconds % 60)
        guard fraction != 0 else { return base }
        var digits = String(format: "%06lld", fraction)
        while digits.hasSuffix("0") {
            digits.removeLast()
        }
        return base + "." + digits
    }

    private static func zoneSuffix(secondsWestOfUTC: Int32) -> String {
        let east = -Int(secondsWestOfUTC)
        let sign = east < 0 ? "-" : "+"
        let minutes = abs(east) / 60
        return minutes % 60 == 0
            ? String(format: "%@%02d", sign, minutes / 60)
            : String(format: "%@%02d:%02d", sign, minutes / 60, minutes % 60)
    }

    static func interval(microseconds: Int64, days: Int32, months: Int32) -> String {
        var parts: [String] = []
        if months != 0 {
            let years = months / 12
            let rest = months % 12
            if years != 0 {
                parts.append("\(years) year" + (abs(years) == 1 ? "" : "s"))
            }
            if rest != 0 {
                parts.append("\(rest) mon" + (abs(rest) == 1 ? "" : "s"))
            }
        }
        if days != 0 {
            parts.append("\(days) day" + (abs(days) == 1 ? "" : "s"))
        }
        if microseconds != 0 || parts.isEmpty {
            parts.append((microseconds < 0 ? "-" : "") + timeOfDay(microseconds: abs(microseconds)))
        }
        return parts.joined(separator: " ")
    }

    private static func networkAddress(_ buffer: inout ByteBuffer) throws -> String {
        let family = try readInteger(&buffer, as: UInt8.self)
        let bits = try readInteger(&buffer, as: UInt8.self)
        _ = try readInteger(&buffer, as: UInt8.self)
        let count = Int(try readInteger(&buffer, as: UInt8.self))
        guard let bytes = buffer.readBytes(length: count) else { throw PostgresDecodingError.Code.missingData }
        let address: String
        if family == 2, count == 4 {
            address = bytes.map(String.init).joined(separator: ".")
            return bits == 32 ? address : "\(address)/\(bits)"
        }
        address = stride(from: 0, to: count, by: 2).map { index in
            String(format: "%x", (UInt16(bytes[index]) << 8) | UInt16(index + 1 < count ? bytes[index + 1] : 0))
        }.joined(separator: ":")
        return bits == 128 ? address : "\(address)/\(bits)"
    }

    private static func hex(_ bytes: some Sequence<UInt8>) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Formatting (R16)

    /// The whole value, as text.
    var fullText: String {
        switch self {
        case .null:
            return Self.nullText
        case .text(let text), .raw(let text), .json(let text):
            return text
        case .int(let value):
            return String(value)
        case .double(let value):
            return value == value.rounded() && abs(value) < 1e15 ? String(Int64(value)) : String(value)
        case .bool(let value):
            return value ? "true" : "false"
        case .date(let date, let hasTime):
            return hasTime ? date.formatted(.iso8601) : date.formatted(.iso8601.year().month().day())
        case .bytes(let bytes):
            return "\\x" + Self.hex(bytes)
        }
    }

    /// The grid's text: `NULL`, `bytea` as truncated hex, everything cut at 1,000 characters.
    var displayText: String {
        switch self {
        case .bytes(let bytes):
            let head = "\\x" + Self.hex(bytes.prefix(Self.bytesDisplayLimit))
            return bytes.count > Self.bytesDisplayLimit ? "\(head)… (\(bytes.count) bytes)" : head
        case .json(let text):
            return Self.truncated(text.replacingOccurrences(of: "\n", with: " "))
        default:
            return Self.truncated(fullText)
        }
    }

    /// The popover's text: `json` pretty-printed, the rest whole.
    var detailText: String {
        guard case .json(let text) = self, let data = text.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
            let pretty = try? JSONSerialization.data(
                withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]),
            let string = String(data: pretty, encoding: .utf8)
        else { return fullText }
        return string
    }

    /// R16, edge cases: `NULL` empty, `\t`, `\n` and `\\` escaped.
    var tsvText: String {
        guard self != .null else { return "" }
        return fullText.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\t", with: "\\t")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    static func truncated(_ text: String) -> String {
        guard text.count > displayLimit else { return text }
        return String(text.prefix(displayLimit)) + "…"
    }

    // MARK: - Sorting (R16)

    /// Numbers by value, dates by time, the rest as text; `NULL` last whatever the direction.
    static func compare(_ lhs: QueryValue, _ rhs: QueryValue) -> ComparisonResult {
        switch (lhs, rhs) {
        case (.null, .null):
            return .orderedSame
        case (.null, _):
            return .orderedDescending
        case (_, .null):
            return .orderedAscending
        case (.int(let a), .int(let b)):
            return a < b ? .orderedAscending : a > b ? .orderedDescending : .orderedSame
        case (.int(let a), .double(let b)):
            return compareDoubles(Double(a), b)
        case (.double(let a), .int(let b)):
            return compareDoubles(a, Double(b))
        case (.double(let a), .double(let b)):
            return compareDoubles(a, b)
        case (.bool(let a), .bool(let b)):
            return a == b ? .orderedSame : (!a ? .orderedAscending : .orderedDescending)
        case (.date(let a, _), .date(let b, _)):
            return a.compare(b)
        default:
            return lhs.fullText.localizedStandardCompare(rhs.fullText)
        }
    }

    private static func compareDoubles(_ a: Double, _ b: Double) -> ComparisonResult {
        a < b ? .orderedAscending : a > b ? .orderedDescending : .orderedSame
    }
}
