import Foundation

public protocol PrivateCoachDataStore: Sendable {
    func load(ownerID: UUID) throws -> PrivateCoachData?
    func save(_ data: PrivateCoachData) throws
    func delete(ownerID: UUID) throws
}

/// A launch-time outcome deliberately distinguishes a genuinely empty App from an existing
/// profile that could not be decoded.  Treating both as “start a new profile” risks hiding a
/// recoverable private record and then replacing the last-owner pointer on the next save.
public enum PrivateCoachDataLoadOutcome: Sendable, Equatable {
    case absent
    case loaded(PrivateCoachData)
    case unreadable

    public static func resolve(_ loader: () throws -> PrivateCoachData?) -> PrivateCoachDataLoadOutcome {
        do {
            return try loader().map(Self.loaded) ?? .absent
        } catch {
            return .unreadable
        }
    }
}

/// iOS target 可将此实现的根目录设为 Application Support；不使用共享目录。
public final class JSONPrivateCoachDataStore: PrivateCoachDataStore, @unchecked Sendable {
    public enum StoreError: Error, Sendable, Equatable {
        /// The filename owner is the storage access boundary. A payload claiming a different
        /// profile identity is corrupt or misplaced and must never be migrated, re-saved under
        /// a new filename, or treated as an empty first-run profile.
        case ownerIdentityMismatch
    }
    private let directory: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(directory: URL, fileManager: FileManager = .default) throws {
        self.directory = directory
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder.dateDecodingStrategy = .iso8601
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try applyPrivateDirectoryProtection()
    }

    public func load(ownerID: UUID) throws -> PrivateCoachData? {
        let url = fileURL(for: ownerID)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try Self.validatingOwner(
            decoder.decode(PrivateCoachData.self, from: Data(contentsOf: url)),
            expectedOwnerID: ownerID
        )
    }

    /// Kept separate from disk I/O so the same identity invariant is directly regression-testable.
    /// A caller must not repair a mismatch by trusting either side: recovery remains read-only
    /// until the actual private record is restored by its owner.
    public static func validatingOwner(
        _ data: PrivateCoachData,
        expectedOwnerID: UUID
    ) throws -> PrivateCoachData {
        guard data.profile.id == expectedOwnerID else { throw StoreError.ownerIdentityMismatch }
        return data
    }

    public func save(_ data: PrivateCoachData) throws {
        let url = fileURL(for: data.profile.id)
        let encoded = try encoder.encode(data)
        // iOS provides complete file protection for the private profile.  The same flag is not
        // supported by macOS atomic writes (Foundation fails while creating its sibling temp
        // file), where the native target instead relies on its App Sandbox directory.
        var options: Data.WritingOptions = [.atomic]
        #if os(iOS)
        options.insert(.completeFileProtection)
        #endif
        try encoded.write(to: url, options: options)
    }

    public func delete(ownerID: UUID) throws {
        try PrivateExport.deleteAll(at: fileURL(for: ownerID), fileManager: fileManager)
    }

    private func fileURL(for ownerID: UUID) -> URL {
        directory.appendingPathComponent("coach-private-\(ownerID.uuidString).json", isDirectory: false)
    }

    /// iOS file protection applies to every private JSON payload on write.  Mark the containing
    /// directory as complete-protection as well, so a future auxiliary private file cannot be
    /// silently created with a weaker default.  macOS uses its separately sandboxed container;
    /// `NSFileProtection` is an iOS/iPadOS data-protection feature.
    private func applyPrivateDirectoryProtection() throws {
        #if os(iOS)
        try fileManager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: directory.path)
        #endif
    }
}

/// 正式 iPhone target 的默认私有位置：Application Support，不使用共享目录或云端同步。
/// 当前内测是“一台设备一个本地档案”，不是账号系统，也没有同机切换用户入口；朋友
/// 应在各自设备上独立建立资料，不能把同一设备当成多人共用档案。
public enum CoachPrivateStorage {
    public static let lastOwnerIDDefaultsKey = "youye.healthCoach.lastOwnerID"

    /// A nonempty but invalid launch pointer is materially different from a first install.  If
    /// it were treated as `absent`, completing onboarding would replace the pointer and make a
    /// possibly recoverable private profile harder to find.  Keep that situation on the same
    /// fail-closed recovery path as an unreadable JSON record instead.
    public enum LastOwnerPointerResolution: Sendable, Equatable {
        case absent
        case valid(UUID)
        case malformed
    }

    public static func resolveLastOwnerPointer(_ storedOwnerID: String?) -> LastOwnerPointerResolution {
        guard let storedOwnerID else { return .absent }
        guard let ownerID = UUID(uuidString: storedOwnerID) else { return .malformed }
        return .valid(ownerID)
    }

    public enum StorageError: Error, Sendable, Equatable {
        case malformedLastOwnerPointer
        /// A nonempty owner pointer with no matching private JSON is not a first run.  The
        /// missing record may be recoverable (or may indicate an interrupted file operation),
        /// so launch must stay read-only instead of allowing onboarding to replace the pointer.
        case ownerRecordMissingForPointer
    }

