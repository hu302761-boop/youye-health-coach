import Foundation

/// 两阶段删除：只暂存本资料引用的 App 私有照片，删除私有 JSON/owner 指针成功后才提交照片删除。
/// 资料删除失败时会恢复照片目录，避免留下“记录还在但照片没了”的半完成状态。反过来，一旦
/// owner JSON 已成功删除，最终暂存清理即使受文件系统中断也不能把“资料已删除”错误地报成失败：
/// 照片已经离开可读目录，只会留在 App 私有隔离暂存区，后续启动会继续清理。
public enum LocalDataDeletion {
    /// App-private UI preferences which belong to the local coaching profile rather than to the
    /// operating system.  Deleting all local coach data must not let a newly created profile
    /// inherit a prior owner's real-time voice choice.  This intentionally excludes system
    /// permissions (camera/HealthKit/notifications), Photos.app, Apple Health, and any other
    /// app's defaults.
    /// The original beta stored this setting under one global key.  New records must never
    /// reuse that value across profiles, but an existing single-profile installation may
    /// migrate it once when that same loaded profile opens live coaching.
    public static let legacyAppPrivatePreferenceKeys = ["livePoseVoiceCuesEnabled"]

    /// A preference key belongs to an owner just as private meal photos do.  Do not use a
    /// display name here: it may change and is not an ownership boundary.
    public static func voiceCuePreferenceKey(for ownerID: UUID) -> String {
        "livePoseVoiceCuesEnabled.\(ownerID.uuidString)"
    }

    /// Migrates the former one-device setting only for an already-loaded owner.  The caller is
    /// responsible for calling this after the matching private profile exists; onboarding never
    /// reads the legacy key, so a newly created profile cannot inherit a deleted owner's choice.
    public static func migrateLegacyVoiceCuePreferenceIfNeeded(
        for ownerID: UUID,
        defaults: UserDefaults = .standard
    ) {
        let scopedKey = voiceCuePreferenceKey(for: ownerID)
        // A current scoped value is authoritative.  Still discard any legacy residue: leaving it
        // behind would create a second, ambiguous source that a later fresh profile could read.
        guard defaults.object(forKey: scopedKey) == nil else {
            legacyAppPrivatePreferenceKeys.forEach(defaults.removeObject(forKey:))
            return
        }
        guard let legacyValue = defaults.object(forKey: legacyAppPrivatePreferenceKeys[0]) as? Bool else { return }
        defaults.set(legacyValue, forKey: scopedKey)
        legacyAppPrivatePreferenceKeys.forEach(defaults.removeObject(forKey:))
    }
    /// The JSON record can be deleted before a filesystem interruption prevents final disposal
    /// of its already-isolated owner photo staging directory. Keep only UUIDs for that narrow
    /// cleanup on the next launch; this is not a profile, photo reference, or shareable datum.
    public static let pendingOwnerPhotoDeletionIDsDefaultsKey = "youye.healthCoach.pendingOwnerPhotoDeletionIDs"

    /// Launch recovery must distinguish a profile that still exists from one whose delete did
    /// commit. An unreadable record is deliberately neither: touching staged photos in that
    /// situation could make a recoverable profile less recoverable.
    public enum OwnerDataRecordState: Sendable {
        case present, absent, unreadable
    }

    public static func deleteAll(
        data: PrivateCoachData,
        photoStore: PrivateMealPhotoStore? = nil,
        defaults: UserDefaults = .standard,
        deleteData: (PrivateCoachData) throws -> Void = { try CoachPrivateStorage.deleteLastOwnerData($0) }
    ) throws {
        let photoStore = try photoStore ?? PrivateMealPhotoStore.forOwner(data.profile.id)
        guard photoStore.canManagePhotos(for: data.profile.id) else {
            // Never infer an owner from a supplied photo store. In particular, do not stage the
            // directory and then discover the mismatch after files have moved: the caller must
            // provide the matching owner store before any private photo or JSON state changes.
            throw PrivateMealPhotoStore.StoreError.ownerMismatch
        }
        if photoStore.isOwnerScoped {
            try deleteOwnerScopedData(data: data, photoStore: photoStore, defaults: defaults, deleteData: deleteData)
            return
        }
        let references = data.unplannedMealLogs.map(\.localPhotoReference)
            + data.actualMealLogs.map(\.localPhotoReference)
            + data.mealSubstitutions.map(\.localIngredientPhotoReference)
            + data.availableIngredients.map(\.localPhotoReference)
        // Clear any transaction folder left after an earlier successful owner-data deletion.
        // This touches only App-private staged photos, never the system photo library.
        try photoStore.purgePendingStagedDeletions()
        let stagedPhotos = try photoStore.stageReferencedPhotosForDeletion(references: references)
        do {
            try deleteData(data)
        } catch {
            try? photoStore.restoreStagedReferencedPhotos(stagedPhotos)
            throw error
        }
        // The owner record no longer exists even if final staged-file disposal encounters a
        // filesystem interruption. Clear profile-owned UI choices at the same durable boundary
        // instead of allowing a fresh profile to inherit them after a retry. The staged files are
        // no longer readable by the deleted owner, so final removal is a continuation task, not
        // a reason to misreport an already-completed data deletion to the UI.
        clearAppPrivatePreferences(for: data.profile.id, defaults: defaults)
        do {
            try photoStore.commitStagedReferencedPhotoDeletion(stagedPhotos)
        } catch {
            try? photoStore.purgePendingStagedDeletions()
        }
    }

