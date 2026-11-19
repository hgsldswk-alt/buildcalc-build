import SwiftUI

enum L {
    static func t(_ key: String) -> String { NSLocalizedString(key, comment: "") }
    static func f(_ key: String, _ args: String...) -> String {
        String(format: t(key), locale: Locale.current, arguments: args)
    }
    static func number(_ value: Decimal, digits: Int = 2, minimum: Int = 0) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale.current
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.maximumFractionDigits = digits
        formatter.minimumFractionDigits = minimum
        let number = NSDecimalNumber(decimal: value)
        let rendered = formatter.string(from: number)
        if value > 0, rendered == formatter.string(from: NSNumber(value: 0)) {
            formatter.maximumFractionDigits = max(digits, 22)
            return formatter.string(from: number) ?? number.stringValue
        }
        return rendered ?? number.stringValue
    }
    static func material(_ material: Material) -> String { t("mode." + material.rawValue) }
    static func package(_ material: Material) -> String { t("package." + material.rawValue) }
    static func quantity(_ record: Record) -> String {
        let count = record.result.quantity
        if count == 1 { return f("value.unit", String(count), package(record.input.material)) }
        return f("quantity." + record.input.material.rawValue, String(count))
    }
    static func volume(_ unit: VolumeUnit) -> String { t("volume." + unit.rawValue) }
    static func area(_ value: Decimal, _ system: UnitSystem) -> String {
        f("value.unit", number(value / system.areaFactor, digits: 2, minimum: 2), system.areaSymbol)
    }
}

enum Palette {
    static let paper = Color(red: 0.97, green: 0.97, blue: 0.94)
    static let white = Color(red: 1, green: 1, blue: 0.98)
    static let ink = Color(red: 0.10, green: 0.16, blue: 0.13)
    static let muted = Color(red: 0.28, green: 0.37, blue: 0.32)
    static let line = Color(red: 0.82, green: 0.87, blue: 0.82)
    static let tint = Color(red: 0.89, green: 0.93, blue: 0.89)
    static let green = Color(red: 0.15, green: 0.33, blue: 0.24)
    static let dark = Color(red: 0.10, green: 0.24, blue: 0.18)
}

struct PanelStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(11).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.white, in: RoundedRectangle(cornerRadius: 13))
            .overlay { RoundedRectangle(cornerRadius: 13).strokeBorder(Palette.line) }
    }
}

struct PrimaryStyle: ButtonStyle {
    var muted = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 49)
            .padding(.horizontal, 8)
            .foregroundStyle(muted ? Palette.green : Palette.white)
            .background(muted ? Palette.tint : Palette.green, in: RoundedRectangle(cornerRadius: 13))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

struct PlanMark: Shape {
    func path(in rect: CGRect) -> Path {
        let scaleX = rect.width / 68, scaleY = rect.height / 53
        var path = Path()
        let strokes: [[CGPoint]] = [
            [.init(x: 9, y: 2), .init(x: 9, y: 9)], [.init(x: 58, y: 2), .init(x: 58, y: 9)],
            [.init(x: 9, y: 5), .init(x: 58, y: 5)], [.init(x: 4, y: 12), .init(x: 4, y: 45)],
            [.init(x: 9, y: 12), .init(x: 58, y: 12), .init(x: 58, y: 45), .init(x: 9, y: 45), .init(x: 9, y: 12)],
            [.init(x: 9, y: 23), .init(x: 58, y: 23)], [.init(x: 9, y: 34), .init(x: 58, y: 34)],
            [.init(x: 25, y: 12), .init(x: 25, y: 23)], [.init(x: 40, y: 23), .init(x: 40, y: 34)],
            [.init(x: 25, y: 34), .init(x: 25, y: 45)]
        ]
        for stroke in strokes {
            guard let first = stroke.first else { continue }
            path.move(to: CGPoint(x: first.x * scaleX, y: first.y * scaleY))
            for point in stroke.dropFirst() { path.addLine(to: CGPoint(x: point.x * scaleX, y: point.y * scaleY)) }
        }
        return path
    }
}
