import AppKit
import SwiftUI

enum Tab: String, CaseIterable, Identifiable {
    case direct = "Improve"
    case captured = "Captured"
    case history = "History"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .direct: return "square.and.pencil"
        case .captured: return "waveform.badge.magnifyingglass"
        case .history: return "clock.arrow.circlepath"
        }
    }
}

/// Which tab the popover shows. Shared so a notification can open the right one.
@MainActor
final class Tabs: ObservableObject {
    static let shared = Tabs()
    @Published var selected: Tab = .direct
    private init() {}
}

struct RootView: View {
    @ObservedObject var composer: Composer
    @ObservedObject private var tabs = Tabs.shared
    @ObservedObject private var queue = ReviewQueue.shared
    @ObservedObject private var capture = KeystrokeCapture.shared

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            switch tabs.selected {
            case .direct:
                ComposerView(composer: composer)
            case .captured:
                CapturedView()
            case .history:
                HistoryView()
                    .frame(height: 520)
            }
        }
        .frame(width: 680)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Picker("", selection: $tabs.selected) {
                ForEach(Tab.allCases) { tab in
                    Label(tab.rawValue, systemImage: tab.icon).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if queue.pending > 0 {
                ProgressView()
                    .controlSize(.small)
                    .help("\(queue.pending) captured sentence(s) waiting to be reviewed")
            }

            if capture.isRunning {
                Image(systemName: "record.circle")
                    .foregroundStyle(.red)
                    .help("Capturing your typing in Brave and Slack.")
            } else if capture.awaitingPermission {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("Waiting for Accessibility permission.")
            }

            Menu {
                Toggle("Capture my typing", isOn: $capture.isEnabled)
                Button("Settings…") { SettingsWindow.show() }
                Button("Open history window") { HistoryWindow.show() }
                Divider()
                Button("Quit Tichit") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
