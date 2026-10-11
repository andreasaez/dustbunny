import AppKit
import SwiftUI

/// A small click-through panel at the top of the screen where a vacuum trundles across and slurps up dust bunnies.
@MainActor
enum VacuumOverlay {
    private static var panel: NSPanel?

    static func show(count: Int) {
        panel?.orderOut(nil)

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let host = NSHostingView(rootView: VacuumScene(count: count, reduceMotion: reduceMotion))
        let size = host.fittingSize

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .transient]
        panel.contentView = host

        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.maxY - size.height - 14))
        }

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.2; panel.animator().alphaValue = 1 }
        self.panel = panel

        let hold = reduceMotion ? 2.5 : VacuumScene.travelDuration + 1.6
        DispatchQueue.main.asyncAfter(deadline: .now() + hold) {
            guard self.panel === panel else { return }
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.35; panel.animator().alphaValue = 0 }) {
                MainActor.assumeIsolated {
                    panel.orderOut(nil)
                    if self.panel === panel { self.panel = nil }
                }
            }
        }
    }
}

struct VacuumScene: View {
    static let travelDuration = 2.6

    let count: Int
    let reduceMotion: Bool
    @State private var start = Date()

    private let bodyPink = Theme.pink
    private let bagLilac = Theme.lilac
    private let ink = Theme.ink
    private let fluff = Theme.fluff

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let elapsed = reduceMotion ? Self.travelDuration : timeline.date.timeIntervalSince(start)
            VStack(spacing: 6) {
                Canvas { context, size in draw(&context, size: size, t: elapsed) }
                    .frame(height: 84)
                Text(elapsed < Self.travelDuration * 0.75 ? "Sweeping…" : message)
                    .font(.system(.callout, design: .rounded).weight(.semibold))
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.25), value: elapsed < Self.travelDuration * 0.75)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: 340)
        .background(alignment: .topLeading) {
            // A faint wash of the app's colours behind the glass.
            LinearGradient(colors: [Theme.pink.opacity(0.18), Theme.lilac.opacity(0.18)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .glassPanel(cornerRadius: 22)
        .padding(10) // room for the glass edge and shadow
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(message)
    }

    private var message: String {
        switch count {
        case 0: return "Nothing to sweep, already tidy!"
        case 1: return "Swept 1 screenshot"
        default: return "Swept \(count) screenshots"
        }
    }

    // MARK: Drawing

    private func draw(_ context: inout GraphicsContext, size: CGSize, t: Double) {
        let floor = size.height - 8

        var line = Path()
        line.move(to: CGPoint(x: 4, y: floor + 1))
        line.addLine(to: CGPoint(x: size.width - 4, y: floor + 1))
        context.stroke(line, with: .color(.secondary.opacity(0.35)),
                       style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [3, 4]))

        if reduceMotion {
            drawVacuum(&context, nose: size.width / 2 + 23, floor: floor, bob: 0)
            return
        }

        let progress = min(max(t / Self.travelDuration, 0), 1)
        let eased = progress < 0.5 ? 2 * progress * progress : 1 - pow(-2 * progress + 2, 2) / 2
        let startX = -8.0
        let endX = size.width + 64
        let nose = startX + (endX - startX) * eased
        let moving = progress < 1

        // Dust bunnies wait on the floor and get pulled into the nozzle as it arrives.
        let bunnies = min(count, 6)
        for i in 0..<bunnies {
            let homeX = bunnies == 1 ? size.width / 2 : 56 + (size.width - 96) * Double(i) / Double(bunnies - 1)
            let gap = homeX - nose
            if gap < 0 { continue }
            let pull = min(gap / 26, 1)
            let mouth = CGPoint(x: nose - 3, y: floor - 5)
            let position = CGPoint(
                x: mouth.x + (homeX - mouth.x) * pull,
                y: mouth.y + (floor - 7 - mouth.y) * pull - (1 - pull) * 6
            )
            drawBunny(&context, at: position, scale: 0.25 + 0.75 * pull, wobble: t * 7 + Double(i) * 1.3)
        }

        if moving {
            for k in 0..<3 {
                let phase = (t * 5 + Double(k) / 3).truncatingRemainder(dividingBy: 1)
                let x = nose + 18 - phase * 14
                let y = floor - 4 - Double(k) * 4
                var dash = Path()
                dash.move(to: CGPoint(x: x, y: y))
                dash.addLine(to: CGPoint(x: x + 5, y: y - 1))
                context.stroke(dash, with: .color(.secondary.opacity(0.5 * (1 - phase))),
                               style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            }
        }

        drawVacuum(&context, nose: nose, floor: floor, bob: moving ? sin(t * 28) * 0.8 : 0)
    }

    /// Upright vacuum facing right. `nose` is the front edge of the head.
    private func drawVacuum(_ context: inout GraphicsContext, nose n: Double, floor f: Double, bob b: Double) {
        // Handle
        var handle = Path()
        handle.move(to: CGPoint(x: n - 35, y: f - 46 + b))
        handle.addLine(to: CGPoint(x: n - 48, y: f - 70 + b))
        context.stroke(handle, with: .color(ink), style: StrokeStyle(lineWidth: 4, lineCap: .round))
        var grip = Path()
        grip.move(to: CGPoint(x: n - 48, y: f - 70 + b))
        grip.addLine(to: CGPoint(x: n - 57, y: f - 72 + b))
        context.stroke(grip, with: .color(bodyPink), style: StrokeStyle(lineWidth: 6, lineCap: .round))

        // Bag with a little face
        let bag = CGRect(x: n - 45, y: f - 52 + b, width: 21, height: 41)
        context.fill(Path(roundedRect: bag, cornerRadius: 10), with: .color(bagLilac))
        for eyeX in [n - 38, n - 30] {
            context.fill(Path(ellipseIn: CGRect(x: eyeX - 1.6, y: f - 39 + b, width: 3.2, height: 3.2)), with: .color(ink))
        }
        var smile = Path()
        smile.addArc(center: CGPoint(x: n - 34, y: f - 34 + b), radius: 3,
                     startAngle: .degrees(20), endAngle: .degrees(160), clockwise: false)
        context.stroke(smile, with: .color(ink), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
        context.fill(Path(ellipseIn: CGRect(x: n - 28.5, y: f - 35 + b, width: 4, height: 2.4)), with: .color(bodyPink.opacity(0.7)))

        // Head, brush and wheel
        context.fill(Path(roundedRect: CGRect(x: n - 48, y: f - 15 + b, width: 48, height: 11), cornerRadius: 5),
                     with: .color(bodyPink))
        context.fill(Path(CGRect(x: n - 42, y: f - 4, width: 39, height: 3)), with: .color(ink.opacity(0.8)))
        context.fill(Path(ellipseIn: CGRect(x: n - 49, y: f - 9, width: 9, height: 9)), with: .color(ink))
        context.fill(Path(ellipseIn: CGRect(x: n - 46, y: f - 6, width: 3, height: 3)), with: .color(.white.opacity(0.8)))
    }

    private func drawBunny(_ context: inout GraphicsContext, at c: CGPoint, scale s: Double, wobble w: Double) {
        let r = 8 * s
        var fuzz = Path()
        for k in 0..<7 {
            let angle = Double(k) / 7 * 2 * .pi + sin(w) * 0.15
            let puff = r * 0.55
            fuzz.addEllipse(in: CGRect(x: c.x + cos(angle) * r * 0.5 - puff, y: c.y + sin(angle) * r * 0.35 - puff,
                                       width: puff * 2, height: puff * 2))
        }
        fuzz.addEllipse(in: CGRect(x: c.x - r * 0.75, y: c.y - r * 0.6, width: r * 1.5, height: r * 1.2))
        fuzz.addEllipse(in: CGRect(x: c.x - r * 0.6, y: c.y - r * 1.5, width: r * 0.4, height: r * 0.95))
        fuzz.addEllipse(in: CGRect(x: c.x + r * 0.15, y: c.y - r * 1.55 + sin(w) * 0.6, width: r * 0.4, height: r * 0.95))
        context.fill(fuzz, with: .color(fluff))

        for eyeX in [c.x - r * 0.3, c.x + r * 0.3] {
            let eye = r * 0.13
            context.fill(Path(ellipseIn: CGRect(x: eyeX - eye, y: c.y - r * 0.2 - eye, width: eye * 2, height: eye * 2)),
                         with: .color(ink))
        }
    }
}
