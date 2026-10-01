//
//  FlekJITSetup.swift
//  LiveContainerSwiftUI
//
//  Whether JIT can be enabled as things stand, asked before an app set to
//  launch with JIT is started. A guest enables JIT for itself as it launches,
//  so one started without a working setup fails there, and all the user gets
//  is an error the next time FlekDeck opens. Asked first, the same thing is a
//  warning that says where JIT is set up, and the app is not started.
//

import Network
import SwiftUI

/// What built-in JIT needs that can be told without trying to enable it.
enum FlekBuiltInJIT {
    /// Why built-in JIT cannot work in this copy of FlekDeck whatever the user
    /// sets up, or nil. Read once: none of it changes while the app runs.
    static let blocker: String? = {
#if targetEnvironment(simulator)
        return "lc.flek.jit.blocker.simulator".loc
#else
        guard #available(iOS 17.4, *) else {
            return "lc.flek.jit.blocker.os".loc
        }
        guard LCUtils.isBuiltInJITLoadable() else {
            return "lc.flek.jit.blocker.unavailable".loc
        }
        // A debugger only attaches to a process signed with get-task-allow, and
        // the signature is whatever this copy was last signed with. A guest
        // runs in LiveProcess when in a window, in the app itself otherwise.
        let liveProcess = Bundle.main.builtInPlugInsURL?.appendingPathComponent("LiveProcess.appex/LiveProcess").path
        for executable in [Bundle.main.executablePath, liveProcess] {
            if let executable, let entitlements = FlekSignature.entitlements(ofExecutableAt: executable),
               entitlements["get-task-allow"] as? Bool != true {
                return "lc.flek.jit.blocker.entitlement".loc
            }
        }
        return nil
#endif
    }()

    static var hasPairingFile: Bool {
        (try? LCPath.pairingFilePath.checkResourceIsReachable()) ?? false
    }

    /// Whether anything answers at the address a VPN gives this device, which
    /// is the only way to tell that LocalDevVPN is connected: another app's VPN
    /// cannot be asked about.
    static func isDeviceReachable(within timeout: TimeInterval = 0.7) async -> Bool {
        await withCheckedContinuation { continuation in
            let connection = NWConnection(host: "10.7.0.1", port: 49152, using: .tcp)
            let answer = OneAnswer { isReachable in
                connection.cancel()
                continuation.resume(returning: isReachable)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: answer.give(true)
                case .failed, .cancelled: answer.give(false)
                default: break
                }
            }
            let queue = DispatchQueue.global(qos: .userInitiated)
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) {
                answer.give(false)
            }
        }
    }

    /// Passes on the first answer it is given and drops the rest: the
    /// connection and the timeout both give one.
    private final class OneAnswer: @unchecked Sendable {
        private let lock = NSLock()
        private var handler: ((Bool) -> Void)?

        init(_ handler: @escaping (Bool) -> Void) {
            self.handler = handler
        }

        func give(_ answer: Bool) {
            lock.lock()
            let handler = self.handler
            self.handler = nil
            lock.unlock()
            handler?(answer)
        }
    }
}

enum FlekJITSetup {
    /// JIT cannot be enabled as things stand, with what to tell the user.
    struct NotReady: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Throws `NotReady` where starting an app with JIT would only fail.
    @MainActor
    static func ensureReady() async throws {
        let defaults = LCUtils.appGroupUserDefault
        guard let enabler = JITEnablerType(rawValue: defaults.integer(forKey: "LCJITEnablerType")) else {
            return
        }
        switch enabler {
        case .StikJITHeadless:
            try await ensureBuiltInReady()
        case .SideJITServer:
            // What a fresh install is set to, with nothing filled in.
            let address = defaults.string(forKey: "LCSideJITServerAddress") ?? ""
            let udid = defaults.string(forKey: "LCDeviceUDID") ?? ""
            if address.isEmpty || udid.isEmpty {
                throw NotReady(message: "lc.flek.jit.notReady.setUp".loc)
            }
        default:
            // Another app enables JIT, and whether it will cannot be told here.
            return
        }
    }

    @MainActor
    private static func ensureBuiltInReady() async throws {
        if let blocker = FlekBuiltInJIT.blocker {
            throw NotReady(message: blocker)
        }
        // Another FlekDeck uses the primary one's pairing file, which it
        // cannot see.
        if DataManager.shared.model.multiLCStatus == 0, !FlekBuiltInJIT.hasPairingFile {
            throw NotReady(message: "lc.flek.jit.notReady.setUp".loc)
        }
        let vpn = FlekLoopbackVPN.shared
        if FlekLoopbackVPN.isAvailable {
            await vpn.refresh()
            if vpn.isConfigured {
                do {
                    try await vpn.connect()
                } catch {
                    throw NotReady(message: "lc.flek.jit.notReady.vpn".loc)
                }
                return
            }
        }
        // No VPN of FlekDeck's own, which leaves LocalDevVPN.
        if !(await FlekBuiltInJIT.isDeviceReachable()) {
            throw NotReady(message: (FlekLoopbackVPN.isAvailable ? "lc.flek.jit.notReady.setUp" : "lc.flek.jit.notReady.vpn").loc)
        }
    }
}
