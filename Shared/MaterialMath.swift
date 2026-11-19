import Foundation

enum UnitSystem: String, Codable, CaseIterable, Sendable {
    case metric, imperial
    var lengthUnit: LengthUnit { self == .metric ? .m : .ft }
    var areaFactor: Decimal { self == .metric ? 1_000_000 : Exact.decimal("92903.04") }
    var areaSymbol: String { self == .metric ? "m²" : "ft²" }
}

enum LengthUnit: String, Sendable {
    case m, cm, mm, ft, inch = "in"
    var factor: Decimal {
        switch self {
        case .m: return 1000
        case .cm: return 10
        case .mm: return 1
        case .ft: return Exact.decimal("304.8")
        case .inch: return Exact.decimal("25.4")
        }
    }
}

enum VolumeUnit: String, Codable, CaseIterable, Sendable {
    case liter, gallon
    var factor: Decimal { self == .liter ? 1 : Exact.decimal("3.785411784") }
}

enum Material: String, Codable, CaseIterable, Sendable {
    case floor, panel, paint
    var defaultWaste: String { self == .floor ? "8" : "10" }
}

enum Field: String, Codable, Hashable, Sendable {
    case length, width, coverage, waste, coats, capacity, conversion
}

struct InputValue: Codable, Equatable, Sendable {
    var text = ""
    var system: UnitSystem = .metric
    var volume: VolumeUnit = .liter
}

struct MaterialInput: Codable, Equatable, Sendable {
    var material: Material
    var length: InputValue
    var width: InputValue
    var coverage: InputValue
    var waste: InputValue
    var coats: InputValue?
    var capacity: InputValue?
}

struct MaterialResult: Codable, Equatable, Sendable {
    var lengthMM: Decimal
    var widthMM: Decimal
    var net: Decimal
    var required: Decimal
    var coverageMM2: Decimal
    var rateVolumeLiters: Decimal
    var bucketLiters: Decimal
    var waste: Decimal
    var coats: Int
    var quantity: Int

    var packageCoverage: Decimal { coverageMM2 * bucketLiters / rateVolumeLiters }
    var ratio: Decimal { required * rateVolumeLiters / (coverageMM2 * bucketLiters) }
}

struct FieldIssue: Error, Equatable {
    enum Reason: String { case missing, invalid, range }
    var field: Field
    var reason: Reason
}

enum Exact {
    static let locale = Locale(identifier: "en_US_POSIX")
    static func decimal(_ token: String) -> Decimal { Decimal(string: token, locale: locale)! }
}

enum MaterialMath {
    static let version = 1
    static let maxQuantity = 1_000_000_000

