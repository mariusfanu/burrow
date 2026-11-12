import SwiftUI

/// A command’s result when its log stays visible.
struct CompletionBanner: View {
    let run: RunController
    @Binding var showsDetails: Bool

    var body: some View {
        HStack(spacing: Theme.Space.item) {
            Image(systemName: run.completionSymbol)
                .font(.title2)
                .foregroundStyle(run.completionTint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(run.completionBannerHeadline)
                    .font(.title3)
                    .bold()
                Text(run.completionDetail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if showsDetails, !run.keepsLogAtEnd {
                Button("Hide Details") { showsDetails = false }
                    .buttonStyle(.link)
            }
        }
        .padding([.horizontal, .top], Theme.Space.page)
        .padding(.bottom, Theme.Space.item)
    }
}
