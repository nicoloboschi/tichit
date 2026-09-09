import AppKit
import SwiftUI

struct SettingsView: View {
    @State private var apiKey = Keychain.read() ?? ""
    @State private var saved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Gemini API key")
                .font(.headline)
            Text("Stored in your macOS Keychain. Get one at aistudio.google.com/apikey.")
                .font(.caption)
                .foregroundStyle(.secondary)
            SecureField("AIza…", text: $apiKey)
                .textFieldStyle(.roundedBorder)
            HStack {
                if saved {
                    Text("Saved")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Save") {
                    Keychain.write(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
                    saved = true
                }
                .keyboardShortcut(.return)
            }
            Divider()
            Text("History: \(History.fileURL.path)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(18)
        .frame(width: 400)
    }
}

@MainActor
enum SettingsWindow {
    private static var window: NSWindow?

    static func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 220),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            w.title = "Tich Settings"
            w.contentView = NSHostingView(rootView: SettingsView())
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