    private static func clearAppPrivatePreferences(for ownerID: UUID, defaults: UserDefaults) {
        defaults.removeObject(forKey: voiceCuePreferenceKey(for: ownerID))
        // The legacy key is not read by a newly created profile.  Remove it at the same durable
        // deletion boundary so an interrupted upgrade cannot later migrate a deleted owner's
        // setting into any profile.  It is intentionally the only non-owner-scoped compatibility
        // key; all current preferences above are owner-scoped.
        legacyAppPrivatePreferenceKeys.forEach(defaults.removeObject(forKey:))
    }

    /// Modern records use an owner-exclusive directory. Staging the whole directory is both more
    /// complete than walking JSON references and safer than an unbounded App-wide cleanup: any
    /// orphan from a previously interrupted write belongs only to this owner and is deleted with
    /// the rest of the requested profile. The JSON/pointer is deleted before final disposal; a
    /// failed data deletion restores the untouched directory.
    private static func deleteOwnerScopedData(
        data: PrivateCoachData,
        photoStore: PrivateMealPhotoStore,
        defaults: UserDefaults,
        deleteData: (PrivateCoachData) throws -> Void
    ) throws {
        try photoStore.purgePendingStagedDeletions()
        // Write the recovery intent before moving files. If the process stops at any later
        // point, launch can inspect the owner record: restore photos when it still exists, or
        // complete the isolated disposal only once its JSON/pointer are gone.
        recordPendingOwnerPhotoDeletion(data.profile.id, defaults: defaults)
        let stagedDirectory: URL?
        do {
            stagedDirectory = try photoStore.stageAllPrivatePhotosForDeletion()
        } catch {
            clearPendingOwnerPhotoDeletion(data.profile.id, defaults: defaults)
            throw error
        }
        do {
            try deleteData(data)
        } catch {
            try? photoStore.restoreStagedDeletion(stagedDirectory)
            clearPendingOwnerPhotoDeletion(data.profile.id, defaults: defaults)
            throw error
        }
        // See the legacy-reference branch above: successful owner-record deletion is the point
        // at which local profile preferences must be reset. Never restore staged photos once
        // that boundary has passed; a failed final disposal stays App-private and is retried on
        // a later launch, while the caller truthfully continues to first-run setup.
        clearAppPrivatePreferences(for: data.profile.id, defaults: defaults)
        do {
            try photoStore.commitStagedDeletion(stagedDirectory)
            clearPendingOwnerPhotoDeletion(data.profile.id, defaults: defaults)
        } catch {
            // The owner record is already gone. The staged directory remains unreadable from
            // normal App paths and the next launch will remove it using the owner UUID marker.
        }
    }

    /// Called during launch after the private store is available. It can only touch the exact
    /// owner staging directory named by a local marker: a present record restores that owner's
    /// private photos, an absent record completes disposal, and an unreadable record is left
    /// untouched. No path creates a profile directory, accesses Photos.app, or inspects another
    /// owner's normal photo directory.
    public static func recoverPendingOwnerPhotoDeletions(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        photoBaseDirectory: URL? = nil,
        recordState: (UUID) -> OwnerDataRecordState
    ) {
        let rawIDs = defaults.stringArray(forKey: pendingOwnerPhotoDeletionIDsDefaultsKey) ?? []
        var remaining: [String] = []
        for rawID in rawIDs {
            guard let ownerID = UUID(uuidString: rawID) else { continue }
            do {
                switch recordState(ownerID) {
                case .present:
                    guard try PrivateMealPhotoStore.restorePendingOwnerScopedDeletion(
                        for: ownerID,
                        baseDirectory: photoBaseDirectory,
                        fileManager: fileManager
                    ) else {
                        remaining.append(rawID)
                        continue
                    }
                case .absent:
                    try PrivateMealPhotoStore.purgePendingOwnerScopedDeletions(
                        for: ownerID,
                        baseDirectory: photoBaseDirectory,
                        fileManager: fileManager
                    )
                    // The owner record was already removed. Finish the same profile-scoped
                    // preference cleanup even if the prior process stopped before this line.
                    clearAppPrivatePreferences(for: ownerID, defaults: defaults)
                case .unreadable:
                    remaining.append(rawID)
                    continue
                }
            } catch {
                remaining.append(rawID)
            }
        }
        if remaining.isEmpty {
            defaults.removeObject(forKey: pendingOwnerPhotoDeletionIDsDefaultsKey)
        } else {
            defaults.set(remaining, forKey: pendingOwnerPhotoDeletionIDsDefaultsKey)
        }
    }

    private static func recordPendingOwnerPhotoDeletion(_ ownerID: UUID, defaults: UserDefaults) {
        var IDs = defaults.stringArray(forKey: pendingOwnerPhotoDeletionIDsDefaultsKey) ?? []
        guard !IDs.contains(ownerID.uuidString) else { return }
        IDs.append(ownerID.uuidString)
        defaults.set(IDs, forKey: pendingOwnerPhotoDeletionIDsDefaultsKey)
    }

    private static func clearPendingOwnerPhotoDeletion(_ ownerID: UUID, defaults: UserDefaults) {
        let remaining = (defaults.stringArray(forKey: pendingOwnerPhotoDeletionIDsDefaultsKey) ?? [])
            .filter { $0 != ownerID.uuidString }
        if remaining.isEmpty {
            defaults.removeObject(forKey: pendingOwnerPhotoDeletionIDsDefaultsKey)
        } else {
            defaults.set(remaining, forKey: pendingOwnerPhotoDeletionIDsDefaultsKey)
        }
    }
}
