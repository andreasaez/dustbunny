import AppKit
import SwiftUI

@main
struct DustbunnyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra("Dustbunny", systemImage: "hare") {
            MenuContent(model: model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        refuseExternalRequests()
        MainActor.assumeIsolated {
            AppModel.shared.start()
        }
    }

    /// Dustbunny takes no input from other apps. Point the standard "open these files / this URL / print"
    /// Apple Events at a handler that refuses them, so they never reach AppKit or SwiftUI. SwiftUI installs its
    /// own URL handler during launch, so this runs again once launch has settled to make sure ours wins.
    private func refuseExternalRequests() {
        let refused: [(AEEventClass, AEEventID)] = [
            (AEEventClass(kCoreEventClass), AEEventID(kAEOpenDocuments)),
            (AEEventClass(kCoreEventClass), AEEventID(kAEPrintDocuments)),
            (AEEventClass(kCoreEventClass), AEEventID(kAEOpenContents)),
            (AEEventClass(kInternetEventClass), AEEventID(kAEGetURL)),
        ]
        let install = {
            for (eventClass, eventID) in refused {
                NSAppleEventManager.shared().setEventHandler(
                    self, andSelector: #selector(self.refuse(_:withReplyEvent:)),
                    forEventClass: eventClass, andEventID: eventID
                )
            }
        }
        install()
        DispatchQueue.main.async(execute: install)
    }

    @objc private func refuse(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        reply.setParam(NSAppleEventDescriptor(int32: Int32(errAEEventNotHandled)), forKeyword: keyErrorNumber)
    }

    // Belt and braces: if a file or URL open request ever gets through, ignore it.
    func application(_ application: NSApplication, open urls: [URL]) {}
}

struct MenuContent: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Button(model.isRunning ? "Sweeping…" : "Run Dustbunny Now") { model.runNow() }
            .keyboardShortcut("r")
            .disabled(model.folderURL == nil || model.isRunning)
        Button("Undo Last Sweep") { model.undoLastSweep() }
            .disabled(!model.canUndo || model.isRunning)

        Divider()

        if model.folderURL == nil {
            Text("Choose a folder in Settings to get started")
        } else {
            Text(model.statusLine)
            Text(model.scheduleLine)
        }

        Divider()

        Button("Settings…") { SettingsWindow.show(model) }
            .keyboardShortcut(",")
        Button("Quit Dustbunny") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
