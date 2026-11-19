import SwiftUI
import UIKit
import LinkPresentation

struct SharePayload: Identifiable {
    let id = UUID()
    let record: Record?
    let system: UnitSystem
    let count: Int?

    init(record: Record, system: UnitSystem) {
        self.record = record
        self.system = system
        count = nil
    }

    init(count: Int) {
        record = nil
        system = .metric
        self.count = count
    }

    var title: String {
        if let record { return L.f("share.material", L.material(record.input.material)) }
        return L.t("milestone.share")
    }

    var tags: String {
        if let record { return L.t("share.tag") + "  " + L.t("tag." + record.input.material.rawValue) }
        return L.t("share.tag")
    }

    var caption: String {
        guard let record else { return L.f("milestone.card", String(count ?? 0)) + "\n" + tags }
        let result = record.result
        let dimension = L.f("share.dimensions", L.number(result.lengthMM / system.lengthUnit.factor, digits: 8, minimum: 2),
                            L.number(result.widthMM / system.lengthUnit.factor, digits: 8, minimum: 2), system.lengthUnit.rawValue)
        let estimate = L.f("share.caption", dimension, L.area(result.net, system), L.area(result.packageCoverage, system),
                           L.number(result.waste, digits: 12), L.quantity(record))
        let note = record.input.material == .panel ? "\n" + L.t("panel.note") : ""
        let paint = record.input.material == .paint ? "\n" + L.f("share.coats", String(result.coats)) : ""
        return estimate + paint + "\n" + L.t("result.verify") + note + "\n" + tags
    }
}

private struct ShareCard: View {
    let payload: SharePayload

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(payload.title).font(.system(size: 16, weight: .bold))
                if let record = payload.record {
                    Text(L.f("share.recommend", L.quantity(record))).font(.system(size: 39, weight: .heavy, design: .monospaced))
                    Text(L.t("result.verify")).font(.system(size: 14))
                } else {
                    Text(L.f("milestone.card", String(payload.count ?? 0))).font(.system(size: 31, weight: .heavy))
                }
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(Palette.white).background(Palette.dark)
            if let record = payload.record {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(RecordResult(record: record, system: payload.system).steps, id: \.label) { step in
                        Text(step.label).font(.system(size: 13)).foregroundStyle(Palette.muted)
                        Text(step.value).font(.system(size: 15, weight: .semibold, design: .monospaced))
                        Divider()
                    }
                    if record.input.material == .panel { Text(L.t("panel.note")).font(.system(size: 13)) }
                }.padding(.horizontal, 20).padding(.vertical, 12)
            }
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L.t("app.name")).font(.system(size: 15, weight: .bold))
                    Text(payload.tags).font(.system(size: 13))
                }
                Spacer(minLength: 2)
                Text(L.t("share.qrPlaceholder")).font(.system(size: 10, weight: .semibold))
                    .multilineTextAlignment(.center).padding(5).frame(width: 64, height: 58)
                    .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.green, style: StrokeStyle(dash: [3, 3])) }
            }.padding(16).foregroundStyle(Palette.green)
        }
        .foregroundStyle(Palette.ink).background(Palette.white).frame(width: 400)
        .environment(\.colorScheme, .light).environment(\.dynamicTypeSize, .medium)
    }
}

struct ShareCardPreview: View {
    @Environment(\.dismiss) private var dismiss
    let payload: SharePayload

    var body: some View {
        ScrollView {
            Button(L.t("action.done")) { dismiss() }.accessibilityIdentifier("share.previewDone")
            if let image = makeImage() {
                Image(uiImage: image).resizable().scaledToFit().accessibilityLabel(payload.caption)
                    .accessibilityIdentifier("share.previewCard")
            }
        }.padding(18).background(Palette.tint.ignoresSafeArea())
    }

    @MainActor private func makeImage() -> UIImage? {
        let renderer = ImageRenderer(content: ShareCard(payload: payload))
        renderer.scale = 3
        return renderer.uiImage
    }
}

@MainActor
struct SharePresentation: UIViewControllerRepresentable {
    let payload: SharePayload

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let renderer = ImageRenderer(content: ShareCard(payload: payload))
        renderer.scale = 3
        let items: [Any]
        if let image = renderer.uiImage { items = [CardActivityItem(image: image, title: payload.title)] }
        else { items = [payload.caption] }
        var actions: [UIActivity] = [CopyActivity(title: L.t("share.copyCaption"), icon: "doc.on.doc", key: "caption", text: payload.caption)]
        if let record = payload.record, let code = try? ShareCode.encode(record) {
            actions.append(CopyActivity(title: L.t("share.copyCode"), icon: "number", key: "code", text: code))
        }
        let controller = UIActivityViewController(activityItems: items, applicationActivities: actions)
        controller.view.accessibilityIdentifier = "share.system"
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private final class CardActivityItem: NSObject, UIActivityItemSource {
    let image: UIImage
    let title: String
    init(image: UIImage, title: String) { self.image = image; self.title = title }
    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any { image }
    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? { image }
    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.title = title
        metadata.imageProvider = NSItemProvider(object: image)
        return metadata
    }
}

private final class CopyActivity: UIActivity {
    let title: String
    let icon: String
    let key: String
    let text: String
    init(title: String, icon: String, key: String, text: String) {
        self.title = title
        self.icon = icon
        self.key = key
        self.text = text
        super.init()
    }
    override var activityTitle: String? { title }
    override var activityType: UIActivity.ActivityType? { UIActivity.ActivityType("com.hgsldswk.buildcalc.copy." + key) }
    override var activityImage: UIImage? { UIImage(systemName: icon) }
    override class var activityCategory: UIActivity.Category { .action }
    override func canPerform(withActivityItems activityItems: [Any]) -> Bool { true }
    override func perform() {
        UIPasteboard.general.string = text
        activityDidFinish(true)
    }
}
