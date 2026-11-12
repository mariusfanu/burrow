import SwiftUI

/// The first thing a tool shows: one symbol, one sentence, and one button. The symbol draws
/// itself in when the page appears.
struct ToolIntro<Actions: View>: View {
    let symbol: String
    let title: String
    let message: String
    var errorMessage: String?
    @ViewBuilder var actions: Actions

    @State private var isDrawn = false

    var body: some View {
        ContentUnavailableView {
            Label {
                Text(title)
            } icon: {
                Image(systemName: symbol)
                    .foregroundStyle(Color.accentColor)
                    .symbolEffect(.drawOn, isActive: !isDrawn)
            }
        } description: {
            Text(message)
        } actions: {
            VStack(spacing: Theme.Space.cluster) {
                if let errorMessage {
                    InlineNotice(text: errorMessage, tint: .red)
                        .frame(maxWidth: 440)
                }
                actions
            }
        }
        .onAppear {
            isDrawn = false
            withAnimation(.easeOut(duration: Motion.isReduced ? 0 : 0.9)) { isDrawn = true }
        }
    }
}