    public static func defaultStore(fileManager: FileManager = .default) throws -> JSONPrivateCoachDataStore {
        let root = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return try JSONPrivateCoachDataStore(
            directory: root.appendingPathComponent("YouyeHealthCoach", isDirectory: true),
            fileManager: fileManager
        )
    }

    public static func loadLastOwnerData(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) throws -> PrivateCoachData? {
        let store = try defaultStore(fileManager: fileManager)
        // A process may stop after staging private photos but before deleting the owner JSON.
        // Resolve each saved deletion intent against the actual owner record before touching its
        // isolated staging directory: restore if the profile still exists; purge only after it
        // is absent; preserve everything when the local record itself is unreadable.
        LocalDataDeletion.recoverPendingOwnerPhotoDeletions(
            defaults: defaults,
            fileManager: fileManager,
            recordState: { ownerID in
                do {
                    return try store.load(ownerID: ownerID) == nil ? .absent : .present
                } catch {
                    return .unreadable
                }
            }
        )
        // If a previous privacy deletion removed the owner JSON but final staged-photo disposal
        // was interrupted, finish clearing only the App-private transaction folder on next launch.
        // This cannot access Photos.app or any external user directory.
        let ownerID: UUID
        switch resolveLastOwnerPointer(defaults.string(forKey: lastOwnerIDDefaultsKey)) {
        case .absent:
            return nil
        case let .valid(id):
            ownerID = id
        case .malformed:
            throw StorageError.malformedLastOwnerPointer
        }
        // A valid pointer is evidence that this device previously had an owner.  If its record
        // is missing, fail closed rather than treating the device as a fresh install: otherwise
        // completing onboarding could overwrite the pointer and make recovery harder.
        guard let loaded = try store.load(ownerID: ownerID) else {
            throw StorageError.ownerRecordMissingForPointer
        }
        let ownerPhotoStore = try PrivateMealPhotoStore.forOwner(ownerID, fileManager: fileManager)
        try? ownerPhotoStore.purgePendingStagedDeletions()
        let migration = try PrivateMealPhotoMigration.prepare(data: loaded, ownerPhotoStore: ownerPhotoStore)
        if migration.changed {
            do {
                try store.save(migration.data)
            } catch {
                PrivateMealPhotoMigration.rollbackPreparedImport(migration, ownerPhotoStore: ownerPhotoStore)
                throw error
            }
            PrivateMealPhotoMigration.commitLegacyCleanup(migration, ownerPhotoStore: ownerPhotoStore)
        }
        let resolvedData = migration.data
        // A failed save must never leave an unreachable private meal/ingredient photo forever.
        // Cleanup is intentionally best-effort: an I/O failure here cannot make an otherwise
        // readable profile appear unavailable, and a later launch can retry the same safe scan.
        let activePhotoReferences = resolvedData.unplannedMealLogs.map(\.localPhotoReference)
            + resolvedData.actualMealLogs.map(\.localPhotoReference)
            + resolvedData.mealSubstitutions.map(\.localIngredientPhotoReference)
            + resolvedData.availableIngredients.map(\.localPhotoReference)
        try? ownerPhotoStore.purgeUnreferencedPhotos(references: activePhotoReferences)
        return resolvedData
    }

    /// UI-facing, fail-closed loader. A corrupt/inaccessible existing profile is not silently
    /// replaced with a new writable profile; callers must show recovery guidance first.
    public static func loadLastOwnerDataOutcome(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) -> PrivateCoachDataLoadOutcome {
        PrivateCoachDataLoadOutcome.resolve {
            try loadLastOwnerData(defaults: defaults, fileManager: fileManager)
        }
    }

    public static func saveLastOwnerData(
        _ data: PrivateCoachData,
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) throws {
        try defaultStore(fileManager: fileManager).save(data)
        defaults.set(data.profile.id.uuidString, forKey: lastOwnerIDDefaultsKey)
    }

    /// A deletion request can only clear the launch pointer for the exact owner it removed.
    /// This is intentionally separate and testable: no stale view model or future multi-profile
    /// migration may make another local profile unreachable by clearing its pointer.
    public static func shouldClearLastOwnerPointer(
        deleting ownerID: UUID,
        storedOwnerID: String?
    ) -> Bool {
        resolveLastOwnerPointer(storedOwnerID) == .valid(ownerID)
    }

    public static func deleteLastOwnerData(
        _ data: PrivateCoachData,
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) throws {
        try defaultStore(fileManager: fileManager).delete(ownerID: data.profile.id)
        if shouldClearLastOwnerPointer(
            deleting: data.profile.id,
            storedOwnerID: defaults.string(forKey: lastOwnerIDDefaultsKey)
        ) {
            defaults.removeObject(forKey: lastOwnerIDDefaultsKey)
        }
    }
}
