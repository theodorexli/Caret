import SwiftUI

struct CaretDebugView: View {
    @State private var text = "Loading…"

    var body: some View {
        ScrollView {
            Text(text)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .frame(minWidth: 420, minHeight: 280)
        .onAppear {
            text = HistoryDebug.load(projectRoot: CaretPaths.projectRoot)
        }
    }
}
