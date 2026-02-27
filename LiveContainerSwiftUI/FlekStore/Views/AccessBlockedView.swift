import SwiftUI

struct AccessBlockedView: View {
    let reason: String
    let message: String

    init(reason: String, message: String) {
        self.reason = reason
        self.message = message
    }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    Image(systemName: "exclamationmark.octagon.fill")
                        .font(.system(size: 52, weight: .semibold))
                        .foregroundStyle(.red)

                    Text("Access blocked")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.85)
                        .lineLimit(2)

                    VStack(alignment: .leading, spacing: 16) {
                        Text("Reason: \(reason)")
                            .font(.title3.bold())
                            .foregroundStyle(.white)

                        Text(message)
                            .font(.body)
                            .foregroundStyle(Color.white.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(22)
                    .background(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(Color.white.opacity(0.12))
                    )
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
            }
        }
    }
}

#Preview {
    AccessBlockedView(
        reason: "dispute",
        message: "Your device's access to the service has been limited due to a chargeback through a bank or contacting a merchant."
    )
}
