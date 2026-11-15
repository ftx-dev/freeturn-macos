import Foundation

public enum PingMeter {
    /// Задержка HTTP-запроса через туннель, мс; nil - нет ответа.
    public static func measure(timeout: TimeInterval = 3) async -> Int? {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        var request = URLRequest(url: URL(string: "https://www.gstatic.com/generate_204")!)
        request.httpMethod = "HEAD"
        let started = Date()
        guard let (_, response) = try? await URLSession(configuration: config).data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 204 else { return nil }
        return Int(Date().timeIntervalSince(started) * 1000)
    }
}
