import Foundation
import SwiftData

@MainActor
final class SwiftDataCaptureRepository: CaptureRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func all() -> [CaptureRecord] {
        let descriptor = FetchDescriptor<CaptureRecord>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }

    func filtered(status: CaptureStatus?) -> [CaptureRecord] {
        if let status {
            let predicate = #Predicate<CaptureRecord> { $0.resultStatus == status }
            let descriptor = FetchDescriptor<CaptureRecord>(
                predicate: predicate,
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
            return (try? context.fetch(descriptor)) ?? []
        }

        return all()
    }

    func latest() -> CaptureRecord? {
        all().first
    }

    func add(_ record: CaptureRecord) {
        context.insert(record)
        saveIfNeeded()
    }

    func update(_ record: CaptureRecord) {
        _ = record
        saveIfNeeded()
    }

    func delete(_ record: CaptureRecord) {
        context.delete(record)
        saveIfNeeded()
    }

    func deleteAll() {
        for record in all() {
            context.delete(record)
        }
        saveIfNeeded()
    }

    func purge(before date: Date) {
        let predicate = #Predicate<CaptureRecord> { $0.createdAt < date }
        let descriptor = FetchDescriptor<CaptureRecord>(predicate: predicate)
        let records = (try? context.fetch(descriptor)) ?? []
        for record in records {
            context.delete(record)
        }
        saveIfNeeded()
    }

    private func saveIfNeeded() {
        do {
            try context.save()
        } catch {
            print("Failed to save capture history: \(error)")
        }
    }
}
