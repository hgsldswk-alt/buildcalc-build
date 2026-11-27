import SwiftUI
import StoreKit
import UIKit
import UniformTypeIdentifiers

struct RecordResult: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let record: Record
    let system: UnitSystem
    private var result: MaterialResult { record.result }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L.t("result.recommend")).font(.caption.bold()).tracking(1)
                Text(L.quantity(record)).font(.system(.largeTitle, design: .monospaced).weight(.heavy))
                    .accessibilityIdentifier("result.quantity")
                Text(L.t("result.roundUp")).font(.caption)
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(alignment: .topTrailing) {
                PlanMark().stroke(Palette.tint.opacity(0.45), lineWidth: 1.4)
                    .frame(width: 60, height: 46).padding(14).accessibilityHidden(true)
            }
            .background(Palette.dark, in: RoundedRectangle(cornerRadius: 17)).foregroundStyle(Palette.white)

            VStack(alignment: .leading, spacing: 7) {
                Text(L.t("result.how")).font(.subheadline.bold())
                ForEach(steps, id: \.label) { step in
                    Divider()
                    let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 6))
                    layout {
                        Text(step.label).font(.caption).foregroundStyle(Palette.muted)
                        if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                        Text(step.value).font(.footnote.monospacedDigit().weight(.semibold))
                            .multilineTextAlignment(typeSize.isAccessibilitySize ? .leading : .trailing)
                    }.accessibilityElement(children: .combine)
                }
            }.modifier(PanelStyle())
            Text(L.t("result.verify")).font(.footnote).foregroundStyle(Palette.muted)
            if record.input.material == .panel { Text(L.t("panel.note")).font(.footnote).foregroundStyle(Palette.muted) }
        }
    }

    var steps: [ResultLine] {
        let scale = system.lengthUnit.factor
        let length = L.number(result.lengthMM / scale, digits: 8, minimum: 2)
        let width = L.number(result.widthMM / scale, digits: 8, minimum: 2)
        let net = L.area(result.net, system)
        let factor = L.number(1 + result.waste / 100, digits: 14)
        let required = L.area(result.required, system)
        let perPackage = L.area(result.packageCoverage, system)
        let paint = record.input.material == .paint
        let work = paint ? L.f("formula.paint", net, String(result.coats), factor, required) : L.f("formula.waste", net, factor, required)
        var lines = [ResultLine(label: L.t("result.net"), value: L.f("formula.net", length, width, system.lengthUnit.rawValue, net)),
                     ResultLine(label: L.f("result.waste", L.number(result.waste, digits: 12)), value: work)]
        if paint {
            let coverage = record.input.coverage
            let capacity = record.input.capacity ?? InputValue()
            lines.append(ResultLine(label: L.t("result.paintCapacity"), value: L.f("formula.capacity", coverage.text,
                L.f("coverage.rateUnit", coverage.system.areaSymbol, L.volume(coverage.volume)), capacity.text, L.volume(capacity.volume), perPackage)))
        }
        lines.append(ResultLine(label: L.t("result.roundUp"), value: L.f("formula.round", required, perPackage,
            L.number(result.ratio, digits: 2), L.quantity(record))))
        return lines
    }
}

struct ResultLine { let label: String; let value: String }

struct HistoryView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview
    @Environment(\.scenePhase) private var scenePhase
    @State private var selected: Record?
    @State private var milestone: SharePayload?
    @State private var interacting = false
    let use: (Record) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if model.milestones.count >= 5 {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L.f("milestone.saved", String(model.milestones.count))).font(.headline)
                            Button(L.t("milestone.share")) {
                                interacting = true
                                milestone = SharePayload(count: model.milestones.count)
                            }.buttonStyle(PrimaryStyle()).accessibilityIdentifier("history.milestoneShare")
                        }.modifier(PanelStyle())
                    }
                    if model.history.isEmpty { Text(L.t("history.empty")).modifier(PanelStyle()) }
                    ForEach(model.history) { row in
                        Button {
                            interacting = true
                            selected = row
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(L.f("history.item", L.material(row.input.material), L.quantity(row))).font(.headline)
                                Text(row.createdAt, format: .dateTime.year().month().day().hour().minute()).font(.footnote)
                                if row.source == .imported { Text(L.t("history.imported")).font(.caption).foregroundStyle(Palette.green) }
                            }.modifier(PanelStyle())
                        }.buttonStyle(.plain).accessibilityIdentifier("history.record")
                    }
                }.padding(16)
            }
            .background(Palette.paper.ignoresSafeArea())
            .navigationTitle(L.t("action.recent"))
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(L.t("action.done")) { dismiss() }.accessibilityIdentifier("history.done") } }
            .navigationDestination(item: $selected) { row in RecordDetail(record: row, use: use) }
            .sheet(item: $milestone) { SharePresentation(payload: $0) }
            .task(id: interacting || scenePhase != .active) {
                guard !interacting, scenePhase == .active, !Launch.testing, model.milestones.canRequest else { return }
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
                guard !interacting, scenePhase == .active, model.milestones.canRequest else { return }
                if !model.storageError, selected == nil, milestone == nil,
                   CoreReview.shared.attempt({ requestReview() }) {
                    model.milestones.requestedReview = true
                }
            }
            .simultaneousGesture(DragGesture(minimumDistance: 8).onChanged { _ in interacting = true })
        }.tint(Palette.green)
    }
}

