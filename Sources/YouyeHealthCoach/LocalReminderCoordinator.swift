import Foundation

/// These reminder definitions intentionally contain only a generic next-action prompt. They do
/// not put health state, food, location, prices, photos, or plan details into system alerts.
public enum DailyReminderKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case breakfast, lunch, dinner, training, bedtimePreparation

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .breakfast: "第一餐"
        case .lunch: "午餐/饭盒"
        case .dinner: "晚餐"
        case .training: "训练或恢复"
        case .bedtimePreparation: "睡前准备"
        }
    }

    /// Notification identifiers are scoped to the private profile rather than being shared by
    /// every profile ever created on this device.  The identifier is internal metadata only;
    /// no owner name, health state, address, food, or plan detail appears in the alert itself.
    fileprivate func identifier(for ownerID: UUID) -> String {
        "youye-health-coach.\(ownerID.uuidString.lowercased()).reminder.\(rawValue)"
    }

    /// Versions before profile-scoped identifiers used these five IDs.  Keep the exact legacy
    /// list solely so an update or a deletion can remove an old pending alert once; new alerts
    /// are never created with these IDs.
    fileprivate var legacyIdentifier: String { "youye-health-coach.reminder.\(rawValue)" }
}

public struct LocalReminderRequest: Sendable, Equatable, Identifiable {
    public let kind: DailyReminderKind
    public let hour: Int
    public let minute: Int

    public var id: DailyReminderKind { kind }
    public var timeText: String { String(format: "%02d:%02d", hour, minute) }
}

public enum DailyReminderPlan {
    public static func requests(
        schedule: DailyRoutineSchedule?,
        preferences: DailyReminderPreferences
    ) -> [LocalReminderRequest] {
        guard let schedule else { return [] }
        return [
            request(.breakfast, at: schedule.breakfastMinutes, enabled: preferences.breakfastEnabled, quiet: schedule),
            request(.lunch, at: schedule.lunchMinutes, enabled: preferences.lunchEnabled, quiet: schedule),
            request(.dinner, at: schedule.dinnerMinutes, enabled: preferences.dinnerEnabled, quiet: schedule),
            request(.training, at: schedule.trainingMinutes, enabled: preferences.trainingEnabled, quiet: schedule),
            request(.bedtimePreparation, at: schedule.bedtimePreparationMinutes, enabled: preferences.bedtimePreparationEnabled, quiet: schedule)
        ].compactMap { $0 }
    }

    public static func unavailableReason(
        schedule: DailyRoutineSchedule?,
        preferences: DailyReminderPreferences
    ) -> String? {
        guard preferences.hasAnyEnabled else { return "未开启任何本机提醒。" }
        guard let schedule else { return "请先保存时间表；未创建任何系统提醒。" }
        let allEnabled = [
            (preferences.breakfastEnabled, schedule.breakfastMinutes),
            (preferences.lunchEnabled, schedule.lunchMinutes),
            (preferences.dinnerEnabled, schedule.dinnerMinutes),
            (preferences.trainingEnabled, schedule.trainingMinutes),
            (preferences.bedtimePreparationEnabled, schedule.bedtimePreparationMinutes)
        ]
        return allEnabled.contains { $0.0 && isQuiet($0.1, in: schedule) }
            ? "静默时段内的提醒不会被自动改到其他时间。请调整时间表或关闭该提醒。"
            : nil
    }

    private static func request(_ kind: DailyReminderKind, at minutes: Int, enabled: Bool, quiet schedule: DailyRoutineSchedule) -> LocalReminderRequest? {
        guard enabled, !isQuiet(minutes, in: schedule) else { return nil }
        return LocalReminderRequest(kind: kind, hour: minutes / 60, minute: minutes % 60)
    }

    /// Endpoints are deliberately treated as quiet. For a cross-midnight interval such as
    /// 23:30–09:00, 23:30 through 08:59 is quiet; an equal start/end means no quiet interval.
    public static func isQuiet(_ minutes: Int, in schedule: DailyRoutineSchedule) -> Bool {
        let start = schedule.quietStartMinutes
        let end = schedule.quietEndMinutes
        guard start != end else { return false }
        if start < end { return minutes >= start && minutes < end }
        return minutes >= start || minutes < end
    }
}

#if canImport(UserNotifications)
import UserNotifications

