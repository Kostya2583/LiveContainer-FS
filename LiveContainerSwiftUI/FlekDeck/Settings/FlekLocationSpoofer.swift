//
//  FlekLocationSpoofer.swift
//  LiveContainerSwiftUI
//
//  The Location Spoofer FlekDeck ships in its Frameworks, turned on per app in
//  the app's settings, or from one list on the Tweaks page, and loaded into the
//  app by TweakLoader. It is a Premium feature, checked where FlekJIT is: when
//  it is turned on, before a launch from FlekDeck, and in the app as it starts.
//

import SwiftUI

enum FlekLocationSpoofer {
    /// In the bundle for devices only (xcconfigs/LiveContainer.xcconfig).
    static let isBundled = FileManager.default.fileExists(atPath: Bundle.main.bundleURL.appendingPathComponent("Frameworks/LocationSpoofer.dylib").path)

    /// A launch refused because Premium is not active, which the home offers
    /// to buy.
    struct PremiumNeeded: LocalizedError {
        var errorDescription: String? { "lc.flek.locationSpoofer.premium.needed".loc }
    }

    /// Before a launch with it on. TweakLoader goes by what this publishes,
    /// and loads it only where that says Premium is active.
    @MainActor
    static func ensurePremium() async throws {
        // What the app goes by where it starts without this having been asked.
        FlekPremium.publish()
        switch await FlekPremium.confirm() {
        case .active:
            FlekPremium.noteConfirmedForLaunch()
        case .inactive:
            throw PremiumNeeded()
        case .unconfirmed:
            throw "lc.flek.jit.premium.unconfirmed".loc
        }
    }
}

/// Turns Location Spoofer on and off for an app, the same in the app's own
/// settings and in the list on the Tweaks page: on only with Premium, which is
/// asked first and offered where it is not active.
@MainActor
final class FlekLocationSpooferSwitch: ObservableObject {
    @Published private(set) var isPremium = FlekPremium.isActive
    /// The app Premium is being asked for, which can take the server a moment:
    /// its switch shows that it is, and every switch waits for the answer.
    @Published private(set) var appBeingChecked: LCAppModel?
    @Published var showsPremiumOffer = false
    @Published var showsUncheckable = false
    /// The app it was being turned on for when Premium was offered.
    private var appWaitingOnPremium: LCAppModel?

    var isChecking: Bool {
        appBeingChecked != nil
    }

    func binding(for app: LCAppModel) -> Binding<Bool> {
        Binding(
            get: { app.uiSpoofLocation },
            set: { self.set($0, for: app) }
        )
    }

    func set(_ isOn: Bool, for app: LCAppModel) {
        guard isOn else {
            app.uiSpoofLocation = false
            return
        }
        guard !isChecking else {
            return
        }
        appBeingChecked = app
        Task {
            let answer = await FlekPremium.confirm()
            appBeingChecked = nil
            switch answer {
            case .active:
                isPremium = true
                app.uiSpoofLocation = true
            case .inactive:
                isPremium = false
                appWaitingOnPremium = app
                showsPremiumOffer = true
            case .unconfirmed:
                showsUncheckable = true
            }
        }
    }

    /// The offer was closed. Premium bought there turns it on for the app it
    /// was asked for.
    func offerClosed() {
        isPremium = FlekPremium.isActive
        if isPremium {
            appWaitingOnPremium?.uiSpoofLocation = true
        }
        appWaitingOnPremium = nil
    }
}

/// The grey crown beside Location Spoofer's name while Premium is not active.
struct FlekPremiumCrown: View {
    var body: some View {
        Image("FlekPremium")
            .resizable()
            .scaledToFit()
            .frame(height: 15)
            .foregroundStyle(.secondary)
    }
}

