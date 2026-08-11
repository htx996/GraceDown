import AppKit
import SwiftUI
import UPSPowerMonitorCore

struct SettingsView: View {
    @ObservedObject var preferences: UPSMonitorPreferences
    @ObservedObject var store: UPSMonitorStore

    private static let shutdownStatusOptions: [PowerSourceStatus] = [.onBattery, .onACPower, .charged]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                HStack(alignment: .top, spacing: 18) {
                    SettingsSectionCard(
                        title: "UPS 来源",
                        subtitle: sourceSummary,
                        systemImage: "network",
                        tint: .green
                    ) {
                        SettingsRow("连接方式", subtitle: "选择 UPS 数据来源") {
                            Picker("连接方式", selection: $preferences.connectionMode) {
                                ForEach(UPSConnectionMode.allCases) { mode in
                                    Text(mode.displayName).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 236)
                        }

                        if preferences.connectionMode == .networkNUT {
                            SettingsDivider()

                            SettingsRow("NAS 地址", subtitle: "绿联 NAS 的 IP 或主机名") {
                                SettingsTextField(
                                    placeholder: "192.168.2.86",
                                    text: $preferences.nasHost
                                )
                            }

                            SettingsDivider()

                            SettingsStepperRow(
                                title: "NUT 端口",
                                subtitle: "默认端口 3493",
                                value: $preferences.nasPort,
                                range: 1...65_535,
                                step: 1,
                                suffix: ""
                            )

                            SettingsDivider()

                            SettingsRow("UPS 名称", subtitle: "留空时使用第一个 UPS") {
                                SettingsTextField(
                                    placeholder: "自动选择",
                                    text: $preferences.upsName
                                )
                            }

                            SettingsDivider()

                            SettingsRow("用户名", subtitle: "NUT 认证用户名") {
                                SettingsTextField(
                                    placeholder: "可选",
                                    text: $preferences.username
                                )
                            }

                            SettingsDivider()

                            SettingsRow("密码", subtitle: "NUT 认证密码") {
                                SettingsTextField(
                                    placeholder: "可选",
                                    text: $preferences.password,
                                    isSecure: true
                                )
                            }
                        }

                        SettingsDivider()

                        SettingsStepperRow(
                            title: "刷新间隔",
                            subtitle: "菜单栏和弹窗状态更新频率",
                            value: $preferences.pollIntervalSeconds,
                            range: 5...300,
                            step: 5,
                            suffix: "秒"
                        )
                    }
                    .frame(width: 435, alignment: .top)

                    SettingsSectionCard(
                        title: "自动关机",
                        subtitle: shutdownSummary,
                        systemImage: "power",
                        tint: preferences.autoShutdownEnabled ? .red : .secondary
                    ) {
                        SettingsToggleRow(
                            title: "启用自动关机",
                            subtitle: "条件持续成立后请求 macOS 关机",
                            isOn: $preferences.autoShutdownEnabled
                        )

                        SettingsDivider()

                        SettingsStatusConditionsRow(
                            title: "状态条件",
                            subtitle: "可单选或多选",
                            options: Self.shutdownStatusOptions,
                            currentStatus: store.selectedUPS?.status,
                            selection: $preferences.shutdownStatusConditions
                        )

                        SettingsDivider()

                        SettingsEnabledStepperRow(
                            title: "电量阈值",
                            subtitle: "UPS 电量低于该比例",
                            isEnabled: $preferences.triggerOnLowBatteryPercent,
                            value: $preferences.lowBatteryPercent,
                            range: 1...100,
                            step: 1,
                            suffix: "%"
                        )

                        SettingsDivider()

                        SettingsEnabledStepperRow(
                            title: "剩余时间阈值",
                            subtitle: "预计续航低于该时长",
                            isEnabled: $preferences.triggerOnLowRuntime,
                            value: $preferences.lowRuntimeMinutes,
                            range: 1...240,
                            step: 1,
                            suffix: "分钟"
                        )

                        SettingsDivider()

                        SettingsStepperRow(
                            title: "持续时间",
                            subtitle: "触发条件保持多久后关机",
                            value: $preferences.shutdownGracePeriodSeconds,
                            range: 0...3600,
                            step: 10,
                            suffix: "秒"
                        )

                        SettingsDivider()

                        SettingsToggleRow(
                            title: "低电量信号",
                            subtitle: "响应 UPS 自身的 LB 状态",
                            isOn: $preferences.triggerOnLowBatterySignal
                        )
                    }
                    .frame(width: 435, alignment: .top)
                }

                statusFooter
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 24)
        }
        .scrollIndicators(.hidden)
        .background(Color(nsColor: .windowBackgroundColor))
        .background(UserWindowActivationObserver().frame(width: 0, height: 0))
        .frame(width: 940, height: 680)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            BatteryLogoView(size: 54)

            VStack(alignment: .leading, spacing: 4) {
                Text("UPS配置")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.primary)
            }

            Spacer()

            SettingsStatusChip(
                title: store.selectedUPS?.status.displayName ?? "未连接",
                color: statusColor
            )
        }
        .padding(.bottom, 4)
    }

    private var statusFooter: some View {
        HStack(spacing: 14) {
            Image(systemName: statusIconName)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(statusColor)
                .frame(width: 34, height: 34)
                .background(statusColor.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text("当前状态")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.primary)

                Text(store.shutdownStatusDescription)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Button {
                store.refresh()
            } label: {
                Label("立即刷新", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(store.isRefreshing)
        }
        .padding(16)
    }

    private var sourceSummary: String {
        switch preferences.connectionMode {
        case .networkNUT:
            let host = preferences.nasHost.trimmingCharacters(in: .whitespacesAndNewlines)
            let address = host.isEmpty ? "未配置 NAS" : "\(host):\(preferences.nasPort)"
            return "绿联 NAS · \(address)"
        case .localIOKit:
            return "本机 USB/电池电源信息"
        }
    }

    private var shutdownSummary: String {
        preferences.autoShutdownEnabled ? "已启用 · \(store.shutdownRuleSummary)" : "未启用"
    }

    private var statusIconName: String {
        guard let status = store.selectedUPS?.status else {
            return "exclamationmark.circle.fill"
        }

        switch status {
        case .onBattery:
            return "bolt.trianglebadge.exclamationmark.fill"
        case .charging:
            return "bolt.fill"
        case .charged, .onACPower:
            return "checkmark.circle.fill"
        case .offline:
            return "xmark.circle.fill"
        case .unknown:
            return "questionmark.circle.fill"
        }
    }

    private var statusColor: Color {
        guard let status = store.selectedUPS?.status else {
            return .secondary
        }

        switch status {
        case .onBattery:
            return .orange
        case .charging:
            return .blue
        case .charged, .onACPower:
            return .green
        case .offline:
            return .red
        case .unknown:
            return .secondary
        }
    }
}

private struct SettingsSectionCard<Content: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    private let content: Content

    init(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: AppCornerRadius.symbolTile, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.primary)

                    Text(subtitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                }

                Spacer(minLength: 0)
            }

            VStack(spacing: 0) {
                content
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
        }
        .padding(16)
    }
}

