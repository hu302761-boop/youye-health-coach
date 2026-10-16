import Foundation

/// One App-private image reference can appear in restored/imported records more than once even
/// though normal capture creates a fresh UUID. Every deletion path must therefore inspect all
/// private meal record types, not just the type that initiated the deletion.
public enum PrivateMealPhotoReferenceUsage {
    public static func isReferenced(_ reference: String, in data: PrivateCoachData) -> Bool {
        data.unplannedMealLogs.contains { $0.localPhotoReference == reference }
            || data.actualMealLogs.contains { $0.localPhotoReference == reference }
            || data.mealSubstitutions.contains { $0.localIngredientPhotoReference == reference }
            || data.availableIngredients.contains { $0.localPhotoReference == reference }
    }
}

/// 计划外餐食照片的本地私有存储。不会上传、同步或加入可分享周报。
/// 新资料使用 `local-photo://<owner-id>/<photo-id>`。旧版无 owner 引用只在启动迁移期间
/// 被复制进原资料的私有目录；日常读写绝不回退至共享旧目录。
public final class PrivateMealPhotoStore: @unchecked Sendable {
    public enum StoreError: Error, Sendable, Equatable {
        /// A full-profile deletion must never accept an owner-scoped photo store that belongs
        /// to another local profile. This is a caller/programming error, not a reason to guess
        /// which owner's private directory should be removed.
        case ownerMismatch
    }
    /// 仅用于删除事务的 App 私有临时位置；不会出现在导出或用户资料中。
    public struct StagedDeletion: Sendable {
        fileprivate let items: [(original: URL, staged: URL)]
        fileprivate let stagingDirectory: URL?

        fileprivate init(items: [(original: URL, staged: URL)], stagingDirectory: URL?) {
            self.items = items
            self.stagingDirectory = stagingDirectory
        }
    }

    private struct ParsedReference {
        let ownerID: UUID?
        let photoID: UUID
    }

    private let directory: URL
    private let legacyDirectory: URL
    private let ownerID: UUID?
    private let fileManager: FileManager

    /// Owner-scoped stores have their own directory, so a full owner-data deletion can safely
    /// stage that entire directory (including any old interrupted-write remnants) without
    /// touching another beta user's photos. Legacy stores remain reference-only.
    public var isOwnerScoped: Bool { ownerID != nil }

    /// Allows higher-level transactions to prove that a supplied owner-scoped store belongs to
    /// the same private profile they are about to change. Legacy stores intentionally return
    /// true here because their deletion path is reference-scoped rather than directory-scoped.
    public func canManagePhotos(for ownerID: UUID) -> Bool {
        self.ownerID.map { $0 == ownerID } ?? true
    }

    /// 旧版/测试用存储。它只识别无 owner 的旧引用。
    public init(directory: URL, fileManager: FileManager = .default) throws {
        self.directory = directory
        self.legacyDirectory = directory
        self.ownerID = nil
        self.fileManager = fileManager
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try applyPrivateDirectoryProtection()
    }

    /// 新资料使用 owner 私有子目录，绝不与本机的其他内测用户共用照片文件。
    public init(ownerID: UUID, baseDirectory: URL? = nil, fileManager: FileManager = .default) throws {
        let baseDirectory = baseDirectory ?? PrivateMealPhotoStore.defaultBaseDirectory()
        self.directory = baseDirectory.appendingPathComponent(ownerID.uuidString, isDirectory: true)
        self.legacyDirectory = baseDirectory
        self.ownerID = ownerID
        self.fileManager = fileManager
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try applyPrivateDirectoryProtection()
    }

    public static func forOwner(_ ownerID: UUID, fileManager: FileManager = .default) throws -> PrivateMealPhotoStore {
        try PrivateMealPhotoStore(ownerID: ownerID, fileManager: fileManager)
    }

