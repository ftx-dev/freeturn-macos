import CoreImage.CIFilterBuiltins
import SwiftUI
import FreeTurnKit

/// «Поделиться»: ссылка freeturn:// и QR-код на этот сервер - для своего второго устройства
/// или чтобы передать доступ (как экран «Поделиться» Android-клиента, без выпуска нового пользователя).
struct ShareSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let server: Server
    @State private var options = ShareOptions()
    @State private var copied = false

    private var link: String {
        ShareLinkBuilder.build(server: server, ownClientId: (try? model.store.ownClientId()) ?? "", options: options)
    }

    var body: some View {
        let link = link
        VStack(alignment: .leading, spacing: 14) {
            Text(String(format: L("Доступ к «%@»"), server.name)).font(.title2.weight(.semibold))
            HStack(alignment: .top, spacing: 18) {
                Image(nsImage: Self.qr(link))
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 204, height: 204)
                    // Белое поле вокруг кода: скругление не задевает угловые квадраты, а сканер видит границу.
                    .padding(12)
                    .background(.white, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel(L("QR-код с ссылкой на доступ"))
                Form {
                    TextField(L("Имя у получателя"), text: $options.name, prompt: Text(server.name))
                    Toggle(isOn: $options.includeCallLink) {
                        Text(L("Вложить ссылку на звонок"))
                        Text(L("Получателю не нужна своя ссылка на звонок"))
                    }
                    .disabled(server.client.provider != Provider.relay || server.client.callLink.isEmpty)
                    Toggle(isOn: $options.includeWireGuard) {
                        Text(L("Вложить конфиг WireGuard"))
                        Text(L("Для своего второго устройства"))
                    }
                    .disabled(!server.client.wireGuardActive)
                }
                .formStyle(.columns)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(L("Ссылка равносильна ключам: передавайте её только тем, кому доверяете. Отдельный доступ для другого человека выпускается на сервере — это появится вместе с управлением сервером."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(copied ? L("Скопировано") : L("Копировать ссылку"), systemImage: copied ? "checkmark" : "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(link, forType: .string)
                    copied = true
                }
                ShareLink(item: link) { Label(L("Поделиться…"), systemImage: "square.and.arrow.up") }
                Button(L("Сохранить QR…"), systemImage: "qrcode") { saveQR(link) }
                Spacer()
                Button(L("Готово")) { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        // Ширина - у содержимого, поля - снаружи: иначе широкая форма прижимала QR к краю окна.
        .frame(width: 620)
        .padding(24)
        .onAppear { options.includeWireGuard = server.client.wireGuardActive }
        .onChange(of: options) { copied = false }
    }

    static func qr(_ text: String) -> NSImage {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)) else { return NSImage() }
        let rep = NSCIImageRep(ciImage: output)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }

    private func saveQR(_ link: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "\(server.name)-freeturn.png"
        guard panel.runModal() == .OK, let url = panel.url,
              let tiff = Self.qr(link).tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { return }
        try? png.write(to: url)
    }
}
