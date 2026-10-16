import Foundation

/// Any owner-selected operation that awaits a system service (HealthKit, PhotosPicker, camera
/// image preparation, and future local-only integrations) must retain the profile it started
/// from. A full local-profile deletion may complete while that operation is suspended; its old
/// result must never appear in, or be written to, a newly created profile.
public enum PrivateProfileAsyncOwnershipPolicy {
    public static func mayContinue(
        capturedOwnerID: UUID,
        currentOwnerID: UUID,
        deletionIsInProgressOrCommitted: Bool
    ) -> Bool {
        capturedOwnerID == currentOwnerID && !deletionIsInProgressOrCommitted
    }
}

/// App-private deletion and UI continuations both run on the main actor. This gate closes the
/// gap between a suspended task returning and an old screen mutating a binding that now belongs
/// to another profile. It contains only UUID tombstones; it never stores health data, photos,
/// a name, or another personal field, and never touches an operating-system service itself.
@MainActor
public enum PrivateProfileAsyncOwnershipGate {
    private static var deletingOwnerIDs: Set<UUID> = []
    private static var deletedOwnerIDs: Set<UUID> = []

    public static func beginDeletion(of ownerID: UUID) {
        deletingOwnerIDs.insert(ownerID)
    }

    /// A failed local deletion leaves the profile intact, so a later explicit owner action can
    /// proceed. A committed deletion can never be reopened for that old owner ID in this process.
    public static func cancelDeletion(of ownerID: UUID) {
        guard !deletedOwnerIDs.contains(ownerID) else { return }
        deletingOwnerIDs.remove(ownerID)
    }

    public static func commitDeletion(of ownerID: UUID) {
        deletingOwnerIDs.remove(ownerID)
        deletedOwnerIDs.insert(ownerID)
    }

    public static func mayContinue(capturedOwnerID: UUID, currentOwnerID: UUID) -> Bool {
        PrivateProfileAsyncOwnershipPolicy.mayContinue(
            capturedOwnerID: capturedOwnerID,
            currentOwnerID: currentOwnerID,
            deletionIsInProgressOrCommitted: deletingOwnerIDs.contains(capturedOwnerID)
                || deletedOwnerIDs.contains(capturedOwnerID)
        )
    }
}
