import BurrowCore
import SwiftUI

/// The app's size with a small bar comparing it to the largest app.
struct UninstallSizeColumn: View {
    let app: InstalledApp
    let state: UninstallModel.SizeState
    let largestSize: Int64
    let model: UninstallModel

    var body: some View {
        VStack(alignment: .trailing, spacing: Theme.Space.tight) {
            switch state {
            case .measured(let size):
                Text(size.fileSize)
                    .font(.callout)
                    .monospacedDigit()
                    .transition(.opacity)
                LevelBar(part: size, of: largestSize, height: 3)
            case .pending:
                ProgressView()
                    .controlSize(.mini)
                    .accessibilityLabel("Measuring")
            case .unavailable:
                Text("—")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Size unavailable")
                    .help("A size isn’t available for this app.")
            case .failed(let message):
                Button("Retry Size", systemImage: "arrow.clockwise", action: retry)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .disabled(model.isMeasuring)
                    .help(message)
                    .accessibilityHint(message)
                Text("Unavailable")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Size unavailable")
                    .accessibilityHint(message)
            }
        }
        .frame(width: 92, alignment: .trailing)
    }

    private func retry() {
        model.retrySize(for: app)
    }
}
