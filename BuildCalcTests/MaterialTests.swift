import Foundation
import XCTest

final class MaterialTests: XCTestCase {
    private func value(_ text: String, _ system: UnitSystem = .metric, volume: VolumeUnit = .liter) -> InputValue {
        InputValue(text: text, system: system, volume: volume)
    }

    private func estimate(_ material: Material = .floor, _ length: String = "4", _ width: String = "3",
                          _ coverage: String = "2.20", waste: String = "8", system: UnitSystem = .metric,
                          volume: VolumeUnit = .liter, coats: String = "2", capacity: String = "2.5") -> MaterialInput {
        MaterialInput(material: material, length: value(length, system), width: value(width, system),
                      coverage: value(coverage, system, volume: volume), waste: value(waste),
                      coats: material == .paint ? value(coats) : nil,
                      capacity: material == .paint ? value(capacity, system, volume: volume) : nil)
    }

    func testCoreReviewRequiresThreeActionsOnTwoLocalDates() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        let firstDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 23)))
        let nextDay = firstDay.addingTimeInterval(2 * 3600)
        let empty = try JSONDecoder().decode(CoreReviewProgress.self, from: Data("{}".utf8))
        XCTAssertFalse(empty.isEligible)
        var progress = CoreReviewProgress.recording(empty, at: firstDay, calendar: calendar)
        var twoDays = progress
        twoDays.record(at: nextDay, calendar: calendar)
        XCTAssertFalse(twoDays.isEligible)
        progress.record(at: firstDay, calendar: calendar)
        XCTAssertFalse(progress.isEligible)

        var sameDay = progress
        sameDay.record(at: firstDay, calendar: calendar)
        XCTAssertFalse(sameDay.isEligible)

        let data = try JSONEncoder().encode(progress)
        progress = try JSONDecoder().decode(CoreReviewProgress.self, from: data)
        progress.record(at: nextDay, calendar: calendar)
        XCTAssertTrue(progress.isEligible)
    }

    func testTapeMeasureAndDecimalInput() throws {
        for (source, expected) in [("12′ 7 1/2″", "3848.1"), ("1/64 in", "0.396875"), ("0.5 ft", "152.4"),
                                   ("6 in", "152.4"), ("４，５ ｍ", "4500"), ("2,50 m", "2500"), ("25 cm", "250"), ("25 mm", "25")] {
            XCTAssertEqual(try MaterialMath.length(value(source), field: .length), Exact.decimal(expected), source)
        }
        XCTAssertEqual(try MaterialMath.length(value("4.5", .imperial), field: .length), Exact.decimal("1371.6"))
        for invalid in ["", "0", "-1", "1/0", "1/3 in", "NaN", "Inf", "1e3", "1,234.5", "100.000001 m", "12 ft -7 in", "4 m junk"] {
            XCTAssertThrowsError(try MaterialMath.length(value(invalid), field: .length), invalid)
        }
    }

    func testPackageBoundariesAndValidation() throws {
        let floor = try MaterialMath.calculate(estimate())
        XCTAssertEqual(floor.net, 12_000_000)
        XCTAssertEqual(floor.required, 12_960_000)
        XCTAssertEqual(floor.quantity, 6)
        XCTAssertEqual(try MaterialMath.calculate(estimate(.panel, "3", "2", "1.50", waste: "0")).quantity, 4)
        XCTAssertEqual(try MaterialMath.calculate(estimate(.panel, "3.000001", "2", "1.50", waste: "0")).quantity, 5)
        XCTAssertEqual(try MaterialMath.calculate(estimate(.paint, "4", "3", "10", waste: "10")).quantity, 2)
        for invalid in [estimate(.floor, "4", "3", "0"), estimate(waste: "100.1"),
                        estimate(.paint, "4", "3", "10", coats: "2.5"), estimate(.paint, "4", "3", "10", capacity: "0")] {
            XCTAssertThrowsError(try MaterialMath.calculate(invalid))
        }
    }

    func testSameRoomAcrossSystems() throws {
        let floorImperial = try MaterialMath.calculate(estimate(.floor, "8", "10", "24", system: .imperial))
        let floorMetric = try MaterialMath.calculate(estimate(.floor, "2.4384", "3.048", "2.22967296"))
        XCTAssertEqual(floorImperial, floorMetric)
        XCTAssertEqual(floorImperial.quantity, 4)
        XCTAssertEqual(try MaterialMath.calculate(estimate(.panel, "8", "10", "20", waste: "0", system: .imperial)).quantity, 4)
        XCTAssertEqual(try MaterialMath.calculate(estimate(.panel, "2.4384", "3.048", "1.8580608", waste: "0")).quantity, 4)
        for (widthFT, widthM, expected) in [("10", "3.048", 2), ("10.01", "3.051048", 3)] {
            let gallons = try MaterialMath.calculate(estimate(.paint, "8", widthFT, "88", waste: "10", system: .imperial, volume: .gallon, capacity: "1"))
            let metricArea = try MaterialMath.calculate(estimate(.paint, "2.4384", widthM, "8.17546752", waste: "10", volume: .gallon, capacity: "1"))
            XCTAssertEqual(gallons, metricArea)
            XCTAssertEqual(gallons.quantity, expected)
        }
        var mixed = estimate(.paint, "8", "10", "88", waste: "10", system: .imperial, volume: .gallon, capacity: "1")
        mixed.capacity = value("3.785411784")
        XCTAssertEqual(try MaterialMath.calculate(mixed).quantity, 2)
    }

    func testCodeRoundTripAndStrictFields() throws {
        let input = estimate()
        let record = Record(input: input, result: try MaterialMath.calculate(input), source: .local)
        let code = try ShareCode.encode(record)
        let imported = try ShareCode.decode(code)
        let duplicate = try ShareCode.decode(code)
        XCTAssertEqual(imported.result, record.result)
        XCTAssertEqual(imported.input, record.input)
        XCTAssertEqual(imported.signature, duplicate.signature)
        XCTAssertNotEqual(imported.id, record.id)
        XCTAssertEqual(imported.source, .imported)
        var source = String(code.dropFirst(5)).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        source += String(repeating: "=", count: (4 - source.count % 4) % 4)
        let data = try XCTUnwrap(Data(base64Encoded: source))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for (key, invalid) in [("version", 2), ("formulaVersion", 2), ("quantity", 99)] {
            var forged = object
            forged[key] = invalid
            let bytes = try JSONSerialization.data(withJSONObject: forged, options: [.sortedKeys, .withoutEscapingSlashes])
            let encoded = bytes.base64EncodedString().replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
            XCTAssertThrowsError(try ShareCode.decode("MAT1:" + encoded))
        }
        XCTAssertThrowsError(try ShareCode.decode(code + "="))
        XCTAssertThrowsError(try ShareCode.decode("MAT1:" + String(repeating: "A", count: 2048)))
    }

    func testMilestoneCountsOnlyDistinctLocalInputsAcrossDays() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var stats = Milestones()
        for index in 1...6 {
            let input = estimate(.floor, String(index), "3")
            let day = index == 6 ? start.addingTimeInterval(86_400 * 2) : start
            var record = Record(createdAt: day, input: input, result: try MaterialMath.calculate(input), source: .imported)
            stats.record(record)
            XCTAssertEqual(stats.count, index - 1)
            record.source = .local
            stats.record(record)
            stats.record(record)
            XCTAssertEqual(stats.count, index)
            XCTAssertEqual(stats.canRequest, index == 6)
        }
        stats.requestedReview = true
        XCTAssertFalse(stats.canRequest)
    }
}
