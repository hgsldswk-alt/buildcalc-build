import Foundation

struct Record: Codable, Identifiable, Equatable, Hashable, Sendable {
    enum Source: String, Codable, Sendable { case local, imported }
    var id = UUID()
    var createdAt = Date()
    var formulaVersion = MaterialMath.version
    var input: MaterialInput
    var result: MaterialResult
    var source: Source

    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var signature: String {
        let values = [result.lengthMM, result.widthMM, result.coverageMM2, result.waste,
                      Decimal(result.coats), result.rateVolumeLiters, result.bucketLiters]
        return "\(formulaVersion):\(input.material.rawValue):" + values.map { NSDecimalNumber(decimal: $0).stringValue }.joined(separator: ":")
    }
}

enum ShareCode {
    private struct Payload: Codable {
        var version: Int
        var formulaVersion: Int
        var input: MaterialInput
    }

    enum Failure: Error { case invalid }
    static let prefix = "MAT1:"
    static let limit = 2048

    private static func bytes(_ payload: Payload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(payload)
    }

    static func encode(_ record: Record) throws -> String {
        let data = try bytes(Payload(version: 1, formulaVersion: record.formulaVersion, input: record.input))
        return prefix + data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    static func decode(_ text: String) throws -> Record {
        guard text.utf8.count <= limit else { throw Failure.invalid }
        let code = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard code.hasPrefix(prefix) else { throw Failure.invalid }
        let body = code.dropFirst(prefix.count)
        guard !body.isEmpty, body.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }) else { throw Failure.invalid }
        var source = body.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        source += String(repeating: "=", count: (4 - source.utf8.count % 4) % 4)
        guard let data = Data(base64Encoded: source),
              let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.version == 1, payload.formulaVersion == MaterialMath.version,
              try bytes(payload) == data else { throw Failure.invalid }
        let input = payload.input
        guard (input.material == .paint && input.coats != nil && input.capacity != nil) ||
              (input.material != .paint && input.coats == nil && input.capacity == nil),
              [input.length, input.width, input.coverage, input.waste, input.coats, input.capacity]
                .compactMap({ $0 }).allSatisfy({ $0.text.utf8.count <= 64 && !$0.text.contains(where: \.isNewline) }) else {
            throw Failure.invalid
        }
        let record = Record(input: input, result: try MaterialMath.calculate(input), source: .imported)
        guard try encode(record) == code else { throw Failure.invalid }
        return record
    }
}

struct Milestones: Codable, Sendable {
    private var signatures: Set<String> = []
    private var days: Set<String> = []
    var requestedReview = false
    var count: Int { signatures.count }
    var canRequest: Bool { count >= 5 && days.count >= 2 && !requestedReview }

    mutating func record(_ record: Record, calendar: Calendar = .current) {
        guard record.source == .local, signatures.insert(record.signature).inserted else { return }
        let day = calendar.dateComponents([.era, .year, .month, .day], from: record.createdAt)
        days.insert([day.era, day.year, day.month, day.day].map { String($0 ?? 0) }.joined(separator: "-"))
    }
}
