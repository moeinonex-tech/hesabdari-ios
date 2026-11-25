import Foundation

/// Lossless JSON value. The backup file is kept as JSON so that every field the web app
/// writes, including fields this version does not know yet, survives import → export.
public enum JSONValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    // MARK: accessors

    public subscript(key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }

    public var objectValue: [String: JSONValue]? { if case .object(let o) = self { return o }; return nil }
    public var arrayValue: [JSONValue]? { if case .array(let a) = self { return a }; return nil }
    public var stringValue: String? { if case .string(let s) = self { return s }; return nil }
    public var boolValue: Bool? { if case .bool(let b) = self { return b }; return nil }
    public var isNull: Bool { if case .null = self { return true }; return false }

    /// Integer value for ints and integral doubles (JSON has one number type).
    public var intValue: Int? {
        switch self {
        case .int(let i): return Int(i)
        case .double(let d): return d.isFinite && d == d.rounded() && abs(d) < 9e15 ? Int(d) : nil
        default: return nil
        }
    }

    public var doubleValue: Double? {
        switch self {
        case .int(let i): return Double(i)
        case .double(let d): return d
        default: return nil
        }
    }

    public var isNumber: Bool { doubleValue != nil }

    /// JS truthiness, for code ported from the web app.
    public var isTruthy: Bool {
        switch self {
        case .null: return false
        case .bool(let b): return b
        case .int(let i): return i != 0
        case .double(let d): return d != 0 && !d.isNaN
        case .string(let s): return !s.isEmpty
        case .array, .object: return true
        }
    }

    /// The value as a plain string id (web ids are strings; old data may hold numbers).
    public var idString: String? {
        switch self {
        case .string(let s): return s.isEmpty ? nil : s
        case .int(let i): return String(i)
        case .double(let d): return Money.jsNumberString(d)
        default: return nil
        }
    }
}

extension JSONValue: Codable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let i = try? c.decode(Int64.self) { self = .int(i); return }
        if let d = try? c.decode(Double.self) { self = .double(d); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([JSONValue].self) { self = .array(a); return }
        if let o = try? c.decode([String: JSONValue].self) { self = .object(o); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported JSON value")
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .int(let i): try c.encode(i)
        case .double(let d): try c.encode(d)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }
}

public enum JSONCoding {
    public static func decode(_ data: Data) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: data)
    }

    public static func encode(_ value: JSONValue, pretty: Bool = false) throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : [.sortedKeys, .withoutEscapingSlashes]
        return try e.encode(value)
    }

    public static func string(_ value: JSONValue) throws -> String {
        String(decoding: try encode(value), as: UTF8.self)
    }

    /// the encoder `encode(_:pretty: false)` uses, to reuse for many values (same output)
    public static func compactEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }

    /// Decodes many JSON texts in parallel; the result is in the same order, each value exactly what `decode` gives.
    public static func decodeAll(_ texts: [String]) throws -> [JSONValue] {
        let n = texts.count
        guard n > 512 else { return try texts.map { try decode(Data($0.utf8)) } }
        var out = [JSONValue?](repeating: nil, count: n)
        var firstError: Error?
        let lock = NSLock()
        let chunks = max(1, min(ProcessInfo.processInfo.activeProcessorCount * 2, n / 256))
        out.withUnsafeMutableBufferPointer { buf in
            let base = buf.baseAddress!
            DispatchQueue.concurrentPerform(iterations: chunks) { c in
                let decoder = JSONDecoder()
                var i = c * n / chunks
                let end = (c + 1) * n / chunks
                while i < end {
                    do { (base + i).pointee = try decoder.decode(JSONValue.self, from: Data(texts[i].utf8)) }
                    catch { lock.lock(); if firstError == nil { firstError = error }; lock.unlock(); return }
                    i += 1
                }
            }
        }
        if let e = firstError { throw e }
        return out.map { $0! }
    }
}
