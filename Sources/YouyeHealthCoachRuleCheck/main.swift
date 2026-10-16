import Foundation
import YouyeHealthCoach

func verify(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

/// Keep every fixture in one explicit execution scope. A large top-level Swift executable can
/// initialize independent globals in compiler-selected order, which is unsafe when a later
/// fixture refers to one declared above it. The rule suite is intentionally sequential.
func runRuleChecks() async throws {

// Foundation fixtures must precede every top-level use. Swift executables may
// evaluate top-level globals through generated initialization functions rather
// than their source order, so relying on a later fixture is unsafe.
var fixedCalendar = Calendar(identifier: .gregorian)
fixedCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
let programStart = fixedCalendar.date(from: DateComponents(year: 2026, month: 8, day: 10))!
// RuleCheck runs in its own command-line process; clear any stale fixture preference left by an
// interrupted prior run so date-sensitive assertions always start from the documented default.
UserDefaults.standard.removeObject(forKey: PlanSchedule.restartDateDefaultsKey)
let profile = UserProfile(displayName: "内测用户", approximateArea: "望京附近")
let sustainableGoalFixture = SustainableGoal(pace: .steady, weeklyTrainingDays: 4, minimumMinutes: 15, reviewEveryWeeks: 2)
verify(sustainableGoalFixture.summary == "稳定推进 · 每周 4 次 · 每次至少 15 分钟", "sustainable goal summary must render the chosen values instead of interpolation tokens")
verify(sustainableGoalFixture.guardrailText.contains("每 2 周复盘一次") && !sustainableGoalFixture.guardrailText.contains("reviewEveryWeeks"), "sustainable goal guardrail must render the review cadence")
verify(
    MealQuantityNote.actualQuantity(from: "鸡蛋 2 个", plannedTitle: "番茄鸡蛋") == "实际数量：2 个",
    "a countable food description must persist the owner's confirmed egg count as a note"
)
verify(
    MealQuantityNote.actualQuantity(from: "蔬菜 2 把", plannedTitle: "清炒蔬菜") == "实际数量：2 把",
    "a custom count word must persist without being coerced into a hand-size serving"
)
verify(
    MealQuantityNote.actualQuantity(from: "鸡蛋 2 个", plannedTitle: "鸡蛋 2 个") == nil,
    "a planned recipe title must not be mistaken for an actual quantity note"
)
verify(
    MealQuantityNote.merging("少油｜实际数量：2 个｜不加糖", with: "实际数量：3 个") == "少油｜不加糖｜实际数量：3 个",
    "editing a count must replace every old actual-quantity marker while retaining other notes"
)
verify(
    MealQuantityNote.removingStoredActualQuantity(from: "2 小把坚果｜实际数量：2 小把｜盘中确认：少油") == "2 小把坚果｜盘中确认：少油",
    "a plan-external meal must hide its internal quantity marker while preserving the owner-facing food description"
)
let reopenedQuantityNote = "少油｜实际数量：2 个｜不加糖"
let reopenedActualQuantity = MealQuantityNote.storedActualQuantity(in: reopenedQuantityNote)
verify(
    reopenedActualQuantity == "实际数量：2 个"
        && MealQuantityNote.merging(reopenedQuantityNote, with: reopenedActualQuantity) == "少油｜不加糖｜实际数量：2 个",
    "reopening a planned meal must retain its confirmed count when the recipe title itself has no count"
)
verify(
    MealQuantityNote.isStillPresent("实际数量：2 小块", in: "2 小块鸡蛋")
        && !MealQuantityNote.isStillPresent("实际数量：2 小块", in: "鸡蛋"),
    "a quantity selected before the food name must persist only while the person keeps that wording"
)
let quantityHistoryMeal = ActualMealLog(
    date: programStart,
    slot: .breakfast,
    relationship: .asPlanned,
    description: "早餐",
    portionNote: "少油｜实际数量：2 个｜照片候选保守区间"
)
verify(
    quantityHistoryMeal.displayPortionNote == "少油｜数量：2 个",
    "meal history must show an owner-confirmed count while hiding internal photo-estimate markers"
)
verify(
    !MealQuantityNote.hasFoodDescription("2 个")
        && !MealQuantityNote.hasFoodDescription("2 小把", excluding: "实际数量：2 小把")
        && MealQuantityNote.hasFoodDescription("鸡蛋 2 个")
        && MealQuantityNote.hasFoodDescription("2 个鸡蛋"),
    "a count-only draft must not become a food record, while either natural Chinese egg-count order remains valid"
)
let healthWriteOwner = UUID()
let replacementHealthWriteOwner = UUID()
verify(
    PrivateProfileAsyncOwnershipPolicy.mayContinue(
        capturedOwnerID: healthWriteOwner,
        currentOwnerID: healthWriteOwner,
        deletionIsInProgressOrCommitted: false
    ),
    "an owner-confirmed HealthKit write may continue only while the same undeleted profile remains active"
)
verify(
    !PrivateProfileAsyncOwnershipPolicy.mayContinue(
        capturedOwnerID: healthWriteOwner,
        currentOwnerID: replacementHealthWriteOwner,
        deletionIsInProgressOrCommitted: false
    ) && !PrivateProfileAsyncOwnershipPolicy.mayContinue(
        capturedOwnerID: healthWriteOwner,
        currentOwnerID: healthWriteOwner,
        deletionIsInProgressOrCommitted: true
    ),
    "a deleted or replaced owner must block an old asynchronous HealthKit write from affecting a new profile"
)
verify(
    !PrivateProfileAsyncOwnershipPolicy.mayContinue(
        capturedOwnerID: healthWriteOwner,
        currentOwnerID: replacementHealthWriteOwner,
        deletionIsInProgressOrCommitted: true
    ),
    "the same ownership boundary must also discard an old asynchronous HealthKit summary instead of applying recovery to a replacement profile"
)
verify(
    !PrivateProfileAsyncOwnershipPolicy.mayContinue(
        capturedOwnerID: healthWriteOwner,
        currentOwnerID: replacementHealthWriteOwner,
        deletionIsInProgressOrCommitted: false
    ),
    "a local weekly-report or manual-review confirmation must not persist into a replacement profile after full deletion"
)
verify(ApproximateAreaPolicy.validationError(for: "望京地铁站附近") == nil, "a short fuzzy nearby-search area must remain allowed")
let nearbyGymURL = NearbyPlaceSearchLink.mapsURL(for: .gym, approximateArea: "望京地铁站附近")
let nearbyGymQuery = nearbyGymURL.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "q" })?.value }
verify(
    nearbyGymURL?.scheme == "https" && nearbyGymURL?.host == "maps.apple.com" && nearbyGymQuery == "望京地铁站附近 健身房",
    "an owner-initiated nearby gym handoff must preserve only the permitted coarse search area"
)
let nearbyCurrentLocation = NearbyMapCoordinate(latitude: 39.9849, longitude: 116.3185)!
let nearbyCurrentGymURL = NearbyPlaceSearchLink.mapsURL(
    for: .gym,
    approximateArea: "望京地铁站附近",
    currentLocation: nearbyCurrentLocation
)
let nearbyCurrentGymComponents = nearbyCurrentGymURL.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
verify(
    nearbyCurrentGymComponents?.queryItems?.first(where: { $0.name == "ll" })?.value == "39.985,116.319",
    "current-location Maps handoff must round the one-off centre before it leaves the app"
)
verify(
    nearbyCurrentGymComponents?.queryItems?.first(where: { $0.name == "q" })?.value == "健身房",
    "a fresh current location must take precedence over an old fuzzy-area query"
)
verify(
    NearbyMapCoordinate(latitude: 91, longitude: 0) == nil,
    "invalid device coordinates must never be handed to Maps"
)
verify(
    NearbyPlaceSearchLink.mapsURL(for: .delivery, approximateArea: "望京地铁站附近") == nil,
    "nearby handoff must not introduce a delivery ordering path"
)
let unsafeNearbyGymQuery = NearbyPlaceSearchLink.mapsURL(for: .gym, approximateArea: "某小区3号楼2单元501室")
    .flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "q" })?.value }
verify(
    unsafeNearbyGymQuery == "健身房",
    "a precise restored address must be dropped from the nearby Maps handoff"
)
verify(ApproximateAreaPolicy.validationError(for: "某小区3号楼2单元501室")?.contains("门牌") == true, "profile location must reject common precise-address markers rather than retaining an apartment address")
verify(ApproximateAreaPolicy.validationError(for: String(repeating: "望", count: 33))?.contains("32") == true, "profile location must remain a compact fuzzy area rather than an unbounded address field")
verify(UserProfile(displayName: "地址边界", approximateArea: "某小区3号楼2单元501室").approximateArea == nil, "profile construction must not retain a precise address that bypassed the settings field")
let malformedRestoredProfileJSON = """
{
  "id": "00000000-0000-0000-0000-000000000002",
  "displayName": "恢复边界",
  "restingHeartRateBaseline": 1000,
  "heightCm": -20
}
""".data(using: .utf8)!
let sanitizedRestoredProfile = try JSONDecoder().decode(UserProfile.self, from: malformedRestoredProfileJSON)
verify(
    sanitizedRestoredProfile.restingHeartRateBaseline == nil && sanitizedRestoredProfile.heightCm == nil,
    "a restored profile must discard malformed baseline and height values before they can affect recovery or exports"
)
let malformedRestoredHealthStatusJSON = """
{
  "sleepHours": 25,
  "restingHeartRateAboveBaseline": 500,
  "energy": 8,
  "stress": -1,
  "hungerOrNightEatingUrge": 9,
  "painOrInjury": true,
  "skinConcerns": ["dryness"]
}
""".data(using: .utf8)!
let sanitizedRestoredHealthStatus = try JSONDecoder().decode(HealthStatus.self, from: malformedRestoredHealthStatusJSON)
verify(
    sanitizedRestoredHealthStatus.sleepHours == nil
        && sanitizedRestoredHealthStatus.restingHeartRateAboveBaseline == nil
        && sanitizedRestoredHealthStatus.energy == nil
        && sanitizedRestoredHealthStatus.stress == nil
        && sanitizedRestoredHealthStatus.hungerOrNightEatingUrge == nil
        && sanitizedRestoredHealthStatus.painOrInjury
        && sanitizedRestoredHealthStatus.skinConcerns == [.dryness]
        && sanitizedRestoredHealthStatus.validationError == nil,
    "a restored health status must drop only malformed metrics while retaining valid protective and skin signals"
)
let malformedRestoredTrendJSON = """
{
  "id": "00000000-0000-0000-0000-000000000001",
  "weekStart": 524880000,
  "recordedAt": 524923200,
  "weightKg": -10,
  "waistCm": 1000,
  "note": "保留备注"
}
""".data(using: .utf8)!
let sanitizedRestoredTrend = try JSONDecoder().decode(WeeklyBodyCheckIn.self, from: malformedRestoredTrendJSON)
verify(
    sanitizedRestoredTrend.weightKg == nil && sanitizedRestoredTrend.waistCm == nil && sanitizedRestoredTrend.note == "保留备注",
    "a restored weekly trend must discard impossible measurements without deleting the owner's note"
)
let malformedCalorieFrameworkJSON = """
{
  "lowerBound": -100,
  "upperBound": 1700
}
""".data(using: .utf8)!
do {
    _ = try JSONDecoder().decode(DailyCalorieFramework.self, from: malformedCalorieFrameworkJSON)
    verify(false, "malformed restored calorie bounds must fail closed rather than produce an intake signal")
} catch {
    verify(true, "malformed restored calorie bounds must fail closed rather than produce an intake signal")
}

// 启动准备日和 8 周结束后的评估日可以留下真实状态，但都不能被当成第 1–56 天：
// 不创建完成记录、不生成恢复退阶审计，也不在重开时把状态重放为日卡改写。
let preparationDate = fixedCalendar.date(from: DateComponents(year: 2026, month: 8, day: 9))!
let preparationPlan = LaunchPreparationPlan.make(date: preparationDate)
let earlyPreparationDate = fixedCalendar.date(from: DateComponents(year: 2026, month: 8, day: 1))!
let earlyPreparationPlan = LaunchPreparationPlan.make(date: earlyPreparationDate, calendar: fixedCalendar)
verify(!PlanSchedule.isFinalPreparationDay(on: earlyPreparationDate, calendar: fixedCalendar), "a date earlier than the eve of launch must not be treated as the final food-prep day")
verify(PlanSchedule.isFinalPreparationDay(on: preparationDate, calendar: fixedCalendar), "only the local calendar day immediately before launch may show thaw-and-portion preparation")
verify(earlyPreparationPlan.dinner.ingredients == ["无需提前解冻或分装"] && !earlyPreparationPlan.dinner.title.contains("明天"), "opening weeks early must not instruct unsafe early thawing or promise that day one is tomorrow")
verify(
    PlanSchedule.makePlan(for: programStart, calendar: fixedCalendar)?.dinner == RecipeCatalog.all56.first,
    "the preparation screen's first-day preview source must resolve to the real first dinner rather than the preparation checklist"
)
let preparationCheckIn = HealthCheckInService.submit(
    HealthStatus(painOrInjury: true),
    at: preparationDate,
    plan: preparationPlan,
    data: PrivateCoachData(profile: profile),
    calendar: fixedCalendar
)
verify(preparationCheckIn.data.datedHealthStatusNotes.count == 1 && preparationCheckIn.data.planChanges.isEmpty && preparationCheckIn.data.dailyCompletions.isEmpty, "preparation-day health status must save privately without a formal-plan audit or completion")
verify(preparationCheckIn.plan == preparationPlan && HealthCheckInService.replayedPlan(for: preparationDate, plan: preparationPlan, data: preparationCheckIn.data, calendar: fixedCalendar) == preparationPlan, "preparation-day health status must not rewrite or replay a preparation plan")
let postProgramDate = fixedCalendar.date(from: DateComponents(year: 2026, month: 10, day: 10))!
let postProgramPlan = ProgramCompletionPlan.make(date: postProgramDate)
let postProgramCheckIn = HealthCheckInService.submit(
    HealthStatus(sleepHours: 5.5),
    at: postProgramDate,
    plan: postProgramPlan,
    data: PrivateCoachData(profile: profile),
    calendar: fixedCalendar
)
verify(postProgramCheckIn.data.datedHealthStatusNotes.count == 1 && postProgramCheckIn.data.planChanges.isEmpty && postProgramCheckIn.data.dailyCompletions.isEmpty, "post-program health status must save privately without a recovery audit or completion")
verify(postProgramCheckIn.plan == postProgramPlan && HealthCheckInService.replayedPlan(for: postProgramDate, plan: postProgramPlan, data: postProgramCheckIn.data, calendar: fixedCalendar) == postProgramPlan, "post-program health status must not rewrite or replay an assessment plan")
verify(CalendarDayStatus.resolve(for: preparationDate, data: preparationCheckIn.data, asOf: programStart, calendar: fixedCalendar) == .unrecorded, "a preparation-day private health note must not appear as a recovery workout day in the calendar")
verify(CalendarDayStatus.resolve(for: postProgramDate, data: postProgramCheckIn.data, asOf: postProgramDate.addingTimeInterval(86_400), calendar: fixedCalendar) == .unrecorded, "a post-program private health note must not appear as a recovery workout day in the calendar")
let nonFormalHealthKitResult = HealthKitSafetyBridge.applyOncePerProtectedDay(
    snapshot: HealthSnapshot(sleepHoursLastNight: 5.5, source: "HealthKit 摘要"),
    restingHeartRateBaseline: nil,
    at: preparationDate,
    plan: preparationPlan,
    data: PrivateCoachData(profile: profile),
    calendar: fixedCalendar
)
verify(nonFormalHealthKitResult == nil, "HealthKit summary on a non-formal day must not create a recovery audit")
let nonFormalTrainingFeedback = TrainingFeedback(effort: 5, pain: 2, sleepHours: 5.5, completed: true)
let preparationFeedbackResult = TrainingFeedbackService.submit(
    nonFormalTrainingFeedback,
    at: preparationDate,
    plan: preparationPlan,
    data: PrivateCoachData(profile: profile),
    calendar: fixedCalendar
)
verify(!preparationFeedbackResult.wasAccepted && preparationFeedbackResult.data.trainingFeedback.isEmpty && preparationFeedbackResult.data.datedHealthStatusNotes.isEmpty && preparationFeedbackResult.data.planChanges.isEmpty && preparationFeedbackResult.data.dailyCompletions.isEmpty, "preparation-day training feedback must not create a formal execution, health signal, or audit")
let postProgramFeedbackResult = TrainingFeedbackService.submit(
    nonFormalTrainingFeedback,
    at: postProgramDate,
    plan: postProgramPlan,
    data: PrivateCoachData(profile: profile),
    calendar: fixedCalendar
)
verify(!postProgramFeedbackResult.wasAccepted && postProgramFeedbackResult.data.trainingFeedback.isEmpty && postProgramFeedbackResult.data.datedHealthStatusNotes.isEmpty && postProgramFeedbackResult.data.planChanges.isEmpty && postProgramFeedbackResult.data.dailyCompletions.isEmpty, "post-program training feedback must not create a new plan-day audit or completion")

let formalWatchPlan = PlanSchedule.makePlan(for: programStart, calendar: fixedCalendar)!
let sameWatchDayRefresh = fixedCalendar.date(byAdding: .hour, value: 8, to: programStart)!
let nextWatchDay = fixedCalendar.date(byAdding: .day, value: 1, to: programStart)!
verify(
    !WatchLocalTimerResetPolicy.shouldReset(previousDay: programStart, newDay: sameWatchDayRefresh, calendar: fixedCalendar),
    "a same-day iPhone Watch-card refresh must not reset deliberate Watch-local timing"
)
verify(
    WatchLocalTimerResetPolicy.shouldReset(previousDay: programStart, newDay: nextWatchDay, calendar: fixedCalendar)
        && WatchLocalTimerResetPolicy.shouldReset(previousDay: programStart, newDay: nil, calendar: fixedCalendar),
    "a changed or invalidated Watch daily card must reset Watch-local timing"
)
verify(
    WatchDailyCardFreshnessPolicy.shouldApply(incoming: nextWatchDay, replacing: programStart)
        && WatchDailyCardFreshnessPolicy.shouldApply(incoming: programStart, replacing: programStart)
        && !WatchDailyCardFreshnessPolicy.shouldApply(incoming: programStart, replacing: nextWatchDay),
    "a delayed Watch context must not overwrite a newer paired-iPhone daily-card state"
)
verify(
    WatchDailyCardFreshnessPolicy.shouldApply(
        incoming: programStart,
        incomingRevision: 8,
        replacing: programStart,
        currentRevision: 7
    )
        && !WatchDailyCardFreshnessPolicy.shouldApply(
            incoming: programStart,
            incomingRevision: 7,
            replacing: programStart,
            currentRevision: 8
        ),
    "same-second Watch contexts must use the transport-only revision to prevent a delayed card from overwriting the newer state"
)
let formalWatchPayload = WatchDailyCardPayload.make(
    plan: formalWatchPlan,
    training: TrainingCatalog.card(for: programStart, calendar: fixedCalendar),
    now: programStart,
    calendar: fixedCalendar
)
let formalWatchContext = formalWatchPayload.applicationContext(transportRevision: 101)
verify(formalWatchPayload.isFormalPlanDay && formalWatchContext["isFormalPlanDay"] as? Bool == true, "Watch payload must identify an executable formal plan day")
verify(
    Set(formalWatchContext.keys) == ["isFormalPlanDay", "date", "publishedAt", "transportRevision", "breakfast", "lunch", "dinner", "training", "trainingMinimum", "isRecovery", "cameraBoundary"]
        && (formalWatchContext["transportRevision"] as? NSNumber)?.int64Value == 101,
    "formal Watch payload must include only minimum day-card display fields plus a transport-only ordering token"
)
verify(
    formalWatchContext["breakfast"] as? String == formalWatchPlan.breakfast.displayTitle
        && formalWatchContext["training"] as? String == TrainingCatalog.card(for: programStart, calendar: fixedCalendar)?.title,
    "formal Watch payload must mirror the iPhone daily-card labels rather than inventing a plan"
)
let mismatchedWatchTraining = TrainingCatalog.card(for: nextWatchDay, calendar: fixedCalendar)!
let mismatchedWatchPayload = WatchDailyCardPayload.make(
    plan: formalWatchPlan,
    training: mismatchedWatchTraining,
    now: programStart,
    calendar: fixedCalendar
)
verify(
    !mismatchedWatchPayload.isFormalPlanDay
        && mismatchedWatchPayload.date == nil
        && Set(mismatchedWatchPayload.applicationContext(transportRevision: 102).keys) == ["isFormalPlanDay", "publishedAt", "transportRevision", "unavailableMessage"],
    "a Watch payload must reject a training card from another program day rather than mixing day-card content"
)
let staleFormalWatchPayload = WatchDailyCardPayload.make(
    plan: formalWatchPlan,
    training: TrainingCatalog.card(for: programStart, calendar: fixedCalendar),
    now: fixedCalendar.date(byAdding: .day, value: 1, to: programStart)!,
    calendar: fixedCalendar
)
verify(
    !staleFormalWatchPayload.isFormalPlanDay
        && staleFormalWatchPayload.date == nil
        && Set(staleFormalWatchPayload.applicationContext(transportRevision: 103).keys) == ["isFormalPlanDay", "publishedAt", "transportRevision", "unavailableMessage"],
    "a delayed publish must never resend yesterday's otherwise-formal day card to Watch"
)
let preparationWatchPayload = WatchDailyCardPayload.make(plan: preparationPlan, training: nil, now: preparationDate, calendar: fixedCalendar)
let preparationWatchContext = preparationWatchPayload.applicationContext(transportRevision: 104)
verify(!preparationWatchPayload.isFormalPlanDay && preparationWatchPayload.date == nil && preparationWatchPayload.breakfast == nil && preparationWatchPayload.training == nil, "preparation-day Watch payload must omit all executable food and training details")
verify(
    Set(preparationWatchContext.keys) == ["isFormalPlanDay", "publishedAt", "transportRevision", "unavailableMessage"] && preparationWatchContext["isFormalPlanDay"] as? Bool == false,
    "non-formal Watch payload must only invalidate a stale day card"
)
let dataRecoveryWatchPayload = WatchDailyCardPayload.unavailable(message: "资料恢复中", now: programStart)
verify(
    !dataRecoveryWatchPayload.isFormalPlanDay
        && dataRecoveryWatchPayload.applicationContext(transportRevision: 105)["unavailableMessage"] as? String == "资料恢复中"
        && Set(dataRecoveryWatchPayload.applicationContext(transportRevision: 105).keys) == ["isFormalPlanDay", "publishedAt", "transportRevision", "unavailableMessage"],
    "private-data recovery must invalidate Watch content without exposing a fallback day card"
)

let original = DayOnePlan.make()
let dayOneScheduled = PlanSchedule.makePlan(for: programStart, calendar: fixedCalendar)
verify(!HealthSnapshot().hasAnyReadableMetric, "empty HealthKit summary must remain explicitly empty rather than being treated as health data")
verify(HealthSnapshot(sleepHoursLastNight: 7).hasAnyReadableMetric, "a HealthKit summary with an authorized aggregate must be treated as readable")
verify(PrivateCoachDataLoadOutcome.resolve { nil } == .absent, "a missing local owner record may enter first-run setup")
// Do not capture any top-level `PrivateCoachData` fixture here. Swift executables may initialize
// top-level storage through generated functions in an order different from the source, so an
// escaping loader can otherwise copy a not-yet-initialized value. Construct this small fixture
// inside the loader, which is also closer to a real decoded record returned by the store.
let readableLoadOutcome = PrivateCoachDataLoadOutcome.resolve {
    PrivateCoachData(profile: UserProfile(displayName: "可读取夹具"))
}
verify({
    guard case let .loaded(loaded) = readableLoadOutcome else { return false }
    return loaded.profile.displayName == "可读取夹具"
}(), "a readable local owner record must remain distinct from a missing record")
verify(PrivateCoachDataLoadOutcome.resolve { throw NSError(domain: "RuleCheck", code: 22) } == .unreadable, "an unreadable local owner record must enter recovery protection instead of first-run setup")
let pointerOwner = UUID()
let unrelatedDeletionOwner = UUID()
verify(CoachPrivateStorage.resolveLastOwnerPointer(nil) == .absent, "only a genuinely missing last-owner pointer may enter first-run setup")
verify(CoachPrivateStorage.resolveLastOwnerPointer(pointerOwner.uuidString) == .valid(pointerOwner), "a valid local owner pointer must resolve to its exact owner")
verify(CoachPrivateStorage.resolveLastOwnerPointer("not-a-uuid") == .malformed, "a damaged local owner pointer must be distinguished from a missing profile")
verify(PrivateCoachDataLoadOutcome.resolve { throw CoachPrivateStorage.StorageError.malformedLastOwnerPointer } == .unreadable, "a malformed local owner pointer must enter recovery protection instead of allowing a new profile to replace it")
verify(PrivateCoachDataLoadOutcome.resolve { throw CoachPrivateStorage.StorageError.ownerRecordMissingForPointer } == .unreadable, "a valid owner pointer whose private record is missing must enter recovery protection instead of allowing a new profile to replace it")
let identityBoundaryOwner = UUID()
let mismatchedIdentityData = PrivateCoachData(profile: UserProfile(id: UUID(), displayName: "错误 owner"))
do {
    _ = try JSONPrivateCoachDataStore.validatingOwner(mismatchedIdentityData, expectedOwnerID: identityBoundaryOwner)
    verify(false, "a private JSON payload whose profile owner differs from its filename owner must be rejected")
} catch let error as JSONPrivateCoachDataStore.StoreError {
    verify(error == .ownerIdentityMismatch, "a mismatched private JSON owner must fail with an explicit identity-boundary error")
} catch {
    verify(false, "a mismatched private JSON owner must not be treated as an unrelated load error")
}
verify(
    PrivateCoachDataLoadOutcome.resolve {
        try JSONPrivateCoachDataStore.validatingOwner(mismatchedIdentityData, expectedOwnerID: identityBoundaryOwner)
    } == .unreadable,
    "a mismatched private JSON owner must keep launch in recovery protection rather than first-run setup"
)
verify(CoachPrivateStorage.shouldClearLastOwnerPointer(deleting: pointerOwner, storedOwnerID: pointerOwner.uuidString), "deleting the current owner may clear only that owner's launch pointer")
verify(!CoachPrivateStorage.shouldClearLastOwnerPointer(deleting: unrelatedDeletionOwner, storedOwnerID: pointerOwner.uuidString), "deleting a stale or unrelated profile must not make the current local owner unreachable")
verify(!CoachPrivateStorage.shouldClearLastOwnerPointer(deleting: pointerOwner, storedOwnerID: "not-a-uuid"), "a malformed launch pointer must not be treated as proof of ownership during deletion")
let transparentSnapshot = HealthSnapshot(source: "HealthKit 摘要")
verify(transparentSnapshot.queryScopeDescription.contains("近 14 天") && transparentSnapshot.queryScopeDescription.contains("并集"), "health summary must disclose its query windows and overlap-safe aggregation")
verify(transparentSnapshot.localRetentionDescription.contains("不写入") && transparentSnapshot.localRetentionDescription.contains("空值"), "health summary must disclose its transient retention and missing-data boundary")
let intervalBase = Date(timeIntervalSinceReferenceDate: 100_000)
verify(HealthSnapshot(fetchedAt: intervalBase).fetchedAt == intervalBase, "a health summary must retain one explicit captured read instant")
let intervalA = HealthTimeInterval(start: intervalBase, end: intervalBase.addingTimeInterval(3_600))!
let intervalOverlap = HealthTimeInterval(start: intervalBase.addingTimeInterval(1_800), end: intervalBase.addingTimeInterval(5_400))!
let intervalSeparate = HealthTimeInterval(start: intervalBase.addingTimeInterval(7_200), end: intervalBase.addingTimeInterval(9_000))!
verify(HealthIntervalAggregation.unionDuration(of: [intervalA, intervalOverlap, intervalSeparate]) == 7_200, "overlapping Health sleep/workout intervals must be unioned rather than double-counted")
verify(HealthIntervalAggregation.unionDuration(of: [intervalA]) == 3_600, "one Health interval must preserve its exact duration")
verify(HealthIntervalAggregation.unionDuration(of: []) == 0, "an empty Health interval set must stay empty rather than inventing duration")
let healthWindow = HealthTimeInterval(start: intervalBase.addingTimeInterval(900), end: intervalBase.addingTimeInterval(4_500))!
let clippedHealthIntervals = HealthIntervalAggregation.clipped([intervalA, intervalOverlap, intervalSeparate], to: healthWindow)
verify(clippedHealthIntervals.count == 2 && HealthIntervalAggregation.unionDuration(of: clippedHealthIntervals) == 3_600, "Health sleep/workout intervals must be clipped to the query window before unioning")
verify(intervalSeparate.clipped(to: healthWindow) == nil, "a Health sample outside the query window must not be counted")
let quantityInsideWindow = HealthTimeInterval(start: intervalBase.addingTimeInterval(1_200), end: intervalBase.addingTimeInterval(1_800))!
let quantityCrossingWindow = HealthTimeInterval(start: intervalBase.addingTimeInterval(600), end: intervalBase.addingTimeInterval(1_200))!
verify(HealthQuantityWindowPolicy.isFullyContained(quantityInsideWindow, in: healthWindow), "a quantity sample fully inside its HealthKit window may be counted")
verify(!HealthQuantityWindowPolicy.isFullyContained(quantityCrossingWindow, in: healthWindow), "a cross-boundary quantity sample must not be counted whole in a shorter HealthKit window")
verify(HealthStepAggregation.average14Days(sourceCount: 1, totalSteps: 14_000).value == 1_000, "single-source Health steps may use the platform cumulative aggregate")
verify(HealthStepAggregation.average14Days(sourceCount: 2, totalSteps: 28_000).value == nil && HealthStepAggregation.average14Days(sourceCount: 2, totalSteps: 28_000).note?.contains("未合并") == true, "multi-source Health steps must not be directly added")
verify(HealthStepAggregation.average14Days(sourceCount: 0, totalSteps: nil).value == nil, "missing Health step samples must remain empty")
verify(HealthStepAggregation.average14Days(sourceCount: 1, totalSteps: .nan).value == nil && HealthStepAggregation.average14Days(sourceCount: 1, totalSteps: .nan).note?.contains("异常") == true, "non-finite Health step totals must remain unavailable without trapping during numeric conversion")
verify(HealthStepAggregation.average14Days(sourceCount: 1, totalSteps: -1).value == nil && HealthStepAggregation.average14Days(sourceCount: 1, totalSteps: -1).note?.contains("异常") == true, "negative Health step totals must remain unavailable")
verify(HealthActiveEnergyAggregation.total24Hours(sourceCount: 1, totalKilocalories: 435).value == 435, "single-source active energy may use the HealthKit 24-hour cumulative aggregate")
verify(HealthActiveEnergyAggregation.total24Hours(sourceCount: 2, totalKilocalories: 870).value == nil && HealthActiveEnergyAggregation.total24Hours(sourceCount: 2, totalKilocalories: 870).note?.contains("未合并") == true, "multi-source active energy must not be directly added")
verify(HealthActiveEnergyAggregation.total24Hours(sourceCount: 0, totalKilocalories: nil).value == nil, "missing Health active energy must remain unavailable rather than becoming zero")
verify(HealthActiveEnergyAggregation.total24Hours(sourceCount: 1, totalKilocalories: .infinity).value == nil && HealthActiveEnergyAggregation.total24Hours(sourceCount: 1, totalKilocalories: .infinity).note?.contains("异常") == true, "non-finite active energy totals must remain unavailable")
verify(HealthKitAccessMessage.readFailure(HealthKitError.unavailable).contains("不可用 Apple 健康"), "HealthKit device unavailability must not be mislabeled as a permission denial")
verify(HealthKitAccessMessage.readFailure(HealthKitError.authorizationNotGranted).contains("尚未获得"), "HealthKit authorization failure must offer a truthful permission recovery path")
verify(HealthKitAccessMessage.readFailure(HealthKitError.metricUnavailable("stepCount")).contains("stepCount"), "an unavailable Health metric must remain explicitly unavailable rather than fabricated")
verify(HealthKitAccessMessage.readFailure(NSError(domain: "RuleCheck", code: 1)).contains("没有使用计划数据补齐"), "unknown HealthKit failures must still disclose that the app did not invent health data")
verify(TrainingCatalog.all56.allSatisfy { $0.video.verifiedCandidateURL != nil }, "all 56 training cards must provide a timestamped direct Bilibili lesson without asking the owner to search")
verify(
    TrainingCatalog.all56.filter { !$0.containsMovingOrWaterSegment }.allSatisfy(\.supportsSynchronizedLiveFollowAlong),
    "every stationary land-based card with a verified lesson must expose the synchronized in-App follow-along path"
)
verify(
    TrainingCatalog.all56.filter(\.containsMovingOrWaterSegment).allSatisfy { !$0.supportsSynchronizedLiveFollowAlong },
    "swimming, cycling, walking, including recovery-priority cards, must never expose synchronized live camera monitoring"
)
let recoveryCyclingCard = TrainingCard(
    dayIndex: 1,
    title: "恢复骑行 + 呼吸",
    standardVersion: "共享单车 20 分钟，结束后做 90/90 呼吸 5 次。",
    minimumVersion: "轻走 10 分钟→90/90 呼吸 5 次。",
    regression: "取消骑行，只做平地轻走和呼吸。",
    stopConditions: "胸痛、异常气短或头晕立即停止。",
    followAlongInstruction: "完成移动后才做静态动作。",
    cameraPrompts: ["手机固定", "呼吸自然"],
    maxMinutes: 25
)
verify(
    recoveryCyclingCard.loadKind == .recovery
        && recoveryCyclingCard.containsMovingOrWaterSegment
        && !recoveryCyclingCard.supportsSynchronizedLiveFollowAlong
        && recoveryCyclingCard.livePoseButtonTitle.contains("完成移动后")
        && recoveryCyclingCard.livePoseSafetyNote.contains("不要开启取景"),
    "a recovery-priority cycling card must still block synchronous video/camera monitoring during its moving segment"
)
let recoveryStationaryCard = TrainingCard(
    dayIndex: 2,
    title: "恢复呼吸",
    standardVersion: "90/90 呼吸 5 次；胸椎旋转每侧 4 次。",
    minimumVersion: "90/90 呼吸 5 次→胸椎旋转每侧 2 次。",
    regression: "只做舒适呼吸。",
    stopConditions: "疼痛、头晕或症状加重立即停止。",
    followAlongInstruction: "固定手机后做静态动作。",
    cameraPrompts: ["手机固定", "动作缓慢"],
    maxMinutes: 12
)
verify(
    !recoveryStationaryCard.containsMovingOrWaterSegment
        && recoveryStationaryCard.supportsSynchronizedLiveFollowAlong,
    "a truly stationary recovery card must retain its optional synchronized local follow-along path"
)
verify(Set(TrainingCatalog.all56.compactMap { $0.video.verifiedCandidateURL }).count == 4, "the training catalogue must use the four separately checked core, posture, full-body, and recovery lessons")
verify(TrainingCatalog.all56.allSatisfy { ($0.video.durationSeconds ?? 0) > 0 && $0.video.fitNote?.isEmpty == false }, "every direct lesson must retain its checked duration and plan-fit note")
let unverifiedBilibiliVideo = FollowAlongVideo(searchQuery: "零基础 核心 跟练")
verify(unverifiedBilibiliVideo.safeSearchURL?.host == "search.bilibili.com" && unverifiedBilibiliVideo.safeSearchURL?.query?.contains("keyword=") == true, "Bilibili follow-along cards must form an explicit keyword search URL without inventing a course link")
verify(BilibiliFollowAlongNavigationPolicy.isAllowed(unverifiedBilibiliVideo.safeSearchURL!), "the in-app follow-along surface must allow the user-selected Bilibili search page")
verify(BilibiliFollowAlongNavigationPolicy.isAllowed(URL(string: "https://www.bilibili.com/video/BV1xx")!), "the in-app follow-along surface must allow Bilibili candidate-video routes")
verify(!BilibiliFollowAlongNavigationPolicy.isAllowed(URL(string: "http://www.bilibili.com/video/BV1xx")!) && !BilibiliFollowAlongNavigationPolicy.isAllowed(URL(string: "https://example.com/collect")!), "the in-app follow-along surface must reject insecure and non-Bilibili navigation")
verify(unverifiedBilibiliVideo.verifiedCandidateURL == nil, "an unverified Bilibili card must never present a direct candidate video as approved or playable")
let verifiedBilibiliVideo = FollowAlongVideo(searchQuery: "核心", title: "测试课程", uploader: "测试 UP", url: URL(string: "https://www.bilibili.com/video/BV1xx"), checkedAt: programStart, durationSeconds: 600, fitNote: "匹配测试训练", status: "已核验")
verify(verifiedBilibiliVideo.verifiedCandidateURL?.host == "www.bilibili.com", "only a timestamped named verified candidate may expose its direct Bilibili URL")
let inlineBilibiliVideo = FollowAlongVideo(searchQuery: "核心", title: "测试课程", uploader: "测试 UP", url: URL(string: "https://www.bilibili.com/video/BV1mpTq6qE9G"), checkedAt: programStart, durationSeconds: 600, fitNote: "匹配测试训练", status: "已核验")
verify(inlineBilibiliVideo.verifiedInlinePlayerURL?.host == "player.bilibili.com" && inlineBilibiliVideo.verifiedInlinePlayerURL?.query?.contains("bvid=BV1mpTq6qE9G") == true, "the synchronized camera route must derive only Bilibili's inline player from the already verified lesson")
verify(verifiedBilibiliVideo.verifiedInlinePlayerURL == nil, "a malformed or incomplete BVID must not be invented into an inline player URL")
let poseMonitoringStart = Date(timeIntervalSince1970: 10_000)
verify(
    !LocalPoseAnalysisWatchdog.shouldStop(
        monitoringStartedAt: poseMonitoringStart,
        lastResultAt: nil,
        now: poseMonitoringStart.addingTimeInterval(7.9)
    ),
    "the synchronized Bilibili and camera route must allow enough time for its first Vision result under initial WebKit load"
)
verify(
    LocalPoseAnalysisWatchdog.shouldStop(
        monitoringStartedAt: poseMonitoringStart,
        lastResultAt: nil,
        now: poseMonitoringStart.addingTimeInterval(8)
    ),
    "a synchronized route that never produces a Vision result must still close capture after its bounded startup grace"
)
verify(
    !LocalPoseAnalysisWatchdog.shouldStop(
        monitoringStartedAt: poseMonitoringStart,
        lastResultAt: poseMonitoringStart.addingTimeInterval(5),
        now: poseMonitoringStart.addingTimeInterval(7.9)
    ) && LocalPoseAnalysisWatchdog.shouldStop(
        monitoringStartedAt: poseMonitoringStart,
        lastResultAt: poseMonitoringStart.addingTimeInterval(5),
        now: poseMonitoringStart.addingTimeInterval(8)
    ),
    "after live pose has produced a result, the shorter refresh-stall limit must replace the first-result grace"
)
let untrustedVerifiedCandidate = FollowAlongVideo(searchQuery: "核心", title: "损坏候选", uploader: "未知来源", url: URL(string: "https://example.com/video"), checkedAt: programStart, durationSeconds: 600, fitNote: "匹配测试训练", status: "已核验")
verify(untrustedVerifiedCandidate.verifiedCandidateURL == nil, "a damaged or imported verified candidate must not turn Bilibili follow-along into an arbitrary external URL")
let insecureVerifiedCandidate = FollowAlongVideo(searchQuery: "核心", title: "不安全候选", uploader: "未知来源", url: URL(string: "http://www.bilibili.com/video/BV1zz"), checkedAt: programStart, durationSeconds: 600, fitNote: "匹配测试训练", status: "已核验")
verify(insecureVerifiedCandidate.verifiedCandidateURL == nil, "an in-app Bilibili candidate must require HTTPS even when its host name looks correct")
let incompleteBilibiliVideo = FollowAlongVideo(searchQuery: "核心", title: "未完整核验", uploader: "测试 UP", url: URL(string: "https://www.bilibili.com/video/BV1yy"), status: "已核验")
verify(incompleteBilibiliVideo.verifiedCandidateURL == nil, "a direct Bilibili candidate without a check timestamp must remain unavailable")
let encodedLegacyFollowAlong = try JSONEncoder().encode(unverifiedBilibiliVideo)
var legacyFollowAlongObject = try JSONSerialization.jsonObject(with: encodedLegacyFollowAlong) as! [String: Any]
legacyFollowAlongObject.removeValue(forKey: "durationSeconds")
legacyFollowAlongObject.removeValue(forKey: "fitNote")
let migratedLegacyFollowAlong = try JSONDecoder().decode(FollowAlongVideo.self, from: JSONSerialization.data(withJSONObject: legacyFollowAlongObject))
verify(migratedLegacyFollowAlong.durationSeconds == nil && migratedLegacyFollowAlong.fitNote == nil && migratedLegacyFollowAlong.verifiedCandidateURL == nil, "older follow-along records without checked duration or plan fit must remain readable but cannot become direct lessons")
verify(TrainingCatalog.all56.allSatisfy { $0.cameraPrompts.count >= 2 }, "local pose reminder must always have action-specific safety prompts")
verify(TrainingCatalog.all56.filter(\.containsMovingOrWaterSegment).allSatisfy { $0.livePoseSafetyNote.contains("不要开启取景") }, "all moving or water-based cards must forbid live camera use during movement")
let fullDailyMealAudit = DailyMealCatalogAudit.validate()
if !fullDailyMealAudit.isEmpty {
    print("DAILY MEAL AUDIT:\n" + fullDailyMealAudit.joined(separator: "\n"))
}
verify(fullDailyMealAudit.isEmpty, "all 56 daily cards must block on grams, prep, single-appliance timing, storage/reheating, substitutions, commuter safety, and the 20-minute limit")
let encodedPlan = try JSONEncoder().encode(original)
var legacyPlanObject = try JSONSerialization.jsonObject(with: encodedPlan) as! [String: Any]
legacyPlanObject.removeValue(forKey: "breakfast")
legacyPlanObject.removeValue(forKey: "lunch")
let legacyPlanData = try JSONSerialization.data(withJSONObject: legacyPlanObject)
let migratedLegacyPlan = try JSONDecoder().decode(TodayPlan.self, from: legacyPlanData)
verify(migratedLegacyPlan.dinner == original.dinner && migratedLegacyPlan.trainingInstruction == original.trainingInstruction, "legacy plan migration must preserve dinner and training")
verify(migratedLegacyPlan.breakfast == DayOnePlan.fallbackBreakfast && migratedLegacyPlan.lunch == DayOnePlan.fallbackLunch, "legacy plan migration must safely add breakfast and lunch defaults")
let lowSleep = PlanAdjuster.adjustment(for: HealthStatus(sleepHours: 5.5), plan: original)
verify(lowSleep.plan.trainingMode == .recovery, "sleep below 6 hours must select recovery")
verify(lowSleep.change?.kind == .recoveryDowngrade, "recovery downgrade must be recorded")
verify(lowSleep.change?.authority == .automatic, "protective downgrade may be automatic")
verify(lowSleep.change?.reason.contains("睡眠") == true, "audit reason must state sleep")
verify(RecoveryPlanAudit.validate(original, protected: lowSleep.plan).isEmpty, "recovery must preserve all meals while enforcing no-progression, stop conditions, normal food, and sleep priority")

let pain = PlanAdjuster.adjustment(for: HealthStatus(painOrInjury: true), plan: original)
verify(pain.plan.trainingMode == .recovery, "pain must select recovery even without sleep data")
verify(pain.change?.reason.contains("疼痛") == true, "audit reason must state pain")
verify(RecoveryPlanAudit.validate(original, protected: pain.plan).isEmpty, "pain recovery must preserve the original meals rather than turning into a diet change")

let medicationRestriction = PlanAdjuster.adjustment(for: HealthStatus(medicationOrClinicianRestriction: true), plan: original)
verify(
    medicationRestriction.plan.trainingMode == .recovery
        && medicationRestriction.plan.trainingInstruction.contains("暂停计划训练")
        && medicationRestriction.plan.trainingInstruction.contains("医生或药品说明明确允许"),
    "a clinician or medication restriction must pause training rather than prescribe a generic walk"
)
verify(
    RecoveryDaySupportService.make(for: medicationRestriction.plan)?.trainingAction.contains("训练已暂停") == true,
    "cross-page recovery support must retain a clinician-restriction training pause"
)
let pausedTrainingFeedback = TrainingFeedback(date: original.date, effort: 5, pain: 0, sleepHours: 7, completed: true)
let pausedTrainingFeedbackResult = TrainingFeedbackService.submit(
    pausedTrainingFeedback,
    at: original.date,
    plan: medicationRestriction.plan,
    data: PrivateCoachData(profile: UserProfile(displayName: "我"))
)
verify(pausedTrainingFeedbackResult.wasAccepted, "a same-day status reflection remains saveable while training is paused")
verify(pausedTrainingFeedbackResult.data.trainingFeedback.first?.completed == false, "a paused-training day must never persist a completion claim from its feedback form")
verify(pausedTrainingFeedbackResult.data.executionCompletion(for: original.date)?.trainingOrRecoveryCompleted != true, "paused-training feedback must not rebuild as completed movement after reload")
verify(pausedTrainingFeedbackResult.adaptation.message.contains("未标记为训练或恢复完成"), "a paused-training feedback save must disclose its non-completion boundary")
let pausedMoveCheckIn = TodayFeature.completing(
    .move,
    for: medicationRestriction.plan,
    in: PrivateCoachData(profile: UserProfile(displayName: "我")),
    at: original.date
)
verify(pausedMoveCheckIn.dailyCompletions.isEmpty, "a paused-training day must reject a direct movement completion from the today card")
let pausedMoveAcknowledgement = TodayFeature.markingCompleted(
    .move,
    for: medicationRestriction.plan,
    in: PrivateCoachData(profile: UserProfile(displayName: "我")),
    at: original.date
)
verify(pausedMoveAcknowledgement.dailyCompletions.isEmpty, "an affirmative movement acknowledgement must also reject a paused-training day")
let pausedMoveAction = TodayFeature.actions(plan: medicationRestriction.plan, completion: nil).first { $0.id == .move }
verify(pausedMoveAction?.title == "训练已暂停" && pausedMoveAction?.detail.contains("不标记训练完成") == true, "the today action must describe a paused plan as rest rather than recovery completion")
let priorPausedMoveCompletion = PrivateCoachData(
    profile: UserProfile(displayName: "我"),
    dailyCompletions: [DailyCompletion(date: original.date, foodCompleted: false, trainingOrRecoveryCompleted: true, bedtimePreparationCompleted: false)]
)
let correctedPausedMoveCompletion = TodayFeature.completing(
    .move,
    for: medicationRestriction.plan,
    in: priorPausedMoveCompletion,
    at: original.date
)
verify(correctedPausedMoveCompletion.executionCompletion(for: original.date)?.trainingOrRecoveryCompleted == false, "a paused day may still let the owner correct an earlier movement completion")
let illnessRecovery = PlanAdjuster.adjustment(for: HealthStatus(illnessSymptoms: true), plan: original)
verify(
    illnessRecovery.plan.trainingInstruction.contains("暂停计划训练") && illnessRecovery.plan.trainingInstruction.contains("休息、补水和睡眠"),
    "illness recovery must default to rest instead of assigning exercise"
)

let checkIn = HealthCheckInService.submit(HealthStatus(illnessSymptoms: true), plan: original, data: PrivateCoachData(profile: UserProfile(displayName: "我")))
verify(checkIn.plan.trainingMode == .recovery, "illness check-in must select recovery")
verify(checkIn.data.planChanges.count == 1, "automatic safety change must be recorded")
verify(checkIn.data.datedHealthStatusNotes.count == 1, "health status must retain a timestamp")
let stableCheckInID = checkIn.data.datedHealthStatusNotes[0].id
let retriedCheckIn = HealthCheckInService.submit(HealthStatus(illnessSymptoms: true), submissionID: stableCheckInID, plan: checkIn.plan, data: checkIn.data)
verify(retriedCheckIn.data.datedHealthStatusNotes.count == 1 && retriedCheckIn.data.planChanges.count == 1 && retriedCheckIn.automaticChange == nil, "retrying one stable health-status submission must not duplicate status or recovery audit history")
let rejectedCrossOwnerCheckIn = HealthCheckInService.submit(
    HealthStatus(painOrInjury: true, medicationOrClinicianRestriction: true),
    formOwnerID: UUID(),
    at: original.date,
    plan: original,
    data: checkIn.data
)
verify(
    rejectedCrossOwnerCheckIn.validationError?.contains("新资料") == true
        && rejectedCrossOwnerCheckIn.data == checkIn.data
        && rejectedCrossOwnerCheckIn.plan == original
        && rejectedCrossOwnerCheckIn.automaticChange == nil,
    "a health sheet opened by another or deleted local owner must save neither symptoms nor a protective plan change"
)
let staleScreenSecondCheckIn = HealthCheckInService.submit(
    HealthStatus(stress: 4, skinConcerns: [.dryness]),
    at: original.date,
    plan: original,
    data: checkIn.data
)
verify(
    staleScreenSecondCheckIn.plan.trainingMode == .recovery
        && staleScreenSecondCheckIn.data.planChanges.count == 1
        && staleScreenSecondCheckIn.data.datedHealthStatusNotes.count == 2
        && staleScreenSecondCheckIn.automaticChange == nil,
    "a second status submitted from a stale standard card must preserve the saved recovery day without duplicating its audit"
)
let replayedIllnessPlan = HealthCheckInService.replayedPlan(for: original.date, plan: original, data: checkIn.data)
verify(replayedIllnessPlan.trainingMode == .recovery, "saved same-day illness status must restore protective recovery after app reload")
let reloadedGuidance = HealthCheckInService.guidance(for: original.date, plan: replayedIllnessPlan, data: checkIn.data)
verify(reloadedGuidance.contains { $0.contains("恢复版") }, "saved same-day health status must restore visible recovery guidance after app reload")
let recoverySupport = RecoveryDaySupportService.make(for: replayedIllnessPlan)
verify(recoverySupport?.trainingAction.contains("不补练") == true && recoverySupport?.foodAction.contains("不因恢复日减餐") == true && recoverySupport?.bedtimeAction.contains("睡眠") == true, "protective recovery must synchronize clear training, food, and bedtime actions without changing the meal framework")
verify(RecoveryDaySupportService.make(for: original) == nil, "standard training days must not be mislabeled as recovery days")
let healthSummary = HealthCheckInService.summary(for: original.date, in: checkIn.data)
verify(healthSummary?.hasProtectiveSignal == true && healthSummary?.labels.contains("生病症状") == true, "today screen health summary must visibly explain a saved protective signal without exposing HealthKit samples")
// DayOnePlan uses the real current date.  Anchor both fixture submissions within its local day
// so this safety check remains deterministic when the rule suite runs late at night.
let healthFixtureDay = Calendar.current.startOfDay(for: original.date)
let earlyPainStatus = DatedHealthStatus(date: healthFixtureDay.addingTimeInterval(9 * 3_600), status: HealthStatus(painOrInjury: true))
let laterSkinStatus = DatedHealthStatus(date: healthFixtureDay.addingTimeInterval(10 * 3_600), status: HealthStatus(stress: 4, skinConcerns: [.dryness]))
let mergedSameDaySummary = HealthCheckInService.summary(
    for: original.date,
    in: PrivateCoachData(profile: UserProfile(displayName: "我"), datedHealthStatusNotes: [earlyPainStatus, laterSkinStatus])
)
verify(mergedSameDaySummary?.hasProtectiveSignal == true && mergedSameDaySummary?.labels.contains("疼痛/受伤") == true && mergedSameDaySummary?.labels.contains("压力 4/5") == true && mergedSameDaySummary?.labels.contains("干燥") == true, "a later non-protective check-in must not hide earlier same-day pain or its recovery signal")
let yesterdayStatus = DatedHealthStatus(date: Calendar.current.date(byAdding: .day, value: -1, to: original.date)!, status: HealthStatus(stress: 5))
let todayGuidanceOnly = HealthCheckInService.guidance(for: original.date, plan: original, data: PrivateCoachData(profile: UserProfile(displayName: "我"), datedHealthStatusNotes: [yesterdayStatus]))
verify(todayGuidanceOnly.isEmpty, "yesterday's health guidance must not leak into today's plan")
verify(HealthCheckInService.summary(for: original.date, in: PrivateCoachData(profile: UserProfile(displayName: "我"), datedHealthStatusNotes: [yesterdayStatus])) == nil, "yesterday's health status summary must not leak into today")
let healthKitSleepSnapshot = HealthSnapshot(fetchedAt: original.date, sleepHoursLastNight: 5.5, restingHeartRate: 57, source: "HealthKit 摘要")
let healthKitSleepResult = HealthKitSafetyBridge.apply(snapshot: healthKitSleepSnapshot, restingHeartRateBaseline: 52, plan: original, data: PrivateCoachData(profile: UserProfile(displayName: "我", restingHeartRateBaseline: 52)))
verify(healthKitSleepResult?.plan.trainingMode == .recovery, "HealthKit sleep summary below 6 hours must apply protective recovery")
verify(healthKitSleepResult?.data.planChanges.last?.authority == .automatic, "HealthKit protective downgrade must retain automatic audit trail")
let healthKitHighHeartSnapshot = HealthSnapshot(fetchedAt: original.date, sleepHoursLastNight: 7, restingHeartRate: 61, source: "HealthKit 摘要")
let healthKitHighHeartResult = HealthKitSafetyBridge.apply(snapshot: healthKitHighHeartSnapshot, restingHeartRateBaseline: 52, plan: original, data: PrivateCoachData(profile: UserProfile(displayName: "我", restingHeartRateBaseline: 52)))
verify(healthKitHighHeartResult?.plan.trainingMode == .recovery, "confirmed baseline plus +8 resting heart rate must apply protective recovery")
let healthKitProtectedDay = HealthKitSafetyBridge.applyOncePerProtectedDay(
    snapshot: healthKitSleepSnapshot,
    restingHeartRateBaseline: 52,
    at: original.date,
    plan: original,
    data: PrivateCoachData(profile: UserProfile(displayName: "我", restingHeartRateBaseline: 52))
)
guard case let .applied(firstHealthKitProtection)? = healthKitProtectedDay else {
    fatalError("FAIL: first HealthKit protective read must apply exactly once")
}
let repeatedHealthKitRead = HealthKitSafetyBridge.applyOncePerProtectedDay(
    snapshot: healthKitSleepSnapshot,
    restingHeartRateBaseline: 52,
    at: original.date,
    plan: firstHealthKitProtection.plan,
    data: firstHealthKitProtection.data
)
verify(repeatedHealthKitRead == .alreadyProtected, "repeated same-day HealthKit safety reads must not append duplicate recovery history")
verify(firstHealthKitProtection.data.datedHealthStatusNotes.count == 1 && firstHealthKitProtection.data.planChanges.count == 1, "the first HealthKit safety read must retain one private status and one audit record")
verify(HealthKitSafetyBridge.apply(snapshot: healthKitHighHeartSnapshot, restingHeartRateBaseline: nil, plan: original, data: PrivateCoachData(profile: UserProfile(displayName: "我"))) == nil, "missing user-confirmed baseline must not use heart rate for automatic adjustment")
let heartRecoveryDecision = HealthKitSafetyBridge.recoveryDecision(snapshot: healthKitHighHeartSnapshot, restingHeartRateBaseline: 52)
verify(heartRecoveryDecision.baselineIsConfirmed && heartRecoveryDecision.restingHeartRateAboveBaseline == 9 && heartRecoveryDecision.triggersRecovery, "health summary must visibly explain confirmed-baseline heart-rate recovery")
let noBaselineDecision = HealthKitSafetyBridge.recoveryDecision(snapshot: healthKitHighHeartSnapshot, restingHeartRateBaseline: nil)
verify(!noBaselineDecision.baselineIsConfirmed && !noBaselineDecision.triggersRecovery, "health summary without baseline must visibly avoid heart-rate recovery")
let invalidBaselineDecision = HealthKitSafetyBridge.recoveryDecision(snapshot: healthKitHighHeartSnapshot, restingHeartRateBaseline: 1_000)
verify(!invalidBaselineDecision.baselineIsConfirmed && !invalidBaselineDecision.triggersRecovery && invalidBaselineDecision.reason?.contains("基线数值异常") == true, "an invalid stored heart-rate baseline must not participate in recovery calculations")
let shortSleepInvalidBaselineDecision = HealthKitSafetyBridge.recoveryDecision(snapshot: healthKitSleepSnapshot, restingHeartRateBaseline: 1_000)
verify(!shortSleepInvalidBaselineDecision.baselineIsConfirmed && shortSleepInvalidBaselineDecision.triggersRecovery && shortSleepInvalidBaselineDecision.reason?.contains("睡眠") == true, "invalid baseline must never suppress the independent short-sleep safety signal")
let sleepRecoveryDecision = HealthKitSafetyBridge.recoveryDecision(snapshot: healthKitSleepSnapshot, restingHeartRateBaseline: nil)
verify(sleepRecoveryDecision.triggersRecovery && sleepRecoveryDecision.reason?.contains("睡眠") == true, "health summary must visibly explain sleep recovery without a heart-rate baseline")
let invalidSleepStatus = HealthStatus(sleepHours: 25)
verify(invalidSleepStatus.validationError?.contains("0–24") == true, "health status domain validation must reject impossible manual sleep values")
let invalidHeartRateStatus = HealthStatus(restingHeartRateAboveBaseline: 121)
verify(invalidHeartRateStatus.validationError?.contains("-80") == true, "health status domain validation must reject implausible manual heart-rate deltas")
let invalidStatusCheckIn = HealthCheckInService.submit(
    invalidSleepStatus,
    at: programStart,
    plan: original,
    data: PrivateCoachData(profile: profile),
    calendar: fixedCalendar
)
verify(invalidStatusCheckIn.validationError != nil && invalidStatusCheckIn.data.datedHealthStatusNotes.isEmpty && invalidStatusCheckIn.data.planChanges.isEmpty && invalidStatusCheckIn.plan == original, "invalid health status must not persist, alter today's card, or create a recovery audit")
let nextCalendarDay = fixedCalendar.date(byAdding: .day, value: 1, to: original.date)!
let staleDateStatusCheckIn = HealthCheckInService.submit(
    HealthStatus(painOrInjury: true),
    at: nextCalendarDay,
    plan: original,
    data: PrivateCoachData(profile: profile),
    calendar: fixedCalendar
)
verify(
    staleDateStatusCheckIn.validationError?.contains("日期已切换") == true
        && staleDateStatusCheckIn.data.datedHealthStatusNotes.isEmpty
        && staleDateStatusCheckIn.data.planChanges.isEmpty
        && staleDateStatusCheckIn.plan == original,
    "a status saved after its visible plan day changed must be rejected rather than filed under an old card"
)
verify(PlanAdjuster.adjustment(for: invalidSleepStatus, plan: original).plan == original, "direct plan adjustment must also reject invalid state values from non-UI callers")
let invalidHealthSnapshot = HealthSnapshot(sleepHoursLastNight: 25, restingHeartRate: 61, source: "异常摘要")
verify(
    HealthKitSafetyBridge.apply(snapshot: invalidHealthSnapshot, restingHeartRateBaseline: 52, plan: original, data: PrivateCoachData(profile: profile), calendar: fixedCalendar) == nil,
    "an invalid external health summary must not alter today's plan or create a private audit"
)
let invalidSnapshotDecision = HealthKitSafetyBridge.recoveryDecision(snapshot: invalidHealthSnapshot, restingHeartRateBaseline: 52)
verify(!invalidSnapshotDecision.triggersRecovery && invalidSnapshotDecision.reason?.contains("异常") == true, "an invalid external health summary must explain that it was ignored rather than silently falling through")
let staleHealthSnapshot = HealthSnapshot(
    fetchedAt: fixedCalendar.date(byAdding: .day, value: -1, to: programStart)!,
    sleepHoursLastNight: 5.5,
    source: "过期摘要"
)
verify(
    !HealthKitSafetyBridge.isCurrentSafetySnapshot(staleHealthSnapshot, at: programStart, calendar: fixedCalendar)
        && HealthKitSafetyBridge.apply(
            snapshot: staleHealthSnapshot,
            restingHeartRateBaseline: 52,
            at: programStart,
            plan: original,
            data: PrivateCoachData(profile: profile),
            calendar: fixedCalendar
        ) == nil,
    "a prior-day HealthKit summary must never automatically downgrade today's training"
)
let futureHealthSnapshot = HealthSnapshot(
    fetchedAt: programStart.addingTimeInterval(60),
    sleepHoursLastNight: 5.5,
    source: "未来时间戳摘要"
)
verify(
    !HealthKitSafetyBridge.isCurrentSafetySnapshot(futureHealthSnapshot, at: programStart, calendar: fixedCalendar)
        && HealthKitSafetyBridge.applyOncePerProtectedDay(
            snapshot: futureHealthSnapshot,
            restingHeartRateBaseline: 52,
            at: programStart,
            plan: original,
            data: PrivateCoachData(profile: profile),
            calendar: fixedCalendar
        ) == nil,
    "a clock-future HealthKit summary must not create a private recovery audit"
)
let malformedDisplaySnapshot = HealthSnapshot(
    weightKg: 0,
    bodyFatPercent: 120,
    averageDailySteps14d: -1,
    sleepHoursLastNight: 25,
    restingHeartRate: 10,
    activeEnergyKcal: -1,
    workoutMinutes: 30,
    swimMinutes: 45,
    source: "异常摘要"
).sanitizedForDisplay()
verify(
    malformedDisplaySnapshot.weightKg == nil
        && malformedDisplaySnapshot.bodyFatPercent == nil
        && malformedDisplaySnapshot.averageDailySteps14d == nil
        && malformedDisplaySnapshot.sleepHoursLastNight == nil
        && malformedDisplaySnapshot.restingHeartRate == nil
        && malformedDisplaySnapshot.activeEnergyKcal == nil
        && malformedDisplaySnapshot.swimMinutes == nil
        && malformedDisplaySnapshot.workoutMinutes == 30
        && malformedDisplaySnapshot.availabilityNotes.count >= 7,
    "malformed HealthKit aggregates must be hidden with visible verification notes while unrelated valid fields remain available"
)
let duplicatedAvailabilityNotesSnapshot = HealthSnapshot(sleepHoursLastNight: 7, source: "HealthKit 摘要", availabilityNotes: ["同一条说明", "同一条说明"])
verify(!duplicatedAvailabilityNotesSnapshot.hasInvalidMetric && !HealthKitSafetyBridge.recoveryDecision(snapshot: duplicatedAvailabilityNotesSnapshot, restingHeartRateBaseline: nil).triggersRecovery, "duplicate availability notes must not be mistaken for an invalid health metric")
let invalidFeedback = TrainingFeedback(effort: 11, pain: 3, sleepHours: 25, completed: false)
let invalidFeedbackResult = TrainingFeedbackService.submit(
    invalidFeedback,
    at: programStart,
    plan: dayOneScheduled!,
    data: PrivateCoachData(profile: profile),
    calendar: fixedCalendar
)
verify(!invalidFeedbackResult.wasAccepted && invalidFeedbackResult.data.trainingFeedback.isEmpty && invalidFeedbackResult.data.planChanges.isEmpty && invalidFeedbackResult.adaptation.message.contains("主观用力"), "invalid feedback must be rejected before it can persist or change a training card")
let stateGuidance = DailyGuidance.make(for: HealthStatus(energy: 2, stress: 4, hungerOrNightEatingUrge: 4, digestionNote: "胃胀", menstrualPhase: .luteal, skinNote: "泛红"), trainingMode: .standard)
verify(stateGuidance.count >= 6, "non-safety health states must produce tailored same-day guidance")
let initiallyVisibleStateGuidance = DailyGuidance.initiallyVisible(stateGuidance)
verify(
    initiallyVisibleStateGuidance.count == 2 && initiallyVisibleStateGuidance == Array(stateGuidance.prefix(2)),
    "today state card must start with two source-ordered actions while preserving the full guidance list for expansion"
)
verify(DailyGuidance.initiallyVisible(stateGuidance, maximumCount: -1).isEmpty, "today state card guidance limit must never produce a negative or unsafe slice")
verify(stateGuidance.contains { $0.contains("不以饿肚子") }, "night eating guidance must not prescribe compensation")
verify(stateGuidance.contains { $0.contains("黄体期") && $0.contains("罚练") }, "menstrual phase guidance must be non-punitive and must not imply automatic progression")
verify(stateGuidance.contains { $0.contains("消化状态") && $0.contains("熟软") }, "digestion notes must produce a gentle-food and medical-escalation boundary")
let phaseOnlyPlan = PlanAdjuster.adjustment(for: HealthStatus(menstrualPhase: .ovulation), plan: original)
verify(phaseOnlyPlan.plan.trainingMode == .standard && phaseOnlyPlan.change == nil, "menstrual phase alone must not automatically change training or calories")
let skinGuidance = DailyGuidance.make(for: HealthStatus(skinConcerns: [.inflamedAcne, .irritationOrAllergy]), trainingMode: .standard)
verify(skinGuidance.contains { $0.contains("不挤压") && $0.contains("皮肤科") }, "inflamed acne guidance must include a safe escalation threshold without product recommendations")
verify(skinGuidance.contains { $0.contains("停用") && $0.contains("尽快就医") }, "irritation guidance must include a safety escalation threshold")
let protectiveStateGuidance = DailyGuidance.make(for: HealthStatus(menstrualDiscomfort: true, painOrInjury: true, illnessSymptoms: true, medicationOrClinicianRestriction: true), trainingMode: .recovery)
verify(protectiveStateGuidance.contains { $0.contains("疼痛或受伤") && $0.contains("不测试疼痛动作") }, "pain status must give an immediate non-diagnostic execution boundary")
verify(protectiveStateGuidance.contains { $0.contains("生病症状") && $0.contains("规律进食") }, "illness status must preserve food and rest support without compensatory exercise")
verify(protectiveStateGuidance.contains { $0.contains("医生/药品说明优先") && $0.contains("不自行加量") }, "medication restriction must defer to clinician guidance and prohibit progression")
verify(protectiveStateGuidance.contains { $0.contains("经期明显不适") && $0.contains("不因训练完成度") }, "menstrual discomfort must carry a non-punitive recovery action")
let preparationGuidance = DailyGuidance.make(
    for: HealthStatus(menstrualDiscomfort: true),
    trainingMode: .recovery,
    isFormalPlanDay: false
)
verify(preparationGuidance.contains { $0.contains("不是正式训练日") } && !preparationGuidance.contains { $0.contains("今天已切换恢复版") }, "non-formal-day guidance must not claim a recovery-plan switch")
// Keep this fixture initialized before use. Referencing the later, unrelated
// `profile` top-level fixture caused a release/runtime bad-access on Swift 6.
let statusSummaryProfile = UserProfile(displayName: "状态测试用户")
let statusSummaryData = PrivateCoachData(profile: statusSummaryProfile, datedHealthStatusNotes: [DatedHealthStatus(date: programStart, status: HealthStatus(restingHeartRateAboveBaseline: 8, hungerOrNightEatingUrge: 4))])
let statusSummary = HealthCheckInService.summary(for: programStart, in: statusSummaryData, calendar: fixedCalendar)
verify(statusSummary?.labels.contains("静息心率较平时 +8 次/分") == true && statusSummary?.labels.contains("饥饿/夜宵冲动 4/5") == true, "today status summary must surface recorded heart-rate delta and hunger signal")
let legacyStatus = HealthStatus(sleepHours: 7, skinNote: "旧记录")
let encodedStatus = try JSONEncoder().encode(legacyStatus)
var legacyStatusObject = try JSONSerialization.jsonObject(with: encodedStatus) as! [String: Any]
legacyStatusObject.removeValue(forKey: "menstrualPhase")
legacyStatusObject.removeValue(forKey: "skinConcerns")
let legacyStatusData = try JSONSerialization.data(withJSONObject: legacyStatusObject)
let migratedLegacyStatus = try JSONDecoder().decode(HealthStatus.self, from: legacyStatusData)
verify(migratedLegacyStatus.skinConcerns.isEmpty && migratedLegacyStatus.menstrualPhase == nil && migratedLegacyStatus.skinNote == "旧记录", "older saved health status must decode without new optional tracking fields")
let proposedGoal = ProposedMajorPlanChange(kind: .goal, reason: "用户主动请求", before: "维持目标", after: "新目标")
verify(proposedGoal?.confirm().authority == .requiresConfirmation, "major proposal must remain confirmation-gated")
verify(
    ProposedMajorPlanChange(kind: .recoveryDowngrade, reason: "错误类型", before: "标准", after: "恢复") == nil,
    "an automatic safety change must not be constructible as a confirmation-gated major proposal or crash the App"
)
verify(PlanAdjuster.authority(for: .mealSubstitution) == .requiresConfirmation, "meal replacement must be user-confirmed")

for kind in [PlanChangeKind.goal, .routineSchedule, .calorieFramework, .progression, .weeklyStructure] {
    verify(PlanAdjuster.authority(for: kind) == .requiresConfirmation, "major change \(kind) must require confirmation")
}

let meal = original.dinner
verify(!meal.ingredients.isEmpty, "meal needs gram-based ingredients")
verify(meal.timedSteps.count >= 6, "meal needs minute-level cooking steps")
verify(meal.portionsAndStorage.contains("2 小时内冷藏"), "meal needs food-safety guidance")
verify(meal.portionsAndStorage.contains("总操作") && meal.portionsAndStorage.contains("分钟"), "meal detail card must be able to surface an explicit total-time label")

let privateData = PrivateCoachData(
    profile: profile,
    dailyCompletions: [DailyCompletion(date: .now, foodCompleted: true, trainingOrRecoveryCompleted: true, bedtimePreparationCompleted: false)],
    healthStatusNotes: [HealthStatus(sleepHours: 7, skinNote: "轻微泛红")]
)
let selection = WeeklyReportSelection(goalProgress: "完成两项", subjectiveReflection: "可坚持", helpRequest: "提醒备饭")
verify(WeeklyReportSharing.makeReport(from: privateData, weekStart: .now, selection: selection, confirmed: false) == nil, "weekly report must not exist without explicit confirmation")
let preview = WeeklyReportSharing.preview(from: privateData, weekStart: .now, selection: selection)
verify(preview.selection == selection && preview.completionRate >= 0 && preview.completionRate <= 1, "weekly report preview must contain only selected text and a bounded completion rate")
let report = WeeklyReportSharing.makeReport(from: privateData, weekStart: .now, selection: selection, confirmed: true)!
verify(report.selection.helpRequest == "提醒备饭", "weekly report keeps only user-selected summary")
verify(WeeklyReportSharing.revoke(report).revokedAt != nil, "weekly report must be revocable")
let reportPayload = try JSONEncoder().encode(report)
let reportPayloadText = String(decoding: reportPayload, as: UTF8.self)
verify(!reportPayloadText.contains("ownerID") && !reportPayloadText.contains(profile.id.uuidString) && !reportPayloadText.contains("local-photo://") && !reportPayloadText.contains("unplannedMealLogs"), "local weekly report must not contain an owner identifier, meal photos, or private meal history")
verify(WeeklyReportSharing.externalPayload(for: report, confirmedForThisShare: false) == nil, "future weekly report sharing must require a fresh explicit confirmation")
let externalWeeklyPayload = WeeklyReportSharing.externalPayload(for: report, confirmedForThisShare: true)!
let externalWeeklyPayloadText = String(decoding: try JSONEncoder().encode(externalWeeklyPayload), as: UTF8.self)
verify(externalWeeklyPayload.period == .currentWeekSoFar, "a partial week share must use a relative period label rather than an exact calendar date")
verify(!externalWeeklyPayloadText.contains("ownerID") && !externalWeeklyPayloadText.contains(profile.id.uuidString) && !externalWeeklyPayloadText.contains("weekStart") && !externalWeeklyPayloadText.contains("consentedAt") && !externalWeeklyPayloadText.contains("revokedAt") && !externalWeeklyPayloadText.contains("local-photo://"), "future external weekly payload must contain only the voluntary minimal summary without a behavioural timestamp")
let completedWeekReport = SharedWeeklyReport(weekStart: .now, observedPlanDays: 7, explicitlySkippedPlanDays: 0, completionRate: 1, selection: WeeklyReportSelection())
verify(WeeklyReportSharing.externalPayload(for: completedWeekReport, confirmedForThisShare: true)?.period == .completedWeek, "a finished week share must remain relative and never add its exact week-start date")
verify(WeeklyReportSharing.externalPayload(for: WeeklyReportSharing.revoke(report), confirmedForThisShare: true) == nil, "a locally revoked weekly report must never produce a future external payload")
let malformedExternalReport = SharedWeeklyReport(
    weekStart: programStart,
    observedPlanDays: 99,
    explicitlySkippedPlanDays: 100,
    completionRate: 2,
    selection: selection,
    consentedAt: programStart
)
verify(
    WeeklyReportSharing.externalPayload(
        for: malformedExternalReport,
        confirmedForThisShare: true,
        now: programStart
    ) == nil,
    "a malformed imported local weekly report must never be promoted into a minimal external payload"
)
verify(
    malformedExternalReport.localDisplayCompletionPercentage == nil
        && report.localDisplayCompletionPercentage != nil,
    "a malformed restored local weekly report must not be rendered as a plausible completion percentage"
)
let futureConsentedReport = SharedWeeklyReport(
    weekStart: programStart,
    observedPlanDays: 1,
    explicitlySkippedPlanDays: 0,
    completionRate: 1,
    selection: selection,
    consentedAt: programStart.addingTimeInterval(60)
)
verify(
    WeeklyReportSharing.externalPayload(
        for: futureConsentedReport,
        confirmedForThisShare: true,
        now: programStart
    ) == nil,
    "a future-dated local consent must never qualify as an external share confirmation"
)
let export = try PrivateExport.makeOwnerExport(privateData)
verify(!export.isEmpty, "owner must be able to export private data")

let restaurantMeal = UnplannedMealEstimator.conservativeEstimate(description: "一份食堂套餐", localPhotoReference: "private-photo://meal-1")
verify(restaurantMeal.isEstimate, "unplanned restaurant meal must always be marked as estimate")
verify(restaurantMeal.estimatedCaloriesRange == 450...900, "no portion data must keep a broad calorie range")
verify(restaurantMeal.displaySummary.contains("不作为精准热量"), "estimate must never be presented as precise")
verify(restaurantMeal.displaySummary.contains("不补练、不挨饿"), "unplanned meal follow-up must not prescribe compensatory exercise or restriction")
verify(restaurantMeal.nextMealGuidance.contains("下一餐正常回到原计划"), "unplanned meal must direct the next meal back to the normal plan")
verify(restaurantMeal.estimateBasis.contains("文字描述") && restaurantMeal.estimateBasis.contains("未做精准识别"), "photo-assisted meal estimates must disclose that they are not precise recognition")
verify(restaurantMeal.historyEstimateLabel == "文字记录 · 宽范围", "compact history rows must retain a short estimate-source boundary")
let compactCandidateHistory = UnplannedMealLog(
    userDescription: "照片候选：米饭/面食/三明治等主食餐｜盘中确认：主食：约 1 碗／1 拳；油：不知道用了多少油｜实际数量：2 个｜照片候选保守区间",
    estimatedCaloriesRange: 450...1_000,
    estimateSource: .onDevicePhotoCandidate
)
verify(
    compactCandidateHistory.displayDescription == "照片候选：米饭/面食/三明治等主食餐",
    "extra-meal history must retain the photo-candidate boundary while hiding internal composition, quantity, and conservative-range markers"
)
verify(
    UnplannedMealEstimator.estimate(
        description: "用户改名的牛肉饭",
        photoSuggestedCaloriesRange: 450...900
    ).userDescription == "用户改名的牛肉饭",
    "changing a photo candidate into an owner-entered dish name must retain the owner's words instead of rewriting it to the candidate category"
)
let correctedRestaurantMeal = UnplannedMealEstimator.estimate(description: "用户确认餐盒分量", manualCaloriesRange: 600...760, manualProteinRange: 25...35, manualRangeConfirmedByOwner: true)
verify(correctedRestaurantMeal.estimatedCaloriesRange == 600...760 && correctedRestaurantMeal.estimatedProteinGramsRange == 25...35 && correctedRestaurantMeal.confidence == .medium, "user-supplied ranges must be retained as a non-precise manual correction")
verify(correctedRestaurantMeal.displaySummary.contains("已补充分量") && correctedRestaurantMeal.displaySummary.contains("不作为精准热量"), "manual range must stay honestly non-precise")
verify(correctedRestaurantMeal.estimateBasis.contains("你补充的分量") && correctedRestaurantMeal.estimateBasis.contains("不是营养检测"), "a manually refined meal range must preserve its user-provided, non-diagnostic basis")
let friedFoodPhotoSuggestion = PrivateFoodPhotoSuggestionPolicy.suggestion(for: ["plate", "fried rice", "chicken"])
verify(friedFoodPhotoSuggestion?.estimatedCaloriesRange == 600...1_900 && friedFoodPhotoSuggestion?.categorySummary.contains("油炸") == true, "on-device labels with several visible food groups must retain room for unconfirmed components instead of using one group's range")
verify(
    friedFoodPhotoSuggestion?.provisionalDescription == "照片候选：油炸/披萨/汉堡/甜点类、米饭/面食/三明治等主食餐、肉/鱼/蛋白质主菜",
    "a photo candidate must persist as an explicitly provisional category rather than masquerading as an owner-entered dish name"
)
verify(friedFoodPhotoSuggestion?.requiresConservativeCalorieRange == true, "fried, dessert, pizza, or burger candidates must not be falsely narrowed by a generic normal-plate default")
let mixedFoodPhotoSuggestion = PrivateFoodPhotoSuggestionPolicy.suggestion(for: ["rice", "chicken", "vegetable"])
verify(mixedFoodPhotoSuggestion?.estimatedCaloriesRange == 450...1_700 && mixedFoodPhotoSuggestion?.requiresConservativeCalorieRange == true && mixedFoodPhotoSuggestion?.hasMultipleUnconfirmedComponents == true && mixedFoodPhotoSuggestion?.conservativeRangeSummary.contains("多样食物") == true, "several non-drink food categories must keep a conservative upper range and disclose that separate components are unconfirmed")
let lightFoodPhotoSuggestion = PrivateFoodPhotoSuggestionPolicy.suggestion(for: ["green salad", "vegetable"])
verify(lightFoodPhotoSuggestion?.estimatedCaloriesRange == 150...650, "on-device photo labels may distinguish a light-food candidate while retaining a broad range")
verify(lightFoodPhotoSuggestion?.requiresConservativeCalorieRange == false, "a light-food candidate may still use an owner-confirmed normal-portion shortcut")
let drinkPhotoSuggestion = PrivateFoodPhotoSuggestionPolicy.suggestion(for: ["milkshake"])
verify(drinkPhotoSuggestion?.estimatedCaloriesRange == 50...500 && drinkPhotoSuggestion?.requiresConservativeCalorieRange == true && drinkPhotoSuggestion?.hasMultipleUnconfirmedComponents == false && drinkPhotoSuggestion?.conservativeRangeSummary.contains("甜饮") == true, "an ambiguous drink photo must retain its full sweet-drink range until the owner confirms label or menu information")
let coffeePhotoSuggestion = PrivateFoodPhotoSuggestionPolicy.suggestion(for: ["coffee"])
verify(coffeePhotoSuggestion?.categoryLabels == ["饮品"] && coffeePhotoSuggestion?.estimatedCaloriesRange == 50...500, "a coffee drink label must remain an ambiguous drink candidate")
verify(PrivateFoodPhotoSuggestionPolicy.suggestion(for: ["coffee table"]) == nil, "a coffee-table furniture label must not fabricate a drink candidate or calories")
let greenTeaPhotoSuggestion = PrivateFoodPhotoSuggestionPolicy.suggestion(for: ["green tea"])
verify(greenTeaPhotoSuggestion?.categoryLabels == ["饮品"] && greenTeaPhotoSuggestion?.estimatedCaloriesRange == 50...500, "a tea word in a Vision label must remain an ambiguous drink candidate")
let steakPhotoSuggestion = PrivateFoodPhotoSuggestionPolicy.suggestion(for: ["steak"])
verify(steakPhotoSuggestion?.categoryLabels == ["肉/鱼/蛋白质主菜"] && steakPhotoSuggestion?.estimatedCaloriesRange == 350...900 && steakPhotoSuggestion?.requiresConservativeCalorieRange == false, "a steak label must not accidentally match the short tea token and invent a drink allowance")
let foodAndDrinkPhotoSuggestion = PrivateFoodPhotoSuggestionPolicy.suggestion(for: ["chicken", "milkshake"])
verify(foodAndDrinkPhotoSuggestion?.estimatedCaloriesRange == 350...1_400 && foodAndDrinkPhotoSuggestion?.requiresConservativeCalorieRange == true, "a visible drink alongside food must widen the candidate upper bound instead of silently discarding a possible sweet-drink extra")
let crowdedFoodAndDrinkPhotoSuggestion = PrivateFoodPhotoSuggestionPolicy.suggestion(for: ["fried rice", "chicken", "milkshake"])
verify(
    crowdedFoodAndDrinkPhotoSuggestion?.categoryLabels == ["油炸/披萨/汉堡/甜点类", "米饭/面食/三明治等主食餐", "饮品"]
        && crowdedFoodAndDrinkPhotoSuggestion?.provisionalDescription.contains("饮品") == true,
    "a drink that widens a crowded mixed-photo estimate must remain visible in the concise candidate and saved provisional description"
)
verify(PrivateFoodPhotoSuggestionPolicy.suggestion(for: []) == nil, "an image without classifier labels must not fabricate a food category")
let unknownFoodPhotoSuggestion = PrivateFoodPhotoSuggestionPolicy.suggestion(for: ["tableware", "plate"])
verify(unknownFoodPhotoSuggestion == nil, "unknown photo labels must require an owner-written dish name rather than create a generic one-tap candidate")
let photoSuggestedMeal = UnplannedMealEstimator.estimate(description: "用户确认为鸡肉炒饭一盘", photoSuggestedCaloriesRange: friedFoodPhotoSuggestion?.estimatedCaloriesRange)
verify(photoSuggestedMeal.estimatedCaloriesRange == 600...1_900 && photoSuggestedMeal.confidence == .low && photoSuggestedMeal.estimateSource == .onDevicePhotoCandidate && photoSuggestedMeal.estimateBasis.contains("本机 Vision"), "photo-derived calories must remain a low-confidence wide range after the owner confirms food and portion in words")
verify(photoSuggestedMeal.historyEstimateLabel == "本机照片候选 · 宽范围", "compact history rows must identify a photo category as a local candidate, not a weighed result")
let photoWithGenericNormalPortion = UnplannedMealEstimator.estimate(
    description: "用户确认的油炸餐食",
    photoSuggestedCaloriesRange: friedFoodPhotoSuggestion?.estimatedCaloriesRange,
    photoRequiresConservativeRange: true,
    compositionConfirmation: MealQuickPortionPreset.regular.composition
)
verify(photoWithGenericNormalPortion.estimatedCaloriesRange == 600...1_900 && photoWithGenericNormalPortion.estimateSource == .onDevicePhotoCandidate && photoWithGenericNormalPortion.compositionConfirmation == nil, "a high-energy or multi-component photo must not be narrowed by an automatic generic normal-portion selection")
let photoRemovedButBoundaryRetained = UnplannedMealEstimator.estimate(
    description: "旧照片已删除，仍保留原来的保守估算边界｜照片候选保守区间",
    photoSuggestedCaloriesRange: 600...1_200,
    photoRequiresConservativeRange: true
)
verify(
    photoRemovedButBoundaryRetained.localPhotoReference == nil
        && photoRemovedButBoundaryRetained.estimatedCaloriesRange == 600...1_200
        && photoRemovedButBoundaryRetained.estimateSource == .onDevicePhotoCandidate,
    "removing a private photo must not silently narrow its already-saved high-energy estimate"
)
verify(MealPortionChoice.small.adjusting(600...1_200) == 270...960, "a small-portion choice must adjust the photo range without asking the owner to calculate calories")
verify(MealPortionChoice.small.restoringApproximateBase(from: 270...960) == 600...1_200, "editing a small photographed portion must reconstruct its broad base before applying a new portion choice")
verify(MealPortionChoice.regular.adjusting(600...1_200) == 600...1_200 && MealPortionChoice.uncertain.adjusting(600...1_200) == 600...1_200, "regular or uncertain portions must retain the original broad photo range")
verify(MealPortionChoice.large.adjusting(600...1_200) == 660...1_800, "a larger portion must conservatively widen the photo estimate upward")
verify(MealPortionChoice.large.restoringApproximateBase(from: 660...1_800) == 600...1_200, "editing a larger photographed portion must not apply its saved multiplier twice")
verify(
    MealPortionChoice.small.displayName == "少一点"
        && MealPortionChoice.regular.displayName == "大致一份"
        && MealPortionChoice.large.displayName == "多一点",
    "unplanned-meal portion labels must use the same plain language as the quick portion choices"
)
verify(
    MealPortionChoice.fromPersistedDisplayName("少量／约半份") == .small
        && MealPortionChoice.fromPersistedDisplayName("常规一份") == .regular
        && MealPortionChoice.fromPersistedDisplayName("较多／约 1.5 份") == .large
        && MealPortionChoice.fromPersistedDisplayName("大致一份") == .regular,
    "legacy and current saved portion labels must both reopen without exposing serialization text in the food description"
)
let smallPhotoSuggestedMeal = UnplannedMealEstimator.estimate(description: "鸡肉炒饭，吃了约半份", photoSuggestedCaloriesRange: 600...1_200, portionChoice: .small)
verify(smallPhotoSuggestedMeal.estimatedCaloriesRange == 270...960 && smallPhotoSuggestedMeal.estimateSource == .onDevicePhotoCandidate, "the saved meal must retain a photo-derived portion-adjusted range without manual calorie input")
let smallHighUncertainPhotoMeal = UnplannedMealEstimator.estimate(
    description: "照片候选为甜饮，喝得少一点",
    photoSuggestedCaloriesRange: 50...500,
    photoRequiresConservativeRange: true,
    portionChoice: .small
)
verify(smallHighUncertainPhotoMeal.estimatedCaloriesRange == 50...500 && smallHighUncertainPhotoMeal.estimateSource == .onDevicePhotoCandidate, "a smaller claimed portion must not narrow a drink or high-energy photo while sugar, toppings, oil, or filling remain unknown")
let ownerOverridePhotoMeal = UnplannedMealEstimator.estimate(description: "有菜单标注", photoSuggestedCaloriesRange: 600...1_200, manualCaloriesRange: 680...720, manualRangeConfirmedByOwner: true)
verify(ownerOverridePhotoMeal.estimatedCaloriesRange == 680...720 && ownerOverridePhotoMeal.confidence == .medium && ownerOverridePhotoMeal.estimateSource == .ownerProvidedRange, "owner-entered menu or portion evidence must override the lower-confidence photo suggestion")
verify(ownerOverridePhotoMeal.historyEstimateLabel == "你确认的范围 · 仍为估算", "compact history rows must distinguish a user-confirmed range from a photo candidate")
let unconfirmedOwnerOverridePhotoMeal = UnplannedMealEstimator.estimate(description: "只填了菜单数字", photoSuggestedCaloriesRange: 600...1_200, manualCaloriesRange: 680...720)
verify(unconfirmedOwnerOverridePhotoMeal.estimatedCaloriesRange == 600...1_200 && unconfirmedOwnerOverridePhotoMeal.estimateSource == .onDevicePhotoCandidate, "a typed manual range must not narrow a photo estimate before the owner confirms oil, add-ons, and eaten amount")
let confirmedComposition = MealCompositionConfirmation(
    staple: .regular,
    protein: .regular,
    vegetables: .regular,
    addedFat: .regular,
    extras: .none,
    consumed: .all
)
verify(confirmedComposition.estimatedCaloriesRange == 511...601 && confirmedComposition.recommendedCalories == 555 && confirmedComposition.isNarrowedByOwner, "complete household-size meal confirmations must use a deterministic tighter range plus one stable diary value")
let manualRangeWithRetainedComposition = UnplannedMealLog(
    userDescription: "菜单范围优先",
    estimatedCaloriesRange: 680...720,
    estimateSource: .ownerProvidedRange,
    compositionConfirmation: confirmedComposition
)
verify(
    !manualRangeWithRetainedComposition.displaySummary.contains("建议记账 555 kcal")
        && manualRangeWithRetainedComposition.displaySummary.contains("估算 680–720 kcal"),
    "a manual menu or scale range must not show a conflicting component-derived diary value"
)
let regularQuickPortion = MealQuickPortionPreset.regular.composition
verify(
    regularQuickPortion.staple == .regular
        && regularQuickPortion.protein == .regular
        && regularQuickPortion.vegetables == .regular
        && regularQuickPortion.consumed == .uncertain
        && regularQuickPortion.addedFat == .uncertain
        && regularQuickPortion.extras == .uncertain,
    "a quick portion preset must confirm only visible plate size without inventing oil, sweet-drink, or eaten-fraction factors"
)
verify(
    MealQuickPortionPreset.light.title == "少一点"
        && MealQuickPortionPreset.regular.title == "大致一份"
        && MealQuickPortionPreset.generous.title == "多一点"
        && !MealQuickPortionPreset.regular.subtitle.contains("拳")
        && !MealQuickPortionPreset.regular.subtitle.contains("掌"),
    "photo portion shortcuts must use everyday comparison words instead of hand-size mnemonics"
)
verify(
    (MealStapleAmount.allCases.map(\.displayName)
        + MealProteinAmount.allCases.map(\.displayName)
        + MealVegetableAmount.allCases.map(\.displayName))
        .allSatisfy { !$0.contains("拳") && !$0.contains("掌") },
    "detailed meal portions must also avoid hand-size mnemonics while retaining eggs as countable items"
)
verify(
    !regularQuickPortion.isNarrowedByOwner
        && regularQuickPortion.estimatedCaloriesRange.upperBound - regularQuickPortion.estimatedCaloriesRange.lowerBound
            > confirmedComposition.estimatedCaloriesRange.upperBound - confirmedComposition.estimatedCaloriesRange.lowerBound,
    "a quick portion preset must retain a wider range until oil and extras are explicitly confirmed"
)
verify(MealQuickPortionPreset.matching(regularQuickPortion) == .regular, "a saved quick portion must restore its selected visual state without pretending every energy factor is known")
verify(MealQuantityNote.actualQuantity(from: "鸡蛋2个", plannedTitle: "鸡蛋") == "实际数量：2 个", "a compact Chinese two-egg entry must be retained as the planned meal's actual count")
verify(
    MealQuantityNote.replacingQuantity(in: "鸡蛋2个", previouslyConfirmed: "实际数量：2 个", with: "3 个") == "鸡蛋 3 个"
        && MealQuantityNote.replacingQuantity(in: "两个鸡蛋", previouslyConfirmed: "实际数量：2 个", with: "3 个") == "3 个鸡蛋"
        && MealQuantityNote.replacingQuantity(in: "鸡蛋两颗", previouslyConfirmed: "实际数量：2 颗", with: "3 颗") == "鸡蛋 3 颗"
        && MealQuantityNote.replacingQuantity(in: "2 小把青菜", previouslyConfirmed: "实际数量：2 小把", with: "3 小把") == "3 小把青菜",
    "changing a picker quantity must replace compact, Chinese-numeral, and custom-unit counts instead of appending a duplicate"
)
verify(MealQuantityNote.actualQuantity(from: "鸡蛋 2个", plannedTitle: "鸡蛋") == "实际数量：2 个", "a mixed-space Chinese two-egg entry must be retained as the planned meal's actual count")
verify(MealQuantityNote.actualQuantity(from: "2个鸡蛋", plannedTitle: "") == "实际数量：2 个", "a picker-first compact two-egg entry must be retained when food is typed after the count")
verify(MealQuantityNote.actualQuantity(from: "2 个鸡蛋", plannedTitle: "") == "实际数量：2 个", "a picker-first spaced two-egg entry must restore as a quantity rather than ordinary prose")
verify(
        MealQuantityNote.actualQuantity(from: "两个鸡蛋", plannedTitle: "") == "实际数量：2 个"
        && MealQuantityNote.actualQuantity(from: "鸡蛋两颗", plannedTitle: "") == "实际数量：2 颗"
        && MealQuantityNote.actualQuantity(from: "鸡蛋两枚", plannedTitle: "") == "实际数量：2 枚"
        && MealQuantityNote.actualQuantity(from: "俩鸡蛋", plannedTitle: "") == "实际数量：2 个"
        && MealQuantityNote.actualQuantity(from: "鸡蛋仨枚", plannedTitle: "") == "实际数量：3 枚"
        && MealQuantityNote.actualQuantity(from: "二十个小番茄", plannedTitle: "") == "实际数量：20 个",
    "ordinary Chinese-numeral count expressions must retain the owner-confirmed count without requiring Arabic digits"
)
verify(
    !MealQuantityNote.hasFoodDescription("两个")
        && MealQuantityNote.hasFoodDescription("两个鸡蛋"),
    "a Chinese-numeral count-only draft must still require a food name"
)
verify(MealQuantityNote.actualQuantity(from: "意面 200g", plannedTitle: "意面") == nil, "a gram amount must not be relabelled as a countable-food quantity")
verify(MealQuantityNote.actualQuantity(from: "意面 200 g", plannedTitle: "意面") == nil, "a spaced gram amount must not be relabelled as a countable-food quantity")
verify(MealQuantityNote.actualQuantity(from: "青菜 2 小把", plannedTitle: "青菜") == "实际数量：2 小把", "a spaced custom count word must remain available for food records")
verify(
    MealQuantityNote.isCountableUnit("小把")
        && MealQuantityNote.isCountableUnit("颗")
        && MealQuantityNote.isCountableUnit("枚")
        && !MealQuantityNote.isCountableUnit("克")
        && !MealQuantityNote.isCountableUnit("ml"),
    "custom quantity units must accept count words but reject weight and volume units"
)
let compositionMeal = UnplannedMealEstimator.estimate(
    description: "照片后确认的一餐",
    photoSuggestedCaloriesRange: 450...1_000,
    compositionConfirmation: confirmedComposition
)
verify(compositionMeal.estimatedCaloriesRange == 511...601 && compositionMeal.compositionConfirmation == confirmedComposition && compositionMeal.estimateSource == .ownerConfirmedComposition && compositionMeal.confidence == .medium, "owner-confirmed plate components must override the broad photo category and retain the structured evidence")
verify(compositionMeal.estimateBasis.contains("主食") && compositionMeal.estimateBasis.contains("不是称重"), "composition-derived estimates must explain their evidence and precision boundary")
verify(
    compositionMeal.displaySummary.contains("建议记账 555 kcal")
        && compositionMeal.displaySummary.contains("确认后的估算范围 511–601")
        && compositionMeal.displaySummary.contains("不是称重值"),
    "a fully confirmed meal must lead with one usable diary value while explicitly keeping its estimate-not-weighed boundary visible"
)
let compositionMealRoundTrip = try JSONDecoder().decode(UnplannedMealLog.self, from: JSONEncoder().encode(compositionMeal))
verify(compositionMealRoundTrip.compositionConfirmation == confirmedComposition && compositionMealRoundTrip.estimatedCaloriesRange == 511...601, "an extra-meal record must round-trip its structured plate confirmation and saved range")
var legacyCompositionMealObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(compositionMeal)) as! [String: Any]
legacyCompositionMealObject.removeValue(forKey: "compositionConfirmation")
let legacyCompositionMealData = try JSONSerialization.data(withJSONObject: legacyCompositionMealObject)
let legacyCompositionMeal = try JSONDecoder().decode(UnplannedMealLog.self, from: legacyCompositionMealData)
verify(legacyCompositionMeal.compositionConfirmation == nil && legacyCompositionMeal.estimatedCaloriesRange == 511...601, "older extra-meal records must decode without changing their already-saved calorie range")
let structuredActualMeal = ActualMealLog(
    date: Date(timeIntervalSince1970: 1_700_000_000),
    slot: .lunch,
    relationship: .different,
    description: "照片确认午餐",
    estimatedCaloriesRange: confirmedComposition.estimatedCaloriesRange,
    compositionConfirmation: confirmedComposition
)
let structuredActualMealRoundTrip = try JSONDecoder().decode(ActualMealLog.self, from: JSONEncoder().encode(structuredActualMeal))
verify(
    structuredActualMealRoundTrip.compositionConfirmation == confirmedComposition
        && structuredActualMealRoundTrip.energyText?.contains("建议记账 555 kcal") == true
        && structuredActualMealRoundTrip.energyText?.contains("估算范围") == true
        && structuredActualMealRoundTrip.energyText?.contains("非称重") == true,
    "a breakfast/lunch/dinner record must restore structured choices without presenting the confirmed estimate as a weighed value"
)
let actualManualRangeWithRetainedComposition = ActualMealLog(
    date: Date(timeIntervalSince1970: 1_700_000_000),
    slot: .dinner,
    relationship: .different,
    description: "菜单范围晚餐",
    portionNote: "菜单/秤热量范围",
    estimatedCaloriesRange: 680...720,
    compositionConfirmation: confirmedComposition
)
verify(
    actualManualRangeWithRetainedComposition.historyEstimateLabel == "菜单/秤范围 · 仍为估算"
        && actualManualRangeWithRetainedComposition.energyText?.contains("680–720 kcal") == true
        && !((actualManualRangeWithRetainedComposition.energyText ?? "").contains("建议记账 555 kcal")),
    "an older direct meal with both markers must keep the owner-provided range ahead of component midpoint"
)
let conservativePhotoWithRetainedComposition = ActualMealLog(
    date: Date(timeIntervalSince1970: 1_700_000_000),
    slot: .dinner,
    relationship: .different,
    description: "混合餐照片候选",
    portionNote: "照片候选保守区间",
    estimatedCaloriesRange: 600...1_900,
    compositionConfirmation: confirmedComposition
)
verify(
    conservativePhotoWithRetainedComposition.historyEstimateLabel == "本机照片候选 · 宽范围"
        && conservativePhotoWithRetainedComposition.energyText?.contains("600–1900 kcal") == true
        && !((conservativePhotoWithRetainedComposition.energyText ?? "").contains("建议记账 555 kcal")),
    "a conservative photo boundary must outrank any retained component midpoint in direct-meal history"
)
var legacyStructuredActualObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(structuredActualMeal)) as! [String: Any]
legacyStructuredActualObject.removeValue(forKey: "compositionConfirmation")
let legacyStructuredActualData = try JSONSerialization.data(withJSONObject: legacyStructuredActualObject)
let legacyStructuredActual = try JSONDecoder().decode(ActualMealLog.self, from: legacyStructuredActualData)
verify(legacyStructuredActual.compositionConfirmation == nil && legacyStructuredActual.estimatedCaloriesRange == 511...601, "older direct meal records must decode without silently recalculating their saved range")
verify(MealCompositionConfirmation().hasAnyOwnerSelection == false, "an untouched photo form must not pretend that the owner confirmed plate components")
let untouchedCompositionMeal = UnplannedMealEstimator.estimate(description: "尚未核对", photoSuggestedCaloriesRange: 450...1_000, compositionConfirmation: MealCompositionConfirmation())
verify(untouchedCompositionMeal.estimatedCaloriesRange == 450...1_000 && untouchedCompositionMeal.estimateSource == .onDevicePhotoCandidate, "an untouched component form must retain the photo candidate instead of producing a misleading component estimate")
let legacyPhotoEstimateData = try JSONEncoder().encode(photoSuggestedMeal)
var legacyPhotoEstimateObject = try JSONSerialization.jsonObject(with: legacyPhotoEstimateData) as! [String: Any]
legacyPhotoEstimateObject.removeValue(forKey: "estimateSource")
let migratedLegacyPhotoEstimate = try JSONDecoder().decode(UnplannedMealLog.self, from: JSONSerialization.data(withJSONObject: legacyPhotoEstimateObject))
verify(migratedLegacyPhotoEstimate.estimatedCaloriesRange == photoSuggestedMeal.estimatedCaloriesRange && migratedLegacyPhotoEstimate.estimateSource == .textAndOptionalPhotoReference, "older meal logs without an estimate-source field must remain readable without inventing on-device photo analysis")
let invalidManualRangeMeal = UnplannedMealEstimator.estimate(description: "无效范围", manualCaloriesRange: -1...50)
verify(invalidManualRangeMeal.estimatedCaloriesRange == 450...900 && invalidManualRangeMeal.confidence == .low, "invalid user ranges must fall back to the conservative estimate")
let foreignPhotoReferenceMeal = UnplannedMealEstimator.conservativeEstimate(description: "外部路径测试", localPhotoReference: "https://example.com/photo.jpg")
verify(foreignPhotoReferenceMeal.localPhotoReference == nil, "unplanned meal logs must reject non-private photo references")
verify(restaurantMeal.spaceSignal(confirmedDailyCalorieFramework: nil) == .unavailable, "unplanned meal must not declare a calorie overage without a user-confirmed framework")
let confirmedFramework = DailyCalorieFramework(lowerBound: 1500, upperBound: 1700)!
verify(restaurantMeal.spaceSignal(confirmedDailyCalorieFramework: confirmedFramework) == .cannotDetermineDailyTotal, "a single broad estimate below a confirmed upper bound cannot prove the whole day remains within range when planned meals have no fabricated calorie totals")
let frameworkBoundaryMeal = UnplannedMealEstimator.estimate(description: "参考上限边界", manualCaloriesRange: 500...1700, manualRangeConfirmedByOwner: true)
verify(frameworkBoundaryMeal.spaceSignal(confirmedDailyCalorieFramework: confirmedFramework) == .cannotDetermineDailyTotal, "an estimate equal to the confirmed upper bound cannot prove the whole day remains within range")
let aboveFrameworkMeal = UnplannedMealEstimator.estimate(description: "高于参考上限", manualCaloriesRange: 500...1701, manualRangeConfirmedByOwner: true)
verify(aboveFrameworkMeal.spaceSignal(confirmedDailyCalorieFramework: confirmedFramework) == .mayExceedDailyFramework, "only an estimate above the confirmed upper bound may produce a cautious space signal")
let sameDayRestaurantLogs = [restaurantMeal, UnplannedMealEstimator.conservativeEstimate(description: "另一份计划外餐食")]
verify(UnplannedMealDaySummary.estimatedUpperBound(for: restaurantMeal.date, logs: sameDayRestaurantLogs) == 1800, "daily unplanned meal summary must sum only the recorded estimate upper bounds")
verify(UnplannedMealDaySummary.spaceSignal(for: restaurantMeal.date, logs: sameDayRestaurantLogs, confirmedFramework: confirmedFramework) == .mayExceedDailyFramework, "multiple unplanned estimate upper bounds may trigger only a cautious framework-space signal")
verify(UnplannedMealDaySummary.spaceSignal(for: restaurantMeal.date, logs: [restaurantMeal], confirmedFramework: confirmedFramework) == .cannotDetermineDailyTotal, "an external-meal aggregate below the daily framework cannot claim the full day remains within range without verified planned-meal calories")
verify(UnplannedMealDaySummary.spaceSignal(for: restaurantMeal.date, logs: sameDayRestaurantLogs, confirmedFramework: nil) == .unavailable, "daily unplanned meal summary must remain unavailable without explicit calorie confirmation")
let tomorrowRestaurantMeal = UnplannedMealEstimator.conservativeEstimate(description: "明天的计划外餐食", at: restaurantMeal.date.addingTimeInterval(86_400))
verify(UnplannedMealDaySummary.estimatedUpperBound(for: restaurantMeal.date, logs: sameDayRestaurantLogs + [tomorrowRestaurantMeal]) == 1800, "daily unplanned meal summary must exclude meals recorded on another date")
verify(UnplannedMealSpaceSignal.mayExceedDailyFramework.displayText.contains("不能据此断言已超标"), "a cautious framework signal must never claim that the user has already exceeded intake")
let implausibleImportedMeal = UnplannedMealLog(
    date: restaurantMeal.date,
    userDescription: "损坏导入的异常数值",
    estimatedCaloriesRange: 0...Int.max,
    estimatedProteinGramsRange: 0...Int.max,
    confidence: .medium
)
verify(
    implausibleImportedMeal.estimatedCaloriesRange == nil
        && implausibleImportedMeal.estimatedProteinGramsRange == nil
        && implausibleImportedMeal.confidence == nil
        && UnplannedMealDaySummary.estimatedUpperBound(for: restaurantMeal.date, logs: [implausibleImportedMeal]) == nil,
    "implausible imported meal ranges must degrade to a text-only note rather than distort or overflow daily calorie guidance"
)
let mealLoggingBaseline = PrivateCoachData(profile: UserProfile(displayName: "餐食边界测试", dailyCalorieFramework: confirmedFramework))
var mealLoggingResult = mealLoggingBaseline
mealLoggingResult.unplannedMealLogs.append(restaurantMeal)
verify(UnplannedMealDaySummary.preservesPlan(before: mealLoggingBaseline, after: mealLoggingResult), "recording an unplanned estimate must not alter meal cards, workouts, goals, health state, or plan changes")
let mealLoggingWithWorkoutDraft = PrivateCoachData(
    profile: UserProfile(displayName: "餐食与训练草稿边界"),
    pendingWorkoutConfirmations: [PendingWorkoutConfirmation(
        workout: ConfirmedHealthWorkout(
            dayIndex: 1,
            startedAt: restaurantMeal.date,
            endedAt: restaurantMeal.date.addingTimeInterval(60),
            kind: .coreTraining
        ),
        savedAt: restaurantMeal.date
    )]
)
var changedMealLoggingWithWorkoutDraft = mealLoggingWithWorkoutDraft
changedMealLoggingWithWorkoutDraft.unplannedMealLogs.append(restaurantMeal)
verify(
    UnplannedMealDaySummary.preservesPlan(before: mealLoggingWithWorkoutDraft, after: changedMealLoggingWithWorkoutDraft),
    "recording an unplanned estimate must not alter a locally saved real-workout confirmation draft"
)
verify(restaurantMeal.nextMealGuidance.contains("不补练、不挨饿"), "unplanned estimate guidance must never prescribe compensation")
let deleteMealPhotoReference = "local-photo://00000000-0000-0000-0000-000000000003"
let deleteMealLog = UnplannedMealEstimator.conservativeEstimate(description: "删除单条测试", localPhotoReference: deleteMealPhotoReference, at: intervalBase)
let retainedMealLog = UnplannedMealEstimator.conservativeEstimate(description: "保留另一条测试", at: intervalBase)
let singleLogDeletion = UnplannedMealDeletionService.prepareDeletion(logID: deleteMealLog.id, from: PrivateCoachData(profile: profile, unplannedMealLogs: [deleteMealLog, retainedMealLog]))
verify(singleLogDeletion.deletedLog?.id == deleteMealLog.id && singleLogDeletion.data.unplannedMealLogs == [retainedMealLog] && singleLogDeletion.photoReferenceToDelete == deleteMealPhotoReference, "deleting one unplanned-meal log must remove only that log and expose its unshared private photo")
let duplicatePhotoLog = UnplannedMealLog(date: intervalBase, localPhotoReference: deleteMealPhotoReference, userDescription: "共享私有照片引用测试")
let sharedPhotoDeletion = UnplannedMealDeletionService.prepareDeletion(logID: deleteMealLog.id, from: PrivateCoachData(profile: profile, unplannedMealLogs: [deleteMealLog, duplicatePhotoLog]))
verify(sharedPhotoDeletion.deletedLog?.id == deleteMealLog.id && sharedPhotoDeletion.photoReferenceToDelete == nil && sharedPhotoDeletion.data.unplannedMealLogs == [duplicatePhotoLog], "deleting one record must retain a photo still referenced by another private record")
let actualMealSharingDeletedPhoto = ActualMealLog(date: intervalBase, slot: .lunch, relationship: .different, description: "实际午餐仍引用照片", localPhotoReference: deleteMealPhotoReference, estimatedCaloriesRange: 400...700)
let crossTypeSharedPhotoDeletion = UnplannedMealDeletionService.prepareDeletion(logID: deleteMealLog.id, from: PrivateCoachData(profile: profile, unplannedMealLogs: [deleteMealLog], actualMealLogs: [actualMealSharingDeletedPhoto]))
verify(crossTypeSharedPhotoDeletion.photoReferenceToDelete == nil && crossTypeSharedPhotoDeletion.data.actualMealLogs == [actualMealSharingDeletedPhoto], "deleting an unplanned meal must retain a private photo still referenced by an actual breakfast/lunch/dinner record")
let missingLogDeletion = UnplannedMealDeletionService.prepareDeletion(logID: UUID(), from: PrivateCoachData(profile: profile, unplannedMealLogs: [deleteMealLog]))
verify(missingLogDeletion.deletedLog == nil && missingLogDeletion.data.unplannedMealLogs == [deleteMealLog] && missingLogDeletion.photoReferenceToDelete == nil, "unknown unplanned-meal deletion must not mutate records or photos")
let legacyProfile = UserProfile(displayName: "旧档案")
let legacyProfileData = try JSONEncoder().encode(legacyProfile)
var legacyProfileObject = try JSONSerialization.jsonObject(with: legacyProfileData) as! [String: Any]
legacyProfileObject.removeValue(forKey: "dailyCalorieFramework")
legacyProfileObject.removeValue(forKey: "workSchedule")
legacyProfileObject.removeValue(forKey: "commuteMode")
legacyProfileObject.removeValue(forKey: "kitchenSetup")
legacyProfileObject.removeValue(forKey: "foodPreferences")
legacyProfileObject.removeValue(forKey: "primaryGoal")
legacyProfileObject.removeValue(forKey: "trainingExperience")
legacyProfileObject.removeValue(forKey: "availableEquipment")
legacyProfileObject.removeValue(forKey: "heightCm")
legacyProfileObject.removeValue(forKey: "dailyRoutineSchedule")
legacyProfileObject.removeValue(forKey: "dailyReminderPreferences")
legacyProfileObject.removeValue(forKey: "nearbyOfferPreferences")
let migratedLegacyProfile = try JSONDecoder().decode(UserProfile.self, from: JSONSerialization.data(withJSONObject: legacyProfileObject))
verify(migratedLegacyProfile.dailyCalorieFramework == nil && migratedLegacyProfile.displayName == "旧档案", "old profiles must decode without a calorie framework")
verify(migratedLegacyProfile.workSchedule == nil && migratedLegacyProfile.commuteMode == nil && migratedLegacyProfile.kitchenSetup == nil && migratedLegacyProfile.foodPreferences == nil && migratedLegacyProfile.primaryGoal == nil && migratedLegacyProfile.trainingExperience == nil && migratedLegacyProfile.availableEquipment == nil && migratedLegacyProfile.heightCm == nil && migratedLegacyProfile.dailyRoutineSchedule == nil && migratedLegacyProfile.dailyReminderPreferences == nil && migratedLegacyProfile.nearbyOfferPreferences == nil, "older profiles must decode without personal-routine, goal, equipment, reminder, and offer-preference fields")
let personalProfile = UserProfile(displayName: "有野", approximateArea: "望京附近", workSchedule: "10:00–19:00", commuteMode: "电动车", kitchenSetup: "电饭锅 + 一个电磁炉锅", foodPreferences: "默认自炊", primaryGoal: "腰腹、体态和睡眠", trainingExperience: "零基础", availableEquipment: "瑜伽垫", heightCm: 165)
let reloadedPersonalProfile = try JSONDecoder().decode(UserProfile.self, from: JSONEncoder().encode(personalProfile))
verify(reloadedPersonalProfile == personalProfile, "personal routine fields must remain private and survive a local profile reload")
let personalizationProposals = PersonalizationAdvisor.proposals(for: personalProfile)
verify(personalizationProposals.map(\.area) == [.goal, .foundation, .equipment, .schedule, .commute, .kitchen, .food, .area], "private profile fields must produce reviewable personalization proposals in a stable order")
verify(personalizationProposals.allSatisfy { !$0.confirmationBoundary.isEmpty }, "personalization proposals must state a confirmation boundary")
verify(personalizationProposals.first(where: { $0.area == .kitchen })?.confirmationBoundary.contains("不会自动改菜单") == true, "kitchen personalization must not silently change a meal")
verify(personalizationProposals.first(where: { $0.area == .goal })?.confirmationBoundary.contains("逐次确认") == true, "goal personalization must never silently change a major plan")
verify(reloadedPersonalProfile.primaryGoal == "腰腹、体态和睡眠" && reloadedPersonalProfile.trainingExperience == "零基础" && reloadedPersonalProfile.availableEquipment == "瑜伽垫" && reloadedPersonalProfile.heightCm == 165, "private goal, foundation, equipment, and optional height must survive a local reload")
verify(PersonalizationAdvisor.missingProfilePrompt(for: personalProfile) == nil, "a complete routine profile must not ask for already-provided details")
let partialRoutineProfile = UserProfile(displayName: "仅称呼")
verify(PersonalizationAdvisor.proposals(for: partialRoutineProfile).isEmpty, "an empty routine profile must not invent a personalized recommendation")
verify(PersonalizationAdvisor.missingProfilePrompt(for: partialRoutineProfile)?.contains("作息") == true, "an incomplete routine profile must transparently name optional missing inputs")
let onboardingRoutine = DailyRoutineSchedule(wakeMinutes: 12 * 60, breakfastMinutes: 12 * 60 + 30, lunchMinutes: 13 * 60, dinnerMinutes: 19 * 60, trainingMinutes: 20 * 60, bedtimePreparationMinutes: 23 * 60 + 15, quietStartMinutes: 23 * 60 + 30, quietEndMinutes: 9 * 60)!
let onboardingInput = FirstRunProfileInput(displayName: "有野", primaryGoal: "腰腹与体态", trainingExperience: "零基础", availableEquipment: "瑜伽垫", kitchenSetup: "电饭锅 + 一个电磁炉锅", workSchedule: "10:00–19:00", dailyRoutineSchedule: onboardingRoutine)
let preexistingOnboardingProfile = UserProfile(displayName: "旧称呼", restingHeartRateBaseline: 58, dailyCalorieFramework: DailyCalorieFramework(lowerBound: 1500, upperBound: 1700), nearbyOfferPreferences: NearbyOfferPreferences(swimmingRemindersEnabled: true))
let appliedOnboardingProfile = onboardingInput.applying(to: preexistingOnboardingProfile)
verify(appliedOnboardingProfile.displayName == "有野" && appliedOnboardingProfile.primaryGoal == "腰腹与体态" && appliedOnboardingProfile.trainingExperience == "零基础" && appliedOnboardingProfile.availableEquipment == "瑜伽垫" && appliedOnboardingProfile.kitchenSetup == "电饭锅 + 一个电磁炉锅" && appliedOnboardingProfile.workSchedule == "10:00–19:00" && appliedOnboardingProfile.dailyRoutineSchedule == onboardingRoutine, "first-run profile input must save only the owner-entered execution context")
verify(appliedOnboardingProfile.restingHeartRateBaseline == 58 && appliedOnboardingProfile.dailyCalorieFramework?.displayName == "1500–1700 kcal/日" && appliedOnboardingProfile.nearbyOfferPreferences?.swimmingRemindersEnabled == true, "first-run profile input must not silently alter health, calorie, or nearby-offer preferences")
verify(appliedOnboardingProfile.id == preexistingOnboardingProfile.id, "first-run context input must retain the existing local owner identity")
let freshOnboardingProfile = onboardingInput.applying(to: UserProfile(displayName: "我"))
verify(freshOnboardingProfile.dailyReminderPreferences == nil, "suggested first-run routine must not silently enable local reminders")
verify(freshOnboardingProfile.nearbyOfferPreferences == nil && freshOnboardingProfile.dailyCalorieFramework == nil && freshOnboardingProfile.restingHeartRateBaseline == nil, "first-run setup must not silently opt into offers, calorie framework, or HealthKit-derived recovery inputs")
verify(FirstRunProfileInput(displayName: "   ", primaryGoal: "  ").applying(to: UserProfile(displayName: "原称呼")).displayName == "我", "blank first-run display names must safely use the local default")
let breakfastTime = fixedCalendar.date(bySettingHour: 8, minute: 0, second: 0, of: original.date)!
let lunchTime = fixedCalendar.date(bySettingHour: 12, minute: 0, second: 0, of: original.date)!
let dinnerTime = fixedCalendar.date(bySettingHour: 19, minute: 0, second: 0, of: original.date)!
let noonRoutine = DailyRoutineSchedule(
    wakeMinutes: 12 * 60,
    breakfastMinutes: 12 * 60 + 30,
    lunchMinutes: 13 * 60,
    dinnerMinutes: 19 * 60,
    trainingMinutes: 20 * 60,
    bedtimePreparationMinutes: 23 * 60,
    quietStartMinutes: 23 * 60 + 30,
    quietEndMinutes: 9 * 60
)!
let optInOfferPreferences = NearbyOfferPreferences(swimmingRemindersEnabled: true, basketSavingsThresholdYuan: 20, swimSingleEntryThresholdYuan: 28)
let hostileOfferPreferencesJSON = """
{
  "gymRemindersEnabled": false,
  "swimmingRemindersEnabled": true,
  "bikeRemindersEnabled": false,
  "groceryRemindersEnabled": true,
  "deliveryRemindersEnabled": false,
  "basketSavingsThresholdYuan": -999,
  "swimSingleEntryThresholdYuan": 999
}
""".data(using: .utf8)!
let hostileOfferPreferences = try JSONDecoder().decode(NearbyOfferPreferences.self, from: hostileOfferPreferencesJSON)
verify(
    hostileOfferPreferences.basketSavingsThresholdYuan == 15 && hostileOfferPreferences.swimSingleEntryThresholdYuan == 30,
    "decoded nearby-offer preferences must retain the ¥15 grocery floor and ¥30 swim ceiling"
)
let optInDailyReminders = DailyReminderPreferences(lunchEnabled: true, trainingEnabled: true, bedtimePreparationEnabled: true)
let routineProfile = UserProfile(displayName: "晚起用户", dailyRoutineSchedule: noonRoutine, dailyReminderPreferences: optInDailyReminders, nearbyOfferPreferences: optInOfferPreferences)
let reloadedRoutineProfile = try JSONDecoder().decode(UserProfile.self, from: JSONEncoder().encode(routineProfile))
verify(reloadedRoutineProfile == routineProfile && reloadedRoutineProfile.dailyReminderPreferences?.hasAnyEnabled == true && reloadedRoutineProfile.nearbyOfferPreferences?.hasAnyReminderEnabled == true, "routine, daily-reminder, and offer preferences must remain opt-in, private, and survive a local reload")
let routinePrivateData = PrivateCoachData(profile: routineProfile)
let resetAfterPrivateDeletion = PrivateCoachData(profile: UserProfile(displayName: "我"))
verify(routinePrivateData.profile.dailyRoutineSchedule != nil && routinePrivateData.profile.dailyReminderPreferences != nil && routinePrivateData.profile.nearbyOfferPreferences != nil && resetAfterPrivateDeletion.profile.dailyRoutineSchedule == nil && resetAfterPrivateDeletion.profile.dailyReminderPreferences == nil && resetAfterPrivateDeletion.profile.nearbyOfferPreferences == nil, "a replacement private-data shell after owner deletion must not retain routine, reminder, or nearby-offer preferences")
let dailyReminderRequests = DailyReminderPlan.requests(schedule: noonRoutine, preferences: optInDailyReminders)
verify(dailyReminderRequests.map(\.kind) == [.lunch, .training, .bedtimePreparation], "only individually enabled daily reminders may be scheduled")
verify(dailyReminderRequests.map(\.timeText) == ["13:00", "20:00", "23:00"], "daily reminders must use the owner-selected routine times")
verify(DailyReminderPlan.requests(schedule: nil, preferences: optInDailyReminders).isEmpty, "daily reminders must not invent a schedule without owner times")
verify(DailyReminderPlan.requests(schedule: noonRoutine, preferences: DailyReminderPreferences()).isEmpty, "a fully disabled reminder profile must schedule nothing")
let quietTrainingRoutine = DailyRoutineSchedule(wakeMinutes: 8 * 60, breakfastMinutes: 8 * 60 + 30, lunchMinutes: 12 * 60, dinnerMinutes: 18 * 60, trainingMinutes: 23 * 60 + 45, bedtimePreparationMinutes: 22 * 60, quietStartMinutes: 23 * 60 + 30, quietEndMinutes: 8 * 60)!
verify(DailyReminderPlan.isQuiet(23 * 60 + 45, in: quietTrainingRoutine) && !DailyReminderPlan.isQuiet(22 * 60, in: quietTrainingRoutine), "quiet-time boundary must correctly support cross-midnight owner schedules")
verify(DailyReminderPlan.requests(schedule: quietTrainingRoutine, preferences: DailyReminderPreferences(trainingEnabled: true, bedtimePreparationEnabled: true)).map(\.kind) == [.bedtimePreparation], "quiet-time reminders must be omitted rather than moved to another time")
verify(DailyReminderPlan.unavailableReason(schedule: quietTrainingRoutine, preferences: DailyReminderPreferences(trainingEnabled: true))?.contains("不会被自动改到其他时间") == true, "quiet-time reminder conflicts must be disclosed rather than silently rescheduled")
verify(UnplannedMealLoggingPolicy.validationError(for: programStart, at: programStart, calendar: fixedCalendar) == nil, "an unplanned meal may be logged only on its current formal plan day")
verify(UnplannedMealLoggingPolicy.validationError(for: programStart, at: fixedCalendar.date(byAdding: .day, value: 1, to: programStart)!, calendar: fixedCalendar)?.contains("日期已切换") == true, "a stale unplanned-meal form must fail closed after midnight")
verify(UnplannedMealLoggingPolicy.validationError(for: preparationDate, at: preparationDate, calendar: fixedCalendar)?.contains("不是第 1–56 天") == true, "unplanned meal logging must not create a preparation-day execution record")
var removableBaselineProfile = UserProfile(displayName: "可撤回基线", restingHeartRateBaseline: 58)
removableBaselineProfile.restingHeartRateBaseline = nil
verify(removableBaselineProfile.restingHeartRateBaseline == nil, "the user-confirmed resting-heart-rate baseline must be removable rather than permanently influencing recovery")
verify(DailyRoutineSchedule(wakeMinutes: -1, breakfastMinutes: 0, lunchMinutes: 0, dinnerMinutes: 0, trainingMinutes: 0, bedtimePreparationMinutes: 0, quietStartMinutes: 0, quietEndMinutes: 0) == nil, "routine schedules must reject invalid clock values")
let malformedRoutineJSON = """
{
  "wakeMinutes": -1,
  "breakfastMinutes": 480,
  "lunchMinutes": 720,
  "dinnerMinutes": 1080,
  "trainingMinutes": 1200,
  "bedtimePreparationMinutes": 1380,
  "quietStartMinutes": 1410,
  "quietEndMinutes": 540
}
""".data(using: .utf8)!
do {
    _ = try JSONDecoder().decode(DailyRoutineSchedule.self, from: malformedRoutineJSON)
    verify(false, "malformed restored routine times must fail closed rather than schedule invalid reminders")
} catch {
    verify(true, "malformed restored routine times must fail closed rather than schedule invalid reminders")
}
let verifiedAt = fixedCalendar.date(bySettingHour: 12, minute: 0, second: 0, of: original.date)!
let verifiedSwimOffer = VerifiedNearbyOffer(kind: .swimming, title: "单次游泳", nearbyPlace: "附近泳馆", sourceName: "官方团购页", checkedAt: verifiedAt, terms: "限工作日使用", priceYuan: 28)
verify(NearbyOfferPolicy.presentation(for: verifiedSwimOffer, preferences: optInOfferPreferences, now: verifiedAt) == .explicitRequestRequired, "a saved nearby-offer preference must not turn an unprompted provider result into an alert")
verify(NearbyOfferPolicy.presentation(for: verifiedSwimOffer, preferences: optInOfferPreferences, requestContext: .ownerInitiatedNearbySearch, now: verifiedAt) == .eligible, "a complete, fresh, opted-in swim offer under the owner threshold may be eligible only after an owner-initiated nearby search")
let disabledOfferPreferences = NearbyOfferPreferences(swimmingRemindersEnabled: false, swimSingleEntryThresholdYuan: 30)
verify(NearbyOfferPolicy.presentation(for: verifiedSwimOffer, preferences: disabledOfferPreferences, requestContext: .ownerInitiatedNearbySearch, now: verifiedAt) == .preferenceDisabled, "a verified offer must not notify when the owner disabled that category")
let missingEvidenceOffer = VerifiedNearbyOffer(kind: .swimming, title: "单次游泳", nearbyPlace: "附近泳馆", sourceName: "", checkedAt: verifiedAt, terms: "限工作日使用", priceYuan: 28)
verify(NearbyOfferPolicy.presentation(for: missingEvidenceOffer, preferences: optInOfferPreferences, requestContext: .ownerInitiatedNearbySearch, now: verifiedAt) == .missingEvidence, "offers without source and terms evidence must remain pending verification")
verify(NearbyOfferPolicy.presentation(for: verifiedSwimOffer, preferences: optInOfferPreferences, requestContext: .ownerInitiatedNearbySearch, now: verifiedAt.addingTimeInterval(NearbyOfferPolicy.maximumFreshness + 1)) == .stale, "stale offers must not remain eligible for a reminder")
let futureCheckedSwimOffer = VerifiedNearbyOffer(kind: .swimming, title: "单次游泳", nearbyPlace: "附近泳馆", sourceName: "官方团购页", checkedAt: verifiedAt.addingTimeInterval(60), terms: "限工作日使用", priceYuan: 28)
verify(NearbyOfferPolicy.presentation(for: futureCheckedSwimOffer, preferences: optInOfferPreferences, requestContext: .ownerInitiatedNearbySearch, now: verifiedAt) == .stale, "a future provider timestamp must never be treated as fresh evidence")
let expensiveSwimOffer = VerifiedNearbyOffer(kind: .swimming, title: "单次游泳", nearbyPlace: "附近泳馆", sourceName: "官方团购页", checkedAt: verifiedAt, terms: "限工作日使用", priceYuan: 31)
verify(NearbyOfferPolicy.presentation(for: expensiveSwimOffer, preferences: optInOfferPreferences, requestContext: .ownerInitiatedNearbySearch, now: verifiedAt) == .belowThreshold, "a verified offer must still meet the owner’s price threshold")
let invalidPriceSwimOffer = VerifiedNearbyOffer(kind: .swimming, title: "单次游泳", nearbyPlace: "附近泳馆", sourceName: "官方团购页", checkedAt: verifiedAt, terms: "限工作日使用", priceYuan: -1)
verify(NearbyOfferPolicy.presentation(for: invalidPriceSwimOffer, preferences: optInOfferPreferences, requestContext: .ownerInitiatedNearbySearch, now: verifiedAt) == .belowThreshold, "a negative provider price must never become an eligible offer")
let malformedSavingsOffer = VerifiedNearbyOffer(kind: .grocery, title: "食材满减", nearbyPlace: "附近商超", sourceName: "官方页面", checkedAt: verifiedAt, terms: "仅当日", basketSavingsYuan: .nan)
verify(NearbyOfferPolicy.presentation(for: malformedSavingsOffer, preferences: NearbyOfferPreferences(groceryRemindersEnabled: true), requestContext: .ownerInitiatedNearbySearch, now: verifiedAt) == .belowThreshold, "a non-finite provider saving must never become an eligible offer")
let verifiedDeliveryOffer = VerifiedNearbyOffer(kind: .delivery, title: "餐品", nearbyPlace: "附近", sourceName: "平台页面", checkedAt: verifiedAt, terms: "仅示例", basketSavingsYuan: 20)
let deliveryPreferences = NearbyOfferPreferences(deliveryRemindersEnabled: true, basketSavingsThresholdYuan: 15)
verify(NearbyOfferPolicy.presentation(for: verifiedDeliveryOffer, preferences: deliveryPreferences, requestContext: .ownerInitiatedNearbySearch, now: verifiedAt) == .explicitRequestRequired, "delivery offers must never be eligible from a generic nearby-search request")
verify(NearbyOfferPolicy.presentation(for: verifiedDeliveryOffer, preferences: deliveryPreferences, requestContext: .explicitDeliveryRequest, now: verifiedAt) == .eligible, "a delivery offer can be evaluated only within the owner’s explicit delivery request")
verify(NearbyOfferPolicy.presentation(for: nil, preferences: optInOfferPreferences, now: verifiedAt) == .awaitingProvider, "no provider result must remain an honest unconnected state")
verify(TodayNextStepAdvisor.recommend(plan: original, completion: nil, now: breakfastTime, calendar: fixedCalendar).kind == .breakfast, "today home should surface breakfast preparation in the morning when training is not due")
verify(TodayNextStepAdvisor.recommend(plan: original, completion: nil, now: lunchTime, calendar: fixedCalendar).kind == .lunch, "today home should surface lunch preparation around midday when training is not due")
verify(TodayNextStepAdvisor.recommend(plan: original, completion: nil, now: dinnerTime, calendar: fixedCalendar).kind == .training, "today home must put unfinished training ahead of dinner in the evening")
verify(TodayNextStepAdvisor.quickLogMealSlot(plan: original, completion: nil, now: dinnerTime, calendar: fixedCalendar) == .dinner, "the visible quick-log meal must be dinner in the dinner window")
let breakfastMarked = DailyCompletion(date: original.date, foodCompleted: false, breakfastCompleted: true, lunchCompleted: false, dinnerCompleted: false, trainingOrRecoveryCompleted: false, bedtimePreparationCompleted: false)
verify(TodayNextStepAdvisor.quickLogMealSlot(plan: original, completion: breakfastMarked, now: lunchTime, calendar: fixedCalendar) == .lunch, "the prep shortcut must follow the current time window rather than legacy meal-completion flags")
verify(TodayNextStepAdvisor.recommend(plan: original, completion: nil, schedule: noonRoutine, now: lunchTime, calendar: fixedCalendar).kind == .breakfast, "a noon routine should surface the first meal after the chosen wake time")
let earlyRoutineOpen = fixedCalendar.date(bySettingHour: 8, minute: 0, second: 0, of: original.date)!
verify(TodayNextStepAdvisor.recommend(plan: original, completion: nil, schedule: noonRoutine, now: earlyRoutineOpen, calendar: fixedCalendar).kind == .training, "opening before a chosen noon wake time must not surface a meal before the day starts")
let noonDinnerPrep = fixedCalendar.date(bySettingHour: 18, minute: 0, second: 0, of: original.date)!
verify(TodayNextStepAdvisor.recommend(plan: original, completion: nil, schedule: noonRoutine, now: noonDinnerPrep, calendar: fixedCalendar).kind == .dinner, "before the selected training lead-in, today home should surface dinner preparation")
let noonTrainingLeadIn = fixedCalendar.date(bySettingHour: 19, minute: 35, second: 0, of: original.date)!
verify(TodayNextStepAdvisor.recommend(plan: original, completion: nil, schedule: noonRoutine, now: noonTrainingLeadIn, calendar: fixedCalendar).kind == .training, "within 30 minutes of the selected training time, today home should surface training")
let noonTrainingDone = DailyCompletion(date: original.date, foodCompleted: false, trainingOrRecoveryCompleted: true, bedtimePreparationCompleted: false)
verify(TodayNextStepAdvisor.recommend(plan: original, completion: noonTrainingDone, schedule: noonRoutine, now: noonTrainingLeadIn, calendar: fixedCalendar).kind == .dinner, "after training is confirmed, the home card should advance to dinner preparation")
let foodOnlyComplete = DailyCompletion(date: original.date, foodCompleted: true, trainingOrRecoveryCompleted: false, bedtimePreparationCompleted: false)
verify(TodayNextStepAdvisor.recommend(plan: original, completion: foodOnlyComplete, now: dinnerTime, calendar: fixedCalendar).kind == .training, "at the training window, today home must recommend the training minimum")
let breakfastOnlyComplete = DailyCompletion(date: original.date, foodCompleted: false, breakfastCompleted: true, lunchCompleted: false, dinnerCompleted: false, trainingOrRecoveryCompleted: false, bedtimePreparationCompleted: false)
verify(TodayNextStepAdvisor.recommend(plan: original, completion: breakfastOnlyComplete, now: lunchTime, calendar: fixedCalendar).kind == .lunch, "after breakfast, today home should surface lunch preparation")
let breakfastLunchComplete = DailyCompletion(date: original.date, foodCompleted: false, breakfastCompleted: true, lunchCompleted: true, dinnerCompleted: false, trainingOrRecoveryCompleted: false, bedtimePreparationCompleted: false)
verify(TodayNextStepAdvisor.recommend(plan: original, completion: breakfastLunchComplete, now: dinnerTime, calendar: fixedCalendar).kind == .training, "at the training window, today home should surface training after meal preparation")
let dinnerCompleteLunchUnrecorded = DailyCompletion(date: original.date, foodCompleted: false, breakfastCompleted: false, lunchCompleted: false, dinnerCompleted: true, trainingOrRecoveryCompleted: false, bedtimePreparationCompleted: false)
verify(
    TodayNextStepAdvisor.recommend(plan: original, completion: dinnerCompleteLunchUnrecorded, now: dinnerTime, calendar: fixedCalendar).kind == .training,
    "after dinner, an unlogged lunch must remain manually recordable but never be prescribed as a make-up next step"
)
verify(
    TodayNextStepAdvisor.quickLogMealSlot(plan: original, completion: dinnerCompleteLunchUnrecorded, now: dinnerTime, calendar: fixedCalendar) == .dinner,
    "a dinner-time quick photo must retain the dinner slot even when earlier meals were never logged"
)
let defaultDeepNight = fixedCalendar.date(bySettingHour: 0, minute: 30, second: 0, of: original.date)!
verify(
    TodayNextStepAdvisor.recommend(plan: original, completion: dinnerCompleteLunchUnrecorded, now: defaultDeepNight, calendar: fixedCalendar).kind == .bedtimePreparation,
    "deep-night home guidance must prioritise bedtime preparation instead of a missed meal or workout"
)
let bedtimeAlreadyPrepared = DailyCompletion(date: original.date, foodCompleted: false, breakfastCompleted: false, lunchCompleted: false, dinnerCompleted: true, trainingOrRecoveryCompleted: false, bedtimePreparationCompleted: true)
verify(
    TodayNextStepAdvisor.recommend(plan: original, completion: bedtimeAlreadyPrepared, now: defaultDeepNight, calendar: fixedCalendar).kind == .windDown,
    "after bedtime preparation, deep-night home guidance must preserve rest rather than prescribe catch-up training"
)
let afterMidnightRoutine = DailyRoutineSchedule(wakeMinutes: 9 * 60, breakfastMinutes: 9 * 60 + 30, lunchMinutes: 13 * 60, dinnerMinutes: 19 * 60, trainingMinutes: 20 * 60, bedtimePreparationMinutes: 30, quietStartMinutes: 1 * 60, quietEndMinutes: 8 * 60)!
let beforeAfterMidnightBedtime = fixedCalendar.date(bySettingHour: 23, minute: 45, second: 0, of: original.date)!
let afterMidnightBedtime = fixedCalendar.date(bySettingHour: 0, minute: 45, second: 0, of: original.date)!
verify(
    TodayNextStepAdvisor.recommend(plan: original, completion: nil, schedule: afterMidnightRoutine, now: beforeAfterMidnightBedtime, calendar: fixedCalendar).kind == .training
        && TodayNextStepAdvisor.recommend(plan: original, completion: nil, schedule: afterMidnightRoutine, now: afterMidnightBedtime, calendar: fixedCalendar).kind == .bedtimePreparation,
    "a user-owned after-midnight bedtime must not trigger early wind-down before its actual circular boundary"
)
let lateWakeLunchDinnerComplete = DailyCompletion(date: original.date, foodCompleted: false, breakfastCompleted: false, lunchCompleted: true, dinnerCompleted: true, breakfastWaivedForLateWake: true, trainingOrRecoveryCompleted: false, bedtimePreparationCompleted: false)
verify(lateWakeLunchDinnerComplete.foodCompleted && !lateWakeLunchDinnerComplete.breakfastCompleted, "late wake acknowledgement must complete today's food pillar without falsely recording breakfast as eaten")
verify(lateWakeLunchDinnerComplete.foodProgressDescription == "已完成 2 餐｜早餐无需补", "late-wake food summary must report two actual meals and the waived breakfast rather than falsely displaying three meals")
let lateWakeUnacknowledged = DailyCompletion(date: original.date, foodCompleted: false, breakfastCompleted: false, lunchCompleted: true, dinnerCompleted: true, trainingOrRecoveryCompleted: false, bedtimePreparationCompleted: false)
verify(TodayNextStepAdvisor.recommend(plan: original, completion: lateWakeUnacknowledged, now: dinnerTime, calendar: fixedCalendar).kind == .training, "after a late wake and completed lunch/dinner, home must move to training rather than demand breakfast")
var lateWakeFoodData = PrivateCoachData(profile: profile)
let lateWakePlan = PlanSchedule.makePlan(for: programStart, calendar: fixedCalendar)!
let fixedLunchTime = fixedCalendar.date(bySettingHour: 12, minute: 0, second: 0, of: programStart)!
let fixedDinnerTime = fixedCalendar.date(bySettingHour: 19, minute: 0, second: 0, of: programStart)!
lateWakeFoodData = TodayFeature.completingMeal(.lunch, for: lateWakePlan, in: lateWakeFoodData, at: fixedLunchTime, calendar: fixedCalendar)
verify(lateWakeFoodData.dailyCompletions.first?.breakfastWaivedForLateWake == true && lateWakeFoodData.dailyCompletions.first?.breakfastCompleted == false, "logging lunch after 11:00 must truthfully acknowledge that breakfast need not be backfilled")
lateWakeFoodData = TodayFeature.completingMeal(.dinner, for: lateWakePlan, in: lateWakeFoodData, at: fixedDinnerTime, calendar: fixedCalendar)
verify(lateWakeFoodData.dailyCompletions.first?.foodCompleted == true && lateWakeFoodData.dailyCompletions.first?.completedMealCount == 2, "late-wake lunch plus dinner must finish today's food pillar while retaining two actual meals")
let lateWakeActions = TodayFeature.mealActions(plan: lateWakePlan, completion: lateWakeFoodData.dailyCompletions.first)
verify(lateWakeActions.first?.isWaived == true && lateWakeActions.first?.canRecordActualMeal == true && lateWakeActions.first?.title.contains("无需补") == true, "late-wake breakfast must be visibly optional rather than a hidden completed meal or a blocked actual-meal record")
lateWakeFoodData = TodayFeature.completingMeal(.breakfast, for: lateWakePlan, in: lateWakeFoodData, at: fixedDinnerTime, calendar: fixedCalendar)
verify(lateWakeFoodData.dailyCompletions.first?.breakfastCompleted == true && lateWakeFoodData.dailyCompletions.first?.breakfastWaivedForLateWake == false, "a person who voluntarily eats breakfast as a later meal must be able to replace the waiver with an actual meal record")
let fixedEarlyTime = fixedCalendar.date(bySettingHour: 8, minute: 0, second: 0, of: programStart)!
let beforeElevenData = TodayFeature.completingMeal(.lunch, for: lateWakePlan, in: PrivateCoachData(profile: profile), at: fixedEarlyTime, calendar: fixedCalendar)
verify(beforeElevenData.dailyCompletions.first?.breakfastWaivedForLateWake == false, "logging a meal before the late-wake boundary must not waive breakfast")
var recoveryPlan = original
recoveryPlan.trainingMode = .recovery
verify(TodayNextStepAdvisor.recommend(plan: recoveryPlan, completion: foodOnlyComplete, now: dinnerTime, calendar: fixedCalendar).kind == .recovery, "a protected plan must recommend recovery rather than standard training")
let skippedDay = DailyCompletion(date: original.date, foodCompleted: false, trainingOrRecoveryCompleted: false, bedtimePreparationCompleted: false, skippedAt: dinnerTime)
let skippedStep = TodayNextStepAdvisor.recommend(plan: original, completion: skippedDay, now: dinnerTime, calendar: fixedCalendar)
verify(skippedStep.kind == .skipped && skippedStep.detail.contains("不补练"), "an explicit skip must receive non-punitive next-step guidance")
let allDone = DailyCompletion(date: original.date, foodCompleted: true, trainingOrRecoveryCompleted: true, bedtimePreparationCompleted: true)
verify(TodayNextStepAdvisor.recommend(plan: original, completion: allDone, now: dinnerTime, calendar: fixedCalendar).kind == .dinner, "after training and sleep preparation, today home may still offer the next dinner preparation card without creating a completion debt")

let privatePhotoDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("youye-photo-rule-check-\(UUID().uuidString)")
let privatePhotoStore = try PrivateMealPhotoStore(directory: privatePhotoDirectory)
let localPhotoReference = try privatePhotoStore.save(data: Data([0x01, 0x02, 0x03]))
verify(localPhotoReference.hasPrefix("local-photo://"), "meal photo store must return a local-only reference")
let storedPhotoData = try privatePhotoStore.data(for: localPhotoReference)
verify(storedPhotoData == Data([0x01, 0x02, 0x03]), "meal photo store must keep selected photo data locally")
let legacyVoiceMigrationSuite = "youye-legacy-voice-migration-rule-check-\(UUID().uuidString)"
let legacyVoiceMigrationDefaults = UserDefaults(suiteName: legacyVoiceMigrationSuite)!
let legacyVoiceOwner = UUID()
let legacyVoiceOwnerKey = LocalDataDeletion.voiceCuePreferenceKey(for: legacyVoiceOwner)
legacyVoiceMigrationDefaults.set(false, forKey: "livePoseVoiceCuesEnabled")
LocalDataDeletion.migrateLegacyVoiceCuePreferenceIfNeeded(for: legacyVoiceOwner, defaults: legacyVoiceMigrationDefaults)
verify(legacyVoiceMigrationDefaults.object(forKey: legacyVoiceOwnerKey) as? Bool == false, "an existing loaded profile may migrate its own legacy live-voice preference once")
verify(legacyVoiceMigrationDefaults.object(forKey: "livePoseVoiceCuesEnabled") == nil, "legacy live-voice preference must be removed after owner-scoped migration")
legacyVoiceMigrationDefaults.set(true, forKey: legacyVoiceOwnerKey)
legacyVoiceMigrationDefaults.set(false, forKey: "livePoseVoiceCuesEnabled")
LocalDataDeletion.migrateLegacyVoiceCuePreferenceIfNeeded(for: legacyVoiceOwner, defaults: legacyVoiceMigrationDefaults)
verify(legacyVoiceMigrationDefaults.object(forKey: legacyVoiceOwnerKey) as? Bool == true, "a scoped live-voice preference must remain authoritative over any legacy residue")
verify(legacyVoiceMigrationDefaults.object(forKey: "livePoseVoiceCuesEnabled") == nil, "an existing scoped preference must discard legacy residue rather than leave a value for a later profile")
legacyVoiceMigrationDefaults.removePersistentDomain(forName: legacyVoiceMigrationSuite)
try privatePhotoStore.delete(localReference: localPhotoReference)
let deletedPhotoData = try privatePhotoStore.data(for: localPhotoReference)
verify(deletedPhotoData == nil, "meal photo must be deletable locally")
let retainedPhoto = try privatePhotoStore.save(data: Data([0x04]))
try privatePhotoStore.deleteAll(references: [retainedPhoto, nil, "not-a-local-photo-reference"])
let deletedBulkPhotoData = try privatePhotoStore.data(for: retainedPhoto)
verify(deletedBulkPhotoData == nil, "bulk privacy deletion must only remove local private photo references")
let allDeletionRoot = FileManager.default.temporaryDirectory.appendingPathComponent("youye-delete-rule-check-\(UUID().uuidString)")
let allDeletionPhotoStore = try PrivateMealPhotoStore(directory: allDeletionRoot.appendingPathComponent("photos", isDirectory: true))
let allDeletionReference = try allDeletionPhotoStore.save(data: Data([0x05]))
let unrelatedDeletionReference = try allDeletionPhotoStore.save(data: Data([0x07]))
let deletionDefaultsSuite = "youye-health-coach-deletion-rule-check-\(UUID().uuidString)"
let deletionDefaults = UserDefaults(suiteName: deletionDefaultsSuite)!
let deletedProfileVoicePreferenceKey = LocalDataDeletion.voiceCuePreferenceKey(for: profile.id)
let unrelatedProfileVoicePreferenceKey = LocalDataDeletion.voiceCuePreferenceKey(for: UUID())
deletionDefaults.set(false, forKey: "livePoseVoiceCuesEnabled")
deletionDefaults.set(false, forKey: deletedProfileVoicePreferenceKey)
deletionDefaults.set(true, forKey: unrelatedProfileVoicePreferenceKey)
var allDeletionDataRemoved = false
try LocalDataDeletion.deleteAll(
    data: PrivateCoachData(profile: profile, unplannedMealLogs: [UnplannedMealEstimator.conservativeEstimate(description: "删除测试", localPhotoReference: allDeletionReference)]),
    photoStore: allDeletionPhotoStore,
    defaults: deletionDefaults,
    deleteData: { _ in allDeletionDataRemoved = true }
)
verify(allDeletionDataRemoved, "full local deletion must remove the private data record after photos")
let deletedAllPhotoData = try allDeletionPhotoStore.data(for: allDeletionReference)
verify(deletedAllPhotoData == nil, "full local deletion must remove photos referenced by the deleted private record")
let retainedUnrelatedPhotoData = try allDeletionPhotoStore.data(for: unrelatedDeletionReference)
verify(retainedUnrelatedPhotoData == Data([0x07]), "deleting one private profile must not remove unrelated private photos from another independent profile")
verify(deletionDefaults.object(forKey: "livePoseVoiceCuesEnabled") == nil, "full local deletion must clear the prior owner's legacy local live-voice preference")
verify(deletionDefaults.object(forKey: deletedProfileVoicePreferenceKey) == nil, "full local deletion must clear only the deleted owner's scoped live-voice preference")
verify(deletionDefaults.object(forKey: unrelatedProfileVoicePreferenceKey) as? Bool == true, "full local deletion must preserve another profile's scoped live-voice preference")
deletionDefaults.removePersistentDomain(forName: deletionDefaultsSuite)
let ownerScopedRoot = FileManager.default.temporaryDirectory.appendingPathComponent("youye-owner-photo-rule-check-\(UUID().uuidString)")
let photoOwnerA = UUID()
let photoOwnerB = UUID()
let ownerAPhotoStore = try PrivateMealPhotoStore(ownerID: photoOwnerA, baseDirectory: ownerScopedRoot)
let ownerBPhotoStore = try PrivateMealPhotoStore(ownerID: photoOwnerB, baseDirectory: ownerScopedRoot)
let ownerAReference = try ownerAPhotoStore.save(data: Data([0x0A]))
let ownerBReference = try ownerBPhotoStore.save(data: Data([0x0B]))
let ownerAOrphanedReference = try ownerAPhotoStore.save(data: Data([0x0D]))
verify(ownerAReference.contains(photoOwnerA.uuidString) && ownerBReference.contains(photoOwnerB.uuidString), "new private meal photo references must bind the photo to its owner")
let crossOwnerRead = try ownerAPhotoStore.data(for: ownerBReference)
verify(crossOwnerRead == nil, "one owner must never read another owner's private meal photo")
try ownerAPhotoStore.delete(localReference: ownerBReference)
let ownerBPhotoAfterCrossOwnerDelete = try ownerBPhotoStore.data(for: ownerBReference)
verify(ownerBPhotoAfterCrossOwnerDelete == Data([0x0B]), "one owner must never delete another owner's private meal photo")
let ownerAData = PrivateCoachData(profile: UserProfile(id: photoOwnerA, displayName: "A"), unplannedMealLogs: [UnplannedMealEstimator.conservativeEstimate(description: "owner A 删除", localPhotoReference: ownerAReference)])
do {
    try LocalDataDeletion.deleteAll(data: ownerAData, photoStore: ownerBPhotoStore, deleteData: { _ in
        verify(false, "an owner-mismatched photo store must be rejected before any profile deletion starts")
    })
    verify(false, "an owner-mismatched photo store must not be accepted for full profile deletion")
} catch let error as PrivateMealPhotoStore.StoreError {
    verify(error == .ownerMismatch, "an owner-mismatched photo store must fail with an explicit owner-mismatch error")
} catch {
    verify(false, "an owner-mismatched photo store must not fail with an unrelated deletion error")
}
let ownerAPhotoAfterRejectedMismatch = try ownerAPhotoStore.data(for: ownerAReference)
let ownerBPhotoAfterRejectedMismatch = try ownerBPhotoStore.data(for: ownerBReference)
verify(
    ownerAPhotoAfterRejectedMismatch == Data([0x0A]) && ownerBPhotoAfterRejectedMismatch == Data([0x0B]),
    "rejecting a mismatched owner photo store must leave both owners' private photos untouched"
)
try LocalDataDeletion.deleteAll(data: ownerAData, photoStore: ownerAPhotoStore, deleteData: { _ in })
let ownerAPhotoAfterDeletion = try ownerAPhotoStore.data(for: ownerAReference)
let ownerAOrphanedPhotoAfterDeletion = try ownerAPhotoStore.data(for: ownerAOrphanedReference)
let ownerBPhotoAfterOwnerADeletion = try ownerBPhotoStore.data(for: ownerBReference)
verify(ownerAPhotoAfterDeletion == nil, "deleting one owner's data must remove only that owner's referenced private photo")
verify(ownerAOrphanedPhotoAfterDeletion == nil, "deleting an owner profile must also remove its own unreferenced private photo remnants")
verify(ownerBPhotoAfterOwnerADeletion == Data([0x0B]), "deleting one owner's data must preserve another owner's private photo")
let orphanCleanupRoot = FileManager.default.temporaryDirectory.appendingPathComponent("youye-orphan-photo-cleanup-rule-check-\(UUID().uuidString)")
let orphanCleanupOwner = UUID()
let otherOrphanCleanupOwner = UUID()
let orphanCleanupStore = try PrivateMealPhotoStore(ownerID: orphanCleanupOwner, baseDirectory: orphanCleanupRoot)
let otherOrphanCleanupStore = try PrivateMealPhotoStore(ownerID: otherOrphanCleanupOwner, baseDirectory: orphanCleanupRoot)
let retainedOwnerPhoto = try orphanCleanupStore.save(data: Data([0x21]))
let unreachableOwnerPhoto = try orphanCleanupStore.save(data: Data([0x22]))
let otherOwnerPhoto = try otherOrphanCleanupStore.save(data: Data([0x23]))
try orphanCleanupStore.purgeUnreferencedPhotos(references: [retainedOwnerPhoto])
let retainedOwnerPhotoData = try orphanCleanupStore.data(for: retainedOwnerPhoto)
let unreachableOwnerPhotoData = try orphanCleanupStore.data(for: unreachableOwnerPhoto)
let otherOwnerPhotoData = try otherOrphanCleanupStore.data(for: otherOwnerPhoto)
verify(retainedOwnerPhotoData == Data([0x21]), "orphan cleanup must retain a photo still referenced by the loaded owner record")
verify(unreachableOwnerPhotoData == nil, "orphan cleanup must remove only an unreferenced owner-private photo left by a failed transaction")
verify(otherOwnerPhotoData == Data([0x23]), "one owner's orphan cleanup must never inspect or delete another owner's private photo")
let interruptedOwnerStageRoot = FileManager.default.temporaryDirectory.appendingPathComponent("youye-owner-delete-resume-rule-check-\(UUID().uuidString)")
let interruptedOwnerID = UUID()
let otherInterruptedOwnerID = UUID()
let interruptedOwnerStore = try PrivateMealPhotoStore(ownerID: interruptedOwnerID, baseDirectory: interruptedOwnerStageRoot)
let otherInterruptedOwnerStore = try PrivateMealPhotoStore(ownerID: otherInterruptedOwnerID, baseDirectory: interruptedOwnerStageRoot)
let interruptedOwnerReference = try interruptedOwnerStore.save(data: Data([0x0E]))
let otherInterruptedOwnerReference = try otherInterruptedOwnerStore.save(data: Data([0x0F]))
_ = try interruptedOwnerStore.stageAllPrivatePhotosForDeletion()
let interruptedPhotoWhileStaged = try interruptedOwnerStore.data(for: interruptedOwnerReference)
verify(interruptedPhotoWhileStaged == nil, "an interrupted full-profile deletion must leave the deleted owner's staged photo unreadable")
try PrivateMealPhotoStore.purgePendingOwnerScopedDeletions(for: interruptedOwnerID, baseDirectory: interruptedOwnerStageRoot)
let interruptedPhotoAfterResumeCleanup = try interruptedOwnerStore.data(for: interruptedOwnerReference)
let otherInterruptedOwnerPhotoAfterCleanup = try otherInterruptedOwnerStore.data(for: otherInterruptedOwnerReference)
verify(interruptedPhotoAfterResumeCleanup == nil, "launch-resume cleanup must remove the exact deleted owner's staged directory")
verify(otherInterruptedOwnerPhotoAfterCleanup == Data([0x0F]), "launch-resume cleanup must preserve another owner's private directory")
let interruptedDeletionRecoveryRoot = FileManager.default.temporaryDirectory.appendingPathComponent("youye-owner-delete-record-state-rule-check-\(UUID().uuidString)")
let presentInterruptedOwnerID = UUID()
let absentInterruptedOwnerID = UUID()
let unreadableInterruptedOwnerID = UUID()
let presentInterruptedStore = try PrivateMealPhotoStore(ownerID: presentInterruptedOwnerID, baseDirectory: interruptedDeletionRecoveryRoot)
let absentInterruptedStore = try PrivateMealPhotoStore(ownerID: absentInterruptedOwnerID, baseDirectory: interruptedDeletionRecoveryRoot)
let unreadableInterruptedStore = try PrivateMealPhotoStore(ownerID: unreadableInterruptedOwnerID, baseDirectory: interruptedDeletionRecoveryRoot)
let presentInterruptedReference = try presentInterruptedStore.save(data: Data([0x10]))
let absentInterruptedReference = try absentInterruptedStore.save(data: Data([0x11]))
let unreadableInterruptedReference = try unreadableInterruptedStore.save(data: Data([0x12]))
_ = try presentInterruptedStore.stageAllPrivatePhotosForDeletion()
_ = try absentInterruptedStore.stageAllPrivatePhotosForDeletion()
_ = try unreadableInterruptedStore.stageAllPrivatePhotosForDeletion()
let interruptedRecoveryDefaultsSuite = "youye-owner-delete-record-state-defaults-\(UUID().uuidString)"
let interruptedRecoveryDefaults = UserDefaults(suiteName: interruptedRecoveryDefaultsSuite)!
let unrelatedRecoveryOwnerID = UUID()
let presentRecoveryVoicePreferenceKey = LocalDataDeletion.voiceCuePreferenceKey(for: presentInterruptedOwnerID)
let absentRecoveryVoicePreferenceKey = LocalDataDeletion.voiceCuePreferenceKey(for: absentInterruptedOwnerID)
let unreadableRecoveryVoicePreferenceKey = LocalDataDeletion.voiceCuePreferenceKey(for: unreadableInterruptedOwnerID)
let unrelatedRecoveryVoicePreferenceKey = LocalDataDeletion.voiceCuePreferenceKey(for: unrelatedRecoveryOwnerID)
interruptedRecoveryDefaults.set(
    [presentInterruptedOwnerID.uuidString, absentInterruptedOwnerID.uuidString, unreadableInterruptedOwnerID.uuidString],
    forKey: LocalDataDeletion.pendingOwnerPhotoDeletionIDsDefaultsKey
)
interruptedRecoveryDefaults.set(false, forKey: "livePoseVoiceCuesEnabled")
interruptedRecoveryDefaults.set(false, forKey: presentRecoveryVoicePreferenceKey)
interruptedRecoveryDefaults.set(false, forKey: absentRecoveryVoicePreferenceKey)
interruptedRecoveryDefaults.set(false, forKey: unreadableRecoveryVoicePreferenceKey)
interruptedRecoveryDefaults.set(true, forKey: unrelatedRecoveryVoicePreferenceKey)
LocalDataDeletion.recoverPendingOwnerPhotoDeletions(
    defaults: interruptedRecoveryDefaults,
    photoBaseDirectory: interruptedDeletionRecoveryRoot,
    recordState: { ownerID in
        if ownerID == presentInterruptedOwnerID { return .present }
        if ownerID == absentInterruptedOwnerID { return .absent }
        return .unreadable
    }
)
let restoredPresentInterruptedPhoto = try presentInterruptedStore.data(for: presentInterruptedReference)
let disposedAbsentInterruptedPhoto = try absentInterruptedStore.data(for: absentInterruptedReference)
let untouchedUnreadableInterruptedPhoto = try unreadableInterruptedStore.data(for: unreadableInterruptedReference)
verify(restoredPresentInterruptedPhoto == Data([0x10]), "if an interrupted deletion still has its owner record, launch recovery must restore that owner's staged photos")
verify(disposedAbsentInterruptedPhoto == nil, "if an interrupted deletion has no owner record, launch recovery must dispose only that owner's staged photos")
verify(untouchedUnreadableInterruptedPhoto == nil, "an unreadable owner record must leave its staged photos untouched rather than risk destructive recovery")
let remainingInterruptedRecoveryIDs = interruptedRecoveryDefaults.stringArray(forKey: LocalDataDeletion.pendingOwnerPhotoDeletionIDsDefaultsKey) ?? []
verify(remainingInterruptedRecoveryIDs == [unreadableInterruptedOwnerID.uuidString], "only an unreadable owner's deletion marker may remain for a later safe retry")
verify(interruptedRecoveryDefaults.object(forKey: "livePoseVoiceCuesEnabled") == nil, "post-delete launch recovery must clear a deleted owner's legacy live-voice preference")
verify(interruptedRecoveryDefaults.object(forKey: presentRecoveryVoicePreferenceKey) as? Bool == false, "recovery must retain a present owner's scoped live-voice preference")
verify(interruptedRecoveryDefaults.object(forKey: absentRecoveryVoicePreferenceKey) == nil, "recovery must clear only an absent deleted owner's scoped live-voice preference")
verify(interruptedRecoveryDefaults.object(forKey: unreadableRecoveryVoicePreferenceKey) as? Bool == false, "recovery must retain an unreadable owner's scoped live-voice preference until a safe retry")
verify(interruptedRecoveryDefaults.object(forKey: unrelatedRecoveryVoicePreferenceKey) as? Bool == true, "a pending cleanup for one owner must never clear a new or unrelated owner's scoped live-voice preference")
interruptedRecoveryDefaults.removePersistentDomain(forName: interruptedRecoveryDefaultsSuite)
let legacyMigrationRoot = FileManager.default.temporaryDirectory.appendingPathComponent("youye-legacy-photo-rule-check-\(UUID().uuidString)")
let legacyMigrationStore = try PrivateMealPhotoStore(directory: legacyMigrationRoot)
let legacyMigrationReference = try legacyMigrationStore.save(data: Data([0x0C]))
let legacyMigrationOwner = UUID()
let upgradedOwnerStore = try PrivateMealPhotoStore(ownerID: legacyMigrationOwner, baseDirectory: legacyMigrationRoot)
let blockedLegacyPhoto = try upgradedOwnerStore.data(for: legacyMigrationReference)
verify(blockedLegacyPhoto == nil, "owner photo reads must never fall back to the shared legacy directory")
let legacyPhotoProfile = UserProfile(id: legacyMigrationOwner, displayName: "迁移资料")
let legacyMigrationData = PrivateCoachData(profile: legacyPhotoProfile, unplannedMealLogs: [UnplannedMealLog(localPhotoReference: legacyMigrationReference, userDescription: "旧照片")])
let wrongMigrationOwnerStore = try PrivateMealPhotoStore(ownerID: UUID(), baseDirectory: legacyMigrationRoot)
do {
    _ = try PrivateMealPhotoMigration.prepare(data: legacyMigrationData, ownerPhotoStore: wrongMigrationOwnerStore)
    verify(false, "legacy photo migration must reject a photo store owned by another profile")
} catch let error as PrivateMealPhotoStore.StoreError {
    verify(error == .ownerMismatch, "legacy photo migration must surface an explicit owner mismatch")
} catch {
    verify(false, "legacy photo migration owner mismatch must not clear references or fail ambiguously")
}
let legacyPhotoAfterRejectedMigrationStore = try legacyMigrationStore.data(for: legacyMigrationReference)
verify(
    legacyPhotoAfterRejectedMigrationStore == Data([0x0C]),
    "rejecting a wrong-owner migration store must preserve the legacy source photo"
)
let preparedLegacyMigration = try PrivateMealPhotoMigration.prepare(data: legacyMigrationData, ownerPhotoStore: upgradedOwnerStore)
verify(preparedLegacyMigration.changed, "loading an old photo reference must prepare an owner-scoped migration")
let migratedLegacyReference = preparedLegacyMigration.data.unplannedMealLogs.first?.localPhotoReference
verify(migratedLegacyReference?.contains(legacyMigrationOwner.uuidString) == true, "legacy records must be rewritten with an owner-bound photo reference")
let importedLegacyPhoto = try migratedLegacyReference.flatMap { try upgradedOwnerStore.data(for: $0) }
verify(importedLegacyPhoto == Data([0x0C]), "migration must copy the old photo into the owning profile directory before cleanup")
PrivateMealPhotoMigration.rollbackPreparedImport(preparedLegacyMigration, ownerPhotoStore: upgradedOwnerStore)
let rolledBackMigratedPhoto = try migratedLegacyReference.flatMap { try upgradedOwnerStore.data(for: $0) }
let retainedLegacyPhotoAfterRollback = try legacyMigrationStore.data(for: legacyMigrationReference)
verify(rolledBackMigratedPhoto == nil && retainedLegacyPhotoAfterRollback == Data([0x0C]), "a failed migrated-record save must remove only the copied owner photo and preserve the original legacy photo")
let preparedLegacyMigrationAfterRollback = try PrivateMealPhotoMigration.prepare(data: legacyMigrationData, ownerPhotoStore: upgradedOwnerStore)
let migratedLegacyReferenceAfterRollback = preparedLegacyMigrationAfterRollback.data.unplannedMealLogs.first?.localPhotoReference
verify(migratedLegacyReferenceAfterRollback?.contains(legacyMigrationOwner.uuidString) == true, "a rolled-back migration must be safely retryable from the unchanged legacy record")
PrivateMealPhotoMigration.commitLegacyCleanup(preparedLegacyMigrationAfterRollback, ownerPhotoStore: upgradedOwnerStore)
let deletedLegacySourcePhoto = try legacyMigrationStore.data(for: legacyMigrationReference)
verify(deletedLegacySourcePhoto == nil, "legacy source photo must be removed only after the migrated data is ready to persist")
let missingLegacyReference = "local-photo://\(UUID().uuidString)"
let missingLegacyData = PrivateCoachData(profile: legacyPhotoProfile, unplannedMealLogs: [UnplannedMealLog(localPhotoReference: missingLegacyReference, userDescription: "已缺失的旧照片")])
let missingLegacyMigration = try PrivateMealPhotoMigration.prepare(data: missingLegacyData, ownerPhotoStore: upgradedOwnerStore)
verify(missingLegacyMigration.data.unplannedMealLogs.first?.localPhotoReference == nil, "a missing old photo must lose its dangling legacy reference instead of retaining a shared-directory route")
let orphanedStageRoot = FileManager.default.temporaryDirectory.appendingPathComponent("youye-delete-orphan-rule-check-\(UUID().uuidString)")
let orphanedStagePhotoStore = try PrivateMealPhotoStore(directory: orphanedStageRoot.appendingPathComponent("photos", isDirectory: true))
let orphanedStageReference = try orphanedStagePhotoStore.save(data: Data([0x08]))
_ = try orphanedStagePhotoStore.stageReferencedPhotosForDeletion(references: [orphanedStageReference])
let photoWhileStaged = try orphanedStagePhotoStore.data(for: orphanedStageReference)
verify(photoWhileStaged == nil, "staged private photos must leave the live directory before owner data deletion")
try orphanedStagePhotoStore.purgePendingStagedDeletions()
let photoAfterStagedPurge = try orphanedStagePhotoStore.data(for: orphanedStageReference)
verify(photoAfterStagedPurge == nil, "orphaned post-delete staging folders must be purged rather than restoring private photos")
let unrelatedStagingDirectory = orphanedStageRoot.appendingPathComponent(".PrivateMealPhotos-deleting-other-owner-\(UUID().uuidString)", isDirectory: true)
try FileManager.default.createDirectory(at: unrelatedStagingDirectory, withIntermediateDirectories: true)
let unrelatedStagingMarker = unrelatedStagingDirectory.appendingPathComponent("must-not-delete", isDirectory: false)
try Data([0x09]).write(to: unrelatedStagingMarker)
try orphanedStagePhotoStore.purgePendingStagedDeletions()
verify(FileManager.default.fileExists(atPath: unrelatedStagingMarker.path), "one owner's staged-photo cleanup must not delete a similarly named foreign staging directory")
let failedDeletionRoot = FileManager.default.temporaryDirectory.appendingPathComponent("youye-delete-fail-rule-check-\(UUID().uuidString)")
let failedDeletionPhotoStore = try PrivateMealPhotoStore(directory: failedDeletionRoot.appendingPathComponent("photos", isDirectory: true))
let failedDeletionReference = try failedDeletionPhotoStore.save(data: Data([0x06]))
let failedDeletionSuite = "youye-health-coach-failed-deletion-rule-check-\(UUID().uuidString)"
let failedDeletionDefaults = UserDefaults(suiteName: failedDeletionSuite)!
let failedDeletionVoicePreferenceKey = LocalDataDeletion.voiceCuePreferenceKey(for: profile.id)
failedDeletionDefaults.set(false, forKey: "livePoseVoiceCuesEnabled")
failedDeletionDefaults.set(false, forKey: failedDeletionVoicePreferenceKey)
var deletionReachedDataStore = false
do {
    try LocalDataDeletion.deleteAll(
        data: PrivateCoachData(profile: profile),
        photoStore: failedDeletionPhotoStore,
        defaults: failedDeletionDefaults,
        deleteData: { _ in deletionReachedDataStore = true; throw NSError(domain: "RuleCheck", code: 1) }
    )
    verify(false, "full local deletion must surface a private data deletion failure")
} catch {}
verify(deletionReachedDataStore, "full local deletion must attempt data deletion after private photos")
let restoredFailedPhotoData = try failedDeletionPhotoStore.data(for: failedDeletionReference)
verify(restoredFailedPhotoData == Data([0x06]), "failed full deletion must restore private photos when the data record remains")
verify(failedDeletionDefaults.object(forKey: "livePoseVoiceCuesEnabled") as? Bool == false, "failed owner data deletion must retain the existing local live-voice preference")
verify(failedDeletionDefaults.object(forKey: failedDeletionVoicePreferenceKey) as? Bool == false, "failed owner data deletion must retain the matching owner's scoped live-voice preference")
failedDeletionDefaults.removePersistentDomain(forName: failedDeletionSuite)
let exportWithPhotoData = PrivateCoachData(
    profile: profile,
    unplannedMealLogs: [UnplannedMealEstimator.conservativeEstimate(description: "带照片的计划外餐食", localPhotoReference: "local-photo://00000000-0000-0000-0000-000000000001")]
)
let portableCopy = PrivateExport.portableCopy(of: exportWithPhotoData)
verify(portableCopy.unplannedMealLogs.first?.localPhotoReference == nil, "portable export copy must remove local photo references")
verify(exportWithPhotoData.unplannedMealLogs.first?.localPhotoReference != nil, "portable export copy must not mutate the on-device private log")
let portableExportText = String(decoding: try PrivateExport.makeOwnerExport(exportWithPhotoData), as: UTF8.self)
verify(!portableExportText.contains("local-photo://"), "owner export must not contain local photo references")

var ingredientCalendar = Calendar(identifier: .gregorian)
ingredientCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
let ingredientDate = ingredientCalendar.date(from: DateComponents(year: 2026, month: 8, day: 10))!
let ingredientPlan = DayOnePlan.make(date: ingredientDate)
let ingredientPhotoReference = "local-photo://00000000-0000-0000-0000-000000000002"
let replacementMeal = MealCard(
    title: "确认替换测试餐",
    ingredients: ["北豆腐 250g", "西兰花 300g", "熟米饭 180g"],
    thawAndPortion: "豆腐冷藏沥水；西兰花洗切；做 1 份。",
    timedSteps: ["0:00 电饭锅加热米饭。", "1:00 锅中放豆腐和水 40ml。", "5:00 放西兰花，盖盖 4 分钟。", "9:00 调味后装盘。"],
    portionsAndStorage: "做 1 份，不做饭盒；剩余食材 2 小时内冷藏。总操作 12 分钟；下次加热至热透。",
    substitutions: "西兰花可换花菜 300g。"
)
let ingredientPhotoSubstitution = MealSubstitutionService.confirm(
    replacement: replacementMeal,
    for: ingredientPlan,
    availableFoodSummary: "北豆腐 250g、西兰花 300g、熟米饭 180g",
    localIngredientPhotoReference: ingredientPhotoReference,
    confirmedByUser: true,
    at: ingredientDate,
    in: PrivateCoachData(profile: profile),
    calendar: ingredientCalendar
)
verify(ingredientPhotoSubstitution.substitution?.localIngredientPhotoReference == ingredientPhotoReference, "confirmed ingredient replacement may retain only a local private photo reference")
let ingredientPhotoExport = PrivateExport.portableCopy(of: ingredientPhotoSubstitution.data)
verify(ingredientPhotoExport.mealSubstitutions.first?.localIngredientPhotoReference == nil, "export must remove ingredient photo references as well as meal photo references")
let revertedIngredientPhoto = MealSubstitutionService.revokeLatest(
    for: ingredientPhotoSubstitution.plan,
    slot: .dinner,
    at: ingredientDate,
    in: ingredientPhotoSubstitution.data,
    calendar: ingredientCalendar
)
verify(revertedIngredientPhoto.wasReverted && revertedIngredientPhoto.photoReferenceToDelete == ingredientPhotoReference, "reverting today’s ingredient substitution must expose only its local photo reference for private deletion")
verify(revertedIngredientPhoto.revertedSubstitutionID == ingredientPhotoSubstitution.substitution?.id, "ingredient reversal must identify exactly which private reference may be cleared after its file deletion succeeds")
verify(MealSubstitutionService.activeSubstitution(for: ingredientDate, in: revertedIngredientPhoto.data, calendar: ingredientCalendar) == nil, "reverted ingredient substitution must no longer override the scheduled meal")
verify(revertedIngredientPhoto.data.mealSubstitutions.first?.isReverted == true && revertedIngredientPhoto.data.mealSubstitutions.first?.localIngredientPhotoReference == ingredientPhotoReference, "reverted records retain their private photo reference until file deletion can succeed")
verify(revertedIngredientPhoto.data.planChanges.contains { $0.reason.contains("撤回") }, "reverting a substitution must retain a private audit entry")
let sharedIngredientPhotoData = PrivateCoachData(
    profile: profile,
    unplannedMealLogs: [UnplannedMealLog(date: ingredientDate, localPhotoReference: ingredientPhotoReference, userDescription: "仍在使用同一私有引用")],
    mealSubstitutions: ingredientPhotoSubstitution.data.mealSubstitutions
)
let sharedIngredientPhotoReversal = MealSubstitutionService.revokeLatest(
    for: ingredientPhotoSubstitution.plan,
    slot: .dinner,
    at: ingredientDate,
    in: sharedIngredientPhotoData,
    calendar: ingredientCalendar
)
verify(sharedIngredientPhotoReversal.wasReverted && sharedIngredientPhotoReversal.photoReferenceToDelete == nil, "reverting a substitution must retain a photo still referenced by another private record")
let actualMealSharedIngredientPhotoData = PrivateCoachData(
    profile: profile,
    actualMealLogs: [ActualMealLog(date: ingredientDate, slot: .lunch, relationship: .different, description: "实际午餐复用食材照片", localPhotoReference: ingredientPhotoReference, estimatedCaloriesRange: 400...700)],
    mealSubstitutions: ingredientPhotoSubstitution.data.mealSubstitutions
)
let actualMealSharedIngredientPhotoReversal = MealSubstitutionService.revokeLatest(
    for: ingredientPhotoSubstitution.plan,
    slot: .dinner,
    at: ingredientDate,
    in: actualMealSharedIngredientPhotoData,
    calendar: ingredientCalendar
)
verify(actualMealSharedIngredientPhotoReversal.wasReverted && actualMealSharedIngredientPhotoReversal.photoReferenceToDelete == nil, "reverting a substitution must not delete a private image still referenced by an actual meal record")
let rejectedFutureReversal = MealSubstitutionService.revokeLatest(
    for: PlanSchedule.makePlan(for: ingredientCalendar.date(byAdding: .day, value: 1, to: ingredientDate)!, calendar: ingredientCalendar)!,
    slot: .dinner,
    at: ingredientDate,
    in: ingredientPhotoSubstitution.data,
    calendar: ingredientCalendar
)
verify(!rejectedFutureReversal.wasReverted && !rejectedFutureReversal.validationErrors.isEmpty, "future meal substitutions must remain read-only and cannot be revoked early")
let invalidIngredientPhotoSubstitution = MealSubstitutionService.confirm(
    replacement: replacementMeal,
    for: ingredientPlan,
    localIngredientPhotoReference: "https://example.com/ingredient.jpg",
    confirmedByUser: true,
    at: ingredientDate,
    in: PrivateCoachData(profile: profile),
    calendar: ingredientCalendar
)
verify(invalidIngredientPhotoSubstitution.substitution?.localIngredientPhotoReference == nil, "ingredient substitutions must reject external photo references")

let actionStart = TodayFeature.actions(plan: original, completion: nil)
verify(actionStart.count == 3, "today screen must contain only three primary actions")
verify(actionStart.allSatisfy { !$0.isCompleted }, "today actions start uncompleted")
verify(actionStart.first(where: { $0.id == .eat })?.detail.contains("三餐 0/3") == true, "today food action must summarize the three separately executable meals")
verify(TodayFeature.actions(plan: original, completion: lateWakeLunchDinnerComplete).first(where: { $0.id == .eat })?.detail.contains("已完成 2 餐｜早餐无需补") == true, "today food action must not display a waived breakfast as an eaten third meal")
let mealActionStart = TodayFeature.mealActions(plan: original, completion: nil)
verify(mealActionStart.map(\.id) == [.breakfast, .lunch, .dinner] && mealActionStart.allSatisfy { !$0.isCompleted }, "today must expose breakfast, lunch, and dinner as separate initially-unchecked actions")
let breakfastDone = TodayFeature.completion(for: original.date, existing: nil, completingMeal: .breakfast)
verify(breakfastDone.breakfastCompleted && !breakfastDone.lunchCompleted && !breakfastDone.dinnerCompleted && !breakfastDone.foodCompleted && breakfastDone.completedMealCount == 1, "checking breakfast must not falsely complete lunch, dinner, or the day food pillar")
let lunchDone = TodayFeature.completion(for: original.date, existing: breakfastDone, completingMeal: .lunch)
let allMealsDone = TodayFeature.completion(for: original.date, existing: lunchDone, completingMeal: .dinner)
verify(allMealsDone.foodCompleted && allMealsDone.completedMealCount == 3, "only all three meals may complete the daily food pillar")
let foodDone = TodayFeature.completion(for: original.date, existing: nil, completing: .eat)
verify(foodDone.foodCompleted && foodDone.completedMealCount == 3 && !foodDone.trainingOrRecoveryCompleted, "legacy whole-food completion must migrate to all three completed meals")
let idempotentPlan = DayOnePlan.make(date: programStart)
let idempotentMoveCompletion = TodayFeature.markingCompleted(.move, for: idempotentPlan, in: PrivateCoachData(profile: profile), at: programStart, calendar: fixedCalendar)
let repeatedIdempotentMoveCompletion = TodayFeature.markingCompleted(.move, for: idempotentPlan, in: idempotentMoveCompletion, at: programStart, calendar: fixedCalendar)
verify(repeatedIdempotentMoveCompletion.dailyCompletions.first?.trainingOrRecoveryCompleted == true, "idempotent completion acknowledgement must never turn a completed movement action off")
let legacyCompletion = DailyCompletion(date: original.date, foodCompleted: true, trainingOrRecoveryCompleted: false, bedtimePreparationCompleted: false)
let legacyCompletionData = try JSONEncoder().encode(legacyCompletion)
var legacyCompletionObject = try JSONSerialization.jsonObject(with: legacyCompletionData) as! [String: Any]
legacyCompletionObject.removeValue(forKey: "breakfastCompleted")
legacyCompletionObject.removeValue(forKey: "lunchCompleted")
legacyCompletionObject.removeValue(forKey: "dinnerCompleted")
legacyCompletionObject.removeValue(forKey: "skippedAt")
let migratedLegacyCompletion = try JSONDecoder().decode(DailyCompletion.self, from: JSONSerialization.data(withJSONObject: legacyCompletionObject))
verify(!migratedLegacyCompletion.isSkipped && migratedLegacyCompletion.foodCompleted && migratedLegacyCompletion.completedMealCount == 3, "older whole-food completion history must remain unskipped and migrate to three completed meals")

var calendarForStatus = Calendar(identifier: .gregorian)
calendarForStatus.timeZone = TimeZone(secondsFromGMT: 0)!
let statusPastDate = calendarForStatus.date(from: DateComponents(year: 2026, month: 8, day: 10))!
let statusTodayDate = calendarForStatus.date(from: DateComponents(year: 2026, month: 8, day: 11))!
let statusFutureDate = calendarForStatus.date(from: DateComponents(year: 2026, month: 8, day: 12))!
let partialStatusData = PrivateCoachData(profile: profile, dailyCompletions: [DailyCompletion(date: statusPastDate, foodCompleted: true, trainingOrRecoveryCompleted: false, bedtimePreparationCompleted: false)])
verify(CalendarDayStatus.resolve(for: statusPastDate, data: partialStatusData, asOf: statusTodayDate, calendar: calendarForStatus) == .partiallyCompleted, "calendar must retain a partial completion state for an earlier day")
let duplicatedSameDayCompletionData = PrivateCoachData(
    profile: profile,
    dailyCompletions: [
        DailyCompletion(date: statusPastDate, foodCompleted: true, trainingOrRecoveryCompleted: false, bedtimePreparationCompleted: false),
        DailyCompletion(date: statusPastDate.addingTimeInterval(60 * 60), foodCompleted: false, trainingOrRecoveryCompleted: true, bedtimePreparationCompleted: false)
    ]
)
verify(
    duplicatedSameDayCompletionData.dailyCompletions.count == 1
        && duplicatedSameDayCompletionData.dailyCompletion(for: statusPastDate, calendar: calendarForStatus)?.completedCount == 2
        && CalendarDayStatus.resolve(for: statusPastDate, data: duplicatedSameDayCompletionData, asOf: statusTodayDate, calendar: calendarForStatus) == .partiallyCompleted,
    "duplicate restored same-day completion snapshots must merge all recorded actions into one deterministic calendar result"
)
verify(CalendarDayStatus.resolve(for: statusTodayDate, data: PrivateCoachData(profile: profile), asOf: statusTodayDate, calendar: calendarForStatus) == .today, "calendar must identify the current day before treating it as unrecorded or upcoming")
verify(CalendarDayStatus.resolve(for: statusFutureDate, data: PrivateCoachData(profile: profile), asOf: statusTodayDate, calendar: calendarForStatus) == .upcoming, "calendar must distinguish future planned days from unrecorded past days")
verify(CalendarDayStatus.resolve(for: statusPastDate, data: PrivateCoachData(profile: profile), asOf: statusTodayDate, calendar: calendarForStatus) == .unrecorded, "calendar must distinguish an earlier day without a saved record from an explicit skip or failure")
let skippedCalendarData = PrivateCoachData(profile: profile, dailyCompletions: [DailyCompletion(date: statusPastDate, foodCompleted: false, trainingOrRecoveryCompleted: false, bedtimePreparationCompleted: false, skippedAt: statusPastDate)])
verify(CalendarDayStatus.resolve(for: statusPastDate, data: skippedCalendarData, asOf: statusTodayDate, calendar: calendarForStatus) == .skipped, "calendar must distinguish an explicit skip from an earlier uncompleted plan day")
let recoveredCalendarData = PrivateCoachData(profile: profile, dailyCompletions: [DailyCompletion(date: statusPastDate, foodCompleted: true, trainingOrRecoveryCompleted: true, bedtimePreparationCompleted: true)], planChanges: [PlanChange(kind: .recoveryDowngrade, authority: .automatic, reason: "疼痛", before: "标准", after: "恢复", createdAt: statusPastDate)])
verify(CalendarDayStatus.resolve(for: statusPastDate, data: recoveredCalendarData, asOf: statusTodayDate, calendar: calendarForStatus) == .recovery, "calendar recovery state must take priority over the ordinary completion color")
let malformedManualRecoveryCalendarData = PrivateCoachData(
    profile: profile,
    planChanges: [PlanChange(kind: .recoveryDowngrade, authority: .requiresConfirmation, reason: "损坏导入记录", before: "标准", after: "恢复", createdAt: statusPastDate)]
)
verify(
    CalendarDayStatus.resolve(for: statusPastDate, data: malformedManualRecoveryCalendarData, asOf: statusTodayDate, calendar: calendarForStatus) == .unrecorded,
    "a malformed or imported non-automatic recovery change must not make a calendar day look protectively executed"
)

verify(dayOneScheduled?.dinner == WeekOneRecipeCatalog.cards[0], "2026-08-10 must resolve to recipe day one")
verify(dayOneScheduled?.breakfast == BreakfastCatalog.card(dayIndex: 1) && dayOneScheduled?.lunch == LunchCatalog.card(dayIndex: 1), "each scheduled day must expose breakfast and lunch alongside dinner for the daily card")
verify(dayOneScheduled?.trainingInstruction.contains(WeekOneTrainingCatalog.cards[0].minimumVersion) == true, "2026-08-10 must resolve to training day one")
verify(PlanSchedule.hasNotStarted(on: fixedCalendar.date(byAdding: .day, value: -1, to: programStart)!, calendar: fixedCalendar), "the evening before the program must remain a preparation day")
verify(PlanSchedule.phase(for: fixedCalendar.date(byAdding: .day, value: -1, to: programStart)!, calendar: fixedCalendar) == .preparation, "preparation day must have its own phase rather than being treated as completed")
verify(PlanSchedule.phase(for: programStart, calendar: fixedCalendar) == .active(dayIndex: 1), "program start must be the active first-day phase")
var beijingCalendar = Calendar(identifier: .gregorian)
beijingCalendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
var losAngelesCalendar = Calendar(identifier: .gregorian)
losAngelesCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
for calendar in [beijingCalendar, losAngelesCalendar] {
    let localStart = calendar.date(from: PlanSchedule.startDateComponents)!
    let justBeforeLocalMidnight = calendar.date(bySettingHour: 23, minute: 59, second: 0, of: localStart)!
    let nextLocalDay = calendar.date(byAdding: .day, value: 1, to: localStart)!
    verify(PlanSchedule.dayIndex(for: localStart, calendar: calendar) == 1, "the configured local start date must remain day one in every supported time zone")
    verify(PlanSchedule.dayIndex(for: justBeforeLocalMidnight, calendar: calendar) == 1, "day one must not advance before its local midnight in another time zone")
    verify(PlanSchedule.dayIndex(for: nextLocalDay, calendar: calendar) == 2, "the next local date must advance to day two in every supported time zone")
}
// Owner-selected start dates are future/today only, previewable before writing, and independent
// of historical completion records. Keep the process preference isolated from the user's actual
// local setting while exercising the write/notification path.
let previousRestartPreference = UserDefaults.standard.object(forKey: PlanSchedule.restartDateDefaultsKey)
UserDefaults.standard.set(programStart.timeIntervalSince1970, forKey: PlanSchedule.restartDateDefaultsKey)
let chosenStartDate = fixedCalendar.date(byAdding: .day, value: 10, to: programStart)!
let beforeStartCompletion = DailyCompletion(date: programStart, foodCompleted: true, trainingOrRecoveryCompleted: true, bedtimePreparationCompleted: false)
let startDateFixtureData = PrivateCoachData(profile: profile, dailyCompletions: [beforeStartCompletion])
verify(!PlanSchedule.canChooseStartDate(fixedCalendar.date(byAdding: .day, value: -1, to: programStart)!, now: programStart, calendar: fixedCalendar), "a selected plan start may not move into the past")
let startPreview = PlanSchedule.previewStartDate(chosenStartDate, now: programStart, calendar: fixedCalendar)
verify(startPreview?.newStartDate == chosenStartDate && startPreview?.newEndDate == fixedCalendar.date(byAdding: .day, value: 60, to: chosenStartDate), "a future start date must preview the complete 61-day range")
verify(startPreview?.dateRangeDescription.contains("newStartDate.formatted") == false && startPreview?.dateRangeDescription.contains("第 1 天") == true, "start-date preview must render actual dates rather than interpolation tokens")
verify(PlanSchedule.setStartDate(chosenStartDate, now: programStart, calendar: fixedCalendar), "an owner-confirmed future start date must persist")
verify(PlanSchedule.dayIndex(for: chosenStartDate, calendar: fixedCalendar) == 1, "the chosen start date must become day one")
verify(startDateFixtureData.dailyCompletions == [beforeStartCompletion], "changing start date must not mutate historical completion records")
let progressProfile = UserProfile(displayName: "节奏测试", sustainableGoal: SustainableGoal(pace: .steady, weeklyTrainingDays: 3, minimumMinutes: 10, reviewEveryWeeks: 2))
UserDefaults.standard.set(programStart.timeIntervalSince1970, forKey: PlanSchedule.restartDateDefaultsKey)
let progressDayOne = fixedCalendar.date(from: DateComponents(year: 2026, month: 8, day: 10))!
let progressDayTwo = fixedCalendar.date(byAdding: .day, value: 1, to: progressDayOne)!
let progressDayThree = fixedCalendar.date(byAdding: .day, value: 2, to: progressDayOne)!
let progressData = PrivateCoachData(
    profile: progressProfile,
    dailyCompletions: [
        DailyCompletion(date: progressDayOne, foodCompleted: false, trainingOrRecoveryCompleted: true, bedtimePreparationCompleted: false),
        DailyCompletion(date: progressDayTwo, foodCompleted: false, trainingOrRecoveryCompleted: false, bedtimePreparationCompleted: false)
    ],
    flexibleTrainingSessions: [
        FlexibleTrainingSession(date: progressDayTwo, option: .postureReset, startedAt: progressDayTwo, endedAt: progressDayTwo.addingTimeInterval(12 * 60)),
        FlexibleTrainingSession(date: progressDayThree, option: .recoveryStretch, startedAt: progressDayThree, endedAt: progressDayThree.addingTimeInterval(15 * 60))
    ]
)
let progress = SustainableGoalProgress.current(data: progressData, date: progressDayThree, calendar: fixedCalendar)
verify(progress.completedSessions == 2 && progress.targetSessions == 3 && progress.confirmedMinutes == 22, "sustainable progress must count confirmed standard/flexible sessions and exclude recovery stretch")
let importedProgressData = PrivateCoachData(
    profile: progressProfile,
    dailyCompletions: [
        DailyCompletion(date: progressDayOne, foodCompleted: false, trainingOrRecoveryCompleted: true, bedtimePreparationCompleted: false)
    ],
    importedWorkoutRecords: [
        ImportedWorkoutRecord(startedAt: progressDayOne, endedAt: progressDayOne.addingTimeInterval(30 * 60), kind: .cycling, source: .appleHealth),
        // Below-threshold manual records must not enter the sustainable goal progress.
        ImportedWorkoutRecord(startedAt: progressDayTwo, endedAt: progressDayTwo.addingTimeInterval(8 * 60), kind: .walking, source: .manual)
    ]
)
let importedProgress = SustainableGoalProgress.current(data: importedProgressData, date: progressDayTwo, calendar: fixedCalendar)
verify(importedProgress.completedSessions == 1 && importedProgress.confirmedMinutes == 30, "imported workouts must respect the minimum duration and must not double-count a same-day formal completion")
let sameDayImportedProgressData = PrivateCoachData(
    profile: progressProfile,
    importedWorkoutRecords: [
        ImportedWorkoutRecord(startedAt: progressDayOne.addingTimeInterval(9 * 3600), endedAt: progressDayOne.addingTimeInterval(9 * 3600 + 15 * 60), kind: .coreTraining, source: .appleHealth),
        ImportedWorkoutRecord(startedAt: progressDayOne.addingTimeInterval(12 * 3600), endedAt: progressDayOne.addingTimeInterval(12 * 3600 + 25 * 60), kind: .coreTraining, source: .appleHealth),
        ImportedWorkoutRecord(startedAt: progressDayOne.addingTimeInterval(18 * 3600), endedAt: progressDayOne.addingTimeInterval(18 * 3600 + 74 * 60), kind: .coreTraining, source: .appleHealth)
    ]
)
let sameDayImportedProgress = SustainableGoalProgress.current(data: sameDayImportedProgressData, date: progressDayOne, calendar: fixedCalendar)
verify(sameDayImportedProgress.completedSessions == 3 && sameDayImportedProgress.confirmedMinutes == 114, "separate same-day Apple Health workouts must each advance weekly sessions and sum non-overlapping minutes")
if let previousRestartPreference {
    UserDefaults.standard.set(previousRestartPreference, forKey: PlanSchedule.restartDateDefaultsKey)
} else {
    UserDefaults.standard.removeObject(forKey: PlanSchedule.restartDateDefaultsKey)
}
verify(LaunchPreparationPlan.make(date: preparationDate, calendar: fixedCalendar).dinner.title.contains("启动准备"), "the final preparation day must not masquerade as plan day one")
verify(TrainingCatalog.card(for: programStart, calendar: fixedCalendar)?.dayIndex == 1, "today training lookup must resolve only the current plan day")
verify(TodayFeature.canComplete(dayOneScheduled!, at: programStart, calendar: fixedCalendar), "only the scheduled current day must allow a daily check-in")
let skippedTodayData = DailySkipService.toggle(for: dayOneScheduled!, in: PrivateCoachData(profile: profile), at: programStart, calendar: fixedCalendar)
verify(skippedTodayData.dailyCompletions.first?.isSkipped == true, "today’s explicit skip must be privately stored")
let resumedTodayData = TodayFeature.completing(.eat, for: dayOneScheduled!, in: skippedTodayData, at: programStart, calendar: fixedCalendar)
verify(resumedTodayData.dailyCompletions.first?.isSkipped == false && resumedTodayData.dailyCompletions.first?.foodCompleted == true, "doing any action must automatically reverse a same-day skip without losing the action")
let restoredSkipData = DailySkipService.toggle(for: dayOneScheduled!, in: skippedTodayData, at: programStart, calendar: fixedCalendar)
verify(restoredSkipData.dailyCompletions.first?.isSkipped == false, "an explicit same-day skip must be reversible")
let tomorrowScheduled = PlanSchedule.makePlan(for: fixedCalendar.date(byAdding: .day, value: 1, to: programStart)!, calendar: fixedCalendar)!
verify(!TodayFeature.canComplete(tomorrowScheduled, at: programStart, calendar: fixedCalendar), "future daily cards must remain read-only")
verify(!TodayFeature.canComplete(dayOneScheduled!, at: tomorrowScheduled.date, calendar: fixedCalendar), "an already-open previous-day card must become read-only after local midnight")
let futureDatedRecordData = PrivateCoachData(
    profile: profile,
    dailyCompletions: [DailyCompletion(date: tomorrowScheduled.date, foodCompleted: true, trainingOrRecoveryCompleted: true, bedtimePreparationCompleted: true)],
    planChanges: [PlanChange(kind: .recoveryDowngrade, authority: .automatic, reason: "损坏测试记录", before: "标准版", after: "恢复版", createdAt: tomorrowScheduled.date)]
)
verify(
    CalendarDayStatus.resolve(for: tomorrowScheduled.date, data: futureDatedRecordData, asOf: programStart, calendar: fixedCalendar) == .upcoming,
    "future-dated private completion or recovery records must never make a future calendar day appear executed"
)
let historicalPlan = PlanSchedule.makePlan(for: fixedCalendar.date(byAdding: .day, value: -1, to: programStart)!, calendar: fixedCalendar)
verify(historicalPlan == nil, "dates before plan start must not create a check-in plan")
let rejectedFutureCheckIn = TodayFeature.completing(.eat, for: tomorrowScheduled, in: PrivateCoachData(profile: profile), at: programStart, calendar: fixedCalendar)
verify(rejectedFutureCheckIn.dailyCompletions.isEmpty, "business rules must reject a future-day check-in even if a UI path attempts it")
let dayEight = fixedCalendar.date(byAdding: .day, value: 7, to: programStart)!
verify(PlanSchedule.dayIndex(for: dayEight, calendar: fixedCalendar) == 8, "program day must advance by local calendar days")
verify(TrainingCatalog.card(for: dayEight, calendar: fixedCalendar)?.dayIndex == 8, "today training lookup must advance with the local plan date")
for dayIndex in 1...56 {
    let date = fixedCalendar.date(byAdding: .day, value: dayIndex - 1, to: programStart)!
    let plan = PlanSchedule.makePlan(for: date, calendar: fixedCalendar)
    verify(plan != nil, "every in-range calendar day must resolve to a complete plan")
    verify(plan?.dinner == RecipeCatalog.all56[dayIndex - 1], "day \(dayIndex) must use its matching dinner card")
    verify(plan?.breakfast == BreakfastCatalog.card(dayIndex: dayIndex), "day \(dayIndex) must use its matching breakfast card")
    let expectedLunch = LunchCatalog.card(dayIndex: dayIndex)
    verify(plan?.lunch == expectedLunch, "day \(dayIndex) must use its matching lunch card")
    verify(TrainingCatalog.card(for: date, calendar: fixedCalendar)?.dayIndex == dayIndex, "day \(dayIndex) must use its matching training card")
    let expectedWeek = ((dayIndex - 1) / 7) + 1
    verify(ShoppingPlanCatalog.plan(forWeek: expectedWeek)?.weekNumber == expectedWeek, "day \(dayIndex) must map to its matching weekly shopping plan")
}
verify(RecipeCatalog.all56.allSatisfy { !$0.displayTitle.contains("周一｜") && !$0.displayTitle.contains("周二｜") && !$0.displayTitle.contains("周三｜") && !$0.displayTitle.contains("周四｜") && !$0.displayTitle.contains("周五｜") && !$0.displayTitle.contains("周六｜") && !$0.displayTitle.contains("周日｜") }, "meal display names must not show fixed weekdays that can disagree with actual dates")
let closingDay = fixedCalendar.date(byAdding: .day, value: 56, to: programStart)!
verify(PlanSchedule.makePlan(for: closingDay, calendar: fixedCalendar) != nil, "day 57 must resolve to an explicit closing plan")
verify(TrainingCatalog.card(for: fixedCalendar.date(byAdding: .day, value: 56, to: programStart)!, calendar: fixedCalendar) == nil, "training lookup must not silently repeat after day 56")
let firstDayAfterProgram = fixedCalendar.date(byAdding: .day, value: 61, to: programStart)!
verify(PlanSchedule.hasEnded(on: firstDayAfterProgram, calendar: fixedCalendar), "the day after 56 days must be an explicit program completion state")
verify(PlanSchedule.phase(for: firstDayAfterProgram, calendar: fixedCalendar) == .completed, "the day after the program must be an explicit completed phase")
verify(ProgramCompletionPlan.make(date: firstDayAfterProgram).dinner.title.contains("阶段评估"), "completed programs must show assessment instead of a new plan day")
let replacementDinner = MealCard(
    title: "豆腐鸡蛋西兰花饭（临时替换）",
    ingredients: ["北豆腐 250g", "鸡蛋 2 个（约 100g）", "西兰花 400g", "熟米饭 90g", "油 5g"],
    thawAndPortion: "豆腐冷藏保存；今天只做 1 份，不做饭盒。",
    timedSteps: ["0:00 电饭锅加热熟饭。", "1:00 锅加油 5g，鸡蛋炒 90 秒盛出。", "3:00 豆腐加水 30ml 煎 3 分钟。", "6:00 西兰花加水 60ml，盖盖 4 分钟。", "10:00 鸡蛋回锅翻 1 分钟，装盘。"],
    portionsAndStorage: "今天做 1 份；如有剩余，2 小时内冷藏，明天中午前彻底加热一次后吃完。总操作 12 分钟。",
    substitutions: "西兰花可换花菜 400g。"
)
verify(MealSubstitutionService.validationErrors(for: replacementDinner).isEmpty, "complete confirmed substitution card must include grams, prep, timing, storage, reheating, and time cap")
let vagueReplacementCard = MealCard(
    title: "审计夹具｜临时餐含糊时长",
    ingredients: ["北豆腐 250g", "西兰花 300g", "熟米饭 180g"],
    thawAndPortion: "豆腐冷藏沥水；西兰花洗切；做 1 份。",
    timedSteps: ["0:00 电饭锅加热米饭。", "1:00 锅中放豆腐和水 40ml。", "5:00 西兰花按包装时间煮熟。", "9:00 调味后装盘。"],
    portionsAndStorage: "做 1 份，不做饭盒；剩余食材 2 小时内冷藏。总操作 12 分钟；下次加热至热透。",
    substitutions: "西兰花可换花菜 300g。"
)
verify(MealSubstitutionService.validationErrors(for: vagueReplacementCard).contains { $0.contains("不能使用含糊时长") }, "same-day replacement must reject vague cooking timing")
let overlongReplacementCard = MealCard(
    title: "审计夹具｜临时餐超时",
    ingredients: ["北豆腐 250g", "西兰花 300g", "熟米饭 180g"],
    thawAndPortion: "豆腐冷藏沥水；西兰花洗切；做 1 份。",
    timedSteps: ["0:00 电饭锅加热米饭。", "1:00 锅中放豆腐和水 40ml。", "5:00 放西兰花，盖盖 4 分钟。", "21:00 调味后装盘。"],
    portionsAndStorage: "做 1 份，不做饭盒；剩余食材 2 小时内冷藏。总操作 12 分钟；下次加热至热透。",
    substitutions: "西兰花可换花菜 300g。"
)
verify(MealSubstitutionService.validationErrors(for: overlongReplacementCard).contains { $0.contains("超过声明的总操作") }, "same-day replacement must reject a step timeline beyond its declared limit")
verify(MealSubstitutionService.availableFoodValidationErrors("北豆腐、西兰花和剩饭").isEmpty == false, "a replacement must not rely on an unmeasured food description")
verify(MealSubstitutionService.availableFoodValidationErrors("北豆腐 250g、西兰花 300g、熟米饭 180g").isEmpty, "a replacement may proceed only after the owner confirms measurable available food")
let incompleteReplacement = MealCard(title: "随便吃", ingredients: [], thawAndPortion: "", timedSteps: ["煮熟"], portionsAndStorage: "", substitutions: "")
let incompleteAttempt = MealSubstitutionService.confirm(replacement: incompleteReplacement, for: dayOneScheduled!, confirmedByUser: true, in: PrivateCoachData(profile: profile), calendar: fixedCalendar)
verify(!incompleteAttempt.validationErrors.isEmpty && incompleteAttempt.substitution == nil, "incomplete replacement must be rejected even after confirmation")
let untouchedSubstitution = MealSubstitutionService.confirm(replacement: replacementDinner, for: dayOneScheduled!, confirmedByUser: false, in: PrivateCoachData(profile: profile), calendar: fixedCalendar)
verify(untouchedSubstitution.plan.dinner == dayOneScheduled?.dinner && untouchedSubstitution.data.mealSubstitutions.isEmpty && untouchedSubstitution.change == nil, "unconfirmed meal replacement must not change the plan or data")
let confirmedSubstitution = MealSubstitutionService.confirm(replacement: replacementDinner, for: dayOneScheduled!, availableFoodSummary: "北豆腐 250g、鸡蛋 100g、西兰花 300g、熟米饭 180g", confirmedByUser: true, at: programStart, in: PrivateCoachData(profile: profile), calendar: fixedCalendar)
verify(confirmedSubstitution.plan.dinner == replacementDinner, "confirmed substitution must apply to today dinner")
let replacementActions = TodayFeature.actions(plan: confirmedSubstitution.plan, completion: nil)
verify(replacementActions.first(where: { $0.id == .eat })?.detail.contains(replacementDinner.title) == true, "today's eat action must immediately show the user-confirmed replacement meal")
verify(confirmedSubstitution.data.mealSubstitutions.count == 1, "confirmed substitution must be private persisted data")
verify(confirmedSubstitution.change?.kind == .mealSubstitution && confirmedSubstitution.change?.authority == .requiresConfirmation, "confirmed substitution must retain confirmation audit trail")
verify(MealSubstitutionService.appliedPlan(for: dayOneScheduled!, in: confirmedSubstitution.data, calendar: fixedCalendar).dinner == replacementDinner, "stored substitution must reapply after reload")
let reloadedReplacementPlan = MealSubstitutionService.appliedPlan(for: dayOneScheduled!, in: confirmedSubstitution.data, calendar: fixedCalendar)
verify(TodayFeature.actions(plan: reloadedReplacementPlan, completion: nil).first(where: { $0.id == .eat })?.detail.contains(replacementDinner.title) == true, "today's eat action must still show the replacement meal after private data reload")
verify(MealSubstitutionService.activeSubstitution(for: dayEight, in: confirmedSubstitution.data, calendar: fixedCalendar) == nil, "meal replacement must not affect other days")
let replacementBreakfast = MealCard(title: "豆浆燕麦蛋早餐（临时替换）", ingredients: ["燕麦 40g", "无糖豆浆 300ml", "鸡蛋 2 个（约 100g）", "苹果 150g"], thawAndPortion: "前夜将燕麦称入带盖碗；鸡蛋冷藏。做 1 份。", timedSteps: ["0:00 电饭锅加水 80ml 蒸蛋。", "0:30 豆浆倒杯。", "6:00 苹果切块。", "7:00 燕麦拌豆浆，配蛋吃完。"], portionsAndStorage: "做 1 份；鸡蛋 2 小时内冷藏，3 天内彻底加热一次后吃完。总操作 8 分钟。", substitutions: "苹果可换橙子 150g。")
let confirmedBreakfast = MealSubstitutionService.confirm(replacement: replacementBreakfast, for: dayOneScheduled!, slot: .breakfast, availableFoodSummary: "燕麦 40g、无糖豆浆 300ml、鸡蛋 2 个、苹果 150g", confirmedByUser: true, at: programStart, in: PrivateCoachData(profile: profile), calendar: fixedCalendar)
verify(confirmedBreakfast.plan.breakfast == replacementBreakfast && confirmedBreakfast.plan.dinner == dayOneScheduled?.dinner, "confirmed breakfast replacement must change only breakfast")
let breakfastAndDinnerReplacements = MealSubstitutionService.confirm(
    replacement: replacementDinner,
    for: confirmedBreakfast.plan,
    slot: .dinner,
    availableFoodSummary: "北豆腐 250g、鸡蛋 100g、西兰花 300g、熟米饭 180g",
    confirmedByUser: true,
    at: programStart,
    in: confirmedBreakfast.data,
    calendar: fixedCalendar
)
let reloadedBreakfastAndDinnerPlan = MealSubstitutionService.appliedPlan(
    for: dayOneScheduled!,
    in: breakfastAndDinnerReplacements.data,
    calendar: fixedCalendar
)
verify(
    reloadedBreakfastAndDinnerPlan.breakfast == replacementBreakfast
        && reloadedBreakfastAndDinnerPlan.dinner == replacementDinner,
    "reloading a day with separate breakfast and dinner replacements must preserve both meal slots"
)
let revertedBreakfastInMultiSlotDay = MealSubstitutionService.revokeLatest(
    for: reloadedBreakfastAndDinnerPlan,
    slot: .breakfast,
    at: programStart,
    in: breakfastAndDinnerReplacements.data,
    calendar: fixedCalendar
)
verify(
    revertedBreakfastInMultiSlotDay.wasReverted
        && revertedBreakfastInMultiSlotDay.plan.breakfast == dayOneScheduled?.breakfast
        && revertedBreakfastInMultiSlotDay.plan.dinner == replacementDinner,
    "reverting one meal slot must restore only that slot and retain another same-day replacement"
)
let futurePlanDate = fixedCalendar.date(byAdding: .day, value: 1, to: programStart)!
let futurePlanForSubstitution = PlanSchedule.makePlan(for: futurePlanDate, calendar: fixedCalendar)!
let futureSubstitution = MealSubstitutionService.confirm(replacement: replacementDinner, for: futurePlanForSubstitution, availableFoodSummary: "北豆腐 250g、鸡蛋 2 个、西兰花 400g、熟米饭 90g", confirmedByUser: true, at: programStart, in: PrivateCoachData(profile: profile), calendar: fixedCalendar)
verify(futureSubstitution.substitution == nil && futureSubstitution.data.mealSubstitutions.isEmpty && futureSubstitution.validationErrors.contains { $0.contains("当天") }, "confirmed meal substitution must reject future-day writes")
let completedDinnerOnly = TodayFeature.completingMeal(.dinner, for: dayOneScheduled!, in: PrivateCoachData(profile: profile), at: programStart, calendar: fixedCalendar)
let rejectedCompletedDinnerReplacement = MealSubstitutionService.confirm(replacement: replacementDinner, for: dayOneScheduled!, slot: .dinner, availableFoodSummary: "北豆腐 250g、鸡蛋 2 个、西兰花 400g、熟米饭 90g", confirmedByUser: true, at: programStart, in: completedDinnerOnly, calendar: fixedCalendar)
verify(rejectedCompletedDinnerReplacement.substitution == nil && rejectedCompletedDinnerReplacement.validationErrors.contains { $0.contains("已标记完成") } && rejectedCompletedDinnerReplacement.plan.dinner == dayOneScheduled?.dinner, "a completed meal must not be retroactively replaced")
let breakfastUnfinishedReplacement = MealSubstitutionService.confirm(replacement: replacementBreakfast, for: dayOneScheduled!, slot: .breakfast, availableFoodSummary: "燕麦 40g、无糖豆浆 300ml、鸡蛋 2 个、苹果 150g", confirmedByUser: true, at: programStart, in: completedDinnerOnly, calendar: fixedCalendar)
verify(breakfastUnfinishedReplacement.substitution != nil && breakfastUnfinishedReplacement.plan.breakfast == replacementBreakfast, "a different unfinished meal may still be safely replaced")
let foodCheckedIn = TodayFeature.completing(.eat, for: confirmedSubstitution.plan, in: confirmedSubstitution.data, at: programStart, calendar: fixedCalendar)
verify(foodCheckedIn.dailyCompletions.count == 1 && foodCheckedIn.dailyCompletions[0].foodCompleted, "today food check-in must be stored privately")
let moveCheckedIn = TodayFeature.completing(.move, for: confirmedSubstitution.plan, in: foodCheckedIn, at: programStart, calendar: fixedCalendar)
verify(moveCheckedIn.dailyCompletions.count == 1 && moveCheckedIn.dailyCompletions[0].trainingOrRecoveryCompleted, "same-day check-in must update rather than duplicate")

let dayOneStatusResult = HealthCheckInService.submit(
    HealthStatus(sleepHours: 5.5, painOrInjury: true),
    at: programStart,
    plan: confirmedSubstitution.plan,
    data: moveCheckedIn
)
verify(dayOneStatusResult.plan.trainingMode == .recovery, "saved day-one protective status must immediately select recovery")
verify(dayOneStatusResult.automaticChange.map { fixedCalendar.isDate($0.createdAt, inSameDayAs: programStart) } == true, "protective audit change must be dated to the actual plan day")
let persistedShoppingKey = InitialShoppingPlans.weekOne.stableKey(for: InitialShoppingPlans.weekOne.requiredItems[0])
var fullyPersistedDayOneData = dayOneStatusResult.data
fullyPersistedDayOneData.purchasedShoppingItemKeys.insert(persistedShoppingKey)
let persistentDayOneStore = try JSONPrivateCoachDataStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("youye-day-one-reload-rule-check-\(UUID().uuidString)"))
try persistentDayOneStore.save(fullyPersistedDayOneData)
let reloadedDayOneData = try persistentDayOneStore.load(ownerID: profile.id)!
let reloadedDayOnePlan = HealthCheckInService.replayedPlan(
    for: programStart,
    plan: MealSubstitutionService.appliedPlan(for: dayOneScheduled!, in: reloadedDayOneData, calendar: fixedCalendar),
    data: reloadedDayOneData,
    calendar: fixedCalendar
)
verify(reloadedDayOnePlan.dinner == replacementDinner && reloadedDayOnePlan.trainingMode == .recovery, "private reload must restore both confirmed meal replacement and protective recovery")
verify(TodayFeature.completion(for: dayOneScheduled!, in: reloadedDayOneData, calendar: fixedCalendar)?.completedCount == 2, "private reload must restore the same-day completion state for calendar color")
verify(reloadedDayOneData.purchasedShoppingItemKeys.contains(persistedShoppingKey), "private reload must restore user-confirmed shopping state")
verify(reloadedDayOneData.planChanges.contains { $0.kind == .recoveryDowngrade && fixedCalendar.isDate($0.createdAt, inSameDayAs: programStart) }, "private reload must retain the dated recovery audit trail for calendar state")

let temporaryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("youye-rule-check-\(UUID().uuidString)")
let store = try JSONPrivateCoachDataStore(directory: temporaryDirectory)
try store.save(privateData)
let reloadedData = try store.load(ownerID: profile.id)
verify(reloadedData?.profile == profile, "private local store must reload same owner data")
try store.delete(ownerID: profile.id)
let deletedData = try store.load(ownerID: profile.id)
verify(deletedData == nil, "private local data must be deletable")
let substitutionStore = try JSONPrivateCoachDataStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("youye-substitution-rule-check-\(UUID().uuidString)"))
try substitutionStore.save(confirmedSubstitution.data)
let reloadedSubstitutionData = try substitutionStore.load(ownerID: profile.id)
verify(reloadedSubstitutionData?.mealSubstitutions.first?.replacement == replacementDinner, "confirmed meal substitution must survive private JSON reload")
let encoderForLegacyData = JSONEncoder()
encoderForLegacyData.dateEncodingStrategy = .iso8601
let encodedCurrentData = try encoderForLegacyData.encode(confirmedSubstitution.data)
var legacyJSONObject = try JSONSerialization.jsonObject(with: encodedCurrentData) as! [String: Any]
legacyJSONObject.removeValue(forKey: "mealSubstitutions")
let legacyData = try JSONSerialization.data(withJSONObject: legacyJSONObject)
let decoderForLegacyData = JSONDecoder()
decoderForLegacyData.dateDecodingStrategy = .iso8601
let decodedLegacyData = try decoderForLegacyData.decode(PrivateCoachData.self, from: legacyData)
verify(decodedLegacyData.mealSubstitutions.isEmpty && decodedLegacyData.profile == profile, "old private JSON without meal substitutions must remain readable")

verify(WeekOneRecipeCatalog.cards.count == 7, "week one must contain seven recipe cards")
verify(WeekOneRecipeCatalog.validate().isEmpty, "week one recipe cards must include grams, prep, timing, storage, and substitutions")
verify(WeekTwoRecipeCatalog.cards.count == 7, "week two must contain seven recipe cards")
verify(WeekTwoRecipeCatalog.validate().isEmpty, "week two recipe cards must include grams, prep, timing, storage, and substitutions")
verify(WeekThreeRecipeCatalog.cards.count == 7, "week three must contain seven recipe cards")
verify(WeekThreeRecipeCatalog.validate().isEmpty, "week three recipe cards must include grams, prep, timing, storage, and substitutions")
verify(WeekFourRecipeCatalog.cards.count == 7, "week four must contain seven recipe cards")
verify(WeekFourRecipeCatalog.validate().isEmpty, "week four recipe cards must include grams, prep, timing, storage, and substitutions")
verify(WeekFiveRecipeCatalog.cards.count == 7, "week five must contain seven recipe cards")
verify(WeekFiveRecipeCatalog.validate().isEmpty, "week five recipe cards must include grams, prep, timing, storage, and substitutions")
verify(WeekSixRecipeCatalog.cards.count == 7, "week six must contain seven recipe cards")
verify(WeekSixRecipeCatalog.validate().isEmpty, "week six recipe cards must include grams, prep, timing, storage, and substitutions")
verify(WeekSevenRecipeCatalog.cards.count == 7, "week seven must contain seven recipe cards")
verify(WeekSevenRecipeCatalog.validate().isEmpty, "week seven recipe cards must include grams, prep, timing, storage, and substitutions")
verify(WeekEightRecipeCatalog.cards.count == 7, "week eight must contain seven recipe cards")
verify(WeekEightRecipeCatalog.validate().isEmpty, "week eight recipe cards must include grams, prep, timing, storage, and substitutions")
let allRecipeCards = WeekOneRecipeCatalog.cards + WeekTwoRecipeCatalog.cards + WeekThreeRecipeCatalog.cards + WeekFourRecipeCatalog.cards + WeekFiveRecipeCatalog.cards + WeekSixRecipeCatalog.cards + WeekSevenRecipeCatalog.cards + WeekEightRecipeCatalog.cards
verify(allRecipeCards.count == 56, "the native catalog must contain 56 recipe cards")
verify(WeekOneRecipeCatalog.validate(allRecipeCards).isEmpty, "all 56 cards must meet the same completeness rules")
verify(allRecipeCards.allSatisfy { card in
    let executionText = card.thawAndPortion + "\n" + card.timedSteps.joined(separator: "\n")
    return !executionText.contains("另一锅") && !executionText.contains("另一个锅") && !executionText.contains("第二口锅")
}, "all 56 dinner cards must run on one rice cooker plus one induction pot")
let deliberatelyOverlongStepCard = MealCard(
    title: "审计夹具｜步骤超时",
    ingredients: ["鸡蛋 100g", "水 80ml"],
    thawAndPortion: "前一晚把鸡蛋冷藏。做 1 份。",
    timedSteps: ["0:00 电饭锅加水启动。", "1:00 备好碗。", "2:00 等待蒸煮。", "12:00 取出鸡蛋。"],
    portionsAndStorage: "做 1 份；鸡蛋 2 小时内冷藏，次日彻底加热后吃完。总操作 10 分钟。",
    substitutions: "鸡蛋可换北豆腐 150g。"
)
verify(WeekOneRecipeCatalog.validate([deliberatelyOverlongStepCard]).contains { $0.contains("超过声明的总操作") }, "meal audit must reject a minute-step timeline that exceeds its declared total duration")
let nonZeroStartCard = MealCard(
    title: "审计夹具｜非零开始",
    ingredients: ["北豆腐 200g", "青菜 300g", "水 40ml"],
    thawAndPortion: "豆腐冷藏；青菜洗净。做 1 份。",
    timedSteps: ["1:00 电磁炉锅备好食材。", "2:00 豆腐加水 40ml 煮 3 分钟。", "5:00 下青菜翻 2 分钟。", "8:00 装盘。"],
    portionsAndStorage: "做 1 份；2 小时内冷藏，次日彻底加热后吃完。总操作 10 分钟。",
    substitutions: "豆腐可换鸡蛋 100g。"
)
verify(
    WeekOneRecipeCatalog.validate([nonZeroStartCard]).contains { $0.contains("必须从 0:00 开始") },
    "meal audit must reject a card that leaves the first execution minute unexplained"
)
let outOfOrderStepCard = MealCard(
    title: "审计夹具｜步骤倒序",
    ingredients: ["北豆腐 200g", "青菜 300g", "水 40ml"],
    thawAndPortion: "豆腐冷藏；青菜洗净。做 1 份。",
    timedSteps: ["0:00 电磁炉锅备好食材。", "5:00 豆腐加水 40ml 煮 3 分钟。", "3:00 下青菜翻 2 分钟。", "8:00 装盘。"],
    portionsAndStorage: "做 1 份；2 小时内冷藏，次日彻底加热后吃完。总操作 10 分钟。",
    substitutions: "豆腐可换鸡蛋 100g。"
)
verify(
    WeekOneRecipeCatalog.validate([outOfOrderStepCard]).contains { $0.contains("分钟步骤不能倒序") },
    "meal audit must reject an out-of-order cooking timeline instead of leaving the person to infer the sequence"
)
let lateDurationOverrunCard = MealCard(
    title: "审计夹具｜末步时长超时",
    ingredients: ["北豆腐 200g", "青菜 300g", "水 40ml"],
    thawAndPortion: "豆腐冷藏；青菜洗净。做 1 份。",
    timedSteps: ["0:00 电磁炉锅备好食材。", "1:00 豆腐加水 40ml 煮 3 分钟。", "5:00 下青菜翻 2 分钟。", "18:00 盖盖再煮 4 分钟后装盘。"],
    portionsAndStorage: "做 1 份；2 小时内冷藏，次日彻底加热后吃完。总操作 20 分钟。",
    substitutions: "豆腐可换鸡蛋 100g。"
)
verify(
    WeekOneRecipeCatalog.validate([lateDurationOverrunCard]).contains { $0.contains("步骤结束于 22 分钟，超过声明的总操作 20 分钟") },
    "meal audit must include an explicit final-step duration when enforcing the 20-minute limit"
)
let deliberatelyVagueTimingCard = MealCard(
    title: "审计夹具｜含糊时长",
    ingredients: ["鸡蛋 100g", "水 80ml"],
    thawAndPortion: "前一晚把鸡蛋冷藏。做 1 份。",
    timedSteps: ["0:00 电饭锅加水启动。", "1:00 备好碗。", "2:00 按包装时间蒸熟。", "8:00 取出鸡蛋。"],
    portionsAndStorage: "做 1 份；鸡蛋 2 小时内冷藏，次日彻底加热后吃完。总操作 10 分钟。",
    substitutions: "鸡蛋可换北豆腐 150g。"
)
verify(WeekOneRecipeCatalog.validate([deliberatelyVagueTimingCard]).contains { $0.contains("不能使用含糊时长") }, "meal audit must reject package-dependent or approximate timing")
let deliberatelyDeviceFreeCookCard = MealCard(
    title: "审计夹具｜未说明设备",
    ingredients: ["鸡蛋 100g", "水 80ml"],
    thawAndPortion: "前一晚把鸡蛋冷藏。做 1 份。",
    timedSteps: ["0:00 加水启动。", "1:00 备好碗。", "2:00 蒸煮。", "8:00 取出鸡蛋。"],
    portionsAndStorage: "做 1 份；鸡蛋 2 小时内冷藏，次日彻底加热后吃完。总操作 10 分钟。",
    substitutions: "鸡蛋可换北豆腐 150g。"
)
verify(WeekOneRecipeCatalog.validate([deliberatelyDeviceFreeCookCard]).contains { $0.contains("缺本餐使用设备说明") }, "meal audit must reject a cooking card with no explicit equipment boundary")
let animalProteinSafetyFinishCard = MealCard(
    title: "审计夹具｜动物蛋白无熟度终点",
    ingredients: ["鸡胸肉 200g", "青菜 300g", "水 80ml"],
    thawAndPortion: "鸡胸前一晚移冷藏。做 1 份。",
    timedSteps: ["0:00 电磁炉锅加油。", "1:00 下鸡胸炒 4 分钟。", "5:00 下青菜翻 2 分钟。", "8:00 装盘。"],
    portionsAndStorage: "做 1 份；2 小时内冷藏，次日彻底加热后吃完。总操作 10 分钟。",
    substitutions: "鸡胸可换北豆腐 200g。"
)
verify(animalProteinSafetyFinishCard.foodSafetyFinish?.contains("无粉红") == true, "every raw-meat card must expose a visible doneness endpoint beyond its minute timer")
verify(WeekOneRecipeCatalog.validate([animalProteinSafetyFinishCard]).isEmpty, "a raw-protein card with the derived visible doneness endpoint must remain executable without rewriting legacy stored step text")
verify(BreakfastCatalog.cards.count == 7, "breakfast catalog must contain seven executable cards")
verify(WeekOneRecipeCatalog.validate(BreakfastCatalog.cards).isEmpty, "every breakfast card must meet the same food-safety and timing rules")
verify(
    BreakfastCatalog.card(dayIndex: 5).kitchenSetup.hasPrefix("本餐使用：电饭锅；"),
    "a rice-cooker-only breakfast must not be presented as needing an induction pot"
)
let riceCookerOnlyFixture = BreakfastCatalog.card(dayIndex: 5)
verify(
    KitchenCompatibility.notice(for: riceCookerOnlyFixture, profileKitchenSetup: "一个电磁炉锅") != nil,
    "a saved kitchen missing a genuinely required rice cooker must block execution with a confirmation notice"
)
let noCookFixture = MealCard(
    title: "审计夹具｜无需加热",
    ingredients: ["无糖酸奶 200g", "香蕉 100g"],
    thawAndPortion: "食材保持冷藏；做 1 份。",
    timedSteps: ["0:00 取出冷藏酸奶。", "1:00 香蕉切片。", "2:00 装碗。", "3:00 吃完并清洗餐具。"],
    portionsAndStorage: "做 1 份；冷食需全程冷藏，开封后立即吃完。总操作 3 分钟。",
    substitutions: "香蕉可换苹果 150g。"
)
verify(
    KitchenCompatibility.notice(for: noCookFixture, profileKitchenSetup: "只有一口炒锅") == nil,
    "a no-cook card must not mistake its friendly no-appliance wording for a required rice cooker or induction pot"
)
verify(
    LunchCatalog.card(dayIndex: 2).kitchenSetup.hasPrefix("本餐使用：1 个电磁炉锅；"),
    "a carried lunch must not assume an office microwave and may use only the owner’s single induction pot for the at-home heat path"
)
verify(
    DayOnePlan.fallbackLunch.timedSteps.first?.contains("鸡蛋 2 个放蒸架") == true
        && DayOnePlan.fallbackLunch.timedSteps.contains { $0.contains("蛋黄凝固") },
    "day-one lunch must explicitly cook its eggs and expose the doneness check instead of leaving a beginner to infer a raw-egg step"
)
verify(
    !LunchCatalog.card(dayIndex: 2).timedSteps.joined(separator: " ").contains("微波")
        && LunchCatalog.card(dayIndex: 2).portionsAndStorage.contains("未确认")
        && LunchCatalog.card(dayIndex: 2).substitutions.contains("午间不在家"),
    "lunch must not invent an office appliance or cold-food path for leftovers; a mismatched lunch environment must require an owner-confirmed self-cook replan"
)
let eggWashFixture = MealCard(
    title: "审计夹具｜鸡蛋清洗",
    ingredients: ["鸡蛋 100g", "水 80ml"],
    thawAndPortion: "鸡蛋使用前清洗；做 1 份。",
    timedSteps: ["0:00 电饭锅加水启动。", "1:00 备好碗。", "2:00 蒸煮。", "8:00 取出鸡蛋。"],
    portionsAndStorage: "做 1 份；鸡蛋 2 小时内冷藏，次日彻底加热后吃完。总操作 10 分钟。",
    substitutions: "鸡蛋可换北豆腐 150g。"
)
verify(WeekOneRecipeCatalog.validate([eggWashFixture]).contains { $0.contains("无需在使用前清洗") }, "recipe audit must reject washing shell eggs immediately before use")
let legacyGenericPotCard = MealCard(
    title: "审计夹具｜泛称锅具",
    ingredients: ["鸡蛋 100g", "水 80ml"],
    thawAndPortion: "前一晚把鸡蛋冷藏。做 1 份。",
    timedSteps: ["0:00 电饭锅加水启动。", "1:00 锅加油。", "2:00 锅内翻炒。", "8:00 装盘吃完。"],
    portionsAndStorage: "做 1 份；鸡蛋 2 小时内冷藏，次日彻底加热后吃完。总操作 10 分钟。",
    substitutions: "鸡蛋可换北豆腐 150g。"
)
verify(
    legacyGenericPotCard.visibleTimedSteps[1].contains("电磁炉锅加油")
        && legacyGenericPotCard.visibleTimedSteps[2].contains("电磁炉锅内翻炒")
        && legacyGenericPotCard.visibleTimedSteps[0] == "0:00 电饭锅加水启动。",
    "rendered recipe steps must make a legacy generic pot explicitly the one induction pot without changing the rice cooker"
)
let everyVisibleMealCard = allRecipeCards + BreakfastCatalog.cards + (1...56).map(LunchCatalog.card)
verify(
    everyVisibleMealCard.filter { card in
        ["鸡胸", "鸡腿", "鸡肉", "牛肉", "肥牛", "里脊", "瘦肉", "肉末", "鱼片", "鱼柳", "巴沙鱼", "虾仁", "鸡蛋"].contains { token in card.ingredients.contains { $0.contains(token) } }
    }.allSatisfy { $0.foodSafetyFinish != nil },
    "every rendered meal with raw animal protein must expose its ingredient-specific doneness endpoint"
)
verify(
    everyVisibleMealCard.allSatisfy { card in
        card.visibleTimedSteps.allSatisfy { step in
            !step
                .replacingOccurrences(of: "电饭锅", with: "")
                .replacingOccurrences(of: "电磁炉锅", with: "")
                .contains("锅")
        }
    },
    "every rendered recipe step must avoid an ambiguous unqualified cooking-pot label"
)
let commuterMealAudit = CommuterMealSafetyAudit.validateLunches()
if !commuterMealAudit.isEmpty { print("COMMUTER MEAL AUDIT:\n" + commuterMealAudit.joined(separator: "\n")) }
verify(commuterMealAudit.isEmpty, "all 56 lunches must be executable, safely carried, and have a same-day self-cook fallback")
let healthPlan = HealthKitPermissionPlan()
verify(healthPlan.readMetrics.count == HealthKitReadMetric.allCases.count, "HealthKit permission plan must enumerate every requested metric")
verify(healthPlan.readMetrics == [.bodyMass, .bodyFatPercentage, .stepCount, .sleepAnalysis, .restingHeartRate, .activeEnergyBurned, .workouts], "HealthKit permission plan must request only the declared minimum metrics")
let readOnlyHealthPlan = HealthKitPermissionPlan.readOnly
verify(readOnlyHealthPlan.readMetrics == Set(HealthKitReadMetric.allCases), "reading Apple Health summary must use the declared minimum read set")
let workoutPolicyBase = intervalBase
let workoutCandidates = [
    HealthWorkoutSummary(startedAt: workoutPolicyBase, endedAt: workoutPolicyBase.addingTimeInterval(20 * 60), kind: .cycling, title: "骑行"),
    HealthWorkoutSummary(startedAt: workoutPolicyBase.addingTimeInterval(3_600), endedAt: workoutPolicyBase.addingTimeInterval(3_600 + 30 * 60), kind: .cycling, title: "骑行"),
    HealthWorkoutSummary(startedAt: workoutPolicyBase.addingTimeInterval(7_200), endedAt: workoutPolicyBase.addingTimeInterval(7_200 + 8 * 60), kind: .walking, title: "步行"),
    // A duplicate HealthKit source row should not become a second local record.
    HealthWorkoutSummary(startedAt: workoutPolicyBase, endedAt: workoutPolicyBase.addingTimeInterval(20 * 60), kind: .cycling, title: "骑行")
]
let alreadyImportedWorkout = ImportedWorkoutRecord(startedAt: workoutPolicyBase.addingTimeInterval(3_600), endedAt: workoutPolicyBase.addingTimeInterval(3_600 + 30 * 60), kind: .cycling, source: .appleHealth)
let eligibleWorkoutCandidates = HealthWorkoutImportPolicy.eligible(workoutCandidates, minimumMinutes: 10, imported: [alreadyImportedWorkout])
verify(eligibleWorkoutCandidates.count == 1 && eligibleWorkoutCandidates[0].durationMinutes == 20, "Apple Health batch import must keep only new workouts at or above the owner's minimum duration and de-duplicate source rows")
verify(HealthWorkoutImportPolicy.eligible(workoutCandidates, minimumMinutes: 10, imported: []).allSatisfy { $0.durationMinutes >= 10 }, "workouts below the owner's minimum duration must not enter the automatic batch")
let confirmedWorkoutSyncID = UUID()
let confirmedWorkout = ConfirmedHealthWorkout(
    dayIndex: 1,
    startedAt: intervalBase,
    endedAt: intervalBase.addingTimeInterval(61),
    kind: .coreTraining,
    syncIdentifier: confirmedWorkoutSyncID
)
verify(confirmedWorkout.syncIdentifier == confirmedWorkoutSyncID && confirmedWorkout.elapsedSeconds == 61, "a confirmed workout must preserve its stable sync identifier and exact observed duration")
let malformedConfirmedWorkoutJSON = """
{
  "dayIndex": 57,
  "startedAt": (intervalBase.timeIntervalSinceReferenceDate),
  "endedAt": (intervalBase.timeIntervalSinceReferenceDate),
  "kind": "coreTraining",
  "syncIdentifier": "(UUID().uuidString)"
}
""".data(using: .utf8)!
do {
    _ = try JSONDecoder().decode(ConfirmedHealthWorkout.self, from: malformedConfirmedWorkoutJSON)
    verify(false, "a restored workout outside the program or without positive duration must not become a sync candidate")
} catch {
    verify(true, "a restored workout outside the program or without positive duration must not become a sync candidate")
}
let locallyConfirmedWorkoutData = HealthWorkoutSyncSafety.recordingConfirmation(confirmedWorkout, in: PrivateCoachData(profile: profile), at: intervalBase)
verify(
    locallyConfirmedWorkoutData.pendingWorkoutConfirmations.count == 1
        && locallyConfirmedWorkoutData.pendingHealthWorkoutSyncs.isEmpty
        && locallyConfirmedWorkoutData.healthWorkoutSyncs.isEmpty,
    "leaving a stopped timer must retain a local owner-confirmation draft without claiming or attempting an Apple Health write"
)
verify(
    HealthWorkoutSyncSafety.recordingConfirmation(confirmedWorkout, in: locallyConfirmedWorkoutData) == locallyConfirmedWorkoutData,
    "reopening or leaving the same stopped workout must not duplicate its local confirmation draft"
)
let discardedWorkoutConfirmationData = HealthWorkoutSyncSafety.discardingConfirmation(
    locallyConfirmedWorkoutData.pendingWorkoutConfirmations[0],
    in: locallyConfirmedWorkoutData
)
verify(
    discardedWorkoutConfirmationData.pendingWorkoutConfirmations.isEmpty
        && discardedWorkoutConfirmationData.pendingHealthWorkoutSyncs.isEmpty
        && discardedWorkoutConfirmationData.healthWorkoutSyncs.isEmpty,
    "discarding a local confirmation draft must not write, delete, or imply any Apple Health workout"
)
verify(
    PrivateExport.portableCopy(of: locallyConfirmedWorkoutData).pendingWorkoutConfirmations.isEmpty
        && PrivateExport.portableCopy(of: locallyConfirmedWorkoutData).pendingHealthWorkoutSyncs.isEmpty,
    "owner export must omit local workout-confirmation drafts and legacy HealthKit sync fields"
)
let healthSyncPortableJSON = String(decoding: try PrivateExport.makeOwnerExport(locallyConfirmedWorkoutData), as: UTF8.self)
verify(
    !healthSyncPortableJSON.contains("healthWorkoutSyncs")
        && !healthSyncPortableJSON.contains("pendingHealthWorkoutSyncs")
        && !healthSyncPortableJSON.contains("pendingWorkoutConfirmations"),
    "owner export JSON must omit legacy HealthKit sync fields and local confirmation-draft keys"
)
let zeroDurationWorkout = ConfirmedHealthWorkout(dayIndex: 1, startedAt: intervalBase, endedAt: intervalBase, kind: .coreTraining, syncIdentifier: confirmedWorkoutSyncID)
verify(zeroDurationWorkout.duration == 0, "zero-duration confirmed workouts must remain identifiable and not become a usable local record")
verify(confirmedWorkout.kind == .coreTraining && confirmedWorkout.duration > 0, "a stopped workout must retain the owner-confirmed type and observed duration as one immutable confirmation payload")
let crossMidnightWorkout = ConfirmedHealthWorkout(dayIndex: 1, startedAt: fixedCalendar.date(bySettingHour: 23, minute: 55, second: 0, of: programStart)!, endedAt: fixedCalendar.date(byAdding: .minute, value: 20, to: fixedCalendar.date(bySettingHour: 23, minute: 55, second: 0, of: programStart)!)!, kind: .flexibility)
verify(crossMidnightWorkout.crossesCalendarDay(calendar: fixedCalendar) && crossMidnightWorkout.duration == 20 * 60, "a real cross-midnight workout must retain exact timestamps instead of being truncated to its scheduled plan day")
verify(HealthSnapshot(source: "HealthKit").source == "HealthKit", "health summaries must carry their source")
let multiSourceStepSummary = HealthStepAggregation.average14Days(sourceCount: 2, totalSteps: 42_000)
let conservativeHealthSnapshot = HealthSnapshot(averageDailySteps14d: multiSourceStepSummary.value, availabilityNotes: multiSourceStepSummary.note.map { [$0] } ?? [])
verify(conservativeHealthSnapshot.averageDailySteps14d == nil && conservativeHealthSnapshot.availabilityNotes.first?.contains("多个来源") == true, "conflicting HealthKit step sources must remain visibly unavailable rather than becoming a merged value")
let minimalHealthPermissionPlan = HealthKitPermissionPlan(readMetrics: [.sleepAnalysis])
verify(minimalHealthPermissionPlan.readMetrics == [.sleepAnalysis], "HealthKit permission plan must support a smaller explicit read set")
verify(!PrivateCoachData.persistsHealthKitSnapshots, "private local profile data must never persist a HealthKit summary or raw sample")
#if !(os(iOS) && canImport(HealthKit))
let unavailableProvider = UnavailableHealthKitProvider()
let unavailableTask = Task { try? await unavailableProvider.readSummary() }
_ = await unavailableTask.value
#endif
verify(WeekOneTrainingCatalog.cards.count == 7, "week one must contain seven training cards")
verify(WeekOneTrainingCatalog.validate().isEmpty, "training cards must include minimum, standard, regression, stop, and camera prompts")
let forbiddenOutsideMealLabel = ["外", "食"].joined()
verify(!LunchCatalog.card(dayIndex: 1).substitutions.contains(forbiddenOutsideMealLabel), "ingredient mismatch must route to a user-confirmed self-cooked meal replanning path rather than the forbidden outside-meal label")
verify(
    WeekOneTrainingCatalog.cards.allSatisfy {
        $0.video.source == .bilibili
            && $0.video.status == "已核验"
            && $0.video.checkedAt != nil
            && $0.video.verifiedCandidateURL != nil
    },
    "checked training videos must stay on Bilibili and expose only complete timestamped direct lessons"
)
verify(WeekTwoTrainingCatalog.cards.count == 7, "week two must contain seven training cards")
verify(WeekTwoTrainingCatalog.validate().isEmpty, "week two training cards must include safety fields and camera prompts")
verify(TrainingCatalog.firstFourteenDays.count == 14, "training list must expose the first two weeks")
verify(WeeksThreeFourTrainingCatalog.cards.count == 14, "weeks three and four must contain fourteen training cards")
verify(WeeksThreeFourTrainingCatalog.validate().isEmpty, "weeks three and four training cards must include safety fields and camera prompts")
verify(TrainingCatalog.firstFourWeeks.count == 28, "training list must expose first four weeks")
verify(WeeksFiveEightTrainingCatalog.cards.count == 28, "weeks five to eight must contain twenty-eight training cards")
verify(WeeksFiveEightTrainingCatalog.validate().isEmpty, "weeks five to eight training cards must include safety fields and camera prompts")
verify(TrainingCatalog.all56.count == 56, "training list must expose all 56 days")
let trainingLoadAudit = TrainingLoadAudit.validate(TrainingCatalog.all56)
if !trainingLoadAudit.isEmpty { print("TRAINING LOAD AUDIT:\n" + trainingLoadAudit.joined(separator: "\n")) }
verify(trainingLoadAudit.isEmpty, "training plan must preserve recovery, endurance choice, and no-four-day core/posture overload structure")
let trainingExecutionAudit = TrainingExecutionAudit.validate(TrainingCatalog.all56)
if !trainingExecutionAudit.isEmpty { print("TRAINING EXECUTION AUDIT:\n" + trainingExecutionAudit.joined(separator: "\n")) }
verify(trainingExecutionAudit.isEmpty, "every training card must remain beginner-executable, equipment-compatible, and safe for live-camera use")
verify(TrainingCatalog.all56.filter(\.containsMovingOrWaterSegment).allSatisfy { $0.livePoseSafetyNote.contains("不要开启取景") }, "all moving or water-based cards must prohibit live camera use")
verify(TrainingCatalog.all56.filter { $0.loadKind == .recovery }.count >= 8, "each week must include a recovery-priority training day")
verify(TrainingCatalog.all56.filter { $0.loadKind == .endurance }.count >= 8, "each week must include a swim-or-bike choice day")
let flexibleProbePlan = TodayPlan(
    date: programStart,
    dinner: RecipeCatalog.all56[0],
    trainingMode: .standard,
    trainingInstruction: "最低完成版",
    bedtimePreparation: []
)
let flexibleNormal = FlexibleTrainingAdvisor.recommendation(
    for: flexibleProbePlan,
    status: HealthStatus(sleepHours: 7, energy: 4),
    trainingAlreadyCompleted: false
)
verify(flexibleNormal.recommended == FlexibleTrainingOption.minimum && flexibleNormal.options.contains(FlexibleTrainingOption.postureReset), "normal status must expose a recommended flexible training choice and a posture alternative")
let flexibleLowEnergy = FlexibleTrainingAdvisor.recommendation(
    for: flexibleProbePlan,
    status: HealthStatus(sleepHours: 5.5, energy: 1),
    trainingAlreadyCompleted: false
)
verify(flexibleLowEnergy.recommended == FlexibleTrainingOption.recoveryStretch && flexibleLowEnergy.options.contains(FlexibleTrainingOption.minimum), "low energy or short sleep must lower the recommendation without removing the minimum option")
let pausedFlexiblePlan = TodayPlan(
    date: programStart,
    dinner: RecipeCatalog.all56[0],
    trainingMode: .recovery,
    trainingInstruction: "暂停计划训练",
    bedtimePreparation: []
)
let pausedFlexible = FlexibleTrainingAdvisor.recommendation(for: pausedFlexiblePlan, status: HealthStatus(illnessSymptoms: true), trainingAlreadyCompleted: false)
verify(pausedFlexible.options == [FlexibleTrainingOption.recoveryStretch] && !pausedFlexible.recommended.canCountAsTraining, "illness or a rest-only plan must expose recovery only and never count rest as training")
let menstrualFlexible = FlexibleTrainingAdvisor.recommendation(for: flexibleProbePlan, status: HealthStatus(menstrualPhase: .menstrual, menstrualDiscomfort: true), trainingAlreadyCompleted: false)
verify(menstrualFlexible.options == [FlexibleTrainingOption.recoveryStretch], "明显经期不适 must use recovery-only flexible training")
let finishedFlexible = FlexibleTrainingAdvisor.recommendation(for: flexibleProbePlan, status: nil, trainingAlreadyCompleted: true)
verify(finishedFlexible.options == [FlexibleTrainingOption.recoveryStretch], "an already completed day must not offer a compensatory training session")
let flexibleStart = programStart.addingTimeInterval(9 * 3600)
let flexibleEnd = flexibleStart.addingTimeInterval(12 * 60)
let flexibleDraft = FlexibleTrainingDraft(date: programStart, option: .postureReset, startedAt: flexibleStart, endedAt: flexibleEnd)
let savedFlexibleDraftData = FlexibleTrainingLedger.recording(flexibleDraft, in: PrivateCoachData(profile: profile))
verify(savedFlexibleDraftData.pendingFlexibleTrainingDrafts == [flexibleDraft] && savedFlexibleDraftData.dailyCompletions.isEmpty, "stopping flexible training must persist an option-aware pending draft without marking completion")
let confirmedFlexibleData = FlexibleTrainingLedger.confirming(flexibleDraft, for: flexibleProbePlan, in: savedFlexibleDraftData)
verify(confirmedFlexibleData.pendingFlexibleTrainingDrafts.isEmpty && confirmedFlexibleData.flexibleTrainingSessions.count == 1 && confirmedFlexibleData.flexibleTrainingSessions[0].option == .postureReset && confirmedFlexibleData.flexibleTrainingSessions[0].durationLabel == "12:00", "confirming a flexible draft must retain its option and real duration")
verify(confirmedFlexibleData.dailyCompletion(for: programStart, calendar: fixedCalendar)?.trainingOrRecoveryCompleted == true, "confirming a countable flexible option must set the day's training pillar once")
let confirmedFlexibleTwice = FlexibleTrainingLedger.confirming(flexibleDraft, for: flexibleProbePlan, in: confirmedFlexibleData)
verify(confirmedFlexibleTwice == confirmedFlexibleData, "confirming the same flexible draft twice must be idempotent")
let recoveryDraft = FlexibleTrainingDraft(date: programStart, option: .recoveryStretch, startedAt: flexibleStart, endedAt: flexibleStart.addingTimeInterval(8 * 60))
let confirmedRecovery = FlexibleTrainingLedger.confirming(recoveryDraft, for: flexibleProbePlan, in: FlexibleTrainingLedger.recording(recoveryDraft, in: PrivateCoachData(profile: profile)))
verify(confirmedRecovery.flexibleTrainingSessions.count == 1 && confirmedRecovery.dailyCompletion(for: programStart, calendar: fixedCalendar)?.trainingOrRecoveryCompleted != true, "confirming recovery stretch must retain the session but never count it as formal training")
let painfulFeedback = TrainingFeedback(effort: 6, pain: 2, sleepHours: 7, completed: true)
let painAdaptation = TrainingFeedbackService.adapt(painfulFeedback)
verify(painAdaptation.action == .recoveryDowngrade && painAdaptation.requiresConfirmation == false, "pain must auto downgrade without confirmation")
let feedbackSafetyResult = TrainingFeedbackService.submit(painfulFeedback, at: programStart, plan: dayOneScheduled!, data: PrivateCoachData(profile: profile))
verify(feedbackSafetyResult.plan.trainingMode == .recovery, "today's painful training feedback must immediately select recovery")
verify(feedbackSafetyResult.automaticChange?.kind == .recoveryDowngrade && feedbackSafetyResult.automaticChange?.authority == .automatic, "training feedback safety downgrade must leave an automatic audit record")
verify(feedbackSafetyResult.wasAccepted && feedbackSafetyResult.data.trainingFeedback.count == 1 && feedbackSafetyResult.data.planChanges.count == 1 && feedbackSafetyResult.data.datedHealthStatusNotes.count == 1, "training feedback safety must persist a minimal same-day protection signal alongside its audit record")
verify(feedbackSafetyResult.data.dailyCompletions.first?.trainingOrRecoveryCompleted == true, "an explicit completed training feedback must mark today’s movement pillar complete")
let twiceCompletedFeedback = TrainingFeedbackService.submit(painfulFeedback, at: programStart, plan: feedbackSafetyResult.plan, data: feedbackSafetyResult.data, calendar: fixedCalendar)
verify(twiceCompletedFeedback.data.dailyCompletions.first?.trainingOrRecoveryCompleted == true, "repeated completed feedback must not toggle a recorded movement completion back off")
verify(twiceCompletedFeedback.data.trainingFeedback.count == 1 && twiceCompletedFeedback.data.datedHealthStatusNotes.count == 1 && twiceCompletedFeedback.data.planChanges.count == 1 && twiceCompletedFeedback.automaticChange == nil, "retrying one stable feedback submission must not duplicate feedback, safety status, or recovery audit history")
let stoppedFeedback = TrainingFeedback(effort: 5, pain: 2, sleepHours: 7, completed: false)
let stoppedFeedbackResult = TrainingFeedbackService.submit(stoppedFeedback, at: programStart, plan: dayOneScheduled!, data: PrivateCoachData(profile: profile), calendar: fixedCalendar)
verify(stoppedFeedbackResult.data.dailyCompletions.first?.trainingOrRecoveryCompleted != true, "a feedback entry without explicit completion must not claim that training was completed")
verify(stoppedFeedbackResult.plan.trainingMode == .recovery && stoppedFeedbackResult.data.planChanges.count == 1, "an early stop with pain must still switch to recovery without claiming completion")
let staleFeedbackAfterSavedRecovery = TrainingFeedbackService.submit(
    TrainingFeedback(effort: 5, pain: 0, sleepHours: 7, completed: false),
    at: programStart,
    plan: dayOneScheduled!,
    data: feedbackSafetyResult.data,
    calendar: fixedCalendar
)
verify(
    staleFeedbackAfterSavedRecovery.plan.trainingMode == .recovery
        && staleFeedbackAfterSavedRecovery.data.planChanges.count == 1
        && staleFeedbackAfterSavedRecovery.automaticChange == nil,
    "feedback from a stale standard card must retain an existing saved recovery day without a duplicate audit"
)
verify(fixedCalendar.isDate(feedbackSafetyResult.data.trainingFeedback[0].date, inSameDayAs: programStart), "accepted training feedback must be stored under the actual plan day rather than its UI construction time")
let replayedFeedbackSafetyPlan = HealthCheckInService.replayedPlan(for: programStart, plan: dayOneScheduled!, data: feedbackSafetyResult.data, calendar: fixedCalendar)
verify(replayedFeedbackSafetyPlan.trainingMode == .recovery, "painful feedback recovery must replay after an app restart instead of silently returning to standard training")
verify(PlanChangeAuditService.canRevert(feedbackSafetyResult.automaticChange!) == false && PlanChangeAuditService.explanation(for: feedbackSafetyResult.automaticChange!).contains("不能"), "a safety recovery audit record must not be directly revertible while its protection signal remains")
let futureFeedbackPlan = PlanSchedule.makePlan(for: fixedCalendar.date(byAdding: .day, value: 1, to: programStart)!, calendar: fixedCalendar)!
let rejectedFutureFeedback = TrainingFeedbackService.submit(painfulFeedback, at: programStart, plan: futureFeedbackPlan, data: PrivateCoachData(profile: profile), calendar: fixedCalendar)
verify(!rejectedFutureFeedback.wasAccepted && rejectedFutureFeedback.data.trainingFeedback.isEmpty && rejectedFutureFeedback.data.planChanges.isEmpty, "future training-card feedback must remain read-only and cannot create a recovery signal")
let rejectedHistoricalFeedback = TrainingFeedbackService.submit(painfulFeedback, at: fixedCalendar.date(byAdding: .day, value: 1, to: programStart)!, plan: dayOneScheduled!, data: PrivateCoachData(profile: profile), calendar: fixedCalendar)
verify(!rejectedHistoricalFeedback.wasAccepted && rejectedHistoricalFeedback.data.trainingFeedback.isEmpty && rejectedHistoricalFeedback.data.planChanges.isEmpty, "historical training-card feedback must remain read-only and cannot create a later recovery signal")
let sleepFeedback = TrainingFeedback(effort: 5, pain: 0, sleepHours: 5.5, completed: true)
let sleepFeedbackResult = TrainingFeedbackService.submit(sleepFeedback, at: programStart, plan: dayOneScheduled!, data: PrivateCoachData(profile: profile))
verify(sleepFeedbackResult.plan.trainingMode == .recovery && sleepFeedbackResult.automaticChange?.reason.contains("睡眠") == true, "training feedback with less than six hours sleep must select recovery with a sleep reason")
let easyFeedback = TrainingFeedback(effort: 3, pain: 0, sleepHours: 7, completed: true)
let easyAdaptation = TrainingFeedbackService.adapt(easyFeedback)
verify(easyAdaptation.action == .smallProgression && easyAdaptation.requiresConfirmation, "progression after easy effort must require confirmation")
let allShoppingPlans = (1...8).compactMap(ShoppingPlanCatalog.plan(forWeek:))
verify(allShoppingPlans.count == 8, "shopping catalog must provide a real shopping plan for every program week")
verify(allShoppingPlans.map(\.weekNumber) == Array(1...8), "shopping plans must map to all eight program weeks in order")
verify((1...8).compactMap(ShoppingPlanCatalog.plan(forWeek:)).allSatisfy { !$0.requiredItems.isEmpty }, "all-week shopping overview must have visible purchase items for every program week")
verify(allShoppingPlans.allSatisfy { $0.budgetCapYuan == ProgramFoodBudgetPolicy.weeklyReservationYuan }, "every shopping plan must use the same conservative ¥200 food reservation")
verify(allShoppingPlans.reduce(Decimal.zero) { $0 + $1.budgetCapYuan } == ProgramFoodBudgetPolicy.eightWeekReservationYuan, "all eight food reservations must remain within the explicit two-month planning ceiling")
verify(ProgramFoodBudgetPolicy.guidance(for: InitialShoppingPlans.weekOne).contains("¥1,500/月") && ProgramFoodBudgetPolicy.guidance(for: InitialShoppingPlans.weekOne).contains("不是实时价格"), "food-budget guidance must distinguish the two-month food reservation from the monthly total cap and real prices")
verify(allShoppingPlans.allSatisfy { $0.priceStatus.contains("待核验") }, "shopping plans must not invent real-time prices")
verify(allShoppingPlans.allSatisfy { $0.requiredItems.count >= 7 }, "every shopping week must have a usable required-item list")
verify(allShoppingPlans.flatMap(\.requiredItems).allSatisfy { !$0.quantity.isEmpty && !$0.prepNote.isEmpty }, "every required shopping item must state quantity and portion or storage guidance")
verify(!allShoppingPlans.flatMap(\.requiredItems).contains { $0.prepNote.contains("使用前清洗") || $0.prepNote.contains("早餐14个") }, "shopping plans must not overbuy eggs or tell the owner to wash shell eggs immediately before use")
verify(ShoppingPlanCatalog.plan(forWeek: 9) == nil && ShoppingPlanCatalog.plan(forWeek: 0) == nil, "shopping catalog must stop after the eight-week program instead of inventing a later plan")
verify(ShoppingPlanCatalog.nextPlan(after: InitialShoppingPlans.weekOne)?.weekNumber == 2, "next-week shopping preview must advance from week one to week two")
verify(ShoppingPlanCatalog.nextPlan(after: InitialShoppingPlans.weekEight) == nil, "next-week shopping preview must stop after the eighth week")
let shoppingCoverageAudit = ShoppingPlanCoverageAudit.validate()
if !shoppingCoverageAudit.isEmpty { print("SHOPPING COVERAGE AUDIT:\n" + shoppingCoverageAudit.joined(separator: "\n")) }
verify(shoppingCoverageAudit.isEmpty, "every weekly shopping list must cover breakfast essentials, meal categories, eggs, and each week’s key dinner proteins")
for weekNumber in 1...8 {
    let ingredientReference = WeeklyMealIngredientReference.days(forWeek: weekNumber)
    verify(ingredientReference.count == 7, "week \(weekNumber) shopping must expose seven days of gram-level breakfast and dinner references")
    verify(ingredientReference.allSatisfy { !$0.breakfast.ingredients.isEmpty && !$0.dinner.ingredients.isEmpty }, "week \(weekNumber) shopping reference must retain the actual meal-card ingredients")
}
verify(WeeklyMealIngredientReference.days(forWeek: 0).isEmpty && WeeklyMealIngredientReference.days(forWeek: 9).isEmpty, "shopping ingredient reference must stop after the eight-week program")
let firstShoppingItem = InitialShoppingPlans.weekOne.requiredItems[0]
verify(!firstShoppingItem.stableKey.isEmpty && firstShoppingItem.stableKey.contains(firstShoppingItem.name), "shopping completion must use a stable item key")
let firstShoppingPlan = InitialShoppingPlans.weekOne
let firstScopedShoppingKey = firstShoppingPlan.stableKey(for: firstShoppingItem)
let shoppingPersistenceData = PrivateCoachData(profile: profile, purchasedShoppingItemKeys: [firstScopedShoppingKey])
let shoppingPersistenceJSON = try JSONEncoder().encode(shoppingPersistenceData)
let reloadedShoppingPersistenceData = try JSONDecoder().decode(PrivateCoachData.self, from: shoppingPersistenceJSON)
verify(reloadedShoppingPersistenceData.purchasedShoppingItemKeys.contains(firstScopedShoppingKey), "user-confirmed shopping checkmarks must persist locally")
let weekOneEggs = InitialShoppingPlans.weekOne.requiredItems.first { $0.name == "鸡蛋" }!
let weekTwoEggs = InitialShoppingPlans.weekTwo.requiredItems.first { $0.name == "鸡蛋" }!
let weekOneScopedEggKey = InitialShoppingPlans.weekOne.stableKey(for: weekOneEggs)
verify(ShoppingPurchaseState.isMarkedPurchased(weekOneEggs, in: InitialShoppingPlans.weekOne, keys: [weekOneScopedEggKey]), "a scoped shopping mark must be visible in its own week")
verify(!ShoppingPurchaseState.isMarkedPurchased(weekTwoEggs, in: InitialShoppingPlans.weekTwo, keys: [weekOneScopedEggKey]), "a week-one purchase mark must never claim the same item is bought in week two")
verify(!ShoppingPurchaseState.isMarkedPurchased(weekOneEggs, in: InitialShoppingPlans.weekOne, keys: [weekOneEggs.stableKey]), "an unscoped legacy shopping mark must remain unconfirmed rather than claiming any week is purchased")
let migratedShoppingKeys = ShoppingPurchaseState.toggled(weekOneEggs, in: InitialShoppingPlans.weekOne, keys: [weekOneEggs.stableKey])
verify(migratedShoppingKeys.contains(weekOneScopedEggKey) && !migratedShoppingKeys.contains(weekOneEggs.stableKey), "explicitly reconfirming a legacy shopping item must replace it with a scoped key")
let unmarkedShoppingKeys = ShoppingPurchaseState.toggled(weekOneEggs, in: InitialShoppingPlans.weekOne, keys: migratedShoppingKeys)
verify(!unmarkedShoppingKeys.contains(weekOneScopedEggKey), "toggling a scoped shopping mark off must not affect another week")
var ledger = MonthlyBudgetLedger(monthKey: "2026-08")
let augustEighth = fixedCalendar.date(from: DateComponents(year: 2026, month: 8, day: 8))!
ledger.record(ExpenseEntry(date: augustEighth, category: .ingredients, amountYuan: 18.09, note: "用户手动记录的实际支出"))
verify(ledger.confirmedSpentYuan == 18.09 && ledger.remainingYuan == 1481.91, "budget ledger must use user-confirmed actual spending")
verify(BudgetPolicy.warning(for: ledger) == nil, "normal remaining budget must not warn")
let negativeImportedExpenseJSON = """
{
  "id": "\(UUID().uuidString)",
  "date": \(augustEighth.timeIntervalSinceReferenceDate),
  "category": "食材",
  "amountYuan": -99,
  "note": "损坏导入的负支出",
  "isUserConfirmed": true
}
""".data(using: .utf8)!
let negativeImportedExpense = try JSONDecoder().decode(ExpenseEntry.self, from: negativeImportedExpenseJSON)
let ledgerWithMalformedNegativeImport = MonthlyBudgetLedger(monthKey: "2026-08", entries: [ledger.entries[0], negativeImportedExpense])
verify(
    ledgerWithMalformedNegativeImport.confirmedSpentYuan == 18.09 && ledgerWithMalformedNegativeImport.remainingYuan == 1481.91,
    "a malformed imported negative expense must not inflate remaining budget"
)
let duplicateImportedExpenseLedger = MonthlyBudgetLedger(
    monthKey: "2026-08",
    entries: [ledger.entries[0], ledger.entries[0]]
)
verify(
    duplicateImportedExpenseLedger.entries.count == 1
        && duplicateImportedExpenseLedger.confirmedSpentYuan == 18.09,
    "a duplicated receipt in restored monthly data must not be counted twice"
)
let nonFiniteExpense = ExpenseEntry(date: augustEighth, category: .ingredients, amountYuan: .nan, note: "损坏导入的非有限支出")
verify(
    nonFiniteExpense.amountYuan == 0
        && MonthlyBudgetLedger(monthKey: "2026-08", entries: [ledger.entries[0], nonFiniteExpense]).remainingYuan == 1481.91,
    "a non-finite imported expense must not contaminate the local budget display"
)
let malformedBudgetCapJSON = """
{
  "monthKey": "2026-08",
  "capYuan": -1,
  "entries": []
}
""".data(using: .utf8)!
let malformedBudgetCapLedger = try JSONDecoder().decode(MonthlyBudgetLedger.self, from: malformedBudgetCapJSON)
verify(
    malformedBudgetCapLedger.capYuan == 0 && malformedBudgetCapLedger.remainingYuan == 0,
    "a malformed imported negative monthly cap must not create fictitious remaining budget"
)
var duplicateSafeLedger = ledger
let duplicateExpense = ExpenseEntry(date: augustEighth, category: .ingredients, amountYuan: 10, note: "重复回调测试")
duplicateSafeLedger.record(duplicateExpense)
duplicateSafeLedger.record(duplicateExpense)
verify(duplicateSafeLedger.entries.filter { $0.id == duplicateExpense.id }.count == 1, "the same expense receipt must not be counted twice after a repeated callback")
let futureExpenseDate = fixedCalendar.date(from: DateComponents(year: 2026, month: 8, day: 30))!
duplicateSafeLedger.record(ExpenseEntry(date: futureExpenseDate, category: .buffer, amountYuan: 20, note: "错误导入的未来支出"))
let sameDayLateExpense = ExpenseEntry(
    date: fixedCalendar.date(byAdding: .hour, value: 21, to: augustEighth)!,
    category: .ingredients,
    amountYuan: 12,
    note: "当天晚间实际支出"
)
duplicateSafeLedger.record(sameDayLateExpense)
verify(
    duplicateSafeLedger.snapshot(asOf: augustEighth, calendar: fixedCalendar).confirmedSpentYuan == Decimal(string: "40.09")!,
    "today's budget snapshot must include all confirmed spending later on the same calendar day"
)
verify(
    duplicateSafeLedger.snapshot(asOf: augustEighth, calendar: fixedCalendar).entries.contains { $0.id == sameDayLateExpense.id }
        && !duplicateSafeLedger.snapshot(asOf: augustEighth, calendar: fixedCalendar).entries.contains { $0.date == futureExpenseDate },
    "today's budget snapshot must include same-day spending but exclude future-dated spending"
)
verify(BudgetPolicy.weeklyShoppingGuidance(plan: InitialShoppingPlans.weekOne, confirmedIngredientSpent: 0).contains("不等于实时价格") && BudgetPolicy.weeklyShoppingGuidance(plan: InitialShoppingPlans.weekOne, confirmedIngredientSpent: 0).contains("¥0"), "weekly shopping cap must remain an unspent, non-real-time-price reservation")
let firstProgramWeek = PlanSchedule.programWeekInterval(for: programStart, calendar: fixedCalendar)!
let secondProgramWeekDate = fixedCalendar.date(byAdding: .day, value: 7, to: programStart)!
let secondProgramWeek = PlanSchedule.programWeekInterval(for: secondProgramWeekDate, calendar: fixedCalendar)!
var multiWeekIngredientLedger = MonthlyBudgetLedger(monthKey: "2026-08")
multiWeekIngredientLedger.record(ExpenseEntry(date: programStart, category: .ingredients, amountYuan: 220, note: "第 1 周用户确认食材支出"))
multiWeekIngredientLedger.record(ExpenseEntry(date: secondProgramWeekDate, category: .ingredients, amountYuan: 20, note: "第 2 周用户确认食材支出"))
verify(multiWeekIngredientLedger.confirmedSpentYuan(in: .ingredients, during: firstProgramWeek) == 220, "weekly shopping guidance must isolate first-week receipts from later weeks")
verify(multiWeekIngredientLedger.confirmedSpentYuan(in: .ingredients, during: secondProgramWeek) == 20, "weekly shopping guidance must not treat month-to-date groceries as the current-week spend")
let fourthProgramWeekDate = fixedCalendar.date(byAdding: .day, value: 21, to: programStart)!
let fourthProgramWeek = PlanSchedule.programWeekInterval(for: fourthProgramWeekDate, calendar: fixedCalendar)!
let septemberFirst = fixedCalendar.date(from: DateComponents(year: 2026, month: 9, day: 1))!
var crossMonthWeekData = PrivateCoachData(profile: profile)
crossMonthWeekData.recordExpense(ExpenseEntry(date: fourthProgramWeekDate, category: .ingredients, amountYuan: 120, note: "第 4 周八月食材"), calendar: fixedCalendar)
crossMonthWeekData.recordExpense(ExpenseEntry(date: septemberFirst, category: .ingredients, amountYuan: 80, note: "第 4 周九月食材"), calendar: fixedCalendar)
verify(
    crossMonthWeekData.confirmedSpentYuan(in: .ingredients, during: fourthProgramWeek, asOf: septemberFirst, calendar: fixedCalendar) == 200,
    "a shopping week crossing months must include confirmed receipts from both monthly ledgers"
)
let duplicateAugustLedger = MonthlyBudgetLedger(
    monthKey: "2026-08",
    entries: [ExpenseEntry(date: fourthProgramWeekDate, category: .ingredients, amountYuan: 999, note: "损坏导入的重复八月账本")]
)
let duplicateMonthImport = PrivateCoachData(
    profile: profile,
    monthlyBudgetLedgers: [
        crossMonthWeekData.ledger(for: fourthProgramWeekDate, calendar: fixedCalendar),
        duplicateAugustLedger,
        crossMonthWeekData.ledger(for: septemberFirst, calendar: fixedCalendar)
    ]
)
verify(
    duplicateMonthImport.confirmedSpentYuan(in: .ingredients, during: fourthProgramWeek, asOf: septemberFirst, calendar: fixedCalendar) == 200,
    "duplicate imported month ledgers must not double-count a weekly shopping reservation"
)
let duplicatedReceiptID = UUID()
let duplicateReceiptAugust = ExpenseEntry(id: duplicatedReceiptID, date: fourthProgramWeekDate, category: .ingredients, amountYuan: 70, note: "错误重复导入的跨月收据")
let duplicateReceiptSeptember = ExpenseEntry(id: duplicatedReceiptID, date: septemberFirst, category: .ingredients, amountYuan: 70, note: "错误重复导入的跨月收据")
let duplicateReceiptAcrossMonths = PrivateCoachData(
    profile: profile,
    monthlyBudgetLedgers: [
        MonthlyBudgetLedger(monthKey: "2026-08", entries: [duplicateReceiptAugust]),
        MonthlyBudgetLedger(monthKey: "2026-09", entries: [duplicateReceiptSeptember])
    ]
)
verify(
    duplicateReceiptAcrossMonths.confirmedSpentYuan(in: .ingredients, during: fourthProgramWeek, asOf: septemberFirst, calendar: fixedCalendar) == 70,
    "a duplicated receipt id across imported month ledgers must count only once in a cross-month shopping week"
)
var overWeeklyReservationLedger = MonthlyBudgetLedger(monthKey: "2026-08")
overWeeklyReservationLedger.record(ExpenseEntry(category: .ingredients, amountYuan: 230, note: "用户确认食材支出"))
verify(BudgetPolicy.weeklyShoppingGuidance(plan: InitialShoppingPlans.weekOne, confirmedIngredientSpent: overWeeklyReservationLedger.confirmedSpentYuan(in: .ingredients)).contains("高于本周预留"), "weekly shopping guidance must flag only user-confirmed ingredient spending above the reservation")
let persistedBudgetData = PrivateCoachData(profile: profile, budgetLedger: ledger)
verify(persistedBudgetData.budgetLedger.confirmedSpentYuan == 18.09, "private profile data must include budget ledger for persistence/export")
var crossMonthBudgetData = PrivateCoachData(profile: profile, budgetLedger: ledger)
let septemberDate = fixedCalendar.date(from: DateComponents(year: 2026, month: 9, day: 2))!
crossMonthBudgetData.recordExpense(ExpenseEntry(date: septemberDate, category: .swimming, amountYuan: 30, note: "用户确认单次游泳"), calendar: fixedCalendar)
verify(crossMonthBudgetData.ledger(for: programStart, calendar: fixedCalendar).confirmedSpentYuan == 18.09, "August budget must not absorb a September expense")
verify(crossMonthBudgetData.ledger(for: septemberDate, calendar: fixedCalendar).confirmedSpentYuan == 30, "expense must be recorded in its actual calendar month")
verify(crossMonthBudgetData.monthlyBudgetLedgers.count == 2, "a 56-day program crossing months must keep separate monthly budget ledgers")
let wronglyBucketedSeptemberExpense = ExpenseEntry(date: septemberDate, category: .cycling, amountYuan: 12, note: "错误导入到八月账本")
let malformedMonthData = PrivateCoachData(profile: profile, budgetLedger: MonthlyBudgetLedger(monthKey: "2026-08", entries: [wronglyBucketedSeptemberExpense]))
verify(malformedMonthData.ledger(for: programStart, calendar: fixedCalendar).entries.isEmpty, "an imported entry from another month must not appear in this month's budget")
let legacyBudgetData = try JSONEncoder().encode(PrivateCoachData(profile: profile, budgetLedger: ledger))
var legacyBudgetObject = try JSONSerialization.jsonObject(with: legacyBudgetData) as! [String: Any]
legacyBudgetObject.removeValue(forKey: "monthlyBudgetLedgers")
let migratedBudgetData = try JSONDecoder().decode(PrivateCoachData.self, from: JSONSerialization.data(withJSONObject: legacyBudgetObject))
verify(migratedBudgetData.monthlyBudgetLedgers == [ledger], "older private JSON with one budget ledger must migrate into the monthly-ledger list")
verify(
    ExpenseSubmissionPolicy.validationError(
        amountYuan: 18.5,
        note: "鸡蛋",
        formOwnerID: profile.id,
        currentOwnerID: profile.id
    ) == nil,
    "a positive confirmed expense owned by the active profile must be accepted"
)
verify(
    ExpenseSubmissionPolicy.validationError(
        amountYuan: 0,
        note: "空记录",
        formOwnerID: profile.id,
        currentOwnerID: profile.id
    )?.contains("大于 0") == true,
    "a zero-value manual expense must not create a misleading ledger entry"
)
verify(
    ExpenseSubmissionPolicy.validationError(
        amountYuan: 18.5,
        note: "鸡蛋",
        formOwnerID: UUID(),
        currentOwnerID: profile.id
    )?.contains("新账本") == true,
    "an expense sheet opened by another or deleted local owner must fail closed"
)
let legacyWorkoutDraftData = try JSONEncoder().encode(PrivateCoachData(profile: profile))
var legacyWorkoutDraftObject = try JSONSerialization.jsonObject(with: legacyWorkoutDraftData) as! [String: Any]
legacyWorkoutDraftObject.removeValue(forKey: "pendingWorkoutConfirmations")
let migratedWorkoutDraftData = try JSONDecoder().decode(PrivateCoachData.self, from: JSONSerialization.data(withJSONObject: legacyWorkoutDraftObject))
verify(
    migratedWorkoutDraftData.pendingWorkoutConfirmations.isEmpty,
    "older private JSON without local workout-confirmation drafts must decode as an empty draft list"
)
let legacyActualMealData = try JSONEncoder().encode(PrivateCoachData(profile: profile))
var legacyActualMealObject = try JSONSerialization.jsonObject(with: legacyActualMealData) as! [String: Any]
legacyActualMealObject.removeValue(forKey: "actualMealLogs")
let migratedActualMealData = try JSONDecoder().decode(PrivateCoachData.self, from: JSONSerialization.data(withJSONObject: legacyActualMealObject))
verify(migratedActualMealData.actualMealLogs.isEmpty, "older private JSON without actual-meal logs must decode without losing the profile")
let blankActualMeal = ActualMealLog(date: programStart, slot: .breakfast, relationship: .different, description: "   ")
if case let .failure(error) = ActualMealLogService.recording(blankActualMeal, in: migratedActualMealData) {
    verify(error.message.contains("实际吃了什么"), "a blank actual-meal description must be rejected with a clear prompt")
} else {
    verify(false, "a blank actual-meal description must never be stored")
}
let mealOwnerID = profile.id
verify(
    ActualMealSubmissionPolicy.validationError(
        for: programStart,
        formOwnerID: mealOwnerID,
        currentOwnerID: mealOwnerID,
        at: programStart,
        calendar: fixedCalendar
    ) == nil,
    "a current-day meal form owned by the active local profile must be accepted"
)
verify(
    ActualMealSubmissionPolicy.validationError(
        for: programStart,
        formOwnerID: UUID(),
        currentOwnerID: mealOwnerID,
        at: programStart,
        calendar: fixedCalendar
    )?.contains("资料已删除或切换") == true,
    "a meal form opened by another or deleted local owner must fail closed"
)
verify(
    ActualMealSubmissionPolicy.validationError(
        for: programStart,
        formOwnerID: mealOwnerID,
        currentOwnerID: mealOwnerID,
        at: fixedCalendar.date(byAdding: .day, value: 1, to: programStart)!,
        calendar: fixedCalendar
    )?.contains("日期已切换") == true,
    "an actual-meal form left open across midnight must fail again at the write boundary"
)
let firstActualMeal = ActualMealLog(date: programStart, slot: .lunch, relationship: .asPlanned, description: "按计划吃了", estimatedCaloriesRange: 480...620)
verify(firstActualMeal.historyEstimateLabel == "计划食材估算" && firstActualMeal.energyText == "计划食材估算 · 480–620 kcal", "a planned-meal history row must retain its ingredient-estimate source and full range")
guard case let .success(firstActualMealData) = ActualMealLogService.recording(firstActualMeal, in: migratedActualMealData) else {
    verify(false, "a valid actual-meal record must save")
    return
}
let actualMealPhotoReference = "local-photo://00000000-0000-0000-0000-000000000111/00000000-0000-0000-0000-000000000112"
let replacementActualMeal = ActualMealLog(date: programStart, slot: .lunch, relationship: .planExternal, description: "鸡肉饭和青菜", portionNote: "约 1 碗", localPhotoReference: actualMealPhotoReference, estimatedCaloriesRange: 520...680)
verify(replacementActualMeal.historyEstimateLabel == "本机照片参考 · 宽范围" && replacementActualMeal.energyText == "本机照片参考 · 宽范围 · 520–680 kcal", "an actual-meal photo reference must stay a broad local estimate in history")
let removedPhotoActualMeal = ActualMealLog(date: programStart, slot: .dinner, relationship: .different, description: "旧照片晚餐", portionNote: "照片候选保守区间", estimatedCaloriesRange: 500...900)
verify(removedPhotoActualMeal.localPhotoReference == nil && removedPhotoActualMeal.historyEstimateLabel == "本机照片候选 · 宽范围", "removing a private actual-meal photo must retain its conservative photo-candidate source in history")
let explicitlyRemovedPhotoActualMeal = ActualMealLog(
    date: programStart,
    slot: .dinner,
    relationship: .different,
    description: "已移除照片的晚餐",
    portionNote: "照片候选保守区间｜照片已移除，保留候选范围",
    estimatedCaloriesRange: 500...900
)
verify(
    explicitlyRemovedPhotoActualMeal.localPhotoReference == nil
        && explicitlyRemovedPhotoActualMeal.historyEstimateLabel == "本机照片候选（照片已移除） · 宽范围"
        && explicitlyRemovedPhotoActualMeal.energyText?.contains("500–900 kcal") == true,
    "an explicit photo removal must retain the prior conservative range while making the absent image visible in history"
)
guard case let .success(replacedActualMealData) = ActualMealLogService.recording(replacementActualMeal, in: firstActualMealData) else {
    verify(false, "replacing an actual-meal record must save")
    return
}
verify(replacedActualMealData.actualMealLogs.count == 1 && replacedActualMealData.actualMealLogs.first?.description == "鸡肉饭和青菜", "one date and meal slot must keep only the latest actual-meal record")
verify(replacedActualMealData.actualMealLogs.first?.relationship == .planExternal && replacedActualMealData.actualMealLogs.first?.estimatedCaloriesRange == 520...680 && replacedActualMealData.actualMealLogs.first?.localPhotoReference == actualMealPhotoReference, "a meal-slot record must preserve its owner-selected plan relationship, calorie range, and private photo reference")
let olderActualMealPhotoReference = "local-photo://00000000-0000-0000-0000-000000000111/00000000-0000-0000-0000-000000000113"
let newerActualMealPhotoReference = "local-photo://00000000-0000-0000-0000-000000000111/00000000-0000-0000-0000-000000000114"
let olderPhotoMeal = ActualMealLog(date: programStart, slot: .dinner, relationship: .different, description: "旧照片晚餐", localPhotoReference: olderActualMealPhotoReference, estimatedCaloriesRange: 500...700)
let newerPhotoMeal = ActualMealLog(date: programStart, slot: .dinner, relationship: .different, description: "新照片晚餐", localPhotoReference: newerActualMealPhotoReference, estimatedCaloriesRange: 500...700)
guard case let .success(newerPhotoMealData) = ActualMealLogService.recording(newerPhotoMeal, in: PrivateCoachData(profile: profile, actualMealLogs: [olderPhotoMeal])) else {
    verify(false, "replacing an actual-meal photo must prepare valid updated data")
    return
}
verify(ActualMealLogService.photoReferenceToDeleteAfterReplacement(previousReference: olderActualMealPhotoReference, replacementReference: newerActualMealPhotoReference, updatedData: newerPhotoMealData) == olderActualMealPhotoReference, "a durably replaced actual-meal photo must expose its now-unreferenced old private image for cleanup")
var crossReferencedNewerPhotoMealData = newerPhotoMealData
crossReferencedNewerPhotoMealData.unplannedMealLogs = [UnplannedMealLog(date: programStart, localPhotoReference: olderActualMealPhotoReference, userDescription: "其他记录仍在使用旧照片")]
verify(ActualMealLogService.photoReferenceToDeleteAfterReplacement(previousReference: olderActualMealPhotoReference, replacementReference: newerActualMealPhotoReference, updatedData: crossReferencedNewerPhotoMealData) == nil, "an actual-meal photo replacement must retain an old image still referenced by another private record type")
let removedOlderPhotoMealData = ActualMealLogService.removing(date: programStart, slot: .dinner, from: PrivateCoachData(profile: profile, actualMealLogs: [olderPhotoMeal]), calendar: fixedCalendar)
verify(ActualMealLogService.photoReferenceToDeleteAfterReplacement(previousReference: olderActualMealPhotoReference, replacementReference: nil, updatedData: removedOlderPhotoMealData) == olderActualMealPhotoReference, "removing an actual-meal record must expose only its now-unreferenced App-private photo for post-persistence cleanup")
let portableActualMealData = PrivateExport.portableCopy(of: replacedActualMealData)
verify(portableActualMealData.actualMealLogs.first?.localPhotoReference == nil && replacedActualMealData.actualMealLogs.first?.localPhotoReference != nil, "owner export must strip an actual-meal private photo reference without mutating on-device data")
let rejectedExternalActualMealPhoto = ActualMealLog(date: programStart, slot: .dinner, relationship: .different, description: "外部路径", localPhotoReference: "file:///Users/example/photo.jpg", estimatedCaloriesRange: 300...500)
verify(rejectedExternalActualMealPhoto.localPhotoReference == nil, "actual meal logs must reject filesystem and non-private photo references")
let encodedActualMeal = try JSONEncoder().encode(replacementActualMeal)
var legacyActualMealEntryObject = try JSONSerialization.jsonObject(with: encodedActualMeal) as! [String: Any]
legacyActualMealEntryObject.removeValue(forKey: "estimatedCaloriesRange")
let migratedActualMealEntry = try JSONDecoder().decode(ActualMealLog.self, from: JSONSerialization.data(withJSONObject: legacyActualMealEntryObject))
verify(migratedActualMealEntry.estimatedCaloriesRange == nil && migratedActualMealEntry.description == replacementActualMeal.description, "older meal entries without calories must remain readable without fabricating a historical estimate")

var calorieSummaryProfile = profile
calorieSummaryProfile.dailyCalorieFramework = DailyCalorieFramework(lowerBound: 1_500, upperBound: 1_700)
let emptyCalorieSummary = DailyCalorieIntakeSummary.make(for: programStart, data: PrivateCoachData(profile: calorieSummaryProfile), calendar: fixedCalendar)
verify(emptyCalorieSummary.recordedRange == nil && emptyCalorieSummary.remainingRange == 1_500...1_700 && emptyCalorieSummary.remainingEstimate == 1_600 && emptyCalorieSummary.progressRange == 0...0, "before the first meal, today's calorie card must show the full confirmed allowance rather than hiding it behind an empty diary")
let breakfastEnergy = ActualMealLog(date: programStart, slot: .breakfast, relationship: .asPlanned, description: "早餐", estimatedCaloriesRange: 300...400)
let lunchEnergy = ActualMealLog(date: programStart, slot: .lunch, relationship: .different, description: "午餐", estimatedCaloriesRange: 500...600)
let snackEnergy = UnplannedMealLog(date: programStart, userDescription: "加餐", estimatedCaloriesRange: 200...300, confidence: .medium)
let calorieSummaryData = PrivateCoachData(profile: calorieSummaryProfile, unplannedMealLogs: [snackEnergy], actualMealLogs: [breakfastEnergy, lunchEnergy])
let calorieSummary = DailyCalorieIntakeSummary.make(for: programStart, data: calorieSummaryData, calendar: fixedCalendar)
verify(calorieSummary.recordedRange == 1_000...1_300 && calorieSummary.remainingRange == 200...700, "daily calorie tracking must sum meal ranges and show an uncertainty-aware remaining range")
verify(calorieSummary.recordedEntries.map(\.label) == ["早餐 · 早餐", "午餐 · 午餐", "加餐 · 加餐"] && calorieSummary.recordedEntries.map(\.estimatedRange) == [300...400, 500...600, 200...300], "daily calorie totals must retain an owner-readable source row for every included meal")
verify(calorieSummary.threshold == .within && calorieSummary.progressRange == (Double(1_000) / 1_700)...(Double(1_300) / 1_700), "daily intake must expose a bounded progress range against the confirmed upper allowance")
verify(calorieSummary.entriesMissingCalories == 0, "fully ranged meal records must not be reported as incomplete")
verify(calorieSummary.recordedSignal == .notAboveReference && calorieSummary.recordedSignal?.nextMealGuidance.contains("不需要") == true, "a recorded range below the confirmed upper reference must keep the next meal normal rather than prescribing restriction")
let possiblyAboveMeal = ActualMealLog(date: programStart, slot: .dinner, relationship: .different, description: "宽区间晚餐", estimatedCaloriesRange: 500...900)
let possiblyAboveSummary = DailyCalorieIntakeSummary.make(for: programStart, data: PrivateCoachData(profile: calorieSummaryProfile, unplannedMealLogs: [snackEnergy], actualMealLogs: [breakfastEnergy, lunchEnergy, possiblyAboveMeal]), calendar: fixedCalendar)
verify(possiblyAboveSummary.recordedRange == 1_500...2_200 && possiblyAboveSummary.recordedSignal == .mayExceedReference && possiblyAboveSummary.recordedSignal?.nextMealGuidance.contains("不跳餐、不补练") == true, "an uncertainty range crossing the reference ceiling must say it may exceed and must not prescribe compensation")
verify(possiblyAboveSummary.threshold == .mayReach, "a recorded range crossing the allowance must use a cautious may-reach threshold")
let clearlyAboveMeal = ActualMealLog(date: programStart, slot: .dinner, relationship: .different, description: "已记录大餐", estimatedCaloriesRange: 900...1_000)
let clearlyAboveSummary = DailyCalorieIntakeSummary.make(for: programStart, data: PrivateCoachData(profile: calorieSummaryProfile, unplannedMealLogs: [snackEnergy], actualMealLogs: [breakfastEnergy, lunchEnergy, clearlyAboveMeal]), calendar: fixedCalendar)
verify(clearlyAboveSummary.recordedRange == 1_900...2_300 && clearlyAboveSummary.remainingRange == 0...0 && clearlyAboveSummary.recordedSignal == .exceedsReference && clearlyAboveSummary.recordedSignal?.nextMealGuidance.contains("明天正常继续") == true, "a recorded range wholly above the reference ceiling must be explicit while keeping the next meal and following day non-punitive")
verify(clearlyAboveSummary.threshold == .reached, "a recorded range whose lower bound reaches the allowance must show a reached threshold")
let incompleteCalorieSummary = DailyCalorieIntakeSummary.make(for: programStart, data: PrivateCoachData(profile: calorieSummaryProfile, actualMealLogs: [migratedActualMealEntry]), calendar: fixedCalendar)
verify(incompleteCalorieSummary.remainingRange == nil && incompleteCalorieSummary.recordedSignal == nil && incompleteCalorieSummary.entriesMissingCalories == 1, "missing legacy meal calories must suppress a misleading remaining allowance or exceed signal")
verify(incompleteCalorieSummary.recordedEntries.count == 1 && incompleteCalorieSummary.recordedEntries[0].estimatedRange == nil, "a diary item without calories must remain visible in the calorie card source list")
let plannedDinnerEnergy = PlannedMealEnergyReference.estimatedRange(for: RecipeCatalog.all56[0])
verify(plannedDinnerEnergy.lowerBound >= 180 && plannedDinnerEnergy.upperBound <= 1_500, "ingredient-derived planned-meal energy must remain within a plausible per-serving reference range")
let calorieRecommendation = CaloriePlanAdvisor.recommendation(weightKg: 60, heightCm: 165, ageYears: 30, formulaSex: .female, activityLevel: .lightlyActive)
verify(calorieRecommendation?.framework == DailyCalorieFramework(lowerBound: 1450, upperBound: 1550), "calorie planning must use a reproducible explainable maintenance estimate and moderate deficit")
verify(calorieRecommendation?.explanation.contains("Mifflin") == true && calorieRecommendation?.deficitPercentRange == 12...18, "calorie planning must disclose the formula and moderate deficit range")
verify(CaloriePlanAdvisor.recommendation(weightKg: 60, heightCm: nil, ageYears: 30, formulaSex: .female, activityLevel: .lightlyActive) == nil, "calorie planning must not fabricate a target from incomplete inputs")
verify(CaloriePlanAdvisor.confirmationError(for: DailyCalorieFramework(lowerBound: 900, upperBound: 1100)!)?.contains("1200") == true, "the confirmation boundary must block crash-diet calorie numbers")

let reviewWeek = fixedCalendar.date(from: DateComponents(year: 2026, month: 8, day: 10))!
// Use explicit historical timestamps rather than `.now`: this rule check is evaluated against a
// fixed simulated week, and a real clock date must not make a valid past check-in look like a
// future import as calendar time advances.
let reviewCheckIn = WeeklyBodyCheckIn(weekStart: reviewWeek, recordedAt: reviewWeek, weightKg: 54.2, waistCm: 68.0, note: "第一周起点")
let previousReviewCheckIn = WeeklyBodyCheckIn(weekStart: fixedCalendar.date(byAdding: .day, value: -7, to: reviewWeek)!, recordedAt: fixedCalendar.date(byAdding: .day, value: -7, to: reviewWeek)!, weightKg: 54.8, waistCm: 69.0)
let reviewCompletions = [
    DailyCompletion(date: reviewWeek, foodCompleted: true, trainingOrRecoveryCompleted: true, bedtimePreparationCompleted: true),
    DailyCompletion(date: fixedCalendar.date(byAdding: .day, value: 1, to: reviewWeek)!, foodCompleted: true, trainingOrRecoveryCompleted: false, bedtimePreparationCompleted: false)
]
let reviewStatuses = [
    DatedHealthStatus(date: reviewWeek, status: HealthStatus(sleepHours: 7.5, skinConcerns: [.dryness])),
    DatedHealthStatus(date: fixedCalendar.date(byAdding: .day, value: 1, to: reviewWeek)!, status: HealthStatus(sleepHours: 7.0, skinConcerns: [.redness]))
]
let reviewData = PrivateCoachData(profile: profile, dailyCompletions: reviewCompletions, datedHealthStatusNotes: reviewStatuses, weeklyBodyCheckIns: [previousReviewCheckIn, reviewCheckIn])
let reviewAsOf = fixedCalendar.date(byAdding: .day, value: 1, to: reviewWeek)!
let reviewSummary = WeeklyReviewService.summary(for: reviewWeek, data: reviewData, asOf: reviewAsOf, calendar: fixedCalendar)
verify(reviewSummary.completionRate > 0 && reviewSummary.completionRate <= 1, "weekly review must calculate a bounded three-action completion rate for its own week")
let legacyMealOnlyLog = ActualMealLog(date: reviewWeek, slot: .breakfast, relationship: .different, description: "旧版已记录早餐", estimatedCaloriesRange: 300...450)
let legacyMealOnlyData = PrivateCoachData(profile: profile, actualMealLogs: [legacyMealOnlyLog])
let reconciledMealOnlyCompletion = legacyMealOnlyData.executionCompletion(for: reviewWeek, calendar: fixedCalendar)
verify(reconciledMealOnlyCompletion?.breakfastCompleted == true && reconciledMealOnlyCompletion?.completedMealCount == 1 && reconciledMealOnlyCompletion?.foodCompleted == false && reconciledMealOnlyCompletion?.trainingOrRecoveryCompleted == false, "an older actual-meal record without a daily snapshot must reappear as meal evidence without inventing a completed food, training, or bedtime pillar")
verify(CalendarDayStatus.resolve(for: reviewWeek, data: legacyMealOnlyData, asOf: reviewAsOf, calendar: fixedCalendar) == .partiallyCompleted, "a past plan day with an actual meal record must not remain labelled unrecorded merely because an older build omitted its completion snapshot")
let legacyMealOnlyReview = WeeklyReviewService.summary(for: reviewWeek, data: legacyMealOnlyData, asOf: reviewAsOf, calendar: fixedCalendar)
verify(legacyMealOnlyReview.recordedMealEntries == 1 && legacyMealOnlyReview.executionDays.first?.recordedMeals == 1 && legacyMealOnlyReview.executionDays.first?.status == .partiallyCompleted, "weekly review must surface actual meal evidence separately from the three-pillar completion score")
let explicitIncompleteMealData = PrivateCoachData(
    profile: profile,
    dailyCompletions: [DailyCompletion(date: reviewWeek, foodCompleted: false, breakfastCompleted: false, lunchCompleted: false, dinnerCompleted: false, trainingOrRecoveryCompleted: false, bedtimePreparationCompleted: false)],
    actualMealLogs: [legacyMealOnlyLog]
)
verify(explicitIncompleteMealData.executionCompletion(for: reviewWeek, calendar: fixedCalendar)?.breakfastCompleted == false, "a real daily snapshot must win over inferred legacy meal evidence so a later owner cancellation is never overwritten")
let allLegacyMealSlotsData = PrivateCoachData(
    profile: profile,
    actualMealLogs: [
        legacyMealOnlyLog,
        ActualMealLog(date: reviewWeek, slot: .lunch, relationship: .different, description: "旧版已记录午餐", estimatedCaloriesRange: 450...650),
        ActualMealLog(date: reviewWeek, slot: .dinner, relationship: .different, description: "旧版已记录晚餐", estimatedCaloriesRange: 450...700)
    ]
)
verify(allLegacyMealSlotsData.executionCompletion(for: reviewWeek, calendar: fixedCalendar)?.foodCompleted == true, "three actual meal records from an older build may restore only the food pillar, never the other daily actions")
let legacyCompletedTrainingFeedback = TrainingFeedback(date: reviewWeek, effort: 5, pain: 0, completed: true)
let legacyCompletedTrainingData = PrivateCoachData(profile: profile, trainingFeedback: [legacyCompletedTrainingFeedback])
let reconciledTrainingCompletion = legacyCompletedTrainingData.executionCompletion(for: reviewWeek, calendar: fixedCalendar)
verify(reconciledTrainingCompletion?.trainingOrRecoveryCompleted == true && reconciledTrainingCompletion?.foodCompleted == false && reconciledTrainingCompletion?.bedtimePreparationCompleted == false, "an older explicit completed-training feedback may restore only the movement pillar")
verify(CalendarDayStatus.resolve(for: reviewWeek, data: legacyCompletedTrainingData, asOf: reviewAsOf, calendar: fixedCalendar) == .partiallyCompleted, "a past plan day with explicit completed training feedback must not remain labelled unrecorded")
let legacyCompletedTrainingReview = WeeklyReviewService.summary(for: reviewWeek, data: legacyCompletedTrainingData, asOf: reviewAsOf, calendar: fixedCalendar)
verify(legacyCompletedTrainingReview.completedTrainingFeedbackDays == 1 && legacyCompletedTrainingReview.completionRate > 0, "weekly review must count a legacy explicit completed-training feedback while naming its evidence separately")
let nonCompletionTrainingData = PrivateCoachData(profile: profile, trainingFeedback: [TrainingFeedback(date: reviewWeek, effort: 7, pain: 2, completed: false)])
verify(nonCompletionTrainingData.executionCompletion(for: reviewWeek, calendar: fixedCalendar) == nil, "pain, early-stop, or reflection feedback without explicit completion must never become a completed workout")
let timerDraftOnlyData = PrivateCoachData(
    profile: profile,
    pendingWorkoutConfirmations: [PendingWorkoutConfirmation(
        workout: ConfirmedHealthWorkout(dayIndex: 1, startedAt: reviewWeek, endedAt: reviewWeek.addingTimeInterval(600), kind: .coreTraining),
        savedAt: reviewWeek
    )]
)
verify(timerDraftOnlyData.executionCompletion(for: reviewWeek, calendar: fixedCalendar) == nil, "a local elapsed-time draft alone must never be treated as completed training")
let explicitCancelledTrainingData = PrivateCoachData(
    profile: profile,
    dailyCompletions: [DailyCompletion(date: reviewWeek, foodCompleted: false, trainingOrRecoveryCompleted: false, bedtimePreparationCompleted: false)],
    trainingFeedback: [legacyCompletedTrainingFeedback]
)
verify(explicitCancelledTrainingData.executionCompletion(for: reviewWeek, calendar: fixedCalendar)?.trainingOrRecoveryCompleted == false, "a later explicit daily snapshot must win over inferred legacy training evidence")
let morningHealthUpdate = DatedHealthStatus(
    date: reviewWeek.addingTimeInterval(8 * 60 * 60),
    status: HealthStatus(sleepHours: 5, painOrInjury: true, skinConcerns: [.dryness])
)
let eveningHealthUpdate = DatedHealthStatus(
    date: reviewWeek.addingTimeInterval(20 * 60 * 60),
    status: HealthStatus(sleepHours: 8, energy: 4, skinConcerns: [.redness])
)
let sameDayHealthAggregates = HealthStatusHistoryAggregation.dailyAggregates(from: [morningHealthUpdate, eveningHealthUpdate], calendar: fixedCalendar)
verify(sameDayHealthAggregates.count == 1 && sameDayHealthAggregates[0].status.sleepHours == 8 && sameDayHealthAggregates[0].status.energy == 4, "multiple same-day health updates must use the latest valid scalar values rather than count one night repeatedly")
verify(sameDayHealthAggregates[0].status.skinConcerns.count == 2 && sameDayHealthAggregates[0].status.skinConcerns.contains(.dryness) && sameDayHealthAggregates[0].status.skinConcerns.contains(.redness) && sameDayHealthAggregates[0].status.painOrInjury && sameDayHealthAggregates[0].hasProtectiveSignal, "same-day aggregation must retain skin and protective risk unions even after a later ordinary update")
let sameDayHealthData = PrivateCoachData(profile: profile, datedHealthStatusNotes: [morningHealthUpdate, eveningHealthUpdate])
let sameDayHealthSummary = HealthCheckInService.summary(for: reviewWeek, in: sameDayHealthData, calendar: fixedCalendar)
verify(sameDayHealthSummary?.labels.contains("睡眠 8.0 小时") == true && sameDayHealthSummary?.labels.contains("睡眠 5.0 小时") == false && sameDayHealthSummary?.hasProtectiveSignal == true, "today's status summary must show the corrected latest sleep while preserving the earlier safety signal")
let sameDayWeeklyReview = WeeklyReviewService.summary(for: reviewWeek, data: sameDayHealthData, asOf: reviewWeek.addingTimeInterval(23 * 60 * 60), calendar: fixedCalendar)
verify(sameDayWeeklyReview.averageSleepHours == 8 && sameDayWeeklyReview.suggestedVariable == .recoveryPriority, "weekly review must count one sleep value per day while retaining any same-day recovery risk")
verify(reviewSummary.observedPlanDays == 2 && abs(reviewSummary.completionRate - 4.0 / 6.0) < 0.0001, "weekly review must count only already-observed official plan days, not future dates")
verify(reviewSummary.executionDays.count == 7 && reviewSummary.executionDays.filter(\.isObservedPlanDay).count == 2, "weekly review must expose a complete seven-day execution trail while counting only observed plan dates")
verify(reviewSummary.executionDays[0].status == .completed && reviewSummary.executionDays[0].completedActions == 3 && reviewSummary.executionDays[1].status == .partiallyCompleted && reviewSummary.executionDays[1].completedActions == 1, "weekly execution trail must agree with saved daily completion states")
verify(reviewSummary.executionDays.dropFirst(2).allSatisfy { !$0.isObservedPlanDay && $0.status == .upcoming }, "unobserved future plan days may be shown but must not affect weekly completion")
let futureWeeklySignalDate = fixedCalendar.date(byAdding: .day, value: 4, to: reviewWeek)!
let futureWeeklyTrend = WeeklyBodyCheckIn(
    weekStart: reviewWeek,
    recordedAt: futureWeeklySignalDate,
    weightKg: 48,
    waistCm: 60,
    note: "错误导入的未来趋势"
)
let futureWeeklySignalData = PrivateCoachData(
    profile: profile,
    datedHealthStatusNotes: [
        DatedHealthStatus(date: reviewWeek, status: HealthStatus(sleepHours: 7.5)),
        DatedHealthStatus(date: futureWeeklySignalDate, status: HealthStatus(sleepHours: 4.0, painOrInjury: true, skinConcerns: [.redness]))
    ],
    weeklyBodyCheckIns: [reviewCheckIn, futureWeeklyTrend]
)
let futureSafeWeeklyReview = WeeklyReviewService.summary(for: reviewWeek, data: futureWeeklySignalData, asOf: reviewAsOf, calendar: fixedCalendar)
verify(
    futureSafeWeeklyReview.averageSleepHours == 7.5
        && futureSafeWeeklyReview.skinLabels.isEmpty
        && futureSafeWeeklyReview.suggestedVariable != .recoveryPriority
        && futureSafeWeeklyReview.latestWeightKg == 54.2,
    "weekly review must exclude future imported health and trend records from current guidance"
)
verify(reviewSummary.latestWeightKg == 54.2 && abs((reviewSummary.weightChangeKg ?? 0) + 0.6) < 0.0001 && reviewSummary.latestWaistCm == 68.0 && abs((reviewSummary.waistChangeCm ?? 0) + 1.0) < 0.0001, "weekly review must show manual trend changes without reading or writing HealthKit")
verify(reviewSummary.skinLabels == ["干燥", "泛红"] && reviewSummary.averageSleepHours == 7.25, "weekly review must summarize recorded sleep and skin states for the current week")
verify(reviewSummary.suggestedVariable == .keepRoutine, "a partially completed active week must not prematurely prescribe a low-completion intervention")
verify(reviewSummary.preparationChecklist.count == 2 && reviewSummary.preparationChecklist.allSatisfy { !$0.contains("自动") }, "weekly maintenance guidance must be a small manual preparation checklist, not an automatic plan change")
let skippedReviewData = PrivateCoachData(
    profile: profile,
    dailyCompletions: [
        DailyCompletion(date: reviewWeek, foodCompleted: true, trainingOrRecoveryCompleted: false, bedtimePreparationCompleted: false, skippedAt: reviewWeek),
        DailyCompletion(date: fixedCalendar.date(byAdding: .day, value: 1, to: reviewWeek)!, foodCompleted: false, trainingOrRecoveryCompleted: false, bedtimePreparationCompleted: false)
    ]
)
let skippedReview = WeeklyReviewService.summary(for: reviewWeek, data: skippedReviewData, asOf: reviewAsOf, calendar: fixedCalendar)
verify(skippedReview.explicitlySkippedPlanDays == 1 && abs(skippedReview.completionRate - 1.0 / 6.0) < 0.0001, "weekly review must preserve an explicit skip while counting only its actually completed actions")
verify(skippedReview.executionDays[0].status == .skipped && skippedReview.evidence.contains { $0.contains("明确跳过") }, "weekly review must explain that an explicit skip is distinct from an unrecorded day")
let skippedPreview = WeeklyReportSharing.preview(from: skippedReviewData, weekStart: reviewWeek, selection: selection, asOf: reviewAsOf, calendar: fixedCalendar)
verify(skippedPreview.observedPlanDays == 2 && skippedPreview.explicitlySkippedPlanDays == 1 && abs(skippedPreview.completionRate - skippedReview.completionRate) < 0.0001, "voluntary weekly report preview must use the same observed-day and skip semantics as the private review")
let skippedReport = WeeklyReportSharing.makeReport(from: skippedReviewData, weekStart: reviewWeek, selection: selection, confirmed: true, now: reviewAsOf, calendar: fixedCalendar)!
verify(skippedReport.observedPlanDays == 2 && skippedReport.explicitlySkippedPlanDays == 1, "saved voluntary weekly report must preserve its generated review scope and explicit skip count")
let encodedLegacyReport = try JSONEncoder().encode(skippedReport)
var legacyReportObject = try JSONSerialization.jsonObject(with: encodedLegacyReport) as! [String: Any]
legacyReportObject.removeValue(forKey: "observedPlanDays")
legacyReportObject.removeValue(forKey: "explicitlySkippedPlanDays")
let migratedLegacyReport = try JSONDecoder().decode(SharedWeeklyReport.self, from: JSONSerialization.data(withJSONObject: legacyReportObject))
verify(migratedLegacyReport.observedPlanDays == 0 && migratedLegacyReport.explicitlySkippedPlanDays == 0, "older local weekly reports without review-scope fields must remain readable")
let protectedReviewData = PrivateCoachData(profile: profile, datedHealthStatusNotes: [DatedHealthStatus(date: reviewWeek, status: HealthStatus(painOrInjury: true))])
let protectedReview = WeeklyReviewService.summary(for: reviewWeek, data: protectedReviewData, asOf: reviewAsOf, calendar: fixedCalendar)
verify(protectedReview.suggestedVariable == .recoveryPriority, "weekly review protective signals must take priority over routine optimization")
verify(protectedReview.preparationChecklist.count == 3 && protectedReview.preparationChecklist.contains { $0.contains("不因恢复日减餐") }, "recovery-priority weekly checklist must remain non-punitive and practical")
let preparationWeek = fixedCalendar.date(from: DateComponents(year: 2026, month: 8, day: 5))!
let preparationReview = WeeklyReviewService.summary(for: preparationWeek, data: PrivateCoachData(profile: profile), asOf: fixedCalendar.date(from: DateComponents(year: 2026, month: 8, day: 9))!, calendar: fixedCalendar)
verify(preparationReview.observedPlanDays == 0 && preparationReview.suggestedVariable == .keepRoutine && preparationReview.completionRate == 0, "the preparation period must not be treated as failed plan completion")
verify(preparationReview.executionDays.count == 7 && preparationReview.executionDays.prefix(5).allSatisfy { $0.dayIndex == nil && $0.status == nil && !$0.isObservedPlanDay } && preparationReview.executionDays.suffix(2).allSatisfy { $0.dayIndex != nil && $0.status == .upcoming && !$0.isObservedPlanDay }, "preparation-week trail must mark pre-start dates as non-plan and later dates as future without calling either missed")
let preparationStatusReview = WeeklyReviewService.summary(
    for: preparationWeek,
    data: PrivateCoachData(profile: profile, datedHealthStatusNotes: [
        DatedHealthStatus(date: preparationDate, status: HealthStatus(sleepHours: 5, painOrInjury: true, skinConcerns: [.redness]))
    ]),
    asOf: fixedCalendar.date(from: DateComponents(year: 2026, month: 8, day: 9))!,
    calendar: fixedCalendar
)
verify(preparationStatusReview.averageSleepHours == nil && preparationStatusReview.skinLabels.isEmpty && preparationStatusReview.suggestedVariable == .keepRoutine, "a preparation-day private status must not turn a non-plan weekly review into recovery priority")
let completedLowCompletionWeek = fixedCalendar.date(from: DateComponents(year: 2026, month: 8, day: 10))!
let lowCompletionReview = WeeklyReviewService.summary(
    for: completedLowCompletionWeek,
    data: PrivateCoachData(profile: profile),
    asOf: fixedCalendar.date(from: DateComponents(year: 2026, month: 8, day: 20))!,
    calendar: fixedCalendar
)
verify(lowCompletionReview.observedPlanDays == 7 && lowCompletionReview.suggestedVariable == .mealPreparation, "a finished low-completion week may recommend only meal preparation")
verify(lowCompletionReview.preparationChecklist.count == 3 && lowCompletionReview.preparationChecklist.contains { $0.contains("冰袋") }, "low-completion weekly checklist must prioritize concrete meal preparation without changing training or calories")
let activeStatusReview = WeeklyReviewService.summary(
    for: completedLowCompletionWeek,
    data: PrivateCoachData(profile: profile, datedHealthStatusNotes: [
        DatedHealthStatus(date: completedLowCompletionWeek, status: HealthStatus(painOrInjury: true))
    ]),
    asOf: fixedCalendar.date(from: DateComponents(year: 2026, month: 8, day: 20))!,
    calendar: fixedCalendar
)
verify(activeStatusReview.suggestedVariable == .recoveryPriority, "a formal plan-day protective status must still take priority in the weekly review")
let encodedReviewData = try JSONEncoder().encode(reviewData)
var legacyReviewObject = try JSONSerialization.jsonObject(with: encodedReviewData) as! [String: Any]
legacyReviewObject.removeValue(forKey: "weeklyBodyCheckIns")
let migratedReviewData = try JSONDecoder().decode(PrivateCoachData.self, from: JSONSerialization.data(withJSONObject: legacyReviewObject))
verify(migratedReviewData.weeklyBodyCheckIns.isEmpty, "older private JSON without weekly body check-ins must remain readable")
let encodedLateWakeCompletion = try JSONEncoder().encode(lateWakeLunchDinnerComplete)
var legacyLateWakeCompletionObject = try JSONSerialization.jsonObject(with: encodedLateWakeCompletion) as! [String: Any]
legacyLateWakeCompletionObject.removeValue(forKey: "breakfastWaivedForLateWake")
let migratedLateWakeCompletion = try JSONDecoder().decode(DailyCompletion.self, from: JSONSerialization.data(withJSONObject: legacyLateWakeCompletionObject))
verify(!migratedLateWakeCompletion.breakfastWaivedForLateWake && !migratedLateWakeCompletion.foodCompleted && migratedLateWakeCompletion.lunchCompleted && migratedLateWakeCompletion.dinnerCompleted, "older daily completion JSON without a late-wake acknowledgement must remain readable without inventing a completed breakfast")
let lateWakeExportText = String(decoding: try PrivateExport.makeOwnerExport(PrivateCoachData(profile: profile, dailyCompletions: [lateWakeLunchDinnerComplete])), as: UTF8.self)
verify(lateWakeExportText.contains("breakfastWaivedForLateWake") && !reportPayloadText.contains("breakfastWaivedForLateWake"), "owner export may retain late-wake execution semantics while voluntary weekly reports omit meal-level history")
let reviewExportText = String(decoding: try PrivateExport.makeOwnerExport(reviewData), as: UTF8.self)
verify(reviewExportText.contains("weeklyBodyCheckIns"), "owner export may include the owner’s manually entered trend points")
verify(!reportPayloadText.contains("weeklyBodyCheckIns"), "voluntary friend weekly reports must not include manual body trends")

let goalChangeDate = fixedCalendar.date(from: DateComponents(year: 2026, month: 8, day: 17, hour: 10))!
let goalUpdate = GoalAdjustmentService.confirmedChange(
    from: "腰腹与体态",
    to: "  两个月减脂塑形，优先腰腹与体态  ",
    at: goalChangeDate
)
verify(goalUpdate?.goal == "两个月减脂塑形，优先腰腹与体态", "confirmed goal updates must trim and preserve the owner's requested goal")
verify(goalUpdate?.change.kind == .goal && goalUpdate?.change.authority == .requiresConfirmation, "goal updates must create a confirmation-gated audit record")
verify(goalUpdate?.change.before == "腰腹与体态" && goalUpdate?.change.after == "两个月减脂塑形，优先腰腹与体态" && goalUpdate?.change.createdAt == goalChangeDate, "goal audit entries must preserve the before, after, and confirmation time")
verify(GoalAdjustmentService.confirmedChange(from: "腰腹与体态", to: " 腰腹与体态 ") == nil, "an unchanged goal must not create duplicate audit entries")
verify(GoalAdjustmentService.confirmedChange(from: "腰腹与体态", to: "   ") == nil, "a blank goal must not erase an existing goal")

let importedExpenseDate = fixedCalendar.date(from: DateComponents(year: 2026, month: 8, day: 11, hour: 16, minute: 39))!
let importedExpenseID = UUID(uuidString: "A1D70A90-26C0-5E4F-9E21-DAAFC7B5C3A1")!
let importedExpense = BudgetImportCandidate(
    id: importedExpenseID,
    sourceRow: 12,
    date: importedExpenseDate,
    amountYuan: 38.5,
    sourceCategory: "餐饮/买菜",
    note: "鸡蛋和蔬菜",
    category: QianJiBudgetImport.suggestedCategory(sourceCategory: "餐饮/买菜", note: "鸡蛋和蔬菜")
)
verify(importedExpense.category == .ingredients, "QianJi import preview must map obvious grocery rows to ingredients while still leaving the category editable")
verify(QianJiBudgetImport.suggestedCategory(sourceCategory: "运动", note: "游泳馆单次票") == .swimming, "QianJi import preview must recognize an explicit swimming expense")
verify(QianJiBudgetImport.suggestedCategory(sourceCategory: "交通", note: "青桔单车") == .cycling, "QianJi import preview must recognize shared-cycle spending")
verify(QianJiBudgetImport.suggestedCategory(sourceCategory: "日用品", note: "防晒和洁面") == .skincare, "QianJi import preview must recognize skincare spending")
let importedLedger = MonthlyBudgetLedger(monthKey: "2026-08", entries: [importedExpense.expenseEntry()])
verify(QianJiBudgetImport.isDuplicate(importedExpense, in: importedLedger), "QianJi import must reject a repeated stable receipt ID")
let semanticDuplicate = BudgetImportCandidate(
    id: UUID(),
    sourceRow: 99,
    date: importedExpenseDate.addingTimeInterval(30),
    amountYuan: 38.5,
    sourceCategory: "其他",
    note: "鸡蛋 和蔬菜",
    category: .buffer
)
verify(QianJiBudgetImport.isDuplicate(semanticDuplicate, in: importedLedger), "QianJi import must flag the same minute, amount, and normalized note even if a re-export changes its row ID")

let prepSessionMeal = MealCard(
    title: "测试｜鸡胸蔬菜饭",
    ingredients: ["鸡胸 300g", "蔬菜 400g", "熟米饭 360g"],
    thawAndPortion: "鸡胸前一晚移冷藏；熟饭分两盒。",
    timedSteps: [
        "0:00 电饭锅加热饭。",
        "1:00 电磁炉锅炒鸡胸。",
        "5:00 下蔬菜。",
        "12:00–15:00 分两盒。"
    ],
    portionsAndStorage: "做两份；第二盒 2 小时内冷藏，次日热透。总操作 15 分钟。",
    substitutions: "鸡胸可换鱼片 300g。"
)
let prepSessionPlan = MealPrepSessionPlan(meal: prepSessionMeal)
verify(prepSessionPlan.totalSeconds == 900, "guided meal prep must use the card's declared operation total")
verify(
    prepSessionMeal.totalOperationText == "总操作 15 分钟"
        && prepSessionMeal.firstExecutionStep == "0:00 电饭锅加热饭。",
    "compact meal entry points must surface the authored first step and declared total without inventing either"
)
verify(prepSessionPlan.steps.map(\.scheduledSecond) == [0, 60, 300, 720], "guided meal prep must preserve the first timestamp of every authored step")
verify(prepSessionPlan.timingMessage(for: 2, elapsedSeconds: 240).contains("还有 1:00"), "guided meal prep must show how long remains before a future step")
verify(prepSessionPlan.timingMessage(for: 2, elapsedSeconds: 400).contains("不要为追时间开大火"), "guided meal prep must not encourage unsafe catch-up cooking")
verify(prepSessionPlan.hardLimitMessage(elapsedSeconds: 899) == nil && prepSessionPlan.hardLimitMessage(elapsedSeconds: 900)?.contains("先关火") == true, "guided meal prep must surface the declared hard limit without treating the timer as a food-safety endpoint")
verify(prepSessionPlan.returnFromBackgroundMessage(awaySeconds: 14, elapsedSeconds: 500) == nil, "guided meal prep must not interrupt a momentary control-center transition")
verify(prepSessionPlan.returnFromBackgroundMessage(awaySeconds: 60, elapsedSeconds: 500)?.contains("App 不能代替你看管炉火") == true, "guided meal prep must disclose that its continuing background clock is not heat supervision")
verify(prepSessionPlan.returnFromBackgroundMessage(awaySeconds: 60, elapsedSeconds: 900)?.contains("已到卡片上限") == true, "returning after the recipe limit must lead with the stop-heat safety boundary")

let healthExportFixture = """
<?xml version="1.0" encoding="UTF-8"?>
<HealthData locale="zh_CN">
  <ExportDate value="2026-08-10 10:00:00 +0800"/>
  <Record type="HKQuantityTypeIdentifierBodyMass" sourceName="Apple Watch" unit="kg" creationDate="2026-08-09 08:00:00 +0800" startDate="2026-08-09 08:00:00 +0800" endDate="2026-08-09 08:00:00 +0800" value="60.5"/>
  <Record type="HKQuantityTypeIdentifierBodyFatPercentage" sourceName="Apple Watch" unit="%" creationDate="2026-08-09 08:00:00 +0800" startDate="2026-08-09 08:00:00 +0800" endDate="2026-08-09 08:00:00 +0800" value="25.0"/>
  <Record type="HKQuantityTypeIdentifierRestingHeartRate" sourceName="Apple Watch" unit="count/min" creationDate="2026-08-10 07:00:00 +0800" startDate="2026-08-10 07:00:00 +0800" endDate="2026-08-10 07:00:01 +0800" value="62"/>
  <Record type="HKQuantityTypeIdentifierStepCount" sourceName="iPhone" unit="count" creationDate="2026-08-09 20:00:00 +0800" startDate="2026-08-09 08:00:00 +0800" endDate="2026-08-09 20:00:00 +0800" value="28000"/>
  <Record type="HKQuantityTypeIdentifierActiveEnergyBurned" sourceName="Apple Watch" unit="kcal" creationDate="2026-08-10 09:00:00 +0800" startDate="2026-08-10 08:00:00 +0800" endDate="2026-08-10 09:00:00 +0800" value="300"/>
  <Record type="HKCategoryTypeIdentifierSleepAnalysis" sourceName="Apple Watch" value="HKCategoryValueSleepAnalysisAsleepCore" startDate="2026-08-09 22:00:00 +0800" endDate="2026-08-10 02:00:00 +0800"/>
  <Record type="HKCategoryTypeIdentifierSleepAnalysis" sourceName="Apple Watch" value="HKCategoryValueSleepAnalysisAsleepREM" startDate="2026-08-10 01:00:00 +0800" endDate="2026-08-10 06:00:00 +0800"/>
  <Workout workoutActivityType="HKWorkoutActivityTypeSwimming" duration="30" durationUnit="min" sourceName="Apple Watch" creationDate="2026-08-10 09:00:00 +0800" startDate="2026-08-10 08:00:00 +0800" endDate="2026-08-10 08:30:00 +0800"/>
</HealthData>
"""
let healthFixtureURL = FileManager.default.temporaryDirectory.appendingPathComponent("youye-health-fixture-\(UUID().uuidString).xml")
defer { try? FileManager.default.removeItem(at: healthFixtureURL) }
try Data(healthExportFixture.utf8).write(to: healthFixtureURL, options: .atomic)
let healthExportPreview = try AppleHealthExportImporter.preview(fromXMLAt: healthFixtureURL, archiveFileName: "fixture.zip")
verify(abs((healthExportPreview.snapshot.weightKg ?? 0) - 60.5) < 0.001, "Apple Health export preview must retain the latest in-window weight")
verify(abs((healthExportPreview.snapshot.bodyFatPercent ?? 0) - 25) < 0.001, "Apple Health export preview must parse body-fat percent without multiplying an exported percentage twice")
verify(healthExportPreview.snapshot.averageDailySteps14d == 2000, "Apple Health export preview must use the same conservative 14-day step average policy")
verify(abs((healthExportPreview.snapshot.sleepHoursLastNight ?? 0) - 8) < 0.001, "Apple Health export preview must union overlapping sleep stages instead of double-counting them")
verify(healthExportPreview.snapshot.restingHeartRate == 62 && healthExportPreview.snapshot.activeEnergyKcal == 300, "Apple Health export preview must parse the supported current-window heart-rate and energy metrics")
verify(healthExportPreview.snapshot.workoutMinutes == 30 && healthExportPreview.snapshot.swimMinutes == 30, "Apple Health export preview must distinguish swimming inside the unioned workout total")
verify(!healthExportPreview.isCurrentDay(asOf: fixedCalendar.date(byAdding: .day, value: 1, to: programStart)!, calendar: fixedCalendar), "an older Apple Health export must remain historical and must not silently drive a later day's recovery decision")
let importedWeightWeek = WeeklyReviewService.weekStart(for: healthExportPreview.latestWeightRecordedAt!, calendar: fixedCalendar)
let weightAdoptionFixture = PrivateCoachData(
    profile: profile,
    weeklyBodyCheckIns: [WeeklyBodyCheckIn(weekStart: importedWeightWeek, recordedAt: programStart, weightKg: 61.0, waistCm: 70, note: "保留本人备注")]
)
verify(AppleHealthWeightAdoption.adopting(preview: healthExportPreview, in: weightAdoptionFixture, confirmed: false, confirmedAt: programStart, calendar: fixedCalendar) == nil, "previewing an Apple Health export must never persist weight without a separate confirmation")
let adoptedWeight = AppleHealthWeightAdoption.adopting(preview: healthExportPreview, in: weightAdoptionFixture, confirmed: true, confirmedAt: programStart, calendar: fixedCalendar)!
let adoptedCheckIn = adoptedWeight.data.weeklyBodyCheckIns.first { fixedCalendar.isDate($0.weekStart, inSameDayAs: importedWeightWeek) }!
verify(adoptedCheckIn.weightKg == 60.5 && adoptedCheckIn.waistCm == 70 && adoptedCheckIn.note == "保留本人备注", "confirmed export weight must replace only that week's weight while preserving the owner's waist and note")
verify(adoptedCheckIn.weightSource == .confirmedAppleHealthExport && adoptedCheckIn.weightMeasuredAt == healthExportPreview.latestWeightRecordedAt, "a confirmed export trend point must retain its source and actual measurement time")
let repeatedWeightAdoption = AppleHealthWeightAdoption.adopting(preview: healthExportPreview, in: adoptedWeight.data, confirmed: true, confirmedAt: programStart.addingTimeInterval(60), calendar: fixedCalendar)!
verify(repeatedWeightAdoption.wasAlreadySaved && repeatedWeightAdoption.data == adoptedWeight.data, "re-importing the same confirmed export weight must be idempotent and must not create a duplicate trend point")
let legacyWeightData = try JSONEncoder().encode(WeeklyBodyCheckIn(weekStart: importedWeightWeek, recordedAt: programStart, weightKg: 60))
var legacyWeightObject = try JSONSerialization.jsonObject(with: legacyWeightData) as! [String: Any]
legacyWeightObject.removeValue(forKey: "weightSource")
legacyWeightObject.removeValue(forKey: "weightMeasuredAt")
let restoredLegacyWeight = try JSONDecoder().decode(WeeklyBodyCheckIn.self, from: JSONSerialization.data(withJSONObject: legacyWeightObject))
verify(restoredLegacyWeight.weightSource == .manual && restoredLegacyWeight.weightMeasuredAt == restoredLegacyWeight.recordedAt, "legacy weekly weights must migrate to a visible manual source without losing their measurement date")
legacyWeightObject["weightSource"] = "damagedFutureSource"
let restoredUnknownWeightSource = try JSONDecoder().decode(WeeklyBodyCheckIn.self, from: JSONSerialization.data(withJSONObject: legacyWeightObject))
verify(restoredUnknownWeightSource.weightSource == .manual, "an unknown imported weight-source token must not make the owner's whole private profile undecodable")
let futureWeightPreview = AppleHealthExportPreview(
    archiveFileName: "future.zip",
    exportDate: programStart.addingTimeInterval(3_600),
    snapshot: HealthSnapshot(fetchedAt: programStart, weightKg: 55, source: "test"),
    relevantRecordCount: 1,
    latestWeightRecordedAt: programStart.addingTimeInterval(3_600),
    latestBodyFatRecordedAt: nil,
    latestRestingHeartRateRecordedAt: nil
)
verify(AppleHealthWeightAdoption.adopting(preview: futureWeightPreview, in: weightAdoptionFixture, confirmed: true, confirmedAt: programStart, calendar: fixedCalendar) == nil, "a future-dated exported weight must never enter the owner's weekly trend")

let phaseEnd = fixedCalendar.date(byAdding: .day, value: 57, to: programStart)!
let completionFixture = PrivateCoachData(
    profile: profile,
    dailyCompletions: [
        DailyCompletion(date: programStart, foodCompleted: true, trainingOrRecoveryCompleted: true, bedtimePreparationCompleted: false),
        DailyCompletion(date: fixedCalendar.date(byAdding: .day, value: 1, to: programStart)!, foodCompleted: false, trainingOrRecoveryCompleted: true, bedtimePreparationCompleted: false, skippedAt: phaseEnd)
    ],
    datedHealthStatusNotes: [
        DatedHealthStatus(date: programStart, status: HealthStatus(sleepHours: 5.5, painOrInjury: true, skinConcerns: [.redness])),
        DatedHealthStatus(date: fixedCalendar.date(byAdding: .day, value: 7, to: programStart)!, status: HealthStatus(sleepHours: 7.5, skinConcerns: [.dryness]))
    ],
    weeklyBodyCheckIns: [
        WeeklyBodyCheckIn(weekStart: programStart, recordedAt: programStart, weightKg: 60, waistCm: 70),
        WeeklyBodyCheckIn(weekStart: fixedCalendar.date(byAdding: .day, value: 49, to: programStart)!, recordedAt: phaseEnd, weightKg: 59, waistCm: 68)
    ]
)
let phaseReview = ProgramCompletionReviewService.make(data: completionFixture, calendar: fixedCalendar)
verify(phaseReview.formalPlanDays == 56 && phaseReview.recordedPlanDays == 2 && phaseReview.unrecordedPlanDays == 54, "phase assessment must report only the 56 formal days and keep unrecorded days distinct")
verify(phaseReview.recordedCompletedActions == 3 && abs(phaseReview.completionRate - 3.0 / 168.0) < 0.0001, "phase assessment must use the auditable 56 by 3 denominator")
verify(phaseReview.explicitlySkippedPlanDays == 1 && phaseReview.evidence.contains { $0.contains("未记录不等于失败") }, "phase assessment must preserve explicit skips and never call missing records failures")
verify(phaseReview.protectiveSignals.contains("疼痛/受伤") && phaseReview.protectiveSignals.contains("睡眠少于 6 小时"), "phase assessment must surface saved protective signals without HealthKit samples")
verify(phaseReview.skinLabels == ["干燥", "泛红"] && phaseReview.latestWeightKg == 59 && phaseReview.weightChangeKg == -1 && phaseReview.latestWaistCm == 68 && phaseReview.waistChangeCm == -2, "phase assessment must summarize manually recorded body trends and skin labels")
verify(phaseReview.confirmationChecklist.contains { $0.contains("不新开 56 天计划") } && phaseReview.confirmationChecklist.contains { $0.contains("不会自动修改") }, "phase assessment must state that all next-stage changes remain confirmation-gated")
let phaseFutureDate = fixedCalendar.date(byAdding: .day, value: 21, to: programStart)!
let phaseAsOf = fixedCalendar.date(byAdding: .day, value: 7, to: programStart)!
let futureSafePhaseReview = ProgramCompletionReviewService.make(
    data: PrivateCoachData(
        profile: profile,
        dailyCompletions: [DailyCompletion(date: programStart, foodCompleted: true, trainingOrRecoveryCompleted: true, bedtimePreparationCompleted: true), DailyCompletion(date: phaseFutureDate, foodCompleted: true, trainingOrRecoveryCompleted: true, bedtimePreparationCompleted: true)],
        datedHealthStatusNotes: [DatedHealthStatus(date: phaseFutureDate, status: HealthStatus(sleepHours: 4.5, painOrInjury: true, skinConcerns: [.redness]))],
        weeklyBodyCheckIns: [WeeklyBodyCheckIn(weekStart: programStart, recordedAt: programStart, weightKg: 60), WeeklyBodyCheckIn(weekStart: phaseFutureDate, recordedAt: phaseFutureDate, weightKg: 40)]
    ),
    asOf: phaseAsOf,
    calendar: fixedCalendar
)
verify(
    futureSafePhaseReview.recordedPlanDays == 1
        && futureSafePhaseReview.recordedCompletedActions == 3
        && futureSafePhaseReview.averageSleepHours == nil
        && futureSafePhaseReview.protectiveSignals.isEmpty
        && futureSafePhaseReview.latestWeightKg == 60,
    "phase assessment must exclude future imported completion, health, and trend records until their day occurs"
)

print("PASS: health-state safety, confirmation boundaries, audit trail, guided meal prep, three-action today screen, private export/local deletion, QianJi import de-duplication, and voluntary weekly sharing rules verified.")
}

do {
    try await runRuleChecks()
    if let flagIndex = CommandLine.arguments.firstIndex(of: "--apple-health-export"),
       CommandLine.arguments.indices.contains(flagIndex + 1) {
        let url = URL(fileURLWithPath: CommandLine.arguments[flagIndex + 1])
        let preview = try AppleHealthExportImporter.preview(fromArchiveAt: url)
        let metrics = preview.snapshot
        let weightText = metrics.weightKg.map { String(format: "%.1f", $0) } ?? "none"
        let sleepText = metrics.sleepHoursLastNight.map { String(format: "%.1f", $0) } ?? "none"
        print("PASS: real Apple Health export parsed locally; date=\(preview.exportDate.formatted(.iso8601)), relevant=\(preview.relevantRecordCount), weight=\(weightText), sleep=\(sleepText). Raw samples were not persisted.")
    }
} catch {
    fputs("FAIL: rule check threw an unexpected error: \(error)\n", stderr)
    exit(1)
}
