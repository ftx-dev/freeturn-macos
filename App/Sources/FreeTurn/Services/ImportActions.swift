import AppKit
import FreeTurnKit
import UniformTypeIdentifiers

/// Импорт серверов: ссылка, буфер обмена, QR с картинки или с экрана.
extension AppModel {
    func offerImport(_ raw: String) {
        importDraft = nil
        do {
            importDraft = try ImportPlanner.draft(for: FreeturnLink.parse(raw), existing: servers.list)
            section = .servers
        } catch ImportError.tcpModeUnsupported {
            importError = L("Этот сервер работает в TCP-режиме для Xray, клиент для macOS его не поддерживает.")
        } catch {
            importError = L("Некорректная ссылка или неподдерживаемая версия приложения.")
        }
    }

    func confirmImport(name: String, callLink: String) {
        guard let draft = importDraft else { return }
        servers.add(ImportPlanner.makeServer(from: draft, name: name, callLink: callLink),
                    activate: !connection.state.isActive)
        persist()
        importDraft = nil
    }

    func importFromPasteboard() {
        if let text = NSPasteboard.general.string(forType: .string), FreeturnLink.looksLikeLink(text) {
            offerImport(text)
        } else if let image = NSImage(pasteboard: .general) {
            importQR(image)
        } else {
            importError = L("В буфере обмена нет ссылки freeturn:// или картинки с QR-кодом.")
        }
    }

    func importQRFromFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK, let url = panel.url, let image = NSImage(contentsOf: url) else { return }
        importQR(image)
    }

    /// Системный выбор области экрана; снимок приходит через буфер обмена.
    func importQRFromScreen() {
        let before = NSPasteboard.general.changeCount
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-i", "-c"]
        capture.terminationHandler = { _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    // Счётчик не изменился - пользователь отменил выбор.
                    guard NSPasteboard.general.changeCount != before,
                          let image = NSImage(pasteboard: .general) else { return }
                    self.importQR(image)
                }
            }
        }
        try? capture.run()
    }

    private func importQR(_ image: NSImage) {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let link = QRDecoder.decode(cg).first(where: FreeturnLink.looksLikeLink) else {
            importError = L("На картинке нет QR-кода со ссылкой freeturn://.")
            return
        }
        offerImport(link)
    }

    func addManualServer() {
        let server = Server(name: L("Новый сервер"))
        servers.add(server, activate: false)
        persist()
        selectedServerId = server.id
    }
}