extension View {
    /// What turning Location Spoofer on can lead to: the Premium offer, and a
    /// warning where Premium could not be checked.
    ///
    /// For the page as a whole, never a section or row of a form or list:
    /// those pass their modifiers on to each row and footer, which redraw
    /// while Premium is asked, so the sheet came up twice or was taken down
    /// as it opened.
    func flekLocationSpooferPrompts(_ spooferSwitch: FlekLocationSpooferSwitch) -> some View {
        modifier(FlekLocationSpooferPrompts(spooferSwitch: spooferSwitch))
    }
}

private struct FlekLocationSpooferPrompts: ViewModifier {
    @ObservedObject var spooferSwitch: FlekLocationSpooferSwitch

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $spooferSwitch.showsPremiumOffer, onDismiss: spooferSwitch.offerClosed) {
                FlekPremiumOfferView()
            }
            .alert("lc.common.error".loc, isPresented: $spooferSwitch.showsUncheckable) {
                Button("lc.common.ok".loc, role: .cancel) {}
            } message: {
                Text("lc.flek.jit.premium.unconfirmed".loc)
            }
    }
}

/// Location Spoofer on the Tweaks page, leading to the apps it is on for,
/// chosen from one list as FlekJIT's are on the JIT page.
struct FlekLocationSpooferSection: View {
    @State private var appCount = FlekLocationSpooferAppsView.countUsingIt
    @State private var isPremium = FlekPremium.isActive

    var body: some View {
        Section {
            NavigationLink {
                FlekLocationSpooferAppsView()
            } label: {
                HStack(spacing: 12) {
                    FlekSetupTile(color: .blue, size: 32) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("lc.flek.locationSpoofer".loc)
                            if !isPremium {
                                FlekPremiumCrown()
                            }
                        }
                        Text(appCount > 0 ? String(format: "lc.flek.locationSpoofer.apps.count %lld".loc, appCount)
                                          : "lc.flek.locationSpoofer.apps.caption".loc)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
            // Also on the way back from the list, where both can change.
            .onAppear {
                appCount = FlekLocationSpooferAppsView.countUsingIt
                isPremium = FlekPremium.isActive
            }
        } footer: {
            Text("lc.flek.locationSpoofer.section.footer".loc)
        }
    }
}

/// The installed apps, each with the switch that turns Location Spoofer on for
/// it, the one in its own settings. The same apps as FlekJIT's list.
struct FlekLocationSpooferAppsView: View {
    static var countUsingIt: Int {
        FlekJITAppsView.apps.filter { $0.uiSpoofLocation }.count
    }

    @ObservedObject private var model = DataManager.shared.model
    @StateObject private var spooferSwitch = FlekLocationSpooferSwitch()

    var body: some View {
        Form {
            Section {
                if FlekJITAppsView.apps.isEmpty {
                    Text("lc.flek.jit.apps.empty".loc)
                        .foregroundStyle(.secondary)
                }
                ForEach(FlekJITAppsView.apps, id: \.self) { app in
                    Row(app: app, spooferSwitch: spooferSwitch)
                }
            } footer: {
                Text("lc.flek.locationSpoofer.apps.footer".loc)
            }
        }
        .navigationTitle("lc.flek.locationSpoofer.apps.title".loc)
        .navigationBarTitleDisplayMode(.inline)
        .flekLocationSpooferPrompts(spooferSwitch)
    }

    private struct Row: View {
        @ObservedObject var app: LCAppModel
        @ObservedObject var spooferSwitch: FlekLocationSpooferSwitch
        @AppStorage("darkModeIcon", store: LCUtils.appGroupUserDefault) private var darkModeIcon = false

        var body: some View {
            Toggle(isOn: spooferSwitch.binding(for: app)) {
                HStack(spacing: 12) {
                    IconImageView(icon: app.appInfo.iconIsDarkIcon(darkModeIcon))
                        .frame(width: 32, height: 32)
                    Text(app.appInfo.displayName() ?? "")
                    if spooferSwitch.appBeingChecked === app {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            // TweakLoader is what loads it
            .disabled(spooferSwitch.isChecking || (app.uiDontInjectTweakLoader && app.uiDontLoadTweakLoader))
        }
    }
}
