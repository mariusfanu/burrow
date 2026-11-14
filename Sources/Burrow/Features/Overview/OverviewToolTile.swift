import SwiftUI

struct OverviewToolTile: View {
    let screen: Screen
    let fact: String
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoverCount = 0

    var body: some View {
        Button(action: open) {
            Surface(padding: Theme.Space.card) {
                HStack(spacing: Theme.Space.cluster) {
                    Image(systemName: screen.symbol)
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                        .symbolEffect(.bounce, options: .speed(1.4), value: hoverCount)
                        .frame(width: 30)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: Theme.Space.micro) {
                        Text(screen.title)
                            .font(.body)
                            .bold()
                        Text(fact)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .contentTransition(.numericText())
                            .animation(Motion.snap(reduced: reduceMotion), value: fact)
                    }
                    Spacer(minLength: 0)
                }
            }
            .modifier(PointerGlow(color: .accentColor, strength: 0.1, radius: 160))
            .clipShape(.rect(cornerRadius: Theme.Radius.card))
        }
        .buttonStyle(SurfaceButtonStyle())
        .onHover(perform: hover)
        .accessibilityHint(fact == screen.summary ? "" : screen.summary)
    }

    private func open() {
        app.selection = screen
    }

    private func hover(_ inside: Bool) {
        if inside, !Motion.isReduced(reduceMotion) { hoverCount += 1 }
    }
}
