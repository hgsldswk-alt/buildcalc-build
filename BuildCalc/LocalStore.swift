import Foundation
import SwiftData

@Model
final class CalculationRecord {
    @Attribute(.unique) var identity: UUID
    var createdAt: Date
    var signature: String
    var source: String
    var snapshot: Data

    init(_ record: Record) throws {
        identity = record.id
        createdAt = record.createdAt
        signature = record.signature
        source = record.source.rawValue
        snapshot = try JSONEncoder().encode(record)
    }
}

@ModelActor
actor LocalStore {
    static func open(testing: Bool) async throws -> LocalStore {
        try await Task.detached(priority: .utility) {
            let schema = Schema([CalculationRecord.self])
            let configuration = ModelConfiguration(testing ? "BuildCalcUI" : "BuildCalcV1",
                                                    schema: schema, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            return LocalStore(modelContainer: container)
        }.value
    }

    func clear() throws {
        try modelContext.delete(model: CalculationRecord.self)
        try save()
    }

    func all() throws -> [Record] {
        try modelContext.fetch(FetchDescriptor<CalculationRecord>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))
            .map(decode)
    }

    func put(_ record: Record) throws -> Record {
        let signature = record.signature
        let source = record.source.rawValue
        var lookup = FetchDescriptor<CalculationRecord>(predicate: #Predicate { $0.signature == signature && $0.source == source })
        lookup.fetchLimit = 1
        if let previous = try modelContext.fetch(lookup).first { return try decode(previous) }
        modelContext.insert(try CalculationRecord(record))
        try save()
        return record
    }

    func remove(_ id: UUID) throws {
        var lookup = FetchDescriptor<CalculationRecord>(predicate: #Predicate { $0.identity == id })
        lookup.fetchLimit = 1
        if let row = try modelContext.fetch(lookup).first {
            modelContext.delete(row)
            try save()
        }
    }

    private func decode(_ row: CalculationRecord) throws -> Record {
        try JSONDecoder().decode(Record.self, from: row.snapshot)
    }

    private func save() throws {
        do { try modelContext.save() }
        catch { modelContext.rollback(); throw error }
    }
}
