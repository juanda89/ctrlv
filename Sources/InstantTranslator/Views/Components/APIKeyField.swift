import SwiftUI

struct APIKeyField: View {
    @Binding var apiKey: String
    let placeholder: String
    @State private var isRevealed = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "key.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            Group {
                if isRevealed {
                    TextField(placeholder, text: $apiKey)
                } else {
                    SecureField(placeholder, text: $apiKey)
                }
            }
            .textFieldStyle(.plain)
            .font(.system(size: 12, weight: .regular, design: .monospaced))

            Button {
                isRevealed.toggle()
            } label: {
                Image(systemName: isRevealed ? "eye.slash.fill" : "eye.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }
}
