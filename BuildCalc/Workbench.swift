import StoreKit
import SwiftUI

private enum WorkSheet: String, Identifiable {
    case history, transfer
    var id: String { rawValue }
}

struct Workbench: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.requestReview) private var requestReview
    @FocusState private var focused: Field?
    @State private var material: Material? = .floor
    @State private var issue: FieldIssue?
    @State private var result: Record?
    @State private var sheet: WorkSheet?
    @State private var share: SharePayload?
    private var kind: Material { material ?? .floor }
    private var system: UnitSystem { model.draft.system }
    private var volume: VolumeUnit { system == .metric ? .liter : .gallon }
    private var activeFields: [Field] { kind == .paint ? [.length, .width, .coverage, .waste, .coats, .capacity] : [.length, .width, .coverage, .waste] }
    private var missing: Bool { activeFields.contains { model.draft.field($0, material: kind).text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.horizontal, 18)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        intro
                        modes
                        if material == nil { conversion }
                        else { estimate }
                        if model.storageError { Text(L.t("storage.error")).font(.footnote).foregroundStyle(.red) }
                    }
                    .padding(.horizontal, 18).padding(.bottom, 10)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: focused) { _, field in
                    if let field { withAnimation(.easeOut(duration: 0.18)) { proxy.scrollTo(field, anchor: .center) } }
                }
                .onChange(of: result?.id) { _, identity in
                    if identity != nil { withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("estimate.result", anchor: .top) } }
                }
            }
            if material != nil { footer.padding(.horizontal, 18).padding(.vertical, 6) }
        }
        .foregroundStyle(Palette.ink)
        .background(Palette.paper.ignoresSafeArea())
        .sheet(item: $sheet) { current in
            switch current {
            case .history:
                HistoryView(use: loadRecord)
            case .transfer: ImportView(use: loadRecord)
            }
        }
        .sheet(item: $share) { SharePresentation(payload: $0) }
        .reviewAfterCoreAction(when: sheet == nil && share == nil && result != nil && issue == nil && focused == nil && !model.storageError) { requestReview() }
        .task {
            if Launch.testing, let selected = Launch.environment["BUILDCALC_MODE"] {
                material = selected == "conversion" ? nil : Material(rawValue: selected) ?? .floor
            }
        }
    }

    private func loadRecord(_ record: Record) {
        model.use(record)
        material = record.input.material
        result = nil
        issue = nil
        sheet = nil
    }

    private var header: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            HStack(spacing: 8) {
                PlanMark().stroke(Palette.green, lineWidth: 1.6).frame(width: 28, height: 24).accessibilityHidden(true)
                Text(L.t("app.name")).font(.headline).accessibilityAddTraits(.isHeader)
            }
            if !typeSize.isAccessibilitySize { Spacer(minLength: 2) }
            HStack(spacing: 8) {
                Button { focused = nil; sheet = .transfer } label: {
                    Text(L.t("action.import")).frame(minHeight: 44).contentShape(Rectangle())
                }
                    .accessibilityIdentifier("home.import")
                Button { focused = nil; sheet = .history } label: {
                    Text(L.t("action.recent")).frame(minHeight: 44).contentShape(Rectangle())
                }
                    .accessibilityIdentifier("home.recent")
            }
        }
        .buttonStyle(.plain).foregroundStyle(Palette.green)
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L.t(material == nil ? "hero.convertIndex" : "hero.index")).font(.caption2.bold()).tracking(1.4).foregroundStyle(Palette.green)
            Text(L.t(material == nil ? "hero.convertTitle" : "hero.title")).font(.title.bold()).accessibilityAddTraits(.isHeader)
            if result == nil {
                Text(L.t(material == nil ? "hero.convertHint" : "hero.hint")).font(.footnote).foregroundStyle(Palette.muted)
            }
        }
    }

    private var modes: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 3)) : AnyLayout(HStackLayout(spacing: 3))
        return layout {
            ForEach(Material.allCases, id: \.self) { option in
                tab(L.material(option), selected: material == option, id: "mode." + option.rawValue) { select(option) }
            }
            tab(L.t("mode.convert"), selected: material == nil, id: "mode.convert") { select(nil) }
        }
        .padding(3).background(Palette.tint, in: RoundedRectangle(cornerRadius: 13))
    }

    private func select(_ option: Material?) {
        guard material != option else { return }
        focused = nil
        material = option
        issue = nil
        result = nil
    }

    private func tab(_ title: String, selected: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.subheadline.bold()).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, 2)
                .foregroundStyle(selected ? Palette.white : Palette.green)
                .background(selected ? Palette.green : .clear, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain).accessibilityIdentifier(id).accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var units: some View {
        HStack(spacing: 2) {
            ForEach(UnitSystem.allCases, id: \.self) { option in
                tab(L.t("units." + option.rawValue), selected: system == option, id: "unit." + option.rawValue) {
                    focused = nil
                    model.draft.system = option
                }
            }
        }
        .padding(2).background(Palette.tint, in: RoundedRectangle(cornerRadius: 11))
        .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : 158)
    }

    private var dimensions: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(alignment: .top, spacing: 8))
        return VStack(spacing: 7) {
            sectionHeader("dimensions", showUnits: material != nil)
            layout {
                field(.length, title: "field.length", placeholder: "placeholder.length", unit: system.lengthUnit.rawValue)
                field(.width, title: "field.width", placeholder: "placeholder.width", unit: system.lengthUnit.rawValue)
            }
        }
    }

    private func sectionHeader(_ title: String, showUnits: Bool) -> some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 5)) : AnyLayout(HStackLayout(spacing: 5))
        return layout {
            Text(L.t(title)).font(.subheadline.bold())
            if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
            if showUnits { units }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var estimate: some View {
        VStack(alignment: .leading, spacing: 8) {
            dimensions
            if result == nil {
                Label { Text(L.t("shape.note")) } icon: {
                    PlanMark().stroke(Palette.green, lineWidth: 1.4).frame(width: 23, height: 18)
                }.font(.caption.bold()).foregroundStyle(Palette.green)
                Text(L.t("spec.title")).font(.subheadline.bold())
            }
            let layout = result != nil && !typeSize.isAccessibilitySize ? AnyLayout(HStackLayout(alignment: .top, spacing: 8)) : AnyLayout(VStackLayout(spacing: 8))
            layout {
                field(.coverage, title: "coverage." + kind.rawValue, placeholder: "placeholder.spec", unit: coverageUnit)
                field(.waste, title: "field.waste", placeholder: "placeholder.number", unit: "%")
            }
            if result == nil { Text(L.t("waste.hint")).font(.footnote).foregroundStyle(Palette.muted) }
            if kind == .paint {
                let pair = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(alignment: .top, spacing: 8))
                pair {
                    field(.coats, title: "field.coats", placeholder: "placeholder.number", unit: nil)
                    field(.capacity, title: "field.capacity", placeholder: "placeholder.spec", unit: L.volume(volume))
                }
            }
            if result == nil {
                if kind == .paint { Text(L.t("paint.note")).font(.footnote).foregroundStyle(Palette.muted) }
                if kind == .panel { Text(L.t("panel.note")).font(.footnote).foregroundStyle(Palette.muted) }
            }
            if let result { RecordResult(record: result, system: system).id("estimate.result") }
        }
    }

    private var coverageUnit: String {
        kind == .paint ? L.f("coverage.rateUnit", system.areaSymbol, L.volume(volume)) : L.f("coverage.packUnit", system.areaSymbol, L.package(kind))
    }

    private var conversion: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("convert.length", showUnits: true)
            field(.conversion, title: "convert.input", placeholder: "convert.example", unit: system.lengthUnit.rawValue)
            if let length = try? MaterialMath.length(model.draft.conversion, field: .conversion) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L.f("value.unit", L.number(length / 1000, digits: 10), "m")).font(.title2.bold()).accessibilityIdentifier("conversion.metric")
                    Text(L.f("convert.imperial", L.number(length / LengthUnit.ft.factor, digits: 8), L.number(length / LengthUnit.inch.factor, digits: 8)))
                        .font(.body.monospacedDigit()).accessibilityIdentifier("conversion.imperial")
                }.modifier(PanelStyle())
            } else if !model.draft.conversion.text.isEmpty {
                Text(L.t("convert.invalid")).font(.footnote).foregroundStyle(.red)
            }
            dimensions
            if let length = try? MaterialMath.length(model.draft.length, field: .length),
               let width = try? MaterialMath.length(model.draft.width, field: .width) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L.t("result.net")).font(.subheadline.bold())
                    Text(L.area(length * width, system) + "  /  " + L.area(length * width, system == .metric ? .imperial : .metric))
                        .font(.body.monospacedDigit()).accessibilityIdentifier("conversion.area")
                }.modifier(PanelStyle())
            }
        }
    }

    private func display(_ field: Field) -> String {
        let value = model.draft.field(field, material: kind)
        guard !value.text.isEmpty else { return "" }
        switch field {
        case .length, .width, .conversion:
            guard value.system != system, let length = try? MaterialMath.length(value, field: field) else { return value.text }
            return L.number(length / system.lengthUnit.factor, digits: 8)
        case .coverage:
            guard value.system != system || (kind == .paint && value.volume != volume),
                  let amount = MaterialMath.number(value.text) else { return value.text }
            let volumeRatio = kind == .paint ? volume.factor / value.volume.factor : 1
            return L.number(amount * value.system.areaFactor / system.areaFactor * volumeRatio, digits: 8)
        case .capacity:
            guard value.volume != volume, let amount = MaterialMath.number(value.text) else { return value.text }
            return L.number(amount * value.volume.factor / volume.factor, digits: 8)
        default: return value.text
        }
    }

    private func field(_ field: Field, title: String, placeholder: String, unit: String?) -> some View {
        let binding = Binding(get: { display(field) }, set: { value in
            guard value != display(field) else { return }
            model.draft.set(field, material: kind, value: InputValue(text: String(value.prefix(80)), system: system, volume: volume))
            result = nil
            issue = nil
        })
        return VStack(alignment: .leading, spacing: 4) {
            Text(L.t(title)).font(.caption.weight(.semibold)).foregroundStyle(Palette.muted)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                TextField(L.t(placeholder), text: binding)
                    .font(.body.monospacedDigit().weight(.semibold))
                    .keyboardType(field == .conversion || ((field == .length || field == .width) && system == .imperial) ? .numbersAndPunctuation : .decimalPad)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($focused, equals: field)
                    .accessibilityLabel(L.t(title)).accessibilityIdentifier("field." + field.rawValue)
                if let unit = inputUnit(field, fallback: unit) { Text(unit).font(.caption2).foregroundStyle(Palette.muted).fixedSize(horizontal: !typeSize.isAccessibilitySize, vertical: true) }
            }
            if let issue, issue.field == field {
                Text(L.t(issueKey(issue))).font(.caption2).foregroundStyle(.red)
                    .accessibilityIdentifier("error." + field.rawValue)
            }
        }.modifier(PanelStyle()).id(field)
    }

    private func inputUnit(_ field: Field, fallback: String?) -> String? {
        guard field == .length || field == .width || field == .conversion else { return fallback }
        let source = MaterialMath.normalized(display(field))
        if source.range(of: #"[a-z'\"]"#, options: .regularExpression) != nil { return nil }
        return source.contains("/") && system == .imperial ? LengthUnit.inch.rawValue : fallback
    }

    private func issueKey(_ issue: FieldIssue) -> String {
        if issue.reason == .range {
            if issue.field == .length || issue.field == .width { return "limit.length" }
            if issue.field == .waste { return "limit.waste" }
            if issue.field == .coats { return "limit.coats" }
        }
        return "error." + issue.reason.rawValue
    }

    private var footer: some View {
        VStack(spacing: 2) {
            if let result {
                Button {
                    share = SharePayload(record: result, system: system)
                } label: { Label(L.t("action.share"), systemImage: "square.and.arrow.up") }
                    .buttonStyle(PrimaryStyle()).accessibilityIdentifier("result.share")
            } else {
                Button(L.t("action.calculate"), action: calculate)
                    .buttonStyle(PrimaryStyle(muted: missing || !model.ready))
                    .accessibilityIdentifier("home.calculate").disabled(!model.ready || !Launch.freePeriod)
            }
        }
    }

    private func calculate() {
        do {
            let input = model.draft.input(kind)
            let computed = try MaterialMath.calculate(input)
            issue = nil
            focused = nil
            save(input, computed: computed)
        } catch let failure as FieldIssue { issue = failure; focused = failure.field }
        catch { issue = FieldIssue(field: .coverage, reason: .invalid) }
    }

    private func save(_ input: MaterialInput, computed: MaterialResult) {
        let record = Record(input: input, result: computed, source: .local)
        result = record
        Task {
            if await model.save(record) != nil { CoreReview.shared.record() }
        }
    }
}
