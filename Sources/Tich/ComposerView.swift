import AppKit
import SwiftUI

@MainActor
final class Composer: ObservableObject {
    @Published var input = ""
    @Published var tone: Tone = .neutral
    @Published var result: Suggestion?
    @Published var error: String?
    @Published var isLoading = false
    @Published var copied = false
    /// Codex runs a full agent loop, so it is far slower than a direct API call.
    @Published var slowProvider = false

    private var task: Task<Void, Never>?

    private var client: RewriteProvider {
        Provider.resolved == .codex ? CodexClient() : GeminiClient()
    }

    var canSubmit: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading
    }

    func improve() {
        guard canSubmit else { return }
        let text = input
        let tone = tone
        let client = client
        let viaCodex = Provider.resolved == .codex
        task?.cancel()
        isLoading = true
        slowProvider = viaCodex
        error = nil
        copied = false

        task = Task {
            do {
                let suggestion = try await client.improve(text: text, tone: tone)
                guard !Task.isCancelled else { return }
                result = suggestion
                History.append(original: text, suggestion: suggestion, tone: tone)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            isLoading = false
        }
    }

    func copyImproved() {
        guard let text = result?.improved else { return }
        copy(text)
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
    }

    func reset() {
        task?.cancel()
        input = ""
        result = nil
        error = nil
        isLoading = false
        copied = false
    }
}

struct ComposerView: View {
    @ObservedObject var composer: Composer

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            SentenceEditor(text: $composer.input) { composer.improve() }
                .frame(height: 84)
                .background(Color(nsColor: .textBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .separatorColor))
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(alignment: .topLeading) {
                    if composer.input.isEmpty {
                        Text("Write in English or Italian…")
                            .foregroundStyle(.tertiary)
                            .font(.system(size: 14))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 10)
                            .allowsHitTesting(false)
                    }
                }

            controls

            if let error = composer.error {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let result = composer.result {
                Divider()
                ScrollView {
                    resultBody(result)
                }
                .frame(minHeight: 260, maxHeight: 720)
            }
        }
        .padding(14)
        .frame(width: 680)
    }

    private var header: some View {
        HStack {
            Text("Tich")
                .font(.headline)
            Spacer()
            Menu {
                Button("Clear") { composer.reset() }
                Button("History…") { HistoryWindow.show() }
                    .keyboardShortcut("y", modifiers: .command)
                Button("Settings…") { SettingsWindow.show() }
                Divider()
                Button("Quit Tich") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Picker("", selection: $composer.tone) {
                ForEach(Tone.allCases) { Text($0.rawValue).tag($0) }
            }
            .labelsHidden()
            .fixedSize()

            Spacer()

            if composer.isLoading {
                ProgressView().controlSize(.small)
                if composer.slowProvider {
                    Text("Codex — this takes ~30s")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }

            Text("↵ improve · ⇧↵ new line")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)

            Button("Improve") { composer.improve() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!composer.canSubmit)
                .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private func resultBody(_ result: Suggestion) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let literal = result.literal, !literal.isEmpty, result.wasItalian {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Word for word")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(literal)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .italic()
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(result.wasItalian ? "In English" : "Improved")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(composer.copied ? "Copied" : "Copy") { composer.copyImproved() }
                        .buttonStyle(.link)
                        .keyboardShortcut("c", modifiers: [.command, .shift])
                }
                Text(result.improved)
                    .font(.system(size: 17, weight: .medium))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.accentColor.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            if let alternative = result.alternative, !alternative.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Alternative")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Copy") { composer.copy(alternative) }
                            .buttonStyle(.link)
                    }
                    Text(alternative)
                        .font(.system(size: 14))
                        .lineSpacing(2)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let glossary = result.glossary, !glossary.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Parole e modi di dire")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(glossary) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline, spacing: 5) {
                                Text(item.term)
                                    .font(.system(size: 13, weight: .medium))
                                Text("=")
                                    .foregroundStyle(.tertiary)
                                Text(item.italian)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                            }
                            if let note = item.note, !note.isEmpty {
                                Text(note)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if !result.notes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(result.wasItalian ? "Perché non è letterale" : "What changed")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(result.notes) { note in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(note.original)
                                    .strikethrough()
                                    .foregroundStyle(.secondary)
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                                Text(note.suggestion)
                                    .foregroundStyle(.primary)
                            }
                            .font(.system(size: 13))
                            Text(note.reason)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}
