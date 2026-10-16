import SwiftUI

/// Owner-selectable visual direction. The choice is a local presentation preference only;
/// it never changes health data, plan logic, reminders, or meal cards.
public enum AppTheme: String, CaseIterable, Identifiable, Sendable {
    case seaGlass
    case coral
    case violet

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .seaGlass: "海岸青"
        case .coral: "珊瑚暖"
        case .violet: "紫雾蓝"
        }
    }

    public var subtitle: String {
        switch self {
        case .seaGlass: "清爽、安静，适合每天跟练"
        case .coral: "温暖、有活力，突出今日行动"
        case .violet: "柔和、专注，降低视觉刺激"
        }
    }

    public var tint: Color {
        switch self {
        case .seaGlass: Color(red: 0.043, green: 0.431, blue: 0.384)
        case .coral: Color(red: 0.80, green: 0.28, blue: 0.22)
        case .violet: Color(red: 0.35, green: 0.25, blue: 0.66)
        }
    }

    public var softTint: Color { tint.opacity(0.12) }
}

struct AppThemeSettingsView: View {
    @AppStorage("youye.healthCoach.appTheme") private var selectedTheme = AppTheme.seaGlass.rawValue

    private var theme: AppTheme { AppTheme(rawValue: selectedTheme) ?? .seaGlass }

    var body: some View {
        Form {
            Section("选择外观") {
                ForEach(AppTheme.allCases) { option in
                    Button {
                        selectedTheme = option.rawValue
                    } label: {
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(option.tint.gradient)
                                .frame(width: 54, height: 42)
                                .overlay {
                                    Image(systemName: option == theme ? "checkmark" : "sparkles")
                                        .foregroundStyle(.white)
                                }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(option.name).font(.headline)
                                Text(option.subtitle).font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if option == theme {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(option.tint)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("外观：\(option.name)")
                    .accessibilityHint(option == theme ? "当前已选择" : "点按立即应用")
                }
            }
            Section("预览") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("今天的主任务").font(.caption.weight(.semibold)).foregroundStyle(theme.tint)
                    Text("20 分钟腰腹体态训练").font(.title3.bold())
                    HStack {
                        Label("本周 2/3 次", systemImage: "target")
                        Spacer()
                        Text("开始跟练").font(.subheadline.bold()).foregroundStyle(.white)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(theme.tint, in: Capsule())
                    }
                }
                .padding(16)
                .background(theme.softTint, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            Text("外观只改变颜色和强调方式；计划、训练、备餐、状态与本机数据不受影响。")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .navigationTitle("外观")
        .tint(theme.tint)
    }
}
