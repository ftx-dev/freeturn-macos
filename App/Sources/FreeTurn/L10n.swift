import Foundation
import FreeTurnKit

/// Ключ строки - русский текст. Английский перевод лежит в en.lproj; русского файла
/// переводов нет: при его отсутствии возвращается сам ключ.
@MainActor enum L10n {
    /// Ресурсы SwiftPM. В .app лежат в Contents/Resources, при `swift run` - рядом с бинарником.
    static let resources: Bundle = {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("FreeTurn_FreeTurn.bundle"),
           let bundle = Bundle(url: url) { return bundle }
        return Bundle.module
    }()

    /// "system" | "ru" | "en" - из настроек; меняется после перезапуска.
    static var language = "system"

    static var isEnglish: Bool {
        switch language {
        case "en": true
        case "ru": false
        default: !(Locale.preferredLanguages.first ?? "ru").hasPrefix("ru")
        }
    }

    private static let english: Bundle? = resources.path(forResource: "en", ofType: "lproj").flatMap(Bundle.init(path:))

    static func text(_ key: String) -> String {
        guard isEnglish, let english else { return key }
        return english.localizedString(forKey: key, value: key, table: nil)
    }

    static var unitStyle: Formatters.UnitStyle { isEnglish ? .en : .ru }
}

@MainActor func L(_ key: String) -> String { L10n.text(key) }
