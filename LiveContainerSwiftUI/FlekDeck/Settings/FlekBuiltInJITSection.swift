//
//  FlekBuiltInJITSection.swift
//  LiveContainerSwiftUI
//
//  What the JIT page shows while built-in JIT is the selected enabler: its
//  setup, as three steps that each tick off once done — the pairing file it
//  connects with, the VPN it connects through, and a check that the two work.
//
//  Built-in JIT is StikJIT run by FlekDeck itself. A guest that needs JIT
//  starts a second LiveProcess, which reaches the device's own debug service
//  through a VPN and attaches to the guest — see enableJITWithStikJIT in
//  LCBootstrap. That happens at launch with nothing on screen, so whatever can
//  be set up or found out ahead of it is here.
//

import SwiftUI
import UniformTypeIdentifiers

struct FlekBuiltInJITSection: View {
    private enum Readiness: Equatable {
        case unchecked
        /// With the step under way, as shown.
        case checking(String)
        case ready
        case failed(String)
    }

    /// One at a time: a check opens a tunnel to the device and may mount a disk
    /// image, and two of those at once would mount it twice.
    private static let checkQueue = DispatchQueue(label: "com.fs.flekdeck.builtInJIT.check")

    private static let localDevVPNURL = URL(string: "https://apps.apple.com/app/localdevvpn/id6755608044")!

    @ObservedObject private var vpn = FlekLoopbackVPN.shared

    @State private var pairingFileFound = (try? LCPath.pairingFilePath.checkResourceIsReachable()) ?? false
    @State private var isChoosingPairingFile = false
    @State private var readiness = Readiness.unchecked
    /// Setting the VPN up or turning it on, which takes a moment.
    @State private var isVPNBusy = false
    @State private var notice = ""
    @State private var noticeShow = false

