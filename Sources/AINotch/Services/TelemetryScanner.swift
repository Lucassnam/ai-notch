import Foundation

actor TelemetryScanner {
    struct FileSignature: Codable, Equatable, Sendable {
        let size: Int64
        let modifiedAt: TimeInterval
    }

    struct CachedFile: Codable, Sendable {
        let signature: FileSignature
        let provider: ProviderID
        let events: [UsageEvent]
        let limits: [RateLimitWindow]
    }

    struct CacheEnvelope: Codable, Sendable {
        let version: Int
        var files: [String: CachedFile]
    }

    private let fileManager: FileManager
    private let claudeRoot: URL
    private let codexRoot: URL
    private let cacheURL: URL
    private var historyStore: UsageHistoryStore
    /// Version 2 added project attribution; version 3 corrected how the project
    /// name is derived from Claude's mangled directory. A mismatch here is
    /// discarded silently (see `loadCacheIfNeeded`), so bumping it simply forces
    /// a one-time re-parse. The durable history envelope must NOT be bumped in
    /// sympathy — that one throws on mismatch and would brick every later scan.
    private var cache = CacheEnvelope(version: 3, files: [:])
    private var hasLoadedCache = false

    init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        cacheURL: URL? = nil,
        historyURL: URL? = nil,
        pricing: PricingCatalog = .init(),
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        claudeRoot = homeDirectory.appendingPathComponent(".claude/projects", isDirectory: true)
        codexRoot = homeDirectory.appendingPathComponent(".codex/sessions", isDirectory: true)

        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? homeDirectory.appendingPathComponent("Library/Application Support")
        let appSupport = applicationSupport.appendingPathComponent("AINotch", isDirectory: true)
        self.cacheURL = cacheURL ?? appSupport.appendingPathComponent("telemetry-cache.json")
        self.historyStore = UsageHistoryStore(
            historyURL: historyURL ?? appSupport.appendingPathComponent("usage-history.json"),
            pricing: pricing,
            fileManager: fileManager
        )
    }

    func scan() throws -> RawTelemetry {
        try loadCacheIfNeeded()

        let claudeFiles = jsonlFiles(below: claudeRoot)
        let codexFiles = jsonlFiles(below: codexRoot)
        let filesByProvider: [(ProviderID, [URL])] = [
            (.claude, claudeFiles),
            (.codex, codexFiles)
        ]
        let livePaths = Set((claudeFiles + codexFiles).map(\.path))
        var cacheChanged = false

        for (provider, files) in filesByProvider {
            for file in files {
                // A transcript can be deleted between listing and reading, or
                // be unreadable. Either one used to fail the whole scan, so the
                // notch froze on its last figures. Keep its cached events, if
                // any, and move on.
                guard let signature = try? signature(for: file) else { continue }
                if cache.files[file.path]?.signature == signature { continue }

                guard let data = try? Data(contentsOf: file, options: [.mappedIfSafe]) else {
                    continue
                }
                let parsed: CachedFile

                switch provider {
                case .claude:
                    parsed = CachedFile(
                        signature: signature,
                        provider: provider,
                        events: TelemetryParser.parseClaude(
                            data: data,
                            fileID: file.lastPathComponent,
                            project: Self.projectName(for: file, below: claudeRoot)
                        ),
                        limits: []
                    )
                case .codex:
                    let result = TelemetryParser.parseCodex(data: data, fileID: file.lastPathComponent)
                    parsed = CachedFile(
                        signature: signature,
                        provider: provider,
                        events: result.events,
                        limits: result.limits
                    )
                }

                cache.files[file.path] = parsed
                cacheChanged = true
            }
        }

        let stalePaths = cache.files.keys.filter { !livePaths.contains($0) }
        if !stalePaths.isEmpty {
            stalePaths.forEach { cache.files.removeValue(forKey: $0) }
            cacheChanged = true
        }

        if cacheChanged {
            try persistCache()
        }

        var eventsByID: [String: UsageEvent] = [:]
        var limitsByID: [String: RateLimitWindow] = [:]

        for cachedFile in cache.files.values {
            for event in cachedFile.events {
                if let existing = eventsByID[event.id] {
                    if event.tokens.total > existing.tokens.total {
                        eventsByID[event.id] = event
                    }
                } else {
                    eventsByID[event.id] = event
                }
            }

            for limit in cachedFile.limits {
                if let existing = limitsByID[limit.id] {
                    if limit.observedAt > existing.observedAt {
                        limitsByID[limit.id] = limit
                    }
                } else {
                    limitsByID[limit.id] = limit
                }
            }
        }

        let durable = try historyStore.merge(liveEvents: Array(eventsByID.values))

        return RawTelemetry(
            events: durable.events,
            limits: Array(limitsByID.values),
            sourceFiles: [
                .claude: claudeFiles.count,
                .codex: codexFiles.count
            ],
            recordedCosts: durable.recordedCosts
        )
    }

    private func loadCacheIfNeeded() throws {
        guard !hasLoadedCache else { return }
        hasLoadedCache = true

        guard fileManager.fileExists(atPath: cacheURL.path) else { return }
        let data = try Data(contentsOf: cacheURL)
        guard let decoded = try? JSONDecoder().decode(CacheEnvelope.self, from: data),
              decoded.version == cache.version else { return }
        cache = decoded
    }

    private func persistCache() throws {
        let directory = cacheURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(cache)
        try data.write(to: cacheURL, options: .atomic)
    }

    /// Claude stores transcripts under a path-mangled project directory, e.g.
    /// `~/.claude/projects/-Users-alice-Desktop-trajectory/session.jsonl`. The
    /// leaf segment is the working directory name, which is what a person
    /// recognises. Nested session directories are walked back up to the
    /// immediate child of the projects root.
    ///
    /// The mangling maps both `/` and `_` to `-`, so it is lossy. A home
    /// directory like `/Users/ada_99` becomes `-Users-ada-99`, whose last
    /// segment is the meaningless `99`. Stripping the mangled home prefix
    /// first avoids that; an account name containing `_` can still split a
    /// project name, which no amount of parsing can recover from the path
    /// alone.
    static func projectName(for file: URL, below root: URL) -> String? {
        let rootComponents = root.standardizedFileURL.pathComponents
        let fileComponents = file.standardizedFileURL.pathComponents
        guard fileComponents.count > rootComponents.count,
              Array(fileComponents.prefix(rootComponents.count)) == rootComponents
        else { return nil }

        let directory = fileComponents[rootComponents.count]
        guard directory != file.lastPathComponent else { return nil }

        // root is <home>/.claude/projects
        let home = root.deletingLastPathComponent().deletingLastPathComponent()
        let mangledHome = mangle(home.standardizedFileURL.path)

        var remainder = directory
        if remainder == mangledHome {
            return "Home"
        }
        if remainder.hasPrefix(mangledHome + "-") {
            remainder = String(remainder.dropFirst(mangledHome.count + 1))
        }

        let leaf = remainder
            .split(separator: "-", omittingEmptySubsequences: true)
            .last
            .map(String.init)
        guard let leaf, !leaf.isEmpty else { return nil }
        return leaf
    }

    private static func mangle(_ path: String) -> String {
        path
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "_", with: "-")
    }

    private func jsonlFiles(below root: URL) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        return enumerator.compactMap { item in
            guard let url = item as? URL, url.pathExtension == "jsonl" else { return nil }
            return url
        }
    }

    private func signature(for url: URL) throws -> FileSignature {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return FileSignature(
            size: Int64(values.fileSize ?? 0),
            modifiedAt: values.contentModificationDate?.timeIntervalSince1970 ?? 0
        )
    }
}
