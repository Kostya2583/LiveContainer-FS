//
//  FlekDevicePairing.swift
//  LiveContainerSwiftUI
//
//  The first step of the JIT setup done without a computer: FlekDeck makes the
//  pairing file itself, see LCDevicePairing.
//
//  The user's part of it is in the Settings app — picking FlekDeck under
//  Developer Mode and typing the code FlekDeck shows — so FlekDeck has to go on
//  running behind Settings, and to show the code there. Both come from a
//  continued-processing task, as installs use: the system keeps the app going
//  for it, and shows its title and subtitle in a Live Activity.
//

import BackgroundTasks
import Combine
import SwiftUI

@MainActor
final class FlekDevicePairing: ObservableObject {
    enum State: Equatable {
        case idle
        /// Advertised, and waiting for the user to pick FlekDeck in Settings.
        case waiting
        /// The device has connected and asks for this code.
        case askingForCode(String)
        case paired
        case failed(String)
    }

    /// A device only pairs with a host on its network from iOS 27, and the
    /// library that does the pairing is in device builds only.
    static var isSupported: Bool {
        if #available(iOS 27.0, *) {
            return LCDevicePairing.isAvailable
        }
        return false
    }

    @Published private(set) var state = State.idle
    /// Set once a try has failed, while the next one is awaited.
    @Published private(set) var hasFailedAttempt = false

    private var pairing: LCDevicePairing?
    /// Counts the starts, so that what a pairing reports can be told from what
    /// one before it still had on its way.
    private var attempt = 0
    /// A `FlekPairingKeepAlive`, which only exists from iOS 26.
    private var keepAlive: AnyObject?
    private var backgroundWatch: AnyCancellable?
    private var backgroundTime = UIBackgroundTaskIdentifier.invalid

    func start() {
        cancel()
        hasFailedAttempt = false
        state = .waiting

        let pairing = LCDevicePairing()
        self.pairing = pairing
        attempt += 1
        let attempt = attempt
        // A developer switch, for finding out whether a device pairs without
        // asking for a code.
        let withoutCode = UserDefaults.standard.bool(forKey: "FlekPairWithoutCode")
        // The blocks are called on the main queue, which the compiler has no
        // way to know, hence the hop onto the main actor in each. By the time
        // one gets there the pairing may have been cancelled, or replaced.
        pairing.start(withName: "FlekDeck", withoutCode: withoutCode) { [weak self] code in
            Task { @MainActor in
                guard let self, self.isCurrent(attempt) else {
                    return
                }
                self.state = .askingForCode(code)
                self.showBehindSettings(String(format: "lc.flek.jit.pair.activity.code %@".loc, code))
            }
        } onAttemptFailed: { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isCurrent(attempt) else {
                    return
                }
                self.hasFailedAttempt = true
                self.state = .waiting
                self.showBehindSettings("lc.flek.jit.pair.retry".loc)
            }
        } completion: { [weak self] file, error in
            Task { @MainActor in
                guard let self, self.isCurrent(attempt) else {
                    return
                }
                self.finish(file: file, error: error)
            }
        }
        keepRunningBehindSettings()
    }

    private func isCurrent(_ attempt: Int) -> Bool {
        attempt == self.attempt && pairing != nil
    }

    func cancel() {
        pairing?.cancel()
        pairing = nil
        endKeepAlive(success: false)
        state = .idle
    }

    private func finish(file: Data?, error: Error?) {
        pairing = nil
        guard let file else {
            state = .failed(Self.describe(error))
            endKeepAlive(success: false)
            return
        }
        do {
            let destination = LCPath.pairingFilePath
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try file.write(to: destination, options: .atomic)
            state = .paired
            endKeepAlive(success: true)
        } catch {
            state = .failed(error.localizedDescription)
            endKeepAlive(success: false)
        }
    }

    private static func describe(_ error: Error?) -> String {
        if let error = error as? LCDevicePairingError, error.code == .localNetworkDenied {
            return "lc.flek.jit.pair.localNetwork".loc
        }
        return error?.localizedDescription ?? ""
    }

    // MARK: Behind Settings

    private func keepRunningBehindSettings() {
        // The half minute any app is given on leaving the foreground, asked for
        // each time FlekDeck leaves it. All there is where the system does not
        // take the task below, and enough to pick FlekDeck in Settings.
        backgroundWatch = NotificationCenter.default
            .publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.askForBackgroundTime()
                }
            }
        guard #available(iOS 26.0, *) else {
            return
        }
        let keepAlive = FlekPairingKeepAlive(title: "lc.flek.jit.pair.activity.title".loc,
                                             subtitle: "lc.flek.jit.pair.activity.waiting".loc)
        // The system took the time back, or the user tapped Cancel in the Live
        // Activity. Without it the pairing would only freeze where it stands.
        keepAlive?.onExpired = { [weak self] in
            guard let self, self.pairing != nil else {
                return
            }
            self.cancel()
            self.state = .failed("lc.flek.jit.pair.stopped".loc)
        }
        self.keepAlive = keepAlive
    }

    private func showBehindSettings(_ text: String) {
        if #available(iOS 26.0, *) {
            (keepAlive as? FlekPairingKeepAlive)?.show(text)
        }
    }

    private func endKeepAlive(success: Bool) {
        backgroundWatch = nil
        giveBackBackgroundTime()
        if #available(iOS 26.0, *) {
            (keepAlive as? FlekPairingKeepAlive)?.end(success: success)
        }
        keepAlive = nil
    }

    private func askForBackgroundTime() {
        guard pairing != nil, backgroundTime == .invalid else {
            return
        }
        backgroundTime = UIApplication.shared.beginBackgroundTask(withName: "Pairing") { [weak self] in
            // Out of time. The pairing stays as it is, and goes on from there
            // if the user comes back to FlekDeck.
            Task { @MainActor in
                self?.giveBackBackgroundTime()
            }
        }
    }

    private func giveBackBackgroundTime() {
        guard backgroundTime != .invalid else {
            return
        }
        UIApplication.shared.endBackgroundTask(backgroundTime)
        backgroundTime = .invalid
    }
}