struct RecordDetail: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var share: SharePayload?
    @State private var notice: String?
    let record: Record
    let use: (Record) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if record.source == .imported { Text(L.t("history.imported")).font(.footnote).foregroundStyle(Palette.green) }
                RecordResult(record: record, system: record.input.length.system)
                originals
                Button(L.t("action.share")) { share = SharePayload(record: record, system: record.input.length.system) }
                    .buttonStyle(PrimaryStyle()).accessibilityIdentifier("history.share")
                Button(L.t("action.copy")) {
                    UIPasteboard.general.string = SharePayload(record: record, system: record.input.length.system).caption
                    notice = "history.copied"
                }.buttonStyle(PrimaryStyle(muted: true)).accessibilityIdentifier("history.copy")
                if Launch.freePeriod {
                    Button(L.t("history.recalculate")) { use(record) }
                        .buttonStyle(PrimaryStyle(muted: true)).accessibilityIdentifier("history.recalculate")
                }
                Button(role: .destructive) {
                    Task { if await model.delete(record) { dismiss() } else { notice = "storage.error" } }
                } label: {
                    Text(L.t("action.delete")).frame(minHeight: 44).contentShape(Rectangle())
                }.accessibilityIdentifier("history.delete")
                if let notice { Text(L.t(notice)).font(.footnote) }
            }.padding(16)
        }
        .navigationTitle(L.material(record.input.material)).navigationBarTitleDisplayMode(.inline)
        .background(Palette.paper.ignoresSafeArea())
        .sheet(item: $share) { SharePresentation(payload: $0) }
    }

    private var originals: some View {
        let input = record.input
        let coverage = input.material == .paint ? L.f("coverage.rateUnit", input.coverage.system.areaSymbol, L.volume(input.coverage.volume)) : L.f("coverage.packUnit", input.coverage.system.areaSymbol, L.package(input.material))
        return VStack(alignment: .leading, spacing: 6) {
            Text(L.t("history.original")).font(.headline)
            original("field.length", input.length.text, rawLengthUnit(input.length))
            original("field.width", input.width.text, rawLengthUnit(input.width))
            original("coverage." + input.material.rawValue, input.coverage.text, coverage)
            original("field.waste", input.waste.text, "%")
            if let coats = input.coats { original("field.coats", coats.text, "") }
            if let capacity = input.capacity { original("field.capacity", capacity.text, L.volume(capacity.volume)) }
        }.modifier(PanelStyle())
    }

    private func rawLengthUnit(_ input: InputValue) -> String {
        let text = MaterialMath.normalized(input.text)
        if text.range(of: #"[a-z'\"]"#, options: .regularExpression) != nil { return "" }
        return text.contains("/") ? LengthUnit.inch.rawValue : input.system.lengthUnit.rawValue
    }

    private func original(_ key: String, _ text: String, _ unit: String) -> some View {
        Text(L.f("history.originalValue", L.t(key), unit.isEmpty ? text : L.f("value.unit", text, unit)))
            .font(.footnote.monospacedDigit())
    }
}

struct ImportView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var code = Launch.environment["BUILDCALC_IMPORT"] ?? ""
    @State private var selected: Record?
    @State private var notice: String?
    @State private var busy = false
    let use: (Record) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L.t("import.help")).font(.subheadline)
                    Text(L.t("import.paste")).font(.subheadline.bold()).accessibilityHidden(true)
                    PasteButton(payloadType: String.self) { items in
                        if let item = items.first { code = String(item.prefix(ShareCode.limit + 1)); open(code) }
                    }.accessibilityLabel(L.t("import.paste")).accessibilityIdentifier("import.paste")
                        .disabled(busy || !model.ready)
                        .tint(Palette.green)
                    TextField(L.t("import.placeholder"), text: $code, axis: .vertical)
                        .lineLimit(3...6).font(.footnote.monospaced()).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("import.code").modifier(PanelStyle())
                    Button(L.t("import.open")) { open(code) }.buttonStyle(PrimaryStyle())
                        .disabled(busy || !model.ready).accessibilityIdentifier("import.open")
                    if let notice { Text(L.t(notice)).foregroundStyle(.red).font(.footnote).accessibilityIdentifier("import.error") }
                }.padding(16)
            }.scrollDismissesKeyboard(.interactively)
            .background(Palette.paper.ignoresSafeArea())
            .navigationTitle(L.t("action.import"))
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(L.t("action.done")) { dismiss() }.accessibilityIdentifier("import.done") } }
            .navigationDestination(item: $selected) { row in RecordDetail(record: row, use: use) }
        }.tint(Palette.green)
    }

    private func open(_ text: String) {
        guard !busy else { return }
        notice = nil
        guard let record = try? ShareCode.decode(text) else { notice = "import.invalid"; return }
        busy = true
        Task {
            defer { busy = false }
            if let saved = await model.save(record) { selected = saved }
            else { notice = "storage.error" }
        }
    }
}
