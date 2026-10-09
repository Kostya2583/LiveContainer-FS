//
//  FlekStikDebugGuideView.swift
//  LiveContainerSwiftUI
//
//  The article "Need Help?" opens on the JIT page while StikDebug is the chosen
//  enabler: how to set StikDebug up, from installing it to an app running with
//  JIT, with links to what it sends the reader to and pictures of what they
//  will see.
//
//  It only explains. StikDebug is another app, and nothing it needs can be set
//  up or checked from FlekDeck, unlike built-in JIT, whose setup is the JIT
//  page's own steps.
//
//  It goes in three chapters, what to get, connecting StikDebug and using it
//  from FlekDeck, with one thing to do and one picture per step. What can go
//  wrong is told in notes after the steps it can go wrong at, not as steps.
//
//  The pictures are screenshots in the asset catalog, each named StikDebugGuide
//  and a number: whole screens, of which a step shows the part it is about.
//  One that is not there takes no room.
//

import SwiftUI

struct FlekStikDebugGuideView: View {
    private struct Reference: Identifiable {
        let title: String
        let url: URL
        var id: URL { url }
    }

    /// The part of a screenshot between two heights, each a fraction of the
    /// whole from its top. The width is kept, so text is the same size in
    /// every picture.
    private struct Shot: Hashable {
        let number: Int
        let top: CGFloat
        let bottom: CGFloat

        init(_ number: Int, _ top: CGFloat = 0, _ bottom: CGFloat = 1) {
            self.number = number
            self.top = top
            self.bottom = bottom
        }

        var name: String { "StikDebugGuide\(number)" }
    }

    /// A card of the article: a step, or a note on the steps before it.
    private struct Entry: Identifiable {
        enum Mark {
            case number(Int)
            case symbol(String)
        }

        /// What its strings are filed under.
        let id: String
        let mark: Mark
        let title: String
        /// With **bold** runs for the names of things to tap.
        let body: String
        var links: [Reference] = []
        var shots: [Shot] = []
    }

    private struct Chapter: Identifiable {
        let id: String
        let title: String
        let entries: [Entry]
    }

    private static let pairingGuideURL = URL(string: "https://github.com/StikDebug/StikDebug-Guide/blob/main/pairing_file.md")!
    private static let discordURL = URL(string: "https://discord.gg/ZnNcrRT3M8")!
    private static let projectURL = URL(string: "https://github.com/StikDebug/StikDebug")!

    /// Whether JIT takes a script on this device, which is when an app's
    /// settings are worth a step for it. Read once: it asks the device tree.
    private static let needsScript = LCUtils.isTXMScriptRequired()

    /// Steps are numbered as they come, so one left out leaves no gap.
    private static var chapters: [Chapter] {
        var count = 0
        func step(_ key: String, links: [Reference] = [], shots: [Shot] = []) -> Entry {
            count += 1
            return entry(key, mark: .number(count), links: links, shots: shots)
        }
        func chapter(_ key: String, _ entries: [Entry]) -> Chapter {
            Chapter(id: key, title: "lc.flek.jit.stikdebug.chapter.\(key)".loc, entries: entries)
        }

        let ready = [
            step("install", shots: [Shot(1, 0.30, 0.52)]),
            step("vpn", links: [Reference(title: "lc.flek.jit.stikdebug.getVPN".loc, url: FlekBuiltInJITSection.localDevVPNURL)]),
            step("pairing", links: [Reference(title: "lc.flek.jit.stikdebug.details".loc, url: pairingGuideURL)]),
        ]
        let connect = [
            step("connect", shots: [Shot(3, 0.08, 0.845)]),
            step("import", shots: [Shot(2, 0.12, 0.625)]),
            step("listed", shots: [Shot(4, 0.065, 0.525)]),
            entry("importFails", mark: .symbol("exclamationmark")),
        ]
        var use = [
            step("enabler", shots: [Shot(5, 0.065, 0.62)]),
            step("appSettings", shots: [Shot(6, 0.115, 0.625)]),
            step("launchWithJIT", shots: [Shot(7, 0.52, 0.65)]),
        ]
        if needsScript {
            use.append(step("script", shots: [Shot(10, 0.385, 0.60)]))
        }
        use += [
            step("start", shots: [Shot(8, 0.71, 0.98)]),
            // What StikDebug says, then what the app does.
            step("back", shots: [Shot(4, 0.80, 0.875), Shot(11, 0.07, 0.204)]),
        ]
        let help = [
            entry("stops", mark: .symbol("exclamationmark")),
            entry("more", mark: .symbol("questionmark"),
                  links: [Reference(title: "lc.flek.jit.stikdebug.discord".loc, url: discordURL),
                          Reference(title: "lc.flek.jit.stikdebug.github".loc, url: projectURL)]),
        ]
        return [chapter("ready", ready), chapter("connect", connect), chapter("use", use), chapter("help", help)]
    }