    /// 仅供启动迁移调用：将一份旧无 owner 照片复制到当前 owner 的目录并返回新引用。
    /// 日常 `data` / `delete` 不会读取旧目录，避免一份旧引用被另一份资料利用。
    public func importLegacyPhoto(localReference: String) throws -> String? {
        guard ownerID != nil, let parsed = Self.parse(localReference), parsed.ownerID == nil else { return nil }
        let legacyURL = fileURL(for: parsed.photoID, directory: legacyDirectory)
        guard fileManager.fileExists(atPath: legacyURL.path) else { return nil }
        return try save(data: Data(contentsOf: legacyURL))
    }

    /// 仅供迁移在新资料写入成功后清理旧副本。系统照片图库永不参与。
    public func deleteLegacyPhoto(localReference: String) throws {
        guard ownerID != nil, let parsed = Self.parse(localReference), parsed.ownerID == nil else { return }
        let legacyURL = fileURL(for: parsed.photoID, directory: legacyDirectory)
        guard fileManager.fileExists(atPath: legacyURL.path) else { return }
        try fileManager.removeItem(at: legacyURL)
    }

    /// 可用于 Codable 的输入校验；不代表当前用户有权读取该引用。
    public static func isValidLocalPhotoReference(_ reference: String?) -> Bool {
        guard let reference, let parsed = parse(reference) else { return reference == nil }
        return parsed.ownerID != nil || parsed.photoID.uuidString.isEmpty == false
    }

    public static func isLegacyLocalPhotoReference(_ reference: String?) -> Bool {
        guard let reference, let parsed = parse(reference) else { return false }
        return parsed.ownerID == nil
    }

    /// 由 PhotosPicker 导出的原始图片数据仅保存到当前 owner 的 App 私有目录。
    @discardableResult
    public func save(data: Data) throws -> String {
        let id = UUID()
        // `.completeFileProtection` is an iOS/iPadOS file-protection attribute.  Passing it to
        // a macOS file URL makes Foundation's atomic temporary-file write fail, so the native
        // Mac app could not retain a local meal photo at all.  macOS keeps this directory inside
        // the app sandbox; iPhone/iPad retain the stronger at-rest protection.
        var options: Data.WritingOptions = [.atomic]
        #if os(iOS)
        options.insert(.completeFileProtection)
        #endif
        try data.write(to: fileURL(for: id, directory: directory), options: options)
        if let ownerID { return "local-photo://\(ownerID.uuidString)/\(id.uuidString)" }
        return "local-photo://\(id.uuidString)"
    }

