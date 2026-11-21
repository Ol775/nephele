import Foundation

public struct MultipartPart: Sendable, Equatable {
    public var name: String?
    public var filename: String?
    public var contentType: String?
    public var data: Data
}

/// Builds and parses `multipart/form-data` bodies (Worker uploads and downloads).
public struct MultipartForm: Sendable {
    public let boundary: String
    private var parts: [Data] = []

    public init(boundary: String = UUID().uuidString) { self.boundary = boundary }

    public var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    public mutating func addJSON(name: String, _ value: Data) {
        append(headers: ["Content-Disposition: form-data; name=\"\(name)\"", "Content-Type: application/json"], data: value)
    }

    public mutating func addFile(name: String, filename: String, contentType: String, data: Data) {
        append(headers: ["Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"", "Content-Type: \(contentType)"], data: data)
    }

    public var body: Data {
        var out = Data()
        for p in parts { out.append(p) }
        out.append(Data("--\(boundary)--\r\n".utf8))
        return out
    }

    private mutating func append(headers: [String], data: Data) {
        var p = Data("--\(boundary)\r\n".utf8)
        p.append(Data((headers.joined(separator: "\r\n") + "\r\n\r\n").utf8))
        p.append(data)
        p.append(Data("\r\n".utf8))
        parts.append(p)
    }

    public static func parse(_ data: Data, contentType: String) -> [MultipartPart] {
        guard let range = contentType.range(of: "boundary=") else { return [] }
        let boundary = contentType[range.upperBound...].split(separator: ";").first.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\" ")) } ?? ""
        guard !boundary.isEmpty else { return [] }
        let delimiter = Data("--\(boundary)".utf8)
        let crlf = Data("\r\n".utf8), blank = Data("\r\n\r\n".utf8)
        var result: [MultipartPart] = []
        var cursor = data.startIndex
        guard var start = data.range(of: delimiter, in: cursor..<data.endIndex) else { return [] }
        while true {
            cursor = start.upperBound
            if data[cursor...].starts(with: Data("--".utf8)) { break }
            guard let next = data.range(of: crlf + delimiter, in: cursor..<data.endIndex) else { break }
            var section = data[cursor..<next.lowerBound]
            if section.starts(with: crlf) { section = section.dropFirst(2) }
            if let split = section.range(of: blank) {
                let head = String(decoding: section[section.startIndex..<split.lowerBound], as: UTF8.self)
                var part = MultipartPart(name: nil, filename: nil, contentType: nil, data: Data(section[split.upperBound...]))
                for line in head.components(separatedBy: "\r\n") {
                    let lower = line.lowercased()
                    if lower.hasPrefix("content-disposition:") {
                        part.name = attribute("name", in: line)
                        part.filename = attribute("filename", in: line)
                    } else if lower.hasPrefix("content-type:") {
                        part.contentType = line.dropFirst("content-type:".count).trimmingCharacters(in: .whitespaces)
                    }
                }
                result.append(part)
            }
            start = next.lowerBound + crlf.count..<next.upperBound
        }
        return result
    }

    private static func attribute(_ key: String, in line: String) -> String? {
        guard let r = line.range(of: "; \(key)=\"") ?? line.range(of: " \(key)=\"") else { return nil }
        let rest = line[r.upperBound...]
        return rest.firstIndex(of: "\"").map { String(rest[..<$0]) }
    }
}
