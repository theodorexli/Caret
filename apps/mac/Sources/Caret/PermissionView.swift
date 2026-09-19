import SwiftUI

struct PermissionView: View {
    let executablePath: String
    let onOpenSettings: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "sparkle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color(red: 0.26, green: 0.52, blue: 0.98))
                Text("Allow Caret in supported apps")
                    .font(.title3.weight(.semibold))
                Spacer()
            }

            Text("Accessibility lets Caret read the focused field and selection so it can place suggestions beside your work. You choose which actions to accept.")
                .font(.callout)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Open Accessibility Settings and turn on Caret.")
                    .fontWeight(.medium)
                Text("If Caret is already enabled but cannot connect, quit Caret, remove its old entry, add this copy again, then reopen Caret.")
                    .foregroundStyle(.secondary)
                Text("Current executable")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(executablePath)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            }
            .font(.callout)

            HStack {
                Button("Not now", action: onDismiss)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Open Accessibility Settings", action: onOpenSettings)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 440)
        // The permission panel starts at 320pt; keep recovery steps from truncating.
        .fixedSize(horizontal: false, vertical: true)
    }
}