private struct SettingsRow<Control: View>: View {
    let title: String
    let subtitle: String?
    private let control: Control

    init(
        _ title: String,
        subtitle: String? = nil,
        @ViewBuilder control: () -> Control
    ) {
        self.title = title
        self.subtitle = subtitle
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.primary)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }

            Spacer(minLength: 12)

            control
                .frame(maxWidth: 250, alignment: .trailing)
        }
        .frame(minHeight: 48)
        .contentShape(Rectangle())
    }
}

private struct SettingsTextField: View {
    let placeholder: String
    @Binding var text: String
    var isSecure = false

    var body: some View {
        Group {
            if isSecure {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
            }
        }
        .textFieldStyle(.plain)
        .font(.system(size: 14, weight: .semibold))
        .multilineTextAlignment(.center)
        .lineLimit(1)
        .padding(.horizontal, 12)
        .frame(width: 210, height: 32)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: AppCornerRadius.control, style: .continuous))
    }
}

private struct SettingsNumberField: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    let suffix: String

    var body: some View {
        HStack(spacing: 6) {
            TextField("", value: clampedValue, formatter: Self.integerFormatter)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .bold))
                .monospacedDigit()
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .frame(width: 70)

            if !suffix.isEmpty {
                Text(suffix)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Stepper("", value: $value, in: range, step: step)
                .labelsHidden()
                .controlSize(.small)
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .frame(height: 32)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: AppCornerRadius.control, style: .continuous))
    }

    private var clampedValue: Binding<Int> {
        Binding(
            get: {
                value
            },
            set: { newValue in
                value = min(max(newValue, range.lowerBound), range.upperBound)
            }
        )
    }

    private static let integerFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.allowsFloats = false
        formatter.usesGroupingSeparator = false
        return formatter
    }()
}

private struct SettingsStepperRow: View {
    let title: String
    let subtitle: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    let suffix: String

    var body: some View {
        SettingsRow(title, subtitle: subtitle) {
            SettingsNumberField(value: $value, range: range, step: step, suffix: suffix)
        }
    }
}

private struct SettingsEnabledStepperRow: View {
    let title: String
    let subtitle: String
    @Binding var isEnabled: Bool
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    let suffix: String

    var body: some View {
        SettingsRow(title, subtitle: subtitle) {
            HStack(spacing: 8) {
                Toggle(title, isOn: $isEnabled)
                    .labelsHidden()
                    .toggleStyle(.checkbox)

                SettingsNumberField(value: $value, range: range, step: step, suffix: suffix)
                    .disabled(!isEnabled)
                    .opacity(isEnabled ? 1 : 0.58)
            }
        }
    }
}

private struct SettingsToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        SettingsRow(title, subtitle: subtitle) {
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }
}

private struct SettingsStatusConditionsRow: View {
    let title: String
    let subtitle: String
    let options: [PowerSourceStatus]
    let currentStatus: PowerSourceStatus?
    @Binding var selection: Set<PowerSourceStatus>

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            Spacer(minLength: 12)

            HStack(spacing: 14) {
                ForEach(options, id: \.self) { status in
                    Toggle(isOn: binding(for: status)) {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(.green)
                                .frame(width: 7, height: 7)
                                .opacity(currentStatus == status ? 1 : 0)

                            Text(status.displayName)
                                .lineLimit(1)
                        }
                    }
                    .toggleStyle(.checkbox)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(currentStatus == status ? .primary : .secondary)
                    .fixedSize(horizontal: true, vertical: false)
                }
            }
        }
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }

    private func binding(for status: PowerSourceStatus) -> Binding<Bool> {
        Binding(
            get: {
                selection.contains(status)
            },
            set: { isSelected in
                var nextSelection = selection
                if isSelected {
                    nextSelection.insert(status)
                } else {
                    nextSelection.remove(status)
                }
                selection = nextSelection
            }
        )
    }
}

private struct SettingsStatusChip: View {
    let title: String
    let color: Color

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)

            Text(title)
                .font(.system(size: 13, weight: .bold))
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(color.opacity(0.12), in: Capsule())
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 2)
    }
}
