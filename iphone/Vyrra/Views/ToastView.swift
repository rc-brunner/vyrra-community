import SwiftUI

struct ToastView: View {
    let message: String
    var systemImage: String = "checkmark.circle.fill"

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
            Text(message)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        // `success` is lighter in dark mode, so the label flips to black there.
        .foregroundStyle(Color(.systemBackground))
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(VyrraTheme.success, in: Capsule())
        .accessibilityElement(children: .combine)
    }
}
