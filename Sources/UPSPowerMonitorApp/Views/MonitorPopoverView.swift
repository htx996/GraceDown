import AppKit
import SwiftUI
import UPSPowerMonitorCore

struct MonitorPopoverView: View {
    static let preferredWidth: CGFloat = 500

    @ObservedObject var store: UPSMonitorStore
    @Environment(\.dismiss) private var dismiss
    private let closeAction: (() -> Void)?
    private let settingsAction: (() -> Void)?
    private let diagnosticsAction: (() -> Void)?

    init(
        store: UPSMonitorStore,
        closeAction: (() -> Void)? = nil,
        settingsAction: (() -> Void)? = nil,
        diagnosticsAction: (() -> Void)? = nil
    ) {
        self.store = store
        self.closeAction = closeAction
        self.settingsAction = settingsAction
        self.diagnosticsAction = diagnosticsAction
    }

    var body: some View {
        VStack(spacing: 14) {
            TopStatusCapsule(
                title: deviceTitle,
                connectionText: connectionText,
                connectionColor: connectionColor
            )

            VStack(spacing: 16) {
                HStack(spacing: 14) {
                    BatterySummaryCard(
                        percentText: percentText,
                        chargeFraction: chargeFraction,
                        statusColor: statusColor
                    )

                    PowerStatusCard(
                        statusText: powerStatusText,
                        sourceText: sourceLine
                    )
                }

                MetricsCard(
                    runtime: store.selectedUPS?.runtimeDescription ?? "-",
                    voltage: store.selectedUPS?.voltageDescription ?? "-",
                    load: store.selectedUPS?.loadDescription ?? "-"
                )

                Divider()
                    .opacity(0.35)

                ShutdownOverviewSection(
                    shutdownState: store.shutdownStateTitle,
                    ruleBrief: ruleText
                )

                Divider()
                    .opacity(0.35)

                ShutdownConditionSummary(
                    graceText: store.shutdownGraceDescription,
                    lowBatteryText: store.lowBatteryMonitoringDescription,
                    cancelText: "可用"
                )

                Divider()
                    .opacity(0.3)

                footer
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 20)
        }
        .padding(14)
        .frame(width: Self.preferredWidth)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.88), in: popoverShape)
        .clipShape(popoverShape)
    }

    private var footer: some View {
        HStack(alignment: .center, spacing: 10) {
            DiagnosticStatusView(
                title: "UPS 诊断",
                status: diagnosticStateText,
                detail: diagnosticDetailText,
                color: diagnosticStateColor
            )

            Spacer(minLength: 12)

            Button {
                if let diagnosticsAction {
                    diagnosticsAction()
                } else {
                    store.refresh()
                }
            } label: {
                Label("诊断", systemImage: "stethoscope")
            }
            .disabled(store.isRefreshing)
            .help("诊断")

            Button {
                store.refresh()
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .disabled(store.isRefreshing)
            .help("刷新")

            Button {
                showSettings()
            } label: {
                Label("设置", systemImage: "line.3.horizontal")
            }
            .help("设置")

            Button(role: .destructive) {
                closePopover()
                NSApplication.shared.terminate(nil)
            } label: {
                Label("退出", systemImage: "power")
            }
            .help("退出")
        }
        .buttonStyle(ToolIconButtonStyle())
        .labelStyle(.iconOnly)
    }

    private func showSettings() {
        closePopover()
        DispatchQueue.main.async {
            if let settingsAction {
                settingsAction()
            } else {
                SettingsWindowPresenter.shared.show()
            }
        }
    }

    private func closePopover() {
        if let closeAction {
            closeAction()
        } else {
            dismiss()
        }
    }

    private var popoverShape: some InsettableShape {
        RoundedRectangle(cornerRadius: AppCornerRadius.panel, style: .continuous)
    }

    private var deviceTitle: String {
        store.selectedUPS?.name ?? "未检测到 UPS"
    }

    private var percentText: String {
        guard let chargePercent = store.selectedUPS?.chargePercent else {
            return "--"
        }

        return "\(chargePercent)%"
    }

    private var chargeFraction: Double {
        Double(store.selectedUPS?.chargePercent ?? 0) / 100
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

    private var powerStatusText: String {
        store.selectedUPS?.powerSupplyDisplayName ?? "未连接"
    }

    private var sourceLine: String {
        if let selectedUPS = store.selectedUPS {
            return formattedSourceLine(fallbackName: selectedUPS.name, source: selectedUPS.sourceDescription)
        }

        return store.sourceDescription
    }

    private var ruleText: String {
        if let message = store.errorMessage, store.selectedUPS == nil {
            return message
        }

        if store.shutdownDecision.action == .wait || store.shutdownDecision.action == .executeShutdown {
            return store.shutdownStatusDescription
        }

        return store.shutdownRuleBrief
    }

    private var diagnosticStateText: String {
        if store.selectedUPS != nil, store.errorMessage == nil {
            return "正常"
        }

        if store.errorMessage != nil {
            return "异常"
        }

        return "未连接"
    }

    private var diagnosticStateColor: Color {
        if store.selectedUPS != nil, store.errorMessage == nil {
            return .green
        }

        if store.errorMessage != nil {
            return .red
        }

        return .secondary
    }

    private var diagnosticDetailText: String {
        let name = diagnosticUPSName
        guard store.selectedUPS != nil else {
            return name
        }

        guard let milliseconds = store.lastRefreshDurationMilliseconds else {
            return name
        }

        return "\(name) · \(milliseconds) ms"
    }

    private var diagnosticUPSName: String {
        if let selectedUPS = store.selectedUPS {
            if let configuredName = configuredUPSName(from: selectedUPS.sourceDescription) {
                return configuredName
            }

            return selectedUPS.name
        }

        if let configuredName = configuredUPSName(from: store.sourceDescription) {
            return configuredName
        }

        return "-"
    }

    private var connectionText: String {
        store.selectedUPS == nil ? "未连接" : "已连接"
    }

    private var connectionColor: Color {
        store.selectedUPS == nil ? .secondary : .green
    }

    private func formattedSourceLine(fallbackName: String, source: String?) -> String {
        guard let source,
              let separator = source.lastIndex(of: "/"),
              separator < source.index(before: source.endIndex) else {
            return fallbackName
        }

        let hostPort = String(source[..<separator])
        let upsName = String(source[source.index(after: separator)...])
        return "\(upsName) · \(hostPort)"
    }

    private func configuredUPSName(from source: String?) -> String? {
        guard let source else {
            return nil
        }

        guard let separator = source.lastIndex(of: "/"),
              separator < source.index(before: source.endIndex) else {
            return nil
        }

        return String(source[source.index(after: separator)...])
    }
}

private struct TopStatusCapsule: View {
    let title: String
    let connectionText: String
    let connectionColor: Color

    var body: some View {
        HStack(spacing: 16) {
            Text(title)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Spacer()

            HStack(spacing: 8) {
                Circle()
                    .fill(connectionColor)
                    .frame(width: 10, height: 10)

                Text(connectionText)
                    .font(.system(size: 17, weight: .bold))
                    .lineLimit(1)
            }
            .foregroundStyle(.white.opacity(0.78))
        }
        .padding(.horizontal, 22)
        .frame(height: 56)
        .background(Color(red: 0.10, green: 0.14, blue: 0.20), in: Capsule())
    }
}

private struct BatterySummaryCard: View {
    let percentText: String
    let chargeFraction: Double
    let statusColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("电池电量")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(percentText)
                .font(.system(size: 52, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            BatteryProgressBar(value: chargeFraction, color: statusColor)
                .frame(height: 8)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 158, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.92), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct PowerStatusCard: View {
    let statusText: String
    let sourceText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("供电状态")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(statusText)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
            }

            Spacer(minLength: 0)

            Text(sourceText)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 158, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.92), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct BatteryProgressBar: View {
    let value: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let clamped = min(max(value, 0), 1)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.16))

                Capsule()
                    .fill(color)
                    .frame(width: max(proxy.size.width * clamped, clamped > 0 ? 8 : 0))
            }
        }
    }
}

