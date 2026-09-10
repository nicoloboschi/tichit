import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation

/// A sentence the user typed somewhere on the system, captured passively.
struct CapturedSentence: Codable, Identifiable {
    let date: Date
    let app: String
    let text: String

    var id: String { ISO8601DateFormatter().string(from: date) + text }
}

enum CaptureStore {
    private static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Tich", isDirectory: true)
    }()

    static var fileURL: URL { directory.appendingPathComponent("captured.jsonl") }

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }

    static func append(_ sentence: CapturedSentence) {
        guard var line = try? encoder.encode(sentence) else { return }
        line.append(0x0A)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? line.write(to: fileURL)
        }
    }

    static func load() -> [CapturedSentence] {
        guard let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8)
        else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return text
            .split(separator: "\n")
            .compactMap { try? decoder.decode(CapturedSentence.self, from: Data($0.utf8)) }
            .reversed()
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

/// Watches typing system-wide and turns keystrokes into whole sentences.
///
/// Deliberately conservative: nothing is recorded while macOS secure input is on
/// (password fields switch it on), nothing from denylisted apps, and nothing that
/// looks like a credential rather than prose.
@MainActor
final class KeystrokeCapture: ObservableObject {
    static let shared = KeystrokeCapture()

    @Published private(set) var isRunning = false
    @Published var isEnabled: Bool = UserDefaults.standard.bool(forKey: "captureEnabled") {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "captureEnabled")
            isEnabled ? start() : stop()
        }
    }

    /// Apps whose typing is never recorded. Sensitive by nature or pure noise.
    static let defaultDenylist: Set<String> = [
        "com.apple.keychainaccess",
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop",
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "com.apple.SecurityAgent",
        "dev.tich.app",
    ]

    /// Apps where Return sends the message, so it really is the end of a thought.
    /// Everywhere else Return is just a line break inside a paragraph.
    static let returnSendsApps: Set<String> = [
        "com.tinyspeck.slackmacgap",
        "com.hnc.Discord",
        "net.whatsapp.WhatsApp",
        "com.apple.MobileSMS",
        "org.telegram.desktop",
        "ru.keepcoder.Telegram",
        "com.microsoft.teams2",
        "com.apple.iChat",
    ]

    /// Set while waiting for the user to grant Accessibility in System Settings.
    @Published private(set) var awaitingPermission = false

    private var permissionTimer: Timer?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var buffer = ""
    private var bufferApp = ""

    private let maxBuffer = 2000

    private init() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Switching away abandons whatever was half-typed; it was never sent.
            MainActor.assumeIsolated { self?.buffer = "" }
        }
    }

    var hasAccessibilityPermission: Bool { AXIsProcessTrusted() }

    func requestAccessibilityPermission() {
        // The constant itself is a global var, so use its documented raw key.
        let options = ["AXTrustedCheckOptionPrompt": true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    func startIfEnabled() {
        if isEnabled { start() }
    }

    func start() {
        guard !isRunning else { return }
        guard hasAccessibilityPermission else {
            requestAccessibilityPermission()
            waitForPermission()
            return
        }
        awaitingPermission = false
        permissionTimer?.invalidate()
        permissionTimer = nil

        let mask = (1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let capture = Unmanaged<KeystrokeCapture>.fromOpaque(userInfo).takeUnretainedValue()
                MainActor.assumeIsolated { capture.handle(type: type, event: event) }
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            // TCC can still refuse the tap moments after AXIsProcessTrusted() turns
            // true, and it fails silently. Keep polling rather than doing nothing.
            waitForPermission()
            return
        }

        self.tap = tap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isRunning = true
    }

    /// Granting Accessibility does not notify the app, so poll until it lands.
    private func waitForPermission() {
        guard permissionTimer == nil else { return }
        awaitingPermission = true
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard self.isEnabled else {
                    self.cancelPermissionWait()
                    return
                }
                if self.hasAccessibilityPermission {
                    self.permissionTimer?.invalidate()
                    self.permissionTimer = nil
                    self.start()
                }
            }
        }
    }

    private func cancelPermissionWait() {
        permissionTimer?.invalidate()
        permissionTimer = nil
        awaitingPermission = false
    }

    /// Clears this app's Accessibility record and asks again.
    ///
    /// The bundle is ad-hoc signed, so its code hash changes on every rebuild and a
    /// previously granted permission stops matching — while System Settings still
    /// lists Tichit as enabled. Resetting the record is the only way back, and it is
    /// far easier than talking someone through removing and re-adding the app.
    func resetPermission() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "Accessibility", "dev.tichit.app"]
        try? process.run()
        process.waitUntilExit()

        stop()
        isEnabled = true
    }

    /// Opens the exact System Settings pane, so it is one click rather than a hunt.
    func openAccessibilitySettings() {
        let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )!
        NSWorkspace.shared.open(url)
    }

    func stop() {
        flush()
        permissionTimer?.invalidate()
        permissionTimer = nil
        awaitingPermission = false
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        buffer = ""
        isRunning = false
    }

    // MARK: - Event handling

    private func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        guard type == .keyDown else { return }

        // A password field is focused: macOS blocks taps anyway, but be explicit.
        if IsSecureEventInputEnabled() {
            buffer = ""
            return
        }

        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        if Self.defaultDenylist.contains(frontmost) {
            buffer = ""
            return
        }
        if !frontmost.isEmpty, frontmost != bufferApp {
            flush()
            bufferApp = frontmost
        }

        let flags = event.flags
        // Shortcuts are commands, not prose.
        if flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate) {
            return
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        switch keyCode {
        case 51: // delete
            if !buffer.isEmpty { buffer.removeLast() }
            return
        case 36, 76: // return, enter
            // The only boundary. A half-typed thought is not worth reviewing, and
            // pressing Return is the moment you committed to the words.
            flush()
            return
        case 53: // escape
            buffer = ""
            return
        default:
            break
        }

        var length = 0
        var chars = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(maxStringLength: 8, actualStringLength: &length, unicodeString: &chars)
        guard length > 0 else { return }
        let text = String(utf16CodeUnits: chars, count: length)
        guard !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            return
        }

        buffer.append(text)

        // Nothing else closes a sentence; the cap only stops runaway growth.
        if buffer.count >= maxBuffer {
            buffer = ""
        }
    }




    private func flush() {
        let text = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        buffer = ""
        guard Self.looksLikeProse(text) else { return }

        let app = NSWorkspace.shared.frontmostApplication?.localizedName ?? bufferApp
        let sentence = CapturedSentence(date: Date(), app: app, text: text)
        CaptureStore.append(sentence)
        ReviewQueue.shared.enqueue(sentence)
    }

    /// Keeps sentences, drops fragments, tokens, paths and anything credential-shaped.
    static func looksLikeProse(_ text: String) -> Bool {
        guard text.count >= 12, text.count <= maxSentence else { return false }
        let words = text.split(separator: " ")
        guard words.count >= 3 else { return false }
        // No spaces but long, or high symbol density: a key, hash, path or URL.
        let letters = text.filter { $0.isLetter }.count
        guard Double(letters) / Double(text.count) > 0.55 else { return false }
        if text.contains("://") || text.hasPrefix("/") || text.hasPrefix("~/") { return false }
        return true
    }

    private static let maxSentence = 2000
}
