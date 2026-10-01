//
//  FlekUDIDProfileView.swift
//  LiveContainerSwiftUI
//
//  The sheet General shows while the UDID profile is being installed: the steps
//  iOS takes the user through, from allowing the download to coming back.
//
//  A server takes the device's answer and sends the user back with the UDID,
//  see FlekUDIDProfile. Once it is in, General drops the card this sheet hangs
//  from, which closes it.
//
//  The download itself happens in Safari inside FlekDeck, FlekInAppSafari,
//  before this sheet: handed to the system, the address would reach the
//  default browser, which need not be Safari, and no other browser takes a
//  configuration profile.
//

import SafariServices
import SwiftUI

/// Safari inside FlekDeck, presented over whatever is showing.
enum FlekInAppSafari {
    /// The delegate of the page showing, which the page does not retain.
    private static var closeHandler: CloseHandler?

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
        whenSettled(presenter) {
            presenter.present(safari, animated: true)
        }
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
            let presenter = controller.presentingViewController
            FlekInAppSafari.closeHandler = nil
            // The page is told before it leaves the screen; what comes next
            // presents once it has.
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

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("lc.flek.udidProfile.intro".loc)
                        .font(.system(size: 15))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                    ForEach(Self.steps) { step in
                        stepCard(step)
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

    /// Stolen Device Protection may hold back installing a profile for an hour
    /// away from familiar places: longer than iOS keeps a downloaded profile,
    /// or FlekDeck serves one, so the download has to be started again after.
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

    private func stepCard(_ step: Step) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(verbatim: "\(step.id)")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.accentColor))
            VStack(alignment: .leading, spacing: 8) {
                Text(step.title)
                    .font(.system(size: 17))
                Text(emphasizing: step.body)
                    .font(.system(size: 14))
                    .fixedSize(horizontal: false, vertical: true)
            }
            // The title's line level with the number beside it.
            .padding(.top, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(FlekSetupCardBackground())
    }
}
