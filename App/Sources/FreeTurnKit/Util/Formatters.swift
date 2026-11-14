import Foundation

public enum Formatters {
    public enum UnitStyle: Sendable {
        case ru, en

        var units: [String] { self == .ru ? ["Б", "КБ", "МБ", "ГБ", "ТБ"] : ["B", "KB", "MB", "GB", "TB"] }
        var separator: String { self == .ru ? "," : "." }
        var perSecond: String { self == .ru ? "/с" : "/s" }
    }

    public static func bytes(_ count: Int64, style: UnitStyle = .ru) -> String {
        var value = Double(max(count, 0))
        var unit = 0
        while value >= 1024, unit < style.units.count - 1 {
            value /= 1024
            unit += 1
        }
        // Байты и трёхзначные значения - без дробной части: «250 МБ», но «1,5 КБ».
        let text = unit == 0 || value >= 100
            ? String(Int(value.rounded()))
            : String(format: "%.1f", value).replacingOccurrences(of: ".", with: style.separator)
        return "\(text) \(style.units[unit])"
    }

    public static func rate(_ bytesPerSecond: Int64, style: UnitStyle = .ru) -> String {
        bytes(bytesPerSecond, style: style) + style.perSecond
    }

    public static func duration(_ interval: TimeInterval) -> String {
        let total = Int(max(interval, 0))
        let (h, m, s) = (total / 3600, total % 3600 / 60, total % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}
