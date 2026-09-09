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

    private let client = GeminiClient()
    private var task: Task<Void, Never>?

    var canSubmit: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading
    }

    func improve() {
        guard canSubmit else { return }
        let text = input
        let tone = tone
        task?.cancel()
        isLoading = true
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
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            TextEditor(text: $composer.input)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(height: 96)
                .background(Color(nsColor: .textBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .separatorColor))
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .focused($inputFocused)
                .overlay(alignment: .topLeading) {
                    if composer.input.isEmpty {
                        Text("Write the sentence you want to send…")
                            .foregroundStyle(.tertiary)
                            .font(.system(size: 13))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 14)
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
                .frame(maxHeight: 260)
            }
        }
        .padding(14)
        .frame(width: 420)
        .onAppear { inputFocused = true }
    }

    private var header: some View {
        HStack {
            Text("Tich")
                .font(.headline)
            Spacer()
            Menu {
                Button("Clear") { composer.reset() }
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
            }

            Button("Improve") { composer.improve() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!composer.canSubmit)
                .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private func resultBody(_ result: Suggestion) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Improved")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(composer.copied ? "Copied" : "Copy") { composer.copyImproved() }
                        .buttonStyle(.link)
                        .keyboardShortcut("c", modifiers: [.command, .shift])
                }
                Text(result.improved)
                    .font(.system(size: 13))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
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
                        .font(.system(size: 13))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !result.notes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("What changed")
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
                            .font(.system(size: 12))
                            Text(note.reason)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}
