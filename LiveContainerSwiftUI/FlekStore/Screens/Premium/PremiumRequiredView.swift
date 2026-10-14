//
//  PremiumRequiredView.swift
//  LiveContainerSwiftUI
//
//  Created by Alexander Grigoryev on 30.01.2026.
//

import SwiftUI

struct PremiumRequiredView: View {
    /// Another way to the same end that needs no Premium, offered under how
    /// to get it. `action` runs while the sheet is still up, so anything it
    /// would present has to wait until the sheet has gone.
    struct Alternative {
        let text: String
        let buttonTitle: String
        let action: () -> Void
    }

    @Environment(\.dismiss) private var dismiss

    /// What Premium is needed for.
    var message = "Premium Access is required to download applications from external sources."
    var alternative: Alternative?
    
    var body: some View {
        VStack {
            Image("premiumLogo")
                .resizable()
                .frame(width: 100, height: 100)
                .cornerRadius(20)
                .shadow(radius: 10)
            
            
            Text(message)
                .font(Font.title3.bold())
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .padding(.vertical)
            
            Text("Open the FlekSt0re app -> Device -> in the Services section, click the Premium Access button")
                .font(Font.caption)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            
            Image("premiumSuggestion")
                .resizable()
                .scaledToFit()
                // Smaller where there is more to fit under it.
                .frame(maxWidth: .infinity, maxHeight: alternative == nil ? 250 : 170)
                .shadow(radius: 10)
                .padding()
            
            if let alternative {
                Text(alternative.text)
                    .font(Font.caption)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)

                Button(alternative.buttonTitle) {
                    alternative.action()
                    dismiss()
                }
                .buttonStyle(.bordered)
                .padding(.top, 4)
            }

            Button {
                dismiss()
            } label: {
                Text("Got it")
                    .font(.title3.bold())
                    .frame(maxWidth: .infinity, maxHeight: 40)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .padding()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
            }
        }
    }
}

#Preview {
    PremiumRequiredView()
}