private struct MetricsCard: View {
    let runtime: String
    let voltage: String
    let load: String

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                MetricColumn(title: "剩余时间", value: runtime)
                MetricColumn(title: "输入电压", value: voltage)
                MetricColumn(title: "负载", value: load)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.92), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct MetricColumn: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .multilineTextAlignment(.center)

            Text(value)
                .font(.system(size: 22, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct ShutdownOverviewSection: View {
    let shutdownState: String
    let ruleBrief: String

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            InfoColumn(title: "自动关机", value: shutdownState)
            InfoColumn(title: "规则", value: ruleBrief)
        }
        .padding(.horizontal, 8)
    }
}

private struct ShutdownConditionSummary: View {
    let graceText: String
    let lowBatteryText: String
    let cancelText: String

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            InfoColumn(title: "断电后", value: graceText)
            InfoColumn(title: "低电量", value: lowBatteryText)
            InfoColumn(title: "手动取消", value: cancelText)
        }
        .padding(.horizontal, 8)
    }
}

private struct InfoColumn: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .center, spacing: 6) {
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .multilineTextAlignment(.center)

            Text(value)
                .font(.system(size: 23, weight: .bold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.55)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct DiagnosticStatusView: View {
    let title: String
    let status: String
    let detail: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(status)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(detail)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .frame(minWidth: 150, alignment: .leading)
    }
}

private struct ToolIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold))
            .frame(width: 34, height: 34)
            .background(Color(nsColor: .controlBackgroundColor), in: Circle())
            .foregroundStyle(.secondary)
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.snappy(duration: 0.12), value: configuration.isPressed)
    }
}
