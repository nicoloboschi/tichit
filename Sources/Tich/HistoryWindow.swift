import AppKit
import SwiftUI

enum HistoryTab: String, CaseIterable, Identifiable {
    case improved = "Improved"
    case captured = "Captured"
    var id: String { rawValue }
}

struct HistoryView: View {
    @State private var entries: [History.Entry] = []
    @State private var captured: [CapturedSentence] = []
    @State private var tab: HistoryTab = .improved
    @State private var search = ""

    private var filteredCaptured: [CapturedSentence] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return captured }
        return captured.filter {
            $0.text.lowercased().contains(query) || $0.app.lowercased().contains(query)
        }
    }

    private var filtered: [History.Entry] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return entries }
        return entries.filter {
            $0.original.lowercased().contains(query)
                || $0.improved.lowercased().contains(query)
                || $0.notes.contains { note in
                    note.original.lowercased().contains(query)
                        || note.suggestion.lowercased().contains(query)
                        || note.reason.lowercased().contains(query)
                }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(HistoryTab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 14)
            .padding(.top, 10)
            toolbar
            Divider()
            if tab == .captured {
                capturedList
            } else if entries.isEmpty {
                placeholder("Nothing yet. Every sentence you improve shows up here.")
            } else if filtered.isEmpty {
                placeholder("No match for “\(search)”.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(filtered) { entry in
                            row(entry)
                            Divider()
                        }
                    }
                }
            }
        }
        .frame(minWidth: 620, minHeight: 460)
        .onAppear { reload() }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search your past sentences", text: $search)
                .textFieldStyle(.plain)
            Text("\(tab == .captured ? filteredCaptured.count : filtered.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                reload()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Reload")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func reload() {
        entries = History.load()
        captured = CaptureStore.load()
    }

    @ViewBuilder
    private var capturedList: some View {
        if !KeystrokeCapture.shared.isEnabled {
            placeholder("Capture is off. Turn on “Capture my typing” in the ⋯ menu.")
        } else if captured.isEmpty {
            placeholder("Nothing captured yet. Keep typing — sentences land here.")
        } else if filteredCaptured.isEmpty {
            placeholder("No match for “\(search)”.")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(filteredCaptured) { item in
                        capturedRow(item)
                        Divider()
                    }
                }
            }
        }
    }

    private func capturedRow(_ item: CapturedSentence) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.date, format: .dateTime.day().month().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(item.app)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(Capsule())
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.text, forType: .string)
                }
                .buttonStyle(.link)
            }
            Text(item.text)
                .font(.system(size: 14))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func placeholder(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func row(_ entry: History.Entry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(entry.date, format: .dateTime.day().month().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(entry.tone)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(Capsule())
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.improved, forType: .string)
                }
                .buttonStyle(.link)
            }

            Text(entry.original)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            Text(entry.improved)
                .font(.system(size: 15, weight: .medium))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            if !entry.notes.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(entry.notes) { note in
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(note.original)
                                .strikethrough()
                                .foregroundStyle(.secondary)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 8))
                                .foregroundStyle(.tertiary)
                            Text(note.suggestion)
                            Text("— \(note.reason)")
                                .foregroundStyle(.secondary)
                        }
                        .font(.system(size: 12))
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

@MainActor
enum HistoryWindow {
    private static var window: NSWindow?

    static func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 680, height: 520),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            w.title = "Tich History"
            w.contentView = NSHostingView(rootView: HistoryView())
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        } else {
            // Re-mount so the list picks up sentences added since it was last opened.
            window?.contentView = NSHostingView(rootView: HistoryView())
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
