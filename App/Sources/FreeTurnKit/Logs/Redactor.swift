import Foundation

/// Прячет секреты в строках лога: ссылки на звонок и ключи - всегда, адреса - по флагу.
public enum Redactor {
    private static func regex(_ pattern: String) -> NSRegularExpression { try! NSRegularExpression(pattern: pattern) }

    private static let callLink = regex(#"https?://\S*/call/\S*"#)
    /// Ключ обфускации (64 hex) и Client ID (32 hex).
    private static let hexKey = regex(#"\b[0-9a-fA-F]{32,}\b"#)
    private static let ipv6Bracketed = regex(#"\[[0-9a-fA-F:]{3,39}\]:\d{1,5}"#)
    /// С «::» или полные 8 групп. Три группы (время 12:34:56) сюда не попадают.
    private static let ipv6 = regex(#"\b[0-9a-fA-F]{1,4}(?::[0-9a-fA-F]{1,4})*::(?:[0-9a-fA-F]{1,4}(?::[0-9a-fA-F]{1,4})*)?|\b[0-9a-fA-F]{1,4}(?::[0-9a-fA-F]{1,4}){7}\b"#)
    private static let ipv4Port = regex(#"\b(?:\d{1,3}\.){3}\d{1,3}:\d{1,5}\b"#)
    private static let ipv4 = regex(#"\b(?:\d{1,3}\.){3}\d{1,3}\b"#)

    public static func redact(_ text: String, secrets: [String], maskAddresses: Bool = true) -> String {
        var out = text
        // Короткие «секреты» (пустые поля) заменили бы полстроки.
        for secret in secrets where secret.count >= 4 {
            out = out.replacingOccurrences(of: secret, with: "•••")
        }
        out = replace(callLink, in: out, with: "•••")
        out = replace(hexKey, in: out, with: "•••")
        guard maskAddresses else { return out }
        out = replace(ipv6Bracketed, in: out, with: "[x:x]:•")
        out = replace(ipv6, in: out, with: "x:x")
        out = replace(ipv4Port, in: out, with: "x.x.x.x:•")
        out = replace(ipv4, in: out, with: "x.x.x.x")
        return out
    }

    private static func replace(_ re: NSRegularExpression, in text: String, with template: String) -> String {
        re.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text),
                                    withTemplate: NSRegularExpression.escapedTemplate(for: template))
    }
}
