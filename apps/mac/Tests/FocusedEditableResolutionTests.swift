import XCTest
@testable import Caret

final class FocusedEditableResolutionTests: XCTestCase {
    private final class Node {
        let editable: Bool
        let children: [Node]
        weak var parent: Node?

        init(editable: Bool = false, children: [Node] = []) {
            self.editable = editable
            self.children = children
            for child in children { child.parent = self }
        }
    }

    private func resolve(_ node: Node) -> Node? {
        AXHelpers.resolveEditable(startingAt: node, isEditable: { $0.editable }, children: { $0.children }, parent: { $0.parent })
    }

    func testBlurToSiblingControlDoesNotRediscoverPreviousInput() {
        let field = Node(editable: true)
        let button = Node()
        let window = Node(children: [field, Node(children: [button])])
        withExtendedLifetime(window) {
            XCTAssertNil(resolve(button))
            XCTAssertTrue(resolve(field) === field)
        }
    }

    func testFocusedEditorWrapperCanResolveItsTextChild() {
        let field = Node(editable: true)
        let wrapper = Node(children: [Node(children: [field])])
        XCTAssertTrue(resolve(wrapper) === field)
    }

    func testEditorInternalChildResolvesEditableAncestorWithoutVisitingSibling() {
        let child = Node()
        let field = Node(editable: true, children: [child])
        let unrelated = Node(editable: true)
        let window = Node(children: [unrelated, field])
        withExtendedLifetime(window) {
            XCTAssertTrue(resolve(child) === field)
        }
    }

    func testParentCycleAndBroadTreesStayBounded() {
        let node = Node()
        node.parent = node
        XCTAssertNil(resolve(node))
        let broad = Node(children: (0..<300).map { _ in Node() } + [Node(editable: true)])
        XCTAssertNil(resolve(broad))
    }
}
