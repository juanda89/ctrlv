import SwiftUI

struct APIKeyTutorialSheet: View {
    let provider: ProviderType
    @Environment(\.dismiss) private var dismiss
    @State private var animatePulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "film.stack.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(MenuTheme.blue)
                Text(provider.apiKeyHelpTitle)
                    .font(.system(size: 18, weight: .bold))

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Text(provider.apiKeyHelpSubtitle)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { index in
                    Capsule()
                        .fill(MenuTheme.blue.opacity(0.5))
                        .frame(width: 6, height: animatePulse ? 20 : 8)
                        .animation(
                            .easeInOut(duration: 0.7)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.08),
                            value: animatePulse
                        )
                }
                Text("Quick setup tutorial")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(MenuTheme.blue.opacity(0.08))
            )

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(provider.apiKeyHelpSteps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(index + 1).")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.secondary)
                        Text(step)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )

            if let url = provider.apiKeyHelpURL {
                Link(destination: url) {
                    Label("Open \(provider.rawValue) key page", systemImage: "arrow.up.right.square")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }

            Button("Done") {
                dismiss()
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(16)
        .frame(width: 360)
        .onAppear {
            animatePulse = true
        }
    }
}
