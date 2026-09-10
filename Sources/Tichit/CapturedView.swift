import AppKit
import SwiftUI

/// Reviewed captures: what you actually wrote out in the wild, and what the model
/// thinks you should have written. Sentences it judged fine are hidden by default.
struct CapturedView: View {
    @ObservedObject private var queue = ReviewQueue.shared
    @ObservedObject private var capture = KeystrokeCapture.shared
    @State private var showAll = false

    private var shown: [Review] {
        showAll ? queue.reviews : queue.reviews.filter(\.worthReporting)
    }

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            content
        }
        .frame(height: 520)
        .onAppear { queue.reload() }
    }

    private var controls: some View {
        HStack {
            Toggle("Show everything", isOn: $showAll)
                .toggleStyle(.checkbox)
                .help("Include sentences the model judged already fine")
            Spacer()
            Text(status)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var status: String {
        if !capture.isEnabled { return "capture off" }
        if !capture.isRunning { return "waiting for permission" }
        if queue.pending > 0 { return "\(queue.pending) to review" }
        return "\(shown.count) shown"
    }

    @ViewBuilder
    private var content: some View {
        if !capture.isEnabled {
            placeholder("Capture is off.\nTurn on “Capture my typing” in Settings to collect what you write in Brave and Slack.")
        } else if !capture.isRunning {
            placeholder("Waiting for Accessibility permission — see Settings.")
        } else if shown.isEmpty {
            placeholder(
                queue.reviews.isEmpty
                    ? "Nothing reviewed yet. Keep typing in Brave or Slack."
                    : "Nothing worth flagging so far — your English held up.\nTick “Show everything” to see them anyway."
            )
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(shown) { review in
                        row(review)
                        Divider()
                    }
                }
            }
        }
    }

    private func placeholder(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 30)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func row(_ review: Review) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text(review.date, format: .dateTime.day().month().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(review.app)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(Capsule())
                if !review.worthReporting {
                    Text("fine as written")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(review.improved, forType: .string)
                }
                .buttonStyle(.link)
            }

            Text(review.original)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .strikethrough(review.worthReporting)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            Text(review.improved)
                .font(.system(size: 15, weight: .medium))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(review.notes) { note in
                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(note.original)
                            .strikethrough()
                            .foregroundStyle(.secondary)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                        Text(note.suggestion)
                    }
                    .font(.system(size: 12))
                    Text(note.reason)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
