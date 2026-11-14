import SwiftUI
import FreeTurnKit

/// Карточка «нужна служба»: показывается вместо ошибки, когда служба не стоит или устарела.
struct DaemonInstallView: View {
    @Environment(AppModel.self) private var model
    let outdated: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(outdated ? L("Служба устарела") : L("Нужна фоновая служба"), systemImage: "lock.shield")
                .font(.headline)
            Text(outdated
                ? L("Установленная служба от другой версии приложения. Её нужно обновить — понадобится пароль администратора.")
                : L("Чтобы поднять системный туннель, FreeTurn один раз ставит небольшую службу. Понадобится пароль администратора."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let error = model.daemonInstallError {
                Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled)
            }
            Button {
                model.installDaemonAndConnect()
            } label: {
                Text(model.installingDaemon ? L("Установка…") : (outdated ? L("Обновить службу") : L("Установить службу")))
                    .frame(minWidth: 160)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.installingDaemon)
        }
        .padding(16)
        .frame(maxWidth: 460, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
    }
}
