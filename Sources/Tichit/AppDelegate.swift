import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let composer = Composer()
    private var hotKeyRef: EventHotKeyRef?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = Logo.statusItemImage(.idle)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)

        popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: RootView(composer: composer)
        )

        registerHotKey()
        observeStatus()
        KeystrokeCapture.shared.startIfEnabled()
        observeReviews()
        requestNotificationPermission()

        // Only nag for a key when there is no working provider at all.
        if Provider.resolved == .gemini, Config.apiKey == nil {
            SettingsWindow.show()
        }
    }

    @objc func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    // MARK: - Status badge and notifications

    private func observeStatus() {
        composer.$status
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                guard let self else { return }
                self.statusItem.button?.image = Logo.statusItemImage(status)
                // An answer that landed while you were looking at it is already read.
                if status == .ready {
                    if self.popover.isShown {
                        self.composer.markRead()
                    } else {
                        self.notifyReady()
                    }
                }
            }
            .store(in: &cancellables)
    }

    private func observeReviews() {
        ReviewQueue.shared.onNotable = { [weak self] review in
            self?.notifyNotable(review)
        }
        // Anything captured while the app was closed still deserves a look.
        ReviewQueue.shared.enqueueBacklog()
    }

    private func notifyNotable(_ review: Review) {
        let content = UNMutableNotificationContent()
        content.title = "Better English"
        content.subtitle = review.original
        content.body = review.improved
        content.sound = nil

        let request = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil
        )
        Task { try? await UNUserNotificationCenter.current().add(request) }
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().delegate = self
        // The completion-handler form calls back off the main queue; declared inside
        // this @MainActor class that trips Swift's executor assertion and kills the
        // app. The async form hops back properly.
        Task {
            _ = try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        }
    }

    private func notifyReady() {
        let content = UNMutableNotificationContent()
        content.title = "Your English is ready"
        content.body = composer.result?.improved ?? ""
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        Task { try? await UNUserNotificationCenter.current().add(request) }
    }

    func togglePopoverFromNotification() {
        if !popover.isShown { showPopover() }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        composer.markRead()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        popover.contentViewController?.view.window?.makeKey()
    }

    // MARK: - Global hotkey (⌘⇧E)

    private func registerHotKey() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { delegate.togglePopover() }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            nil
        )

        let id = EventHotKeyID(signature: OSType(0x54494348), id: 1) // 'TICH'
        RegisterEventHotKey(
            UInt32(kVK_ANSI_E),
            UInt32(cmdKey | shiftKey),
            id,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    // nonisolated because the delegate callbacks arrive off the main actor.
    /// Tapping the notification opens the popover on the answer.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let finish = UncheckedSendable(completionHandler)
        let capturedTab = response.notification.request.content.title == "Better English"
        Task { @MainActor in
            if capturedTab { Tabs.shared.selected = .captured }
            self.togglePopoverFromNotification()
            finish.value()
        }
    }

    /// Show the banner even when Tichit is the frontmost app.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

/// Carries a non-Sendable completion handler across the hop to the main actor.
private struct UncheckedSendable<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}
