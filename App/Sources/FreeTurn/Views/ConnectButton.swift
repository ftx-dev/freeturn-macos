import SwiftUI

/// Большая кнопка подключения.
struct ConnectButton: View {
    enum Kind { case off, busy, on, attention, error }

    let kind: Kind
    let action: () -> Void
    @State private var spinning = false
    @State private var hovering = false

    private var colors: [Color] {
        switch kind {
        case .off: [Color(white: 0.42), Color(white: 0.28)]
        case .busy: [Color(red: 0.25, green: 0.52, blue: 0.96), Color(red: 0.18, green: 0.32, blue: 0.78)]
        case .on: [Color(red: 0.16, green: 0.78, blue: 0.52), Color(red: 0.05, green: 0.55, blue: 0.45)]
        case .attention: [Color(red: 0.98, green: 0.66, blue: 0.18), Color(red: 0.90, green: 0.45, blue: 0.10)]
        case .error: [Color(red: 0.93, green: 0.33, blue: 0.31), Color(red: 0.72, green: 0.18, blue: 0.22)]
        }
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(colors[0].opacity(kind == .off ? 0 : 0.22))
                    .frame(width: 208, height: 208)
                    .blur(radius: 18)
                Circle()
                    .fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
                    .overlay(Circle().strokeBorder(.white.opacity(0.22), lineWidth: 1))
                    .shadow(color: colors[1].opacity(0.45), radius: hovering ? 22 : 14, y: 8)
                if kind == .busy {
                    Circle()
                        .trim(from: 0, to: 0.28)
                        .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .padding(9)
                        .rotationEffect(.degrees(spinning ? 360 : 0))
                        .animation(.linear(duration: 1.1).repeatForever(autoreverses: false), value: spinning)
                        .onAppear { spinning = true }
                        .onDisappear { spinning = false }
                }
                Image(systemName: "power")
                    .font(.system(size: 58, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 164, height: 164)
            .scaleEffect(hovering ? 1.03 : 1)
            .animation(.spring(duration: 0.3), value: hovering)
            .animation(.easeInOut(duration: 0.35), value: kind)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .frame(width: 208, height: 208)
    }
}
