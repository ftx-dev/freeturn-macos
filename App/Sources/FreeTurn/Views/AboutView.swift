import SwiftUI
import FreeTurnKit

/// О проекте: логотип, версия, ссылки на Telegram-канал и исходный код.
struct AboutView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Image(nsImage: AppIcons.image(model.settings.appIcon))
                    .resizable()
                    .frame(width: 128, height: 128)
                    .padding(.top, 32)
                Text("FreeTurnX").font(.largeTitle.weight(.semibold))
                Text(String(format: L("Версия %@"), model.updater.currentVersion) + " · " + UpdateCheck.currentArch)
                    .foregroundStyle(.secondary)
                Text(L("FreeTurnX проксирует WireGuard и AmneziaWG через TURN-реле звонков или напрямую. Открытый исходный код и никакой телеметрии: все настройки хранятся только на этом компьютере."))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
                    .padding(.vertical, 8)
                Link(destination: AppModel.telegramURL) {
                    Label(L("Telegram-канал"), systemImage: "paperplane.fill").frame(minWidth: 200)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                Link(L("Исходный код на GitHub"), destination: URL(string: "https://github.com/\(UpdateCheck.repository)")!)
                Text(L("Ядро — free-turn-proxy, туннель — Amnezia Box."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 12)
            }
            .frame(maxWidth: .infinity)
            .padding(24)
        }
    }
}

/// Три варианта иконки. В Dock меняется сразу; значок FreeTurn.app в Finder остаётся стандартным -
/// правка значка внутри бандла сломала бы его подпись.
enum AppIcons {
    static let variants: [(id: String, title: String)] = [("standard", "Стандартная"), ("black", "Black"), ("x", "X")]

    @MainActor static func image(_ variant: String) -> NSImage {
        let name = variants.contains { $0.id == variant } ? variant : "standard"
        if let url = L10n.resources.url(forResource: "icon-\(name)", withExtension: "png"), let image = NSImage(contentsOf: url) {
            return image
        }
        return NSImage(named: NSImage.applicationIconName) ?? NSImage()
    }

    @MainActor static func apply(_ variant: String) {
        // nil - вернуть значок из бандла.
        NSApp.applicationIconImage = variant == "standard" ? nil : image(variant)
    }
}
