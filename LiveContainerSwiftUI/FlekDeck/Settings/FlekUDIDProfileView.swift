//
//  FlekUDIDProfileView.swift
//  LiveContainerSwiftUI
//
//  The sheet shown for getting the UDID with the profile: the steps iOS takes
//  the user through, from downloading the profile to coming back. The first
//  step has the button that downloads it, so that what is about to happen
//  is read before it does.
//
//  FlekSt0re's server takes the device's answer, and FlekDeck collects the UDID
//  from it when the user is back, see FlekUDIDProfile. Once it is in, what
//  shows this sheet closes it.
//
//  The download itself happens in Safari inside FlekDeck, FlekInAppSafari,
//  over this sheet: handed to the system, the address would reach the
//  default browser, which need not be Safari, and no other browser takes a
//  configuration profile.
//

import SafariServices
import SwiftUI

/// Safari inside FlekDeck, presented over whatever is showing.
enum FlekInAppSafari {
    /// The delegate of the page showing, which the page does not retain.
    private static var closeHandler: CloseHandler?
    /// The page showing, while it is.
    private static weak var page: SFSafariViewController?

    /// Opens `url`, then calls `onClose` once the user has closed it and it is
    /// off screen. Hands `url` to the system instead when there is nothing to
    /// present from.
    static func open(_ url: URL, onClose: @escaping () -> Void) {
        guard let presenter = topViewController() else {
            UIApplication.shared.open(url)
            return
        }
        let safari = SFSafariViewController(url: url)
        let handler = CloseHandler(onClose: onClose)
        safari.delegate = handler
        closeHandler = handler
        page = safari
        whenSettled(presenter) {
            presenter.present(safari, animated: true)
        }
    }

    /// Closes the page showing as its Done button would, for a site that
    /// sends the user back to FlekDeck itself, and says whether there was
    /// one. Closed this way, it does not tell its delegate.
    @discardableResult
    static func close() -> Bool {
        guard let page, let presenter = page.presentingViewController, let handler = closeHandler else {
            return false
        }
        closeHandler = nil
        page.dismiss(animated: true) {
            handler.finish(after: presenter)
        }
        return true
    }

    /// The top of the key window's presentations, leaving out one on its way
    /// off screen, such as the alert that led here.
    private static func topViewController() -> UIViewController? {
        var top = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .windows.first { $0.isKeyWindow }?
            .rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }

    /// Runs `body` once `controller` is done with any transition under way,
    /// since presenting during one is refused.
    private static func whenSettled(_ controller: UIViewController?, _ body: @escaping () -> Void) {
        if let coordinator = controller?.transitionCoordinator {
            coordinator.animate(alongsideTransition: nil) { _ in body() }
        } else {
            body()
        }
    }

    private final class CloseHandler: NSObject, SFSafariViewControllerDelegate {
        private let onClose: () -> Void

        init(onClose: @escaping () -> Void) {
            self.onClose = onClose
        }

        func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
            FlekInAppSafari.closeHandler = nil
            finish(after: controller.presentingViewController)
        }

        /// Calls `onClose` once the page is off screen. The page is told it
        /// is done before it leaves; what comes next presents once it has.
        func finish(after presenter: UIViewController?) {
            DispatchQueue.main.async { [onClose] in
                FlekInAppSafari.whenSettled(presenter, onClose)
            }
        }
    }
}

struct FlekUDIDProfileView: View {
    private struct Step: Identifiable {
        let id: Int
        let title: String
        /// With **bold** runs, as the design sets the names of things to tap.
        let body: String
    }

    private static var steps: [Step] {
        (1...5).map { number in
            Step(id: number,
                 title: "lc.flek.udidProfile.step\(number).title".loc,
                 body: "lc.flek.udidProfile.step\(number).body".loc)
        }
    }

    @Environment(\.dismiss) private var dismiss

