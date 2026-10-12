import AppKit
import SwiftUI

@MainActor
enum SettingsWindow {
    private static var window: NSWindow?

    static func show(_ model: AppModel) {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model)))
            window.title = "Dustbunny"
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isOpaque = false
            window.backgroundColor = .clear
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 14) {
            header

            Button { model.runNow() } label: {
                Label(model.isRunning ? "Sweeping…" : "Run Dustbunny Now", systemImage: "sparkles")
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 3)
            }
            .controlSize(.large)
            .glassButtonStyle(prominent: true)
            .tint(Theme.pink)
            .disabled(model.folderURL == nil || model.isRunning)

            GlassCard(title: "Folder to tidy", systemImage: "folder") {
                HStack(spacing: 10) {
                    if let folder = model.folderURL {
                        Text(folder.path(percentEncoded: false))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(folder.path(percentEncoded: false))
                    } else {
                        Text("No folder chosen yet")
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Button(model.folderURL == nil ? "Choose…" : "Change…") { model.chooseFolder() }
                        .glassButtonStyle()
                }
                Text("Screenshots move into a “Screenshots” folder inside it, one subfolder per day.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            GlassCard(title: "Schedule", systemImage: "moon.stars") {
                Toggle("Sweep every evening", isOn: $model.scheduleEnabled)
                HStack {
                    Text("Time")
                    Spacer()
                    DatePicker("Time", selection: $model.scheduleTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
                .disabled(!model.scheduleEnabled)
                .opacity(model.scheduleEnabled ? 1 : 0.5)
                Toggle("Open Dustbunny at login", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
                Toggle("Show the vacuum animation", isOn: $model.showAnimation)
            }
            .toggleStyle(.switch)
            .tint(Theme.pink)

            HStack {
                Button { model.undoLastSweep() } label: {
                    Label("Undo Last Sweep", systemImage: "arrow.uturn.backward")
                }
                .controlSize(.small)
                .glassButtonStyle()
                .disabled(!model.canUndo || model.isRunning)
                .help(model.canUndo ? "Put every file from the last sweep back where it was." : "Nothing to undo yet.")
                Spacer()
            }

            if let error = model.errorMessage {
                GlassCard(title: "Something needs attention", systemImage: "exclamationmark.triangle", tint: .orange) {
                    Text(error)
                        .font(.callout)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Dismiss") { model.errorMessage = nil }
                        .glassButtonStyle()
                }
            }

            Label {
                Text("Dustbunny only reads file names. It never opens files, can't connect to the internet, and touches nothing outside the folder you choose. Files are moved, never deleted, and the last sweep can be undone.")
            } icon: {
                Image(systemName: "lock.shield")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
        }
        .padding(.horizontal, 20)
        .padding(.top, 34) // room for the window's close button
        .padding(.bottom, 20)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .background(GlassBackdrop())
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 60, height: 60)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Dustbunny")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text(model.folderURL == nil ? "Choose a folder to get started" : model.statusLine)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if model.folderURL != nil {
                    Text(model.scheduleLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }
}

struct GlassCard<Content: View>: View {
    let title: String
    let systemImage: String
    var tint: Color? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(.secondary)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(cornerRadius: 18, tint: tint?.opacity(0.15))
    }
}
