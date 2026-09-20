import AppKit
import SwiftUI
import XCTest
@testable import Caret

final class ActionsPanelLayoutTests: XCTestCase {
    @MainActor
    func testPanelFitsSmallAndOffsetDisplays() {
        for screen in [
            CGRect(x: 0, y: 38, width: 1512, height: 906),
            CGRect(x: -1280, y: 60, width: 1280, height: 720),
            CGRect(x: 400, y: -800, width: 280, height: 240)
        ] {
            for point in [screen.origin, CGPoint(x: screen.maxX, y: screen.maxY), CGPoint(x: screen.midX, y: screen.midY)] {
                for size in [CGSize(width: 300, height: 340), CGSize(width: 400, height: 324)] {
                    let frame = CaretPanel.fittedFrame(near: point, size: size, visibleFrame: screen)
                    XCTAssertTrue(screen.insetBy(dx: 12, dy: 12).contains(frame), "\(frame) exceeds \(screen)")
                    XCTAssertGreaterThan(frame.width, 0)
                    XCTAssertGreaterThan(frame.height, 0)
                    XCTAssertLessThanOrEqual(frame.width, size.width)
                    XCTAssertLessThanOrEqual(frame.height, size.height)
                }
            }
        }
    }

    @MainActor
    func testBrowseViewportFitsHeaderAndKeepsLastRowReachable() throws {
        _ = NSApplication.shared
        for height in [CGFloat(216), 340, 560] {
            for headerHeight in [CGFloat(30), 64] {
                let view = NSHostingView(rootView: ActionsBrowseLayout {
                    Text("Search actions").frame(height: headerHeight)
                } rows: {
                    LazyVStack(spacing: 2) {
                        ForEach(0..<20) { row in
                            Text("Action \(row)").frame(height: 34)
                        }
                    }
                })
                view.sizingOptions = []
                let window = NSWindow(
                    contentRect: CGRect(x: 0, y: 0, width: 300, height: height),
                    styleMask: [.borderless], backing: .buffered, defer: false
                )
                window.contentView = view
                view.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.02))
                view.layoutSubtreeIfNeeded()
                let scroll = try XCTUnwrap(descendants(view).compactMap { $0 as? NSScrollView }.first)
                let viewport = scroll.convert(scroll.bounds, to: view)
                XCTAssertTrue(view.bounds.contains(viewport), "Viewport \(viewport) exceeds panel \(view.bounds)")
                XCTAssertLessThanOrEqual(viewport.height, height - headerHeight - 22)
                let document = try XCTUnwrap(scroll.documentView)
                XCTAssertGreaterThan(document.bounds.height, scroll.contentView.bounds.height)
                let bottom = document.bounds.maxY - scroll.contentView.bounds.height
                scroll.contentView.scroll(to: CGPoint(x: 0, y: bottom))
                scroll.reflectScrolledClipView(scroll.contentView)
                XCTAssertEqual(scroll.documentVisibleRect.maxY, document.bounds.maxY, accuracy: 1)
            }
        }
    }

    @MainActor
    private func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }
}
