import AppKit
import SwiftUI

/// Dustbunny's palette, shared by the settings window, the vacuum animation and the app icon.
enum Theme {
    static let pink = Color(red: 0.95, green: 0.52, blue: 0.66)
    static let lilac = Color(red: 0.73, green: 0.67, blue: 0.96)
    static let ink = Color(white: 0.22)
    static let fluff = Color(white: 0.62)
}

extension View {
    /// Frosted glass panel: Liquid Glass on macOS 26 and later, a translucent material with a light edge before that.
    @ViewBuilder
    func glassPanel(cornerRadius: CGFloat, tint: Color? = nil) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            glassEffect(tint.map { Glass.regular.tint($0) } ?? .regular, in: shape)
        } else {
            background((tint ?? .clear).opacity(0.12), in: shape)
                .background(.ultraThinMaterial, in: shape)
                .overlay(
                    shape.strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.08)], startPoint: .top, endPoint: .bottom),
                        lineWidth: 1
                    )
                )
        }
    }

    @ViewBuilder
    func glassButtonStyle(prominent: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            if prominent { buttonStyle(.glassProminent) } else { buttonStyle(.glass) }
        } else {
            if prominent { buttonStyle(.borderedProminent) } else { buttonStyle(.bordered) }
        }
    }
}

/// Window background: the desktop blurred through the window, with two soft blobs of the app's colours.
struct GlassBackdrop: View {
    var body: some View {
        ZStack {
            VisualEffectBackground()
            Circle()
                .fill(Theme.pink.opacity(0.35))
                .frame(width: 280, height: 280)
                .blur(radius: 80)
                .offset(x: -160, y: -230)
            Circle()
                .fill(Theme.lilac.opacity(0.45))
                .frame(width: 320, height: 320)
                .blur(radius: 90)
                .offset(x: 170, y: 240)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