    public func data(for localReference: String) throws -> Data? {
        guard let url = accessibleFileURL(for: localReference), fileManager.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    public func delete(localReference: String) throws {
        guard let url = accessibleFileURL(for: localReference), fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    /// 删除用户资料时，按日志中的本地引用逐张清理，不触及设备照片图库。
    public func deleteAll(references: [String?]) throws {
        for reference in references {
            if let reference { try delete(localReference: reference) }
        }
    }

    /// Removes only this owner's unreferenced App-private photo files after a durable profile
    /// load. This repairs the narrow failure window where an image was copied locally but the
    /// matching JSON transaction could not be saved (and its immediate rollback also failed).
    /// It never scans Photos.app, another owner's directory, staging folders, or unrecognised
    /// files. References retained by a reverted substitution deliberately remain live until the
    /// owner explicitly completes that record's deletion.
    public func purgeUnreferencedPhotos(references: [String?]) throws {
        guard ownerID != nil, fileManager.fileExists(atPath: directory.path) else { return }
        // Compare the file names after the owner/UUID validation above. FileManager may return
        // file-reference URLs with different identity semantics from the path URLs constructed
        // by `fileURL(for:directory:)`; the deterministic UUID filename is the safer key here.
        let retainedFileNames = Set(references.compactMap { accessibleFileURL(for: $0)?.lastPathComponent })
        let candidates = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        for candidate in candidates {
            let values = try candidate.resourceValues(forKeys: [.isRegularFileKey])
            // Fail closed for files the store did not create.  A UUID-named .private-photo file
            // is the only normal payload written by `save(data:)` in an owner directory.
            guard values.isRegularFile == true,
                  candidate.pathExtension == "private-photo",
                  UUID(uuidString: candidate.deletingPathExtension().lastPathComponent) != nil,
                  !retainedFileNames.contains(candidate.lastPathComponent) else { continue }
            try fileManager.removeItem(at: candidate)
        }
    }

    /// 只暂存当前 owner 明确引用的照片；跨 owner 引用和系统图库均不会被触及。
    public func stageReferencedPhotosForDeletion(references: [String?]) throws -> StagedDeletion {
        let urls = Set(references.compactMap { accessibleFileURL(for: $0) })
        guard !urls.isEmpty else { return StagedDeletion(items: [], stagingDirectory: nil) }
        let stagingDirectory = directory.deletingLastPathComponent()
            .appendingPathComponent("\(stagingPrefix)\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        var items: [(original: URL, staged: URL)] = []
        do {
            for original in urls where fileManager.fileExists(atPath: original.path) {
                let staged = stagingDirectory.appendingPathComponent(original.lastPathComponent, isDirectory: false)
                try fileManager.moveItem(at: original, to: staged)
                items.append((original, staged))
            }
            return StagedDeletion(items: items, stagingDirectory: stagingDirectory)
        } catch {
            try? restoreStagedReferencedPhotos(StagedDeletion(items: items, stagingDirectory: stagingDirectory))
            throw error
        }
    }

    public func commitStagedReferencedPhotoDeletion(_ staged: StagedDeletion) throws {
        guard let directory = staged.stagingDirectory, fileManager.fileExists(atPath: directory.path) else { return }
        try fileManager.removeItem(at: directory)
    }

    public func restoreStagedReferencedPhotos(_ staged: StagedDeletion) throws {
        for item in staged.items where fileManager.fileExists(atPath: item.staged.path) && !fileManager.fileExists(atPath: item.original.path) {
            try fileManager.moveItem(at: item.staged, to: item.original)
        }
        if let directory = staged.stagingDirectory, fileManager.fileExists(atPath: directory.path) { try? fileManager.removeItem(at: directory) }
    }

    /// 仅清理此 owner 自己的中断删除事务。不会枚举或触及其他 owner、系统相册或外部目录。
    public func purgePendingStagedDeletions() throws {
        let parent = directory.deletingLastPathComponent()
        guard fileManager.fileExists(atPath: parent.path) else { return }
        let candidates = try fileManager.contentsOfDirectory(at: parent, includingPropertiesForKeys: [.isDirectoryKey], options: [])
        // Every staging name includes the owner UUID (or the exact legacy prefix).  Require the
        // full expected prefix, so a crafted/foreign directory with a similar generic name can
        // never be removed by this owner's launch-time cleanup.
        let expectedPrefix = stagingPrefix
        for candidate in candidates where candidate.lastPathComponent.hasPrefix(expectedPrefix) {
            let values = try candidate.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else { continue }
            try fileManager.removeItem(at: candidate)
        }
    }

    /// Finishes a previously committed full-profile deletion without creating a new owner photo
    /// directory. This is intentionally a static, owner-scoped cleanup: after the JSON and the
    /// last-owner pointer are gone, launch code must still be able to remove only the deleted
    /// owner's isolated transaction folder, never another beta user's files or Photos.app data.
    public static func purgePendingOwnerScopedDeletions(
        for ownerID: UUID,
        baseDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) throws {
        let base = baseDirectory ?? defaultBaseDirectory()
        guard fileManager.fileExists(atPath: base.path) else { return }
        let expectedPrefix = ".PrivateMealPhotos-deleting-owner-\(ownerID.uuidString)-"
        let candidates = try fileManager.contentsOfDirectory(
            at: base,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        )
        for candidate in candidates where candidate.lastPathComponent.hasPrefix(expectedPrefix) {
            let values = try candidate.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else { continue }
            try fileManager.removeItem(at: candidate)
        }
    }

    /// Restores a whole owner directory if profile deletion never committed. This is the inverse
    /// of the exact-owner purge above and is intentionally available only to launch recovery:
    /// a still-readable owner JSON means staged photos remain part of that owner's private data.
    /// If a live owner directory already exists or staging is ambiguous, fail closed and leave
    /// the marker for a later retry rather than deleting or merging private files.
    public static func restorePendingOwnerScopedDeletion(
        for ownerID: UUID,
        baseDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> Bool {
        let base = baseDirectory ?? defaultBaseDirectory()
        guard fileManager.fileExists(atPath: base.path) else { return true }
        let expectedPrefix = ".PrivateMealPhotos-deleting-owner-\(ownerID.uuidString)-"
        let candidates = try fileManager.contentsOfDirectory(
            at: base,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ).filter {
            $0.lastPathComponent.hasPrefix(expectedPrefix)
                && (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
        guard !candidates.isEmpty else { return true }
        let liveDirectory = base.appendingPathComponent(ownerID.uuidString, isDirectory: true)
        guard !fileManager.fileExists(atPath: liveDirectory.path), candidates.count == 1,
              let stagedDirectory = candidates.first else {
            return false
        }
        try fileManager.moveItem(at: stagedDirectory, to: liveDirectory)
        return true
    }

    /// 目录级 API 只限当前 owner（或旧版单用户目录）使用；正式删除流程优先按引用删除。
    public func deleteAllPrivatePhotos() throws {
        guard fileManager.fileExists(atPath: directory.path) else { return }
        try fileManager.removeItem(at: directory)
    }

    public func stageAllPrivatePhotosForDeletion() throws -> URL? {
        guard fileManager.fileExists(atPath: directory.path) else { return nil }
        let staged = directory.deletingLastPathComponent().appendingPathComponent("\(stagingPrefix)\(UUID().uuidString)", isDirectory: true)
        try fileManager.moveItem(at: directory, to: staged)
        return staged
    }

    public func commitStagedDeletion(_ stagedDirectory: URL?) throws {
        guard let stagedDirectory, fileManager.fileExists(atPath: stagedDirectory.path) else { return }
        try fileManager.removeItem(at: stagedDirectory)
    }

    public func restoreStagedDeletion(_ stagedDirectory: URL?) throws {
        guard let stagedDirectory, fileManager.fileExists(atPath: stagedDirectory.path), !fileManager.fileExists(atPath: directory.path) else { return }
        try fileManager.moveItem(at: stagedDirectory, to: directory)
    }

    private static func defaultBaseDirectory() -> URL {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        return applicationSupport.appendingPathComponent("YouyeHealthCoach", isDirectory: true).appendingPathComponent("PrivateMealPhotos", isDirectory: true)
    }

    private var stagingPrefix: String {
        ownerID.map { ".PrivateMealPhotos-deleting-owner-\($0.uuidString)-" } ?? ".PrivateMealPhotos-deleting-legacy-"
    }

    private func accessibleFileURL(for reference: String?) -> URL? {
        guard let reference, let parsed = Self.parse(reference) else { return nil }
        if let ownerID {
            guard let referenceOwner = parsed.ownerID, referenceOwner == ownerID else { return nil }
            return fileURL(for: parsed.photoID, directory: directory)
        }
        guard parsed.ownerID == nil else { return nil }
        return fileURL(for: parsed.photoID, directory: directory)
    }

    private func fileURL(for id: UUID, directory: URL) -> URL {
        directory.appendingPathComponent("\(id.uuidString).private-photo", isDirectory: false)
    }

    /// Photos themselves are written with `.completeFileProtection`; protect the owner-scoped
    /// directory too so future local private artifacts do not inherit a weaker default.  This
    /// is deliberately iPhone/iPad-only: the Mac target relies on its App Sandbox instead.
    private func applyPrivateDirectoryProtection() throws {
        #if os(iOS)
        try fileManager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: directory.path)
        #endif
    }

    private static func parse(_ localReference: String) -> ParsedReference? {
        guard localReference.hasPrefix("local-photo://") else { return nil }
        let value = String(localReference.dropFirst("local-photo://".count))
        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
        if parts.count == 1, let photoID = UUID(uuidString: String(parts[0])) { return ParsedReference(ownerID: nil, photoID: photoID) }
        if parts.count == 2, let ownerID = UUID(uuidString: String(parts[0])), let photoID = UUID(uuidString: String(parts[1])) {
            return ParsedReference(ownerID: ownerID, photoID: photoID)
        }
        return nil
    }
}
