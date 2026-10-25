//
//  apiDateFormatter.swift
//  LiveContainerSwiftUI
//
//  Created by Alexander Grigoryev on 30.01.2026.
//

import Foundation

extension DateFormatter {
    static let deviceServiceFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0) // adjust if needed
        return formatter
    }()

    /// A date as FlekSt0re's services write one. A device record adds
    /// fractions of a second, "2026-11-13 11:51:33.000000", which the format
    /// above does not take, so they are left off: an end date that cannot be
    /// read would count as Premium without end.
    static func deviceServiceDate(from text: String) -> Date? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let date = deviceServiceFormatter.date(from: text) {
            return date
        }
        guard let fraction = text.firstIndex(of: ".") else {
            return nil
        }
        return deviceServiceFormatter.date(from: String(text[..<fraction]))
    }
}
