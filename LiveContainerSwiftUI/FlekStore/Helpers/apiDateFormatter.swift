//
//  apiDateFormatter.swift
//  LiveContainerSwiftUI
//
//  Created by Alexander Grigoryev on 30.01.2026.
//

import Foundation


let apiDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSS"
    f.locale = Locale(identifier: "en_US_POSIX")
    return f
}()

let displayDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    return f
}()