/// Serializes App-owned notification mutations across asynchronous system calls.  `add` and
/// `remove` are not a transaction in UserNotifications; without this small gate, an old settings
/// task could finish after profile deletion and recreate a reminder.  Deleted owner IDs stay
/// blocked for the process lifetime, while a newly created profile receives a new UUID and can
/// opt in normally.
private actor ReminderMutationGate {
    static let shared = ReminderMutationGate()

    private var isBusy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var deletedOwnerIDs: Set<UUID> = []

    func withExclusiveAccess<T: Sendable>(
        ownerID: UUID,
        operation: @Sendable (_ ownerWasDeleted: Bool) async -> T
    ) async -> T {
        await acquire()
        let ownerWasDeleted = deletedOwnerIDs.contains(ownerID)
        let result = await operation(ownerWasDeleted)
        release()
        return result
    }

    func deleteAndWithExclusiveAccess<T: Sendable>(
        ownerID: UUID,
        operation: @Sendable () async -> T
    ) async -> T {
        await acquire()
        // Mark before clearing so a waiting settings task cannot later be permitted to add its
        // stale selection after this deletion operation releases the gate.
        deletedOwnerIDs.insert(ownerID)
        let result = await operation()
        release()
        return result
    }

    private func acquire() async {
        guard isBusy else {
            isBusy = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        if waiters.isEmpty {
            isBusy = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}

/// This coordinator is only called after the owner presses the explicit enable action. It clears
/// this App's prior reminder IDs before adding the currently eligible selection, so disabled or
/// quiet-time reminders cannot survive as stale notifications.
public enum LocalReminderCoordinator {
    /// Clears only the five fixed identifiers owned by this App. Removing delivered copies as
    /// well as pending requests matters when a profile is deleted or a reminder is turned off:
    /// an old lock-screen notification must not remain as a misleading trace of a profile that
    /// no longer exists. This never touches another App's notifications.
    private static func clearAppReminders(from center: UNUserNotificationCenter, ownerID: UUID) {
        let identifiers = DailyReminderKind.allCases.flatMap {
            [$0.identifier(for: ownerID), $0.legacyIdentifier]
        }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    public static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    public static func requestAuthorizationAndSynchronize(
        ownerID: UUID,
        schedule: DailyRoutineSchedule?,
        preferences: DailyReminderPreferences
    ) async -> String {
        await ReminderMutationGate.shared.withExclusiveAccess(ownerID: ownerID) { ownerWasDeleted in
            let center = UNUserNotificationCenter.current()
            guard !ownerWasDeleted else {
                // A deletion that was queued first already cleared this profile's alerts.  Do
                // not touch another profile's reminders merely because an old view task wakes.
                return "此资料已删除；没有创建或更新系统提醒。"
            }
            do {
                let allowed = try await center.requestAuthorization(options: [.alert, .sound])
                guard allowed else {
                    clearAppReminders(from: center, ownerID: ownerID)
                    return "系统未授予通知权限；已清除旧提醒，未创建新的提醒。你仍可在 App 内手动执行日卡。"
                }
                return await synchronizeUnlocked(ownerID: ownerID, schedule: schedule, preferences: preferences, center: center)
            } catch {
                clearAppReminders(from: center, ownerID: ownerID)
                return "无法请求系统通知权限；已清除旧提醒，未创建新的提醒。你仍可在 App 内手动执行日卡。"
            }
        }
    }

    public static func synchronize(
        ownerID: UUID,
        schedule: DailyRoutineSchedule?,
        preferences: DailyReminderPreferences
    ) async -> String {
        await ReminderMutationGate.shared.withExclusiveAccess(ownerID: ownerID) { ownerWasDeleted in
            guard !ownerWasDeleted else {
                return "此资料已删除；没有创建或更新系统提醒。"
            }
            let center = UNUserNotificationCenter.current()
            return await synchronizeUnlocked(ownerID: ownerID, schedule: schedule, preferences: preferences, center: center)
        }
    }

    /// Profile deletion deliberately has its own API instead of pretending a blank schedule is
    /// an ordinary save.  It serializes behind any existing add operation, permanently blocks
    /// that deleted owner from adding again in this process, then clears only this App's current
    /// and legacy IDs.  It never changes Apple Health, Photos, or another app's notifications.
    public static func invalidateAndClear(ownerID: UUID) async {
        await ReminderMutationGate.shared.deleteAndWithExclusiveAccess(ownerID: ownerID) {
            let center = UNUserNotificationCenter.current()
            clearAppReminders(from: center, ownerID: ownerID)
        }
    }

    private static func synchronizeUnlocked(
        ownerID: UUID,
        schedule: DailyRoutineSchedule?,
        preferences: DailyReminderPreferences,
        center: UNUserNotificationCenter
    ) async -> String {
        clearAppReminders(from: center, ownerID: ownerID)
        let requests = DailyReminderPlan.requests(schedule: schedule, preferences: preferences)
        guard !requests.isEmpty else {
            return DailyReminderPlan.unavailableReason(schedule: schedule, preferences: preferences) ?? "没有符合条件的提醒；已清除旧提醒。"
        }
        let status = await authorizationStatus()
        guard isAuthorized(status) else {
            return "系统通知尚未授权；已清除旧提醒，未创建新的提醒。"
        }
        do {
            for item in requests {
                let content = UNMutableNotificationContent()
                content.title = "私人健康教练"
                content.body = "现在查看今天的\(item.kind.title)。"
                content.sound = .default
                let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: item.hour, minute: item.minute), repeats: true)
                try await center.add(UNNotificationRequest(identifier: item.kind.identifier(for: ownerID), content: content, trigger: trigger))
            }
            if let reason = DailyReminderPlan.unavailableReason(schedule: schedule, preferences: preferences) {
                return "已设置 \(requests.count) 项本机提醒。\(reason)"
            }
            return "已设置 \(requests.count) 项本机提醒；仅在你选定的时间提醒，可随时逐项关闭。"
        } catch {
            // `UNUserNotificationCenter.add` is not transactional: a later request can fail
            // after an earlier one was accepted.  Do not leave a partial, misleading subset
            // of a freshly chosen schedule behind.  The next explicit owner action can retry
            // the complete set from scratch.
            clearAppReminders(from: center, ownerID: ownerID)
            return "部分或全部提醒未能写入系统；旧提醒已清除。请稍后重试，App 内日卡不受影响。"
        }
    }

    private static func isAuthorized(_ status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional:
            true
        #if os(iOS)
        case .ephemeral:
            true
        #endif
        default:
            false
        }
    }
}
#endif
