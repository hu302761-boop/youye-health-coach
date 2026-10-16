#if canImport(SwiftUI)
import Foundation
import SwiftUI

/// A compact native daily-card summary. Detailed gram-level recipes remain one tap away so the
/// home screen can answer “what do I do now?” without turning into a long web document.
struct TodayDailyCardHeader: View {
    let plan: TodayPlan
    let completion: DailyCompletion?
    let recovery: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var trainingIsComplete: Bool {
        completion?.trainingOrRecoveryCompleted == true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            titleRow

            if dynamicTypeSize.isAccessibilitySize {
                accessibilityStatusLabels
            } else {
                ViewThatFits(in: .horizontal) {
                    statusLabels
                    VStack(alignment: .leading, spacing: 6) { statusLabels }
                }
            }

            HStack(spacing: 8) {
                Image(systemName: trainingIsComplete ? "checkmark.circle.fill" : (recovery ? "shield.lefthalf.filled" : "play.circle.fill"))
                    .foregroundStyle(recovery ? CoachPalette.recovery : (trainingIsComplete ? CoachPalette.completed : CoachPalette.action))
                Text(trainingIsComplete ? "今天训练已完成" : (recovery ? "今天按恢复版" : "今天待视频跟练"))
                    .font(.headline)
                Spacer(minLength: 0)
            }

        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((recovery ? CoachPalette.recovery : CoachPalette.action).opacity(0.07), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke((recovery ? CoachPalette.recovery : CoachPalette.action).opacity(0.22), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .accessibilityElement(children: .combine)
    }

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline) {
            titleBlock
            Spacer(minLength: 12)
            progressLabel
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(plan.date.formatted(
                .dateTime
                    .locale(Locale(identifier: "zh_CN"))
                    .month()
                    .day()
                    .weekday(.wide)
            ))
            .font(.headline)
            Text(recovery ? "今天按恢复版完成即可" : "按自己的节奏完成，不补练")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var progressLabel: some View {
        Text(trainingIsComplete ? "已完成" : "待开始")
            .font(.subheadline.weight(.semibold).monospacedDigit())
            .foregroundStyle(recovery ? CoachPalette.recovery : CoachPalette.action)
            .accessibilityLabel(trainingIsComplete ? "今天训练已完成" : "今天训练待开始")
    }

    private var statusLabels: some View {
        HStack(spacing: 8) {
            Label(recovery ? "恢复优先" : "视频跟练", systemImage: recovery ? "shield.lefthalf.filled" : "play.rectangle.fill")
            Label("真实计时", systemImage: "timer")
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(recovery ? CoachPalette.recovery : CoachPalette.action)
    }

    private var accessibilityStatusLabels: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(recovery ? "恢复优先" : "视频跟练", systemImage: recovery ? "shield.lefthalf.filled" : "play.rectangle.fill")
            Label("真实计时", systemImage: "timer")
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(recovery ? CoachPalette.recovery : CoachPalette.action)
    }
}
#endif