    static func normalized(_ text: String) -> String {
        (text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text)
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: "′", with: "'")
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "″", with: "\"")
            .replacingOccurrences(of: "”", with: "\"")
            .replacingOccurrences(of: "⁄", with: "/")
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func number(_ text: String) -> Decimal? {
        guard text.utf8.count <= 64, !text.contains(where: \.isNewline) else { return nil }
        let source = normalized(text)
        guard source.range(of: #"\A(?:[0-9]{1,10}(?:\.[0-9]{0,12})?|\.[0-9]{1,12})\z"#,
                           options: .regularExpression) != nil else { return nil }
        return Decimal(string: source, locale: Exact.locale)
    }

    private static func match(_ pattern: String, _ source: String) -> [String]? {
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let result = expression.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)) else { return nil }
        return (1..<result.numberOfRanges).map { index in
            Range(result.range(at: index), in: source).map { String(source[$0]) } ?? ""
        }
    }

    private static func inches(_ source: String) -> Decimal? {
        if let parsed = number(source) { return parsed }
        guard let parts = match(#"\A(?:([0-9]{1,7})[ -]+)?([0-9]{1,2})\s*/\s*(2|4|8|16|32|64)\z"#, source),
              let numerator = Int(parts[1]), let denominator = Int(parts[2]), numerator < denominator else { return nil }
        return Decimal(Int(parts[0]) ?? 0) + Decimal(numerator) / Decimal(denominator)
    }

    static func length(_ input: InputValue, field: Field) throws -> Decimal {
        guard input.text.utf8.count <= 64, !input.text.contains(where: \.isNewline) else {
            throw FieldIssue(field: field, reason: .invalid)
        }
        let source = normalized(input.text)
        guard !source.isEmpty else { throw FieldIssue(field: field, reason: .missing) }
        let value: Decimal?
        if let parts = match(#"\A(.+?)\s*(?:ft|')\s*(.+?)\s*(?:in|\")?\z"#, source),
           let feet = number(parts[0]), let inch = inches(parts[1]), inch < 12 {
            value = feet * LengthUnit.ft.factor + inch * LengthUnit.inch.factor
        } else if let parts = match(#"\A(.+?)\s*(mm|cm|m|ft|in|'|\")\z"#, source) {
            let unit: LengthUnit? = parts[1] == "'" ? .ft : parts[1] == "\"" ? .inch : LengthUnit(rawValue: parts[1])
            value = unit.flatMap { kind in
                (kind == .inch ? inches(parts[0]) : number(parts[0])).map { $0 * kind.factor }
            }
        } else if source.contains("/"), input.system == .imperial {
            value = inches(source).map { $0 * LengthUnit.inch.factor }
        } else {
            value = number(source).map { $0 * input.system.lengthUnit.factor }
        }
        guard let value else { throw FieldIssue(field: field, reason: .invalid) }
        guard value > 0, value <= 100_000 else { throw FieldIssue(field: field, reason: .range) }
        return value
    }

    static func spec(_ input: InputValue?, field: Field, max maximum: Decimal = 1_000_000, zero: Bool = false) throws -> Decimal {
        guard let input, !input.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FieldIssue(field: field, reason: .missing)
        }
        guard let value = number(input.text) else { throw FieldIssue(field: field, reason: .invalid) }
        guard (zero ? value >= 0 : value > 0), value <= maximum else { throw FieldIssue(field: field, reason: .range) }
        return value
    }

    private static func product(_ left: Decimal, _ right: Decimal, field: Field) throws -> Decimal {
        var first = left, second = right, result = Decimal()
        guard NSDecimalMultiply(&result, &first, &second, .plain) == .noError else {
            throw FieldIssue(field: field, reason: .range)
        }
        return result
    }

    static func calculate(_ input: MaterialInput) throws -> MaterialResult {
        let lengthMM = try length(input.length, field: .length)
        let widthMM = try length(input.width, field: .width)
        let coverage = try spec(input.coverage, field: .coverage) * input.coverage.system.areaFactor
        let waste = try spec(input.waste, field: .waste, max: 100, zero: true)
        let paint = input.material == .paint
        let coats = paint ? try spec(input.coats, field: .coats, max: 10) : 1
        let coatCount = NSDecimalNumber(decimal: coats).intValue
        guard coatCount > 0, Decimal(coatCount) == coats else { throw FieldIssue(field: .coats, reason: .range) }
        let rate = paint ? input.coverage.volume.factor : 1
        let capacity = paint ? try spec(input.capacity, field: .capacity) * (input.capacity?.volume.factor ?? 1) : 1
        let net = try product(lengthMM, widthMM, field: .width)
        var multiplier = Decimal(), whole = Decimal(1), fraction = waste / 100
        guard NSDecimalAdd(&multiplier, &whole, &fraction, .plain) == .noError else {
            throw FieldIssue(field: .waste, reason: .range)
        }
        let required = try product(product(net, coats, field: .coats), multiplier, field: .waste)
        let commonVolume = rate == (input.capacity?.volume.factor ?? 1)
        let comparisonRate = commonVolume ? 1 : rate
        let comparisonCapacity = commonVolume && paint ? try spec(input.capacity, field: .capacity) : capacity
        let numerator = try product(required, comparisonRate, field: .coverage)
        let denominator = try product(coverage, comparisonCapacity, field: paint ? .capacity : .coverage)
        var lower = 1, upper = maxQuantity
        while lower < upper {
            let midpoint = lower + (upper - lower) / 2
            if try meetsDemand(midpoint, denominator: denominator, numerator: numerator) { upper = midpoint }
            else { lower = midpoint + 1 }
        }
        guard try meetsDemand(lower, denominator: denominator, numerator: numerator) else {
            throw FieldIssue(field: .coverage, reason: .range)
        }
        return MaterialResult(lengthMM: lengthMM, widthMM: widthMM, net: net, required: required,
                              coverageMM2: coverage, rateVolumeLiters: rate, bucketLiters: capacity,
                              waste: waste, coats: coatCount, quantity: lower)
    }

    private static func meetsDemand(_ quantity: Int, denominator: Decimal, numerator: Decimal) throws -> Bool {
        var count = Decimal(quantity), coverage = denominator, total = Decimal()
        let status = NSDecimalMultiply(&total, &count, &coverage, .down)
        if status == .noError || (status == .lossOfPrecision && total >= numerator) { return total >= numerator }
        if status == .lossOfPrecision {
            var ceiling = Decimal()
            _ = NSDecimalMultiply(&ceiling, &count, &coverage, .up)
            if ceiling <= numerator { return false }
        }
        throw FieldIssue(field: .coverage, reason: .range)
    }
}