    private static func entry(_ key: String, mark: Entry.Mark, links: [Reference] = [], shots: [Shot] = []) -> Entry {
        Entry(id: key, mark: mark,
              title: "lc.flek.jit.stikdebug.\(key).title".loc,
              body: "lc.flek.jit.stikdebug.\(key).body".loc,
              links: links, shots: shots)
    }

    /// A debug build marks where a screenshot is missing and what to call it,
    /// for whoever is adding them.
#if DEBUG
    private static let marksMissingScreenshots = true
#else
    private static let marksMissingScreenshots = false
#endif

    var body: some View {
        ScrollView {
            // Lazy, for the screenshots: each is a screen's worth of pixels.
            LazyVStack(alignment: .leading, spacing: 16) {
                Text("lc.flek.jit.stikdebug.intro".loc)
                    .font(.system(size: 15))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                ForEach(Self.chapters) { chapter in
                    Text(chapter.title)
                        .font(.system(size: 20, weight: .semibold))
                        .padding(.horizontal, 4)
                        .padding(.top, 8)
                    ForEach(chapter.entries) { entry in
                        card(entry)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .principal) { Text("lc.flek.jit.stikdebug.title".loc).font(.headline) } }
    }

    private func card(_ entry: Entry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                mark(entry.mark)
                VStack(alignment: .leading, spacing: 8) {
                    Text(entry.title)
                        .font(.system(size: 17))
                    Text(emphasizing: entry.body)
                        .font(.system(size: 14))
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(entry.links) { link in
                        Link(link.title, destination: link.url)
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                            .controlSize(.small)
                    }
                }
                // The title's line level with the mark beside it.
                .padding(.top, 3)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Under the text and across the card, not beside the mark, for the
            // width.
            ForEach(entry.shots, id: \.self) { shot in
                picture(shot)
            }
        }
        .padding(16)
        .background(FlekSetupCardBackground())
    }

    @ViewBuilder
    private func mark(_ mark: Entry.Mark) -> some View {
        switch mark {
        case .number(let number):
            Text(verbatim: "\(number)")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.accentColor))
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.orange))
        }
    }

    /// The most room a picture is given. The width is about a card's on a
    /// phone, so a picture is no larger on an iPad than the screen it shows.
    private static let pictureLimit = CGSize(width: 340, height: 460)

    @ViewBuilder
    private func picture(_ shot: Shot) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        if let image = Self.image(for: shot) {
            // A width that keeps it within the height too. A limit on the
            // height itself would not: here a picture is never offered one.
            let width = min(Self.pictureLimit.width, Self.pictureLimit.height * image.size.width / max(image.size.height, 1))
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: width)
                .clipShape(shape)
                .overlay(shape.strokeBorder(Color.primary.opacity(0.1)))
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
        } else if Self.marksMissingScreenshots {
            Text(verbatim: shot.name)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 72)
                .overlay(shape.strokeBorder(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [5])))
        }
    }

    /// Cut out of the screenshot's own pixels, which copies none of them.
    private static func image(for shot: Shot) -> UIImage? {
        guard let whole = UIImage(named: shot.name) else {
            return nil
        }
        guard shot.top > 0 || shot.bottom < 1, let pixels = whole.cgImage else {
            return whole
        }
        let height = CGFloat(pixels.height)
        let band = CGRect(x: 0, y: (shot.top * height).rounded(),
                          width: CGFloat(pixels.width), height: ((shot.bottom - shot.top) * height).rounded())
        guard let part = pixels.cropping(to: band) else {
            return whole
        }
        return UIImage(cgImage: part, scale: whole.scale, orientation: whole.imageOrientation)
    }
}
