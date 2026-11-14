import Foundation

/// Разбор ручного DNS-списка - те же правила, что у Android DnsList.
public enum DnsList {
    private static let allowed = CharacterSet(charactersIn:
        "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ.:_-")

    static func tokens(_ raw: String) -> [String] {
        raw.split(whereSeparator: { ",; \n\t".contains($0) }).map(String.init)
    }

    private static func isValid(_ token: String) -> Bool {
        token.unicodeScalars.allSatisfy(allowed.contains)
    }

    /// Строка валидных токенов через запятую; пусто - список не задан.
    public static func normalize(_ raw: String) -> String {
        tokens(raw).filter(isValid).joined(separator: ",")
    }

    public static func hasInvalidTokens(_ raw: String) -> Bool {
        tokens(raw).contains { !isValid($0) }
    }
}
