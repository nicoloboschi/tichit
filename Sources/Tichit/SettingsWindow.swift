import AppKit
import SwiftUI

struct SettingsView: View {
    @State private var apiKey = Keychain.read() ?? ""
    @State private var saved = false
    @State private var provider = Provider.current

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rewrites come from")
                .font(.headline)
            Picker("", selection: $provider) {
                ForEach(Provider.allCases) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.radioGroup)
            .onChange(of: provider) { _, new in Provider.current = new }

            Text(providerStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

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
        .frame(width: 440)
    }

    private var providerStatus: String {
        switch Provider.resolved {
        case .codex where CodexAuth.isSignedIn:
            return "Using your Codex subscription login from ~/.codex/auth.json — no API key needed."
        case .codex:
            return "Not signed in to Codex. Run `codex login` in a terminal."
        default:
            return "Using the Gemini API with the key below."
        }
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
            w.title = "Tichit Settings"
            w.contentView = NSHostingView(rootView: SettingsView())
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
