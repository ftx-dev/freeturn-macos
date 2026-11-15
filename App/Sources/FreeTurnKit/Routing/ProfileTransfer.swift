import Foundation

public enum ProfileTransferError: Error, Equatable {
    case wrongFormat, unsupportedVersion
}

/// Обмен профилями маршрутов через файл.
public enum ProfileTransfer {
    static let format = "freeturn-routing"
    static let version = 1

    private struct Envelope: Codable {
        var format: String
        var version: Int
        var profile: RoutingProfile
    }

    public static func export(_ profile: RoutingProfile) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(Envelope(format: format, version: version, profile: profile))
    }

    public static func importProfile(_ data: Data) throws -> RoutingProfile {
        // Версию смотрим до разбора профиля: у новой версии он может не разобраться вовсе.
        guard let header = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              header["format"] as? String == format, let fileVersion = header["version"] as? Int
        else { throw ProfileTransferError.wrongFormat }
        guard fileVersion <= version else { throw ProfileTransferError.unsupportedVersion }
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else {
            throw ProfileTransferError.wrongFormat
        }
        // Чужой файл не должен подменить встроенный профиль или совпасть по id с имеющимся.
        return envelope.profile.editableCopy(name: envelope.profile.name)
    }
}