/// Keeps the app running, and one line of text on show, while it is behind
/// another app.
@available(iOS 26.0, *)
@MainActor
private final class FlekPairingKeepAlive {
    /// The one in use. The scheduler's launch handler outlives it, as a
    /// registration cannot be taken back, so the handler finds it here by
    /// identifier rather than holding on to it.
    private static weak var current: FlekPairingKeepAlive?

    private let identifier: String
    private let title: String
    private var subtitle: String
    private var task: BGContinuedProcessingTask?
    private var ticker: Timer?
    private var isOver = false
    var onExpired: (() -> Void)?

    /// Nil where the system would not take the task, which leaves the pairing
    /// to whatever time the app is given anyway.
    init?(title: String, subtitle: String) {
        guard let prefix = LCInstallBackgroundTask.taskIdentifierPrefix() else {
            return nil
        }
        // Never reused: registering one identifier twice ends the app.
        identifier = prefix + "pairing-" + UUID().uuidString
        self.title = title
        self.subtitle = subtitle

        let identifier = identifier
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let task = task as? BGContinuedProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                FlekPairingKeepAlive.adopt(task, identifier: identifier)
            }
        }
        guard registered else {
            return nil
        }
        let request = BGContinuedProcessingTaskRequest(identifier: identifier, title: title, subtitle: subtitle)
        // Now or not at all: by the time a queued task started, the user would
        // be done in Settings.
        request.strategy = .fail
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            NSLog("[LC] pairing keep-alive was not taken: \(error)")
            return nil
        }
        Self.current = self
    }

    private static func adopt(_ task: BGContinuedProcessingTask, identifier: String) {
        guard let keepAlive = current, keepAlive.identifier == identifier, !keepAlive.isOver else {
            task.setTaskCompleted(success: true)
            return
        }
        keepAlive.task = task
        task.expirationHandler = {
            Task { @MainActor in
                guard let keepAlive = FlekPairingKeepAlive.current, keepAlive.identifier == identifier else {
                    return
                }
                keepAlive.end(success: false)
                keepAlive.onExpired?()
            }
        }
        task.updateTitle(keepAlive.title, subtitle: keepAlive.subtitle)
        // There is nothing to measure while waiting for the user, but a bar
        // that stands still reads as stalled, and stalled tasks are the first
        // the system takes back. It creeps towards full without getting there.
        task.progress.totalUnitCount = 1000
        keepAlive.ticker = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            Task { @MainActor in
                FlekPairingKeepAlive.current?.tick()
            }
        }
    }

    private func tick() {
        guard let progress = task?.progress else {
            return
        }
        progress.completedUnitCount += max(1, (progress.totalUnitCount - progress.completedUnitCount) / 60)
    }

    func show(_ subtitle: String) {
        self.subtitle = subtitle
        task?.updateTitle(title, subtitle: subtitle)
    }

    func end(success: Bool) {
        guard !isOver else {
            return
        }
        isOver = true
        ticker?.invalidate()
        ticker = nil
        if let task {
            task.progress.completedUnitCount = task.progress.totalUnitCount
            task.setTaskCompleted(success: success)
        }
        task = nil
    }
}

/// The sheet shown while the pairing file is being made: what to do in
/// Settings, and the code to type there once the device asks for it.
struct FlekDevicePairingView: View {
    @ObservedObject var pairing: FlekDevicePairing
    /// Called once the pairing file is in place.
    var onPaired: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Label("lc.flek.jit.pair.step1".loc, systemImage: "1.circle")
                    Label("lc.flek.jit.pair.step2".loc, systemImage: "2.circle")
                    Label("lc.flek.jit.pair.step3".loc, systemImage: "3.circle")
                    code
                } footer: {
                    Text(footer)
                        .foregroundStyle(isFailure ? Color.red : Color.secondary)
                }
                Section {
                    if isFailure {
                        Button("lc.flek.retry".loc) {
                            pairing.start()
                        }
                    } else {
                        Button("lc.flek.jit.pair.openSettings".loc) {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                    }
                }
            }
            .navigationTitle("lc.flek.jit.pair.title".loc)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("lc.common.cancel".loc) {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            pairing.start()
        }
        .onDisappear {
            // Also how Cancel and a swipe down end the pairing. Once paired
            // there is nothing left to end.
            if pairing.state != .paired {
                pairing.cancel()
            }
        }
        .onChange(of: pairing.state) { state in
            if state == .paired {
                onPaired()
                dismiss()
            }
        }
    }

    /// The code, large enough to be read at a glance on the way back to
    /// Settings; until the device asks for one, that it is being waited for.
    @ViewBuilder
    private var code: some View {
        if case .askingForCode(let code) = pairing.state {
            Text(code)
                .font(.system(size: 34, weight: .semibold, design: .monospaced))
                .frame(maxWidth: .infinity)
                .textSelection(.enabled)
        } else if !isFailure {
            HStack(spacing: 8) {
                ProgressView()
                Text("lc.flek.jit.pair.waiting".loc)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var isFailure: Bool {
        if case .failed = pairing.state { return true }
        return false
    }

    private var footer: String {
        if case .failed(let reason) = pairing.state {
            return reason
        }
        if pairing.hasFailedAttempt {
            return "lc.flek.jit.pair.retry".loc
        }
        return "lc.flek.jit.pair.footer".loc
    }
}
