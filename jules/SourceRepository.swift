import Foundation
import Combine
import GRDB

/// Repository for managing sources with offline-first support
@MainActor
class SourceRepository: ObservableObject {
    private let dbQueue: DatabasePool
    private let apiService: APIService

    // Publishers
    var sourcesPublisher: AnyPublisher<[Source], Error> {
        sourcesSubject.eraseToAnyPublisher()
    }
    private let sourcesSubject = CurrentValueSubject<[Source], Error>([])

    @Published var isLoading: Bool = false
    @Published var lastSyncTime: Date?
    private var isRefreshInProgress = false
    private var pendingForcedRefresh = false
    private var lastRefreshAttemptTime: Date?
    private let minimumRefreshInterval: TimeInterval = 5

    private var cancellables: Set<AnyCancellable> = []

    init(dbQueue: DatabasePool, apiService: APIService) {
        self.dbQueue = dbQueue
        self.apiService = apiService

        setupObservation()
        loadLastSyncTime()
    }

    private func loadLastSyncTime() {
        lastSyncTime = UserDefaults.standard.object(forKey: "sources_last_sync_time") as? Date
    }

    private func saveLastSyncTime() {
        lastSyncTime = Date()
        UserDefaults.standard.set(lastSyncTime, forKey: "sources_last_sync_time")
    }

    private func setupObservation() {
        // Observe source table changes
        let observation = ValueObservation.tracking { db in
            try Source.order(Column("name")).fetchAll(db)
        }

        observation.publisher(in: dbQueue)
            // CRITICAL FIX: GRDB ValueObservation emits on every database transaction
            // that could affect observed data, even if the data hasn't changed.
            // Without deduplication, this can cause excessive SwiftUI view updates.
            // Source conforms to Equatable, so removeDuplicates() compares arrays.
            .removeDuplicates()
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        print("Source database observation error: \(error)")
                    }
                },
                receiveValue: { [weak self] sources in
                    self?.sourcesSubject.send(sources)
                }
            )
            .store(in: &cancellables)
    }

    /// Returns cached sources from the database
    func getCachedSources() async -> [Source] {
        do {
            return try await dbQueue.read { db in
                try Source.order(Column("name")).fetchAll(db)
            }
        } catch {
            print("Error reading cached sources: \(error)")
            return []
        }
    }

    /// Fetches sources from API and updates the local cache
    /// Returns the sources (from cache if API fails when offline)
    @discardableResult
    func refresh(force: Bool = false) async -> [Source] {
        // Prevent overlapping source refreshes from concurrent call sites.
        guard !isRefreshInProgress else {
            // Queue one forced refresh to run after the in-flight request completes.
            // This is important when credentials switch while a request is running.
            if force {
                pendingForcedRefresh = true
            }
            return await getCachedSources()
        }

        // Soft rate limit to avoid hammering the API when multiple UI events trigger refresh.
        if !force, let lastRefreshAttemptTime {
            let elapsed = Date().timeIntervalSince(lastRefreshAttemptTime)
            if elapsed < minimumRefreshInterval {
                let cached = await getCachedSources()
                if !cached.isEmpty {
                    return cached
                }
            }
        }

        isRefreshInProgress = true
        lastRefreshAttemptTime = Date()
        isLoading = true
        defer {
            isRefreshInProgress = false
            isLoading = false
            if pendingForcedRefresh {
                pendingForcedRefresh = false
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    _ = await self.refresh(force: true)
                }
            }
        }

        do {
            let fetchedSources = try await apiService.fetchSources()

            // Only update if we got valid data
            if !fetchedSources.isEmpty {
                try await dbQueue.write { db in
                    // Clear existing sources and insert fresh data
                    try Source.deleteAll(db)
                    for source in fetchedSources {
                        try source.save(db)
                    }
                }
                lastRefreshAttemptTime = Date()
                saveLastSyncTime()
                return fetchedSources
            } else {
                // API returned empty, fall back to cached data
                return await getCachedSources()
            }
        } catch {
            print("Error fetching sources from API: \(error)")
            // Return cached sources when API fails (offline scenario)
            return await getCachedSources()
        }
    }

    /// Checks if we have cached sources available
    func hasCachedSources() async -> Bool {
        do {
            let count = try await dbQueue.read { db in
                try Source.fetchCount(db)
            }
            return count > 0
        } catch {
            return false
        }
    }

    /// Gets a specific source by ID from cache
    func getSource(byId id: String) async -> Source? {
        do {
            return try await dbQueue.read { db in
                try Source.fetchOne(db, key: id)
            }
        } catch {
            print("Error fetching source by ID: \(error)")
            return nil
        }
    }

    /// Gets a specific source by name from cache
    func getSource(byName name: String) async -> Source? {
        do {
            return try await dbQueue.read { db in
                try Source.filter(Column("name") == name).fetchOne(db)
            }
        } catch {
            print("Error fetching source by name: \(error)")
            return nil
        }
    }
}
