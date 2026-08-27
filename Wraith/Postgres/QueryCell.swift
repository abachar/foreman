import Foundation
import PostgresNIO

/// A result cell as text (postgres R16, the minimum of it: the grid of 5.7 builds on this).
///
/// Results come back in the binary format, so the text is what PostgresNIO decodes per type;
/// a type it does not know is shown as UTF-8 when it reads, or as its type name.
nonisolated enum QueryCell {
    static let nullText = "NULL"

    /// `nil` is SQL `NULL`.
    static func text(of cell: PostgresCell) -> String? {
        guard cell.bytes != nil else { return nil }
        do {
            switch cell.dataType {
            case .bool:
                return try cell.decode(Bool.self).description
            case .int2:
                return try cell.decode(Int16.self).description
            case .int4:
                return try cell.decode(Int32.self).description
            case .int8:
                return try cell.decode(Int64.self).description
            case .float4:
                return try cell.decode(Float.self).description
            case .float8:
                return try cell.decode(Double.self).description
            case .numeric:
                return try cell.decode(Decimal.self).description
            case .text, .varchar, .name, .bpchar:
                return try cell.decode(String.self)
            case .uuid:
                return try cell.decode(UUID.self).uuidString.lowercased()
            case .date, .timestamp, .timestamptz:
                return iso8601(try cell.decode(Date.self), dateOnly: cell.dataType == .date)
            case .json, .jsonb:
                return try cell.decode(String.self)
            case .bytea:
                return "\\x" + (try cell.decode([UInt8].self)).map { String(format: "%02x", $0) }.joined()
            default:
                return fallback(cell)
            }
        } catch {
            return fallback(cell)
        }
    }

    private static func fallback(_ cell: PostgresCell) -> String {
        if var bytes = cell.bytes, let string = bytes.readString(length: bytes.readableBytes), !string.isEmpty,
            string.unicodeScalars.allSatisfy({ $0.value >= 0x20 || $0 == "\n" || $0 == "\t" })
        {
            return string
        }
        return "<\(cell.dataType)>"
    }

    private static func iso8601(_ date: Date, dateOnly: Bool) -> String {
        if dateOnly {
            return date.formatted(.iso8601.year().month().day())
        }
        return date.formatted(.iso8601)
    }
}
