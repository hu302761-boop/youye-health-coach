import Foundation

/// Local state machine for a stopped workout draft.
///
/// Older local JSON may still decode legacy Apple Health receipt fields for compatibility, but
/// this type deliberately has no HealthKit-write operation. New training data only creates or
/// removes an owner-controlled, App-private confirmation draft.
public enum HealthWorkoutSyncSafety {
    /// Stops are durable before a training-detail screen can disappear. This is only a local
    /// “decide later” draft: no HealthKit request is made, and it must not coexist with a write
    /// receipt or an uncertain write marker for the same exact timed session.
    public static func recordingConfirmation(
        _ workout: ConfirmedHealthWorkout,
        in data: PrivateCoachData,
        at date: Date = .now
    ) -> PrivateCoachData {
        guard workout.duration > 0,
              !data.healthWorkoutSyncs.contains(where: { $0.sessionID == workout.syncIdentifier }),
              !data.pendingHealthWorkoutSyncs.contains(where: { $0.sessionID == workout.syncIdentifier }),
              !data.pendingWorkoutConfirmations.contains(where: { $0.workout.syncIdentifier == workout.syncIdentifier }) else {
            return data
        }
        var changed = data
        changed.pendingWorkoutConfirmations.append(PendingWorkoutConfirmation(workout: workout, savedAt: date))
        return changed
    }

    /// Discarding a local confirmation draft never touches legacy receipt fields or Apple
    /// Health. Keeping those opaque compatibility values avoids destructive migration.
    public static func discardingConfirmation(
        _ confirmation: PendingWorkoutConfirmation,
        in data: PrivateCoachData
    ) -> PrivateCoachData {
        var changed = data
        changed.pendingWorkoutConfirmations.removeAll { $0.id == confirmation.id }
        return changed
    }
}
