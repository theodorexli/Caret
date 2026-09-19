import Foundation

struct StoredMemory: Identifiable, Codable, Equatable {
    let id: String
    var text: String
    var sourceApp: String?
    let createdAt: Date

    init(id: String = UUID().uuidString, text: String, sourceApp: String? = nil, createdAt: Date = .now) {
        self.id = id
        self.text = text
        self.sourceApp = sourceApp
        self.createdAt = createdAt
    }
}

struct MemoryRepository {
    private static let storeFileName = "store.json"

    static var memoriesRoot: URL? {
        CaretPaths.memoriesJSONRoot
    }

    func load() -> [StoredMemory] {
        guard let url = storeURL,
              let data = try? Data(contentsOf: url)
        else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let items = try? decoder.decode([StoredMemory].self, from: data) else { return [] }
        return items.sorted { $0.createdAt > $1.createdAt }
    }

    @discardableResult
    func add(text: String, sourceApp: String? = nil) throws -> StoredMemory {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MemoryRepositoryError.emptyText }
        var items = load()
        let memory = StoredMemory(text: trimmed, sourceApp: sourceApp)
        items.insert(memory, at: 0)
        try save(items)
        return memory
    }

    func delete(id: String) throws {
        var items = load()
        items.removeAll { $0.id == id }
        try save(items)
    }

    private var storeURL: URL? {
        guard let root = Self.memoriesRoot else { return nil }
        return root.appendingPathComponent(Self.storeFileName)
    }

    private func save(_ items: [StoredMemory]) throws {
        guard let root = Self.memoriesRoot else { throw MemoryRepositoryError.missingRoot }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        guard let url = storeURL else { throw MemoryRepositoryError.missingRoot }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(items)
        try data.write(to: url)
    }
}

enum MemoryRepositoryError: Error {
    case emptyText
    case missingRoot
}
