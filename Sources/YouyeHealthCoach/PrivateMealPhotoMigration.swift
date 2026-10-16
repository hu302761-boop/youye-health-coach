import Foundation

/// 升级前的照片引用没有 owner。该迁移仅在加载该资料时将其复制进该资料自己的目录，
/// 先持久化改写后的 JSON，才清除旧副本；日常读取绝不回退到旧共享目录。
public enum PrivateMealPhotoMigration {
    public struct Result: Sendable {
        public let data: PrivateCoachData
        public let legacyReferencesToDelete: Set<String>
        public let createdOwnerReferences: Set<String>

        public var changed: Bool { data != originalData }
        fileprivate let originalData: PrivateCoachData
    }

    public static func prepare(
        data: PrivateCoachData,
        ownerPhotoStore: PrivateMealPhotoStore
    ) throws -> Result {
        // This migration copies files and may later remove legacy originals, so it has a stricter
        // boundary than reference-only legacy deletion: it must run only inside the exact
        // profile owner's modern directory. A wrong or unscoped store must not turn missing
        // imports into silently cleared references.
        guard ownerPhotoStore.isOwnerScoped,
              ownerPhotoStore.canManagePhotos(for: data.profile.id) else {
            throw PrivateMealPhotoStore.StoreError.ownerMismatch
        }
        var migrated = data
        var references: [String: String] = [:]
        var oldReferences: Set<String> = []
        var createdReferences: Set<String> = []

        func migratedReference(_ oldReference: String?) throws -> String? {
            guard let oldReference, PrivateMealPhotoStore.isLegacyLocalPhotoReference(oldReference) else { return oldReference }
            if let cached = references[oldReference] { return cached }
            // If the old file is already absent, retain neither a dangling reference nor a
            // route back to the shared legacy directory. This does not delete any existing file.
            guard let newReference = try ownerPhotoStore.importLegacyPhoto(localReference: oldReference) else { return nil }
            references[oldReference] = newReference
            oldReferences.insert(oldReference)
            createdReferences.insert(newReference)
            return newReference
        }

        do {
            for index in migrated.unplannedMealLogs.indices {
                let item = migrated.unplannedMealLogs[index]
                let newReference = try migratedReference(item.localPhotoReference)
                guard newReference != item.localPhotoReference else { continue }
                migrated.unplannedMealLogs[index] = UnplannedMealLog(
                    id: item.id,
                    date: item.date,
                    localPhotoReference: newReference,
                    userDescription: item.userDescription,
                    estimatedCaloriesRange: item.estimatedCaloriesRange,
                    estimatedProteinGramsRange: item.estimatedProteinGramsRange,
                    confidence: item.confidence,
                    estimateSource: item.estimateSource,
                    isEstimate: item.isEstimate
                )
            }
            for index in migrated.mealSubstitutions.indices {
                let oldReference = migrated.mealSubstitutions[index].localIngredientPhotoReference
                let newReference = try migratedReference(oldReference)
                if newReference != oldReference { migrated.mealSubstitutions[index].localIngredientPhotoReference = newReference }
            }
        } catch {
            // Imports are copies. If a later import fails before a Result can be returned to the
            // caller, clean every copy made in this attempt; legacy files remain untouched.
            for reference in createdReferences { try? ownerPhotoStore.delete(localReference: reference) }
            throw error
        }
        return Result(data: migrated, legacyReferencesToDelete: oldReferences, createdOwnerReferences: createdReferences, originalData: data)
    }

    /// 如果新版资料 JSON 无法写入，删除本次复制出的 owner 文件；旧资料和旧照片均保持原样。
    public static func rollbackPreparedImport(_ result: Result, ownerPhotoStore: PrivateMealPhotoStore) {
        for reference in result.createdOwnerReferences { try? ownerPhotoStore.delete(localReference: reference) }
    }

    /// 只能在 `result.data` 已成功写入当前 owner JSON 后调用。
    public static func commitLegacyCleanup(_ result: Result, ownerPhotoStore: PrivateMealPhotoStore) {
        for reference in result.legacyReferencesToDelete { try? ownerPhotoStore.deleteLegacyPhoto(localReference: reference) }
    }
}
