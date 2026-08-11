import AppKit
import SwiftUI
import UPSPowerMonitorCore

struct MonitorPopoverView: View {
    @ObservedObject var store: UPSMonitorStore
    @Environment(\.dismiss) private var dismiss
    private let closeAction: (() -> Void)?
    private let settingsAction: (() -> Void)?

    init(
        store: UPSMonitorStore,
        closeAction: (() -> Void)? = nil,
        settingsAction: (() -> Void)? = nil
    ) {
        self.store = store
        self.closeAction = closeAction
        self.settingsAction = settingsAction
    }

    var body: some View {
        VStack(spacing: 14) {
            TopStatusCapsule(
                title: deviceTitle,
                connectionText: connectionText,
                connectionColor: connectionColor
            )

            VStack(spacing: 18) {
                ChargeStatusCard(
                    chargeText: chargeText,
                    chargeFraction: chargeFraction,
                    statusColor: statusColor,
                    shutdownStateTitle: store.shutdownStateTitle
                )

                Divider()
                    .opacity(0.45)

                MetricsCard(
                    runtime: store.selectedUPS?.runtimeDescription ?? "-",
                    voltage: store.selectedUPS?.voltageDescription ?? "-",
                    load: store.selectedUPS?.loadDescription ?? "-",
                    ruleSummary: footerSummary
                )

                Divider()
                    .opacity(0.35)

                footer
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 20)
        }
        .padding(14)
        .frame(width: 430)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.88), in: popoverShape)
        .clipShape(popoverShape)
        .background {
            PopoverWindowShapeConfigurator(cornerRadius: AppCornerRadius.panel)
                .frame(width: 0, height: 0)
        }
    }

    private var footer: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("刷新 \(store.lastRefreshDescription)")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

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

    private var chargeText: String {
        guard let chargePercent = store.selectedUPS?.chargePercent else {
            return "UPS --"
        }

        return "UPS \(chargePercent)%"
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

    private var footerSummary: String {
        if let message = store.errorMessage, store.selectedUPS == nil {
            return message
        }

        if store.shutdownDecision.action == .wait || store.shutdownDecision.action == .executeShutdown {
            return store.shutdownStatusDescription
        }

        return store.shutdownRuleSummary
    }

    private var connectionText: String {
        store.selectedUPS == nil ? "未连接" : "已连接"
    }

    private var connectionColor: Color {
        store.selectedUPS == nil ? .secondary : .green
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

private struct ChargeStatusCard: View {
    let chargeText: String
    let chargeFraction: Double
    let statusColor: Color
    let shutdownStateTitle: String

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 14) {
                Text(percentText)
                    .font(.system(size: 58, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                BatteryProgressBar(value: chargeFraction, color: statusColor)
                    .frame(width: 210, height: 9)
            }

            Spacer(minLength: 4)

            VStack(alignment: .leading, spacing: 4) {
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 4) {
                    Text("自动关机")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.secondary)

                    Text(shutdownStateTitle)
                        .font(.system(size: 25, weight: .bold))
                        .foregroundStyle(.primary)
                }

                Spacer(minLength: 0)
            }
            .frame(width: 128, alignment: .leading)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
    }

    private var percentText: String {
        chargeText.replacingOccurrences(of: "UPS ", with: "")
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
    let ruleSummary: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 0) {
                MetricColumn(title: "剩余时间", value: runtime)
                MetricColumn(title: "输入电压", value: voltage)
                MetricColumn(title: "负载", value: load)
            }

            Divider()

            Text(ruleSummary)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 18)
    }
}

private struct MetricColumn: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(value)
                .font(.system(size: 22, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ToolIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold))
            .frame(width: 34, height: 34)
            .background(Color(nsColor: .controlBackgroundColor), in: Circle())
            .foregroundStyle(configuration.role == .destructive ? .red : .secondary)
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.snappy(duration: 0.12), value: configuration.isPressed)
    }
}