    /// The download page has been opened and closed again.
    @State private var hasDownloaded = false
    /// There was no page to open for the profile.
    @State private var downloadFailed = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("lc.flek.udidProfile.intro".loc)
                        .font(.system(size: 15))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                    ForEach(Self.steps) { step in
                        // The first step is done from here; the rest are iOS's.
                        if step.id == 1 {
                            stepCard(step, isDone: hasDownloaded) {
                                downloadButton
                            }
                        } else {
                            stepCard(step) {
                                EmptyView()
                            }
                        }
                    }
                    securityDelayNote
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("lc.flek.udidProfile.title".loc)
                        .font(.headline)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("lc.common.close".loc)
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .alert("lc.flek.udidProfile.failedTitle".loc, isPresented: $downloadFailed) {
            Button("lc.common.ok".loc, role: .cancel) {}
        } message: {
            Text("lc.flek.udidProfile.failedMessage".loc)
        }
        .apply { sheet in
            // The grabber the design draws. It is iOS 16 API, so the result is
            // erased: left in the static type, iOS 15 would trap resolving it
            // before the availability check ever ran.
            if #available(iOS 16.0, *) {
                AnyView(sheet.presentationDragIndicator(.visible))
            } else {
                AnyView(sheet)
            }
        }
    }

    /// Downloads the profile: the one filled button while that is still to
    /// do, and a quieter one for doing it again, as a profile left too long
    /// is dropped by iOS.
    @ViewBuilder
    private var downloadButton: some View {
        if hasDownloaded {
            Button("lc.flek.udidProfile.downloadAgain".loc, action: downloadProfile)
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
        } else {
            Button("lc.flek.udidProfile.download".loc, action: downloadProfile)
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
        }
    }

    /// Opens the download of the UDID profile in Safari inside FlekDeck, over
    /// this sheet, which is back with the steps that are left once the page
    /// is closed.
    private func downloadProfile() {
        guard let page = FlekUDIDProfile.startRequest() else {
            downloadFailed = true
            return
        }
        FlekInAppSafari.open(page) {
            hasDownloaded = true
        }
    }

    /// Stolen Device Protection may hold back installing a profile for an hour
    /// away from familiar places: longer than iOS keeps a downloaded profile,
    /// so the download has to be started again after.
    private var securityDelayNote: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.orange))
            VStack(alignment: .leading, spacing: 8) {
                Text("lc.flek.udidProfile.securityDelay.title".loc)
                    .font(.system(size: 17))
                Text(emphasizing: "lc.flek.udidProfile.securityDelay.body".loc)
                    .font(.system(size: 14))
                    .fixedSize(horizontal: false, vertical: true)
            }
            // The title's line level with the mark beside it.
            .padding(.top, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(FlekSetupCardBackground())
    }

    /// A step: its number, or a check once it is done, what it is, and under
    /// that whatever it is done with from here.
    private func stepCard<Action: View>(_ step: Step, isDone: Bool = false,
                                        @ViewBuilder action: () -> Action) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if isDone {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                } else {
                    Text(verbatim: "\(step.id)")
                        .font(.system(size: 15, weight: .semibold))
                }
            }
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(Circle().fill(isDone ? Color.green : Color.accentColor))
            VStack(alignment: .leading, spacing: 8) {
                Text(step.title)
                    .font(.system(size: 17))
                Text(emphasizing: step.body)
                    .font(.system(size: 14))
                    .fixedSize(horizontal: false, vertical: true)
                action()
                    .padding(.top, 4)
            }
            // The title's line level with the number beside it.
            .padding(.top, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(FlekSetupCardBackground())
    }
}

/// Getting the UDID with the profile: asking whether to, and then the steps,
/// the first of which downloads it. Hung from whatever offers it: General's
/// device row, and the Premium sheet, as a subscription is for a UDID.
/// Setting `isAsked` starts it.
struct FlekUDIDRetrieval: ViewModifier {
    @Binding var isAsked: Bool
    @State private var guideShown = false

    func body(content: Content) -> some View {
        content
            .alert("lc.flek.general.udid.addTitle".loc, isPresented: $isAsked) {
                Button("lc.flek.premium.installProfile".loc) {
                    // Once the question has gone.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        guideShown = true
                    }
                }
                .keyboardShortcut(.defaultAction)
                Button("lc.common.cancel".loc, role: .cancel) {}
            } message: {
                Text("lc.flek.premium.promptMessage".loc)
            }
            .sheet(isPresented: $guideShown) {
                FlekUDIDProfileView()
            }
            // The UDID is in, and the steps have nothing left to say.
            .onReceive(FlekUDIDProfile.udidReceived) { _ in
                guideShown = false
            }
    }
}

extension View {
    func flekUDIDRetrieval(isAsked: Binding<Bool>) -> some View {
        modifier(FlekUDIDRetrieval(isAsked: isAsked))
    }
}
