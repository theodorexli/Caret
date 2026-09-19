import Combine
import Foundation

@MainActor
final class ModifierChordState: ObservableObject {
    @Published private(set) var commandOptionHeld = false

    func setCommandOptionHeld(_ held: Bool) {
        guard commandOptionHeld != held else { return }
        commandOptionHeld = held
    }
}
