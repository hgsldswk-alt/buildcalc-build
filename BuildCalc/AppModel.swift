import SwiftUI

struct Draft: Codable, Equatable {
    var system: UnitSystem = Locale.current.measurementSystem == .us ? .imperial : .metric
    var length = InputValue()
    var width = InputValue()
    var conversion = InputValue()
    var specs = Dictionary(uniqueKeysWithValues: Material.allCases.map { ($0, Specs(material: $0)) })

    struct Specs: Codable, Equatable {
        var coverage = InputValue()
        var waste: InputValue
        var coats = InputValue(text: "2")
        var capacity = InputValue()

        init(material: Material) { waste = InputValue(text: material.defaultWaste) }
    }

    func input(_ material: Material) -> MaterialInput {
        let spec = specs[material] ?? Specs(material: material)
        return MaterialInput(material: material, length: length, width: width, coverage: spec.coverage,
                             waste: spec.waste, coats: material == .paint ? spec.coats : nil,
                             capacity: material == .paint ? spec.capacity : nil)
    }

    func field(_ field: Field, material: Material) -> InputValue {
        let spec = specs[material] ?? Specs(material: material)
        switch field {
        case .length: return length
        case .width: return width
        case .conversion: return conversion
        case .coverage: return spec.coverage
        case .waste: return spec.waste
        case .coats: return spec.coats
        case .capacity: return spec.capacity
        }
    }

    mutating func set(_ field: Field, material: Material, value: InputValue) {
        switch field {
        case .length: length = value
        case .width: width = value
        case .conversion: conversion = value
        default:
            var spec = specs[material] ?? Specs(material: material)
            switch field {
            case .coverage: spec.coverage = value
            case .waste: spec.waste = value
            case .coats: spec.coats = value
            case .capacity: spec.capacity = value
            default: break
            }
            specs[material] = spec
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var draft = Draft() { didSet { persist(draft, key: "draft") } }
    @Published var milestones = Milestones() { didSet { persist(milestones, key: "milestones") } }
    @Published private(set) var history: [Record] = []
    @Published private(set) var ready = false
    @Published private(set) var storageError = false
    private let defaults = Launch.testing ? UserDefaults(suiteName: "BuildCalcUI")! : .standard
    private var store: LocalStore?
    private var opening = false

    func start() async {
        guard !ready, !opening else { return }
        opening = true
        defer { opening = false }
        let reset = Launch.testing && Launch.arguments.contains("-reset")
        if reset { defaults.removePersistentDomain(forName: "BuildCalcUI") }
        if let saved: Draft = load("draft") { draft = saved }
        if let saved: Milestones = load("milestones") { milestones = saved }
        if Launch.testing {
            if let system = Launch.environment["BUILDCALC_SYSTEM"].flatMap(UnitSystem.init(rawValue:)) { draft.system = system }
            let material = Launch.environment["BUILDCALC_MATERIAL"].flatMap(Material.init(rawValue:)) ?? .floor
            for (field, key) in [(Field.length, "LENGTH"), (.width, "WIDTH"), (.coverage, "COVERAGE"), (.waste, "WASTE"),
                                 (.coats, "COATS"), (.capacity, "CAPACITY"), (.conversion, "CONVERSION")] {
                if let text = Launch.environment["BUILDCALC_" + key] {
                    draft.set(field, material: material, value: InputValue(text: text, system: draft.system,
                                                                          volume: draft.system == .metric ? .liter : .gallon))
                }
            }
        }
        do {
            let opened = try await LocalStore.open(testing: Launch.testing)
            if reset { try await opened.clear() }
            history = try await opened.all()
            store = opened
            storageError = false
        } catch { storageError = true }
        ready = true
    }

    func save(_ record: Record) async -> Record? {
        guard let store else { storageError = true; return nil }
        do {
            let saved = try await store.put(record)
            if !history.contains(where: { $0.id == saved.id }) {
                history.insert(saved, at: 0)
                milestones.record(saved)
            }
            storageError = false
            return saved
        } catch { storageError = true; return nil }
    }

    func delete(_ record: Record) async -> Bool {
        guard let store else { return false }
        do {
            try await store.remove(record.id)
            history.removeAll { $0.id == record.id }
            storageError = false
            return true
        } catch { storageError = true; return false }
    }

    func use(_ record: Record) {
        let input = record.input
        draft.length = input.length
        draft.width = input.width
        draft.set(.coverage, material: input.material, value: input.coverage)
        draft.set(.waste, material: input.material, value: input.waste)
        if let coats = input.coats { draft.set(.coats, material: input.material, value: coats) }
        if let capacity = input.capacity { draft.set(.capacity, material: input.material, value: capacity) }
    }

    private func persist<Value: Encodable>(_ value: Value, key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }

    private func load<Value: Decodable>(_ key: String) -> Value? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(Value.self, from: $0) }
    }
}