    var body: some View {
        Section {
            if let blocker = FlekBuiltInJIT.blocker {
                Text(blocker)
                    .foregroundStyle(.red)
            }
            pairingStep
            vpnStep
            readinessStep
            if readiness == .ready {
                // Being ready enables JIT for no app yet, which is the one
                // thing the steps above do not say.
                Label {
                    Text("lc.flek.jit.perApp".loc)
                        .font(.footnote)
                } icon: {
                    Image(systemName: FlekSymbol.jit)
                        .foregroundStyle(.secondary)
                }
            }
            DisclosureGroup("lc.flek.jit.more".loc) {
                if pairingFileFound {
                    Button("lc.flek.jit.pairingFile.remove".loc, role: .destructive) {
                        try? FileManager.default.removeItem(at: LCPath.pairingFilePath)
                        pairingFileFound = false
                        readiness = .unchecked
                    }
                }
                if vpn.isConfigured {
                    Button("lc.flek.jit.vpn.remove".loc, role: .destructive) {
                        runVPN { try await vpn.remove() }
                    }
                    .disabled(isVPNBusy)
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

    /// One step of the setup: its number, which becomes a tick once the step is
    /// done, what the step is, a line about it, and the control that does it.
    private func step<Control: View>(_ number: Int, isDone: Bool, title: String, caption: String,
                                     captionColor: Color = .secondary,
                                     @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 12) {
            Image(systemName: isDone ? "checkmark.circle.fill" : "\(number).circle")
                .font(.title2)
                .foregroundStyle(isDone ? Color.green : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(captionColor)
            }
            Spacer(minLength: 8)
            control()
        }
        .padding(.vertical, 2)
    }

    /// A step's control. Bordered, so that it is the button that is tapped
    /// rather than the whole row.
    private func stepButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
    }

    // MARK: 1. Pairing file

    private var pairingStep: some View {
        step(1, isDone: pairingFileFound,
             title: "lc.flek.jit.step1.title".loc,
             caption: (pairingFileFound ? "lc.flek.jit.step1.done" : "lc.flek.jit.step1.caption").loc) {
            stepButton((pairingFileFound ? "lc.flek.jit.replace" : "lc.flek.jit.import").loc) {
                isChoosingPairingFile = true
            }
        }
        // On the one row that is always here: a modifier on the section would
        // be applied to every row, and so present, or run, once per row.
        .alert("lc.flek.jit.header".loc, isPresented: $noticeShow) {
            Button("lc.common.ok".loc) {}
        } message: {
            Text(notice)
        }
        .task {
            if FlekLoopbackVPN.isAvailable {
                await vpn.refresh()
            }
        }
        .betterFileImporter(isPresented: $isChoosingPairingFile, types: Self.pairingFileTypes, multiple: false) { urls in
            importPairingFile(from: urls[0])
        } onDismiss: {
            isChoosingPairingFile = false
        }
    }

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

    // MARK: 2. VPN

    /// The VPN the helper connects through: FlekDeck's own where this copy can
    /// provide one, and LocalDevVPN, which FlekDeck has no way to see or to
    /// start, where it cannot.
    @ViewBuilder
    private var vpnStep: some View {
        if FlekLoopbackVPN.isAvailable {
            step(2, isDone: vpn.isConfigured,
                 title: "lc.flek.jit.step2.title".loc,
                 caption: "lc.flek.jit.step2.caption".loc) {
                if vpn.isConfigured {
                    Toggle("lc.flek.jit.step2.title".loc, isOn: vpnSwitch)
                        .labelsHidden()
                        .disabled(isVPNBusy)
                } else if isVPNBusy {
                    ProgressView()
                } else {
                    stepButton("lc.flek.jit.setUp".loc) {
                        runVPN {
                            try await vpn.setUp()
                            try await vpn.connect()
                        }
                    }
                }
            }
        } else {
            step(2, isDone: false,
                 title: "lc.flek.jit.step2.external.title".loc,
                 caption: "lc.flek.jit.step2.external.caption".loc) {
                stepButton("lc.flek.jit.get".loc) {
                    UIApplication.shared.open(Self.localDevVPNURL)
                }
            }
        }
    }

    private var vpnSwitch: Binding<Bool> {
        Binding {
            vpn.isOn
        } set: { isOn in
            if isOn {
                runVPN { try await vpn.connect() }
            } else {
                vpn.disconnect()
            }
        }
    }

    private func runVPN(_ work: @escaping () async throws -> Void) {
        isVPNBusy = true
        Task {
            do {
                try await work()
            } catch {
                show(error.localizedDescription)
            }
            isVPNBusy = false
        }
    }

    // MARK: 3. Readiness

    private var readinessStep: some View {
        step(3, isDone: readiness == .ready,
             title: "lc.flek.jit.step3.title".loc,
             caption: readinessCaption,
             captionColor: readinessColor) {
            if isChecking {
                ProgressView()
            } else {
                stepButton("lc.flek.jit.check".loc) {
                    checkReadiness()
                }
                .disabled(!pairingFileFound || FlekBuiltInJIT.blocker != nil)
            }
        }
    }

    private var isChecking: Bool {
        if case .checking = readiness { return true }
        return false
    }

    private var readinessCaption: String {
        switch readiness {
        case .unchecked:
            return "lc.flek.jit.step3.caption".loc
        case .checking(let step):
            return step
        case .ready:
            return "lc.flek.jit.ready".loc
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
        readiness = .checking(Self.stepText(0, -1))
        Task {
            // FlekDeck's own VPN is turned on for the check as it is for a
            // launch. If it does not come up, the check says so in its own way.
            if vpn.isConfigured {
                try? await vpn.connect()
            }
            Self.checkQueue.async {
                let error = LCUtils.prepareBuiltInJIT { stage, fraction in
                    let step = Self.stepText(stage, fraction)
                    DispatchQueue.main.async {
                        readiness = .checking(step)
                    }
                }
                DispatchQueue.main.async {
                    if let error = error as NSError? {
                        // Code 1 is StikJITPreflight's "nothing answered", which is
                        // nearly always the VPN that leads back to the device.
                        let hint = error.code == 1 ? "\n" + "lc.flek.jit.unreachableHint".loc : ""
                        readiness = .failed(error.localizedDescription + hint)
                    } else {
                        readiness = .ready
                    }
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
}
