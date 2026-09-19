import AppKit
import SwiftUI

struct AppReferenceIcon: View {
    let bundleURL: URL?
    var size: CGFloat = 18

    var body: some View {
        Group {
            if let bundleURL {
                Image(nsImage: InstalledApps.icon(for: bundleURL))
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: size * 0.62, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: size, height: size)
    }
}
