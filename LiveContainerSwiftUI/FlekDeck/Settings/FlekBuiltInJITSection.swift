//
//  FlekBuiltInJITSection.swift
//  LiveContainerSwiftUI
//
//  The section the JIT page shows while built-in JIT is the selected enabler:
//  the pairing file it connects with, and a check of the rest of what it needs.
//
//  Built-in JIT is StikJIT run by FlekDeck itself. A guest that needs JIT
//  starts a second LiveProcess, which reaches the device's own debug service
//  through LocalDevVPN and attaches to the guest — see enableJITWithStikJIT in
//  LCBootstrap. That happens at launch with nothing on screen, so whatever can
//  be found out ahead of it is found out here.
//

import SwiftUI
import UniformTypeIdentifiers

struct FlekBuiltInJITSection: View {
    private enum Readiness: Equatable {
        case unchecked
        /// With the step under way, as shown.
        case checking(String)
        /// With whether the device has TXM, nil where that cannot be told.
        case ready(txm: Bool?)
        case failed(String)
    }

    /// One at a time: a check opens a tunnel to the device and may mount a disk
    /// image, and two of those at once would mount it twice.
    private static let checkQueue = DispatchQueue(label: "com.fs.flekdeck.builtInJIT.check")

    @State private var pairingFileFound = (try? LCPath.pairingFilePath.checkResourceIsReachable()) ?? false
    @State private var isChoosingPairingFile = false
    @State private var readiness = Readiness.unchecked
    @State private var notice = ""
    @State private var noticeShow = false

    /// Why built-in JIT cannot work in this copy of FlekDeck whatever the user
    /// sets up, or nil. Read once: none of it changes while the app runs.
    private static let blocker = findBlocker()

    var body: some View {
        Section {
            if let blocker = Self.blocker {
                Text(blocker)
                    .foregroundStyle(.red)
            }
            HStack {
                Text("lc.flek.jit.pairingFile".loc)
                Spacer()
                Text((pairingFileFound ? "lc.flek.jit.pairingFile.imported" : "lc.flek.jit.pairingFile.missing").loc)
                    .foregroundStyle(.secondary)
            }
            // On the one row that is always here: a modifier on the section
            // would be applied to every row, and so present once per row.
            .alert("lc.flek.jit.header".loc, isPresented: $noticeShow) {
                Button("lc.common.ok".loc) {}
            } message: {
                Text(notice)
            }
            Button((pairingFileFound ? "lc.flek.jit.pairingFile.replace" : "lc.flek.jit.pairingFile.import").loc) {
                isChoosingPairingFile = true
            }
            .betterFileImporter(isPresented: $isChoosingPairingFile, types: Self.pairingFileTypes, multiple: false) { urls in
                importPairingFile(from: urls[0])
            } onDismiss: {
                isChoosingPairingFile = false
            }
            if pairingFileFound {
                Button("lc.flek.jit.pairingFile.remove".loc, role: .destructive) {
                    try? FileManager.default.removeItem(at: LCPath.pairingFilePath)
                    pairingFileFound = false
                    readiness = .unchecked
                }
            }
            if Self.blocker == nil {
                Button {
                    checkReadiness()
                } label: {
                    HStack {
                        Text("lc.flek.jit.check".loc)
                        Spacer()
                        if isChecking {
                            ProgressView()
                        }
                    }
                }
                .disabled(isChecking)
                if let readinessText {
                    Text(readinessText)
                        .font(.footnote)
                        .foregroundStyle(readinessColor)
                }
                Button("lc.flek.jit.resetImage".loc) {
                    resetDiskImage()
                }
                .disabled(isChecking)
            }
        } header: {
            Text("lc.flek.jit.header".loc)
        } footer: {
            Text("lc.flek.jit.footer".loc)
        }
    }

    // MARK: Pairing file

    /// A pairing file is a property list whatever it is called; iloader and
    /// SideStore name theirs .mobiledevicepairing.
    private static let pairingFileTypes: [UTType] = [
        .propertyList,
        UTType(filenameExtension: "mobiledevicepairing", conformingTo: .data),
        UTType(filenameExtension: "mobiledevicepair", conformingTo: .data),
    ].compactMap { $0 }

    /// Takes the file only if it holds a RemotePairing record, which is the one
    /// StikJIT connects with. A pairing file made by an older tool holds only a
    /// lockdown record, and would otherwise fail much later, at an app's
    /// launch, with an error that says nothing about the file.
    private func importPairingFile(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let record = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            guard let record, record["public_key"] is Data, record["private_key"] is Data,
                  record["identifier"] is String else {
                throw "lc.flek.jit.pairingFile.wrongKind".loc
            }
            let destination = LCPath.pairingFilePath
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try data.write(to: destination, options: .atomic)
            pairingFileFound = true
            readiness = .unchecked
        } catch {
            show(error.localizedDescription)
        }
    }

    // MARK: Readiness

    private var isChecking: Bool {
        if case .checking = readiness { return true }
        return false
    }

    private var readinessText: String? {
        switch readiness {
        case .unchecked:
            return nil
        case .checking(let step):
            return step
        case .ready(let txm):
            return (txm == true ? "lc.flek.jit.ready.txm" : "lc.flek.jit.ready").loc
        case .failed(let reason):
            return reason
        }
    }

    private var readinessColor: Color {
        switch readiness {
        case .ready: return .green
        case .failed: return .red
        default: return .secondary
        }
    }

    /// Does what a guest's helper does first at launch — reach the device and
    /// mount its developer disk image — but here, where it can be watched, and
    /// with the image left mounted for the launches that follow.
    private func checkReadiness() {
        guard pairingFileFound else {
            readiness = .failed("lc.flek.jit.needsPairingFile".loc)
            return
        }
        readiness = .checking(Self.stepText(0, -1))
        Self.checkQueue.async {
            let error = LCUtils.prepareBuiltInJIT { stage, fraction in
                let step = Self.stepText(stage, fraction)
                DispatchQueue.main.async {
                    readiness = .checking(step)
                }
            }
            let txm = LCUtils.isTXMPresentForBuiltInJIT()?.boolValue
            DispatchQueue.main.async {
                if let error = error as NSError? {
                    // Code 1 is StikJITPreflight's "nothing answered", which is
                    // nearly always the VPN that leads back to the device.
                    let hint = error.code == 1 ? "\n" + "lc.flek.jit.unreachableHint".loc : ""
                    readiness = .failed(error.localizedDescription + hint)
                } else {
                    readiness = .ready(txm: txm)
                }
            }
        }
    }

    /// The stages StikJITPreflight reports, in its numbering.
    private static func stepText(_ stage: Int, _ fraction: Double) -> String {
        let percent = Int((max(0, min(1, fraction)) * 100).rounded())
        switch stage {
        case 1: return "lc.flek.jit.step.checkingImage".loc
        case 2: return String(format: "lc.flek.jit.step.downloading %lld".loc, percent)
        case 3: return String(format: "lc.flek.jit.step.mounting %lld".loc, percent)
        case 4, 5: return "lc.flek.jit.step.verifying".loc
        default: return "lc.flek.jit.step.reaching".loc
        }
    }

    private func resetDiskImage() {
        Self.checkQueue.async {
            let error = LCUtils.resetBuiltInJITDiskImage()
            DispatchQueue.main.async {
                show(error?.localizedDescription ?? "lc.flek.jit.resetImage.done".loc)
            }
        }
    }

    private func show(_ text: String) {
        notice = text
        noticeShow = true
    }

    // MARK: What rules built-in JIT out

    private static func findBlocker() -> String? {
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
            if let executable, isSigned(executable, withoutEntitlement: "get-task-allow") {
                return "lc.flek.jit.blocker.entitlement".loc
            }
        }
        return nil
#endif
    }

    /// True only where the entitlements could be read and `entitlement` is not
    /// set in them. A signature that cannot be read rules nothing out.
    private static func isSigned(_ executable: String, withoutEntitlement entitlement: String) -> Bool {
        guard let xml = getExecutableEntitlementXML(executable),
              let entitlements = try? PropertyListSerialization.propertyList(
                from: Data(xml.utf8), format: nil) as? [String: Any] else {
            return false
        }
        return entitlements[entitlement] as? Bool != true
    }
}
